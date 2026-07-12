import Combine
import SwiftUI
import UIKit

/// 대국 화면 — 4×5로 배열된 20개의 접시와 스코어, 턴 타이머, 안내 배너.
struct GameView: View {
    @State var viewModel: GameViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showResignAlert = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.09, green: 0.07, blue: 0.12),
                                    Color(red: 0.16, green: 0.10, blue: 0.10)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                scoreboard
                banner
                plateGrid
                Spacer(minLength: 0)
                bottomBar
            }
            .padding()

            if viewModel.engine.phase == .finished {
                gameOverOverlay
            }
        }
        .navigationBarBackButtonHidden(true)
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.userDidTakeScreenshotNotification)) { _ in
            // 규칙: 토큰 개수를 물리적으로 기록하면 몰수패 (암기 위반)
            viewModel.memoryViolation()
        }
        .onDisappear { viewModel.cancelAllWork() }
        .alert("기권하시겠습니까?", isPresented: $showResignAlert) {
            Button("기권", role: .destructive) { viewModel.resign() }
            Button("계속하기", role: .cancel) {}
        }
        .alert("상대가 나갔습니다", isPresented: $viewModel.opponentLeft) {
            Button("나가기") { dismiss() }
        }
    }

    // MARK: 스코어보드

    private var scoreboard: some View {
        HStack(spacing: 12) {
            playerBadge(name: "나 (\(viewModel.localPlayer.label))",
                        tokens: viewModel.myTokens,
                        active: viewModel.isMyTurn)
            if viewModel.engine.phase == .opening || viewModel.engine.phase == .finished {
                Text("\(viewModel.myTokens) : \(viewModel.opponentTokens)")
                    .font(.title2.monospacedDigit().bold())
                    .foregroundStyle(.white)
            } else {
                Text("라운드 \(viewModel.engine.round)/9")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.9))
            }
            playerBadge(name: "\(viewModel.opponentName) (\(viewModel.localPlayer.opponent.label))",
                        tokens: viewModel.opponentTokens,
                        active: !viewModel.isMyTurn && viewModel.engine.phase != .finished)
        }
    }

    private func playerBadge(name: String, tokens: Int, active: Bool) -> some View {
        VStack(spacing: 4) {
            Text(name)
                .font(.caption.bold())
                .lineLimit(1)
            if viewModel.engine.phase != .placement {
                Label("\(tokens)", systemImage: "circlebadge.2.fill")
                    .font(.caption2.monospacedDigit())
            }
        }
        .foregroundStyle(active ? .yellow : .white.opacity(0.6))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.white.opacity(active ? 0.14 : 0.05))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(active ? .yellow.opacity(0.7) : .clear, lineWidth: 1.5))
        )
    }

    // MARK: 배너 & 타이머

    private var banner: some View {
        VStack(spacing: 8) {
            Text(viewModel.banner)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 40)
                .padding(.horizontal, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.08)))

            if viewModel.engine.phase == .opening && !viewModel.engine.awaitingDeposit {
                HStack(spacing: 8) {
                    Image(systemName: "timer")
                    ProgressView(value: Double(viewModel.secondsLeft),
                                 total: GameEngine.turnTimeLimit)
                        .tint(viewModel.secondsLeft <= 10 ? .red : .yellow)
                    Text("\(viewModel.secondsLeft)초")
                        .font(.caption.monospacedDigit().bold())
                }
                .foregroundStyle(.white.opacity(0.85))
            }
        }
    }

    // MARK: 접시 그리드

    private var plateGrid: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(0..<GameEngine.plateCount, id: \.self) { plate in
                PlateView(
                    number: plate + 1,
                    revealedCount: viewModel.revealed[plate],
                    isSelected: viewModel.firstSelection == plate,
                    isDepositTarget: viewModel.engine.awaitingDeposit && viewModel.isMyTurn
                        && (viewModel.engine.pendingDepositPlates?.contains(plate) ?? false),
                    showOccupiedMark: viewModel.engine.phase == .placement
                        && viewModel.engine.plates[plate] > 0
                        && viewModel.revealed[plate] == nil
                )
                .onTapGesture { viewModel.tapPlate(plate) }
            }
        }
    }

    // MARK: 하단 바

    private var bottomBar: some View {
        HStack {
            Button {
                showResignAlert = true
            } label: {
                Label("기권", systemImage: "flag.fill")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            Label("기록·스크린샷은 몰수패!", systemImage: "camera.viewfinder")
                .font(.caption2)
                .foregroundStyle(.red.opacity(0.8))
        }
    }

    // MARK: 게임 종료 오버레이

    private var gameOverOverlay: some View {
        VStack(spacing: 16) {
            Text(viewModel.engine.winner == viewModel.localPlayer ? "🏆 승리!" : "💀 패배")
                .font(.largeTitle.bold())
            Text(viewModel.banner)
                .font(.subheadline)
                .multilineTextAlignment(.center)
            Button("나가기") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(.yellow)
                .foregroundStyle(.black)
        }
        .foregroundStyle(.white)
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 20).fill(.black.opacity(0.85)))
        .padding(40)
    }
}

/// 접시 하나 — 평소엔 번호가 적힌 커버(클로슈), 공개 시 토큰 개수 표시.
struct PlateView: View {
    let number: Int
    let revealedCount: Int?
    let isSelected: Bool
    let isDepositTarget: Bool
    let showOccupiedMark: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(revealedCount != nil
                      ? AnyShapeStyle(Color(red: 0.93, green: 0.89, blue: 0.80))
                      : AnyShapeStyle(LinearGradient(colors: [Color(red: 0.75, green: 0.72, blue: 0.78),
                                                              Color(red: 0.45, green: 0.42, blue: 0.50)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing)))
                .overlay(
                    Circle().stroke(
                        isDepositTarget ? Color.green :
                        isSelected ? Color.yellow : Color.white.opacity(0.25),
                        lineWidth: isSelected || isDepositTarget ? 3 : 1)
                )

            if let count = revealedCount {
                VStack(spacing: 2) {
                    Text("\(count)")
                        .font(.title2.bold().monospacedDigit())
                        .foregroundStyle(Color(red: 0.35, green: 0.15, blue: 0.12))
                    Text("토큰")
                        .font(.system(size: 9))
                        .foregroundStyle(Color(red: 0.35, green: 0.15, blue: 0.12).opacity(0.7))
                }
            } else {
                VStack(spacing: 1) {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                    Text("\(number)")
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                }
            }

            if showOccupiedMark {
                Circle()
                    .fill(.orange)
                    .frame(width: 8, height: 8)
                    .offset(x: 18, y: -18)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .animation(.spring(duration: 0.3), value: revealedCount)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}
