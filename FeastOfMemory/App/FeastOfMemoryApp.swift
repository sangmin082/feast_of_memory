import SwiftUI

@main
struct FeastOfMemoryApp: App {
    init() {
        // 실제 방송 대국(이세돌 vs 홍진호) 리플레이로 엔진 규칙을 검증 (DEBUG 전용)
        EngineSelfTest.run()
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
    }
}
