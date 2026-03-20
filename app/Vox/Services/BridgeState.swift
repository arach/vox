import Foundation

final class BridgeState: ObservableObject {
    @Published var isRunning = false
    @Published var port: UInt16 = 0
}
