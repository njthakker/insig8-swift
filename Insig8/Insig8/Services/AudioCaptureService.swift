//
//  AudioCaptureService.swift
//  Insig8
//
//  Audio capture and transcription service for meeting intelligence
//

import Foundation
import AVFoundation
import AVKit
import Speech
import Combine
import os.log

@MainActor
class AudioCaptureService: NSObject, ObservableObject {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Insig8", category: "AudioCapture")
    
    // Audio capture state
    @Published var isRecording = false
    @Published var isTranscribing = false
    @Published var currentTranscript = ""
    @Published var meetingTitle = ""
    @Published var participants: [String] = []
    @Published var recordingDuration: TimeInterval = 0
    
    // Permissions
    @Published var microphonePermissionGranted = false
    @Published var speechRecognitionPermissionGranted = false
    
    // Audio components
    private var audioEngine = AVAudioEngine()
    private var speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    // Recording state
    private var recordingStartTime: Date?
    private var recordingTimer: Timer?
    private var transcriptBuffer: [TranscriptSegment] = []
    
    // Meeting detection
    private var meetingApps: Set<String> = ["Zoom", "Microsoft Teams", "Google Meet", "Skype", "Discord", "FaceTime"]
    private var activeMeetingApp: String?
    
    override init() {
        super.init()
        logger.info("Initializing AudioCaptureService")
        checkPermissions()
        setupSpeechRecognizer()
    }
    
    // MARK: - Permission Management
    
    private func checkPermissions() {
        // Check microphone permission on macOS
        Task {
            let status = AVCaptureDevice.authorizationStatus(for: .audio)
            
            if status == .notDetermined {
                let granted = await AVCaptureDevice.requestAccess(for: .audio)
                await MainActor.run {
                    self.microphonePermissionGranted = granted
                    if granted {
                        self.logger.info("Microphone permission granted")
                    } else {
                        self.logger.warning("Microphone permission denied")
                    }
                }
            } else {
                await MainActor.run {
                    self.microphonePermissionGranted = (status == .authorized)
                    if status == .authorized {
                        self.logger.info("Microphone permission already granted")
                    } else {
                        self.logger.warning("Microphone permission denied")
                    }
                }
            }
        }
        
        // Check speech recognition permission
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.speechRecognitionPermissionGranted = (status == .authorized)
                if status == .authorized {
                    self?.logger.info("Speech recognition permission granted")
                } else {
                    self?.logger.warning("Speech recognition permission denied: \(status.rawValue)")
                }
            }
        }
    }
    
    private func setupSpeechRecognizer() {
        guard let recognizer = speechRecognizer else {
            logger.error("Speech recognizer not available for current locale")
            return
        }
        
        recognizer.delegate = self
    }
    
    // MARK: - Recording Control
    
    func startRecording(meetingTitle: String? = nil, detectedApp: String? = nil) async throws {
        guard microphonePermissionGranted && speechRecognitionPermissionGranted else {
            throw AudioCaptureError.permissionsNotGranted
        }
        
        guard !isRecording else {
            logger.warning("Already recording")
            return
        }
        
        logger.info("Starting audio recording")
        
        // Set up meeting context
        self.meetingTitle = meetingTitle ?? "Meeting Recording"
        self.activeMeetingApp = detectedApp
        self.participants = []
        self.transcriptBuffer = []
        self.currentTranscript = ""
        
        // Configure audio session
        try configureAudioSession()
        
        // Start audio engine
        try startAudioEngine()
        
        // Start speech recognition
        try startSpeechRecognition()
        
        // Update state
        recordingStartTime = Date()
        isRecording = true
        isTranscribing = true
        
        // Start recording timer
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                self.updateRecordingDuration()
            }
        }
        
        logger.info("Audio recording started successfully")
    }
    
    func stopRecording() async {
        logger.info("Stopping audio recording")
        
        // Stop timers
        recordingTimer?.invalidate()
        recordingTimer = nil
        
        // Stop speech recognition
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        // Stop audio engine
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        
        // Update state
        isRecording = false
        isTranscribing = false
        
        // Process final transcript
        await processFinalTranscript()
        
        logger.info("Audio recording stopped")
    }
    
    func pauseRecording() {
        guard isRecording else { return }
        
        audioEngine.pause()
        recognitionTask?.cancel()
        
        logger.info("Audio recording paused")
    }
    
    func resumeRecording() async throws {
        guard !audioEngine.isRunning else { return }
        
        try audioEngine.start()
        try startSpeechRecognition()
        
        logger.info("Audio recording resumed")
    }
    
    // MARK: - Audio Configuration
    
    private func configureAudioSession() throws {
        // On macOS, we don't need to configure AVAudioSession like on iOS
        // AVAudioEngine handles the audio session configuration automatically
        logger.info("Audio session configured for macOS")
    }
    
    private func startAudioEngine() throws {
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // Install tap on input node
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
    }
    
    private func startSpeechRecognition() throws {
        // Cancel previous task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw AudioCaptureError.speechRecognitionSetupFailed
        }
        
        recognitionRequest.shouldReportPartialResults = true
        
        // Start recognition task
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            self?.handleSpeechRecognitionResult(result: result, error: error)
        }
    }
    
    // MARK: - Speech Recognition Handling
    
    private func handleSpeechRecognitionResult(result: SFSpeechRecognitionResult?, error: Error?) {
        if let error = error {
            logger.error("Speech recognition error: \(error)")
            return
        }
        
        guard let result = result else { return }
        
        let transcribedText = result.bestTranscription.formattedString
        
        Task { @MainActor in
            // Update current transcript
            currentTranscript = transcribedText
            
            // If result is final, add to buffer
            if result.isFinal {
                let segment = TranscriptSegment(
                    id: UUID(),
                    text: transcribedText,
                    timestamp: Date(),
                    confidence: 0.8, // Simplified confidence score since averageConfidence isn't available
                    speakerDetected: detectSpeaker(in: transcribedText)
                )
                
                transcriptBuffer.append(segment)
                
                // Detect participants from transcript
                detectParticipants(in: transcribedText)
                
                // Process for action items and key information
                processTranscriptSegment(segment)
                
                // Clear current transcript for next segment
                currentTranscript = ""
            }
        }
    }
    
    // MARK: - Meeting Intelligence
    
    private func detectSpeaker(in text: String) -> String? {
        // Simple speaker detection based on patterns
        // In production, would use voice recognition or meeting app APIs
        
        let speakerPatterns = [
            "my name is", "I'm", "this is", "speaking"
        ]
        
        for pattern in speakerPatterns {
            if let range = text.lowercased().range(of: pattern) {
                let remainder = String(text[range.upperBound...])
                let words = remainder.components(separatedBy: .whitespaces)
                if let name = words.first(where: { !$0.isEmpty && $0.count > 2 }) {
                    return name.trimmingCharacters(in: .punctuationCharacters)
                }
            }
        }
        
        return nil
    }
    
    private func detectParticipants(in text: String) {
        // Look for name patterns and add to participants
        if let speaker = detectSpeaker(in: text) {
            if !participants.contains(speaker) {
                participants.append(speaker)
                logger.info("Detected new participant: \(speaker)")
            }
        }
        
        // Also look for mentions of other people
        let mentionPatterns = ["@", "hey ", "hi ", "thanks "]
        for pattern in mentionPatterns {
            if let range = text.lowercased().range(of: pattern) {
                let remainder = String(text[range.upperBound...])
                let words = remainder.components(separatedBy: .whitespaces)
                if let name = words.first(where: { !$0.isEmpty && $0.count > 2 }) {
                    let cleanName = name.trimmingCharacters(in: .punctuationCharacters)
                    if !participants.contains(cleanName) {
                        participants.append(cleanName)
                    }
                }
            }
        }
    }
    
    private func processTranscriptSegment(_ segment: TranscriptSegment) {
        // Extract action items
        let actionItems = extractActionItems(from: segment.text)
        
        // Extract commitments
        let commitments = extractCommitments(from: segment.text)
        
        // Extract decisions
        let decisions = extractDecisions(from: segment.text)
        
        // Store for later processing
        let processedSegment = ProcessedTranscriptSegment(
            original: segment,
            actionItems: actionItems,
            commitments: commitments,
            decisions: decisions
        )
        
        // Send to ActionManager for processing
        Task {
            await sendToActionManager(processedSegment)
        }
    }
    
    private func extractActionItems(from text: String) -> [String] {
        let actionPatterns = [
            "action item:", "TODO:", "follow up on", "need to",
            "will do", "responsible for", "assigned to",
            "next steps", "homework", "deliverable"
        ]
        
        var actionItems: [String] = []
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
        
        for sentence in sentences {
            let lower = sentence.lowercased()
            
            for pattern in actionPatterns {
                if lower.contains(pattern) {
                    let cleanSentence = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleanSentence.isEmpty {
                        actionItems.append(cleanSentence)
                        break
                    }
                }
            }
        }
        
        return actionItems
    }
    
    private func extractCommitments(from text: String) -> [String] {
        let commitmentPatterns = [
            "I'll", "I will", "I can", "I should",
            "I'll get back", "I'll follow up", "I'll check",
            "I'll send", "I'll review", "I'll investigate"
        ]
        
        var commitments: [String] = []
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
        
        for sentence in sentences {
            let lower = sentence.lowercased()
            
            for pattern in commitmentPatterns {
                if lower.contains(pattern) {
                    let cleanSentence = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleanSentence.isEmpty {
                        commitments.append(cleanSentence)
                        break
                    }
                }
            }
        }
        
        return commitments
    }
    
    private func extractDecisions(from text: String) -> [String] {
        let decisionPatterns = [
            "we decided", "decision:", "agreed to", "consensus",
            "we'll go with", "final decision", "resolved",
            "concluded", "outcome"
        ]
        
        var decisions: [String] = []
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
        
        for sentence in sentences {
            let lower = sentence.lowercased()
            
            for pattern in decisionPatterns {
                if lower.contains(pattern) {
                    let cleanSentence = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleanSentence.isEmpty {
                        decisions.append(cleanSentence)
                        break
                    }
                }
            }
        }
        
        return decisions
    }
    
    // MARK: - Integration
    
    private func sendToActionManager(_ segment: ProcessedTranscriptSegment) async {
        // Get ActionManager instance from AppStore
        // This would be properly injected in production
        
        for actionItem in segment.actionItems {
            logger.info("Creating action from meeting: \(actionItem)")
            // ActionManager would create actions from meeting transcript
        }
        
        for commitment in segment.commitments {
            logger.info("Creating commitment from meeting: \(commitment)")
            // ActionManager would track commitments
        }
    }
    
    private func processFinalTranscript() async {
        logger.info("Processing final meeting transcript")
        
        let fullTranscript = transcriptBuffer.map { $0.text }.joined(separator: " ")
        
        // Generate meeting summary
        let summary = generateMeetingSummary(fullTranscript)
        
        // Extract overall action items
        let allActionItems = transcriptBuffer.flatMap { segment in
            extractActionItems(from: segment.text)
        }
        
        // Create meeting record
        let meetingRecord = MeetingRecord(
            id: UUID(),
            title: meetingTitle,
            participants: participants,
            duration: recordingDuration,
            transcript: fullTranscript,
            summary: summary,
            actionItems: allActionItems,
            startTime: recordingStartTime ?? Date(),
            endTime: Date(),
            appSource: activeMeetingApp
        )
        
        // Store meeting record
        await storeMeetingRecord(meetingRecord)
        
        logger.info("Meeting processed: \(allActionItems.count) action items extracted")
    }
    
    private func generateMeetingSummary(_ transcript: String) -> String {
        // Simple summary generation - in production would use AI
        let sentences = transcript.components(separatedBy: CharacterSet(charactersIn: ".!?"))
        let keyPhrases = ["decision", "action", "follow up", "deadline", "responsible"]
        
        let importantSentences = sentences.filter { sentence in
            let lower = sentence.lowercased()
            return keyPhrases.contains { lower.contains($0) }
        }
        
        return importantSentences.prefix(5).joined(separator: ". ")
    }
    
    private func storeMeetingRecord(_ record: MeetingRecord) async {
        // Store in secure storage for later retrieval
        do {
            let data = try JSONEncoder().encode(record)
            let secureStorage = SecureAIStorage()
            // Encrypt the data
            let encryptedData = try secureStorage.encrypt(data)
            
            // Store in UserDefaults (in production, would use proper database)
            UserDefaults.standard.set(encryptedData, forKey: "meeting_\(record.id.uuidString)")
            
            logger.info("Stored meeting record: \(record.title)")
        } catch {
            logger.error("Failed to store meeting record: \(error)")
        }
    }
    
    private func updateRecordingDuration() {
        guard let startTime = recordingStartTime else { return }
        recordingDuration = Date().timeIntervalSince(startTime)
    }
    
    // MARK: - Public API
    
    func getRecentMeetings(limit: Int = 10) async -> [MeetingRecord] {
        // In production, would query from database
        return []
    }
    
    func searchMeetings(query: String) async -> [MeetingRecord] {
        // In production, would perform full-text search on transcripts
        return []
    }
    
    func exportMeetingTranscript(_ meetingId: UUID, format: ExportFormat) async throws -> URL {
        // Export meeting transcript in various formats
        throw AudioCaptureError.notImplemented
    }
}

// MARK: - SFSpeechRecognizerDelegate

extension AudioCaptureService: SFSpeechRecognizerDelegate {
    nonisolated func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        logger.info("Speech recognizer availability changed: \(available)")
    }
}

// MARK: - Supporting Types

struct TranscriptSegment {
    let id: UUID
    let text: String
    let timestamp: Date
    let confidence: Float
    let speakerDetected: String?
}

struct ProcessedTranscriptSegment {
    let original: TranscriptSegment
    let actionItems: [String]
    let commitments: [String]
    let decisions: [String]
}

struct MeetingRecord: Codable, Identifiable {
    let id: UUID
    let title: String
    let participants: [String]
    let duration: TimeInterval
    let transcript: String
    let summary: String
    let actionItems: [String]
    let startTime: Date
    let endTime: Date
    let appSource: String?
}

enum ExportFormat {
    case text
    case markdown
    case pdf
    case json
}

enum AudioCaptureError: LocalizedError {
    case permissionsNotGranted
    case speechRecognitionSetupFailed
    case audioEngineStartFailed
    case notImplemented
    
    var errorDescription: String? {
        switch self {
        case .permissionsNotGranted:
            return "Microphone or speech recognition permission not granted"
        case .speechRecognitionSetupFailed:
            return "Failed to set up speech recognition"
        case .audioEngineStartFailed:
            return "Failed to start audio engine"
        case .notImplemented:
            return "Feature not yet implemented"
        }
    }
}