import Foundation
import Network

/// Canal persistente, ordenado y con confirmaciones. Nunca reenvía una orden dudosa.
final class ControlPC {
    static let compartido = ControlPC()
    typealias Respuesta = (Result<[String: Any], Error>) -> Void
    private var tareas: [([String: Any], Respuesta)] = []
    private var activa: Respuesta?
    private var conexion: NWConnection?
    private var preparada = false
    private var destino = ""
    private var recibido = Data()
    private var numero = 0

    struct Fallo: LocalizedError {
        let mensaje: String
        var errorDescription: String? { mensaje }
    }
    func enviar(_ orden: [String: Any], completa: @escaping Respuesta) {
        dispatchPrecondition(condition: .onQueue(.main))
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            NotificationCenter.default.post(name: .init("LowkPadOrdenPrueba"), object: nil, userInfo: orden)
            completa(.success(["version": "0.4.0"]))
            return
        }
        #endif
        let a = Ajustes.compartidos
        guard !a.clavePaneles.isEmpty else {
            completa(.failure(Fallo(mensaje: "Pega la clave de enlace del PC en Ajustes para activar los paneles."))); return
        }
        let nuevoDestino = a.ip + ":" + a.clavePaneles
        if conexion != nil && destino != nuevoDestino {
            fallar("Ha cambiado la conexión. Las órdenes pendientes se han cancelado.")
        }
        guard tareas.count < 64 else {
            fallar("La conexión no sigue el ritmo. Comprueba el texto del PC antes de continuar.")
            completa(.failure(Fallo(mensaje: "Escritura pausada por acumulación de teclas."))); return
        }
        tareas.append((orden, completa))
        if conexion == nil {
            destino = nuevoDestino
            conectar()
        }
        siguiente()
    }
    private func conectar() {
        let params = NWParameters.tcp
        params.prohibitedInterfaceTypes = [.cellular]
        (params.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options)?.noDelay = true
        let c = NWConnection(host: NWEndpoint.Host(Ajustes.compartidos.ip), port: 8787, using: params)
        conexion = c
        c.stateUpdateHandler = { [weak self, weak c] estado in
            guard let self, let c, self.conexion === c else { return }
            switch estado {
            case .ready:
                self.preparada = true
                self.recibir(c)
                self.siguiente()
            case .failed:
                self.fallar("No se puede conectar al PC. Comprueba IP, servidor y Wi-Fi.")
            default: break
            }
        }
        c.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self, weak c] in
            guard let self, let c, self.conexion === c, !self.preparada else { return }
            self.fallar("No se pudo abrir la conexión con el PC.")
        }
    }
    private func siguiente() {
        guard preparada, activa == nil, !tareas.isEmpty, let c = conexion else { return }
        var (orden, completa) = tareas.removeFirst()
        orden["token"] = Ajustes.compartidos.clavePaneles.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var data = try? JSONSerialization.data(withJSONObject: orden) else {
            completa(.failure(Fallo(mensaje: "No se pudo preparar la orden."))); siguiente(); return
        }
        activa = completa
        numero += 1
        let id = numero
        data.append(10)
        c.send(content: data, completion: .contentProcessed { [weak self, weak c] error in
            guard let self, let c, self.conexion === c, error != nil else { return }
            self.fallar("Conexión interrumpida; comprueba el PC antes de repetir la última tecla.")
        })
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self, weak c] in
            guard let self, let c, self.conexion === c, self.numero == id, self.activa != nil else { return }
            self.fallar("El PC no confirmó la última tecla. Comprueba el texto antes de continuar.")
        }
    }
    private func recibir(_ c: NWConnection) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, fin, error in
            guard let self, self.conexion === c else { return }
            if let data { self.recibido.append(data) }
            guard self.recibido.count <= 400000 else { self.fallar("Respuesta demasiado grande."); return }
            while let limite = self.recibido.firstIndex(of: 10) {
                let linea = self.recibido.prefix(upTo: limite)
                guard let obj = try? JSONSerialization.jsonObject(with: linea) as? [String: Any],
                      let completa = self.activa else { self.fallar("Respuesta inesperada del PC."); return }
                self.recibido.removeSubrange(...limite)
                if obj["ok"] as? Bool == true {
                    self.activa = nil
                    completa(.success(obj["data"] as? [String: Any] ?? [:]))
                    self.siguiente()
                } else {
                    self.fallar(obj["error"] as? String ?? "El PC rechazó la orden."); return
                }
            }
            if fin || error != nil {
                self.fallar("Conexión cerrada. Comprueba el PC antes de repetir la última tecla.")
            } else { self.recibir(c) }
        }
    }
    func cancelarPendientes() { fallar("Escritura pausada al salir de la app.") }
    private func fallar(_ mensaje: String) {
        conexion?.stateUpdateHandler = nil
        conexion?.cancel()
        conexion = nil
        preparada = false
        recibido.removeAll()
        let pendientes = tareas
        let enCurso = activa
        tareas.removeAll()
        activa = nil
        let error = Fallo(mensaje: mensaje)
        enCurso?(.failure(error))
        for (_, completa) in pendientes { completa(.failure(error)) }
    }
}
