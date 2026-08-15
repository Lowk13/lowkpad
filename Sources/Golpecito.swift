import CoreMotion
import Foundation

/// Detecta un golpecito en la trasera o el lateral del móvil.
///
/// Es la respuesta al problema de siempre: con el móvil en una mano, el pulgar
/// apunta y no se puede levantar. El índice, que está detrás sujetando, da un
/// golpe seco y eso es el clic. Cero espacio en pantalla y no interrumpe el
/// movimiento.
///
/// El truco para no llenarlo de falsos positivos es exigir **calma antes del
/// golpe**: si el móvil ya venía moviéndose (lo estás recolocando, andando,
/// dejándolo en la mesa), no cuenta.
final class Golpecito {

    private let motion = CMMotionManager()
    private let cola = OperationQueue()

    /// Se llama en el hilo principal cuando hay un golpe válido.
    var alGolpear: (() -> Void)?
    /// Valor instantáneo, para poder calibrar el umbral mirando la pantalla.
    var alMedir: ((Double) -> Void)?

    private var ultimoGolpe: CFAbsoluteTime = 0
    private var ultimoMovimiento: CFAbsoluteTime = 0
    private var pico: Double = 0
    private var ultimoAviso: CFAbsoluteTime = 0

    /// Por debajo de esto se considera que el móvil está quieto.
    private let calma: Double = 0.25
    /// Hay que venir quieto al menos este tiempo para que un pico sea un golpe.
    private let calmaMinima: Double = 0.10
    /// Tras un golpe, se ignora el rebote.
    private let descanso: Double = 0.25

    var disponible: Bool { motion.isDeviceMotionAvailable }

    init() {
        cola.qualityOfService = .userInteractive
        cola.maxConcurrentOperationCount = 1
    }

    func arrancar() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 100.0
        ultimoMovimiento = CFAbsoluteTimeGetCurrent()

        motion.startDeviceMotionUpdates(to: cola) { [weak self] dm, _ in
            guard let self, let dm else { return }
            let a = dm.userAcceleration               // ya viene sin gravedad
            let fuerza = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
            let ahora = CFAbsoluteTimeGetCurrent()

            // Un golpe válido es un pico brusco DESPUÉS de un rato de calma.
            // Si el móvil ya venía moviéndose (lo estás recolocando, andando,
            // dejándolo en la mesa), no cuenta.
            if fuerza >= Ajustes.compartidos.umbralGolpe,
               ahora - self.ultimoMovimiento > self.calmaMinima,
               ahora - self.ultimoGolpe > self.descanso {
                self.ultimoGolpe = ahora
                if Ajustes.compartidos.golpecito {
                    DispatchQueue.main.async { self.alGolpear?() }
                }
            }
            if fuerza >= self.calma { self.ultimoMovimiento = ahora }

            // Para calibrar el umbral hace falta ver el pico, no el valor
            // instantáneo (el pico dura 10-20 ms y se te escapa). Se avisa
            // 10 veces por segundo, no 100: actualizar una etiqueta a 100 Hz
            // es tirar batería para nada.
            self.pico = max(self.pico, fuerza)
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
