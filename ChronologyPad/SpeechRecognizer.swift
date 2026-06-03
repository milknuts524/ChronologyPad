import Foundation
import Combine
import Speech
import AVFoundation

final class SpeechRecognizer: ObservableObject {

    @Published var transcribedText = ""
    @Published var isRecording = false

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { _ in }
        if #available(iOS 17.0, *) {
            
            AVAudioApplication.requestRecordPermission { granted in
                
                DispatchQueue.main.async {
                    print("Microphone permission:", granted)
                }
            }
            
        } else {
            
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                
                DispatchQueue.main.async {
                    print("Microphone permission:", granted)
                }
            }
        }
    }

    
    func startRecording() throws {

            guard recognizer?.isAvailable == true else {
                print("Speech recognizer is not available")
                return
            }

            transcribedText = ""
            isRecording = true

            recognitionTask?.cancel()
            recognitionTask = nil

            let audioSession = AVAudioSession.sharedInstance()

            try audioSession.setCategory(
                .record,
                mode: .measurement,
                options: [.duckOthers]
            )

            try audioSession.setActive(
                true,
                options: .notifyOthersOnDeactivation
            )

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            guard recordingFormat.sampleRate > 0 else {
                print("Invalid microphone format")
                stopRecording()
                return
            }

            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

            guard let recognitionRequest else {
                stopRecording()
                return
            }

            recognitionRequest.shouldReportPartialResults = true

            inputNode.removeTap(onBus: 0)

            inputNode.installTap(
                onBus: 0,
                bufferSize: 1024,
                format: recordingFormat
            ) { buffer, _ in

                recognitionRequest.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            recognitionTask = recognizer?.recognitionTask(
                with: recognitionRequest
            ) { result, error in

                if let result {
                    DispatchQueue.main.async {
                        self.transcribedText = result.bestTranscription.formattedString
                    }
                }

                if error != nil {
                    self.stopRecording()
                }
            }
        }

    func stopRecording() {
        isRecording = false

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        try? AVAudioSession.sharedInstance().setActive(false)
    }
}
