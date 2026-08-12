import UIKit
import SwiftUI

final class PhoneSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(
            rootView: RootView().environmentObject(VehicleDataStore.shared))
        window.overrideUserInterfaceStyle = .dark   // night-drive UI is deliberately dark
        self.window = window
        window.makeKeyAndVisible()
    }
}
