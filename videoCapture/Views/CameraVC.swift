//
//  ViewController.swift
//  videoCapture
//
//  Created by Aviram Netanel on 14/08/2025.
//

import UIKit
import AVFoundation
import AVKit

//MARK: - LocalVideo
struct LocalVideo {
  let url: URL
  var duration: TimeInterval?  // filled in asynchronously
}

//MARK: -

class CameraViewController: UIViewController {
  
  //MARK: Constants
  private let maxVideoDuration = 30.0
  private let analysisFPS = 15.0
  private let imageCellSize = CGSize(width: 100, height: 100)
  
  // MARK:  properties
  private let session = AVCaptureSession()
  private let sessionQueue = DispatchQueue(label: "camera.session.queue")
  private var videoDeviceInput: AVCaptureDeviceInput?
  private let movieOutput = AVCaptureMovieFileOutput()
  private var videoPreviewView = VideoPreviewView()
  
  private var isRecording: Bool = false
  private var isObservingPhotoLibrary = false
  private var isSessionConfigured = false
  private var elapsedTime: TimeInterval = 0.0
  private var timer: Timer?
  
  // Video Manager
  let videoManager = VideoManager()
  private let analyzer = SimpleAnalyzer()
  
  // MARK: grid state
  private var localVideos: [LocalVideo] = []
  private let thumbCache = NSCache<NSURL, UIImage>()
  private let thumbQueue = DispatchQueue(label: "thumb.gen.queue", qos: .userInitiated)
  private var gridItemSize: CGSize = .zero
  
  // MARK: UI properties
  @IBOutlet weak var recordBoundingBox: UIView!
  @IBOutlet weak var recordButton: UIButton!
  @IBOutlet weak var savedVideosCollection: UICollectionView!
  @IBOutlet weak var progressBar: UIProgressView!
  
  // MARK: - Lifecycle
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
        
    recordButton.addTarget(self, action: #selector(toggleRecording), for: .touchUpInside)
    
    // Prepare permissions + session
    checkPermissionsAndConfigure()
        
    configureSavedVideosCollectionView()
    configureRecordBoundingBox()
    configureProgressBar()
    configureVideoPreviewView()
    
    reloadLocalVideos()
    
    // VideoManager wiring
    videoManager.delegate = self
    videoManager.analyzer = analyzer
    videoManager.maxDuration = maxVideoDuration
    videoManager.analysisFPS = analysisFPS
    videoManager.startSession()

  } // viewDidLoad
  
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    videoPreviewView.frame = view.bounds
    self.configureSavedVideosSize()
    
    //TODO: handle orientation
//    if let c = previewLayer.videoPreviewLayer.connection, c.isVideoOrientationSupported {
//        c.videoOrientation = currentVideoOrientation()
//    }
  }
  
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    sessionQueue.async { [weak self] in
      guard let self = self else { return }
      if self.isSessionConfigured, !self.session.isRunning {
        self.session.startRunning()
      }
    }
  }
  
  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    sessionQueue.async { [weak self] in
      self?.session.stopRunning()
    }
  }
  
  //MARK: -
  private func configureProgressBar(){
    progressBar.progress = 0.0
    progressBar.isHidden = true
  }
  
  private func configureRecordBoundingBox(){
    recordBoundingBox.layer.cornerRadius = 25
    recordBoundingBox.layer.borderColor = UIColor.gray.cgColor
    recordBoundingBox.layer.borderWidth = 2.0
    recordBoundingBox.clipsToBounds = true
  }
  
  private func configureVideoPreviewView(){
    videoPreviewView.videoPreviewLayer.videoGravity = .resizeAspectFill
    videoPreviewView.session = videoManager.session
    view.layer.insertSublayer(videoPreviewView.videoPreviewLayer, at: 0)
  }
  
  private func configureSavedVideosCollectionView(){
    // Collection view wiring
    savedVideosCollection.dataSource = self
    savedVideosCollection.delegate = self
      
    savedVideosCollection.register(VideoGridCell.self,
                                   forCellWithReuseIdentifier: VideoGridCell.reuseIdentifier)
    
    if let flow = savedVideosCollection.collectionViewLayout as? UICollectionViewFlowLayout {
        flow.scrollDirection = .horizontal
        flow.minimumLineSpacing = 8
        flow.minimumInteritemSpacing = 8
        flow.estimatedItemSize = .zero // disable self-sizing; we’ll provide exact size
        savedVideosCollection.contentInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
    }
    
    //long press to delete:
    let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
    longPress.minimumPressDuration = 0.5
    savedVideosCollection.addGestureRecognizer(longPress)
  }
  
  private func configureSavedVideosSize() {
    if let flow = savedVideosCollection.collectionViewLayout as? UICollectionViewFlowLayout {
        let columns: CGFloat = 3
        let spacing: CGFloat = 6
        let inset = savedVideosCollection.contentInset.left + savedVideosCollection.contentInset.right
        let totalSpacing = (columns - 1) * spacing + inset
        let width = savedVideosCollection.bounds.width
        let itemSide = floor((width - totalSpacing) / columns)
        let newSize = CGSize(width: itemSide, height: itemSide)
        if flow.itemSize != newSize {
            flow.itemSize = newSize
            gridItemSize = CGSize(width: newSize.width * UIScreen.main.scale,
                                  height: newSize.height * UIScreen.main.scale) // pixel size for thumbnails
            savedVideosCollection.collectionViewLayout.invalidateLayout()
        }
    }
  }
  
  // MARK: - Permissions + Session
  private func checkPermissionsAndConfigure() {
       let group = DispatchGroup()

       var cameraGranted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
       var micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized

       if !cameraGranted {
           group.enter()
           AVCaptureDevice.requestAccess(for: .video) { granted in
               cameraGranted = granted
               group.leave()
           }
       }

       if !micGranted {
           group.enter()
           AVCaptureDevice.requestAccess(for: .audio) { granted in
               micGranted = granted
               group.leave()
           }
       }

       group.notify(queue: .main) { [weak self] in
           guard let self = self else { return }
           guard cameraGranted && micGranted else {
               self.presentPermissionAlert()
               return
           }
       }
   } // checkPermissionsAndConfigure
  
  private func presentPermissionAlert() {
    let alert = UIAlertController(
      title: "Permissions Needed",
      message: "Please enable Camera and Microphone access in Settings to record video.",
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "OK", style: .default))
    present(alert, animated: true)
  }
    
  // MARK: - Recording
//  @objc private func toggleRecording() {
//      if movieOutput.isRecording {
//          movieOutput.stopRecording()
//          setRecordingUI(isRecording: false)
//          stopProgressAnimation()
//          return
//      }
//
//    //TODO: handle orientation
////      if let connection = movieOutput.connection(with: .video),
////         connection.isVideoOrientationSupported {
////          connection.videoOrientation = currentVideoOrientation()
////      }
//
//      // ⬇️ Write directly into the app's Documents/CapturedVideos
//      let outputURL = VideoStore.newRecordingURL()
//
//      setRecordingUI(isRecording: true)
//      startProgressAnimation()
//      movieOutput.startRecording(to: outputURL, recordingDelegate: self)
//  } // toggleRecording
  
  @objc private func toggleRecording() {
    if self.isRecording {
          videoManager.stopRecording()
          setRecordingUI(isRecording: false)
          stopProgressAnimation()
      } else {
          setRecordingUI(isRecording: true)
          startProgressAnimation()
          let url = VideoStore.newRecordingURL()    // your local storage helper
          videoManager.startRecording(to: url)
      }
    self.isRecording.toggle()
  } // toggleRecording
  
  func setRecordingUI(isRecording: Bool) {
    UIView.transition(with: recordButton, duration: 0.2, options: .transitionCrossDissolve, animations: {
      if isRecording {
        self.recordButton.setImage(UIImage(systemName: "stop.circle.fill"), for: .normal)
        self.recordButton.tintColor = .white
      } else {
        self.recordButton.setImage(UIImage(systemName: "record.circle"), for: .normal)
        self.recordButton.tintColor = .systemRed
        //            self.ringView.layer.borderColor = UIColor.systemGray4.cgColor
      }
    })
  } // setRecordingUI
  

  func stopProgressAnimation(){
    progressBar.isHidden = true
  }
  
  func startProgressAnimation(){
    progressBar.isHidden = false
    elapsedTime = 0.0
    progressBar.progress = 0.0
    
    timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] t in
      guard let self = self else { return }
      self.elapsedTime += 0.05
      let progress = Float(self.elapsedTime / self.maxVideoDuration)
      self.progressBar.setProgress(min(progress, 1.0), animated: true)
      
      if self.elapsedTime >= self.maxVideoDuration {
        t.invalidate()
      }
    }
  }
}//CameraViewController

// MARK: - AVCaptureFileOutputRecordingDelegate
extension CameraViewController: AVCaptureFileOutputRecordingDelegate {
  func fileOutput(_ output: AVCaptureFileOutput,
                  didFinishRecordingTo outputFileURL: URL,
                  from connections: [AVCaptureConnection],
                  error: Error?) {

      DispatchQueue.main.async { [weak self] in
          self?.setRecordingUI(isRecording: false)
          if let avErr = error as? AVError, avErr.code == .maximumDurationReached {
//              self?.stopProgressDepletion(finalizeToEmpty: true)
          }
          // Refresh the gallery of local files
          self?.reloadLocalVideos()
      }
  } // fileOutput didFinishRecordingTo
  
  //MARK: -
//  func thumbnail(for url: URL, targetPixels: CGSize, completion: @escaping (UIImage?) -> Void) {
//      if let cached = thumbCache.object(forKey: url as NSURL) {
//          completion(cached)
//          return
//      }
//      thumbQueue.async {
//          let asset = AVURLAsset(url: url)
//          let gen = AVAssetImageGenerator(asset: asset)
//          gen.appliesPreferredTrackTransform = true
//          gen.maximumSize = targetPixels   // keeps it efficient
//          let time = CMTime(seconds: 0.1, preferredTimescale: 600)
//          let image = (try? gen.copyCGImage(at: time, actualTime: nil)).map { UIImage(cgImage: $0) }
//          if let image { self.thumbCache.setObject(image, forKey: url as NSURL) }
//          DispatchQueue.main.async { completion(image) }
//      }
//  }
  private func thumbnail(for url: URL, targetPixels: CGSize, completion: @escaping (UIImage?) -> Void) {
      if let cached = thumbCache.object(forKey: url as NSURL) {
          completion(cached)
          return
      }

      let time = CMTime(seconds: 0.1, preferredTimescale: 600)

      thumbQueue.async {
          let asset = AVURLAsset(url: url)
          let gen = AVAssetImageGenerator(asset: asset)
          gen.appliesPreferredTrackTransform = true
          gen.maximumSize = targetPixels  // pass pixel size (e.g., 100pt * screenScale)

              let times = [NSValue(time: time)]
              gen.generateCGImagesAsynchronously(forTimes: times) { _, cgImage, _, result, _ in
                  var image: UIImage?
                  if result == .succeeded, let cgImage {
                      image = UIImage(cgImage: cgImage)
                      if let image { self.thumbCache.setObject(image, forKey: url as NSURL) }
                  }
                  DispatchQueue.main.async { completion(image) }
              }
          }
  }

  
} // extension


//MARK: - UICollectionViewDelegate
extension CameraViewController: UICollectionViewDataSource, UICollectionViewDelegate {
  
  func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
      localVideos.count
  }

  func collectionView(_ collectionView: UICollectionView,
                      cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
      guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "VideoGridCell", for: indexPath) as? VideoGridCell else {
          return UICollectionViewCell()
      }

      let item = localVideos[indexPath.item]
      let id = item.url.absoluteString
    let durationText = formatTime(item.duration ?? 0)
      cell.configure(image: nil, durationText: durationText, assetIdentifier: id)

      // Build a pixel target size based on your gridItemSize (set in viewDidLayoutSubviews)
    let target = gridItemSize == .zero ? CGSize(width: imageCellSize.width,
                                                height: imageCellSize.height) : gridItemSize
      thumbnail(for: item.url, targetPixels: target) { [weak cell] img in
          guard let cell, cell.representedAssetIdentifier == id else { return }
          cell.configure(image: img, durationText: durationText, assetIdentifier: id)
      }
      return cell
  }


  func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
      let url = localVideos[indexPath.item].url
      let playerVC = AVPlayerViewController()
      playerVC.player = AVPlayer(url: url)
      present(playerVC, animated: true) { playerVC.player?.play() }
  }
  
  
  //MARK: -
  private func formatTime(_ duration: TimeInterval) -> String {
      let d = Int(duration.rounded())
      let h = d / 3600
      let m = (d % 3600) / 60
      let s = d % 60
      if h > 0 {
          return String(format: "%d:%02d:%02d", h, m, s)
      } else {
          return String(format: "%d:%02d", m, s)
      }
  } // formatTime
  
  @MainActor
  func reloadLocalVideos() {
    // 1) Build list synchronously (main thread)
    let urls = VideoStore.listVideos()
    self.localVideos = urls.map { LocalVideo(url: $0, duration: nil) }
    self.savedVideosCollection.reloadData()
    
    // 2) Load durations asynchronously
    //    (Task inherits MainActor but `await` calls will suspend it)
    let snapshot = urls
    Task { [weak self] in
      guard let self else { return }
      for (_ , url) in snapshot.enumerated() {
        let asset = AVURLAsset(url: url)
        do {
          let duration = try await asset.load(.duration)
          let seconds = CMTimeGetSeconds(duration)
          
          // 3) Update UI on the main actor
          await MainActor.run {
            if let j = self.localVideos.firstIndex(where: { $0.url == url }) {
              self.localVideos[j].duration = seconds
              self.savedVideosCollection.reloadItems(at: [IndexPath(item: j, section: 0)])
            }
          }
        } catch {
          // Optional: handle per-file error
          print("Could not load duration for \(url.lastPathComponent): \(error)")
        }
      }
    }
  }
  
  @objc private func handleLongPress(_ gr: UILongPressGestureRecognizer) {
      guard gr.state == .began else { return }
      let point = gr.location(in: savedVideosCollection)
      guard let indexPath = savedVideosCollection.indexPathForItem(at: point) else { return }

      let item = localVideos[indexPath.item]
      let cell = savedVideosCollection.cellForItem(at: indexPath)

      let alert = UIAlertController(
          title: "Delete this video?",
          message: item.url.lastPathComponent,
          preferredStyle: .actionSheet
      )
      alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
          self?.deleteVideo(at: indexPath)
      })
      alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

      // iPad safety
      if let pop = alert.popoverPresentationController {
          pop.sourceView = cell ?? savedVideosCollection
          pop.sourceRect = cell?.bounds ?? CGRect(origin: point, size: .zero)
      }

      // Nice haptic on trigger
      UIImpactFeedbackGenerator(style: .medium).impactOccurred()
      present(alert, animated: true)
  }
  
  private func deleteVideo(at indexPath: IndexPath) {
    let url = localVideos[indexPath.item].url
    do {
      try VideoStore.delete(url)                   // remove from Documents/CapturedVideos
      thumbCache.removeObject(forKey: url as NSURL)
      
      localVideos.remove(at: indexPath.item)
      savedVideosCollection.performBatchUpdates({
        savedVideosCollection.deleteItems(at: [indexPath])
      })
      
    } catch {
      let alert = UIAlertController(title: "Couldn't Delete",
                                    message: error.localizedDescription,
                                    preferredStyle: .alert)
      alert.addAction(UIAlertAction(title: "OK", style: .default))
      present(alert, animated: true)
    }
  }

} // UICollectionViewDataSource/Delegate

