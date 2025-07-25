import Speech
import Foundation
import OSLog
import AVFoundation
import Observation

@Observable final class TranscriptionService {
    private let logger = Logger(subsystem: "com.insig8", category: "Transcription")
    
    // Use SFSpeechRecognizer for compatibility with current macOS
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine = AVAudioEngine()
    
    // Simple properties for @Observable
    var liveText: AttributedString = AttributedString("")
    var finalisedSegments: [TranscriptSegment] = []

    init(locale: Locale = .current) throws {
        speechRecognizer = SFSpeechRecognizer(locale: locale)
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw TranscriptionError.localeUnsupported
        }
    }

    func attachAudioStream(_ stream: AsyncStream<CMSampleBuffer>) {
        // For now, we'll use a simpler approach with AVAudioEngine
        // In production, this would process the CMSampleBuffer stream
        logger.info("Audio stream attached, using simplified transcription")
        startTranscription()
    }
    
    private func startTranscription() {
        guard let recognizer = speechRecognizer else { return }
        
        do {
            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let request = recognitionRequest else { return }
            
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = true
            
            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    
                    if let result = result {
                        self.liveText = AttributedString(result.bestTranscription.formattedString)
                        
                        if result.isFinal {
                            let segment = TranscriptSegment(
                                id: UUID(),
                                text: result.bestTranscription.formattedString,
                                timestamp: Date(),
                                confidence: 0.8
                            )
                            self.finalisedSegments.append(segment)
                            self.liveText = AttributedString("")
                        }
                    }
                    
                    if let error = error {
                        self.logger.error("Recognition error: \(error)")
                    }
                }
            }
            
            // Set up audio engine
            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                request.append(buffer)
            }
            
            audioEngine.prepare()
            try audioEngine.start()
            
        } catch {
            logger.error("Failed to start transcription: \(error)")
        }
    }
    
    deinit {
        recognitionTask?.cancel()
        recognitionRequest?.endAudio()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
    }
}

struct TranscriptSegment {
    let id: UUID
    let text: String
    let timestamp: Date
    let confidence: Float
}

enum TranscriptionError: Error { 
    case localeUnsupported 
}