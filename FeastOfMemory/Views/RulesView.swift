import SwiftUI

struct RulesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ruleSection("🎯 목표",
                        "커버로 덮인 20개의 접시 중, 같은 개수의 토큰이 들어 있는 두 접시를 찾아 " +
                        "내 토큰을 먼저 전부 소진하면 승리합니다.")

                    ruleSection("🍽️ 배치 단계",
                        """
                        • 테이블에는 1~20번 커버가 덮인 접시 20개가 놓여 있습니다.
                        • 각 플레이어는 배치 토큰 45개를 가지고 시작합니다.
                        • 선 플레이어부터 원하는 접시에 토큰 1개를 놓고 커버를 덮으며, 후 플레이어도 동일하게 진행합니다.
                        • 이미 토큰이 들어 있는 접시에는 놓을 수 없습니다.
                        • 라운드마다 놓는 토큰을 1개씩 늘려 9개까지, 45개를 모두 배치할 때까지 반복합니다.
                        • 두 접시는 끝까지 비어 있게 됩니다(0개).
                        """)

                    ruleSection("🧠 암기",
                        "접시 속 토큰의 개수는 오직 암기로만 기억해야 합니다. " +
                        "스크린샷 등 물리적으로 기록하면 그 즉시 몰수패합니다.")

                    ruleSection("🔓 오픈 단계",
                        """
                        • 배치가 끝나면 각자 토큰 10개를 추가로 지급받습니다.
                        • 선 플레이어부터 제한 시간 1분 안에 원하는 접시 2개를 오픈합니다.
                        • 1분 안에 고르지 못하면 페널티로 토큰 2개를 더 받습니다.
                        • 두 접시의 토큰 개수가 일치하면 → 내 토큰 1개를 두 접시 중 한 곳에 추가합니다.
                        • 개수가 다르면 → 페널티로 토큰 1개를 더 받습니다.
                        """)

                    ruleSection("🏆 승리",
                        "자신의 토큰을 먼저 전부 소진한 플레이어가 승리합니다.")

                    ruleSection("💡 팁",
                        "토큰을 추가하면 그 접시의 개수가 변합니다. 내가 만든 새 개수로 다음 쌍을 준비하거나, " +
                        "같은 접시를 반복 공략해 상대의 암기를 흔들 수도 있습니다.")
                }
                .padding()
            }
            .navigationTitle("게임 방법")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func ruleSection(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.06)))
    }
}
