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
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["Enviar texto"].exists)
        app.typeText("hola")
        let estado = app.staticTexts["estadoPanel"]
        XCTAssertEqual(estado.value as? String, "hola")
        app.typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertEqual(estado.value as? String, "hol")
        app.buttons["Intro"].tap()
        XCTAssertEqual(estado.value as? String, "hol\n")
        foto("04-Teclado-directo")
        app.buttons["Cerrar"].tap()
        barra.swipeLeft()
        XCTAssertTrue(barra.buttons["Atajos"].isHittable)
        foto("05-Barra-desplazada")
        barra.buttons["Atajos"].tap()
        XCTAssertTrue(app.buttons["Monitor izquierdo"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Monitor derecho"].isHittable)
        app.buttons["Monitor izquierdo"].tap()
        XCTAssertEqual(app.staticTexts["estadoPanel"].value as? String, "monitor_left")
        app.buttons["Monitor derecho"].tap()
        XCTAssertEqual(app.staticTexts["estadoPanel"].value as? String, "monitor_right")
        foto("06-Atajos")
    }
}
