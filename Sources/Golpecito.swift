import CoreMotion
import Foundation

/// Detecta un golpecito en la trasera o el lateral del móvil.
///
/// **Detecta el tirón, no la fuerza.** La primera versión miraba cuánta
/// aceleración había, y eso obliga a dar un golpe fuerte: sujetando el móvil
/// con una mano, la propia mano amortigua el golpe y el valor no llega. Además,
/// bajar el umbral para compensar hacía que cualquier movimiento del brazo
/// contase como clic.
///
/// Lo que distingue un golpecito de mover el móvil no es la magnitud, es la
/// **brusquedad**: un golpe cambia la aceleración de golpe entre dos muestras
/// consecutivas (10 ms), mientras que mover la mano, por rápido que sea, es un
/// cambio suave. Midiendo esa diferencia entre muestras se puede detectar un
/// toque flojito sin que los movimientos normales disparen nada.
final class Golpecito {

    private let motion = CMMotionManager()
    private let cola = OperationQueue()

    /// Se llama en el hilo principal cuando hay un golpe válido.
    var alGolpear: (() -> Void)?
    /// Pico de brusquedad medido, para poder calibrar mirando la pantalla.
    var alMedir: ((Double) -> Void)?

    private var ultimoGolpe: CFAbsoluteTime = 0
    private var anterior: Double = 0
    private var pico: Double = 0
    private var ultimoAviso: CFAbsoluteTime = 0

    /// Tras un golpe se ignora el rebote.
    private let descanso: Double = 0.22

    var disponible: Bool { motion.isDeviceMotionAvailable }

    init() {
        cola.qualityOfService = .userInteractive
        cola.maxConcurrentOperationCount = 1
    }

    func arrancar() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 100.0
        anterior = 0

        motion.startDeviceMotionUpdates(to: cola) { [weak self] dm, _ in
            guard let self, let dm else { return }
            let a = dm.userAcceleration                   // ya viene sin gravedad
            let fuerza = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
            let ahora = CFAbsoluteTimeGetCurrent()

            // Brusquedad: cuánto ha cambiado la aceleración desde la muestra
            // anterior. Esto es lo que separa un golpe de un movimiento.
            let tiron = abs(fuerza - self.anterior)
            self.anterior = fuerza

            if tiron >= Ajustes.compartidos.umbralGolpe,
               ahora - self.ultimoGolpe > self.descanso {
                self.ultimoGolpe = ahora
                if Ajustes.compartidos.golpecito {
                    DispatchQueue.main.async { self.alGolpear?() }
                }
            }

            // El pico dura 10-20 ms y se te escaparía mirando el valor
            // instantáneo. Se avisa 10 veces por segundo, no 100: refrescar una
            // etiqueta a 100 Hz es tirar batería para nada.
            self.pico = max(self.pico, tiron)
            if ahora - self.ultimoAviso > 0.1 {
                self.ultimoAviso = ahora
                let p = self.pico
                self.pico = 0
                DispatchQueue.main.async { self.alMedir?(p) }
            }
        }
    }

    func parar() {
        motion.stopDeviceMotionUpdates()
    }
}
