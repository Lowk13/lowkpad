import UIKit

/// El tacto.
///
/// Con la vista puesta en el monitor y no en el móvil, esto no es un adorno:
/// **es la única forma de saber que has hecho clic**. En el prototipo web no
/// existía (Safari en iOS no vibra) y por eso todo parecía roto.
final class Haptica {

    static let compartida = Haptica()
    private init() {}

    private let clicIzq = UIImpactFeedbackGenerator(style: .rigid)
    private let clicDer = UIImpactFeedbackGenerator(style: .heavy)
    private let suave = UIImpactFeedbackGenerator(style: .soft)

    /// Mantener los generadores "calientes" quita unos milisegundos de retardo
    /// en el primer golpe.
    func preparar() {
        guard Ajustes.compartidos.haptico else { return }
        clicIzq.prepare(); clicDer.prepare(); suave.prepare()
    }

    func clic(derecho: Bool = false) {
        guard Ajustes.compartidos.haptico else { return }
        if derecho { clicDer.impactOccurred() } else { clicIzq.impactOccurred() }
        preparar()
    }

    func toque() {
        guard Ajustes.compartidos.haptico else { return }
        suave.impactOccurred(intensity: 0.5)
        suave.prepare()
    }
}
