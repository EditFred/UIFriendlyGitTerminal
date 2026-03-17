import AppKit
import Foundation

protocol BrowserOpening: Sendable {
    func open(_ url: URL)
}

struct BrowserOpener: BrowserOpening {
    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
