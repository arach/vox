import Foundation

enum PCMWAV {
    static func isWave(_ data: Data) -> Bool {
        data.count >= 12
            && data.starts(with: Data("RIFF".utf8))
            && data[8..<12] == Data("WAVE".utf8)
    }

    static func isStructurallyValid(_ data: Data) -> Bool {
        guard isWave(data), data.count >= 44 else { return false }

        let declaredSize = Int(littleEndianUInt32(data, at: 4))
        let payloadEnd = 8 + declaredSize
        guard declaredSize >= 4, payloadEnd <= data.count else { return false }

        var offset = 12
        var sawFmt = false
        var sawData = false

        while offset + 8 <= payloadEnd {
            let chunkID = data[offset..<(offset + 4)]
            let chunkSize = Int(littleEndianUInt32(data, at: offset + 4))
            let payloadStart = offset + 8
            guard chunkSize >= 0, payloadStart + chunkSize <= payloadEnd else { return false }

            if chunkID == Data("fmt ".utf8) {
                guard chunkSize >= 16 else { return false }
                sawFmt = true
            } else if chunkID == Data("data".utf8) {
                guard chunkSize > 0 else { return false }
                sawData = true
            }

            offset = payloadStart + chunkSize
            if chunkSize % 2 == 1 {
                guard offset < payloadEnd else { return false }
                offset += 1
            }
        }

        return sawFmt && sawData && offset == payloadEnd
    }

    private static func littleEndianUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    static func wrap(
        pcm: Data,
        sampleRate: UInt32,
        channelCount: UInt16 = 1,
        bitsPerSample: UInt16 = 16
    ) throws -> Data {
        guard !pcm.isEmpty else {
            throw PCMWAVError.emptyAudio
        }
        guard (8_000...192_000).contains(sampleRate), (1...8).contains(channelCount) else {
            throw PCMWAVError.unsupportedParameters
        }
        let blockAlign = channelCount * bitsPerSample / 8
        guard blockAlign > 0, pcm.count.isMultiple(of: Int(blockAlign)) else {
            throw PCMWAVError.incompleteFrame
        }
        guard pcm.count <= Int(UInt32.max) - 36 else {
            throw PCMWAVError.unsupportedParameters
        }

        let byteRate = sampleRate * UInt32(channelCount) * UInt32(bitsPerSample) / 8
        var wav = Data("RIFF".utf8)
        wav.appendLittleEndian(UInt32(36 + pcm.count))
        wav.append(Data("WAVEfmt ".utf8))
        wav.appendLittleEndian(UInt32(16))
        wav.appendLittleEndian(UInt16(1))
        wav.appendLittleEndian(channelCount)
        wav.appendLittleEndian(sampleRate)
        wav.appendLittleEndian(byteRate)
        wav.appendLittleEndian(blockAlign)
        wav.appendLittleEndian(bitsPerSample)
        wav.append(Data("data".utf8))
        wav.appendLittleEndian(UInt32(pcm.count))
        wav.append(pcm)
        return wav
    }

    static func wavIfNeeded(
        _ data: Data,
        sampleRate: UInt32,
        channelCount: UInt16 = 1,
        bitsPerSample: UInt16 = 16
    ) throws -> Data {
        if isWave(data) {
            return data
        }
        return try wrap(
            pcm: data,
            sampleRate: sampleRate,
            channelCount: channelCount,
            bitsPerSample: bitsPerSample
        )
    }
}

enum PCMWAVError: Error, LocalizedError {
    case emptyAudio
    case unsupportedParameters
    case incompleteFrame

    var errorDescription: String? {
        switch self {
        case .emptyAudio:
            return "Cannot wrap empty PCM audio as WAV."
        case .unsupportedParameters:
            return "Unsupported PCM WAV parameters."
        case .incompleteFrame:
            return "PCM audio is not aligned to a complete sample frame."
        }
    }
}

extension Data {
    mutating func appendLittleEndian(_ value: UInt16) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }

    mutating func appendLittleEndian(_ value: UInt32) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }
}
