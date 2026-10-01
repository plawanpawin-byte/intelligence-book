import UIKit

/// Presents the native iOS share sheet from whatever is on top (works from inside SwiftUI sheets).
@MainActor
enum SharePresenter {
    static func present(_ items: [Any], completion: (() -> Void)? = nil) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard let root = scene?.keyWindow?.rootViewController ?? scene?.windows.first?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController, !presented.isBeingDismissed { top = presented }

        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in completion?() }
        if let popover = controller.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        top.present(controller, animated: true)
    }
}
