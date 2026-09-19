import XCTest
import UIKit
@testable import LowkPad

/// Contactos controlados para verificar el estado real de Trackpad sin depender
/// de la sincronización de dos gestos del simulador ni de una conexión al PC.
private final class ToquePrueba: UITouch {
    var punto: CGPoint
    private let instante: TimeInterval

    init(_ x: CGFloat, _ y: CGFloat, orden: TimeInterval = 1) {
        punto = CGPoint(x: x, y: y)
        instante = orden
        super.init()
    }

    override func location(in view: UIView?) -> CGPoint { punto }
    override var timestamp: TimeInterval { instante }
    override var majorRadius: CGFloat { 5 }
}

private final class RegistroGestos: TrackpadDelegado {
    var movimientos: [CGPoint] = []
    var scroll: [CGPoint] = []
    var botones: [Bool] = []
    var clics: [String] = []

    func trackpadMovio(dx: Double, dy: Double) { movimientos.append(CGPoint(x: dx, y: dy)) }
    func trackpadScroll(dx: Double, dy: Double) { scroll.append(CGPoint(x: dx, y: dy)) }
    func trackpadBoton(_ cual: String, pulsado: Bool) { botones.append(pulsado) }
    func trackpadClic(_ cual: String) { clics.append(cual) }
    func trackpadNota(_ texto: String, derecho: Bool) {}
    func trackpadHuella(_ radio: Double, base: Double, minimo: Double, maximo: Double) {}
}

@MainActor
final class TrackpadTests: XCTestCase {
    private var pad: Trackpad!
    private var registro: RegistroGestos!
    private var anteriores: [String: Any] = [:]
    private let claves = ["franjaScroll", "tocarClic", "segundoDedo", "mantenerDerecho", "dosDedosDerecho", "presion"]

    override func setUp() {
        super.setUp()
        let d = UserDefaults.standard
        for clave in claves { anteriores[clave] = d.object(forKey: clave) }
        let a = Ajustes.compartidos
        a.franjaScroll = false
        a.tocarClic = true
        a.segundoDedo = true
        a.mantenerDerecho = true
        a.dosDedosDerecho = true
        a.presion = false
        pad = Trackpad(frame: CGRect(x: 0, y: 0, width: 320, height: 500))
        registro = RegistroGestos()
        pad.delegado = registro
    }

    override func tearDown() {
        pad.reiniciar()
        for clave in claves {
            if let valor = anteriores[clave] { UserDefaults.standard.set(valor, forKey: clave) }
            else { UserDefaults.standard.removeObject(forKey: clave) }
        }
        anteriores.removeAll()
        super.tearDown()
    }

    private func empezar(_ dedos: UITouch...) { pad.touchesBegan(Set(dedos), with: nil) }
    private func mover(_ dedos: UITouch...) { pad.touchesMoved(Set(dedos), with: nil) }
    private func acabar(_ dedos: UITouch...) { pad.touchesEnded(Set(dedos), with: nil) }

    private func esperar(_ segundos: TimeInterval) {
        let e = expectation(description: "Temporizador del gesto")
        DispatchQueue.main.asyncAfter(deadline: .now() + segundos) { e.fulfill() }
        wait(for: [e], timeout: segundos + 1)
    }

    func testToqueSimpleSoloHaceUnClic() {
        let dedo = ToquePrueba(100, 100)
        empezar(dedo)
        acabar(dedo)
        XCTAssertEqual(registro.clics, ["l"])
        XCTAssertTrue(registro.botones.isEmpty)
    }

    func testDosDedosHacenUnSoloClicDerechoAlLevantarEnCualquierOrden() {
        for primeroPrincipal in [true, false] {
            pad.reiniciar()
            registro.clics.removeAll()
            let p = ToquePrueba(100, 100, orden: 1)
            let s = ToquePrueba(180, 100, orden: 2)
            empezar(p, s)
            acabar(primeroPrincipal ? p : s)
            acabar(primeroPrincipal ? s : p)
            XCTAssertEqual(registro.clics, ["r"])
            XCTAssertTrue(registro.botones.isEmpty)
        }
    }

    func testScrollNoMueveCursorAntesNiDespuesDeLevantarUnDedo() {
        let p = ToquePrueba(100, 100, orden: 1)
        let s = ToquePrueba(180, 100, orden: 2)
        empezar(p, s)
        p.punto.y += 4
        s.punto.y += 4
        mover(p, s)
        XCTAssertTrue(registro.movimientos.isEmpty)
        XCTAssertTrue(registro.scroll.isEmpty)
        p.punto.y += 20
        s.punto.y += 20
        mover(p, s)
        XCTAssertEqual(registro.scroll.count, 1)
        acabar(s)
        p.punto.y += 25
        mover(p)
        acabar(p)
        XCTAssertTrue(registro.movimientos.isEmpty)
        XCTAssertTrue(registro.clics.isEmpty)
        XCTAssertTrue(registro.botones.isEmpty)

        let nuevo = ToquePrueba(100, 100)
        empezar(nuevo)
        nuevo.punto.x += 20
        mover(nuevo)
        acabar(nuevo)
        XCTAssertEqual(registro.movimientos.count, 1)
    }

    func testBotonExternoPermiteApuntarEnFranjaSinScrollNiClicAlSoltar() {
        Ajustes.compartidos.franjaScroll = true
        pad.botonExternoPulsado = true
        let p = ToquePrueba(Ajustes.compartidos.scrollALaIzquierda ? 2 : 318, 100)
        empezar(p)
        p.punto.y += 20
        mover(p)
        pad.botonExternoPulsado = false
        acabar(p)
        XCTAssertEqual(registro.movimientos.count, 1)
        XCTAssertTrue(registro.scroll.isEmpty)
        XCTAssertTrue(registro.clics.isEmpty)
        XCTAssertTrue(registro.botones.isEmpty)

        let nuevo = ToquePrueba(150, 100)
        empezar(nuevo)
        acabar(nuevo)
        XCTAssertEqual(registro.clics, ["l"])
    }

    func testArrastreTapYMedioNoSeConvierteEnScrollConSegundoDedo() {
        let toque = ToquePrueba(100, 100)
        empezar(toque)
        acabar(toque)
        let p = ToquePrueba(100, 100, orden: 1)
        let s = ToquePrueba(180, 100, orden: 2)
        empezar(p)
        XCTAssertEqual(registro.botones, [true])
        empezar(s)
        p.punto.y += 20
        s.punto.y += 20
        mover(p, s)
        XCTAssertEqual(registro.movimientos.count, 1)
        XCTAssertTrue(registro.scroll.isEmpty)
        acabar(p)
        acabar(s)
        XCTAssertEqual(registro.botones, [true, false])
        XCTAssertEqual(registro.clics, ["l"])
    }

    func testArrastreSecundarioSeSueltaAlPerderDedoPrincipal() {
        let p = ToquePrueba(100, 100, orden: 1)
        let s = ToquePrueba(180, 100, orden: 2)
        empezar(p)
        esperar(0.15)
        empezar(s)
        esperar(0.30)
        XCTAssertEqual(registro.botones, [true])
        acabar(p)
        XCTAssertEqual(registro.botones, [true, false])
        let nuevo = ToquePrueba(100, 100, orden: 3)
        empezar(nuevo)
        nuevo.punto.x += 20
        mover(nuevo)
        XCTAssertTrue(registro.movimientos.isEmpty)
        acabar(s, nuevo)
        XCTAssertTrue(registro.clics.isEmpty)
    }

    func testTercerDedoNoGeneraClicsYExigeLevantarTodos() {
        let p = ToquePrueba(100, 100, orden: 1)
        let s = ToquePrueba(180, 100, orden: 2)
        let tercero = ToquePrueba(230, 100, orden: 3)
        empezar(p, s, tercero)
        p.punto.y += 25
        mover(p)
        acabar(s)
        acabar(p, tercero)
        XCTAssertTrue(registro.clics.isEmpty)
        XCTAssertTrue(registro.botones.isEmpty)
        XCTAssertTrue(registro.movimientos.isEmpty)
        XCTAssertTrue(registro.scroll.isEmpty)
        let nuevo = ToquePrueba(100, 100)
        empezar(nuevo)
        acabar(nuevo)
        XCTAssertEqual(registro.clics, ["l"])
    }

    func testCancelacionParcialNoReconoceHastaLevantarRestantes() {
        let p = ToquePrueba(100, 100, orden: 1)
        let s = ToquePrueba(180, 100, orden: 2)
        empezar(p, s)
        pad.touchesCancelled([p], with: nil)
        let nuevo = ToquePrueba(100, 100, orden: 3)
        empezar(nuevo)
        nuevo.punto.x += 20
        mover(nuevo)
        acabar(s, nuevo)
        XCTAssertTrue(registro.clics.isEmpty)
        XCTAssertTrue(registro.movimientos.isEmpty)
        XCTAssertTrue(registro.botones.isEmpty)
    }

    func testBotonExternoCancelaArrastreInternoUnaSolaVez() {
        let toque = ToquePrueba(100, 100)
        empezar(toque)
        acabar(toque)
        let p = ToquePrueba(100, 100)
        empezar(p)
        XCTAssertEqual(registro.botones, [true])
        pad.botonExternoPulsado = true
        XCTAssertEqual(registro.botones, [true, false])
        p.punto.x += 20
        mover(p)
        acabar(p)
        pad.reiniciar()
        XCTAssertEqual(registro.botones, [true, false])
        XCTAssertEqual(registro.clics, ["l"])
        XCTAssertEqual(registro.movimientos.count, 1)
    }
}
