struct ParakeetHypothesis {
    var score: Float = 0
    var tokenIDs: [Int] = []
    var decoderState: ParakeetDecoderState?
    var timestamps: [Int] = []
    var tokenDurations: [Int] = []
    var tokenConfidences: [Float] = []
    var lastToken: Int?

    init(decoderState: ParakeetDecoderState) {
        self.decoderState = decoderState
    }

    var isEmpty: Bool { tokenIDs.isEmpty }
    var hasTokens: Bool { !tokenIDs.isEmpty }
}
