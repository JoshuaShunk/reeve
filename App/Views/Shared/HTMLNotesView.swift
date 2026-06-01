import SwiftUI

#if canImport(WebKit)
import WebKit
#endif

/// Renders a guest's Markdown/HTML notes in a self-sizing, transparent web view
/// that adapts to light/dark mode.
struct HTMLNotesView: View {
    let html: String
    @State private var height: CGFloat = 44

    var body: some View {
        #if canImport(WebKit)
        WebView(html: document, height: $height)
            .frame(height: height)
        #else
        Text(html)
        #endif
    }

    private var document: String {
        """
        <!doctype html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light dark">
        <style>
          :root { color-scheme: light dark; }
          body { font-family: -apple-system, system-ui, sans-serif; font-size: 15px;
                 margin: 0; padding: 0; color: canvastext; background: transparent;
                 overflow-wrap: anywhere; }
          img { max-width: 100%; height: auto; }
          a { color: #0A84FF; text-decoration: none; }
          h1, h2, h3 { margin: 8px 0; }
          p { margin: 8px 0; }
        </style></head>
        <body>\(html)</body></html>
        """
    }
}

#if canImport(WebKit)
#if os(iOS)
private struct WebView: UIViewRepresentable {
    let html: String
    @Binding var height: CGFloat

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        web.scrollView.isScrollEnabled = false
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.navigationDelegate = context.coordinator
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html
        web.loadHTMLString(html, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator($height) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let height: Binding<CGFloat>
        var loadedHTML: String?
        init(_ height: Binding<CGFloat>) { self.height = height }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.body.scrollHeight") { value, _ in
                if let number = value as? CGFloat { self.height.wrappedValue = max(number, 1) }
                else if let number = value as? Double { self.height.wrappedValue = CGFloat(number) }
            }
        }
    }
}
#elseif os(macOS)
private struct WebView: NSViewRepresentable {
    let html: String
    @Binding var height: CGFloat

    func makeNSView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        web.setValue(false, forKey: "drawsBackground")
        web.navigationDelegate = context.coordinator
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html
        web.loadHTMLString(html, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator($height) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let height: Binding<CGFloat>
        var loadedHTML: String?
        init(_ height: Binding<CGFloat>) { self.height = height }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.body.scrollHeight") { value, _ in
                if let number = value as? Double { self.height.wrappedValue = CGFloat(number) }
            }
        }
    }
}
#endif
#endif
