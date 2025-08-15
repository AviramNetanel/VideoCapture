//
//  CameraVC+VideoManagerDelegate.swift
//  videoCapture
//
//  Created by Aviram Netanel on 14/08/2025.
//

import UIKit

extension CameraViewController: VideoManagerDelegate {
  func videoManager(_ manager: VideoManager, didPassAnalysis: Bool) {
    // Called on main thread.

    let color = didPassAnalysis ? UIColor.systemGreen : UIColor.systemRed
        
    videoManager.setGreenState(didPassAnalysis)
    
    self.recordBoundingBox.layer.borderColor = color.cgColor
  } // didUpdate
  
  func videoManager(_ manager: VideoManager, didChangeRecording isRecording: Bool) {
    // Keep UI in sync with actual start/stop
    self.isRecording = isRecording
    if isRecording {
      setRecordingUI(isRecording: true)
      startProgressAnimation()
    } else {
      setRecordingUI(isRecording: false)
    }
  } // didChangeRecording
  
  func videoManager(_ manager: VideoManager, didFinishRecordingTo url: URL) {
    // Update gallery of local files
    isRecording = false
    stopProgressAnimation()
    reloadLocalVideos()
  } // didFinishRecordingTo
  
  func videoManager(_ manager: VideoManager, didFail error: Error) {
    // Show an alert or inline message
    print("Video error:", error.localizedDescription)
    self.isRecording = false
  } // didFail
} // VideoManagerDelegate
