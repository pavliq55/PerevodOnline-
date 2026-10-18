import SwiftUI
import WebKit
import UIKit

let appURL = URL(string: "https://perevod.molly-trade.workers.dev/")!

struct WebScreen: UIViewRepresentable {
    func makeCoordinator() -> Bridge { Bridge() }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []      // автоозвучка без касания
        cfg.applicationNameForUserAgent = "PerevodApp/1.0"     // страница узнаёт, что она в приложении
        cfg.websiteDataStore = .default()                      // PIN и история сохраняются
        cfg.userContentController.add(context.coordinator, name: "native")
        let web = WKWebView(frame: .zero, configuration: cfg)
        web.uiDelegate = context.coordinator
        web.navigationDelegate = context.coordinator
        web.scrollView.bounces = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.isOpaque = false
        web.backgroundColor = .systemBackground
        web.allowsLinkPreview = false
        #if DEBUG
        if #available(iOS 16.4, *) { web.isInspectable = true }
        #endif
        context.coordinator.web = web
        web.load(URLRequest(url: appURL))
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Audio.setup()                                       // после звонка/Siri звук снова в нужном режиме
        }
        let bridge = context.coordinator
        NotificationCenter.default.addObserver(forName: PendingAction.note, object: nil, queue: .main) { _ in bridge.runPending() }
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

/// Мост страница ↔ айфон: window.webkit.messageHandlers.native.postMessage({t: "tick"})
final class Bridge: NSObject, WKScriptMessageHandler, WKUIDelegate, WKNavigationDelegate {
    weak var web: WKWebView?
    private var pageReady = false

    /// Siri / кнопка действия: передать действие странице, когда она готова (сообщение {t:"ready"}).
    func runPending() {
        guard pageReady, let web else { return }
        guard let a = PendingAction.take() else { return }
        web.evaluateJavaScript("window.nativeAction && window.nativeAction('\(a)')")
    }
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let success = UINotificationFeedbackGenerator()

    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let m = message.body as? [String: Any], let t = m["t"] as? String else { return }
        switch t {
        case "tick": light.impactOccurred(intensity: 0.7)
        case "done": success.notificationOccurred(.success)
        case "audio": Audio.setup()
        case "ready": pageReady = true; runPending()
        case "lang": if let c = m["to"] as? String { PartnerLang.set(c) }
        case "offlinePrep": NotificationCenter.default.post(name: .offlinePrep, object: nil)
        default: break
        }
    }

    // Микрофон и камера для страницы — без второго вопроса (айфон уже спросил разрешение у приложения).
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(origin.host == appURL.host ? .grant : .prompt)
    }

    // Чужие ссылки — в Safari, наш сайт — внутри.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let u = action.request.url, u.host == appURL.host, u.path == "/privacy" {   // политика — поверх, с кнопкой «Готово»
            presentSafari(u); decisionHandler(.cancel); return
        }
        if let u = action.request.url, let h = u.host, h != appURL.host, action.navigationType == .linkActivated {
            UIApplication.shared.open(u); decisionHandler(.cancel); return
        }
        decisionHandler(.allow)
    }

    // window.open (например, страница «Показать») — открываем в этом же окне.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let u = navigationAction.request.url {
            if u.path == "/privacy" || u.host != appURL.host { presentSafari(u) } else { webView.load(navigationAction.request) }
        }
        return nil
    }

    // Нет сети при запуске — повторить через 3 с, а не белый экран.
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let html = """
        <html><body style="font:20px -apple-system;display:flex;height:100vh;align-items:center;justify-content:center;text-align:center;color:#888">
        Нет интернета<br>Подключусь, как только появится…</body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { webView.load(URLRequest(url: appURL)) }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { pageReady = false; webView.load(URLRequest(url: appURL)) }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { pageReady = false }
}
