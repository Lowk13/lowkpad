import UIKit

enum FuncionPC: String {
    case multimedia = "Multimedia", portapapeles = "Portapapeles", teclado = "Teclado"
    var icono: String {
        switch self {
        case .multimedia: return "playpause.fill"
        case .portapapeles: return "doc.on.clipboard"
        case .teclado: return "keyboard"
        }
    }
}

/// Panel nativo adaptable: scroll vertical y espacio reservado al teclado de iOS.
final class PanelPC: UIViewController {
    private let funcion: FuncionPC
    private let pila = UIStackView()
    private let estado = UILabel()
    private let texto = UITextView()
    private var botones: [UIButton] = []
    var alCerrar: (() -> Void)?
    init(_ funcion: FuncionPC) { self.funcion = funcion; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .secondarySystemBackground
        let scroll = UIScrollView()
        scroll.keyboardDismissMode = .interactive
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        pila.axis = .vertical
        pila.spacing = 12
        pila.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(pila)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            scroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            pila.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            pila.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -20),
            pila.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 16),
            pila.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -16),
            pila.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -32),
        ])
        let titulo = UILabel()
        titulo.text = funcion.rawValue
        titulo.font = .preferredFont(forTextStyle: .title2)
        titulo.adjustsFontForContentSizeCategory = true
        let cerrar = boton("Cerrar", icono: "xmark") { [weak self] in self?.dismiss(animated: true) }
        let cabecera = UIStackView(arrangedSubviews: [titulo, cerrar])
        cabecera.spacing = 12
        titulo.setContentHuggingPriority(.defaultLow, for: .horizontal)
        pila.addArrangedSubview(cabecera)
        estado.numberOfLines = 0
        estado.font = .preferredFont(forTextStyle: .footnote)
        estado.textColor = .secondaryLabel
        estado.accessibilityIdentifier = "estadoPanel"

        switch funcion {
        case .multimedia:
            aviso("Controla la reproducción y el volumen del PC.")
            fila([("Anterior", "backward.end.fill", "previous"), ("Siguiente", "forward.end.fill", "next")])
            fila([("Play / pausa", "playpause.fill", "play_pause"), ("Stop", "stop.fill", "stop")])
            fila([("Volumen −", "speaker.fill", "volume_down"), ("Volumen +", "speaker.wave.3.fill", "volume_up")])
            pila.addArrangedSubview(boton("Silenciar", icono: "speaker.slash.fill") { [weak self] in self?.tecla("mute") })
        case .portapapeles:
            aviso("En el PC, selecciona el texto y cópialo (Ctrl+C). Después pulsa «Recuperar del PC». También puedes pegar texto del iPhone aquí y enviarlo al PC.")
            pila.addArrangedSubview(boton("Recuperar del PC", icono: "arrow.down.doc") { [weak self] in
                self?.orden(["op": "clipboard_get"], exito: "Texto recuperado. Puedes copiarlo al iPhone.") { data in
                    self?.texto.text = data["text"] as? String ?? ""
                }
            })
            editor()
            pila.addArrangedSubview(boton("Copiar al iPhone", icono: "doc.on.doc") { [weak self] in
                guard let self else { return }
                UIPasteboard.general.string = self.texto.text
                self.estado.text = "Texto copiado al iPhone."
            })
            pila.addArrangedSubview(boton("Enviar al portapapeles del PC", icono: "arrow.up.doc") { [weak self] in
                guard let self, self.validarTexto() else { return }
                self.orden(["op": "clipboard_set", "text": self.texto.text ?? ""], exito: "Copiado en el PC. Pulsa Ctrl+V donde quieras pegarlo.")
            })
            pila.addArrangedSubview(boton("Enviar y pegar en el PC", icono: "doc.on.clipboard.fill") { [weak self] in
                guard let self, self.validarTexto() else { return }
                self.orden(["op": "clipboard_paste", "text": self.texto.text ?? ""], exito: "Texto enviado y pegado en la ventana activa del PC.")
            })
            aviso("Para traer texto del iPhone, mantén pulsado el cuadro y elige Pegar. Solo se transfiere al pulsar un botón.")
        case .teclado:
            aviso("Selecciona en el PC dónde escribir. Escribe aquí con el teclado del iPhone y pulsa Enviar texto.")
            editor()
            pila.addArrangedSubview(boton("Enviar texto", icono: "paperplane.fill") { [weak self] in
                guard let self, self.validarTexto(), !self.texto.text.isEmpty else { return }
                self.orden(["op": "text", "text": self.texto.text ?? ""], exito: "Texto enviado al PC.") { _ in self.texto.text = "" }
            })
            fila([("Intro", "return", "enter"), ("Borrar", "delete.left", "backspace")])
            fila([("Tab", "arrow.right.to.line", "tab"), ("Esc", "escape", "escape")])
            fila([("Izquierda", "arrow.left", "left"), ("Derecha", "arrow.right", "right")])
            fila([("Arriba", "arrow.up", "up"), ("Abajo", "arrow.down", "down")])
        }
        pila.addArrangedSubview(estado)
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        alCerrar?()
    }
    private func aviso(_ mensaje: String) {
        let label = UILabel()
        label.text = mensaje
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        pila.addArrangedSubview(label)
    }
    private func editor() {
        texto.backgroundColor = .tertiarySystemBackground
        texto.layer.cornerRadius = 12
        texto.font = .preferredFont(forTextStyle: .body)
        texto.adjustsFontForContentSizeCategory = true
        texto.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)
        texto.accessibilityLabel = "Texto para el PC"
        texto.accessibilityIdentifier = "editorTexto"
        texto.heightAnchor.constraint(equalToConstant: 120).isActive = true
        pila.addArrangedSubview(texto)
    }
    private func boton(_ titulo: String, icono: String, accion: @escaping () -> Void) -> UIButton {
        var cfg = UIButton.Configuration.tinted()
        cfg.title = titulo
        cfg.image = UIImage(systemName: icono)
        cfg.imagePadding = 8
        cfg.cornerStyle = .medium
        cfg.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 12, bottom: 14, trailing: 12)
        let b = UIButton(configuration: cfg)
        b.titleLabel?.numberOfLines = 0
        b.accessibilityLabel = titulo
        b.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        b.addAction(UIAction { _ in accion() }, for: .touchUpInside)
        botones.append(b)
        return b
    }
    private func fila(_ items: [(String, String, String)]) {
        let row = UIStackView()
        row.spacing = 12
        row.distribution = .fillEqually
        for (nombre, icono, key) in items {
            row.addArrangedSubview(boton(nombre, icono: icono) { [weak self] in self?.tecla(key) })
        }
        pila.addArrangedSubview(row)
    }
    private func tecla(_ key: String) { orden(["op": "key", "key": key], exito: "Orden enviada al PC.") }
    private func validarTexto() -> Bool {
        guard texto.text.utf8.count <= 65536 else { estado.text = "Máximo 64 KB de texto por envío."; return false }
        return true
    }
    private func orden(_ comando: [String: Any], exito: String, recibe: (([String: Any]) -> Void)? = nil) {
        estado.text = "Conectando…"
        botones.forEach { $0.isEnabled = false }
        texto.isEditable = false
        ControlPC.compartido.enviar(comando) { [weak self] result in
            guard let self else { return }
            self.botones.forEach { $0.isEnabled = true }
            self.texto.isEditable = true
            switch result {
            case .success(let data): recibe?(data); self.estado.text = exito
            case .failure(let error): self.estado.text = error.localizedDescription
            }
        }
    }
}
