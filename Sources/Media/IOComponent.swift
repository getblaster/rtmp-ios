import CoreMedia
import Foundation

public class IOComponent: NSObject {
    private(set) weak var mixer: AVMixer?

    init(mixer: AVMixer) {
        self.mixer = mixer
    }
}
