import UIKit

/// Cambia la postura sin tocar la velocidad, la conexión ni los gestos elegidos.
final class PantallaErgonomia: UIViewController, UIAdaptivePresentationControllerDelegate {
    var alCambiar: (() -> Void)?
    var alCerrar: (() -> Void)?

    private let a = Ajustes.compartidos
    private let pila = UIStackView()
    private var modos: [DisposicionPad: UIButton] = [:]
    private let altura = UISegmentedControl(items: ["Compacta", "Media", "Amplia"])
    private var cerrado = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        presentationController?.delegate = self

        let cabecera = UIStackView()
        cabecera.alignment = .center
        let titulo = UILabel()
        titulo.text = "A tu mano"
        titulo.font = .preferredFont(forTextStyle: .title2)
        titulo.adjustsFontForContentSizeCategory = true
        let listo = UIButton(type: .system)
        listo.setTitle("Listo", for: .normal)
        listo.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        listo.widthAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true
        listo.heightAnchor.constraint(equalToConstant: 48).isActive = true
        listo.addAction(UIAction { [weak self] _ in
            self?.dismiss(animated: true) { self?.terminar() }
        }, for: .touchUpInside)
        cabecera.addArrangedSubview(titulo)
        cabecera.addArrangedSubview(listo)

        let scroll = UIScrollView()
        scroll.alwaysBounceVertical = true
        for v in [cabecera, scroll] {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
        }
        pila.axis = .vertical
        pila.spacing = 12
        pila.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(pila)
        NSLayoutConstraint.activate([
            cabecera.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            cabecera.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            cabecera.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            scroll.topAnchor.constraint(equalTo: cabecera.bottomAnchor, constant: 4),
            scroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            pila.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 8),
            pila.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            pila.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20),
            pila.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20),
            pila.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40)
        ])

        texto("Elige cómo lo sujetas. Puedes cambiar de postura en cualquier momento.", estilo: .subheadline)
        for modo in DisposicionPad.allCases {
            var cfg = UIButton.Configuration.tinted()
            cfg.title = modo.titulo
            cfg.subtitle = modo.detalle
            cfg.image = UIImage(systemName: modo.icono)
            cfg.imagePadding = 14
            cfg.titleAlignment = .leading
            cfg.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
            cfg.cornerStyle = .large
            let b = UIButton(configuration: cfg)
            b.contentHorizontalAlignment = .leading
            b.accessibilityIdentifier = "modo-\(modo.rawValue)"
            b.accessibilityLabel = modo.titulo
            b.heightAnchor.constraint(greaterThanOrEqualToConstant: 76).isActive = true
            b.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                self.a.disposicion = modo
                self.actualizar()
                self.alCambiar?()
                Haptica.compartida.toque()
            }, for: .touchUpInside)
            modos[modo] = b
            pila.addArrangedSubview(b)
        }

        texto("Alcance del pulgar", estilo: .headline)
        altura.accessibilityIdentifier = "alturaPulgar"
        altura.heightAnchor.constraint(equalToConstant: 44).isActive = true
        altura.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.a.alcancePulgar = self.altura.selectedSegmentIndex
            self.alCambiar?()
        }, for: .valueChanged)
        pila.addArrangedSubview(altura)
        texto("En vertical, ajusta la altura de la zona para una mano. Mesa y horizontal aprovechan todo el espacio.", estilo: .footnote)
        interruptor("Botones de clic visibles", id: "botonesVisibles", valor: a.botonesVisibles) { [weak self] valor in
            self?.a.botonesVisibles = valor
        }
        interruptor("Scroll lateral", id: "scrollLateral", valor: a.franjaScroll) { [weak self] valor in
            self?.a.franjaScroll = valor
        }
        texto("Gestos y controles", estilo: .headline)
        texto("• Desliza un dedo para mover; un toque hace clic.\n• Dos dedos: toque derecho o deslizar para scroll.\n• La franja lateral permite scroll con un pulgar.\n• Arrastrar mantiene el clic: mueve, levanta y recoloca el dedo. Pulsa Soltar para terminar.\n• Precisión reduce el movimiento para apuntar a objetivos pequeños.\n• Clic y Derecho también se pueden mantener pulsados.", estilo: .subheadline)
        texto("Los arrastres se sueltan al abrir un panel, cambiar postura, girar el móvil, perder conexión o salir de la app. En Ajustes puedes afinar la sensibilidad y los gestos.", estilo: .footnote)
        actualizar()
    }

    private func actualizar() {
        for (modo, b) in modos {
            var cfg = b.configuration
            cfg?.baseBackgroundColor = modo == a.disposicion ? .systemBlue : .secondarySystemBackground
            cfg?.baseForegroundColor = modo == a.disposicion ? .systemBlue : .label
            b.configuration = cfg
            b.accessibilityValue = modo == a.disposicion ? "seleccionado" : ""
        }
        altura.selectedSegmentIndex = min(2, max(0, a.alcancePulgar))
        altura.isEnabled = a.disposicion != .mesa
    }

    private func texto(_ texto: String, estilo: UIFont.TextStyle) {
        let l = UILabel()
        l.text = texto
        l.font = .preferredFont(forTextStyle: estilo)
        l.adjustsFontForContentSizeCategory = true
        l.numberOfLines = 0
        l.textColor = estilo == .headline ? .label : .secondaryLabel
        pila.addArrangedSubview(l)
    }

    private func interruptor(_ titulo: String, id: String, valor: Bool, cambiar: @escaping (Bool) -> Void) {
        let fila = UIStackView()
        fila.spacing = 12
        fila.alignment = .center
        let l = UILabel()
        l.text = titulo
        l.font = .preferredFont(forTextStyle: .body)
        l.adjustsFontForContentSizeCategory = true
        l.numberOfLines = 0
        let sw = UISwitch()
        sw.isOn = valor
        sw.accessibilityLabel = titulo
        sw.accessibilityIdentifier = id
        sw.addAction(UIAction { [weak self] action in
            guard let sw = action.sender as? UISwitch else { return }
            cambiar(sw.isOn)
            self?.alCambiar?()
        }, for: .valueChanged)
        fila.addArrangedSubview(l)
        fila.addArrangedSubview(sw)
        fila.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        pila.addArrangedSubview(fila)
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { terminar() }
    private func terminar() {
        guard !cerrado else { return }
        cerrado = true
        alCerrar?()
    }
}
