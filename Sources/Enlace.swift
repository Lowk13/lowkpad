import Foundation
import Network

/// El enlace por UDP con el PC.
///
/// Regla de oro del protocolo: **cada paquete lleva el total acumulado, nunca
/// un incremento**. Si uno se pierde por el camino, el siguiente ya trae la
/// cuenta correcta y el hueco se cierra solo. Por eso no hace falta
/// retransmitir nada, que es justo lo que provoca los tirones de las apps que
/// van por TCP.
final class Enlace {

    static let compartido = Enlace()

    private var conexion: NWConnection?
    private let cola = DispatchQueue(label: "lowkpad.red", qos: .userInteractive)
    private let sesion = Int.random(in: 1...9_999_999)
    private let t0 = DispatchTime.now().uptimeNanoseconds

    // acumuladores
    private var accX = 0.0, accY = 0.0
    private var accSX = 0.0, accSY = 0.0
    private var botones = 0
    private var clicId = 0
    private var clicBoton = "l"
    private var seq = 0

    private var latido: DispatchSourceTimer?
    private var pendientes: [Int: UInt64] = [:]     // ping enviado -> instante

    /// Latencia de ida y vuelta, en milisegundos (mediana de las últimas medidas).
    private(set) var latencia: Double = 0
    private var muestras: [Double] = []

    /// El socket existe. **No significa que el PC reciba nada**: un socket UDP
    /// se declara listo en cuanto se crea, aunque iOS esté tirando los paquetes
    /// por falta de permiso de red local.
    private(set) var socketListo = false

    /// Instante del último "pong" recibido. Esta es la única prueba de verdad
    /// de que el PC nos está oyendo y contestando.
    private var ultimoPong: CFAbsoluteTime = 0

    /// De verdad conectado: el PC ha contestado hace poco.
    var listo: Bool { CFAbsoluteTimeGetCurrent() - ultimoPong < 2.0 }

    var alCambiar: ((Bool) -> Void)?

    private var ms: Int { Int((DispatchTime.now().uptimeNanoseconds &- t0) / 1_000_000) }

    // MARK: - conexión

    func conectar(ip: String, puerto: UInt16) {
        cola.async {
            self.conexion?.cancel()

            let params = NWParameters.udp
            // Marca el tráfico como "voz interactiva": el Wi-Fi lo mete en la cola
            // prioritaria (WMM AC_VO). En una red con tráfico esto vale más que
            // cualquier otra optimización.
            params.serviceClass = .interactiveVoice
            params.prohibitedInterfaceTypes = [.cellular]

            guard let p = NWEndpoint.Port(rawValue: puerto) else { return }
            let c = NWConnection(host: NWEndpoint.Host(ip), port: p, using: params)

            c.stateUpdateHandler = { [weak self] estado in
                guard let self else { return }
                let ok: Bool
                switch estado {
                case .ready: ok = true
                case .failed, .cancelled: ok = false
                default: return
                }
                self.socketListo = ok
                DispatchQueue.main.async { self.alCambiar?(ok) }
            }

            self.conexion = c
            c.start(queue: self.cola)
            self.recibir()
            self.arrancarLatido()
            self.mandarAjustes()
        }
    }

    private func recibir() {
        conexion?.receiveMessage { [weak self] datos, _, _, _ in
            guard let self else { return }
            if let datos, let texto = String(data: datos, encoding: .utf8),
               texto.contains("\"pong\"") {
                // el eco trae de vuelta la marca de tiempo que mandamos
                if let r = texto.range(of: "\"p\":"),
                   let valor = Int(texto[r.upperBound...].prefix(while: { $0.isNumber })) {
                    let ida = Double(self.ms - valor)
                    self.ultimoPong = CFAbsoluteTimeGetCurrent()
                    self.muestras.append(ida)
                    if self.muestras.count > 15 { self.muestras.removeFirst() }
                    let ordenadas = self.muestras.sorted()
                    self.latencia = ordenadas[ordenadas.count / 2]
                }
            }
            if self.conexion != nil { self.recibir() }
        }
    }

    /// Un latido constante evita que la radio Wi-Fi del iPhone entre en ahorro
    /// de energía. Sin esto, el primer movimiento tras una pausa puede tardar
    /// más de 100 ms en llegar.
    private func arrancarLatido() {
        latido?.cancel()
        let t = DispatchSource.makeTimerSource(queue: cola)
        t.schedule(deadline: .now() + 0.1, repeating: 0.1)
        t.setEventHandler { [weak self] in self?.enviar(conPing: true) }
        t.resume()
        latido = t
    }

    // MARK: - lo que manda la interfaz

    func mover(dx: Double, dy: Double) {
        cola.async { self.accX += dx; self.accY += dy; self.enviar() }
    }

    func scroll(dx: Double, dy: Double) {
        cola.async { self.accSX += dx; self.accSY += dy; self.enviar() }
    }

    func boton(_ cual: String, pulsado: Bool) {
        let bit = cual == "l" ? 1 : (cual == "r" ? 2 : 4)
        cola.async {
            let antes = self.botones
            self.botones = pulsado ? (antes | bit) : (antes & ~bit)
            if self.botones != antes { self.enviar(repetir: 3) }
        }
    }

    func clic(_ cual: String) {
        cola.async {
            self.clicId += 1
            self.clicBoton = cual
            // Un clic puede ser lo último que ocurra antes de levantar el dedo:
            // si ese único paquete se pierde, el clic se pierde. Se repite tres
            // veces; el PC los descarta por identificador, así que no hay riesgo
            // de que salgan clics de más.
            self.enviar(repetir: 3)
        }
    }

    func mandarAjustes() {
        let a = Ajustes.compartidos
        let json = """
        {"t":"cfg","cfg":{"gain":\(a.ganancia),"accel":\(a.aceleracion),\
        "accel_thr":\(a.umbralAcel),"accel_slope":\(a.pendienteAcel),\
        "scroll_gain":\(a.gananciaScroll),"scroll_natural":\(a.scrollNatural)}}
        """
        cola.async { self.mandarCrudo(json) }
    }

    // MARK: - envío

    private func enviar(conPing: Bool = false, repetir: Int = 1) {
        seq += 1
        let t = ms
        var json = "{\"t\":\"m\",\"ses\":\(sesion),\"s\":\(seq),\"tm\":\(t)"
        json += ",\"x\":\(redondo(accX)),\"y\":\(redondo(accY))"
        json += ",\"sx\":\(redondo(accSX)),\"sy\":\(redondo(accSY))"
        json += ",\"b\":\(botones),\"ci\":\(clicId),\"cb\":\"\(clicBoton)\""
        if conPing { json += ",\"p\":\(t)" }
        json += "}"
        mandarCrudo(json)

        if repetir > 1 {
            for i in 1..<repetir {
                cola.asyncAfter(deadline: .now() + .milliseconds(8 * i)) {
                    self.seq += 1
                    var repe = "{\"t\":\"m\",\"ses\":\(self.sesion),\"s\":\(self.seq),\"tm\":\(self.ms)"
                    repe += ",\"x\":\(self.redondo(self.accX)),\"y\":\(self.redondo(self.accY))"
                    repe += ",\"sx\":\(self.redondo(self.accSX)),\"sy\":\(self.redondo(self.accSY))"
                    repe += ",\"b\":\(self.botones),\"ci\":\(self.clicId),\"cb\":\"\(self.clicBoton)\"}"
                    self.mandarCrudo(repe)
                }
            }
        }
    }

    private func redondo(_ v: Double) -> String {
        String(format: "%.2f", v)
    }

    private func mandarCrudo(_ texto: String) {
        guard let c = conexion, let datos = texto.data(using: .utf8) else { return }
        c.send(content: datos, completion: .idempotent)
    }

    /// Al irse a segundo plano no puede quedarse ningún botón pulsado en el PC.
    func soltarTodo() {
        cola.async {
            self.botones = 0
            self.enviar(repetir: 3)
        }
    }
}
