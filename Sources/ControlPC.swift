import Foundation
import Network

/// Texto/órdenes van confirmados y en orden; el ratón conserva su canal UDP.
final class ControlPC {
    static let compartido = ControlPC()
    typealias Respuesta = (Result<[String: Any], Error>) -> Void
    private var tareas: [([String: Any], Respuesta)] = []
    private var ocupado = false

    struct Fallo: LocalizedError {
        let mensaje: String
        var errorDescription: String? { mensaje }
    }
    func enviar(_ orden: [String: Any], completa: @escaping Respuesta) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !Ajustes.compartidos.clavePaneles.isEmpty else {
            completa(.failure(Fallo(mensaje: "Pega la clave de enlace del PC en Ajustes para activar los paneles.")))
            return
        }
        guard tareas.count < 32 else {
            completa(.failure(Fallo(mensaje: "Espera a que terminen las órdenes pendientes."))); return
        }
        tareas.append((orden, completa))
        siguiente()
    }
    private func siguiente() {
        guard !ocupado, !tareas.isEmpty else { return }
        ocupado = true
        var (orden, completa) = tareas.removeFirst()
        let a = Ajustes.compartidos
        orden["token"] = a.clavePaneles.trimmingCharacters(in: .whitespacesAndNewlines)
        let params = NWParameters.tcp
        params.prohibitedInterfaceTypes = [.cellular]
        (params.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options)?.noDelay = true
        let c = NWConnection(host: NWEndpoint.Host(a.ip), port: 8787, using: params)
        var terminado = false
        var recibido = Data()
        func terminar(_ result: Result<[String: Any], Error>) {
            guard !terminado else { return }
            terminado = true
            c.stateUpdateHandler = nil
            c.cancel()
            self.ocupado = false
            completa(result)
            // Tras una respuesta perdida, no reproducir una cola de teclas a ciegas.
            if case .failure = result {
                let pendientes = self.tareas
                self.tareas.removeAll()
                for (_, respuesta) in pendientes {
                    respuesta(.failure(Fallo(mensaje: "Orden cancelada por un fallo de conexión.")))
                }
            }
            self.siguiente()
        }
        func recibir() {
            c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, fin, error in
                guard !terminado else { return }
                if let data { recibido.append(data) }
                if recibido.count > 400000 {
                    terminar(.failure(Fallo(mensaje: "Respuesta demasiado grande."))); return
                }
                if let limite = recibido.firstIndex(of: 10) {
                    guard let obj = try? JSONSerialization.jsonObject(with: recibido.prefix(upTo: limite)) as? [String: Any] else {
                        terminar(.failure(Fallo(mensaje: "Respuesta no válida del servidor."))); return
                    }
                    if obj["ok"] as? Bool == true {
                        terminar(.success(obj["data"] as? [String: Any] ?? [:]))
                    } else {
                        terminar(.failure(Fallo(mensaje: obj["error"] as? String ?? "El PC rechazó la orden.")))
                    }
                } else if fin || error != nil {
                    terminar(.failure(Fallo(mensaje: "Conexión interrumpida; la orden podría haberse aplicado. Comprueba el PC antes de repetir.")))
                } else { recibir() }
            }
        }
        c.stateUpdateHandler = { estado in
            switch estado {
            case .ready:
                guard var data = try? JSONSerialization.data(withJSONObject: orden) else {
                    terminar(.failure(Fallo(mensaje: "No se pudo preparar la orden."))); return
                }
                data.append(10)
                c.send(content: data, completion: .contentProcessed { error in
                    if error != nil { terminar(.failure(Fallo(mensaje: "No se pudo enviar; comprueba el PC antes de repetir."))) }
                })
                recibir()
            case .failed:
                terminar(.failure(Fallo(mensaje: "No se puede conectar al PC. Comprueba IP, servidor y Wi-Fi.")))
            default: break
            }
        }
        c.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            terminar(.failure(Fallo(mensaje: "El PC no confirmó la orden; compruébalo antes de repetir.")))
        }
    }
}
