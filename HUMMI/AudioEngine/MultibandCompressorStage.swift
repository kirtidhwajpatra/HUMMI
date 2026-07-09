//
//  MultibandCompressorStage.swift
//  HUMMI
//

import Accelerate

/// 3-band compression (<250 Hz, 250 Hz-4 kHz, >4 kHz) at a moderate
/// ratio. Zero-phase crossovers so the bands sum back exactly; the
/// threshold sits relative to each band's own level, with RMS-restoring
/// auto-makeup per band. Port of tools/spike/polish.py
/// multiband_compress(): the scipy butter-4 sosfiltfilt crossovers are
/// realized in the frequency domain as the identical |H(ω)|² response.
nonisolated final class MultibandCompressorStage: BufferStage {
    let name = "Multiband compressor"
    var isEnabled = true

    static let lowCrossoverHz = 250.0
    static let highCrossoverHz = 4_000.0
    static let filterOrder = 4  // per pass; forward+backward doubles it

    private let ratio: Double

    init(parameters: PresetParameters) {
        self.ratio = parameters.multibandRatio
    }

    func process(_ samples: [Float]) throws -> [Float] {
        let (low, high) = try Self.splitBands(samples)
        var mid = vDSP.subtract(samples, low)
        mid = vDSP.subtract(mid, high)

        var output = [Float](repeating: 0, count: samples.count)
        for band in [low, mid, high] {
            output = vDSP.add(output, compressBand(band))
        }
        return output
    }

    /// Threshold 6 dB above the band's own RMS (bites on its peaks),
    /// then makeup gain restoring the band's RMS, capped at +12 dB.
    private func compressBand(_ band: [Float]) -> [Float] {
        let rmsIn = Self.rms(band)
        guard rmsIn >= 1e-6 else { return band }  // effectively empty band
        let compressor = PeakCompressor(
            thresholdDB: 20 * log10(rmsIn) + 6.0, ratio: ratio,
            attackMS: 15, releaseMS: 150)
        let compressed = compressor.process(band)
        let makeup = Float(min(rmsIn / max(Self.rms(compressed), 1e-9), 4.0))
        return vDSP.multiply(makeup, compressed)
    }

    // MARK: - Zero-phase crossovers

    /// Low band (butter-4 lowpass at 250 Hz, applied forward+backward =
    /// |H|²) and high band (same at 4 kHz highpass), both zero-phase.
    static func splitBands(_ samples: [Float]) throws -> (low: [Float], high: [Float]) {
        // Margin so the zero-phase filter's symmetric tails don't wrap.
        var fftSize = 1024
        while fftSize < samples.count + 19_200 { fftSize *= 2 }
        let fft = try RealFFT(count: fftSize)

        var padded = samples
        padded.append(contentsOf: [Float](repeating: 0, count: fftSize - samples.count))
        let (re, im) = fft.forward(padded)

        let bins = fft.binCount
        var lowGain = [Float](repeating: 0, count: bins)
        var highGain = [Float](repeating: 0, count: bins)
        for b in 0..<bins {
            let freq = Double(b) * DFNContract.sampleRate / Double(fftSize)
            lowGain[b] = Float(zeroPhaseButterGain(
                freq: freq, cutoff: lowCrossoverHz, highpass: false))
            highGain[b] = Float(zeroPhaseButterGain(
                freq: freq, cutoff: highCrossoverHz, highpass: true))
        }

        let low = fft.inverse(
            re: vDSP.multiply(re, lowGain), im: vDSP.multiply(im, lowGain))
        let high = fft.inverse(
            re: vDSP.multiply(re, highGain), im: vDSP.multiply(im, highGain))
        return (Array(low[0..<samples.count]), Array(high[0..<samples.count]))
    }

    /// |H(ω)|² of a bilinear-transform butter-4: the exact magnitude
    /// response of scipy sosfiltfilt(butter(4, fc), x).
    static func zeroPhaseButterGain(
        freq: Double, cutoff: Double, highpass: Bool,
        sampleRate: Double = DFNContract.sampleRate
    ) -> Double {
        let nyquist = sampleRate / 2
        if freq <= 0 { return highpass ? 0 : 1 }
        if freq >= nyquist { return highpass ? 1 : 0 }
        let warped = tan(.pi * freq / sampleRate)
        let warpedCut = tan(.pi * cutoff / sampleRate)
        let x = highpass ? warpedCut / warped : warped / warpedCut
        return 1.0 / (1.0 + pow(x, Double(2 * filterOrder)))
    }

    static func rms(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return 0 }
        var sum = 0.0
        for s in samples {
            sum += Double(s) * Double(s)
        }
        return (sum / Double(samples.count)).squareRoot()
    }
}
