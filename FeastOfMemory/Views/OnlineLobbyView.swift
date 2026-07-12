import SwiftUI

/// 2인용 로비 — 방을 만들어 코드를 공유하거나, 받은 코드로 입장한다.
struct OnlineLobbyView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("serverURL") private var serverURLString = "ws://localhost:8080"
    @State private var client = RoomClient()
    @State private var joinCode = ""
    @State private var game: GameViewModel?

    var body: some View {
        NavigationStack {
            Form {
                Section("서버") {
                    TextField("ws://주소:포트", text: $serverURLString)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("server/ 디렉터리의 릴레이 서버 주소를 입력하세요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("방 만들기") {
                    Button {
                        if let url = serverURL { client.createRoom(serverURL: url) }
                    } label: {
                        Label("새 방 만들기", systemImage: "plus.circle.fill")
                    }
                    .disabled(serverURL == nil || isBusy)

                    if case .waitingForOpponent(let code) = client.state {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("방 코드")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack {
                                Text(code)
                                    .font(.system(size: 34, weight: .black, design: .monospaced))
                                    .kerning(6)
                                Spacer()
                                ShareLink(item: "기억의 만찬 대결 초대! 방 코드: \(code)") {
                                    Image(systemName: "square.and.arrow.up")
                                }
                            }
                            Label("상대의 입장을 기다리는 중…", systemImage: "hourglass")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("코드로 입장") {
                    HStack {
                        TextField("방 코드 6자리", text: $joinCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .onChange(of: joinCode) { _, newValue in
                                joinCode = String(newValue.uppercased().prefix(6))
                            }
                        Button("입장") {
                            if let url = serverURL {
                                client.joinRoom(code: joinCode, serverURL: url)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(joinCode.count != 6 || serverURL == nil || isBusy)
                    }
                }

                if case .failed(let message) = client.state {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
                if case .connecting = client.state {
                    Section { ProgressView("연결 중…") }
                }
            }
            .navigationTitle("둘이 하기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") {
                        client.close()
                        dismiss()
                    }
                }
            }
            .onChange(of: client.state) { _, newState in
                if case .matched = newState {
                    game = GameViewModel(mode: .online(client))
                }
            }
            .fullScreenCover(item: $game) { game in
                GameView(viewModel: game)
                    .onDisappear {
                        // 대국 화면을 벗어나면 연결 종료 (재대국은 새 방으로)
                        client.close()
                        self.game = nil
                    }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var serverURL: URL? {
        guard let url = URL(string: serverURLString),
              url.scheme == "ws" || url.scheme == "wss" else { return nil }
        return url
    }

    private var isBusy: Bool {
        switch client.state {
        case .idle, .failed, .opponentLeft: return false
        case .connecting, .waitingForOpponent, .matched: return true
        }
    }
}
