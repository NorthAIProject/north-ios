import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The Share sheet's entry point: reads what was shared, then hands it to
/// `ShareView`. UIKit only because the extension point asks for a view
/// controller; everything the person sees is SwiftUI.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        Task { @MainActor in
            let shared = await SharedItem.read(from: extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            let view = ShareView(item: shared) { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            }
            let host = UIHostingController(rootView: view)
            addChild(host)
            host.view.frame = self.view.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            self.view.addSubview(host.view)
            host.didMove(toParent: self)
        }
    }
}

/// What arrived from the other app: a link, some text, or both (Safari shares
/// the page's URL with its title as the item's text).
struct SharedItem: Equatable {
    var url: URL?
    var title: String
    var text: String

    var isEmpty: Bool { url == nil && text.isEmpty }

    /// Short enough to be a thing that happened ("ran 5k, slept badly"), and
    /// so worth offering to log rather than only to save.
    var isLoggable: Bool { url == nil && !text.isEmpty && text.count <= 280 }

    @MainActor
    static func read(from items: [NSExtensionItem]) async -> SharedItem {
        var out = SharedItem(url: nil, title: "", text: "")
        for item in items {
            if let title = item.attributedTitle?.string, out.title.isEmpty { out.title = title }
            if let body = item.attributedContentText?.string, out.text.isEmpty { out.text = body }
            for provider in item.attachments ?? [] {
                if out.url == nil, provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                    out.url = url
                } else if out.text.isEmpty, provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                          let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                    out.text = text
                }
            }
        }
        out.text = out.text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Some apps share a link as plain text; treat it as the link it is.
        if out.url == nil, let url = URL(string: out.text), url.scheme?.hasPrefix("http") == true {
            out.url = url
            out.text = ""
        }
        return out
    }
}
