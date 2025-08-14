//
//  VideoPreviewView.swift
//  videoCapture
//
//  Created by Aviram Netanel on 15/08/2025.
//

import UIKit
import AVFoundation

final class VideoPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    var session: AVCaptureSession? {
        get { videoPreviewLayer.session }
        set { videoPreviewLayer.session = newValue }
    }
}
