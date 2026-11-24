import AVFoundation
import SwiftUI
import UIKit

/// Maps image-space coordinates (upright for the holder) onto the portrait viewfinder.
/// `rotation` is how far the image must turn clockwise to sit on screen: 0 in portrait, 90 or 270 in landscape.
struct ViewMap {
    let size: CGSize
    let r: Int

    init(size: CGSize, rotation: Double) {
        self.size = size
        let snapped = Int((rotation / 90).rounded()) * 90
        r = ((snapped % 360) + 360) % 360
    }

    private func norm(_ p: Vec2) -> (Double, Double) {
        switch r {
        case 90: return (1 - p.y, p.x)
        case 180: return (1 - p.x, 1 - p.y)
        case 270: return (p.y, 1 - p.x)
        default: return (p.x, p.y)
        }
    }

    func point(_ p: Vec2) -> CGPoint {
        let n = norm(p)
        return CGPoint(x: n.0 * size.width, y: n.1 * size.height)
    }

    func rect(_ rect: Rect) -> CGRect {
        let a = point(Vec2(rect.minX, rect.minY))
        let b = point(Vec2(rect.maxX, rect.maxY))
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    /// Screen angle (degrees clockwise from up) for a direction given in image space.
    func angle(_ imageAngle: Double) -> Double { imageAngle + Double(r) }
}

/// Hosts the camera's preview layer.
final class PreviewHostView: UIView {
    var previewLayer: AVCaptureVideoPreviewLayer? {
        didSet {
            oldValue?.removeFromSuperlayer()
            if let previewLayer { layer.addSublayer(previewLayer) }
            setNeedsLayout()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer?.frame = bounds
        CATransaction.commit()
    }
}

struct CameraPreview: UIViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer

    func makeUIView(context: Context) -> PreviewHostView {
        let v = PreviewHostView()
        v.backgroundColor = .black
        v.previewLayer = previewLayer
        return v
    }

    func updateUIView(_ uiView: PreviewHostView, context: Context) {}
}

extension Arrow {
    /// SF Symbol and the image-space direction it should point (degrees clockwise from up), if it rotates.
    var symbol: (name: String, angle: Double?) {
        switch self {
        case .left: return ("arrow.up", 270)
        case .right: return ("arrow.up", 90)
        case .up: return ("arrow.up", 0)
        case .down: return ("arrow.up", 180)
        case .raise: return ("arrow.up.to.line", 0)
        case .lower: return ("arrow.down.to.line", 0)
        case .tiltUp: return ("chevron.up", 0)
        case .tiltDown: return ("chevron.down", 0)
        case .closer: return ("arrow.down.right.and.arrow.up.left", nil)
        case .back: return ("arrow.up.left.and.arrow.down.right", nil)
        case .rotateCW: return ("arrow.clockwise", nil)
        case .rotateCCW: return ("arrow.counterclockwise", nil)
        case .turn: return ("arrow.triangle.2.circlepath", nil)
        }
    }

    /// Where on the frame to draw it: toward the edge it points at.
    var offset: CGVector {
        switch self {
        case .left: return CGVector(dx: -1, dy: 0)
        case .right: return CGVector(dx: 1, dy: 0)
        case .up, .raise, .tiltUp: return CGVector(dx: 0, dy: -1)
        case .down, .lower, .tiltDown: return CGVector(dx: 0, dy: 1)
        default: return CGVector(dx: 0, dy: -0.55)
        }
    }
}
