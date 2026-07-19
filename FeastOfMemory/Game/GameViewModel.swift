import Foundation
import Observation

/// 한 판의 대국을 진행하는 뷰모델.
/// 1인용은 AI가 상대 무브를 만들고, 2인용은 RoomClient가 상대 무브를 전달한다.
/// 양쪽 모두 동일한 `GameEngine`을 통해 상태가 결정된다.
@Observable
@MainActor
final class GameViewModel {
    enum Mode {
        case solo(AIPlayer.Difficulty)
        case online(RoomClient)
    }

    let mode: Mode
    private(set) var engine = GameEngine()
    private(set) var localPlayer: Player

    /// 현재 화면에 공개 중인 접시들 (접시 번호 → 토큰 개수)
    private(set) var revealed: [Int: Int] = [:]
    /// 오픈 단계에서 첫 번째로 선택한 접시 (두 번째 선택 대기)
    private(set) var firstSelection: Int?
    /// 상단 안내 문구
    private(set) var banner: String = ""
    /// 오픈 단계 남은 시간 (초)
    private(set) var secondsLeft: Int = Int(GameEngine.turnTimeLimit)
    /// 암기 위반(스크린샷)으로 몰수패했는지
    private(set) var forfeitedByViolation = false
    /// 남은 "전체 접시 보기" 횟수 (1인용, 보상형 광고 시청으로 사용)
    private(set) var peeksRemaining = MonetizationConfig.peeksPerGame
    /// 상대가 나갔는지 (온라인)
    var opponentLeft = false

    private var ai: AIPlayer?
    private var aiTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private var revealGeneration: [Int: Int] = [:]
    /// 방금 일치 판정된 두 접시 (deposit 후 둘 다 다시 덮기 위해 기억)
    private var matchedPair: (Int, Int)?

    var isMyTurn: Bool { engine.currentTurn == localPlayer && engine.phase != .finished }
    var isSolo: Bool {
        if case .solo = mode { return true }
        return false
    }
    /// "전체 접시 보기"를 지금 쓸 수 있는가 — 1인용 오픈 단계, 내 차례, 잔여 횟수 있음
    var canPeekAllPlates: Bool {
        isSolo && engine.phase == .opening && isMyTurn
            && !engine.awaitingDeposit && peeksRemaining > 0
    }
    var myTokens: Int { engine.handTokens[localPlayer.rawValue] }
    var opponentTokens: Int { engine.handTokens[localPlayer.opponent.rawValue] }
    var opponentName: String {
        if case .solo = mode { return "AI" }
        return "상대"
    }

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .solo(let difficulty):
            // 선/후는 랜덤 배정
            localPlayer = Bool.random() ? .first : .second
            ai = AIPlayer(difficulty: difficulty, me: localPlayer.opponent)
        case .online(let client):
            if case .matched(let me) = client.state {
                localPlayer = me
            } else {
                localPlayer = .first
            }
            client.onRemoteMove = { [weak self] move in
                self?.applyRemote(move)
            }
            client.onOpponentLeft = { [weak self] in
                guard let self, self.engine.phase != .finished else { return }
                self.opponentLeft = true
            }
        }
        updateBanner()
        scheduleAIIfNeeded()
    }

    func cancelAllWork() {
        aiTask?.cancel()
        timerTask?.cancel()
    }

    // MARK: - 사용자 입력

    func tapPlate(_ plate: Int) {
        guard isMyTurn else { return }

        switch engine.phase {
        case .placement:
            guard engine.plates[plate] == 0 else { return }
            applyLocal(.place(plate: plate))

        case .opening:
            if engine.awaitingDeposit {
                // 일치한 두 접시 중 하나를 골라 토큰 추가
                applyLocal(.deposit(plate: plate))
            } else if firstSelection == plate {
                firstSelection = nil
            } else if let first = firstSelection {
                firstSelection = nil
                applyLocal(.open(a: first, b: plate))
            } else {
                firstSelection = plate
            }

        case .finished:
            break
        }
    }

    /// 스크린샷 등 기록 행위 감지 시 — 규칙대로 몰수패
    func memoryViolation() {
        guard engine.phase != .finished else { return }
        forfeitedByViolation = true
        applyLocal(.forfeit)
    }

    func resign() {
        guard engine.phase != .finished else { return }
        applyLocal(.forfeit)
    }

    // MARK: - 전체 접시 보기 (보상형 광고 보상, 1인용 전용)

    /// 광고 표시 전 — 턴 타이머를 멈춘다
    func pauseForAd() {
        timerTask?.cancel()
    }

    /// 광고가 보상 없이 끝났을 때 — 타이머를 새로 시작한다
    func resumeAfterAd() {
        restartTimerIfNeeded()
    }

    /// 보상 획득: 모든 접시를 잠시 공개했다가 다시 덮는다
    func peekAllPlates() {
        guard canPeekAllPlates else {
            resumeAfterAd()
            return
        }
        peeksRemaining -= 1
        firstSelection = nil
        for plate in engine.plates.indices {
            reveal(plate: plate, count: engine.plates[plate])
        }
        let seconds = Int(MonetizationConfig.peekDurationSeconds)
        banner = "집사의 배려 — \(seconds)초간 모든 접시가 공개됩니다!"
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(MonetizationConfig.peekDurationSeconds))
            guard let self else { return }
            // 진행 중이던 개별 flash 타이머가 잘못 덮지 않도록 세대를 올리고 전부 덮는다
            for plate in self.engine.plates.indices {
                self.revealGeneration[plate, default: 0] += 1
            }
            self.revealed.removeAll()
            self.banner = ""
            self.updateBanner()
            self.restartTimerIfNeeded()
        }
    }

    // MARK: - 무브 적용

    private func applyLocal(_ move: Move) {
        guard let outcome = try? engine.apply(move, by: localPlayer) else { return }
        if case .online(let client) = mode {
            client.send(move: move)
        }
        present(outcome)
    }

    private func applyRemote(_ move: Move) {
        guard let outcome = try? engine.apply(move, by: localPlayer.opponent) else { return }
        present(outcome)
    }

    private func applyAI(_ move: Move) {
        guard let aiPlayer = ai,
              let outcome = try? engine.apply(move, by: aiPlayer.me) else { return }
        present(outcome)
    }

    // MARK: - 연출/상태 반영

    private func present(_ outcome: MoveOutcome) {
        ai?.observe(outcome)

        switch outcome {
        case .placed(let player, let plate, let count):
            flash(plate: plate, count: count, for: 1.8)
            banner = "\(name(of: player))가 \(plate + 1)번 접시에 토큰 \(count)개를 놓았습니다."

        case .revealMatched(let player, let a, let b, let count):
            matchedPair = (a, b)
            reveal(plate: a, count: count)
            reveal(plate: b, count: count)
            if player == localPlayer {
                banner = "일치! 토큰을 놓을 접시를 선택하세요."
            } else {
                banner = "\(name(of: player))가 일치하는 쌍을 찾았습니다!"
            }

        case .revealMismatched(let player, let a, let b, let countA, let countB):
            flash(plate: a, count: countA, for: 2.5)
            flash(plate: b, count: countB, for: 2.5)
            banner = "불일치! \(name(of: player)) 페널티 토큰 +1"

        case .deposited(let player, let plate, let newCount, let remaining):
            flash(plate: plate, count: newCount, for: 1.5)
            // 쌍의 나머지 접시도 잠시 뒤 다시 덮는다
            if let pair = matchedPair {
                let other = pair.0 == plate ? pair.1 : pair.0
                flash(plate: other, count: engine.plates[other], for: 1.5)
                matchedPair = nil
            }
            if remaining == 0 {
                banner = "\(name(of: player)) 토큰 전부 소진 — 승리!"
            } else {
                banner = "\(name(of: player))가 \(plate + 1)번 접시에 토큰을 추가했습니다. (남은 토큰 \(remaining)개)"
            }

        case .timedOut(let player):
            banner = "시간 초과! \(name(of: player)) 페널티 토큰 +2"

        case .forfeited(let player):
            banner = forfeitedByViolation
                ? "암기 위반! \(name(of: player)) 몰수패"
                : "\(name(of: player)) 기권"
        }

        updateBanner(keepOutcomeMessage: true)
        restartTimerIfNeeded()
        scheduleAIIfNeeded()
    }

    private func updateBanner(keepOutcomeMessage: Bool = false) {
        guard !keepOutcomeMessage || banner.isEmpty else { return }
        switch engine.phase {
        case .placement:
            banner = isMyTurn
                ? "라운드 \(engine.round) — 빈 접시에 토큰 \(engine.round)개를 놓으세요."
                : "\(opponentName)가 배치 중입니다…"
        case .opening:
            banner = isMyTurn
                ? "토큰 개수가 같은 접시 2개를 찾아 여세요."
                : "\(opponentName)의 차례입니다…"
        case .finished:
            break
        }
    }

    private func name(of player: Player) -> String {
        player == localPlayer ? "나" : opponentName
    }

    /// 접시를 잠시 공개했다가 다시 덮는다
    private func flash(plate: Int, count: Int, for seconds: Double) {
        reveal(plate: plate, count: count)
        let generation = revealGeneration[plate, default: 0]
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, self.revealGeneration[plate] == generation else { return }
            // 일치 판정으로 열려 있는 접시는 deposit이 끝날 때까지 덮지 않는다
            if let pair = self.matchedPair, pair.0 == plate || pair.1 == plate { return }
            self.revealed.removeValue(forKey: plate)
        }
    }

    private func reveal(plate: Int, count: Int) {
        revealed[plate] = count
        revealGeneration[plate, default: 0] += 1
    }

    private func coverAllSoon() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            self?.revealed.removeAll()
        }
    }

    // MARK: - 턴 타이머 (오픈 단계 60초)

    private func restartTimerIfNeeded() {
        timerTask?.cancel()
        guard engine.phase == .opening, !engine.awaitingDeposit else {
            if engine.phase == .finished { coverAllSoon() }
            return
        }
        secondsLeft = Int(GameEngine.turnTimeLimit)
        let turnOwner = engine.currentTurn
        timerTask = Task { [weak self] in
            while let self, self.secondsLeft > 0, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self.secondsLeft -= 1
            }
            guard let self, !Task.isCancelled else { return }
            // 내 차례에서만 시간 초과를 실제로 적용한다 (상대 기기는 자기 쪽에서 처리)
            if turnOwner == self.localPlayer, self.engine.currentTurn == turnOwner,
               self.engine.phase == .opening, !self.engine.awaitingDeposit {
                self.firstSelection = nil
                self.applyLocal(.timeout)
            }
        }
    }

    // MARK: - AI 턴 진행 (1인용)

    private func scheduleAIIfNeeded() {
        guard case .solo = mode, let aiPlayer = ai,
              engine.phase != .finished, engine.currentTurn == aiPlayer.me else { return }
        aiTask?.cancel()
        aiTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Double.random(in: 1.0...2.0)))
            guard let self, !Task.isCancelled else { return }
            guard self.engine.currentTurn == aiPlayer.me, self.engine.phase != .finished else { return }

            switch self.engine.phase {
            case .placement:
                let plate = self.ai?.choosePlacement(emptyPlates: self.engine.emptyPlates) ?? 0
                self.applyAI(.place(plate: plate))

            case .opening:
                if self.engine.awaitingDeposit {
                    // (이 경로는 아래 revealMatched 이후 재스케줄로 진입)
                    self.aiDeposit()
                } else {
                    self.ai?.decayMemory()
                    let pair = self.ai?.chooseOpen() ?? (0, 1)
                    self.applyAI(.open(a: pair.0, b: pair.1))
                }

            case .finished:
                break
            }
        }
    }

    private func aiDeposit() {
        guard let pending = engine.pendingDepositPlates, pending.count == 2 else { return }
        let choice = ai?.chooseDeposit(between: pending[0], and: pending[1]) ?? pending[0]
        applyAI(.deposit(plate: choice))
    }
}
