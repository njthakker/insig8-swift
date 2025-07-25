import Foundation
import OSLog
import Combine

// MARK: - Meeting Storage Models

struct MeetingRecord: Codable, Identifiable {
    let id: UUID
    let startTime: Date
    let endTime: Date
    let title: String
    let transcript: String
    let summary: MeetingSummary
    
    var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }
    
    var formattedDuration: String {
        let duration = self.duration
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Meeting Storage Service

@MainActor
final class MeetingStorageService: ObservableObject {
    static let shared = MeetingStorageService()
    
    private let logger = Logger(subsystem: "com.insig8", category: "MeetingStorage")
    private let storageURL: URL
    
    @Published var recentMeetings: [MeetingRecord] = []
    
    private init() {
        // Store meetings in Application Support directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, 
                                                  in: .userDomainMask).first!
        let insig8Directory = appSupport.appendingPathComponent("Insig8")
        
        // Create directory if needed
        try? FileManager.default.createDirectory(at: insig8Directory, 
                                                withIntermediateDirectories: true)
        
        storageURL = insig8Directory.appendingPathComponent("meetings.json")
        
        loadMeetings()
    }
    
    func saveMeeting(_ meeting: MeetingRecord) async {
        logger.info("Saving meeting: \(meeting.title)")
        
        // Add to recent meetings (keep latest 50)
        recentMeetings.insert(meeting, at: 0)
        if recentMeetings.count > 50 {
            recentMeetings = Array(recentMeetings.prefix(50))
        }
        
        // Persist to disk
        await persistMeetings()
        
        logger.info("Meeting saved successfully")
    }
    
    func getMeeting(id: UUID) -> MeetingRecord? {
        return recentMeetings.first { $0.id == id }
    }
    
    func deleteMeeting(id: UUID) async {
        recentMeetings.removeAll { $0.id == id }
        await persistMeetings()
    }
    
    private func loadMeetings() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            logger.info("No meetings file found, starting fresh")
            return
        }
        
        do {
            let data = try Data(contentsOf: storageURL)
            recentMeetings = try JSONDecoder().decode([MeetingRecord].self, from: data)
            logger.info("Loaded \(self.recentMeetings.count) meetings from storage")
        } catch {
            logger.error("Failed to load meetings: \(error)")
            recentMeetings = []
        }
    }
    
    private func persistMeetings() async {
        do {
            let data = try JSONEncoder().encode(recentMeetings)
            try data.write(to: storageURL, options: .atomic)
            logger.info("Persisted \(self.recentMeetings.count) meetings to storage")
        } catch {
            logger.error("Failed to persist meetings: \(error)")
        }
    }
}