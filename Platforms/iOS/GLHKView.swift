#if os(iOS)

import AVFoundation
import GLKit

open class GLHKView: UIView, NetStreamRenderer {
    var orientation: AVCaptureVideoOrientation {
        get { .portrait
        }
        set {
            
        }
    }
    
    var position: AVCaptureDevice.Position {
        get {
            return .front
        } set {
            
        }
    }
    
    var videoFormatDescription: CMVideoFormatDescription? {
        return nil
    }
    
    var displayImage: CIImage?
    
    let mainLayer = AVSampleBufferDisplayLayer()
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        
        mainLayer.videoGravity = .resizeAspectFill
        
        layer.addSublayer(mainLayer)
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    open override func layoutSubviews() {
        super.layoutSubviews()
        
        mainLayer.frame = bounds
    }
    
    private weak var currentStream: NetStream? {
        didSet {
            oldValue?.mixer.videoIO.renderer = nil
        }
    }

    open func attachStream(_ stream: NetStream?) {
        if let stream: NetStream = stream {
            stream.lockQueue.async {
                stream.mixer.videoIO.renderer = self
                stream.mixer.startRunning()
            }
        }
        currentStream = stream
    }
}

#endif
