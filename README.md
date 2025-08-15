# VideoCapture

##Brief Instructions:
1. clone / copy the project
2. change the signning to your profile
3. run

* in case you receive "Untrusted Developer" popup:
Open Settings on the device and navigate to General -> VPN & Device Management, then select your Developer App certificate to trust it.

##What Does The App DO?
1. Camera View: The screen should display a full-screen live camera preview from the device's front camera.
2. Recording Functionality:
  - A single button should start and stop the video recording
  - maximum duration of a video is 30 seconds
  - progress bar to indicate the time left for the video recording
3. Post-Capture:
- When the recording is stopped, the video should be saved to the device
- A thumbnail of the captured video should be displayed on the screen
- Tapping the thumbnail should play the recorded video back to the user.

Advanced Features:
4. Real-Time Frame Analysis & UI Feedback:
- UI Overlay: Display a semi-transparent bounding box in the center of the camera preview
- Real-Time Logic: the app analyzes the video for brightness and motion. if it's too dark or bright, or if it's too blurry from motion - the bounding box would be red. otherwise it'd be green.

Post-Capture Metadata Generation:
5. for every video record - the app produces a report as a json file.

##Architecture: 
- app was built in MVC, mainly due to time consideration.

##Performance:
- real-time frame analysis is performed on background threads
- Analysis: in order to reduce work - it samples every 8th pixel per row/col
- Throttle analysis with analysisFPS (e.g., 15 fps) so heavy work doesn’t run every frame.
- JSON write done on a background task, options: .atomic to avoid partial files

##Scalability:
- no problem: just change the Analyzer, which is currently FrameAnalyzer, to a different Analyzer, which conforms to Analyzer protocol and implements didPass function.

##Things I added: 
- Progress bar - to show the progress during the 30 sec 
- Delete video on long press
- button to export json files
- Sounds & Vibration feedback
- Real-Time Logic: motion detection.

##Things I’d add if I had more time:
- Handle orientation - after spending some time, I decided to disable it.
- code separation - split the code into smaller chuncks / files
- better UX: more sounds, and haptic feedback
- share / export video
