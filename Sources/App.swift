import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions
                     opciones: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-reset-ajustes-ui") {
            // Solo preferencias de presentación; nunca IP, clave ni texto del usuario.
            for clave in ["disposicionPad", "alcancePulgar", "botonesVisibles", "barraClic", "franjaScroll", "franjaIzquierda", "oscurecer"] {
                UserDefaults.standard.removeObject(forKey: clave)
            }
        }
        #endif
        let v = UIWindow(frame: UIScreen.main.bounds)
        v.rootViewController = PantallaPrincipal()
        v.overrideUserInterfaceStyle = .dark
        v.makeKeyAndVisible()
        window = v
        return true
    }
}
