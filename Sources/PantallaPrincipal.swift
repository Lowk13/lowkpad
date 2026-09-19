import UIKit

final class PantallaPrincipal: UIViewController, TrackpadDelegado {
    private let hud = UILabel()
    private let marca = UILabel()
    private let registro = UILabel()
    private let pista = UILabel()
    private let resumen = UILabel()
    private let trackpad = Trackpad()
    private let franja = UIView()
    private let flechasScroll = UIImageView(image: UIImage(systemName: "arrow.up.arrow.down"))
    private let engranaje = UIButton(type: .system)
    private let postura = UIButton(type: .system)
    private let arrastre = UIButton(type: .system)
    private let precision = UIButton(type: .system)
    private let izquierdo = UIButton(type: .system)
    private let derecho = UIButton(type: .system)
    private let filaRapida = UIStackView()
    private let filaClic = UIStackView()
    private let oscurecedor = UIView()
    private let herramientas = UIScrollView()
    private let filaHerramientas = UIStackView()
    private let permiso = PermisoRedLocal()
    private let golpecito = Golpecito()
    private let enlace = Enlace.compartido
    private var relojHud: Timer?
    private var borrarNota: DispatchWorkItem?
    private var fuentesIzquierdo = Set<String>()
    private var fuentesDerecho = Set<String>()
    private var liberando = false
    private var arrastreFijo = false
    private var precisionActiva = false
    private var probando: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-ui-testing") || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        #else
        return false
        #endif
    }
    private var puedeControlar: Bool { probando || enlace.listo }
    private let azul = UIColor(red: 0.35, green: 0.70, blue: 1, alpha: 1)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.035, alpha: 1)
        marca.text = "LOWKPAD"
        marca.font = .systemFont(ofSize: 12, weight: .bold)
        marca.textColor = .secondaryLabel
        view.addSubview(marca)
        hud.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        hud.textColor = .secondaryLabel
        hud.isUserInteractionEnabled = true
        hud.accessibilityLabel = "Estado de conexión"
        hud.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(diagnosticar)))
        view.addSubview(hud)
        engranaje.setImage(UIImage(systemName: "slider.horizontal.3"), for: .normal)
        engranaje.tintColor = .secondaryLabel
        engranaje.accessibilityLabel = "Ajustes avanzados"
        engranaje.addTarget(self, action: #selector(abrirAjustes), for: .touchUpInside)
        view.addSubview(engranaje)
        trackpad.delegado = self
        trackpad.accessibilityIdentifier = "trackpad"
        trackpad.isAccessibilityElement = true
        trackpad.accessibilityLabel = "Superficie del ratón"
        trackpad.accessibilityHint = "Desliza para mover; toca para hacer clic."
        trackpad.backgroundColor = UIColor(red: 0.055, green: 0.072, blue: 0.095, alpha: 1)
        trackpad.layer.cornerRadius = 28
        trackpad.layer.cornerCurve = .continuous
        trackpad.layer.borderWidth = 1
        trackpad.layer.borderColor = UIColor(white: 0.19, alpha: 1).cgColor
        trackpad.clipsToBounds = true
        view.addSubview(trackpad)
        franja.backgroundColor = azul.withAlphaComponent(0.075)
        franja.accessibilityIdentifier = "franjaScroll"
        franja.isUserInteractionEnabled = false
        trackpad.addSubview(franja)
        flechasScroll.tintColor = azul.withAlphaComponent(0.45)
        flechasScroll.contentMode = .scaleAspectFit
        franja.addSubview(flechasScroll)
        registro.font = .systemFont(ofSize: 12, weight: .medium)
        registro.textColor = azul
        registro.numberOfLines = 2
        registro.isUserInteractionEnabled = false
        trackpad.addSubview(registro)
        pista.textAlignment = .center
        pista.numberOfLines = 0
        pista.font = .systemFont(ofSize: 13)
        pista.textColor = UIColor(white: 0.43, alpha: 1)
        pista.isUserInteractionEnabled = false
        trackpad.addSubview(pista)
        resumen.numberOfLines = 0
        resumen.textColor = .secondaryLabel
        resumen.font = .systemFont(ofSize: 17, weight: .medium)
        resumen.textAlignment = .center
        resumen.isUserInteractionEnabled = false
        view.addSubview(resumen)
        configurarBoton(postura, "Mesa", "hand.draw", id: "disposicionPad")
        configurarBoton(arrastre, "Arrastrar", "hand.draw", id: "arrastre")
        configurarBoton(precision, "Precisión", "scope", id: "precision")
        postura.addTarget(self, action: #selector(abrirErgonomia), for: .touchUpInside)
        arrastre.addTarget(self, action: #selector(alternarArrastre), for: .touchUpInside)
        precision.addTarget(self, action: #selector(alternarPrecision), for: .touchUpInside)
        filaRapida.spacing = 8
        filaRapida.distribution = .fillEqually
        [postura, arrastre, precision].forEach { filaRapida.addArrangedSubview($0) }
        view.addSubview(filaRapida)
        configurarBoton(izquierdo, "Clic", "cursorarrow.click", id: "clicIzquierdo")
        configurarBoton(derecho, "Derecho", "computermouse", id: "clicDerecho")
        for b in [izquierdo, derecho] {
            b.addTarget(self, action: #selector(botonAbajo(_:)), for: .touchDown)
            b.addTarget(self, action: #selector(botonArriba(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        }
        filaClic.spacing = 8
        filaClic.distribution = .fillEqually
        filaClic.addArrangedSubview(izquierdo)
        filaClic.addArrangedSubview(derecho)
        view.addSubview(filaClic)
        construirHerramientas()
        oscurecedor.backgroundColor = .black
        oscurecedor.alpha = CGFloat(Ajustes.compartidos.oscurecer)
        oscurecedor.isUserInteractionEnabled = false
        view.addSubview(oscurecedor)
        enlace.alCambiar = { [weak self] _ in self?.pintarHud() }
        golpecito.alGolpear = { [weak self] in self?.golpeDetectado() }
        NotificationCenter.default.addObserver(self, selector: #selector(alFondo), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(alFrente), name: UIApplication.didBecomeActiveNotification, object: nil)
        actualizarControles()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        arrancarTodo()
    }
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        liberarEntrada()
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in self.view.setNeedsLayout() })
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let s = view.safeAreaInsets
        let ancho = view.bounds.width - s.left - s.right - 24
        let x = s.left + 12
        let arriba = s.top + 52
        let fondo = view.bounds.height - s.bottom - 8
        let a = Ajustes.compartidos
        let horizontal = view.bounds.width > view.bounds.height
        marca.frame = CGRect(x: x + 4, y: s.top, width: 90, height: 44)
        hud.frame = CGRect(x: x + 96, y: s.top, width: max(0, ancho - 144), height: 44)
        engranaje.frame = CGRect(x: x + ancho - 44, y: s.top, width: 44, height: 44)
        herramientas.frame = CGRect(x: x, y: fondo - 68, width: ancho, height: 68)
        let limite = herramientas.frame.minY - 10
        let botones = a.botonesVisibles
        filaClic.isHidden = !botones
        if horizontal {
            let lateral: CGFloat = min(208, ancho * 0.29)
            let izquierda = a.disposicion == .izquierda
            let cx = izquierda ? x : x + ancho - lateral
            let px = izquierda ? x + lateral + 12 : x
            let alto = max(0, limite - arriba)
            filaRapida.axis = .vertical
            let altoClic: CGFloat = botones ? 52 : 0
            filaRapida.frame = CGRect(x: cx, y: arriba, width: lateral, height: max(144, alto - altoClic - (botones ? 8 : 0)))
            filaClic.frame = CGRect(x: cx, y: limite - altoClic, width: lateral, height: altoClic)
            trackpad.frame = CGRect(x: px, y: arriba, width: ancho - lateral - 12, height: alto)
            resumen.isHidden = true
        } else {
            filaRapida.axis = .horizontal
            let mano = a.disposicion != .mesa
            let util = mano ? min(ancho, max(296, ancho * 0.86)) : ancho
            let px = a.disposicion == .derecha ? x + ancho - util : x
            let altoClic: CGFloat = botones ? 56 : 0
            filaClic.frame = CGRect(x: px, y: limite - altoClic, width: util, height: altoClic)
            let finRapida = limite - altoClic - (botones ? 8 : 0)
            filaRapida.frame = CGRect(x: x, y: finRapida - 50, width: ancho, height: 50)
            let finPad = filaRapida.frame.minY - 10
            let disponible = max(0, finPad - arriba)
            let factores: [CGFloat] = [0.53, 0.68, 0.84]
            let alto = mano ? min(disponible, max(180, disponible * factores[min(2, max(0, a.alcancePulgar))])) : disponible
            trackpad.frame = CGRect(x: px, y: finPad - alto, width: util, height: alto)
            resumen.isHidden = !mano || trackpad.frame.minY - arriba < 64
            resumen.frame = CGRect(x: x + 16, y: arriba + 8, width: ancho - 32, height: max(0, trackpad.frame.minY - arriba - 24))
            resumen.text = "\(a.disposicion.titulo)\nAcerca los controles a tu pulgar."
        }
        let af = a.anchoFranja(en: trackpad.bounds.width)
        franja.frame = CGRect(x: a.scrollALaIzquierda ? 0 : trackpad.bounds.width - af, y: 0, width: af, height: trackpad.bounds.height)
        franja.isHidden = af == 0
        flechasScroll.frame = CGRect(x: (af - 16) / 2, y: (franja.bounds.height - 28) / 2, width: 16, height: 28)
        let tx = 18 + (a.scrollALaIzquierda ? af : 0)
        let tw = max(0, trackpad.bounds.width - af - 36)
        registro.frame = CGRect(x: tx, y: 12, width: tw, height: 36)
        pista.frame = CGRect(x: tx, y: max(44, (trackpad.bounds.height - 54) / 2), width: tw, height: 54)
        pista.isHidden = trackpad.bounds.height < 128
        oscurecedor.frame = view.bounds
    }
    override var prefersStatusBarHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .bottom }

    private func arrancarTodo() {
        actualizarControles()
        view.setNeedsLayout()
        pintarHud()
        guard !probando else { return }
        let a = Ajustes.compartidos
        UIApplication.shared.isIdleTimerDisabled = true
        permiso.pedir()
        enlace.conectar(ip: a.ip, puerto: UInt16(a.puerto))
        if a.golpecito { golpecito.arrancar() } else { golpecito.parar() }
        Haptica.compartida.preparar()
        relojHud?.invalidate()
        relojHud = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.pintarHud() }
    }
    @objc private func alFondo() {
        liberarEntrada()
        golpecito.parar()
        UIApplication.shared.isIdleTimerDisabled = false
    }
    @objc private func alFrente() {
        guard presentedViewController == nil else { return }
        arrancarTodo()
    }
    private func liberarEntrada() {
        liberando = true
        arrastreFijo = false
        fuentesIzquierdo.removeAll()
        fuentesDerecho.removeAll()
        trackpad.reiniciar()
        trackpad.botonExternoPulsado = false
        enlace.soltarTodo()
        liberando = false
        actualizarControles()
    }
    private func pintarHud() {
        if puedeControlar {
            hud.text = probando ? "● Conectado · prueba" : "● \(Int(enlace.latencia)) ms · red"
            hud.textColor = .systemGreen
        } else {
            hud.text = "○ Sin conexión · ayuda"
            hud.textColor = .systemOrange
            if !fuentesIzquierdo.isEmpty || !fuentesDerecho.isEmpty { liberarEntrada() }
        }
        arrastre.isEnabled = puedeControlar
        izquierdo.isEnabled = puedeControlar
        derecho.isEnabled = puedeControlar && !arrastreFijo
    }
    private func configurarBoton(_ b: UIButton, _ titulo: String, _ icono: String, id: String) {
        var cfg = UIButton.Configuration.tinted()
        cfg.title = titulo
        cfg.image = UIImage(systemName: icono)
        cfg.imagePadding = 6
        cfg.baseForegroundColor = .label
        cfg.baseBackgroundColor = UIColor(white: 0.15, alpha: 1)
        cfg.cornerStyle = .large
        cfg.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 6, bottom: 8, trailing: 6)
        cfg.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { var a = $0; a.font = .systemFont(ofSize: 13, weight: .semibold); return a }
        b.configuration = cfg
        b.accessibilityIdentifier = id
        b.titleLabel?.adjustsFontSizeToFitWidth = true
    }
    private func actualizarControles() {
        guard isViewLoaded else { return }
        let a = Ajustes.compartidos
        postura.configuration?.title = a.disposicion.corto
        postura.configuration?.image = UIImage(systemName: a.disposicion.icono)
        postura.accessibilityLabel = "Postura: \(a.disposicion.titulo)"
        postura.accessibilityHint = "Elige postura y alcance del pulgar."
        arrastre.configuration?.title = arrastreFijo ? "Soltar" : "Arrastrar"
        arrastre.configuration?.image = UIImage(systemName: arrastreFijo ? "lock.fill" : "hand.draw")
        arrastre.configuration?.baseForegroundColor = arrastreFijo ? .systemOrange : .label
        arrastre.configuration?.baseBackgroundColor = arrastreFijo ? .systemOrange : UIColor(white: 0.15, alpha: 1)
        arrastre.accessibilityValue = arrastreFijo ? "activo" : "inactivo"
        precision.configuration?.baseForegroundColor = precisionActiva ? azul : .label
        precision.configuration?.baseBackgroundColor = precisionActiva ? azul : UIColor(white: 0.15, alpha: 1)
        precision.accessibilityValue = precisionActiva ? "activo" : "inactivo"
        trackpad.accessibilityValue = "\(a.disposicion.titulo); arrastre \(arrastreFijo ? "activo" : "inactivo"); precisión \(precisionActiva ? "activa" : "inactiva")"
        derecho.isEnabled = puedeControlar && !arrastreFijo
        pista.text = arrastreFijo ? "Mueve y recoloca el dedo\nPulsa Soltar para terminar" : "Desliza para mover\nToque · clic    Dos dedos · scroll"
        registro.text = arrastreFijo ? "Arrastre bloqueado" : (precisionActiva ? "Precisión · movimiento ×0,35" : "\(a.disposicion.titulo) · trackpad")
        registro.textColor = arrastreFijo ? .systemOrange : azul
        oscurecedor.alpha = CGFloat(a.oscurecer)
    }

    /// Un origen no puede soltar el botón que está manteniendo otro.
    private func cambiarBoton(_ cual: String, fuente: String, pulsado: Bool) {
        guard !liberando, !pulsado || puedeControlar else { return }
        if cual == "l" {
            if pulsado { fuentesIzquierdo.insert(fuente) } else { fuentesIzquierdo.remove(fuente) }
        } else {
            if pulsado { fuentesDerecho.insert(fuente) } else { fuentesDerecho.remove(fuente) }
        }
        let externo = fuentesIzquierdo.contains("boton") || fuentesIzquierdo.contains("bloqueo") || fuentesDerecho.contains("boton")
        trackpad.botonExternoPulsado = externo
        enlace.boton(cual, pulsado: cual == "l" ? !fuentesIzquierdo.isEmpty : !fuentesDerecho.isEmpty)
    }
    @objc private func botonAbajo(_ b: UIButton) {
        guard puedeControlar else { return }
        if b === izquierdo && arrastreFijo { alternarArrastre(); return }
        cambiarBoton(b === izquierdo ? "l" : "r", fuente: "boton", pulsado: true)
        Haptica.compartida.clic(derecho: b === derecho)
    }
    @objc private func botonArriba(_ b: UIButton) {
        cambiarBoton(b === izquierdo ? "l" : "r", fuente: "boton", pulsado: false)
    }
    @objc private func alternarArrastre() {
        guard puedeControlar else { return }
        let activar = !arrastreFijo
        liberarEntrada()
        arrastreFijo = activar
        cambiarBoton("l", fuente: "bloqueo", pulsado: activar)
        Haptica.compartida.toque()
        actualizarControles()
    }
    @objc private func alternarPrecision() {
        precisionActiva.toggle()
        Haptica.compartida.toque()
        actualizarControles()
    }
    private func golpeDetectado() {
        guard presentedViewController == nil, UIApplication.shared.applicationState == .active,
              puedeControlar, fuentesIzquierdo.isEmpty, fuentesDerecho.isEmpty else { return }
        trackpadClic(Ajustes.compartidos.golpeDerecho ? "r" : "l")
    }
    @objc private func abrirErgonomia() {
        alFondo()
        let p = PantallaErgonomia()
        p.alCambiar = { [weak self] in self?.liberarEntrada(); self?.view.setNeedsLayout() }
        p.alCerrar = { [weak self] in self?.alFrente() }
        presentar(p)
    }
    @objc private func abrirAjustes() {
        alFondo()
        let p = PantallaAjustes()
        p.alCerrar = { [weak self] in
            self?.enlace.mandarAjustes()
            self?.actualizarControles()
            self?.view.setNeedsLayout()
        }
        p.modalPresentationStyle = .fullScreen
        present(p, animated: true)
    }
    private func presentar(_ p: UIViewController) {
        p.modalPresentationStyle = .pageSheet
        if let sheet = p.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 24
        }
        present(p, animated: true)
    }
    private func construirHerramientas() {
        herramientas.accessibilityIdentifier = "barraHerramientas"
        herramientas.showsHorizontalScrollIndicator = true
        herramientas.alwaysBounceHorizontal = true
        herramientas.backgroundColor = UIColor(white: 0.085, alpha: 1)
        herramientas.layer.cornerRadius = 20
        view.addSubview(herramientas)
        filaHerramientas.spacing = 6
        filaHerramientas.translatesAutoresizingMaskIntoConstraints = false
        herramientas.addSubview(filaHerramientas)
        NSLayoutConstraint.activate([
            filaHerramientas.leadingAnchor.constraint(equalTo: herramientas.contentLayoutGuide.leadingAnchor, constant: 6),
            filaHerramientas.trailingAnchor.constraint(equalTo: herramientas.contentLayoutGuide.trailingAnchor, constant: -6),
            filaHerramientas.topAnchor.constraint(equalTo: herramientas.contentLayoutGuide.topAnchor, constant: 4),
            filaHerramientas.bottomAnchor.constraint(equalTo: herramientas.contentLayoutGuide.bottomAnchor, constant: -4),
            filaHerramientas.heightAnchor.constraint(equalTo: herramientas.frameLayoutGuide.heightAnchor, constant: -8)
        ])
        for f in [FuncionPC.multimedia, .portapapeles, .teclado, .atajos] {
            herramienta(f.rawValue, icono: f.icono) { [weak self] in self?.abrirPanel(f) }
        }
        herramienta("Ajustes", icono: "slider.horizontal.3") { [weak self] in self?.abrirAjustes() }
    }
    private func herramienta(_ titulo: String, icono: String, accion: @escaping () -> Void) {
        var cfg = UIButton.Configuration.plain()
        cfg.title = titulo
        cfg.image = UIImage(systemName: icono)
        cfg.imagePlacement = .top
        cfg.imagePadding = 5
        cfg.baseForegroundColor = .label
        cfg.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { var a = $0; a.font = .systemFont(ofSize: 12, weight: .medium); return a }
        let b = UIButton(configuration: cfg)
        b.accessibilityLabel = titulo
        b.widthAnchor.constraint(equalToConstant: 112).isActive = true
        b.addAction(UIAction { _ in accion() }, for: .touchUpInside)
        filaHerramientas.addArrangedSubview(b)
    }
    private func abrirPanel(_ funcion: FuncionPC) {
        alFondo()
        let p = PanelPC(funcion)
        p.alCerrar = { [weak self] in DispatchQueue.main.async { self?.alFrente() } }
        presentar(p)
    }
    @objc private func diagnosticar() {
        guard !probando else { return }
        alFondo()
        let a = Ajustes.compartidos
        permiso.pedir()
        hud.text = "Probando conexión…"
        Diagnostico.probar(ip: a.ip, puertoUDP: UInt16(a.puerto)) { [weak self] r in
            guard let self, self.presentedViewController == nil else { return }
            let alerta = UIAlertController(title: r.udp ? "Conectado" : "No llega al PC", message: "\(a.ip) · UDP \(a.puerto)\n\n\(r.detalle)", preferredStyle: .alert)
            alerta.addAction(UIAlertAction(title: "Vale", style: .default) { [weak self] _ in self?.arrancarTodo() })
            alerta.addAction(UIAlertAction(title: "Ajustes de iOS", style: .default) { _ in
                if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
            })
            self.present(alerta, animated: true)
        }
    }
    private func nota(_ texto: String, derecho: Bool) {
        registro.text = texto
        registro.textColor = derecho ? .systemOrange : azul
        borrarNota?.cancel()
        let t = DispatchWorkItem { [weak self] in self?.actualizarControles() }
        borrarNota = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: t)
    }
    func trackpadMovio(dx: Double, dy: Double) {
        guard puedeControlar else { return }
        let factor = precisionActiva ? 0.35 : 1.0
        enlace.mover(dx: dx * factor, dy: dy * factor)
    }
    func trackpadScroll(dx: Double, dy: Double) {
        guard puedeControlar, fuentesIzquierdo.isEmpty, fuentesDerecho.isEmpty else { return }
        enlace.scroll(dx: dx, dy: dy)
    }
    func trackpadBoton(_ cual: String, pulsado: Bool) {
        cambiarBoton(cual, fuente: "gesto", pulsado: pulsado)
        if pulsado && puedeControlar { Haptica.compartida.clic(derecho: cual == "r") }
    }
    func trackpadClic(_ cual: String) {
        guard puedeControlar, fuentesIzquierdo.isEmpty, fuentesDerecho.isEmpty else { return }
        enlace.clic(cual)
        Haptica.compartida.clic(derecho: cual == "r")
    }
    func trackpadNota(_ texto: String, derecho: Bool) { nota(texto, derecho: derecho) }
    func trackpadHuella(_ radio: Double, base: Double, minimo: Double, maximo: Double) {}
}
