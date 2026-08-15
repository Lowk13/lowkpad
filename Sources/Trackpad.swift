import UIKit

protocol TrackpadDelegado: AnyObject {
    func trackpadMovio(dx: Double, dy: Double)
    func trackpadScroll(dx: Double, dy: Double)
    func trackpadBoton(_ cual: String, pulsado: Bool)
    func trackpadClic(_ cual: String)
    func trackpadNota(_ texto: String, derecho: Bool)
    func trackpadHuella(_ radio: Double, base: Double)
}

/// La superficie táctil.
///
/// Todo lo que aprendimos en el prototipo web está aplicado aquí:
///  - apoyar un segundo dedo NO entra en modo scroll (solo se entra si los
///    dedos se mueven de verdad). Ese fallo hacía que el gesto pareciera roto.
///  - el segundo dedo apoyado y quieto deja el botón pulsado, que es lo que
///    permite arrastrar sin levantar ningún dedo.
///  - los clics sueltos los ejecuta el PC con duración real; desde aquí solo
///    se avisa del evento.
final class Trackpad: UIView {

    weak var delegado: TrackpadDelegado?

    private struct Secundario {
        var inicio: CFAbsoluteTime
        var origen: CGPoint
        var movido = false
        var arrastre = false
        var tarea: DispatchWorkItem?
    }

    private var principal: UITouch?
    private var inicioPrincipal: CFAbsoluteTime = 0
    private var ultimoPunto: CGPoint = .zero
    private var ultimoInstante: CFAbsoluteTime = 0
    private var recorrido: Double = 0
    private var enFranja = false
    private var gemelo = false
    private var modoScroll = false
    private var apretando = false
    private var baseHuella: Double = 0
    private var muestrasHuella: [Double] = []

    private var secundarios: [ObjectIdentifier: Secundario] = [:]
    private var tareaLarga: DispatchWorkItem?

    private var ultimoTap: CFAbsoluteTime = 0
    private var ultimoTapPunto: CGPoint = .zero
    private var arrastrandoPorTap = false

    private let umbralMov: Double = 10
    private let msTap: Double = 0.26
    private let msSegundo: Double = 0.45
    private let msArrastre: Double = 0.26

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isUserInteractionEnabled = true
        backgroundColor = .clear
    }
    required init?(coder: NSCoder) { fatalError() }

    private var anchoFranja: CGFloat {
        Ajustes.compartidos.franjaScroll ? bounds.width * 0.14 : 0
    }

    // MARK: - dedos

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let a = Ajustes.compartidos
        let ahora = CFAbsoluteTimeGetCurrent()

        for t in touches {
            if principal == nil {
                principal = t
                inicioPrincipal = ahora
                ultimoPunto = t.location(in: self)
                ultimoInstante = ahora
                recorrido = 0
                gemelo = false
                apretando = false
                muestrasHuella.removeAll()
                baseHuella = 0
                enFranja = ultimoPunto.x > bounds.width - anchoFranja

                if enFranja { modoScroll = true }

                // tap y medio: tocar y, en el segundo toque, no levantar = arrastrar
                if a.tocarClic, ahora - ultimoTap < 0.32,
                   hypot(ultimoPunto.x - ultimoTapPunto.x, ultimoPunto.y - ultimoTapPunto.y) < 40 {
                    arrastrandoPorTap = true
                    delegado?.trackpadBoton("l", pulsado: true)
                    delegado?.trackpadNota("arrastrando (tap y medio)", derecho: false)
                }

                if a.mantenerDerecho {
                    let tarea = DispatchWorkItem { [weak self] in
                        guard let self, self.principal != nil, self.recorrido < self.umbralMov,
                              !self.arrastrandoPorTap, self.secundarios.isEmpty else { return }
                        self.delegado?.trackpadClic("r")
                        self.delegado?.trackpadNota("clic DERECHO · mantener", derecho: true)
                        self.recorrido = self.umbralMov + 1   // que no cuente además como toque
                    }
                    tareaLarga = tarea
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.62, execute: tarea)
                }
            } else {
                var s = Secundario(inicio: ahora, origen: t.location(in: self))
                tareaLarga?.cancel()

                if secundarios.isEmpty, recorrido < umbralMov, ahora - inicioPrincipal < 0.12 {
                    gemelo = true
                }

                // segundo dedo apoyado y quieto = botón pulsado mientras siga ahí
                if a.segundoDedo, !gemelo {
                    let id = ObjectIdentifier(t)
                    let tarea = DispatchWorkItem { [weak self] in
                        guard let self, var sec = self.secundarios[id],
                              !sec.movido, self.principal != nil else { return }
                        sec.arrastre = true
                        self.secundarios[id] = sec
                        self.modoScroll = false
                        self.delegado?.trackpadBoton("l", pulsado: true)
                        self.delegado?.trackpadNota("arrastrando (segundo dedo)", derecho: false)
                    }
                    s.tarea = tarea
                    DispatchQueue.main.asyncAfter(deadline: .now() + msArrastre, execute: tarea)
                }
                secundarios[ObjectIdentifier(t)] = s
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        let ahora = CFAbsoluteTimeGetCurrent()
        var dx = 0.0, dy = 0.0, huboPrincipal = false

        for t in touches {
            if t === principal {
                let p = t.location(in: self)
                dx += Double(p.x - ultimoPunto.x)
                dy += Double(p.y - ultimoPunto.y)
                ultimoPunto = p
                huboPrincipal = true
                medirHuella(t)
            } else if var s = secundarios[ObjectIdentifier(t)] {
                let p = t.location(in: self)
                if hypot(p.x - s.origen.x, p.y - s.origen.y) > CGFloat(umbralMov) {
                    s.movido = true
                    s.tarea?.cancel()
                    secundarios[ObjectIdentifier(t)] = s
                }
            }
        }

        guard huboPrincipal else { return }

        recorrido += (dx * dx + dy * dy).squareRoot()
        if recorrido > umbralMov { tareaLarga?.cancel() }

        // Solo se entra en scroll si hay dos dedos Y movimiento real, y ninguno
        // de ellos está haciendo de botón.
        if !modoScroll, !enFranja, !secundarios.isEmpty, recorrido > umbralMov {
            let alguienDeBoton = secundarios.values.contains { $0.arrastre }
            if !alguienDeBoton {
                modoScroll = true
                delegado?.trackpadNota("scroll con dos dedos", derecho: false)
            }
        }

        ultimoInstante = ahora
        if modoScroll {
            delegado?.trackpadScroll(dx: enFranja ? 0 : dx, dy: dy)
        } else {
            delegado?.trackpadMovio(dx: dx, dy: dy)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        terminar(touches)
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        terminar(touches)
    }

    private func terminar(_ touches: Set<UITouch>) {
        let a = Ajustes.compartidos
        let ahora = CFAbsoluteTimeGetCurrent()

        for t in touches {
            if t === principal {
                tareaLarga?.cancel()
                let dur = ahora - inicioPrincipal

                if arrastrandoPorTap {
                    arrastrandoPorTap = false
                    delegado?.trackpadBoton("l", pulsado: false)
                    delegado?.trackpadNota("fin de arrastre", derecho: false)
                } else if apretando {
                    apretando = false
                    delegado?.trackpadBoton("l", pulsado: false)
                } else if a.tocarClic, recorrido < umbralMov, !enFranja,
                          dur < msTap, !gemelo, secundarios.isEmpty {
                    delegado?.trackpadClic("l")
                    delegado?.trackpadNota("clic izquierdo · toque", derecho: false)
                    ultimoTap = ahora
                    ultimoTapPunto = ultimoPunto
                }

                principal = nil
                enFranja = false
                if secundarios.isEmpty { modoScroll = false }

            } else if let s = secundarios.removeValue(forKey: ObjectIdentifier(t)) {
                s.tarea?.cancel()
                let dur = ahora - s.inicio

                if s.arrastre {
                    delegado?.trackpadBoton("l", pulsado: false)
                    delegado?.trackpadNota("fin de arrastre", derecho: false)
                } else if !s.movido, dur < msSegundo {
                    if gemelo, a.dosDedosDerecho {
                        delegado?.trackpadClic("r")
                        delegado?.trackpadNota("clic DERECHO · dos dedos", derecho: true)
                    } else if principal != nil, a.segundoDedo {
                        delegado?.trackpadClic("l")
                        delegado?.trackpadNota("clic izquierdo · segundo dedo", derecho: false)
                    }
                }
                if secundarios.isEmpty {
                    gemelo = false
                    if principal == nil || !enFranja { modoScroll = false }
                }
            }
        }
    }

    // MARK: - el experimento de la presión

    /// El iPhone 13 no tiene sensor de fuerza, pero sí da el tamaño de la huella
    /// del dedo, que crece al apretar. En Safari este dato venía siempre fijo;
    /// aquí usamos `majorRadius`, que es otra fuente distinta. Puede funcionar
    /// o no: por eso se muestra en pantalla en crudo.
    private func medirHuella(_ t: UITouch) {
        let r = Double(t.majorRadius)
        delegado?.trackpadHuella(r, base: baseHuella)
        guard Ajustes.compartidos.presion, r > 0 else { return }

        muestrasHuella.append(r)
        if muestrasHuella.count <= 5 {
            baseHuella = muestrasHuella.reduce(0, +) / Double(muestrasHuella.count)
            return
        }
        let ratio = r / max(baseHuella, 0.001)
        let a = Ajustes.compartidos
        if !apretando, ratio >= a.presionAbajo {
            apretando = true
            delegado?.trackpadBoton("l", pulsado: true)
            delegado?.trackpadNota("clic por presión", derecho: false)
        } else if apretando, ratio <= a.presionArriba {
            apretando = false
            delegado?.trackpadBoton("l", pulsado: false)
        }
    }

    /// Al irse la app a segundo plano hay que soltarlo todo.
    func reiniciar() {
        tareaLarga?.cancel()
        secundarios.values.forEach { $0.tarea?.cancel() }
        secundarios.removeAll()
        principal = nil
        modoScroll = false
        arrastrandoPorTap = false
        apretando = false
        gemelo = false
    }
}
