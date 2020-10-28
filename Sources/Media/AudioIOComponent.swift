import AVFoundation

#if canImport(SwiftPMSupport)
import SwiftPMSupport
#endif

public class AudioIOComponent: IOComponent, DisplayLinkedQueueClockReference {
    lazy var encoder = AudioConverter()
    let lockQueue = DispatchQueue(label: "com.haishinkit.HaishinKit.AudioIOComponent.lock")

    var audioEngine: AVAudioEngine?
    public var duration: TimeInterval {
        guard let nodeTime = playerNode.lastRenderTime, let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
            return 0.0
        }
        return TimeInterval(playerTime.sampleTime) / playerTime.sampleRate
    }
    public var currentAudioTime: TimeInterval {
        return lastPlayedTime.seconds
    }
    
    public var lastScheduledTime = CMTime.zero
    var lastPlayedTime = CMTime.zero
    
    var currentBuffers: Atomic<Int> = .init(0)
    var soundTransform: SoundTransform = .init() {
        didSet {
            soundTransform.apply(playerNode)
        }
    }

    private var _playerNode: AVAudioPlayerNode?
    private var playerNode: AVAudioPlayerNode! {
        get {
            if _playerNode == nil {
                _playerNode = AVAudioPlayerNode()
                audioEngine?.attach(_playerNode!)
            }
            return _playerNode
        }
        set {
            if let playerNode = _playerNode {
                audioEngine?.detach(playerNode)
            }
            _playerNode = newValue
        }
    }

    private var audioFormat: AVAudioFormat? {
        didSet {
            guard let audioFormat = audioFormat, let audioEngine = audioEngine else {
                return
            }
            nstry({
                audioEngine.connect(self.playerNode, to: audioEngine.mainMixerNode, format: audioFormat)
            }, { exeption in
                logger.warn(exeption)
            })
            do {
                try audioEngine.start()
                if !playerNode.isPlaying && audioEngine != nil {
                    playerNode.play()
                }
            } catch {
                logger.warn(error)
            }
        }
    }

#if os(iOS) || os(macOS)
    var input: AVCaptureDeviceInput? {
        didSet {
            guard let mixer: AVMixer = mixer, oldValue != input else {
                return
            }
            if let oldValue: AVCaptureDeviceInput = oldValue {
                mixer.session.removeInput(oldValue)
            }
            if let input: AVCaptureDeviceInput = input, mixer.session.canAddInput(input) {
                mixer.session.addInput(input)
            }
        }
    }

    private var _output: AVCaptureAudioDataOutput?
    var output: AVCaptureAudioDataOutput! {
        get {
            if _output == nil {
                _output = AVCaptureAudioDataOutput()
            }
            return _output
        }
        set {
            if _output == newValue {
                return
            }
            if let output: AVCaptureAudioDataOutput = _output {
                output.setSampleBufferDelegate(nil, queue: nil)
                mixer?.session.removeOutput(output)
            }
            _output = newValue
        }
    }
#endif

    override init(mixer: AVMixer) {
        super.init(mixer: mixer)
        encoder.lockQueue = lockQueue
    }

    func appendSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        mixer?.recorder.appendSampleBuffer(sampleBuffer, mediaType: .audio)
        encoder.encodeSampleBuffer(sampleBuffer)
    }

#if os(iOS) || os(macOS)
    func attachAudio(_ audio: AVCaptureDevice?, automaticallyConfiguresApplicationAudioSession: Bool) throws {
        guard let mixer: AVMixer = mixer else {
            return
        }

        mixer.session.beginConfiguration()
        defer {
            mixer.session.commitConfiguration()
        }

        output = nil
        encoder.invalidate()

        guard let audio: AVCaptureDevice = audio else {
            input = nil
            return
        }

        input = try AVCaptureDeviceInput(device: audio)
        #if os(iOS)
        mixer.session.automaticallyConfiguresApplicationAudioSession = automaticallyConfiguresApplicationAudioSession
        #endif
        mixer.session.addOutput(output)
        output.setSampleBufferDelegate(self, queue: lockQueue)
    }

    func dispose() {
        input = nil
        output = nil
        playerNode = nil
        audioFormat = nil
    }
#else
    func dispose() {
        playerNode = nil
        audioFormat = nil
    }
#endif

    func registerEffect(_ effect: AudioEffect) -> Bool {
        encoder.effects.insert(effect).inserted
    }

    func unregisterEffect(_ effect: AudioEffect) -> Bool {
        encoder.effects.remove(effect) != nil
    }

    func startDecoding(_ audioEngine: AVAudioEngine?) {
        self.audioEngine = audioEngine
        encoder.delegate = self
        encoder.startRunning()
    }

    func stopDecoding() {
        playerNode.reset()
        audioEngine = nil
        encoder.delegate = nil
        encoder.stopRunning()
        currentBuffers.mutate { $0 = 0 }
    }
    
    public func reset() {
        self.playerNode.reset()
    }
}

extension AudioIOComponent: AVCaptureAudioDataOutputSampleBufferDelegate {
    // MARK: AVCaptureAudioDataOutputSampleBufferDelegate
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        appendSampleBuffer(sampleBuffer)
    }
}

extension AudioIOComponent: AudioConverterDelegate {
    // MARK: AudioConverterDelegate
    public func didSetFormatDescription(audio formatDescription: CMFormatDescription?) {
        guard let formatDescription = formatDescription else {
            mixer?.videoIO.queue.clockReference = nil
            return
        }
        #if os(iOS)
        if #available(iOS 9.0, *) {
            lockQueue.sync {
                audioFormat = AVAudioFormat(cmAudioFormatDescription: formatDescription)
            }
        } else {
            guard let asbd = formatDescription.streamBasicDescription?.pointee else {
                return
            }
            audioFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: asbd.mSampleRate, channels: asbd.mChannelsPerFrame, interleaved: false)
        }
        #else
            lockQueue.sync {
                audioFormat = AVAudioFormat(cmAudioFormatDescription: formatDescription)
            }
        #endif
        mixer?.videoIO.queue.clockReference = self
    }

    public func sampleOutput(audio data: UnsafeMutableAudioBufferListPointer, presentationTimeStamp: CMTime) {
        guard !data.isEmpty, data[0].mDataByteSize != 0 else { return }

        guard
            let audioFormat = audioFormat,
            let buffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: data[0].mDataByteSize / 4) else {
            return
        }

        if let queue = mixer?.videoIO.queue, queue.isPaused {
            queue.isPaused = false
        }

        buffer.frameLength = buffer.frameCapacity
        let bufferList = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        for i in 0..<bufferList.count {
            guard let mData = data[i].mData else { continue }
            memcpy(bufferList[i].mData, mData, Int(data[i].mDataByteSize))
            bufferList[i].mDataByteSize = data[i].mDataByteSize
            bufferList[i].mNumberChannels = 1
        }

        self.lastScheduledTime = presentationTimeStamp
        
        mixer?.delegate?.didOutputAudio(buffer, presentationTimeStamp: presentationTimeStamp)
        currentBuffers.mutate { $0 += 1 }

        nstry({
            if #available(iOS 11.0, *) {
                self.playerNode.scheduleBuffer(buffer, completionCallbackType: AVAudioPlayerNodeCompletionCallbackType.dataPlayedBack) { [weak self, presentationTimeStamp] callback in
                    guard let self = self else { return }
                    self.lastPlayedTime = presentationTimeStamp
                    self.didAVAudioNodeCompletion()
                }
            } else {
                self.playerNode.scheduleBuffer(buffer, completionHandler: self.didAVAudioNodeCompletion)
            }
            if !self.playerNode.isPlaying {
                self.playerNode.play()
            }
        }, { exeption in
            logger.warn(exeption)
        })
    }

    private func didAVAudioNodeCompletion() {
        currentBuffers.mutate { value in
            value -= 1
            if value == 0 {
                self.playerNode.pause()
                self.mixer?.didBufferEmpty(self)
            }
        }
    }
}
