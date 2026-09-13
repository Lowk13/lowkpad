import XCTest

final class PanelesTests: XCTestCase {
    func foto(_ nombre: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = nombre
        a.lifetime = .keepAlways
        add(a)
    }
    func testPanelesEnPantalla() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        let barra = app.scrollViews["barraHerramientas"]
        XCTAssertTrue(barra.waitForExistence(timeout: 10))
        XCTAssertTrue(barra.buttons["Multimedia"].isHittable)
        XCTAssertTrue(barra.buttons["Portapapeles"].isHittable)
        XCTAssertTrue(barra.buttons["Teclado"].isHittable)
        XCTAssertLessThan(barra.frame.maxY, app.frame.maxY)
        foto("01-Raton-barra")
        barra.buttons["Multimedia"].tap()
        XCTAssertTrue(app.buttons["Play / pausa"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Anterior"].isHittable)
        foto("02-Multimedia")
        app.buttons["Cerrar"].tap()
        barra.buttons["Portapapeles"].tap()
        XCTAssertTrue(app.buttons["Recuperar del PC"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Copiar al iPhone"].isHittable)
        XCTAssertTrue(app.buttons["Enviar al portapapeles del PC"].isHittable)
        foto("03-Portapapeles")
        app.buttons["Cerrar"].tap()
        barra.buttons["Teclado"].tap()
        let editor = app.textViews["editorTexto"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        foto("04-Teclado-panel")
        editor.tap()
        editor.typeText("Hola desde iPhone")
        XCTAssertEqual(editor.value as? String, "Hola desde iPhone")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertLessThanOrEqual(editor.frame.maxY, app.keyboards.firstMatch.frame.minY + 1)
        foto("05-Teclado-abierto")
    }
}
