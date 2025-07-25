import AppIntents   // Insig8 already wraps this for its palette
import AppKit

struct ToggleMeetingAssistant: AppIntent {
    static var title: LocalizedStringResource = "Start/Stop Meeting Assistant"
    @MainActor
    func perform() async throws -> some IntentResult {
        // Access the shared meeting controller through AppStore
        AppStore.shared.meetingService.toggle()
        return .result()
    }
}

struct CopyMeetingSummary: AppIntent {
    static var title: LocalizedStringResource = "Copy Latest Meeting Summary"
    @MainActor
    func perform() async throws -> some IntentResult {
        guard let summary = AppStore.shared.meetingService.meetingSummary else {
            throw NSError(domain: "NoSummary", code: 1, userInfo: [NSLocalizedDescriptionKey: "No meeting summary available"])
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary.actionItems.joined(separator: "\n"),
                                       forType: .string)
        return .result()
    }
}

// Extension to add a toggle method to MeetingService for compatibility
extension MeetingService {
    func toggle() {
        Task {
            do {
                if isRecording {
                    try await stopMeeting()
                } else {
                    try await startMeeting()
                }
            } catch {
                // Handle error appropriately
                self.error = .audioConfigurationFailed
            }
        }
    }
}