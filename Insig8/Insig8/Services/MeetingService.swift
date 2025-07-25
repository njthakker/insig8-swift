import SwiftUI
import Combine
import OSLog
import Observation

// MARK: - Meeting Service
// Updated to use new architecture with MeetingAssistantController
// Integrates ScreenCaptureKit, modern Speech APIs, and on-device AI

@MainActor
class MeetingService: ObservableObject {
    
    // MARK: - Published Properties
    @Published var isRecording = false
    @Published var liveTranscript = ""
    @Published var finalTranscript = ""
    @Published var meetingSummary: MeetingSummary?
    @Published var error: MeetingError?
    @Published var isGeneratingSummary = false
    @Published var summaryError: Error?
    
    // MARK: - Private Properties
    private let logger = Logger(subsystem: "com.insig8.meeting", category: "MeetingService")
    private var controller: MeetingAssistantController?
    private let storageService = MeetingStorageService.shared
    
    // Storage Layer
    var currentMeeting: MeetingSession?
    private var transcriptionObserver: Task<Void, Never>?
    private var controllerObserver: Task<Void, Never>?
    
    // MARK: - Initialization
    init() {
        setupServices()
    }
    
    // MARK: - Public Interface
    
    func requestMicrophonePermission() async -> Bool {
        // On macOS, microphone permission is handled by the system
        // SFSpeechRecognizer will automatically request permission when needed
        logger.info("Microphone permission handled by SFSpeechRecognizer on macOS")
        return true
    }
    
    // MARK: - Meeting History Access
    
    var recentMeetings: [MeetingRecord] {
        return storageService.recentMeetings
    }
    
    func getMeeting(id: UUID) -> MeetingRecord? {
        return storageService.getMeeting(id: id)
    }
    
    func deleteMeeting(id: UUID) async {
        await storageService.deleteMeeting(id: id)
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
        isGeneratingSummary = false
        summaryError = nil
        
        // Create new meeting session
        currentMeeting = MeetingSession(
            id: UUID(),
            startTime: Date(),
            title: "Meeting \(DateFormatter.shortDateTime.string(from: Date()))"
        )
        
        // Create and start the controller
        controller = MeetingAssistantController()
        guard let controller = controller else {
            throw MeetingError.audioConfigurationFailed
        }
        
        do {
            try await controller.start()
            startTranscriptionObserver()
            startControllerObserver()
            isRecording = true
            logger.info("Meeting started successfully")
        } catch {
            self.error = .audioConfigurationFailed
            throw error
        }
    }
    
    func stopMeeting() async throws {
        logger.info("Stopping meeting transcription...")
        
        guard isRecording else {
            throw MeetingError.notRecording
        }
        
        // Stop the controller
        controller?.stop()
        transcriptionObserver?.cancel()
        transcriptionObserver = nil
        controllerObserver?.cancel()
        controllerObserver = nil
        
        // Update meeting session
        currentMeeting?.endTime = Date()
        currentMeeting?.transcript = finalTranscript
        currentMeeting?.summary = meetingSummary
        
        isRecording = false
        logger.info("Meeting stopped successfully")
        
        // Keep controller reference until summary is generated
        // It will be cleaned up when summary generation completes
    }
    
    // MARK: - Private Implementation
    
    private func setupServices() {
        logger.info("Setting up meeting services with new architecture")
    }
    
    private func startTranscriptionObserver() {
        guard let controller = controller else { return }
        
        transcriptionObserver = Task { [weak self] in
            guard let self = self else { return }
            
            var lastLiveUpdate = ""
            var lastFinalUpdate = ""
            
            // Observe live transcription updates with throttling
            while !Task.isCancelled {
                if let transcriber = controller.transcriber {
                    let currentLive = String(transcriber.liveText.characters)
                    let segments = transcriber.finalisedSegments
                    let currentFinal = segments.map { $0.text }.joined(separator: " ")
                    
                    // Only update UI if content actually changed
                    if currentLive != lastLiveUpdate || currentFinal != lastFinalUpdate {
                        await MainActor.run {
                            if currentLive != lastLiveUpdate {
                                self.liveTranscript = currentLive
                                lastLiveUpdate = currentLive
                            }
                            
                            if currentFinal != lastFinalUpdate {
                                self.finalTranscript = currentFinal
                                lastFinalUpdate = currentFinal
                            }
                        }
                    }
                }
                
                // Throttle updates to 5 times per second to prevent UI overwhelm
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
            }
        }
    }
    
    private func startControllerObserver() {
        guard let controller = controller else { return }
        
        controllerObserver = Task { [weak self] in
            guard let self = self else { return }
            
            var lastGeneratingSummary = false
            var lastSummaryError: Error?
            var lastSummary: MeetingSummary?
            
            // Observe controller state changes with throttling
            while !Task.isCancelled {
                let currentGenerating = controller.isGeneratingSummary
                let currentError = controller.summaryError
                let currentSummary = controller.summary
                
                // Only update UI if state actually changed
                var shouldUpdate = false
                
                if currentGenerating != lastGeneratingSummary {
                    lastGeneratingSummary = currentGenerating
                    shouldUpdate = true
                }
                
                if currentError?.localizedDescription != lastSummaryError?.localizedDescription {
                    lastSummaryError = currentError
                    shouldUpdate = true
                }
                
                if currentSummary?.title != lastSummary?.title {
                    lastSummary = currentSummary
                    shouldUpdate = true
                }
                
                if shouldUpdate {
                    await MainActor.run {
                        self.isGeneratingSummary = currentGenerating
                        self.summaryError = currentError
                        
                        if let summary = currentSummary {
                            self.meetingSummary = summary
                            
                            // Clean up controller after summary is generated
                            if !currentGenerating {
                                self.controller = nil
                            }
                        }
                    }
                }
                
                // Check every 0.5 seconds for state changes
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }
    
    // MARK: - Permission Management (moved to Public Interface section)
    
    // MARK: - Summary Generation (delegated to MeetingLLMService)
    
    private func generateBasicSummary() {
        logger.info("Summary generation is now handled by MeetingAssistantController")
        
        // Legacy fallback if needed
        if meetingSummary == nil {
            meetingSummary = MeetingSummary(
                title: currentMeeting?.title ?? "Meeting Summary",
                attendees: [],
                keyDecisions: extractKeyTopics(),
                actionItems: []
            )
        }
    }
    
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

// MeetingSummary is now defined in MeetingLLMService.swift

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
    
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()
    
    static let longDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}