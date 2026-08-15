import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions
                     opciones: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let v = UIWindow(frame: UIScreen.main.bounds)
        v.rootViewController = PantallaPrincipal()
        v.overrideUserInterfaceStyle = .dark
        v.makeKeyAndVisible()
        window = v
        return true
    }
}
