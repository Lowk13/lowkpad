import UIKit

final class PantallaPrincipal: UIViewController, TrackpadDelegado {

    private let hud = UILabel()
    private let registro = UILabel()
    private let trackpad = Trackpad()
    private let franja = UIView()
    private let barra = UIButton(type: .custom)
    private let engranaje = UIButton(type: .system)
    private let oscurecedor = UIView()
    private let herramientas = UIScrollView()
    private let filaHerramientas = UIStackView()

    private let permiso = PermisoRedLocal()
    private let golpecito = Golpecito()
    private let enlace = Enlace.compartido

    private var relojHud: Timer?
    private var borrarNota: DispatchWorkItem?
    private var huella: Double = 0
    private var huellaBase: Double = 0
    private var huellaMin: Double = 0
    private var huellaMax: Double = 0
    private var picoGolpe: Double = 0

    // MARK: - ciclo de vida

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.03, alpha: 1)

        hud.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        hud.textColor = UIColor(white: 0.55, alpha: 1)
        hud.isUserInteractionEnabled = true
        hud.addGestureRecognizer(UITapGestureRecognizer(target: self,
                                                        action: #selector(diagnosticar)))
        view.addSubview(hud)

        engranaje.setTitle("ajustes", for: .normal)
        engranaje.titleLabel?.font = .systemFont(ofSize: 12)
        engranaje.setTitleColor(UIColor(white: 0.55, alpha: 1), for: .normal)
        engranaje.addTarget(self, action: #selector(abrirAjustes), for: .touchUpInside)
        view.addSubview(engranaje)

        trackpad.delegado = self
        trackpad.backgroundColor = UIColor(white: 0.07, alpha: 1)
        trackpad.layer.cornerRadius = 16
        trackpad.layer.borderWidth = 1
        trackpad.layer.borderColor = UIColor(white: 0.16, alpha: 1).cgColor
        trackpad.clipsToBounds = true
        view.addSubview(trackpad)

        franja.backgroundColor = UIColor(red: 0.29, green: 0.62, blue: 1, alpha: 0.06)
        franja.isUserInteractionEnabled = false
        trackpad.addSubview(franja)

        registro.font = .systemFont(ofSize: 12)
        registro.textColor = UIColor(white: 0.36, alpha: 1)
        let v = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
        registro.text = "LowkPad \(v)"
        registro.isUserInteractionEnabled = false
        trackpad.addSubview(registro)

        barra.setTitle("C L I C", for: .normal)
        barra.titleLabel?.font = .systemFont(ofSize: 12)
        barra.setTitleColor(UIColor(white: 0.35, alpha: 1), for: .normal)
        barra.backgroundColor = UIColor(white: 0.08, alpha: 1)
        barra.layer.cornerRadius = 14
        barra.layer.borderWidth = 1
        barra.layer.borderColor = UIColor(white: 0.16, alpha: 1).cgColor
        barra.addTarget(self, action: #selector(barraAbajo), for: .touchDown)
        barra.addTarget(self, action: #selector(barraArriba),
                        for: [.touchUpInside, .touchUpOutside, .touchCancel])
        view.addSubview(barra)

        construirHerramientas()

        oscurecedor.backgroundColor = .black
        oscurecedor.alpha = CGFloat(Ajustes.compartidos.oscurecer)
        oscurecedor.isUserInteractionEnabled = false
        view.addSubview(oscurecedor)

        enlace.alCambiar = { [weak self] _ in self?.pintarHud() }
        golpecito.alGolpear = { [weak self] in self?.golpeDetectado() }
        golpecito.alMedir = { [weak self] p in self?.picoGolpe = p }

        NotificationCenter.default.addObserver(
            self, selector: #selector(alFondo),
            name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(alFrente),
            name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        arrancarTodo()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let s = view.safeAreaInsets
        let a = view.bounds.width, alto = view.bounds.height
        hud.frame = CGRect(x: 14, y: s.top, width: a - 110, height: 44)
        engranaje.frame = CGRect(x: a - 94, y: s.top, width: 80, height: 44)

        let hayBarra = Ajustes.compartidos.barraClic
        let altoBarra: CGFloat = hayBarra ? 74 : 0
        let arriba = s.top + 48
        let bordeHerramientas = alto - s.bottom - 76
        herramientas.frame = CGRect(x: s.left + 8, y: bordeHerramientas, width: a - s.left - s.right - 16, height: 68)
        let abajo = bordeHerramientas - 8 - altoBarra - (hayBarra ? 8 : 0)
        trackpad.frame = CGRect(x: 8, y: arriba, width: a - 16, height: max(0, abajo - arriba))
        barra.isHidden = !hayBarra
        barra.frame = CGRect(x: 8, y: bordeHerramientas - 8 - altoBarra,
                             width: a - 16, height: altoBarra)

        let ancho = Ajustes.compartidos.franjaScroll ? trackpad.bounds.width * 0.14 : 0
        franja.frame = CGRect(x: Ajustes.compartidos.franjaIzquierda ? 0 : trackpad.bounds.width - ancho, y: 0,
                              width: ancho, height: trackpad.bounds.height)
        franja.isHidden = ancho == 0
        registro.frame = CGRect(x: 12 + (Ajustes.compartidos.franjaIzquierda ? ancho : 0), y: 10, width: trackpad.bounds.width - ancho - 24, height: 16)
        oscurecedor.frame = view.bounds
    }

    override var prefersStatusBarHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }

    // MARK: - arranque

    private func arrancarTodo() {
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") { return }
        let a = Ajustes.compartidos
        UIApplication.shared.isIdleTimerDisabled = true
        // Provoca el aviso de "permitir buscar dispositivos en tu red local".
        // Sin permiso, iOS tira los paquetes sin avisar de nada.
        permiso.pedir()
        enlace.conectar(ip: a.ip, puerto: UInt16(a.puerto))
        golpecito.arrancar()
        Haptica.compartida.preparar()
        oscurecedor.alpha = CGFloat(a.oscurecer)

        relojHud?.invalidate()
        relojHud = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.pintarHud()
        }
        view.setNeedsLayout()
    }

    @objc private func alFondo() {
        // iOS suspende la app: no puede quedarse ningún botón pulsado en el PC.
        trackpad.reiniciar()
        enlace.soltarTodo()
        golpecito.parar()
    }

    @objc private func alFrente() {
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") { return }
        guard presentedViewController == nil else { return }
        // Al bloquear el móvil iOS suspende la app y la conexión se queda
        // muerta: hay que rehacerla, no basta con volver a primer plano.
        let a = Ajustes.compartidos
        enlace.conectar(ip: a.ip, puerto: UInt16(a.puerto))
        golpecito.arrancar()
        Haptica.compartida.preparar()
        trackpad.reiniciar()
    }

    private func pintarHud() {
        let a = Ajustes.compartidos
        // El estado se basa en que el PC CONTESTE, no en que el socket exista:
        // un socket UDP se declara listo aunque no llegue nada al otro lado.
        if enlace.listo {
            var texto = "● \(a.ip)  \(Int(enlace.latencia)) ms"
            if huella > 0 {
                texto += String(format: "  ·  huella %.0f/%.0f x%.2f",
                                huella, huellaMin, huella / max(huellaBase, 0.001))
            }
            if a.golpecito { texto += String(format: "  ·  tiron %.2f", picoGolpe) }
            hud.text = texto
            hud.textColor = UIColor(white: 0.55, alpha: 1)
        } else {
            hud.text = "○ sin respuesta de \(a.ip) · toca aquí"
            hud.textColor = UIColor(red: 1, green: 0.36, blue: 0.36, alpha: 1)
        }
    }

    // MARK: - clics que no vienen del trackpad

    private func golpeDetectado() {
        let derecho = Ajustes.compartidos.golpeDerecho
        enlace.clic(derecho ? "r" : "l")
        Haptica.compartida.clic(derecho: derecho)
        nota(derecho ? "clic DERECHO · golpecito" : "clic izquierdo · golpecito", derecho: derecho)
    }

    @objc private func barraAbajo() {
        enlace.boton("l", pulsado: true)
        Haptica.compartida.clic()
        barra.backgroundColor = UIColor(red: 0.11, green: 0.14, blue: 0.19, alpha: 1)
        nota("barra de clic", derecho: false)
    }

    @objc private func barraArriba() {
        enlace.boton("l", pulsado: false)
        barra.backgroundColor = UIColor(white: 0.08, alpha: 1)
    }

    @objc private func diagnosticar() {
        let a = Ajustes.compartidos
        permiso.pedir()
        hud.text = "probando \(a.ip)..."
        Diagnostico.probar(ip: a.ip, puertoUDP: UInt16(a.puerto)) { [weak self] r in
            let titulo = r.udp ? "Conectado" : "No llega al PC"
            let cuerpo = """
            UDP \(a.puerto): \(r.udp ? "responde" : "nada")

            \(r.detalle)
            """
            let alerta = UIAlertController(title: titulo, message: cuerpo,
                                           preferredStyle: .alert)
            alerta.addAction(UIAlertAction(title: "Vale", style: .default))
            alerta.addAction(UIAlertAction(title: "Abrir Ajustes de iOS", style: .default) { _ in
                if let u = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(u)
                }
            })
            self?.present(alerta, animated: true)
        }
    }

    @objc private func abrirAjustes() {
        alFondo()
        let p = PantallaAjustes()
        p.alCerrar = { [weak self] in
            guard let self else { return }
            let a = Ajustes.compartidos
            self.enlace.conectar(ip: a.ip, puerto: UInt16(a.puerto))
            self.enlace.mandarAjustes()
            self.oscurecedor.alpha = CGFloat(a.oscurecer)
            self.view.setNeedsLayout()
        }
        p.modalPresentationStyle = .fullScreen
        present(p, animated: true)
    }

    private func construirHerramientas() {
        herramientas.accessibilityIdentifier = "barraHerramientas"
        herramientas.showsHorizontalScrollIndicator = true
        herramientas.alwaysBounceHorizontal = true
        herramientas.backgroundColor = UIColor(white: 0.08, alpha: 1)
        herramientas.layer.cornerRadius = 16
        view.addSubview(herramientas)
        filaHerramientas.spacing = 6
        filaHerramientas.translatesAutoresizingMaskIntoConstraints = false
        herramientas.addSubview(filaHerramientas)
        NSLayoutConstraint.activate([
            filaHerramientas.leadingAnchor.constraint(equalTo: herramientas.contentLayoutGuide.leadingAnchor, constant: 6),
            filaHerramientas.trailingAnchor.constraint(equalTo: herramientas.contentLayoutGuide.trailingAnchor, constant: -6),
            filaHerramientas.topAnchor.constraint(equalTo: herramientas.contentLayoutGuide.topAnchor, constant: 4),
            filaHerramientas.bottomAnchor.constraint(equalTo: herramientas.contentLayoutGuide.bottomAnchor, constant: -4),
            filaHerramientas.heightAnchor.constraint(equalTo: herramientas.frameLayoutGuide.heightAnchor, constant: -8),
        ])
        for funcion in [FuncionPC.multimedia, .portapapeles, .teclado] {
            herramienta(funcion.rawValue, icono: funcion.icono) { [weak self] in self?.abrirPanel(funcion) }
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
        cfg.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { entrada in
            var salida = entrada
            salida.font = .systemFont(ofSize: 12, weight: .medium)
            return salida
        }
        let b = UIButton(configuration: cfg)
        b.accessibilityLabel = titulo
        b.widthAnchor.constraint(equalToConstant: 112).isActive = true
        b.addAction(UIAction { _ in accion() }, for: .touchUpInside)
        filaHerramientas.addArrangedSubview(b)
    }
    private func abrirPanel(_ funcion: FuncionPC) {
        alFondo()
        let p = PanelPC(funcion)
        p.alCerrar = { [weak self] in
            guard let self, UIApplication.shared.applicationState == .active else { return }
            DispatchQueue.main.async { self.alFrente() }
        }
        p.modalPresentationStyle = .pageSheet
        if let sheet = p.sheetPresentationController {
            sheet.detents = funcion == .multimedia ? [.medium(), .large()] : [.large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 24
        }
        present(p, animated: true)
    }

    // MARK: - avisos en pantalla

    private func nota(_ texto: String, derecho: Bool) {
        registro.text = texto
        registro.textColor = derecho ? UIColor(red: 1, green: 0.69, blue: 0.13, alpha: 1)
                                     : UIColor(red: 0.29, green: 0.62, blue: 1, alpha: 1)
        trackpad.layer.borderColor = registro.textColor?.cgColor
        borrarNota?.cancel()
        let t = DispatchWorkItem { [weak self] in
            self?.registro.textColor = UIColor(white: 0.36, alpha: 1)
            self?.trackpad.layer.borderColor = UIColor(white: 0.16, alpha: 1).cgColor
        }
        borrarNota = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: t)
    }

    // MARK: - TrackpadDelegado

    func trackpadMovio(dx: Double, dy: Double) { enlace.mover(dx: dx, dy: dy) }
    func trackpadScroll(dx: Double, dy: Double) { enlace.scroll(dx: dx, dy: dy) }

    func trackpadBoton(_ cual: String, pulsado: Bool) {
        enlace.boton(cual, pulsado: pulsado)
        if pulsado { Haptica.compartida.clic(derecho: cual == "r") }
    }

    func trackpadClic(_ cual: String) {
        enlace.clic(cual)
        Haptica.compartida.clic(derecho: cual == "r")
    }

    func trackpadNota(_ texto: String, derecho: Bool) { nota(texto, derecho: derecho) }

    func trackpadHuella(_ radio: Double, base: Double, minimo: Double, maximo: Double) {
        huella = radio; huellaBase = base; huellaMin = minimo; huellaMax = maximo
    }
}
