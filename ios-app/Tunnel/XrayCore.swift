import Foundation
import LibXray

/// Thin wrapper around libXray's single entry point, `Invoke(requestJSON) -> responseJSON` (API version 3).
/// See https://github.com/XTLS/libXray#api
enum XrayCore {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { "Xray：\(message)" }
    }

    static func run(configJSON: String) throws {
        try invoke("runXray", payload: ["xrayJson": configJSON])
    }

    static func stop() {
        _ = try? invoke("stopXray")
    }

    @discardableResult
    private static func invoke(_ method: String, payload: [String: Any]? = nil) throws -> Any? {
        var request: [String: Any] = ["apiVersion": 3, "method": method]
        if let payload {
            request["payload"] = payload
        }
        let requestData = try JSONSerialization.data(withJSONObject: request)
        let responseText = LibXrayInvoke(String(decoding: requestData, as: UTF8.self))
        guard let response = try? JSONSerialization.jsonObject(with: Data(responseText.utf8)) as? [String: Any] else {
            throw Failure(message: "无法解析返回内容：\(responseText)")
        }
        guard response["success"] as? Bool == true else {
            throw Failure(message: response["error"] as? String ?? "未知错误")
        }
        return response["data"]
    }
}
