import UIKit

protocol TrackpadDelegado: AnyObject {
    func trackpadMovio(dx: Double, dy: Double)
    func trackpadScroll(dx: Double, dy: Double)
    func trackpadBoton(_ cual: String, pulsado: Bool)
    func trackpadClic(_ cual: String)
    func trackpadNota(_ texto: String, derecho: Bool)
    func trackpadHuella(_ radio: Double, base: Double, minimo: Double, maximo: Double)
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

    /// Los botones visibles y el bloqueo de arrastre pertenecen al controlador.
    /// Mientras están pulsados esta superficie sirve únicamente para apuntar.
    var botonExternoPulsado = false {
        didSet {
            guard botonExternoPulsado != oldValue else { return }
            cancelarReconocedores()
            modoScroll = false
            enFranja = false
            ultimoTap = 0
            if principal != nil { soloPuntero = true }
        }
    }

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
    private var huboSecundario = false
    private var modoScroll = false
    private var apretando = false
    private var baseHuella: Double = 0
    private var muestrasHuella: [Double] = []
    private var radioMin: Double = 0
    private var radioMax: Double = 0

    private var secundarios: [ObjectIdentifier: Secundario] = [:]
    private var dedosActivos: Set<ObjectIdentifier> = []
    private var esperandoLevantar = false
    private var soloPuntero = false
    private var botonInternoPulsado = false
    private var recorridoConSecundario = 0.0
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
        Ajustes.compartidos.anchoFranja(en: bounds.width)
    }

    private var hayArrastre: Bool {
        arrastrandoPorTap || apretando || secundarios.values.contains { $0.arrastre }
    }

    /// Agrega las fuentes internas: terminar una no puede soltar otra activa.
    private func actualizarBotonInterno() {
        let pulsado = hayArrastre
        guard pulsado != botonInternoPulsado else { return }
        botonInternoPulsado = pulsado
        delegado?.trackpadBoton("l", pulsado: pulsado)
    }

    private func cancelarReconocedores() {
        tareaLarga?.cancel()
        tareaLarga = nil
        arrastrandoPorTap = false
        apretando = false
        for id in Array(secundarios.keys) {
            secundarios[id]?.tarea?.cancel()
            secundarios[id]?.arrastre = false
        }
        actualizarBotonInterno()
    }

    // MARK: - dedos

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let a = Ajustes.compartidos
        let ahora = CFAbsoluteTimeGetCurrent()

        for t in touches.sorted(by: { $0.timestamp < $1.timestamp }) {
            dedosActivos.insert(ObjectIdentifier(t))
            guard !esperandoLevantar else { continue }
            if principal == nil {
                principal = t
                inicioPrincipal = ahora
                ultimoPunto = t.location(in: self)
                ultimoInstante = ahora
                recorrido = 0
                gemelo = false
                huboSecundario = false
                apretando = false
                muestrasHuella.removeAll()
                baseHuella = 0
                soloPuntero = botonExternoPulsado
                modoScroll = false
                enFranja = !soloPuntero && anchoFranja > 0 && (a.scrollALaIzquierda
                    ? ultimoPunto.x < anchoFranja : ultimoPunto.x > bounds.width - anchoFranja)

                if enFranja { modoScroll = true }

                // tap y medio: tocar y, en el segundo toque, no levantar = arrastrar
                if a.tocarClic, !soloPuntero, !enFranja, ahora - ultimoTap < 0.32,
                   hypot(ultimoPunto.x - ultimoTapPunto.x, ultimoPunto.y - ultimoTapPunto.y) < 40 {
                    arrastrandoPorTap = true
                    actualizarBotonInterno()
                    delegado?.trackpadNota("arrastrando (tap y medio)", derecho: false)
                }

                if a.mantenerDerecho, !soloPuntero, !enFranja {
                    let tarea = DispatchWorkItem { [weak self] in
                        guard let self, self.principal != nil, self.recorrido < self.umbralMov,
                              !self.hayArrastre, !self.soloPuntero, !self.esperandoLevantar,
                              self.secundarios.isEmpty else { return }
                        self.delegado?.trackpadClic("r")
                        self.delegado?.trackpadNota("clic DERECHO · mantener", derecho: true)
                        self.recorrido = self.umbralMov + 1   // que no cuente además como toque
                    }
                    tareaLarga = tarea
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.62, execute: tarea)
                }
            } else {
                huboSecundario = true
                ultimoTap = 0
                guard secundarios.isEmpty else {
                    // Tres contactos no son un gesto: impedir clics repetidos y
                    // esperar a que todos se levanten antes de volver a reconocer.
                    esperandoLevantar = true
                    cancelarReconocedores()
                    continue
                }
                var s = Secundario(inicio: ahora, origen: t.location(in: self))
                tareaLarga?.cancel()
                recorridoConSecundario = 0

                if secundarios.isEmpty, recorrido < umbralMov, ahora - inicioPrincipal < 0.12 {
                    gemelo = true
                }

                // segundo dedo apoyado y quieto = botón pulsado mientras siga ahí
                if a.segundoDedo, !gemelo, !soloPuntero, !enFranja, !hayArrastre {
                    let id = ObjectIdentifier(t)
                    let tarea = DispatchWorkItem { [weak self] in
                        guard let self, var sec = self.secundarios[id],
                              !sec.movido, self.principal != nil, !self.modoScroll,
                              !self.soloPuntero, !self.esperandoLevantar,
                              !self.botonExternoPulsado, !self.hayArrastre else { return }
                        sec.arrastre = true
                        self.secundarios[id] = sec
                        self.modoScroll = false
                        self.actualizarBotonInterno()
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
        guard !esperandoLevantar else { return }
        let ahora = CFAbsoluteTimeGetCurrent()
        var dx = 0.0, dy = 0.0, huboPrincipal = false

        for t in touches {
            if t === principal {
                // Recuperar la trayectoria real sin crear una ráfaga de paquetes
                // con marcas de tiempo idénticas para muestras ya antiguas.
                for muestra in event?.coalescedTouches(for: t) ?? [t] {
                    let p = muestra.location(in: self)
                    let mx = Double(p.x - ultimoPunto.x)
                    let my = Double(p.y - ultimoPunto.y)
                    dx += mx; dy += my
                    recorrido += hypot(mx, my)
                    if !secundarios.isEmpty { recorridoConSecundario += hypot(mx, my) }
                    ultimoPunto = p
                }
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

        if recorrido > umbralMov { tareaLarga?.cancel() }

        // Solo se entra en scroll si hay dos dedos Y movimiento real, y ninguno
        // de ellos está haciendo de botón.
        if !modoScroll, !enFranja, !soloPuntero, !hayArrastre,
           !secundarios.isEmpty, recorridoConSecundario > umbralMov {
            if gemelo || secundarios.values.contains(where: { $0.movido }) {
                secundarios.values.forEach { $0.tarea?.cancel() }
                modoScroll = true
                ultimoTap = 0
                delegado?.trackpadNota("scroll con dos dedos", derecho: false)
            }
        }

        ultimoInstante = ahora
        if modoScroll {
            delegado?.trackpadScroll(dx: enFranja ? 0 : dx, dy: dy)
        } else if !soloPuntero, !hayArrastre, !secundarios.isEmpty,
                  gemelo || secundarios.values.contains(where: { $0.movido }) {
            // La zona muerta decide entre clic de dos dedos y scroll sin mover
            // antes el cursor por debajo de aquello que se quería seleccionar.
            return
        } else {
            delegado?.trackpadMovio(dx: dx, dy: dy)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        terminar(touches)
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        cancelarReconocedores()
        secundarios.removeAll()
        principal = nil
        modoScroll = false
        enFranja = false
        ultimoTap = 0
        for t in touches { dedosActivos.remove(ObjectIdentifier(t)) }
        // UIKit puede cancelar solo una parte de los contactos. Los restantes
        // no deben convertirse en un gesto nuevo sin haberse levantado antes.
        esperandoLevantar = !dedosActivos.isEmpty
    }

    private func terminar(_ touches: Set<UITouch>) {
        let a = Ajustes.compartidos
        let ahora = CFAbsoluteTimeGetCurrent()

        // Resolver el toque con dos dedos una sola vez, al levantar el primero.
        // Da igual si UIKit entrega los finales juntos o en callbacks distintos.
        let terminaReconocido = touches.contains { $0 === principal || secundarios[ObjectIdentifier($0)] != nil }
        if terminaReconocido, gemelo, a.dosDedosDerecho, !esperandoLevantar,
           !soloPuntero, !modoScroll, !hayArrastre, recorrido < umbralMov,
           ahora - inicioPrincipal < msSegundo,
           let s = secundarios.values.first, !s.movido, ahora - s.inicio < msSegundo {
            delegado?.trackpadClic("r")
            delegado?.trackpadNota("clic DERECHO · dos dedos", derecho: true)
            esperandoLevantar = true
            ultimoTap = 0
        }

        // Procesar primero el dedo principal hace determinista el final simultáneo.
        for t in touches.sorted(by: { ($0 === principal ? 0 : 1) < ($1 === principal ? 0 : 1) }) {
            if t === principal {
                tareaLarga?.cancel()
                let dur = ahora - inicioPrincipal

                if hayArrastre {
                    delegado?.trackpadNota("fin de arrastre", derecho: false)
                } else if a.tocarClic, !soloPuntero, !esperandoLevantar, !modoScroll,
                          recorrido < umbralMov, !enFranja,
                          dur < msTap, !gemelo, !huboSecundario, secundarios.isEmpty {
                    delegado?.trackpadClic("l")
                    delegado?.trackpadNota("clic izquierdo · toque", derecho: false)
                    ultimoTap = ahora
                    ultimoTapPunto = ultimoPunto
                }

                cancelarReconocedores()
                principal = nil
                enFranja = false
                esperandoLevantar = true

            } else if let s = secundarios.removeValue(forKey: ObjectIdentifier(t)) {
                s.tarea?.cancel()
                let dur = ahora - s.inicio

                if s.arrastre {
                    actualizarBotonInterno()
                    delegado?.trackpadNota("fin de arrastre", derecho: false)
                } else if !s.movido, !modoScroll, !soloPuntero, !esperandoLevantar,
                          !hayArrastre, !gemelo, dur < msSegundo {
                    if principal != nil, a.segundoDedo {
                        delegado?.trackpadClic("l")
                        delegado?.trackpadNota("clic izquierdo · segundo dedo", derecho: false)
                    }
                }
                if modoScroll { esperandoLevantar = true }
                gemelo = false
            }
            dedosActivos.remove(ObjectIdentifier(t))
        }
        if dedosActivos.isEmpty {
            cancelarReconocedores()
            secundarios.removeAll()
            principal = nil
            modoScroll = false
            esperandoLevantar = false
            soloPuntero = false
            gemelo = false
            enFranja = false
        }
    }

    // MARK: - el experimento de la presión

    /// Clic **apoyando el pulgar plano**.
    ///
    /// El iPhone 13 no tiene sensor de fuerza, pero sí da el tamaño de la huella
    /// (`majorRadius`). Apretar más fuerte cambia esa huella un 20 % y con un
    /// sensor tosco eso se pierde en el ruido. En cambio, pasar de apuntar con
    /// la **punta** del pulgar a apoyarlo **plano** la cambia al doble o más:
    /// una señal enorme, imposible de confundir, y un gesto que se hace con la
    /// misma mano que sujeta el móvil sin levantar el dedo.
    ///
    /// La referencia es el **mínimo** que se ha visto (el pulgar de punta), no
    /// las primeras muestras: así da igual si empiezas ya con el dedo apoyado.
    /// Baja al instante y sube muy despacio, para que la referencia se recupere
    /// si cambias de postura pero no la arrastre un apoyo mantenido.
    private func medirHuella(_ t: UITouch) {
        let r = Double(t.majorRadius)
        guard r > 0 else { return }

        if baseHuella == 0 { baseHuella = r }
        if r < baseHuella { baseHuella = r }
        else { baseHuella += (r - baseHuella) * 0.0008 }

        if radioMin == 0 || r < radioMin { radioMin = r }
        if r > radioMax { radioMax = r }
        delegado?.trackpadHuella(r, base: baseHuella, minimo: radioMin, maximo: radioMax)

        guard Ajustes.compartidos.presion, !soloPuntero, !modoScroll,
              !arrastrandoPorTap, secundarios.isEmpty else { return }
        muestrasHuella.append(r)
        guard muestrasHuella.count > 4 else { return }

        let ratio = r / max(baseHuella, 0.001)
        let a = Ajustes.compartidos
        if !apretando, ratio >= a.presionAbajo {
            apretando = true
            actualizarBotonInterno()
            delegado?.trackpadNota("clic · pulgar apoyado", derecho: false)
        } else if apretando, ratio <= a.presionArriba {
            apretando = false
            actualizarBotonInterno()
        }
    }

    /// Para poder calibrar mirando la pantalla: cuánto llega a cambiar la huella
    /// entre la punta del pulgar y el pulgar apoyado.
    func reiniciarMedidas() {
        radioMin = 0
        radioMax = 0
    }

    /// Al irse la app a segundo plano hay que soltarlo todo.
    func reiniciar() {
        cancelarReconocedores()
        secundarios.removeAll()
        dedosActivos.removeAll()
        principal = nil
        modoScroll = false
        arrastrandoPorTap = false
        apretando = false
        gemelo = false
        huboSecundario = false
        enFranja = false
        esperandoLevantar = false
        soloPuntero = false
        ultimoTap = 0
    }
}
