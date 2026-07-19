import Foundation

/// 온라인 대전 서버 설정
enum OnlineConfig {
    /// 기본 릴레이 서버 주소 — 사용자에게는 노출되지 않는다.
    /// (server/ 디렉터리를 Render에 배포한 주소. 서비스 이름을 바꾸면 여기도 함께 수정)
    static let defaultServerURLString = "wss://feast-of-memory.onrender.com"

    /// 설정 > 고급에서 서버 주소를 덮어쓴 경우 그 값을, 아니면 기본 서버를 쓴다
    static func resolvedServerURL() -> URL? {
        let override = UserDefaults.standard.string(forKey: "serverURLOverride")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let urlString = override.isEmpty ? defaultServerURLString : override
        guard let url = URL(string: urlString),
              url.scheme == "ws" || url.scheme == "wss" else { return nil }
        return url
    }
}
