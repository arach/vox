@preconcurrency import CoreML
import Foundation

final class ParakeetReusableJointInputProvider: NSObject, MLFeatureProvider {
    let encoderStep: MLMultiArray
    let decoderStep: MLMultiArray

    init(encoderStep: MLMultiArray, decoderStep: MLMultiArray) {
        self.encoderStep = encoderStep
        self.decoderStep = decoderStep
        super.init()
    }

    var featureNames: Set<String> {
        ["encoder_step", "decoder_step"]
    }

    func featureValue(for featureName: String) -> MLFeatureValue? {
        switch featureName {
        case "encoder_step":
            return MLFeatureValue(multiArray: encoderStep)
        case "decoder_step":
            return MLFeatureValue(multiArray: decoderStep)
        default:
            return nil
        }
    }
}
