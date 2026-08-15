import AVFoundation
import MediaPlayer
import UIKit

/// Convierte los botones de volumen en clic izquierdo y derecho.
///
/// Sujetando el móvil con la derecha, el índice cae solo sobre ellos mientras
/// el pulgar sigue apuntando: clic físico de verdad, sin gastar pantalla.
///
/// No hay API oficial para esto. Lo que se hace es vigilar el volumen del
/// sistema y devolverlo a la mitad en cuanto cambia; el `MPVolumeView` oculto
/// que metemos en la jerarquía es lo que impide que salga el indicador de
/// volumen en pantalla.
///
/// Limitaciones conocidas y aceptadas:
///  - añade unos 30-60 ms frente a un toque en pantalla,
///  - deja el volumen del móvil anclado a la mitad mientras la app está abierta,
///  - solo funciona con la app en primer plano.
final class BotonesVolumen {

    /// `true` = botón de subir, `false` = botón de bajar.
    var alPulsar: ((Bool) -> Void)?

    private let sesion = AVAudioSession.sharedInstance()
    private var observador: NSKeyValueObservation?
    private let ancla: Float = 0.5
    private var restaurando = false
    private let vistaOculta = MPVolumeView(frame: CGRect(x: -3000, y: -3000, width: 1, height: 1))
    private var activo = false

    func arrancar(en contenedor: UIView) {
        guard !activo else { return }
        activo = true

        vistaOculta.isHidden = false          // oculta no suprime el indicador
        vistaOculta.alpha = 0.001
        contenedor.addSubview(vistaOculta)

        // .ambient + mixWithOthers: no interrumpe la música que estés oyendo.
        try? sesion.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? sesion.setActive(true)
        fijar(ancla)

        observador = sesion.observe(\.outputVolume, options: [.new]) { [weak self] _, cambio in
            guard let self, let nuevo = cambio.newValue else { return }
            // El propio hecho de devolver el volumen a su sitio dispara otra
            // notificación. Sin esta guarda entraríamos en bucle.
            if self.restaurando { return }
            guard Ajustes.compartidos.volumen else { return }

            let subida = nuevo > self.ancla
            let invertir = Ajustes.compartidos.volumenInvertido
            DispatchQueue.main.async { self.alPulsar?(invertir ? !subida : subida) }
            self.fijar(self.ancla)
        }
    }

    func parar() {
        observador?.invalidate()
        observador = nil
        vistaOculta.removeFromSuperview()
        try? sesion.setActive(false, options: [.notifyOthersOnDeactivation])
        activo = false
    }

    private func fijar(_ valor: Float) {
        restaurando = true
        DispatchQueue.main.async {
            if let deslizador = self.vistaOculta.subviews.compactMap({ $0 as? UISlider }).first {
                deslizador.value = valor
            }
            // margen para que la notificación provocada por nosotros ya haya pasado
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                self.restaurando = false
            }
        }
    }
}
