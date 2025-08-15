# VideoCapture

Brief instructions:

1. clone / copy the project
2. change the signning to your profile
3. run

* in case you receive "Untrusted Developer" popup:
Open Settings on the device and navigate to General -> VPN & Device Management, then select your Developer App certificate to trust it.

Architecture: 
- app was built in MVC, mainly due to time consideration.

Performance:
- real-time frame analysis is performed on background threads
- Analysis: in order to reduce work - it samples every 8th pixel per row/col
- Throttle analysis with analysisFPS (e.g., 15 fps) so heavy work doesn’t run every frame.
- JSON write done on a background task, options: .atomic to avoid partial files

Scalability:
- no problem: just change the Analyzer, which is currently FrameAnalyzer, to a different Analyzer, which conforms to Analyzer protocol and implements didPass function.

Things I’d add if I had more time:
- Handle orientation - after spending some time, I decided to disable it.
- code separation - split the code into smaller chuncks / files
- better UX: more sounds, and haptic feedback

Things I added: 
- Progress bar - to show the progress during the 30 sec 
- Delete video on long press
- button to export json files 

