import UIKit

/// Todo ajustable desde el móvil, a propósito: cada parámetro que se pueda
/// tocar aquí es una compilación que no hay que hacer.
final class PantallaAjustes: UIViewController {

    var alCerrar: (() -> Void)?

    private let scroll = UIScrollView()
    private let pila = UIStackView()
    private let a = Ajustes.compartidos
    private let campoIP = UITextField()

    private let fondoFila = UIColor(white: 0.07, alpha: 1)
    private let borde = UIColor(white: 0.16, alpha: 1)
    private let tenue = UIColor(white: 0.55, alpha: 1)
    private let acento = UIColor(red: 0.29, green: 0.62, blue: 1, alpha: 1)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.04, alpha: 1)

        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.keyboardDismissMode = .onDrag
        view.addSubview(scroll)

        pila.axis = .vertical
        pila.spacing = 7
        pila.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(pila)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            pila.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 10),
            pila.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 16),
            pila.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -16),
            pila.bottomAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -40),
            pila.widthAnchor.constraint(equalTo: scroll.widthAnchor, constant: -32),
        ])

        construir()
    }

    private func construir() {
        titulo("Conexión")
        filaIP()

        titulo("Velocidad")
        deslizador("Velocidad del cursor", 0.4, 5.0, { self.a.ganancia }, { self.a.ganancia = $0 }) {
            String(format: "%.1fx", $0)
        }
        interruptor("Aceleración", { self.a.aceleracion }, { self.a.aceleracion = $0 })
        deslizador("· a partir de", 150, 1500, { self.a.umbralAcel }, { self.a.umbralAcel = $0 }) {
            String(format: "%.0f", $0)
        }
        deslizador("· cuánto acelera", 0, 2, { self.a.pendienteAcel }, { self.a.pendienteAcel = $0 }) {
            String(format: "%.2f", $0)
        }
        nota("La aceleración es independiente: al apagarla, la velocidad base no cambia.")

        titulo("Scroll")
        deslizador("Velocidad de scroll", 0.2, 4, { self.a.gananciaScroll }, { self.a.gananciaScroll = $0 }) {
            String(format: "%.1fx", $0)
        }
        interruptor("Dirección natural", { self.a.scrollNatural }, { self.a.scrollNatural = $0 })
        interruptor("Franja de scroll (borde derecho)", { self.a.franjaScroll }, { self.a.franjaScroll = $0 })
        nota("La franja es para usarlo a una mano: el pulgar no llega a hacer el gesto de dos dedos.")

        titulo("Clic a una mano")
        interruptor("Golpecito en la trasera", { self.a.golpecito }, { self.a.golpecito = $0 })
        deslizador("· sensibilidad (brusquedad)", 0.08, 1.5, { self.a.umbralGolpe }, { self.a.umbralGolpe = $0 }) {
            String(format: "%.2f", $0)
        }
        interruptor("· que sea clic derecho", { self.a.golpeDerecho }, { self.a.golpeDerecho = $0 })
        nota("Ahora detecta lo BRUSCO del golpe, no lo fuerte: sujetando el móvil con una mano, "
             + "tu propia mano amortigua el golpe y por fuerza nunca llegaba. En la pantalla principal "
             + "sale «tiron» con el pico. Da un golpecito flojito, mira qué marca y pon el umbral "
             + "algo por debajo.")

        interruptor("Botones de volumen", { self.a.volumen }, { self.a.volumen = $0 })
        interruptor("· intercambiar izquierdo y derecho", { self.a.volumenInvertido }, { self.a.volumenInvertido = $0 })
        nota("Bajar = clic izquierdo, subir = clic derecho. Mientras la app esté abierta, el volumen "
             + "del móvil se queda anclado a la mitad.")

        titulo("Clic en la pantalla")
        interruptor("Tocar para hacer clic", { self.a.tocarClic }, { self.a.tocarClic = $0 })
        interruptor("Segundo dedo = clic", { self.a.segundoDedo }, { self.a.segundoDedo = $0 })
        interruptor("Barra de clic abajo", { self.a.barraClic }, { self.a.barraClic = $0 })
        interruptor("Mantener = clic derecho", { self.a.mantenerDerecho }, { self.a.mantenerDerecho = $0 })
        interruptor("Dos dedos = clic derecho", { self.a.dosDedosDerecho }, { self.a.dosDedosDerecho = $0 })
        nota("Si dejas el segundo dedo apoyado, el botón se queda pulsado: así se arrastra sin levantar nada.")

        titulo("Clic apoyando el pulgar")
        interruptor("Apoyar el pulgar = clic", { self.a.presion }, { self.a.presion = $0 })
        deslizador("· cuánto hay que apoyar", 1.15, 2.5, { self.a.presionAbajo }, { self.a.presionAbajo = $0 }) {
            String(format: "x%.2f", $0)
        }
        deslizador("· cuándo se suelta", 1.05, 2.0, { self.a.presionArriba }, { self.a.presionArriba = $0 }) {
            String(format: "x%.2f", $0)
        }
        nota("No es apretar más fuerte (eso cambia la huella un 20 % y se pierde en el ruido): es pasar "
             + "de apuntar con la PUNTA del pulgar a apoyarlo PLANO, que la cambia al doble. Arriba "
             + "sale «huella actual/mínima x factor»: apoya el pulgar plano, mira hasta dónde sube el "
             + "factor y pon el umbral por debajo de ese máximo.")

        titulo("Pantalla y tacto")
        interruptor("Vibración al hacer clic", { self.a.haptico }, { self.a.haptico = $0 })
        deslizador("Oscurecer (modo cama)", 0, 0.85, { self.a.oscurecer }, { self.a.oscurecer = $0 }) {
            String(format: "%.0f%%", $0 * 100)
        }

        let cerrar = UIButton(type: .system)
        cerrar.setTitle("Volver al trackpad", for: .normal)
        cerrar.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        cerrar.setTitleColor(UIColor(red: 0, green: 0.08, blue: 0.18, alpha: 1), for: .normal)
        cerrar.backgroundColor = acento
        cerrar.layer.cornerRadius = 10
        cerrar.heightAnchor.constraint(equalToConstant: 48).isActive = true
        cerrar.addTarget(self, action: #selector(cerrarPantalla), for: .touchUpInside)
        pila.addArrangedSubview(espacio(12))
        pila.addArrangedSubview(cerrar)
    }

    @objc private func cerrarPantalla() {
        a.ip = campoIP.text?.trimmingCharacters(in: .whitespaces) ?? a.ip
        alCerrar?()
        dismiss(animated: true)
    }

    // MARK: - piezas de la interfaz

    private func titulo(_ texto: String) {
        let l = UILabel()
        l.text = texto.uppercased()
        l.font = .systemFont(ofSize: 12, weight: .semibold)
        l.textColor = tenue
        pila.addArrangedSubview(espacio(14))
        pila.addArrangedSubview(l)
    }

    private func nota(_ texto: String) {
        let l = UILabel()
        l.text = texto
        l.numberOfLines = 0
        l.font = .systemFont(ofSize: 12)
        l.textColor = UIColor(white: 0.42, alpha: 1)
        pila.addArrangedSubview(l)
    }

    private func espacio(_ alto: CGFloat) -> UIView {
        let v = UIView()
        v.heightAnchor.constraint(equalToConstant: alto).isActive = true
        return v
    }

    private func caja() -> UIView {
        let v = UIView()
        v.backgroundColor = fondoFila
        v.layer.cornerRadius = 10
        v.layer.borderWidth = 1
        v.layer.borderColor = borde.cgColor
        return v
    }

    private func filaIP() {
        let v = caja()
        let l = UILabel()
        l.text = "IP del PC"
        l.font = .systemFont(ofSize: 15)
        l.textColor = .white
        campoIP.text = a.ip
        campoIP.textColor = acento
        campoIP.font = .monospacedDigitSystemFont(ofSize: 15, weight: .regular)
        campoIP.keyboardType = .numbersAndPunctuation   // decimalPad pondría coma en español
        campoIP.textAlignment = .right
        campoIP.keyboardAppearance = .dark
        for x in [l, campoIP] {
            x.translatesAutoresizingMaskIntoConstraints = false
            v.addSubview(x)
        }
        NSLayoutConstraint.activate([
            v.heightAnchor.constraint(equalToConstant: 50),
            l.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 12),
            l.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            campoIP.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -12),
            campoIP.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            campoIP.leadingAnchor.constraint(equalTo: l.trailingAnchor, constant: 8),
        ])
        pila.addArrangedSubview(v)
    }

    private func interruptor(_ texto: String, _ leer: @escaping () -> Bool,
                             _ escribir: @escaping (Bool) -> Void) {
        let v = caja()
        let l = UILabel()
        l.text = texto
        l.font = .systemFont(ofSize: 15)
        l.textColor = .white
        l.numberOfLines = 0
        let s = UISwitch()
        s.isOn = leer()
        s.onTintColor = acento
        // Se lee del emisor y no de la variable capturada: si capturamos `s`, el
        // interruptor se retiene a sí mismo a través de la acción y no se libera.
        s.addAction(UIAction { accion in
            guard let sw = accion.sender as? UISwitch else { return }
            escribir(sw.isOn)
            Haptica.compartida.toque()
        }, for: .valueChanged)
        for x in [l, s] as [UIView] {
            x.translatesAutoresizingMaskIntoConstraints = false
            v.addSubview(x)
        }
        NSLayoutConstraint.activate([
            v.heightAnchor.constraint(greaterThanOrEqualToConstant: 52),
            l.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 12),
            l.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            l.trailingAnchor.constraint(equalTo: s.leadingAnchor, constant: -10),
            s.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -12),
            s.centerYAnchor.constraint(equalTo: v.centerYAnchor),
        ])
        pila.addArrangedSubview(v)
    }

    private func deslizador(_ texto: String, _ minimo: Double, _ maximo: Double,
                            _ leer: @escaping () -> Double,
                            _ escribir: @escaping (Double) -> Void,
                            _ formato: @escaping (Double) -> String) {
        let v = caja()
        let l = UILabel()
        l.text = texto
        l.font = .systemFont(ofSize: 15)
        l.textColor = .white
        let valor = UILabel()
        valor.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        valor.textColor = tenue
        valor.text = formato(leer())
        let s = UISlider()
        s.minimumValue = Float(minimo)
        s.maximumValue = Float(maximo)
        s.value = Float(leer())
        s.minimumTrackTintColor = acento
        s.addAction(UIAction { accion in
            guard let sl = accion.sender as? UISlider else { return }
            escribir(Double(sl.value))
            valor.text = formato(Double(sl.value))
        }, for: .valueChanged)

        for x in [l, valor, s] as [UIView] {
            x.translatesAutoresizingMaskIntoConstraints = false
            v.addSubview(x)
        }
        NSLayoutConstraint.activate([
            l.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 12),
            l.topAnchor.constraint(equalTo: v.topAnchor, constant: 10),
            valor.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -12),
            valor.centerYAnchor.constraint(equalTo: l.centerYAnchor),
            s.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 12),
            s.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -12),
            s.topAnchor.constraint(equalTo: l.bottomAnchor, constant: 4),
            s.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -8),
        ])
        pila.addArrangedSubview(v)
    }
}
