import SwiftUI
import UniformTypeIdentifiers

// MARK: - Meeting Widget for Command Palette Integration
// Clean Phase 1 implementation that integrates seamlessly with the command palette

struct MeetingWidgetView: View {
    @EnvironmentObject var appStore: AppStore
    @StateObject private var meetingService = MeetingService()
    @State private var selectedTab = 0
    @State private var showingPermissionsAlert = false
    @State private var showingExportSheet = false
    @State private var autoScroll = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with meeting controls
            MeetingHeaderView(
                meetingService: meetingService,
                showingPermissionsAlert: $showingPermissionsAlert,
                showingExportSheet: $showingExportSheet
            )
            
            Divider()
            
            // Main content based on meeting state
            if meetingService.isRecording || !meetingService.finalTranscript.isEmpty {
                // Show transcript and controls when meeting is active or has content
                MeetingContentView(
                    meetingService: meetingService,
                    selectedTab: $selectedTab,
                    autoScroll: $autoScroll
                )
            } else {
                // Show getting started view when no meeting
                MeetingGettingStartedView(meetingService: meetingService)
            }
        }
        .alert("Permissions Required", isPresented: $showingPermissionsAlert) {
            Button("Open System Preferences") {
                openSystemPreferences()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Meeting transcription requires microphone and screen recording permissions. Please grant these permissions in System Preferences.")
        }
        .sheet(isPresented: $showingExportSheet) {
            MeetingExportView(meetingService: meetingService)
        }
    }
    
    private func openSystemPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Meeting Header

struct MeetingHeaderView: View {
    @ObservedObject var meetingService: MeetingService
    @Binding var showingPermissionsAlert: Bool
    @Binding var showingExportSheet: Bool
    
    var body: some View {
        HStack {
            // Meeting status
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    // Status indicator
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    
                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if meetingService.isRecording {
                        Text(formattedDuration)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                }
                
                Text(meetingTitle)
                    .font(.headline)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Action buttons
            HStack(spacing: 12) {
                // Export/Summary button
                if !meetingService.finalTranscript.isEmpty {
                    Button {
                        if meetingService.isRecording {
                            // Generate live summary
                            generateLiveSummary()
                        } else {
                            // Open export sheet
                            showingExportSheet = true
                        }
                    } label: {
                        Image(systemName: meetingService.isRecording ? "doc.text.magnifyingglass" : "square.and.arrow.up")
                            .font(.title3)
                    }
                    .help(meetingService.isRecording ? "Generate Summary" : "Export Meeting")
                }
                
                // Record/Stop button
                Button {
                    Task {
                        await toggleRecording()
                    }
                } label: {
                    Image(systemName: recordingButtonIcon)
                        .font(.title2)
                        .foregroundColor(recordingButtonColor)
                }
                .help(recordingButtonHelp)
                .keyboardShortcut(.space, modifiers: .command)
            }
        }
        .padding()
    }
    
    // MARK: - Computed Properties
    
    private var statusColor: Color {
        if meetingService.error != nil {
            return .red
        } else if meetingService.isRecording {
            return .red
        } else {
            return .gray
        }
    }
    
    private var statusText: String {
        if let error = meetingService.error {
            return "Error: \(error.localizedDescription)"
        } else if meetingService.isRecording {
            return "Recording"
        } else {
            return "Ready"
        }
    }
    
    private var meetingTitle: String {
        if let meeting = meetingService.currentMeeting {
            return meeting.title
        } else if meetingService.isRecording {
            return "Recording Meeting..."
        } else {
            return "Meeting Transcription"
        }
    }
    
    private var formattedDuration: String {
        guard let meeting = meetingService.currentMeeting else { return "0:00" }
        let duration = Date().timeIntervalSince(meeting.startTime)
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private var recordingButtonIcon: String {
        meetingService.isRecording ? "stop.circle.fill" : "record.circle"
    }
    
    private var recordingButtonColor: Color {
        meetingService.isRecording ? .red : .accentColor
    }
    
    private var recordingButtonHelp: String {
        meetingService.isRecording ? "Stop Recording (⌘Space)" : "Start Recording (⌘Space)"
    }
    
    // MARK: - Actions
    
    private func toggleRecording() async {
        do {
            if meetingService.isRecording {
                try await meetingService.stopMeeting()
            } else {
                try await meetingService.startMeeting()
            }
        } catch {
            if error.localizedDescription.contains("permission") {
                showingPermissionsAlert = true
            }
        }
    }
    
    private func generateLiveSummary() {
        // For Phase 1, this could trigger a summary of current transcript
        // Implementation depends on the AI service integration
    }
}

// MARK: - Meeting Content

struct MeetingContentView: View {
    @ObservedObject var meetingService: MeetingService
    @Binding var selectedTab: Int
    @Binding var autoScroll: Bool
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Live Transcript Tab
            TranscriptView(meetingService: meetingService, autoScroll: $autoScroll)
                .tabItem {
                    Image(systemName: "text.bubble")
                    Text("Transcript")
                }
                .tag(0)
            
            // Summary Tab
            SummaryView(meetingService: meetingService)
                .tabItem {
                    Image(systemName: "doc.text")
                    Text("Summary")
                }
                .tag(1)
        }
        .frame(height: 400)
    }
}

// MARK: - Transcript View

struct TranscriptView: View {
    @ObservedObject var meetingService: MeetingService
    @Binding var autoScroll: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Controls
            HStack {
                Toggle("Auto-scroll", isOn: $autoScroll)
                    .font(.caption)
                
                Spacer()
                
                if meetingService.isRecording {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.red)
                            .frame(width: 6, height: 6)
                            .scaleEffect(1.0)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: meetingService.isRecording)
                        
                        Text("Live")
                            .font(.caption)
                            .foregroundColor(.red)
                            .fontWeight(.medium)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            
            Divider()
            
            // Transcript content
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        // Final transcript
                        if !meetingService.finalTranscript.isEmpty {
                            TranscriptTextView(
                                text: meetingService.finalTranscript,
                                isLive: false
                            )
                            .id("final")
                        }
                        
                        // Live transcript (if recording)
                        if meetingService.isRecording {
                            TranscriptTextView(
                                text: meetingService.liveTranscript.isEmpty ? "Listening..." : meetingService.liveTranscript,
                                isLive: true
                            )
                            .id("live")
                        }
                        
                        // Bottom spacer for better scrolling
                        Spacer()
                            .frame(height: 20)
                            .id("bottom")
                    }
                    .padding()
                }
                .onChange(of: meetingService.finalTranscript) {
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: meetingService.liveTranscript) {
                    scrollToBottom(proxy: proxy)
                }
                .onAppear {
                    scrollToBottom(proxy: proxy)
                }
            }
        }
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        if autoScroll {
            withAnimation(.easeInOut(duration: 0.3)) {
                if meetingService.isRecording {
                    proxy.scrollTo("live", anchor: .bottom)
                } else {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }
}

// MARK: - Transcript Text View

struct TranscriptTextView: View {
    let text: String
    let isLive: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isLive {
                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.red)
                            .frame(width: 6, height: 6)
                            .scaleEffect(1.0)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isLive)
                        
                        Text("Live Transcript")
                            .font(.caption)
                            .foregroundColor(.red)
                            .fontWeight(.medium)
                    }
                    Spacer()
                }
            }
            
            Text(text)
                .font(.body)
                .textSelection(.enabled)
                .foregroundColor(text == "Listening..." ? .secondary : .primary)
                .italic(text == "Listening...")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(isLive ? Color.red.opacity(0.05) : Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isLive ? Color.red.opacity(0.3) : Color.clear, lineWidth: 1)
                )
                .cornerRadius(8)
        }
    }
}

// MARK: - Summary View

struct SummaryView: View {
    @ObservedObject var meetingService: MeetingService
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let summary = meetingService.meetingSummary {
                    // Meeting summary content
                    VStack(alignment: .leading, spacing: 12) {
                        Text(summary.title)
                            .font(.headline)
                        
                        HStack {
                            Label(summary.duration, systemImage: "clock")
                            Spacer()
                            Label("\(summary.wordCount) words", systemImage: "text.word.spacing")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    
                    if !summary.keyTopics.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Key Topics")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            LazyVGrid(columns: [
                                GridItem(.adaptive(minimum: 100))
                            ], spacing: 8) {
                                ForEach(summary.keyTopics, id: \.self) { topic in
                                    Text(topic)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.accentColor.opacity(0.1))
                                        .cornerRadius(12)
                                }
                            }
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                } else if meetingService.isRecording {
                    // Recording in progress
                    VStack(spacing: 16) {
                        Image(systemName: "waveform")
                            .font(.largeTitle)
                            .foregroundColor(.accentColor)
                        
                        Text("Recording in Progress")
                            .font(.headline)
                        
                        Text("Summary will be generated when the meeting ends")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !meetingService.finalTranscript.isEmpty {
                    // Has transcript but no summary yet
                    VStack(spacing: 16) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        
                        Text("Processing Summary")
                            .font(.headline)
                        
                        Text("Summary is being generated from the transcript")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // No meeting content
                    VStack(spacing: 16) {
                        Image(systemName: "doc.text")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        
                        Text("No Summary Available")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("Start a meeting to generate a summary")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding()
        }
    }
}

// MARK: - Getting Started View

struct MeetingGettingStartedView: View {
    @ObservedObject var meetingService: MeetingService
    
    var body: some View {
        VStack(spacing: 24) {
            // Hero section
            VStack(spacing: 16) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)
                
                Text("Meeting Transcription")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Record and transcribe meetings with AI-powered summaries")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Features
            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "mic.fill", title: "Real-time Transcription", description: "Live speech-to-text with high accuracy")
                FeatureRow(icon: "brain.head.profile", title: "AI Summaries", description: "Generate key insights and action items")
                FeatureRow(icon: "lock.shield", title: "Privacy First", description: "All processing happens on your device")
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            
            // Get started button
            Button {
                Task {
                    try? await meetingService.startMeeting()
                }
            } label: {
                HStack {
                    Image(systemName: "record.circle")
                    Text("Start Recording")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.accentColor)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Feature Row

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

// MARK: - Export View

struct MeetingExportView: View {
    @ObservedObject var meetingService: MeetingService
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Export Meeting")
                .font(.headline)
            
            VStack(spacing: 12) {
                Button("Export Transcript as Text") {
                    exportTranscript()
                }
                .buttonStyle(.borderedProminent)
                
                if meetingService.meetingSummary != nil {
                    Button("Export Summary as Markdown") {
                        exportSummary()
                    }
                    .buttonStyle(.bordered)
                }
                
                Button("Copy Transcript to Clipboard") {
                    copyToClipboard()
                }
                .buttonStyle(.bordered)
            }
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Spacer()
            }
        }
        .padding()
        .frame(width: 300, height: 200)
    }
    
    private func exportTranscript() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.nameFieldStringValue = "Meeting Transcript.txt"
        
        if savePanel.runModal() == .OK {
            if let url = savePanel.url {
                try? meetingService.finalTranscript.write(to: url, atomically: true, encoding: .utf8)
            }
        }
        dismiss()
    }
    
    private func exportSummary() {
        guard let summary = meetingService.meetingSummary else { return }
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.text]
        savePanel.nameFieldStringValue = "Meeting Summary.md"
        
        if savePanel.runModal() == .OK {
            if let url = savePanel.url {
                let markdown = """
                # \(summary.title)
                
                **Duration:** \(summary.duration)  
                **Word Count:** \(summary.wordCount)
                
                ## Key Topics
                \(summary.keyTopics.map { "- \($0)" }.joined(separator: "\n"))
                
                ## Full Transcript
                \(meetingService.finalTranscript)
                """
                
                try? markdown.write(to: url, atomically: true, encoding: .utf8)
            }
        }
        dismiss()
    }
    
    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(meetingService.finalTranscript, forType: .string)
        dismiss()
    }
}

#Preview {
    MeetingWidgetView()
        .environmentObject(AppStore.shared)
        .frame(width: 800, height: 600)
}