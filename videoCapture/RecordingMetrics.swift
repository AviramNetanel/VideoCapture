//
//  RecordingMetrics.swift
//  videoCapture
//
//  Created by Aviram Netanel on 15/08/2025.
//

import Foundation
import AVFoundation

// MARK: - Recording metadata model (JSON)
struct RecordingMetadata: Codable {
    let video_filename: String
    let recording_duration_seconds: Double
    let was_condition_met: Bool
    let time_in_green_state_seconds: Double
} // RecordingMetadata

// MARK: - Internal metrics
struct RecordingMetrics {
    var active = false
    var wasGreenEver = false
    var greenAccum: CFTimeInterval = 0
    var greenBeganAt: CFTimeInterval?

    mutating func begin() {
        active = true
        wasGreenEver = false
        greenAccum = 0
        greenBeganAt = nil
    } // begin

    mutating func endNow() {
        guard active else { return }
        if let t0 = greenBeganAt {
            greenAccum += CACurrentMediaTime() - t0
        }
        greenBeganAt = nil
        active = false
    } // endNow

    mutating func setGreen(_ isGreen: Bool) {
        guard active else { return }
        let now = CACurrentMediaTime()
        if isGreen {
            if greenBeganAt == nil { greenBeganAt = now; wasGreenEver = true }
        } else if let t0 = greenBeganAt {
            greenAccum += now - t0
            greenBeganAt = nil
        }
    } // setGreen
} // RecordingMetrics
