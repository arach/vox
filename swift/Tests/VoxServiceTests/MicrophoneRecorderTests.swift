import AVFoundation
import Foundation
import Testing
@testable import VoxService

struct MicrophoneRecorderTests {
    @Test("Manual AVCapture stop errors are recoverable")
    func manualAVCaptureStopErrorIsRecoverable() {
        let error = NSError(domain: AVFoundationErrorDomain, code: -11806, userInfo: [
            NSLocalizedDescriptionKey: "Recording Stopped"
        ])

        #expect(MicrophoneRecorder.isRecoverableStopError(error))
    }

    @Test("Localized recording stopped errors are recoverable")
    func localizedRecordingStoppedErrorIsRecoverable() {
        let error = NSError(domain: "com.apple.coremedia", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "Recording Stopped"
        ])

        #expect(MicrophoneRecorder.isRecoverableStopError(error))
    }

    @Test("Unrelated recording errors are not recoverable")
    func unrelatedErrorIsNotRecoverable() {
        let error = NSError(domain: "VoxServiceTests", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Disk full"
        ])

        #expect(!MicrophoneRecorder.isRecoverableStopError(error))
    }
}
