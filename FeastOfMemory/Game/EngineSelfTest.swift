import Foundation

/// 엔진 규칙 검증 — 실제 방송 대국(이세돌 vs 홍진호)을 그대로 리플레이해서
/// 엔진이 나무위키에 기록된 진행 결과와 동일하게 동작하는지 확인한다.
/// DEBUG 빌드에서 앱 시작 시 1회 실행된다.
enum EngineSelfTest {
    /// 접시 번호(1~20)를 인덱스(0~19)로
    private static func p(_ number: Int) -> Int { number - 1 }

    static func run() {
        #if DEBUG
        do {
            try replayLeeSedolVsHongJinho()
            print("[EngineSelfTest] 이세돌 vs 홍진호 리플레이 검증 통과 ✅")
        } catch {
            assertionFailure("[EngineSelfTest] 엔진 규칙 검증 실패: \(error)")
        }
        #endif
    }

    private enum TestError: Error { case mismatch(String) }

    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw TestError.mismatch(message) }
    }

    static func replayLeeSedolVsHongJinho() throws {
        var engine = GameEngine()

        // ── 배치: (라운드 = 토큰 개수, 선 이세돌 / 후 홍진호)
        let placements: [(first: Int, second: Int)] = [
            (20, 18), (3, 12), (6, 10), (16, 14), (11, 15),
            (5, 8), (2, 19), (7, 17), (1, 13),
        ]
        for (round, pair) in placements.enumerated() {
            let count = round + 1
            let o1 = try engine.apply(.place(plate: p(pair.first)), by: .first)
            try expect(o1 == .placed(player: .first, plate: p(pair.first), count: count), "배치 R\(count) 선")
            let o2 = try engine.apply(.place(plate: p(pair.second)), by: .second)
            try expect(o2 == .placed(player: .second, plate: p(pair.second), count: count), "배치 R\(count) 후")
        }
        try expect(engine.phase == .opening, "배치 완료 후 오픈 단계 진입")
        try expect(engine.plates[p(4)] == 0 && engine.plates[p(9)] == 0, "4번·9번 접시는 0개")
        try expect(engine.handTokens == [10, 10], "오픈 단계 시작 토큰 10:10")

        // ── 오픈: (오픈한 두 접시, 일치 여부, 성공 시 토큰을 추가한 접시)
        // 각 턴 끝의 스코어(이세돌:홍진호)는 방송 기록과 대조
        struct Turn { let player: Player; let a: Int; let b: Int; let deposit: Int? }
        let turns: [Turn] = [
            // 1턴 — 9:9
            Turn(player: .first, a: 1, b: 13, deposit: 1),
            Turn(player: .second, a: 17, b: 7, deposit: 17),
            // 2턴 — 8:8
            Turn(player: .first, a: 12, b: 3, deposit: 3),
            Turn(player: .second, a: 3, b: 10, deposit: 10),
            // 3턴 — 7:7
            Turn(player: .first, a: 20, b: 18, deposit: 20),
            Turn(player: .second, a: 11, b: 15, deposit: 15),
            // 4턴 — 8:6 (이세돌 3-4 실패)
            Turn(player: .first, a: 6, b: 10, deposit: nil),
            Turn(player: .second, a: 3, b: 6, deposit: 3),
            // 5턴 — 7:5
            Turn(player: .first, a: 3, b: 10, deposit: 10),
            Turn(player: .second, a: 10, b: 11, deposit: 11),
            // 6턴 — 6:4
            Turn(player: .first, a: 5, b: 15, deposit: 15),
            Turn(player: .second, a: 3, b: 14, deposit: 14),
            // 7턴 — 5:3
            Turn(player: .first, a: 16, b: 3, deposit: 3),
            Turn(player: .second, a: 3, b: 14, deposit: 14),
            // 8턴 — 6:2 (이세돌 6-4 실패)
            Turn(player: .first, a: 11, b: 16, deposit: nil),
            Turn(player: .second, a: 11, b: 14, deposit: 11),
            // 9턴 — 7:1 (이세돌 4-5 실패; 위키 표의 "7:2"는 오기 —
            // 홍진호는 9턴 연속 성공이므로 10-9=1개가 맞고, 10턴의 8:0과도 이쪽이 정합)
            Turn(player: .first, a: 16, b: 10, deposit: nil),
            Turn(player: .second, a: 3, b: 10, deposit: 10),
            // 10턴 — 8:0 (이세돌 실패, 홍진호 마지막 토큰 소진)
            Turn(player: .first, a: 16, b: 3, deposit: nil),
            Turn(player: .second, a: 10, b: 14, deposit: 14),
        ]
        let scoresAfterEachRound = [
            [9, 9], [8, 8], [7, 7], [8, 6], [7, 5],
            [6, 4], [5, 3], [6, 2], [7, 1], [8, 0],
        ]

        for (index, turn) in turns.enumerated() {
            let outcome = try engine.apply(.open(a: p(turn.a), b: p(turn.b)), by: turn.player)
            if let deposit = turn.deposit {
                guard case .revealMatched = outcome else {
                    throw TestError.mismatch("턴 \(index): 일치해야 하는데 불일치 (\(turn.a)&\(turn.b))")
                }
                try engine.apply(.deposit(plate: p(deposit)), by: turn.player)
            } else {
                guard case .revealMismatched = outcome else {
                    throw TestError.mismatch("턴 \(index): 불일치해야 하는데 일치 (\(turn.a)&\(turn.b))")
                }
            }
            if index % 2 == 1 {
                let expected = scoresAfterEachRound[index / 2]
                try expect(engine.handTokens == expected,
                           "턴 \(index / 2 + 1) 스코어 \(engine.handTokens) ≠ \(expected)")
            }
        }

        try expect(engine.phase == .finished, "게임 종료")
        try expect(engine.winner == .second, "홍진호(후) 승리")
    }
}
