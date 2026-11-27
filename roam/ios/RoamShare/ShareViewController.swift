import MapKit
import Observation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Share sheet target: "Share" a place in Google Maps (or Apple Maps, or any link) and pick roam.
/// The place is resolved to coordinates here and dropped in the shared inbox; the app picks it up on its next wake.
final class ShareViewController: UIViewController {
    private let state = ShareState()

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareView(state: state) { [weak self] in self?.finish() })
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
        Task { await process() }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func process() async {
        var text = ""
        var link: String?
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        for item in items {
            if let t = item.attributedContentText?.string, !t.isEmpty { text += t + "\n" }
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                    link = link ?? url.absoluteString
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                          let t = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                    text += t + "\n"
                }
            }
        }
        let parsed = MapsLink.parseShareText(text)
        let url = link ?? parsed.url
        var name = parsed.name
        var coord: Coordinate?
        var finalURL = url

        if let u = url {
            let full = await Self.expand(u)
            finalURL = full
            if GoogleList.listID(in: full) != nil || GoogleList.listID(in: u) != nil {
                // A whole list: the app imports it (thousands of places) the next time it opens.
                SharedInbox.append(Place(name: name ?? "Google Maps list", kind: .saved, source: .share,
                                         lists: [GoogleList.marker], url: full))
                await MainActor.run {
                    state.message = "List sent to roam. Open roam to import all its places."
                    state.done = true
                }
                return
            }
            coord = MapsLink.coordinate(in: full)
            if name == nil { name = MapsLink.placeName(in: full) ?? MapsLink.queryText(in: full) }
        }
        if coord == nil, let n = name {
            let query = [n, parsed.address].compactMap { $0 }.joined(separator: ", ")
            let req = MKLocalSearch.Request()
            req.naturalLanguageQuery = query
            if let item = try? await MKLocalSearch(request: req).start().mapItems.first {
                let c = item.placemark.coordinate
                coord = Coordinate(lat: c.latitude, lng: c.longitude)
            }
        }
        guard let placeName = name ?? (coord != nil ? "Shared place" : nil) else {
            await MainActor.run { state.message = "That share did not include a place."; state.done = true }
            return
        }
        let place = Place(name: placeName, coordinate: coord, kind: .saved, source: .share, lists: ["Shared to roam"],
                          address: parsed.address, url: finalURL)
        SharedInbox.append(place)
        await MainActor.run {
            state.message = coord == nil ? "Saved \(placeName). roam will find it on the map." : "Saved \(placeName)"
            state.done = true
        }
        try? await Task.sleep(for: .seconds(1.2))
        await MainActor.run { finish() }
    }

    static func expand(_ url: String) async -> String {
        guard MapsLink.isShortLink(url), let u = URL(string: url) else { return url }
        var r = URLRequest(url: u)
        r.setValue(GoogleList.browserUserAgent, forHTTPHeaderField: "User-Agent")
        guard let (_, resp) = try? await URLSession.shared.data(for: r), let final = resp.url?.absoluteString else { return url }
        return MapsLink.unwrapConsent(final)
    }
}

@Observable
final class ShareState {
    var message = "Saving to roam…"
    var done = false
}

struct ShareView: View {
    let state: ShareState
    var close: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            VStack(spacing: 14) {
                Image(systemName: state.done ? "checkmark.circle.fill" : "mappin.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color(red: 0.94, green: 0.40, blue: 0.16))
                Text(state.message).font(.headline).multilineTextAlignment(.center)
                if state.done { Button("Done", action: close).buttonStyle(.borderedProminent).tint(Color(red: 0.94, green: 0.40, blue: 0.16)) }
                else { ProgressView() }
            }
            .padding(28)
            .frame(maxWidth: 320)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(uiColor: .systemBackground)))
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.25).ignoresSafeArea())
    }
}
