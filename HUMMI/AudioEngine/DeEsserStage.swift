//
//  DeEsserStage.swift
//  HUMMI
//

import Accelerate

/// STFT de-esser: dynamic cut of 6-9 kHz sibilance. The threshold sits
/// 8 dB above the clip's typical (median) band level, so it only bites
/// on sibilants. Port of tools/spike/polish.py deess() — 1024-point
/// hann frames, 256-sample hop, scipy-compatible spectrum scaling.
nonisolated final class DeEsserStage: BufferStage {
    let name = "De-esser"
    var isEnabled = true

    static let fftSize = 1024
    static let hop = 256
    static let bandLowHz = 6_000.0
    static let bandHighHz = 9_000.0
    static let thresholdMarginDB = 8.0

    private let ratio: Double

    init(parameters: PresetParameters) {
        self.ratio = parameters.deEsserRatio
    }

    func process(_ samples: [Float]) throws -> [Float] {
        let n = Self.fftSize
        let hop = Self.hop
        let fft = try RealFFT(count: n)
        let window = Self.hannPeriodic(n)
        let windowSum = window.reduce(Float(0), +)

        // scipy stft boundary='zeros' + padded=True framing.
        var extended = [Float](repeating: 0, count: n / 2)
        extended.append(contentsOf: samples)
        extended.append(contentsOf: [Float](repeating: 0, count: n / 2))
        let remainder = (extended.count - n) % hop
        if remainder != 0 {
            extended.append(contentsOf: [Float](repeating: 0, count: hop - remainder))
        }
        let frames = (extended.count - n) / hop + 1

        let band = Self.bandBins(fftSize: n)

        // Pass 1: per-frame band level -> per-frame cut.
        var bandLevelsDB = [Double](repeating: 0, count: frames)
        var windowed = [Float](repeating: 0, count: n)
        for k in 0..<frames {
            let start = k * hop
            vDSP.multiply(window, extended[start..<start + n], result: &windowed)
            let (re, im) = fft.forward(windowed)
            var sum = 0.0
            for b in band {
                let scaledRe = Double(re[b]) / Double(windowSum)
                let scaledIm = Double(im[b]) / Double(windowSum)
                sum += scaledRe * scaledRe + scaledIm * scaledIm
            }
            bandLevelsDB[k] = 20 * log10((sum / Double(band.count)).squareRoot() + 1e-12)
        }
        guard let cutsDB = Self.cutsDB(bandLevelsDB: bandLevelsDB, ratio: ratio) else {
            return samples  // no active frames; nothing to de-ess
        }

        // Pass 2: apply the band gain, weighted overlap-add resynthesis.
        var output = [Float](repeating: 0, count: extended.count)
        var norm = [Float](repeating: 0, count: extended.count)
        let windowSquared = vDSP.multiply(window, window)
        for k in 0..<frames {
            let start = k * hop
            vDSP.multiply(window, extended[start..<start + n], result: &windowed)
            var (re, im) = fft.forward(windowed)
            let gain = Float(pow(10.0, -cutsDB[k] / 20.0))
            for b in band {
                re[b] *= gain
                im[b] *= gain
            }
            let frame = fft.inverse(re: re, im: im)
            for i in 0..<n {
                output[start + i] += frame[i] * window[i]
                norm[start + i] += windowSquared[i]
            }
        }
        var result = [Float](repeating: 0, count: samples.count)
        for i in 0..<samples.count {
            let w = norm[n / 2 + i]
            result[i] = w > 1e-10 ? output[n / 2 + i] / w : 0
        }
        return result
    }

    // MARK: - Pure math (unit-tested)

    /// Per-frame cut in dB from per-frame 6-9 kHz band levels: threshold =
    /// median(levels > -80) + 8 dB, cut above it by (1 - 1/ratio),
    /// de-fluttered with a 3-frame moving average. Returns nil when no
    /// frame is active (silent clip).
    static func cutsDB(bandLevelsDB: [Double], ratio: Double) -> [Double]? {
        let active = bandLevelsDB.filter { $0 > -80 }
        guard !active.isEmpty else { return nil }
        let thresholdDB = median(active) + thresholdMarginDB
        let raw = bandLevelsDB.map { max($0 - thresholdDB, 0) * (1 - 1 / ratio) }
        return movingAverage3(raw)
    }

    /// numpy-style median: mean of the two middle values for even counts.
    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 1 {
            return sorted[mid]
        }
        return (sorted[mid - 1] + sorted[mid]) / 2
    }

    /// np.convolve(x, ones(3)/3, mode="same"): zero-padded edges.
    static func movingAverage3(_ values: [Double]) -> [Double] {
        let n = values.count
        return (0..<n).map { i in
            let left = i > 0 ? values[i - 1] : 0
            let right = i < n - 1 ? values[i + 1] : 0
            return (left + values[i] + right) / 3
        }
    }

    /// Bin indices whose center frequency lies in [6 kHz, 9 kHz].
    static func bandBins(fftSize: Int, sampleRate: Double = DFNContract.sampleRate) -> [Int] {
        (0...(fftSize / 2)).filter { b in
            let freq = Double(b) * sampleRate / Double(fftSize)
            return freq >= bandLowHz && freq <= bandHighHz
        }
    }

    /// Periodic hann, matching scipy.signal.get_window("hann", n).
    static func hannPeriodic(_ n: Int) -> [Float] {
        (0..<n).map { i in
            Float(0.5 * (1 - cos(2 * Double.pi * Double(i) / Double(n))))
        }
    }
}
