//
//  SoundPlayer.swift
//  videoCapture
//
//  Created by Aviram Netanel on 15/08/2025.
//

import AVFAudio

final class SoundPlayer {
  
  static var shared = SoundPlayer()
  
  private var audioPlayer : AVAudioPlayer?
  private let audioQueue = DispatchQueue(label: "audioQueue")
  
  private init(){
    do{
      //allow AVAudioSession playback also in silent mode:
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
    }
    catch{
      print("couldn't set sound session!")
    }
  }
  
  //MARK: -
  func playSound(sound: SoundsEnum, ext: String? = nil){
    audioQueue.async {
      guard let soundFileURL = Bundle.main.url(
        forResource: sound.rawValue,
        withExtension: ext != nil ? ext : "mp3"
      ) else {
        print("sound file missing: \(sound.rawValue)!")
        return
      }
      do{
        self.audioPlayer = try AVAudioPlayer(contentsOf: soundFileURL)
        self.audioPlayer?.play()
      }catch{
        print("couldn't play sound!")
      }
    }
  }
}

//MARK: - Sounds
enum SoundsEnum : String{
  case click = "click"
  case shrink = "shrink"
  case delete = "delete"
}
