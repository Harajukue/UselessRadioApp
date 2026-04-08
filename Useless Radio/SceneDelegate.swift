import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }

        window = UIWindow(windowScene: windowScene)
        window?.rootViewController = ViewController()
        window?.makeKeyAndVisible()
    }

    // Handle OAuth deep link callbacks (e.g. uselessradio://login-callback)
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }

        if url.scheme == "uselessradio" {
            if let vc = window?.rootViewController as? ViewController {
                let js = "window.location.href = '\(url.absoluteString)';"
                vc.webView.evaluateJavaScript(js, completionHandler: nil)
            }
        }
    }
}
