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
    func flush()
    func attachStream(_ stream: NetStream?)
}

extension NetStreamRenderer where Self: NetStreamRendererView {
    func render(image: CMSampleBuffer?) {
        if let view = self as? GLHKView, let sample = image {
            if view.mainLayer.status == .failed {
                view.mainLayer.flush()
            }
            if view.mainLayer.controlTimebase == nil {
                CMTimebaseCreateWithMasterClock(allocator: kCFAllocatorDefault, masterClock: CMClockGetHostTimeClock(), timebaseOut: &view.mainLayer.controlTimebase)
                if let timebase = view.mainLayer.controlTimebase {
                    CMTimebaseSetTime(view.mainLayer.controlTimebase!, time: sample.presentationTimeStamp)
                    CMTimebaseSetRate(view.mainLayer.controlTimebase!, rate: 1.0)
                }
            }
            view.mainLayer.enqueue(sample)
        }
    }
    func flush() {
        if let view = self as? GLHKView {
            view.mainLayer.flushAndRemoveImage()
        }
    }
}
