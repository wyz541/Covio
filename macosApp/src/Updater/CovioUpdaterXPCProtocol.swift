import Foundation

@objc protocol CovioUpdaterXPCProtocol {
    func getStatus(withReply reply: @escaping (Data) -> Void)
    func checkNow(withReply reply: @escaping (Data) -> Void)
    func installAvailable(withReply reply: @escaping (Data) -> Void)
    func setAutomaticUpdates(_ enabled: Bool, withReply reply: @escaping (Data) -> Void)
    func restartApp(withReply reply: @escaping (Data) -> Void)
}
