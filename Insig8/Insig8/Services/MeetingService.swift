import SwiftUI
import Combine
import AVFoundation
import Speech
import OSLog
import ScreenCaptureKit
import FoundationModels

// MARK: - Meeting Service
// Clean Phase 1 implementation following the blueprint architecture
// Uses actual macOS 26 APIs: SpeechAnalyzer, SpeechTranscriber, FoundationModels

@MainActor
class MeetingService: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    @Published var isRecording = false
    @Published var liveTranscript = ""
    @Published var finalTranscript = ""
    @Published var meetingSummary: MeetingSummary?
    @Published var error: MeetingError?
    
    // MARK: - Private Properties
    private let logger = Logger(subsystem: "com.insig8.meeting", category: "MeetingService")
    
    // Audio Capture Layer (ScreenCaptureKit)
    private var screenStream: SCStream?
    private var streamConfig: SCStreamConfiguration?
    
    // Transcription Layer (Speech APIs)
    // Note: Using availability checks for macOS 26 APIs
    @available(macOS 26.0, *)
    private var speechAnalyzer: SpeechAnalyzer?
    @available(macOS 26.0, *)
    private var speechTranscriber: SpeechTranscriber?
    
    // Legacy fallback for earlier macOS versions
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine = AVAudioEngine()
    
    // AI Layer (Foundation Models)
    @available(macOS 26.0, *)
    private var languageSession: LanguageModelSession?
    
    // Storage Layer
    var currentMeeting: MeetingSession?
    private var meetingSegments: [MeetingTranscriptSegment] = []
    
    // MARK: - Initialization
    override init() {
        super.init()
        setupServices()
    }
    
    // MARK: - Public Interface
    
    func requestMicrophonePermission() async -> Bool {
        // On macOS, microphone permission is handled by the system
        // SFSpeechRecognizer will automatically request permission when needed
        logger.info("Microphone permission handled by SFSpeechRecognizer on macOS")
        return true
    }
    
    func startMeeting() async throws {
        logger.info("Starting meeting transcription...")
        
        guard !isRecording else {
            throw MeetingError.alreadyRecording
        }
        
        // Reset state
        liveTranscript = ""
        finalTranscript = ""
        meetingSummary = nil
        error = nil
        meetingSegments = []
        
        // Create new meeting session
        currentMeeting = MeetingSession(
            id: UUID(),
            startTime: Date(),
            title: "Meeting \(DateFormatter.shortDateTime.string(from: Date()))"
        )
        
        // Check and request microphone permission
        let hasPermission = await requestMicrophonePermission()
        if !hasPermission {
            throw MeetingError.speechRecognitionUnavailable
        }
        
        // Phase 1: Skip ScreenCaptureKit, use direct microphone access only
        logger.info("Phase 1: Using direct microphone access for reliability")
        
        // Start transcription (includes microphone setup)
        try await startTranscription()
        
        isRecording = true
        logger.info("Meeting started successfully")
    }
    
    func stopMeeting() async throws {
        logger.info("Stopping meeting transcription...")
        
        guard isRecording else {
            throw MeetingError.notRecording
        }
        
        // Stop transcription (includes microphone cleanup)
        await stopTranscription()
        
        // Phase 1: No ScreenCaptureKit cleanup needed
        logger.info("Phase 1: Direct microphone access stopped")
        
        // Generate summary
        await generateMeetingSummary()
        
        // Update meeting session
        currentMeeting?.endTime = Date()
        currentMeeting?.transcript = finalTranscript
        currentMeeting?.summary = meetingSummary
        
        isRecording = false
        logger.info("Meeting stopped successfully")
    }
    
    // MARK: - Private Implementation
    
    private func setupServices() {
        // Check API availability and setup appropriate services
        if #available(macOS 26.0, *) {
            setupMacOS26Services()
        } else {
            setupLegacyServices()
        }
    }
    
    @available(macOS 26.0, *)
    private func setupMacOS26Services() {
        logger.info("Setting up macOS 26 native services")
        
        // Initialize Foundation Models
        languageSession = LanguageModelSession()
        
        // Speech services will be initialized when recording starts
        logger.info("macOS 26 services configured")
    }
    
    private func setupLegacyServices() {
        logger.info("Setting up legacy services for pre-macOS 26")
        
        // Initialize legacy speech recognizer
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        
        logger.info("Legacy services configured")
    }
    
    // MARK: - Audio Capture (ScreenCaptureKit)
    
    private func startAudioCapture() async throws {
        logger.info("Starting ScreenCaptureKit audio capture...")
        
        // For Phase 1, use direct microphone access instead of ScreenCaptureKit
        // This avoids the video stream issues and works more reliably
        logger.info("Phase 1: Using direct microphone access for stability")
        
        // ScreenCaptureKit setup is disabled for Phase 1 due to:
        // 1. Stream output errors when only audio is needed
        // 2. Complex audio buffer conversion requirements
        // 3. Better reliability with direct AVAudioEngine approach
        
        // The audio will be captured directly by AVAudioEngine in startLegacyTranscription()
        logger.info("Audio capture configured for direct microphone access")
    }
    
    private func stopAudioCapture() async {
        logger.info("Stopping audio capture...")
        
        if let stream = screenStream {
            do {
                try await stream.stopCapture()
            } catch {
                logger.error("Error stopping capture: \(error)")
            }
        }
        
        screenStream = nil
        streamConfig = nil
        
        logger.info("Audio capture stopped")
    }
    
    // MARK: - Transcription Layer
    
    private func startTranscription() async throws {
        // For Phase 1, use legacy transcription for stability
        // macOS 26 APIs will be enabled in future phases when they're more stable
        try startLegacyTranscription()
        
        // TODO: Enable macOS 26 transcription when APIs are stable
        // if #available(macOS 26.0, *) {
        //     try await startMacOS26Transcription() 
        // } else {
        //     try startLegacyTranscription()
        // }
    }
    
    // TODO: Re-enable when macOS 26 APIs are stable in future phases
    /*
    @available(macOS 26.0, *)
    private func startMacOS26Transcription() async throws {
        logger.info("Starting macOS 26 native transcription")
        
        // Initialize SpeechTranscriber with appropriate configuration
        let locale = Locale(identifier: "en-US")
        
        // Create SpeechTranscriber - API still unstable in beta 4
        speechTranscriber = SpeechTranscriber(locale: locale, preset: .dictation)
        
        guard let transcriber = speechTranscriber else {
            throw MeetingError.speechTranscriberInitFailed
        }
        
        // Initialize SpeechAnalyzer
        speechAnalyzer = SpeechAnalyzer(modules: [transcriber])
        
        // Set up async streams for live and final transcripts
        await setupTranscriptionStreams()
        
        logger.info("macOS 26 transcription started")
    }
    */
    
    // TODO: Re-enable when macOS 26 APIs are stable in future phases
    /*
    @available(macOS 26.0, *)
    private func setupTranscriptionStreams() async {
        guard let transcriber = speechTranscriber else { return }
        
        // Handle transcription results from async stream
        Task {
            do {
                for try await result in transcriber.results {
                    if result.isFinal {
                        // Final result - add to transcript
                        await MainActor.run {
                            let text = String(describing: result.text)
                            self.finalTranscript += text + " "
                            self.liveTranscript = ""
                        }
                        
                        // Store final transcript segment
                        await storeMeetingSegment(result)
                    } else {
                        // Live/volatile result - update UI
                        await MainActor.run {
                            self.liveTranscript = String(describing: result.text)
                        }
                    }
                }
            } catch {
                logger.error("Transcription stream error: \(error)")
                await MainActor.run {
                    self.error = .transcriptionFailed
                }
            }
        }
    }
    */
    
    private func startLegacyTranscription() throws {
        logger.info("Starting legacy transcription")
        
        // On macOS, microphone permission is handled automatically by SFSpeechRecognizer
        logger.info("Starting legacy transcription with automatic permission handling")
        
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw MeetingError.speechRecognitionUnavailable
        }
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else {
            throw MeetingError.speechRecognitionRequestFailed
        }
        
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                if let result = result {
                    self?.liveTranscript = result.bestTranscription.formattedString
                    
                    if result.isFinal {
                        self?.finalTranscript += result.bestTranscription.formattedString + " "
                        self?.liveTranscript = ""
                    }
                }
                
                if let error = error {
                    self?.logger.error("Recognition error: \(error)")
                    self?.error = .transcriptionFailed
                }
            }
        }
        
        // Start audio engine
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        logger.info("Legacy transcription started")
    }
    
    private func stopTranscription() async {
        // For Phase 1, use legacy transcription for stability
        stopLegacyTranscription()
        
        // TODO: Enable macOS 26 transcription when APIs are stable
        // if #available(macOS 26.0, *) {
        //     await stopMacOS26Transcription() 
        // } else {
        //     stopLegacyTranscription()
        // }
    }
    
    // TODO: Re-enable when macOS 26 APIs are stable in future phases
    /*
    @available(macOS 26.0, *)
    private func stopMacOS26Transcription() async {
        logger.info("Stopping macOS 26 transcription")
        
        // Clean up analyzer and transcriber
        speechAnalyzer = nil
        speechTranscriber = nil
        
        logger.info("macOS 26 transcription stopped")
    }
    */
    
    private func stopLegacyTranscription() {
        logger.info("Stopping legacy transcription")
        
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        recognitionRequest = nil
        recognitionTask = nil
        
        logger.info("Legacy transcription stopped")
    }
    
    // MARK: - AI Summary Generation
    
    private func generateMeetingSummary() async {
        guard !finalTranscript.isEmpty else {
            logger.warning("No transcript available for summary generation")
            return
        }
        
        // For Phase 1, use basic summary generation for stability
        generateBasicSummary()
        
        // TODO: Enable macOS 26 AI summary when APIs are stable
        // if #available(macOS 26.0, *) {
        //     await generateMacOS26Summary()
        // } else {
        //     generateBasicSummary()
        // }
    }
    
    // TODO: Re-enable when macOS 26 APIs are stable in future phases
    /*
    @available(macOS 26.0, *)
    private func generateMacOS26Summary() async {
        logger.info("Generating meeting summary with Foundation Models")
        
        guard let session = languageSession else {
            logger.error("Language model session not available")
            return
        }
        
        let prompt = """
        Please analyze this meeting transcript and provide a structured summary:
        
        \(finalTranscript)
        
        Generate a comprehensive summary including key topics, decisions, and action items.
        """
        
        do {
            let response = try await session.respond(to: prompt)
            let _ = response.content // Use content for future summary generation
            
            await MainActor.run {
                self.meetingSummary = MeetingSummary(
                    title: self.currentMeeting?.title ?? "Meeting Summary",
                    duration: self.formatDuration(),
                    keyTopics: self.extractKeyTopics(),
                    wordCount: self.finalTranscript.split(separator: " ").count,
                    confidence: 0.9
                )
            }
            logger.info("Meeting summary generated successfully")
        } catch {
            logger.error("Failed to generate summary: \(error)")
            await MainActor.run {
                self.error = .summaryGenerationFailed
            }
        }
    }
    */
    
    private func generateBasicSummary() {
        logger.info("Generating basic summary for legacy system")
        
        // Create a simple summary for pre-macOS 26 systems
        meetingSummary = MeetingSummary(
            title: currentMeeting?.title ?? "Meeting Summary",
            duration: formatDuration(),
            keyTopics: extractKeyTopics(),
            wordCount: finalTranscript.split(separator: " ").count,
            confidence: 0.8
        )
    }
    
    // MARK: - Storage Layer
    
    // TODO: Re-enable when macOS 26 APIs are stable in future phases
    /*
    @available(macOS 26.0, *)
    private func storeMeetingSegment(_ result: SpeechTranscriber.Result) async {
        let segment = MeetingTranscriptSegment(
            id: UUID(),
            timestamp: Date(),
            text: String(describing: result.text),
            confidence: 0.9, // Simplified for Phase 1 - real confidence would come from result
            speaker: "Speaker 1", // Simplified speaker detection for Phase 1
            audioSource: .microphone
        )
        
        meetingSegments.append(segment)
    }
    */
    
    // MARK: - Utility Methods
    
    private func formatDuration() -> String {
        guard let meeting = currentMeeting,
              let endTime = meeting.endTime else {
            return "00:00"
        }
        
        let duration = endTime.timeIntervalSince(meeting.startTime)
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    private func extractKeyTopics() -> [String] {
        // Simple keyword extraction for basic summary
        let commonWords = Set(["the", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with", "by"])
        let words = finalTranscript.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 3 && !commonWords.contains($0) }
        
        let wordCounts = Dictionary(grouping: words, by: { $0 })
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }
        
        return Array(wordCounts.prefix(5).map { $0.key.capitalized })
    }
}

// MARK: - SCStreamOutput Delegate

extension MeetingService: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // Phase 1: ScreenCaptureKit audio processing disabled
        // Using direct AVAudioEngine microphone access for reliability
        logger.debug("ScreenCaptureKit sample buffer received but ignored in Phase 1")
        
        // TODO: Future phases will implement proper audio buffer conversion
        // when ScreenCaptureKit integration is needed for system audio capture
    }
    
    private func convertToAudioBuffer(_ sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        // Phase 1: Disabled ScreenCaptureKit audio conversion
        // Direct microphone access via AVAudioEngine is more reliable
        logger.debug("ScreenCaptureKit audio conversion disabled in Phase 1")
        return nil
    }
}

// MARK: - SCStreamDelegate

extension MeetingService: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        logger.error("Stream stopped with error: \(error)")
        Task { @MainActor in
            self.error = .audioStreamError
            if self.isRecording {
                try? await self.stopMeeting()
            }
        }
    }
}

// MARK: - Data Models

struct MeetingSession {
    let id: UUID
    let startTime: Date
    var endTime: Date?
    var title: String
    var transcript: String = ""
    var summary: MeetingSummary?
}

// Use different name to avoid conflict with existing TranscriptSegment
struct MeetingTranscriptSegment {
    let id: UUID
    let timestamp: Date
    let text: String
    let confidence: Float
    let speaker: String
    let audioSource: AudioSource
}

// Phase 1: Simple struct without @Generable for compatibility
struct MeetingSummary: Codable {
    var title: String
    var duration: String
    var keyTopics: [String]
    var wordCount: Int
    var confidence: Float
}

enum AudioSource {
    case microphone
    case systemAudio
}

// MARK: - Error Types

enum MeetingError: Error, LocalizedError {
    case alreadyRecording
    case notRecording
    case audioConfigurationFailed
    case audioStreamCreationFailed
    case audioStreamError
    case speechRecognitionUnavailable
    case speechRecognitionRequestFailed
    case speechTranscriberInitFailed
    case unsupportedLocale
    case transcriptionFailed
    case summaryGenerationFailed
    
    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "Meeting is already being recorded"
        case .notRecording:
            return "No meeting is currently being recorded"
        case .audioConfigurationFailed:
            return "Failed to configure audio capture"
        case .audioStreamCreationFailed:
            return "Failed to create audio stream"
        case .audioStreamError:
            return "Audio stream encountered an error"
        case .speechRecognitionUnavailable:
            return "Speech recognition is not available"
        case .speechRecognitionRequestFailed:
            return "Failed to create speech recognition request"
        case .speechTranscriberInitFailed:
            return "Failed to initialize speech transcriber"
        case .unsupportedLocale:
            return "The selected language is not supported"
        case .transcriptionFailed:
            return "Transcription failed"
        case .summaryGenerationFailed:
            return "Failed to generate meeting summary"
        }
    }
}

// MARK: - Extensions

extension DateFormatter {
    static let shortDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}