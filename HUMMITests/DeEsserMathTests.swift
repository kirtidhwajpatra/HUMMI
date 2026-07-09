//
//  DeEsserMathTests.swift
//  HUMMITests
//

import Foundation
import Testing
@testable import HUMMI

struct DeEsserMathTests {
    @Test func medianMatchesNumpy() {
        #expect(DeEsserStage.median([3, 1, 2]) == 2)
        #expect(DeEsserStage.median([4, 1, 3, 2]) == 2.5)  // mean of middles
        #expect(DeEsserStage.median([7]) == 7)
    }

    @Test func movingAverage3ZeroPadsEdges() {
        // np.convolve(x, ones(3)/3, mode="same")
        let out = DeEsserStage.movingAverage3([3, 6, 9])
        #expect(abs(out[0] - 3) < 1e-12)   // (0+3+6)/3
        #expect(abs(out[1] - 6) < 1e-12)   // (3+6+9)/3
        #expect(abs(out[2] - 5) < 1e-12)   // (6+9+0)/3
    }

    @Test func bandCoversSixToNineKilohertz() {
        let bins = DeEsserStage.bandBins(fftSize: 1024)
        // 6000/46.875 = 128, 9000/46.875 = 192, inclusive
        #expect(bins.first == 128)
        #expect(bins.last == 192)
        #expect(bins.count == 65)
    }

    @Test func cutsOnlyAboveThreshold() {
        // Flat levels: median = level, threshold = level + 8 → no cut.
        let flat = DeEsserStage.cutsDB(bandLevelsDB: [-30, -30, -30, -30], ratio: 4)
        #expect(flat != nil)
        #expect(flat.map { $0.allSatisfy { $0 == 0 } } == true)

        // One sibilant frame 12 dB above the rest: cut = (12-8)·(1-1/4) = 3,
        // then spread by the 3-frame smoother.
        let cuts = DeEsserStage.cutsDB(
            bandLevelsDB: [-30, -30, -18, -30, -30], ratio: 4)
        #expect(cuts != nil)
        if let cuts {
            #expect(abs(cuts[2] - 1.0) < 1e-9)  // 3 dB averaged over 3 frames
            #expect(abs(cuts[1] - 1.0) < 1e-9)
            #expect(cuts[0] == 0)
        }
    }

    @Test func silentClipCutsNothing() {
        #expect(DeEsserStage.cutsDB(bandLevelsDB: [-120, -100], ratio: 4) == nil)
    }

    @Test func hannWindowIsPeriodic() {
        let w = DeEsserStage.hannPeriodic(1024)
        #expect(w[0] == 0)
        #expect(abs(w[512] - 1) < 1e-6)
        let sum = w.reduce(Float(0), +)
        #expect(abs(sum - 512) < 1e-2)  // periodic hann sums to n/2
    }

    @Test func roundTripPreservesCleanSignal() throws {
        // A 1 kHz tone has no 6-9 kHz energy: the de-esser must pass it
        // through (analysis/resynthesis is exact where gain is 1).
        let tone = (0..<48_000).map { Float(sin(2 * Double.pi * 1_000 * Double($0) / 48_000)) }
        let out = try DeEsserStage(parameters: .default).process(tone)
        var maxErr: Float = 0
        for i in 0..<tone.count {
            maxErr = max(maxErr, abs(out[i] - tone[i]))
        }
        #expect(maxErr < 1e-4)
    }
}
