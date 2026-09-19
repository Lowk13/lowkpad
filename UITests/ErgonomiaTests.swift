import XCTest

final class ErgonomiaTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["-ui-testing", "-reset-ajustes-ui"]
        app.launch()
        XCTAssertTrue(app.otherElements["trackpad"].waitForExistence(timeout: 10))
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        app.terminate()
        super.tearDown()
    }

    private func foto(_ nombre: String) {
        let adjunto = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        adjunto.name = nombre
        adjunto.lifetime = .keepAlways
        add(adjunto)
    }

    private func esperar(_ condicion: @escaping () -> Bool,
                         archivo: StaticString = #filePath, linea: UInt = #line) {
        let predicado = NSPredicate { _, _ in condicion() }
        let espera = XCTNSPredicateExpectation(predicate: predicado, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [espera], timeout: 5), .completed,
                       file: archivo, line: linea)
    }

    private func valor(_ identificador: String, _ esperado: String,
                       archivo: StaticString = #filePath, linea: UInt = #line) {
        esperar({ self.app.buttons[identificador].value as? String == esperado },
                archivo: archivo, linea: linea)
    }

    private func abrirSelector() {
        let boton = app.buttons["disposicionPad"]
        XCTAssertTrue(boton.isHittable)
        boton.tap()
        XCTAssertTrue(app.buttons["modo-mesa"].waitForExistence(timeout: 5))
    }

    private func cerrarSelector() {
        XCTAssertTrue(app.buttons["Listo"].isHittable)
        app.buttons["Listo"].tap()
        esperar { !self.app.buttons["modo-mesa"].exists }
    }

    private func mostrarEnSelector(_ elemento: XCUIElement) {
        let scroll = app.scrollViews.containing(.button, identifier: "modo-mesa").firstMatch
        XCTAssertTrue(scroll.exists)
        for _ in 0..<5 {
            let rect = elemento.frame
            if elemento.isHittable && rect.minY >= scroll.frame.minY && rect.maxY <= scroll.frame.maxY {
                return
            }
            if rect.minY < scroll.frame.minY { scroll.swipeDown() }
            else { scroll.swipeUp() }
        }
        XCTAssertTrue(elemento.isHittable)
    }

    private func dentroDePantalla(_ elemento: XCUIElement,
                                  archivo: StaticString = #filePath, linea: UInt = #line) {
        let pantalla = app.frame
        let rect = elemento.frame
        XCTAssertGreaterThan(rect.width, 0, file: archivo, line: linea)
        XCTAssertGreaterThan(rect.height, 0, file: archivo, line: linea)
        XCTAssertGreaterThanOrEqual(rect.minX, pantalla.minX - 1, file: archivo, line: linea)
        XCTAssertGreaterThanOrEqual(rect.minY, pantalla.minY - 1, file: archivo, line: linea)
        XCTAssertLessThanOrEqual(rect.maxX, pantalla.maxX + 1, file: archivo, line: linea)
        XCTAssertLessThanOrEqual(rect.maxY, pantalla.maxY + 1, file: archivo, line: linea)
    }

    private func objetivoTactil(_ boton: XCUIElement,
                               archivo: StaticString = #filePath, linea: UInt = #line) {
        XCTAssertTrue(boton.isHittable, file: archivo, line: linea)
        XCTAssertGreaterThanOrEqual(boton.frame.width, 44, file: archivo, line: linea)
        XCTAssertGreaterThanOrEqual(boton.frame.height, 44, file: archivo, line: linea)
        dentroDePantalla(boton, archivo: archivo, linea: linea)
    }

    func testPosturasAlturaYPersistencia() {
        let pad = app.otherElements["trackpad"]
        let mesa = pad.frame
        foto("07-Ergonomia-mesa")

        abrirSelector()
        app.buttons["modo-derecha"].tap()
        mostrarEnSelector(app.segmentedControls["alturaPulgar"])
        app.segmentedControls["alturaPulgar"].buttons["Compacta"].tap()
        mostrarEnSelector(app.switches["botonesVisibles"])
        app.switches["botonesVisibles"].tap()
        mostrarEnSelector(app.switches["scrollLateral"])
        app.switches["scrollLateral"].tap()
        cerrarSelector()
        let derecha = pad.frame
        XCTAssertLessThan(derecha.height, mesa.height - 10)
        XCTAssertLessThan(derecha.width, mesa.width - 4)
        XCTAssertGreaterThan(derecha.midX, mesa.midX + 4)
        XCTAssertFalse(app.buttons["clicIzquierdo"].isHittable)
        XCTAssertFalse(app.buttons["clicDerecho"].isHittable)
        dentroDePantalla(pad)
        foto("08-Ergonomia-derecha-compacta")

        // El segundo arranque conserva preferencias y no ejecuta el reset de pruebas.
        app.terminate()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        XCTAssertTrue(pad.waitForExistence(timeout: 10))
        XCTAssertEqual(pad.frame.minX, derecha.minX, accuracy: 2)
        XCTAssertEqual(pad.frame.height, derecha.height, accuracy: 2)

        abrirSelector()
        mostrarEnSelector(app.segmentedControls["alturaPulgar"])
        XCTAssertTrue(app.segmentedControls["alturaPulgar"].buttons["Compacta"].isSelected)
        mostrarEnSelector(app.switches["botonesVisibles"])
        XCTAssertEqual(app.switches["botonesVisibles"].value as? String, "0")
        app.switches["botonesVisibles"].tap()
        mostrarEnSelector(app.switches["scrollLateral"])
        XCTAssertEqual(app.switches["scrollLateral"].value as? String, "0")
        app.switches["scrollLateral"].tap()
        mostrarEnSelector(app.buttons["modo-izquierda"])
        app.buttons["modo-izquierda"].tap()
        mostrarEnSelector(app.segmentedControls["alturaPulgar"])
        app.segmentedControls["alturaPulgar"].buttons["Amplia"].tap()
        cerrarSelector()
        let izquierda = pad.frame
        XCTAssertLessThan(izquierda.midX, mesa.midX - 4)
        XCTAssertGreaterThan(izquierda.height, derecha.height + 10)
        dentroDePantalla(pad)
        foto("09-Ergonomia-izquierda-amplia")
    }

    func testPrecisionYArrastreSeLiberanAlCambiarContexto() {
        let arrastre = app.buttons["arrastre"]
        objetivoTactil(arrastre)
        objetivoTactil(app.buttons["precision"])
        objetivoTactil(app.buttons["clicIzquierdo"])
        objetivoTactil(app.buttons["clicDerecho"])
        valor("precision", "inactivo")
        app.buttons["precision"].tap()
        valor("precision", "activo")
        app.buttons["precision"].tap()
        valor("precision", "inactivo")

        arrastre.tap()
        valor("arrastre", "activo")
        foto("10-Arrastre-activado")
        app.scrollViews["barraHerramientas"].buttons["Multimedia"].tap()
        XCTAssertTrue(app.buttons["Cerrar"].waitForExistence(timeout: 5))
        app.buttons["Cerrar"].tap()
        valor("arrastre", "inactivo")

        arrastre.tap()
        valor("arrastre", "activo")
        abrirSelector()
        app.buttons["modo-derecha"].tap()
        cerrarSelector()
        valor("arrastre", "inactivo")

        arrastre.tap()
        valor("arrastre", "activo")
        XCUIDevice.shared.orientation = .landscapeLeft
        esperar { self.app.frame.width > self.app.frame.height }
        valor("arrastre", "inactivo")
        dentroDePantalla(app.otherElements["trackpad"])
        foto("11-Arrastre-liberado-al-girar")
    }

    func testHorizontalSelectorYBarraAccesibles() {
        XCUIDevice.shared.orientation = .landscapeLeft
        esperar { self.app.frame.width > self.app.frame.height }
        let pad = app.otherElements["trackpad"]
        dentroDePantalla(pad)
        let barra = app.scrollViews["barraHerramientas"]
        dentroDePantalla(barra)
        // El pad y las herramientas quedan separados incluso con poca altura.
        XCTAssertLessThanOrEqual(pad.frame.maxY, barra.frame.minY + 1)
        objetivoTactil(app.buttons["disposicionPad"])
        objetivoTactil(app.buttons["clicIzquierdo"])
        objetivoTactil(app.buttons["clicDerecho"])
        objetivoTactil(barra.buttons["Multimedia"])
        objetivoTactil(barra.buttons["Portapapeles"])
        objetivoTactil(barra.buttons["Teclado"])
        foto("12-Ergonomia-horizontal")

        abrirSelector()
        mostrarEnSelector(app.buttons["modo-mesa"])
        objetivoTactil(app.buttons["modo-mesa"])
        mostrarEnSelector(app.buttons["modo-derecha"])
        objetivoTactil(app.buttons["modo-derecha"])
        mostrarEnSelector(app.buttons["modo-izquierda"])
        objetivoTactil(app.buttons["modo-izquierda"])
        dentroDePantalla(app.buttons["Listo"])
        foto("13-Selector-horizontal")
        app.buttons["modo-izquierda"].tap()
        cerrarSelector()
        dentroDePantalla(pad)

        if !barra.buttons["Atajos"].isHittable { barra.swipeLeft() }
        objetivoTactil(barra.buttons["Atajos"])
        barra.buttons["Atajos"].tap()
        XCTAssertTrue(app.buttons["Monitor izquierdo"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Monitor derecho"].isHittable)
        foto("14-Atajos-horizontal")
    }
}
