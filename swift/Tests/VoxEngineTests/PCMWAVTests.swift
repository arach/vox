import Foundation
import Testing
@testable import HudsonSpeechEngine

struct PCMWAVTests {
    @Test("wrapped PCM is a structurally valid WAVE")
    func wrapProducesStructurallyValidWave() throws {
        let wav = try PCMWAV.wrap(pcm: Data([0x00, 0x01, 0x02, 0x03]), sampleRate: 44_100)
        #expect(PCMWAV.isStructurallyValid(wav))
        #expect(Int(littleEndianUInt32(wav, at: 4)) == wav.count - 8)
    }

    @Test("WAVE with fmt but no data chunk is invalid")
    func fmtWithoutDataIsInvalid() {
        let wav = riffWave(chunks: [("fmt ", pcmFmtChunk())])
        #expect(PCMWAV.isWave(wav))
        #expect(!PCMWAV.isStructurallyValid(wav))
    }

    @Test("WAVE with empty data chunk is invalid")
    func emptyDataChunkIsInvalid() {
        let wav = riffWave(chunks: [
            ("fmt ", pcmFmtChunk()),
            ("data", Data())
        ])
        #expect(!PCMWAV.isStructurallyValid(wav))
    }

    @Test("RIFF declared size larger than the buffer is invalid")
    func oversizedRIFFSizeIsInvalid() throws {
        var wav = try PCMWAV.wrap(pcm: Data([0x00, 0x01, 0x02, 0x03]), sampleRate: 44_100)
        wav[4] = 0xff
        wav[5] = 0xff
        wav[6] = 0xff
        wav[7] = 0x7f
        #expect(PCMWAV.isWave(wav))
        #expect(!PCMWAV.isStructurallyValid(wav))
    }

    @Test("RIFF declared size that truncates the data chunk is invalid")
    func undersizedRIFFSizeIsInvalid() throws {
        var wav = try PCMWAV.wrap(pcm: Data([0x00, 0x01, 0x02, 0x03]), sampleRate: 44_100)
        let truncated = UInt32(16)
        wav[4] = UInt8(truncated & 0xff)
        wav[5] = UInt8((truncated >> 8) & 0xff)
        wav[6] = 0
        wav[7] = 0
        #expect(!PCMWAV.isStructurallyValid(wav))
    }

    @Test("data chunk that claims more bytes than remain is invalid")
    func truncatedDataPayloadIsInvalid() {
        var wav = riffWave(chunks: [
            ("fmt ", pcmFmtChunk()),
            ("data", Data([0x00, 0x01, 0x02, 0x03]))
        ])
        let dataSizeOffset = 12 + 8 + 16 + 4
        wav[dataSizeOffset] = 64
        #expect(!PCMWAV.isStructurallyValid(wav))
    }

    @Test("odd-sized chunk without the required pad byte is invalid")
    func missingChunkPaddingIsInvalid() {
        let wav = riffWave(
            chunks: [
                ("fmt ", pcmFmtChunk()),
                ("data", Data([0x00]))
            ],
            includePad: false
        )
        #expect(!PCMWAV.isStructurallyValid(wav))
    }

    @Test("odd-sized data chunk with pad byte and matching RIFF size is valid")
    func oddSizedDataChunkWithPadIsValid() {
        let wav = riffWave(chunks: [
            ("fmt ", pcmFmtChunk()),
            ("data", Data([0x00]))
        ])
        #expect(PCMWAV.isStructurallyValid(wav))
    }

    @Test("fmt chunk smaller than 16 bytes is invalid")
    func shortFmtChunkIsInvalid() {
        let wav = riffWave(chunks: [
            ("fmt ", Data(repeating: 0, count: 14)),
            ("data", Data([0x00, 0x01]))
        ])
        #expect(!PCMWAV.isStructurallyValid(wav))
    }

    private func pcmFmtChunk() -> Data {
        var fmt = Data()
        fmt.appendLittleEndian(UInt16(1))
        fmt.appendLittleEndian(UInt16(1))
        fmt.appendLittleEndian(UInt32(44_100))
        fmt.appendLittleEndian(UInt32(88_200))
        fmt.appendLittleEndian(UInt16(2))
        fmt.appendLittleEndian(UInt16(16))
        return fmt
    }

    private func riffWave(chunks: [(String, Data)], includePad: Bool = true) -> Data {
        var payload = Data("WAVE".utf8)
        for (id, chunk) in chunks {
            payload.append(Data(id.utf8))
            payload.appendLittleEndian(UInt32(chunk.count))
            payload.append(chunk)
            if includePad, chunk.count % 2 == 1 {
                payload.append(0)
            }
        }
        var data = Data("RIFF".utf8)
        data.appendLittleEndian(UInt32(payload.count))
        data.append(payload)
        return data
    }

    private func littleEndianUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}
