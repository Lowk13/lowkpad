import UIKit

/// Periférico de teclado: no conserva un documento local ni mueve el cursor del PC.
final class TecladoRemoto: UIView, UIKeyInput {
    var alEscribir: ((String) -> Void)?
    var alBorrar: (() -> Void)?
    var alActivar: (() -> Void)?
    var habilitado = false
    var hasText: Bool { true } // También permite borrar texto que ya existía en el PC.
    override var canBecomeFirstResponder: Bool { habilitado }
    var autocorrectionType: UITextAutocorrectionType = .no
    var autocapitalizationType: UITextAutocapitalizationType = .none
    var spellCheckingType: UITextSpellCheckingType = .no
    var smartQuotesType: UITextSmartQuotesType = .no
    var smartDashesType: UITextSmartDashesType = .no
    var smartInsertDeleteType: UITextSmartInsertDeleteType = .no
    var keyboardType: UIKeyboardType = .default
    var keyboardAppearance: UIKeyboardAppearance = .dark
    var returnKeyType: UIReturnKeyType = .default
    private let rotulo = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .tertiarySystemBackground
        layer.cornerRadius = 12
        rotulo.text = "Teclado en directo · toca para activar"
        rotulo.font = .preferredFont(forTextStyle: .body)
        rotulo.numberOfLines = 0
        rotulo.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rotulo)
        NSLayoutConstraint.activate([
            rotulo.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            rotulo.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            rotulo.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            rotulo.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
        ])
        isAccessibilityElement = true
        accessibilityLabel = "Teclado en directo"
        accessibilityIdentifier = "tecladoDirecto"
        accessibilityTraits = .button
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(activar)))
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func activar() { alActivar?() }
    func insertText(_ text: String) { if habilitado { alEscribir?(text) } }
    func deleteBackward() { if habilitado { alBorrar?() } }
}
