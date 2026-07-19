import Foundation

// MARK: - 기본 타입

/// 대국의 두 플레이어. `first`가 선(先), `second`가 후(後).
enum Player: Int, Codable, Equatable, Sendable {
    case first = 0
    case second = 1

    var opponent: Player { self == .first ? .second : .first }
    var label: String { self == .first ? "선" : "후" }
}

/// 게임 진행 단계
enum Phase: String, Codable, Equatable, Sendable {
    /// 배치 단계 — 라운드마다 토큰 수를 1개씩 늘려가며 접시에 배치 (1~9개, 총 45개)
    case placement
    /// 오픈 단계 — 접시 2개를 열어 토큰 개수가 같은 쌍을 찾는 단계
    case opening
    /// 게임 종료
    case finished
}

/// 플레이어가 취할 수 있는 행동
enum Move: Codable, Equatable, Sendable {
    /// 배치 단계: 빈 접시에 이번 라운드 개수만큼 토큰을 놓고 커버를 덮는다
    case place(plate: Int)
    /// 오픈 단계: 접시 2개의 커버를 연다
    case open(a: Int, b: Int)
    /// 오픈한 두 접시가 일치했을 때, 그중 한 접시에 자기 토큰 1개를 추가한다
    case deposit(plate: Int)
    /// 제한 시간(60초) 초과 — 페널티 토큰 2개
    case timeout
    /// 기권 또는 몰수패(암기 위반 등)
    case forfeit

    private enum CodingKeys: String, CodingKey { case kind, plate, a, b }
    private enum Kind: String, Codable { case place, open, deposit, timeout, forfeit }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .place: self = .place(plate: try c.decode(Int.self, forKey: .plate))
        case .open: self = .open(a: try c.decode(Int.self, forKey: .a), b: try c.decode(Int.self, forKey: .b))
        case .deposit: self = .deposit(plate: try c.decode(Int.self, forKey: .plate))
        case .timeout: self = .timeout
        case .forfeit: self = .forfeit
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .place(let plate):
            try c.encode(Kind.place, forKey: .kind)
            try c.encode(plate, forKey: .plate)
        case .open(let a, let b):
            try c.encode(Kind.open, forKey: .kind)
            try c.encode(a, forKey: .a)
            try c.encode(b, forKey: .b)
        case .deposit(let plate):
            try c.encode(Kind.deposit, forKey: .kind)
            try c.encode(plate, forKey: .plate)
        case .timeout:
            try c.encode(Kind.timeout, forKey: .kind)
        case .forfeit:
            try c.encode(Kind.forfeit, forKey: .kind)
        }
    }
}

/// 무브 적용 결과 — UI 연출과 AI 관찰에 사용
enum MoveOutcome: Equatable, Sendable {
    /// 접시에 토큰 `count`개 배치됨
    case placed(player: Player, plate: Int, count: Int)
    /// 두 접시를 열었더니 개수가 일치 — 같은 플레이어의 `deposit`을 기다림
    case revealMatched(player: Player, a: Int, b: Int, count: Int)
    /// 두 접시를 열었더니 불일치 — 페널티 토큰 1개
    case revealMismatched(player: Player, a: Int, b: Int, countA: Int, countB: Int)
    /// 일치한 접시에 토큰 1개 추가 (남은 토큰 `remaining`개, 0이면 승리)
    case deposited(player: Player, plate: Int, newCount: Int, remaining: Int)
    /// 시간 초과 — 페널티 토큰 2개
    case timedOut(player: Player)
    /// 기권/몰수패 — 상대 승리
    case forfeited(player: Player)
}

enum EngineError: Error, Equatable {
    case gameFinished
    case notYourTurn
    case wrongPhase
    case plateOutOfRange
    case plateOccupied
    case samePlate
    case depositRequired      // 일치 직후에는 deposit만 가능
    case depositNotAllowed    // 일치 상태가 아닌데 deposit 시도
    case invalidDepositPlate  // 방금 연 두 접시 외의 접시에 deposit 시도
}

// MARK: - 게임 엔진

/// 「기억의 만찬」 규칙 상태기계.
/// 순수 값 타입이라 온라인 대전에서 양쪽 기기가 같은 무브 스트림으로 동일 상태를 재현한다.
struct GameEngine: Codable, Equatable {
    static let plateCount = 20
    static let placementRounds = 9   // 1+2+…+9 = 45개 토큰
    static let openingHandTokens = 10
    static let turnTimeLimit: TimeInterval = 60

    /// 접시별 토큰 개수 (커버 속 내용물 — UI는 규칙에 따라 숨겨서 표시)
    private(set) var plates: [Int]
    private(set) var phase: Phase
    /// 배치 단계의 현재 라운드 (= 이번에 놓을 토큰 개수)
    private(set) var round: Int
    private(set) var currentTurn: Player
    /// 오픈 단계에서 각 플레이어가 소진해야 하는 토큰 수
    private(set) var handTokens: [Int]
    /// 일치 판정 직후, deposit을 기다리는 두 접시
    private(set) var pendingDepositPlates: [Int]?
    private(set) var winner: Player?
    /// 몰수패/기권으로 끝났는지 (승리 연출 구분용)
    private(set) var endedByForfeit: Bool

    init() {
        plates = Array(repeating: 0, count: Self.plateCount)
        phase = .placement
        round = 1
        currentTurn = .first
        handTokens = [0, 0]
        pendingDepositPlates = nil
        winner = nil
        endedByForfeit = false
    }

    /// 배치 단계에서 아직 커버가 비어 있는 접시들
    var emptyPlates: [Int] {
        plates.indices.filter { plates[$0] == 0 }
    }

    var awaitingDeposit: Bool { pendingDepositPlates != nil }

    // MARK: 무브 적용

    @discardableResult
    mutating func apply(_ move: Move, by player: Player) throws -> MoveOutcome {
        guard phase != .finished else { throw EngineError.gameFinished }

        // 기권/몰수패(암기 위반)는 상대 턴 중에도 발생할 수 있다
        if case .forfeit = move {
            phase = .finished
            winner = player.opponent
            endedByForfeit = true
            return .forfeited(player: player)
        }

        guard player == currentTurn else { throw EngineError.notYourTurn }

        switch move {
        case .place(let plate):
            return try applyPlace(plate: plate, by: player)
        case .open(let a, let b):
            return try applyOpen(a: a, b: b, by: player)
        case .deposit(let plate):
            return try applyDeposit(plate: plate, by: player)
        case .timeout:
            return try applyTimeout(by: player)
        case .forfeit:
            fatalError("위에서 처리됨")
        }
    }

    private mutating func applyPlace(plate: Int, by player: Player) throws -> MoveOutcome {
        guard phase == .placement else { throw EngineError.wrongPhase }
        guard plates.indices.contains(plate) else { throw EngineError.plateOutOfRange }
        guard plates[plate] == 0 else { throw EngineError.plateOccupied }

        let count = round
        plates[plate] = count

        // 선→후 순으로 배치하고, 후가 놓으면 다음 라운드로
        if player == .first {
            currentTurn = .second
        } else {
            if round == Self.placementRounds {
                startOpeningPhase()
            } else {
                round += 1
                currentTurn = .first
            }
        }
        return .placed(player: player, plate: plate, count: count)
    }

    private mutating func startOpeningPhase() {
        phase = .opening
        handTokens = [Self.openingHandTokens, Self.openingHandTokens]
        currentTurn = .first
    }

    private mutating func applyOpen(a: Int, b: Int, by player: Player) throws -> MoveOutcome {
        guard phase == .opening else { throw EngineError.wrongPhase }
        guard pendingDepositPlates == nil else { throw EngineError.depositRequired }
        guard plates.indices.contains(a), plates.indices.contains(b) else { throw EngineError.plateOutOfRange }
        guard a != b else { throw EngineError.samePlate }

        if plates[a] == plates[b] {
            pendingDepositPlates = [a, b]
            return .revealMatched(player: player, a: a, b: b, count: plates[a])
        } else {
            handTokens[player.rawValue] += 1
            currentTurn = player.opponent
            return .revealMismatched(player: player, a: a, b: b, countA: plates[a], countB: plates[b])
        }
    }

    private mutating func applyDeposit(plate: Int, by player: Player) throws -> MoveOutcome {
        guard phase == .opening else { throw EngineError.wrongPhase }
        guard let pending = pendingDepositPlates else { throw EngineError.depositNotAllowed }
        guard pending.contains(plate) else { throw EngineError.invalidDepositPlate }

        plates[plate] += 1
        handTokens[player.rawValue] -= 1
        pendingDepositPlates = nil

        let remaining = handTokens[player.rawValue]
        if remaining == 0 {
            phase = .finished
            winner = player
        } else {
            currentTurn = player.opponent
        }
        return .deposited(player: player, plate: plate, newCount: plates[plate], remaining: remaining)
    }

    private mutating func applyTimeout(by player: Player) throws -> MoveOutcome {
        guard phase == .opening, pendingDepositPlates == nil else { throw EngineError.wrongPhase }
        handTokens[player.rawValue] += 2
        currentTurn = player.opponent
        return .timedOut(player: player)
    }
}
