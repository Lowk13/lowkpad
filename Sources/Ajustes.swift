import Foundation

/// Todo lo ajustable, guardado en el propio móvil.
///
/// La idea es que **una sola compilación sirva para probar veinte
/// configuraciones**: cuantas más cosas se puedan tocar desde la pantalla de
/// ajustes, menos veces hay que volver a compilar.
@propertyWrapper
struct Guardado<T> {
    let clave: String
    let porDefecto: T
    var wrappedValue: T {
        get { UserDefaults.standard.object(forKey: clave) as? T ?? porDefecto }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: clave) }
    }
}

final class Ajustes {
    static let compartidos = Ajustes()
    private init() {}

    // --- conexión ---
    @Guardado(clave: "ip", porDefecto: "192.168.1.41") var ip: String
    @Guardado(clave: "puerto", porDefecto: 8788) var puerto: Int

    // --- movimiento (esto viaja al PC) ---
    @Guardado(clave: "ganancia", porDefecto: 1.8) var ganancia: Double
    @Guardado(clave: "aceleracion", porDefecto: true) var aceleracion: Bool
    @Guardado(clave: "umbralAcel", porDefecto: 450.0) var umbralAcel: Double
    @Guardado(clave: "pendienteAcel", porDefecto: 0.55) var pendienteAcel: Double
    @Guardado(clave: "gananciaScroll", porDefecto: 1.0) var gananciaScroll: Double
    @Guardado(clave: "scrollNatural", porDefecto: false) var scrollNatural: Bool

    // --- formas de hacer clic ---
    @Guardado(clave: "golpecito", porDefecto: true) var golpecito: Bool
    @Guardado(clave: "umbralGolpe", porDefecto: 1.6) var umbralGolpe: Double
    @Guardado(clave: "golpeDerecho", porDefecto: false) var golpeDerecho: Bool
    @Guardado(clave: "volumen", porDefecto: true) var volumen: Bool
    @Guardado(clave: "volumenInvertido", porDefecto: false) var volumenInvertido: Bool
    @Guardado(clave: "tocarClic", porDefecto: true) var tocarClic: Bool
    @Guardado(clave: "segundoDedo", porDefecto: true) var segundoDedo: Bool
    @Guardado(clave: "barraClic", porDefecto: false) var barraClic: Bool
    @Guardado(clave: "mantenerDerecho", porDefecto: true) var mantenerDerecho: Bool
    @Guardado(clave: "dosDedosDerecho", porDefecto: true) var dosDedosDerecho: Bool

    // --- el experimento de la presión ---
    @Guardado(clave: "presion", porDefecto: false) var presion: Bool
    @Guardado(clave: "presionAbajo", porDefecto: 1.22) var presionAbajo: Double
    @Guardado(clave: "presionArriba", porDefecto: 1.10) var presionArriba: Double

    // --- pantalla y tacto ---
    @Guardado(clave: "haptico", porDefecto: true) var haptico: Bool
    @Guardado(clave: "franjaScroll", porDefecto: true) var franjaScroll: Bool
    @Guardado(clave: "oscurecer", porDefecto: 0.0) var oscurecer: Double
}
