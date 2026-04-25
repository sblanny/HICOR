import SwiftUI
import UIKit
import VisionKit

struct DocumentScanView: UIViewControllerRepresentable {
    /// Returns every page the operator captured in this scanner session.
    /// VisionKit's document camera is multi-page by design — the shutter
    /// stays available after each capture until the operator taps Save.
    /// All pages from a single session belong to the same physical
    /// printout, so the caller adds them all to the active printout group.
    let onImagesPicked: ([UIImage]) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagesPicked: onImagesPicked, onCancel: onCancel)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onImagesPicked: ([UIImage]) -> Void
        let onCancel: () -> Void

        init(onImagesPicked: @escaping ([UIImage]) -> Void, onCancel: @escaping () -> Void) {
            self.onImagesPicked = onImagesPicked
            self.onCancel = onCancel
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            guard scan.pageCount > 0 else {
                onCancel()
                return
            }
            var pages: [UIImage] = []
            pages.reserveCapacity(scan.pageCount)
            for i in 0..<scan.pageCount {
                pages.append(scan.imageOfPage(at: i))
            }
            onImagesPicked(pages)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: Error) {
            onCancel()
        }
    }
}
