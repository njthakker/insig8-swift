import SwiftUI
import Observation
import OSLog

@Observable final class MeetingAssistantController {
    private(set) var capture = AudioCaptureService()
    private(set) var transcriber: TranscriptionService?
    private let llm = MeetingLLMService()
    private let logger = Logger(subsystem: "com.insig8", category: "MeetingController")

    var summary: MeetingSummary?
    var isRecording = false
    var isGeneratingSummary = false
    var summaryError: Error?
    
    // Current meeting session data
    var currentMeetingId: UUID?
    var meetingStartTime: Date?
    
    func toggle() {
        if isRecording { 
            stop() 
        } else { 
            Task {
                try? await start()
            }
        }
    }

    func start() async throws {
        logger.info("Starting meeting assistant")
        
        // Reset state
        summary = nil
        summaryError = nil
        isGeneratingSummary = false
        currentMeetingId = UUID()
        meetingStartTime = Date()
        
        try await capture.start()
        let t = try TranscriptionService()
        t.attachAudioStream(capture.sampleBufferStream)
        transcriber = t
        isRecording = true
        
        logger.info("Meeting assistant started successfully")
    }

    func stop() {
        logger.info("Stopping meeting assistant")
        isRecording = false
        capture.stop()
        
        // Generate summary asynchronously with progress tracking
        Task { @MainActor [self] in
            do {
                isGeneratingSummary = true
                summaryError = nil
                
                let text = transcriber?.finalisedSegments.map(\.text).joined(separator: " ") ?? ""
                logger.info("Generating summary from \(text.count) characters of transcript")
                
                let generatedSummary = try await llm.summarize(text)
                
                // Add meeting metadata
                var finalSummary = generatedSummary
                finalSummary.duration = formatMeetingDuration()
                finalSummary.wordCount = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
                
                summary = finalSummary
                
                // Save to persistent storage
                await saveMeetingRecord(summary: finalSummary, transcript: text)
                
                logger.info("Summary generated successfully")
            } catch {
                logger.error("Failed to generate summary: \(error)")
                summaryError = error
            }
            
            isGeneratingSummary = false
        }
    }
    
    private func formatMeetingDuration() -> String {
        guard let startTime = meetingStartTime else { return "00:00" }
        let duration = Date().timeIntervalSince(startTime)
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    private func saveMeetingRecord(summary: MeetingSummary, transcript: String) async {
        guard let meetingId = currentMeetingId,
              let startTime = meetingStartTime else { return }
        
        let meetingRecord = MeetingRecord(
            id: meetingId,
            startTime: startTime,
            endTime: Date(),
            title: summary.title,
            transcript: transcript,
            summary: summary
        )
        
        await MeetingStorageService.shared.saveMeeting(meetingRecord)
    }
}