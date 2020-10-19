import AVFoundation
import Foundation
#if canImport(AppKit)
import AppKit
#endif

#if os(macOS)
typealias NetStreamRendererView = NSView
#else
import UIKit
typealias NetStreamRendererView = UIView
#endif

protocol NetStreamRenderer: class {
#if os(iOS) || os(macOS)
    var orientation: AVCaptureVideoOrientation { get set }
    var position: AVCaptureDevice.Position { get set }
#endif
    var displayImage: CIImage? { get set }
    var videoFormatDescription: CMVideoFormatDescription? { get }

    func render(image: CMSampleBuffer?)
    func attachStream(_ stream: NetStream?)
}

extension NetStreamRenderer where Self: NetStreamRendererView {
    func render(image: CMSampleBuffer?) {
        if Thread.isMainThread {
            //displayImage = image
//            #if os(macOS)
//            self.needsDisplay = true
//            #else
//            self.setNeedsDisplay()
//            #endif
            if let view = self as? GLHKView, let sample = image {
                view.mainLayer.enqueue(sample)
            }
        } else {
            DispatchQueue.main.async {
                self.render(image: image)
            }
        }
    }
}
