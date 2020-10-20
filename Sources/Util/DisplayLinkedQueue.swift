import AVFoundation

#if os(macOS)
#else
    typealias DisplayLink = CADisplayLink
#endif

protocol DisplayLinkedQueueDelegate: class {
    func queue(_ buffer: CMSampleBuffer)
    func empty()
}

protocol DisplayLinkedQueueClockReference: class {
    var duration: TimeInterval { get }
}

public class DisplayLinkedQueue: NSObject {
    static let defaultPreferredFramesPerSecond = 0

    public var offset: TimeInterval = 0
    
    public func reset() {
        lockQueue.async {
            self.buffer.removeAll()
            self.buffer = .init(256)
        }
    }
    
    var isPaused: Bool {
        get { displayLink?.isPaused ?? false }
        set { displayLink?.isPaused = newValue }
    }
    var duration: TimeInterval {
        (displayLink?.timestamp ?? 0.0) - timestamp
    }
    weak var delegate: DisplayLinkedQueueDelegate?
    weak var clockReference: DisplayLinkedQueueClockReference?
    private var timestamp: TimeInterval = 0.0
    private var buffer: CircularBuffer<CMSampleBuffer> = .init(256)
    private var displayLink: DisplayLink? {
        didSet {
            oldValue?.invalidate()
            guard let displayLink = displayLink else {
                return
            }
            displayLink.isPaused = true
            if #available(iOS 10.0, tvOS 10.0, *) {
                displayLink.preferredFramesPerSecond = DisplayLinkedQueue.defaultPreferredFramesPerSecond
            } else {
                displayLink.frameInterval = 1
            }
            displayLink.add(to: .main, forMode: .common)
        }
    }
    private let lockQueue = DispatchQueue(label: "com.haishinkit.HaishinKit.DisplayLinkedQueue.lock")
    public var isRunning: Atomic<Bool> = .init(false)

    func enqueue(_ buffer: CMSampleBuffer) {
        guard buffer.presentationTimeStamp != .invalid else {
            return
        }
        
        lockQueue.async {
            if self.buffer.isEmpty {
                self.delegate?.queue(buffer)
            }
            self.buffer.append(buffer)
        }
    }

    @objc
    private func update(displayLink: DisplayLink) {
        lockQueue.async {
            if self.timestamp == 0.0 {
                self.timestamp = displayLink.timestamp
            }
            guard let first = self.buffer.first else {
                return
            }
            defer {
                if self.buffer.isEmpty {
                    self.delegate?.empty()
                }
            }
            let current = (self.clockReference?.duration ?? self.duration) + self.offset
            let targetTimestamp = first.presentationTimeStamp.seconds + first.duration.seconds
            if targetTimestamp < current {
                self.buffer.removeFirst()
                self.update(displayLink: displayLink)
                return
            }
            if first.presentationTimeStamp.seconds <= current && current <= targetTimestamp {
                self.buffer.removeFirst()
                self.delegate?.queue(first)
            }
        }
    }
}

extension DisplayLinkedQueue: Running {
    // MARK: Running
    public func startRunning() {
        lockQueue.async {
            guard !self.isRunning.value else {
                return
            }
            self.timestamp = 0.0
            self.displayLink = DisplayLink(target: self, selector: #selector(self.update(displayLink:)))
            self.isRunning.mutate { $0 = true }
        }
    }

    public func stopRunning() {
        guard self.isRunning.value else {
            return
        }
        
        lockQueue.async {
            self.buffer.removeAll()
            self.displayLink = nil
            self.clockReference = nil
            self.isRunning.mutate { $0 = false }
        }
    }
}
