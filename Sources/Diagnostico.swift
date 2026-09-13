import Foundation
import Network

/// El host actual usa UDP; el TCP del prototipo no es un requisito.
enum Diagnostico {
    struct Resultado {
        var udp = false
        var detalle = ""
    }

    static func probar(ip: String, puertoUDP: UInt16,
                       completa: @escaping (Resultado) -> Void) {
        guard let puerto = NWEndpoint.Port(rawValue: puertoUDP) else { return }
        let cola = DispatchQueue(label: "lowkpad.diagnostico")
        let params = NWParameters.udp
        params.prohibitedInterfaceTypes = [.cellular]
        let c = NWConnection(host: NWEndpoint.Host(ip), port: puerto, using: params)
        var terminado = false
        func terminar(_ ok: Bool) {
            guard !terminado else { return }
            terminado = true
            c.cancel()
            let detalle = ok ? "El servidor contesta por UDP. La cifra del panel es ida y vuelta de red, no latencia total del cursor."
                : "Comprueba la IP, que LowkPad esté abierto en el PC, el permiso de Red local de LiveContainer, el Wi-Fi y el cortafuegos de Windows."
            DispatchQueue.main.async { completa(Resultado(udp: ok, detalle: detalle)) }
        }
        c.stateUpdateHandler = { [weak c] estado in
            guard let c, !terminado else { return }
            switch estado {
            case .ready:
                for intento in 0..<3 {
                    cola.asyncAfter(deadline: .now() + Double(intento) * 0.25) {
                        guard !terminado else { return }
                        c.send(content: Data("{\"t\":\"ping\",\"p\":1}".utf8), completion: .idempotent)
                    }
                }
                c.receiveMessage { datos, _, _, _ in
                    let obj = datos.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                    terminar(obj?["t"] as? String == "pong" && obj?["p"] as? Int == 1)
                }
            case .failed: terminar(false)
            default: break
            }
        }
        c.start(queue: cola)
        cola.asyncAfter(deadline: .now() + 3) { terminar(false) }
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
