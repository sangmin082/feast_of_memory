import Foundation

/// 1인용 모드의 AI 상대.
///
/// 사람처럼 "불완전한 기억"으로 플레이한다: 배치·오픈 과정을 관찰해 접시별 개수를
/// 기억하되, 난이도에 따라 일부를 잊거나 헷갈린다. 실제 접시 내용(`GameEngine.plates`)은
/// 절대 직접 읽지 않고 자신의 기억(`memory`)만으로 판단한다.
struct AIPlayer {
    enum Difficulty: String, CaseIterable, Identifiable {
        case easy, normal, hard

        var id: String { rawValue }
        var label: String {
            switch self {
            case .easy: return "쉬움"
            case .normal: return "보통"
            case .hard: return "어려움"
            }
        }
        /// 관찰 직후 올바르게 기억할 확률
        var retention: Double {
            switch self {
            case .easy: return 0.55
            case .normal: return 0.78
            case .hard: return 0.95
            }
        }
        /// 매 턴 시작 시 기억 하나를 잊을 확률
        var decay: Double {
            switch self {
            case .easy: return 0.30
            case .normal: return 0.15
            case .hard: return 0.04
            }
        }
    }

    let difficulty: Difficulty
    let me: Player

    /// 접시별로 "몇 개가 들어 있다고 기억하는지" (nil = 모름/잊음)
    private(set) var memory: [Int?]
    private var rng: SystemRandomNumberGenerator

    init(difficulty: Difficulty, me: Player) {
        self.difficulty = difficulty
        self.me = me
        // 게임 시작 시 모든 접시가 비어 있다는 것은 자명한 정보
        self.memory = Array(repeating: 0, count: GameEngine.plateCount)
        self.rng = SystemRandomNumberGenerator()
    }

    // MARK: - 관찰 (엔진 outcome을 흘려 넣어 기억을 갱신)

    mutating func observe(_ outcome: MoveOutcome) {
        switch outcome {
        case .placed(let player, let plate, let count):
            // 자기 배치는 확실히 기억, 상대 배치는 난이도 확률로 기억
            if player == me || Double.random(in: 0..<1, using: &rng) < difficulty.retention {
                memory[plate] = count
            } else {
                memory[plate] = nil
            }
        case .revealMatched(_, let a, let b, let count):
            memory[a] = count
            memory[b] = count
        case .revealMismatched(_, let a, let b, let countA, let countB):
            memory[a] = countA
            memory[b] = countB
        case .deposited(_, let plate, let newCount, _):
            memory[plate] = newCount
        case .timedOut, .forfeited:
            break
        }
    }

    /// 턴 사이에 자연스럽게 기억이 흐려진다
    mutating func decayMemory() {
        guard Double.random(in: 0..<1, using: &rng) < difficulty.decay else { return }
        let known = memory.indices.filter { memory[$0] != nil }
        if let victim = known.randomElement(using: &rng) {
            memory[victim] = nil
        }
    }

    // MARK: - 의사결정

    /// 배치 단계: 빈 접시 중 하나를 고른다
    func choosePlacement(emptyPlates: [Int]) -> Int {
        emptyPlates.randomElement() ?? 0
    }

    /// 오픈 단계: 열어볼 접시 2개를 고른다
    func chooseOpen() -> (Int, Int) {
        // 1순위: 기억상 개수가 같은 두 접시
        var byCount: [Int: [Int]] = [:]
        for (plate, count) in memory.enumerated() {
            if let count { byCount[count, default: []].append(plate) }
        }
        let pairs = byCount.values.filter { $0.count >= 2 }
        if let pair = pairs.randomElement() {
            let shuffled = pair.shuffled()
            return (shuffled[0], shuffled[1])
        }

        // 2순위: 모르는 접시를 열어 정보 수집 (페널티 1개를 내고 배우는 셈)
        let unknown = memory.indices.filter { memory[$0] == nil }.shuffled()
        if unknown.count >= 2 {
            return (unknown[0], unknown[1])
        }
        if let u = unknown.first {
            let other = memory.indices.filter { $0 != u }.randomElement() ?? (u + 1) % GameEngine.plateCount
            return (u, other)
        }

        // 전부 기억하는데 쌍이 없는 경우(드묾): 아무거나 연다
        let all = memory.indices.shuffled()
        return (all[0], all[1])
    }

    /// 일치 후 어느 접시에 토큰을 추가할지 고른다.
    /// 어느 쪽이든 count+1이 되는 것은 같으므로 전략 차이는 없다 — 랜덤 선택.
    func chooseDeposit(between a: Int, and b: Int) -> Int {
        Bool.random() ? a : b
    }
}
