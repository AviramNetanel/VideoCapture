//
//  VideoManager.swift
//  videoCapture
//
//  Created by Aviram Netanel on 14/08/2025.
//

import AVFoundation
import UIKit


// MARK: - Analyzer protocol (you can supply your own)
public protocol FrameAnalyzer: AnyObject {
    /// Called off the main thread on the analysis queue.
    func analyze(pixelBuffer: CVPixelBuffer, time: CMTime) -> VideoAnalysis?
} // FrameAnalyzer

// MARK: - Manager delegate
public protocol VideoManagerDelegate: AnyObject {
    func videoManager(_ manager: VideoManager, didUpdate analysis: VideoAnalysis)
    func videoManager(_ manager: VideoManager, didChangeRecording isRecording: Bool)
    func videoManager(_ manager: VideoManager, didFinishRecordingTo url: URL)
    func videoManager(_ manager: VideoManager, didFail error: Error)
} // VideoManagerDelegate

// MARK: - Analysis payload
public struct VideoAnalysis {
    /// Average scene brightness in [0, 1] (0 = dark, 1 = bright)
    public let averageLuma: Float
    /// Approx motion magnitude in [0, 1] (heuristic, 0 = static)
    public let motion: Float
    public let time: CMTime
  
  func didPass() -> Bool {
    // color the box based on brightness/motion.
    // averageLuma ~0..1, motion ~0..1
    let tooDark = self.averageLuma < 0.15
    let tooBright = self.averageLuma > 0.85
    let noMotion = self.motion < 0.05
    
    //uncomment for real-time values:
//    print("averageLuma: \(analysis.averageLuma), motion: \(analysis.motion)")
    
    let didPass = !tooDark && !tooBright && noMotion
    return didPass
  }
} // VideoAnalysis


// MARK: - VideoManager
public final class VideoManager: NSObject {

    // Public
    public weak var delegate: VideoManagerDelegate?
    public let session = AVCaptureSession()
    public var maxDuration: TimeInterval = 30 { didSet { movieOutput.maxRecordedDuration = CMTime(seconds: maxDuration, preferredTimescale: 1) } }

    /// Throttle analysis to this FPS to keep CPU/GPU happy.
    public var analysisFPS: Double = 15

    /// Inject any analyzer you want (face, barcode, ML, etc.)
    public var analyzer: FrameAnalyzer?

    // Private
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let analysisQueue = DispatchQueue(label: "video.analysis.queue", qos: .userInitiated)
  
    private var metrics = RecordingMetrics()
  
    private let videoOutput = AVCaptureVideoDataOutput() //for raw video frames
    private let movieOutput = AVCaptureMovieFileOutput() //for Recording video (+audio)
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var isConfigured = false
    private var lastAnalysisTime: CMTime = .negativeInfinity

    // Lifecycle
    public override init() {
        super.init()
        session.sessionPreset = .high
    }

    // MARK: - Permissions + Configure
  public func startSession() {
      print("▶️ startSession()")
      checkPermissions { [weak self] camOK, micOK in
          guard let self else { return }
          guard camOK else {
              print("❌ Camera permission denied")
              self.notifyError(VideoManagerError.permissionsDenied)
              return
          }
          self.sessionQueue.async {
              if !self.isConfigured { self.configureSession(micEnabled: micOK) }
              if !self.session.isRunning {
                  self.session.startRunning()
                  print("🔁 session.startRunning() called")
              }
          }
      }
  }

    public func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

  /// Ask for camera; mic optional so preview isn't blocked
  private func checkPermissions(_ completion: @escaping (_ cameraOK: Bool, _ micOK: Bool)->Void) {
      func status(_ mediaType: AVMediaType) -> AVAuthorizationStatus {
          AVCaptureDevice.authorizationStatus(for: mediaType)
      }
      let cam = status(.video)
      let mic = status(.audio)

      if cam == .authorized && (mic == .authorized || mic == .denied || mic == .restricted) {
          return completion(true, mic == .authorized)
      }

      var camOK = (cam == .authorized)
      var micOK = (mic == .authorized)
      let group = DispatchGroup()

      if cam == .notDetermined {
          group.enter()
          AVCaptureDevice.requestAccess(for: .video) { ok in camOK = ok; group.leave() }
      }
      if mic == .notDetermined {
          group.enter()
          AVCaptureDevice.requestAccess(for: .audio) { ok in micOK = ok; group.leave() }
      }

      group.notify(queue: .main) { completion(camOK, micOK) }
  }

  private func configureSession(micEnabled: Bool) {
      print("⚙️ configureSession(micEnabled: \(micEnabled))")
      session.beginConfiguration()
      session.sessionPreset = .high

      // VIDEO INPUT
      do {
          guard let cam = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) ??
                           AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
              print("❌ No camera device available")
              session.commitConfiguration()
              notifyError(VideoManagerError.noCamera)
              return
          }
          let vInput = try AVCaptureDeviceInput(device: cam)
          guard session.canAddInput(vInput) else {
              print("❌ session.canAddInput(video) == false")
              session.commitConfiguration()
              notifyError(VideoManagerError.noCamera)
              return
          }
          session.addInput(vInput)
          self.videoDeviceInput = vInput
          print("✅ Added video input:", cam.localizedName)
      } catch {
          print("❌ Video input error:", error.localizedDescription)
          session.commitConfiguration()
          notifyError(error)
          return
      }

      // AUDIO INPUT (optional)
      if micEnabled, let mic = AVCaptureDevice.default(for: .audio) {
          do {
              let aInput = try AVCaptureDeviceInput(device: mic)
              if session.canAddInput(aInput) {
                  session.addInput(aInput)
                  print("✅ Added audio input:", mic.localizedName)
              } else {
                  print("⚠️ Could not add audio input")
              }
          } catch {
              print("⚠️ Audio input error:", error.localizedDescription)
          }
      } else {
          print("ℹ️ Skipping audio input (mic not authorized)")
      }

      // MOVIE OUTPUT (for recording)
      if session.canAddOutput(movieOutput) {
          session.addOutput(movieOutput)
          movieOutput.maxRecordedDuration = CMTime(seconds: maxDuration, preferredTimescale: 1)
          if let c = movieOutput.connection(with: .video), c.isVideoStabilizationSupported {
              c.preferredVideoStabilizationMode = .auto
          }
          print("✅ Added movieOutput")
      } else {
          print("❌ session.canAddOutput(movieOutput) == false")
      }

      // VIDEO DATA OUTPUT (for analysis)
      videoOutput.alwaysDiscardsLateVideoFrames = true
      videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String:
                                   kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
      videoOutput.setSampleBufferDelegate(self, queue: analysisQueue)
      if session.canAddOutput(videoOutput) {
          session.addOutput(videoOutput)
          if let c = videoOutput.connection(with: .video), c.isVideoStabilizationSupported {
              c.preferredVideoStabilizationMode = .auto
          }
          print("✅ Added videoDataOutput")
      } else {
          print("❌ session.canAddOutput(videoDataOutput) == false")
      }

      session.commitConfiguration()
      isConfigured = true
      print("✅ Session configured")
  } // configureSession

    // MARK: - Recording
  
  public func setGreenState(_ isGreen: Bool) {
    analysisQueue.async { [weak self] in
      self?.metrics.setGreen(isGreen)
    }
  }
  
  public func startRecording(to url: URL) {
    sessionQueue.async { [weak self] in
      guard let self else { return }
      if self.movieOutput.isRecording { return } // already recording
      
      //TODO: handle orientation
      //          if let connection = self.movieOutput.connection(with: .video),
      //               connection.isVideoOrientationSupported {
      //                // Keep orientation roughly in sync
      //                connection.videoOrientation = self.currentVideoOrientation()
      //            }
      self.analysisQueue.async { [weak self] in self?.metrics.begin() }
      
      self.movieOutput.startRecording(to: url, recordingDelegate: self)
      DispatchQueue.main.async { [weak self] in self?.delegate?.videoManager(self!, didChangeRecording: true) }
    }
  }
  
  public func stopRecording() {
    sessionQueue.async { [weak self] in
      self?.movieOutput.stopRecording()
    }
  }
  


    // MARK: - Orientation (call from VC on rotation/layout changes)
    public func updateVideoOrientation(using interfaceOrientation: UIInterfaceOrientation?) {
      //TODO: handle orientation
//        guard let orientation = interfaceOrientation else { return }
//        sessionQueue.async { [weak self] in
//            guard let self else { return }
//          if let conn = self.movieOutput.connection(with: .video), conn.isVideoOrientationSupported {
//                conn.videoOrientation = orientation.toAVCaptureVideoOrientation() ?? .portrait
//            }
//          if let conn = self.videoOutput.connection(with: .video), conn.isVideoOrientationSupported {
//                conn.videoOrientation = orientation.toAVCaptureVideoOrientation() ?? .portrait
//            }
//        }
    }
  
  //TODO: handle orientation
//    private func currentVideoOrientation() -> AVCaptureVideoOrientation {
//        guard let o = UIApplication.shared.connectedScenes
//            .compactMap({ ($0 as? UIWindowScene)?.interfaceOrientation }).first else { return .portrait }
//        return o.toAVCaptureVideoOrientation() ?? .portrait
//    }

    // MARK: - Utils
  private func notifyError(_ error: Error) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.delegate?.videoManager(self, didFail: error)
      print(error)
    }
  }
} // VideoManager

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate (real-time frames)
extension VideoManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput,
                              didOutput sampleBuffer: CMSampleBuffer,
                              from connection: AVCaptureConnection) {

        guard let analyzer, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Throttle to analysisFPS
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let minDelta = CMTime(seconds: 1.0 / max(1.0, analysisFPS), preferredTimescale: 600)
        if time - lastAnalysisTime < minDelta { return }
        lastAnalysisTime = time

        // Run analysis off the main thread (we're already on analysisQueue)
        if let result = analyzer.analyze(pixelBuffer: buffer, time: time) {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.videoManager(self, didUpdate: result)
            }
        }
    } // captureOutput didOutput
} // VideoDataOutput delegate

// MARK: - AVCaptureFileOutputRecordingDelegate (recording callbacks)
extension VideoManager: AVCaptureFileOutputRecordingDelegate {
    public func fileOutput(_ output: AVCaptureFileOutput,
                           didFinishRecordingTo outputFileURL: URL,
                           from connections: [AVCaptureConnection],
                           error: Error?) {

      // Finalize metrics
      analysisQueue.async { [weak self] in self?.metrics.endNow() }
      
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.videoManager(self, didChangeRecording: false)

            if let err = error as? AVError, err.code == .maximumDurationReached {
                // Auto-stop hit the cap; still a success case
                self.delegate?.videoManager(self, didFinishRecordingTo: outputFileURL)
                return
            }
            if let e = error {
                self.delegate?.videoManager(self, didFail: e)
            } else {
                self.delegate?.videoManager(self, didFinishRecordingTo: outputFileURL)
            }
        }
      
      // Proceed to save JSON (off the main thread)
      saveMetadataJSON(alongside: outputFileURL, recordingError: error)
    }
}// MovieFileOutput delegate


//MARK: - Save Json
extension VideoManager {
    func saveMetadataJSON(alongside videoURL: URL, recordingError: Error?) {
        // If recording failed, you could skip writing metadata. Here we still write what we have.
        let asset = AVURLAsset(url: videoURL)

        Task.detached { [weak self] in
            guard let self else { return }
            do {
                // iOS 16+: async duration load
                let dur = try await asset.load(.duration)
                let seconds = CMTimeGetSeconds(dur)

                // Snapshot metrics (thread-safe)
                var wasGreen = false
                var greenSecs: CFTimeInterval = 0
                await withCheckedContinuation { cont in
                    self.analysisQueue.async {
                        wasGreen = self.metrics.wasGreenEver
                        greenSecs = self.metrics.greenAccum
                        cont.resume()
                    }
                }

                let meta = RecordingMetadata(
                    video_filename: videoURL.lastPathComponent,
                    recording_duration_seconds: seconds,
                    was_condition_met: wasGreen,
                    time_in_green_state_seconds: Double(greenSecs)
                )

                let data = try JSONEncoder().encode(meta)
                let jsonURL = videoURL.deletingPathExtension().appendingPathExtension("json")
                try data.write(to: jsonURL, options: .atomic)

                // Optional: notify your VC
                DispatchQueue.main.async { [weak self] in
                    // Add a delegate method:
                    // self?.delegate?.videoManager(self!, didSaveMetadataAt: jsonURL)
                    print("📝 Saved metadata JSON:", jsonURL.lastPathComponent)
                }
            } catch {
                print("⚠️ Failed to save metadata JSON:", error.localizedDescription)
            }
        }
    } // saveMetadataJSON

  }


// MARK: - Errors & helpers
public enum VideoManagerError: LocalizedError {
    case permissionsDenied
    case noCamera

    public var errorDescription: String? {
        switch self {
        case .permissionsDenied: return "Camera/Microphone permission was denied."
        case .noCamera: return "No compatible camera was found."
        }
    }
}

//TODO: handle orientation
//private extension UIInterfaceOrientation {
//    func toAVCaptureVideoOrientation() -> AVCaptureVideoOrientation? {
//        switch self {
//        case .portrait: return .portrait
//        case .portraitUpsideDown: return .portraitUpsideDown
//        case .landscapeLeft: return .landscapeLeft
//        case .landscapeRight: return .landscapeRight
//        default: return nil
//        }
//    }
//}

