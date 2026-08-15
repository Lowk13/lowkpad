import Foundation
import Network

/// Averigua POR QUÉ no llega nada al PC.
///
/// Con UDP no hay forma de saberlo mirando el socket: no hay saludo ni acuse de
/// recibo, así que un socket "listo" puede estar tirando todos los paquetes.
/// Aquí se prueban las dos cosas por separado:
///
///  - **TCP al 8787** (el servidor web del prototipo). Si esto conecta, la red y
///    el permiso de red local están bien, y el problema es solo del UDP
///    (cortafuegos del PC, o puerto equivocado).
///  - **UDP al 8788** con un ping propio y espera de respuesta.
///
/// Si fallan los dos, casi siempre es el **permiso de red local** de iOS.
enum Diagnostico {

    struct Resultado {
        var tcp = false
        var udp = false
        var detalle = ""
    }

    static func probar(ip: String, puertoUDP: UInt16,
                       completa: @escaping (Resultado) -> Void) {
        var r = Resultado()
        let grupo = DispatchGroup()

        grupo.enter()
        probarTCP(ip: ip, puerto: 8787) { ok in r.tcp = ok; grupo.leave() }

        grupo.enter()
        probarUDP(ip: ip, puerto: puertoUDP) { ok in r.udp = ok; grupo.leave() }

        grupo.notify(queue: .main) {
            switch (r.tcp, r.udp) {
            case (true, true):
                r.detalle = "Todo bien: el PC contesta por los dos caminos."
            case (true, false):
                r.detalle = """
                El PC se deja ver (TCP 8787 responde) pero el UDP 8788 no llega.
                Es el cortafuegos de Windows: falta la regla para UDP 8788.
                """
            case (false, true):
                r.detalle = "Raro: llega el UDP pero no el TCP. ¿Servidor a medias?"
            case (false, false):
                r.detalle = """
                No se llega al PC por ningún puerto.
                1) Comprueba que la IP sea la correcta.
                2) Mira en Ajustes de iOS → Privacidad y seguridad → Red local
                   y activa el interruptor de LiveContainer (o de LowkPad).
                3) Comprueba que el móvil esté en el mismo Wi-Fi y no en 5G.
                """
            }
            completa(r)
        }
    }

    private static func probarTCP(ip: String, puerto: UInt16,
                                  completa: @escaping (Bool) -> Void) {
        guard let p = NWEndpoint.Port(rawValue: puerto) else { return completa(false) }
        let params = NWParameters.tcp
        params.prohibitedInterfaceTypes = [.cellular]
        let c = NWConnection(host: NWEndpoint.Host(ip), port: p, using: params)
        var respondido = false

        c.stateUpdateHandler = { estado in
            guard !respondido else { return }
            switch estado {
            case .ready:
                respondido = true; c.cancel(); completa(true)
            case .failed, .cancelled:
                respondido = true; c.cancel(); completa(false)
            default: break
            }
        }
        c.start(queue: .global())
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            guard !respondido else { return }
            respondido = true; c.cancel(); completa(false)
        }
    }

    private static func probarUDP(ip: String, puerto: UInt16,
                                  completa: @escaping (Bool) -> Void) {
        guard let p = NWEndpoint.Port(rawValue: puerto) else { return completa(false) }
        let params = NWParameters.udp
        params.prohibitedInterfaceTypes = [.cellular]
        let c = NWConnection(host: NWEndpoint.Host(ip), port: p, using: params)
        var respondido = false

        func terminar(_ ok: Bool) {
            guard !respondido else { return }
            respondido = true
            c.cancel()
            completa(ok)
        }

        c.stateUpdateHandler = { estado in
            if case .ready = estado {
                let sonda = "{\"t\":\"m\",\"ses\":999999,\"s\":1,\"tm\":0,\"x\":0,\"y\":0," +
                            "\"sx\":0,\"sy\":0,\"b\":0,\"ci\":0,\"cb\":\"l\",\"p\":1}"
                c.send(content: sonda.data(using: .utf8), completion: .idempotent)
                c.receiveMessage { datos, _, _, _ in
                    let ok = datos.flatMap { String(data: $0, encoding: .utf8) }?
                        .contains("pong") ?? false
                    terminar(ok)
                }
            }
            if case .failed = estado { terminar(false) }
        }
        c.start(queue: .global())
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { terminar(false) }
    }
}

/// Fuerza que iOS enseñe el aviso de "¿Permitir buscar dispositivos en tu red
/// local?".
///
/// El aviso lo dispara de forma fiable **buscar servicios Bonjour**; mandar un
/// paquete UDP suelto a veces no lo saca, y entonces iOS se limita a tirar los
/// paquetes sin decir nada. Este buscador no espera encontrar nada: existe solo
/// para provocar la pregunta.
///
/// Requiere que `NSBonjourServices` del Info.plist incluya el tipo de servicio.
final class PermisoRedLocal {

    private var buscador: NWBrowser?

    func pedir() {
        guard buscador == nil else { return }
        let params = NWParameters()
        params.includePeerToPeer = true
        let b = NWBrowser(for: .bonjour(type: "_lowkpad._udp", domain: nil), using: params)
        b.stateUpdateHandler = { _ in }
        b.browseResultsChangedHandler = { _, _ in }
        b.start(queue: .main)
        buscador = b

        // En cuanto ha salido el aviso ya no hace falta seguir buscando.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            self?.buscador?.cancel()
            self?.buscador = nil
        }
    }
}
