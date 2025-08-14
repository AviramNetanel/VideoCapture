//
//  Analyzer.swift
//  videoCapture
//
//  Created by Aviram Netanel on 14/08/2025.
//

import AVFoundation
import Accelerate

final class SimpleAnalyzer: FrameAnalyzer {

    private var lastSample: [UInt8] = []
    private let sampleStep = 8 // sample every Nth pixel per row/col to reduce work

    func analyze(pixelBuffer: CVPixelBuffer, time: CMTime) -> VideoAnalysis? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard CVPixelBufferGetPlaneCount(pixelBuffer) > 0 else { return nil }

        let width  = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        guard let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)?.assumingMemoryBound(to: UInt8.self) else {
            return nil
        }

        var samples: [UInt8] = []
        samples.reserveCapacity((width / sampleStep) * (height / sampleStep))

        var sum: Int = 0
        var count: Int = 0

        var y = 0
        while y < height {
            let rowPtr = base.advanced(by: y * rowBytes)
            var x = 0
            while x < width {
                let v = rowPtr[x]
                samples.append(v)
                sum += Int(v)
                count += 1
                x += sampleStep
            }
            y += sampleStep
        }

        let avgLuma01 = Float(sum) / Float(max(count * 255, 1))

        // Motion: mean absolute difference vs previous sample
        var motion01: Float = 0
        if !lastSample.isEmpty, lastSample.count == samples.count {
            var diffSum: Int = 0
            for i in 0..<samples.count {
                diffSum += Int( abs( Int(samples[i]) - Int(lastSample[i]) ) )
            }
            // Normalize by 255 per-sample; clamp to [0,1]
            motion01 = min(1.0, Float(diffSum) / Float(samples.count * 255))
        }
        lastSample = samples

        return VideoAnalysis(averageLuma: avgLuma01, motion: motion01, time: time)
    } // analyze
} // SimpleAnalyzer
