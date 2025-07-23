//
//  ScreenCaptureService.swift
//  Insig8
//
//  Complete screen capture and OCR implementation with Vision framework
//

import Foundation
import ScreenCaptureKit
import Vision
import AppKit
import Combine
import os.log

@MainActor
class ScreenCaptureService: ObservableObject {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Insig8", category: "ScreenCapture")
    
    // Capture state
    @Published var isMonitoring = false
    @Published var monitoredApps: Set<String> = ["Slack", "Microsoft Teams", "Discord", "Mail", "Messages"]
    @Published var captureStatistics = CaptureStatistics()
    @Published var lastCaptureTime: Date?
    @Published var permissionGranted = false
    
    // Performance metrics
    @Published var lastOCRTime: TimeInterval = 0
    @Published var averageOCRTime: TimeInterval = 0
    
    private var stream: SCStream?
    private var captureTimer: Timer?
    private let ocrQueue = DispatchQueue(label: "ai.insig8.ocr", qos: .userInitiated)
    private let processedContentCache = NSCache<NSString, ProcessedScreenContent>()
    
    // OCR request factory for thread safety
    nonisolated private func createOCRRequest() -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US"]
        return request
    }
    
    init() {
        logger.info("Initializing ScreenCaptureService")
        checkPermissions()
        setupCache()
    }
    
    // MARK: - Permission Management
    
    private func checkPermissions() {
        // Check if we have screen recording permission
        Task {
            permissionGranted = await requestScreenRecordingPermission()
            
            // Update UI state based on permission
            if !permissionGranted {
                logger.info("Screen capture features will be disabled until permission is granted")
            }
        }
    }
    
    /// Get user-friendly permission status message
    func getPermissionStatusMessage() -> String {
        if permissionGranted {
            return "Screen recording permission granted - monitoring active"
        } else {
            return "Screen recording permission required for app monitoring. Enable in System Settings > Privacy & Security > Screen Recording"
        }
    }
    
    /// Request screen recording permission using Apple's recommended approach for macOS 15+
    func requestScreenRecordingPermission() async -> Bool {
        logger.info("Requesting screen recording permission...")
        
        // For macOS 15+, use a more robust approach
        if #available(macOS 15.0, *) {
            return await requestPermissionMacOS15()
        } else {
            return await requestPermissionLegacy()
        }
    }
    
    @available(macOS 15.0, *)
    private func requestPermissionMacOS15() async -> Bool {
        // macOS 15 requires special handling due to Sequoia permission changes
        do {
            // First, try to check current permission status without triggering a prompt
            let _ = try await SCShareableContent.current
            logger.info("Screen recording permission already granted")
            return true
        } catch {
            logger.info("Screen recording permission needed, starting request flow...")
            
            // Set app to regular to show in dock temporarily
            let originalPolicy = NSApp.activationPolicy()
            NSApp.setActivationPolicy(.regular)
            
            // Bring app to foreground to ensure permission dialog appears
            NSApp.activate(ignoringOtherApps: true)
            
            // Wait for app to become active
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
            // Try to get shareable content which will trigger permission dialog
            do {
                let content = try await SCShareableContent.current
                logger.info("Successfully obtained shareable content after permission request")
                
                // Test with a minimal capture to ensure permission works
                if let display = content.displays.first {
                    // Use the newer recommended initializer for macOS 15
                    let filter = SCContentFilter(display: display, including: [], exceptingWindows: [])
                    let configuration = SCStreamConfiguration()
                    configuration.width = 1
                    configuration.height = 1
                    configuration.minimumFrameInterval = CMTime(seconds: 1, preferredTimescale: 1)
                    
                    let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
                    
                    do {
                        try await stream.startCapture()
                        try? await stream.stopCapture()
                        logger.info("Screen recording permission granted and verified")
                        
                        // Restore original activation policy
                        NSApp.setActivationPolicy(originalPolicy)
                        return true
                    } catch {
                        logger.error("Failed to start test capture: \(error)")
                        NSApp.setActivationPolicy(originalPolicy)
                        return false
                    }
                } else {
                    logger.warning("No displays found")
                    NSApp.setActivationPolicy(originalPolicy)
                    return false
                }
            } catch let scError {
                logger.error("Permission request failed: \(scError)")
                
                // Handle specific error codes
                if let nsError = scError as NSError?,
                   nsError.domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain",
                   nsError.code == -3801 {
                    logger.info("User declined screen recording permission - screen monitoring will be disabled")
                } else {
                    logger.warning("Screen recording permission check failed: \(scError)")
                }
                
                NSApp.setActivationPolicy(originalPolicy)
                return false
            }
        }
    }
    
    private func requestPermissionLegacy() async -> Bool {
        // Legacy approach for macOS < 15
        do {
            let _ = try await SCShareableContent.current
            logger.info("Screen recording permission already granted (legacy)")
            return true
        } catch {
            logger.info("Screen recording permission needed (legacy)")
            
            // Force app to become regular app temporarily
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            
            // Wait for app to become active
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            do {
                let content = try await SCShareableContent.current
                
                if let display = content.displays.first {
                    let filter = SCContentFilter(display: display, excludingWindows: [])
                    let configuration = SCStreamConfiguration()
                    configuration.width = 100
                    configuration.height = 100
                    
                    let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
                    try await stream.startCapture()
                    try? await stream.stopCapture()
                    
                    logger.info("Screen recording permission granted (legacy)")
                    NSApp.setActivationPolicy(.accessory)
                    return true
                }
            } catch let scError {
                logger.error("Failed to request permission (legacy): \(scError)")
                
                // Handle specific error codes
                if let nsError = scError as NSError?,
                   nsError.domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain",
                   nsError.code == -3801 {
                    logger.info("User declined screen recording permission - screen monitoring will be disabled")
                } else {
                    logger.warning("Screen recording permission check failed: \(scError)")
                }
                
                NSApp.setActivationPolicy(.accessory)
                return false
            }
        }
        
        NSApp.setActivationPolicy(.accessory)
        return false
    }
    
    // MARK: - Monitoring Control
    
    func startMonitoring() async throws {
        if !permissionGranted {
            permissionGranted = await requestScreenRecordingPermission()
            guard permissionGranted else {
                throw CaptureError.permissionDenied
            }
        }
        
        logger.info("Starting screen monitoring for apps: \(self.monitoredApps)")
        
        // Create capture stream
        try await setupCaptureStream()
        
        // Start periodic capture (every 2 seconds)
        await MainActor.run {
            captureTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                Task {
                    await self.captureAndProcess()
                }
            }
            isMonitoring = true
        }
    }
    
    func stopMonitoring() async {
        logger.info("Stopping screen monitoring")
        
        await MainActor.run {
            captureTimer?.invalidate()
            captureTimer = nil
            isMonitoring = false
        }
        
        if let stream = stream {
            try? await stream.stopCapture()
            self.stream = nil
        }
    }
    
    // MARK: - Screen Capture Setup
    
    private func setupCaptureStream() async throws {
        // Get shareable content
        let content = try await SCShareableContent.current
        
        // Find windows for monitored apps
        let monitoredWindows = content.windows.filter { window in
            guard let app = window.owningApplication else { return false }
            return monitoredApps.contains(app.applicationName)
        }
        
        guard !monitoredWindows.isEmpty else {
            logger.warning("No monitored app windows found")
            return
        }
        
        // Create filter for monitored windows
        let filter = SCContentFilter(desktopIndependentWindow: monitoredWindows.first!)
        
        // Configure stream
        let config = SCStreamConfiguration()
        config.width = 1920 // Max width
        config.height = 1080 // Max height
        config.scalesToFit = true
        config.capturesAudio = false
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1) // 1 FPS for efficiency
        
        // Create stream
        stream = SCStream(filter: filter, configuration: config, delegate: nil)
        
        logger.info("Screen capture stream configured for \(monitoredWindows.count) windows")
    }
    
    // MARK: - Capture and Processing
    
    private func captureAndProcess() async {
        guard isMonitoring else { return }
        
        do {
            let content = try await SCShareableContent.current
            
            // Process each monitored app window
            for window in content.windows {
                guard let app = window.owningApplication,
                      monitoredApps.contains(app.applicationName) else { continue }
                
                // Capture window
                let image = try await captureWindow(window)
                
                // Process with OCR
                let processedContent = try await processScreenCapture(
                    image: image,
                    appName: app.applicationName,
                    windowTitle: window.title ?? "Unknown"
                )
                
                // Cache result
                let cacheKey = "\(app.applicationName)-\(window.windowID)" as NSString
                processedContentCache.setObject(processedContent, forKey: cacheKey)
                
                // Send to AI pipeline if there's interesting content
                if processedContent.hasInterestingContent {
                    await sendToAIPipeline(processedContent)
                }
                
                // Update statistics
                await updateStatistics(processedContent)
            }
            
            lastCaptureTime = Date()
            
        } catch {
            logger.error("Capture and process failed: \(error)")
        }
    }
    
    private func captureWindow(_ window: SCWindow) async throws -> CGImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        
        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width)
        config.height = Int(window.frame.height)
        
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
        
        return image
    }
    
    // MARK: - OCR Processing
    
    private func processScreenCapture(image: CGImage, appName: String, windowTitle: String) async throws -> ProcessedScreenContent {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Perform OCR
        let text = try await extractText(from: image)
        
        // Parse app-specific content
        let parsedContent = parseAppContent(text, appName: appName)
        
        // Detect unresponded messages
        let unrespondedMessages = detectUnrespondedMessages(in: parsedContent, appName: appName)
        
        // Extract key information
        let keyInfo = extractKeyInformation(from: parsedContent)
        
        let ocrTime = CFAbsoluteTimeGetCurrent() - startTime
        lastOCRTime = ocrTime
        
        // Update average
        let totalSamples = captureStatistics.totalCaptures + 1
        averageOCRTime = ((averageOCRTime * Double(captureStatistics.totalCaptures)) + ocrTime) / Double(totalSamples)
        
        logger.debug("OCR completed in \(ocrTime * 1000)ms for \(appName)")
        
        return ProcessedScreenContent(
            id: UUID(),
            appName: appName,
            windowTitle: windowTitle,
            extractedText: text,
            parsedContent: parsedContent,
            unrespondedMessages: unrespondedMessages,
            keyInformation: keyInfo,
            timestamp: Date(),
            processingTime: ocrTime,
            hasInterestingContent: !unrespondedMessages.isEmpty || !keyInfo.commitments.isEmpty
        )
    }
    
    private func extractText(from image: CGImage) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            ocrQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: CaptureError.serviceUnavailable)
                    return
                }
                
                let ocrRequest = self.createOCRRequest()
                let handler = VNImageRequestHandler(cgImage: image, options: [:])
                
                do {
                    try handler.perform([ocrRequest])
                    
                    guard let observations = ocrRequest.results else {
                        continuation.resume(returning: "")
                        return
                    }
                    
                    // Extract text with confidence threshold
                    let recognizedText = observations
                        .compactMap { observation in
                            observation.topCandidates(1).first?.string
                        }
                        .joined(separator: "\n")
                    
                    continuation.resume(returning: recognizedText)
                    
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - App-Specific Parsing
    
    private func parseAppContent(_ text: String, appName: String) -> ParsedContent {
        switch appName {
        case "Slack":
            return parseSlackContent(text)
        case "Microsoft Teams":
            return parseTeamsContent(text)
        case "Discord":
            return parseDiscordContent(text)
        case "Mail":
            return parseMailContent(text)
        case "Messages":
            return parseMessagesContent(text)
        default:
            return parseGenericContent(text)
        }
    }
    
    private func parseSlackContent(_ text: String) -> ParsedContent {
        var messages: [Message] = []
        var channels: [String] = []
        var mentions: [String] = []
        
        let lines = text.components(separatedBy: .newlines)
        var currentMessage: Message?
        
        for line in lines {
            // Detect channel names
            if line.starts(with: "#") {
                if let channel = line.split(separator: " ").first {
                    channels.append(String(channel))
                }
            }
            
            // Detect mentions
            let mentionRegex = try? NSRegularExpression(pattern: "@[\\w]+", options: [])
            if let regex = mentionRegex {
                let matches = regex.matches(in: line, range: NSRange(line.startIndex..., in: line))
                for match in matches {
                    if let range = Range(match.range, in: line) {
                        mentions.append(String(line[range]))
                    }
                }
            }
            
            // Parse messages (simplified - production would be more sophisticated)
            if let timeMatch = extractTimestamp(from: line) {
                // Save previous message if exists
                if let msg = currentMessage {
                    messages.append(msg)
                }
                
                // Start new message
                currentMessage = Message(
                    sender: extractSender(from: line) ?? "Unknown",
                    content: "",
                    timestamp: timeMatch,
                    isUnread: line.contains("•") // Slack uses bullet for unread
                )
            } else if var msg = currentMessage {
                // Append to current message content
                msg.content += "\n" + line
                currentMessage = msg
            }
        }
        
        // Add last message
        if let msg = currentMessage {
            messages.append(msg)
        }
        
        return ParsedContent(
            messages: messages,
            channels: channels,
            mentions: mentions,
            rawText: text
        )
    }
    
    private func parseTeamsContent(_ text: String) -> ParsedContent {
        // Similar parsing logic for Teams
        return parseGenericContent(text)
    }
    
    private func parseDiscordContent(_ text: String) -> ParsedContent {
        // Similar parsing logic for Discord
        return parseGenericContent(text)
    }
    
    private func parseMailContent(_ text: String) -> ParsedContent {
        var messages: [Message] = []
        let lines = text.components(separatedBy: .newlines)
        
        // Look for email patterns
        var currentEmail: Message?
        
        for line in lines {
            if line.contains("From:") {
                if let email = currentEmail {
                    messages.append(email)
                }
                
                let sender = line.replacingOccurrences(of: "From:", with: "").trimmingCharacters(in: .whitespaces)
                currentEmail = Message(
                    sender: sender,
                    content: "",
                    timestamp: Date(),
                    isUnread: true
                )
            } else if line.contains("Subject:") && currentEmail != nil {
                let subject = line.replacingOccurrences(of: "Subject:", with: "").trimmingCharacters(in: .whitespaces)
                currentEmail?.content = subject
            }
        }
        
        if let email = currentEmail {
            messages.append(email)
        }
        
        return ParsedContent(
            messages: messages,
            channels: [],
            mentions: [],
            rawText: text
        )
    }
    
    private func parseMessagesContent(_ text: String) -> ParsedContent {
        // Parse iMessage/SMS content
        return parseGenericContent(text)
    }
    
    private func parseGenericContent(_ text: String) -> ParsedContent {
        return ParsedContent(
            messages: [],
            channels: [],
            mentions: [],
            rawText: text
        )
    }
    
    // MARK: - Message Analysis
    
    private func detectUnrespondedMessages(in content: ParsedContent, appName: String) -> [UnrespondedMessage] {
        var unresponded: [UnrespondedMessage] = []
        
        for message in content.messages {
            // Check if message requires response
            if requiresResponse(message: message, appName: appName) {
                let urgency = calculateUrgency(message: message, mentions: content.mentions)
                
                unresponded.append(UnrespondedMessage(
                    id: UUID(),
                    appName: appName,
                    sender: message.sender,
                    content: message.content,
                    timestamp: message.timestamp,
                    urgencyLevel: urgency,
                    suggestedAction: generateSuggestedAction(message: message, urgency: urgency)
                ))
            }
        }
        
        return unresponded
    }
    
    private func requiresResponse(message: Message, appName: String) -> Bool {
        let content = message.content.lowercased()
        
        // Question indicators
        if content.contains("?") { return true }
        
        // Request patterns
        let requestPatterns = [
            "can you", "could you", "would you", "will you",
            "please", "let me know", "thoughts", "feedback",
            "when", "where", "what", "how", "why",
            "asap", "urgent", "immediately", "eod", "eow"
        ]
        
        for pattern in requestPatterns {
            if content.contains(pattern) { return true }
        }
        
        // Direct mentions usually require response
        if content.contains("@") { return true }
        
        return false
    }
    
    private func calculateUrgency(message: Message, mentions: [String]) -> Priority {
        let content = message.content.lowercased()
        
        // High priority indicators
        let highPriorityWords = ["urgent", "asap", "immediately", "critical", "emergency", "now"]
        for word in highPriorityWords {
            if content.contains(word) { return .urgent }
        }
        
        // Medium priority - direct mentions or time-sensitive
        if mentions.contains(where: { content.contains($0.lowercased()) }) {
            return .high
        }
        
        let timeSensitiveWords = ["today", "eod", "tomorrow", "deadline", "due"]
        for word in timeSensitiveWords {
            if content.contains(word) { return .medium }
        }
        
        return .low
    }
    
    private func generateSuggestedAction(message: Message, urgency: Priority) -> String {
        switch urgency {
        case .urgent:
            return "Respond immediately - marked as urgent"
        case .high:
            return "Respond within 30 minutes - you were mentioned"
        case .medium:
            return "Respond within 2 hours"
        case .low:
            return "Respond when convenient"
        }
    }
    
    // MARK: - Key Information Extraction
    
    private func extractKeyInformation(from content: ParsedContent) -> KeyInformation {
        let text = content.rawText
        
        // Extract commitments
        let commitments = extractCommitments(from: text)
        
        // Extract deadlines
        let deadlines = extractDeadlines(from: text)
        
        // Extract action items
        let actionItems = extractActionItems(from: text)
        
        // Extract links
        let links = extractLinks(from: text)
        
        return KeyInformation(
            commitments: commitments,
            deadlines: deadlines,
            actionItems: actionItems,
            links: links
        )
    }
    
    private func extractCommitments(from text: String) -> [String] {
        let patterns = [
            "I'll", "I will", "I can", "I should",
            "will do", "will send", "will follow up",
            "let me", "I'll get back"
        ]
        
        var commitments: [String] = []
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
        
        for sentence in sentences {
            for pattern in patterns {
                if sentence.contains(pattern) {
                    commitments.append(sentence.trimmingCharacters(in: .whitespacesAndNewlines))
                    break
                }
            }
        }
        
        return commitments
    }
    
    private func extractDeadlines(from text: String) -> [String] {
        // Simple deadline extraction - production would use NLP
        let patterns = [
            "by", "before", "deadline", "due",
            "end of day", "eod", "end of week", "eow",
            "tomorrow", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday"
        ]
        
        var deadlines: [String] = []
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
        
        for sentence in sentences {
            for pattern in patterns {
                if sentence.lowercased().contains(pattern.lowercased()) {
                    deadlines.append(sentence.trimmingCharacters(in: .whitespacesAndNewlines))
                    break
                }
            }
        }
        
        return deadlines
    }
    
    private func extractActionItems(from text: String) -> [String] {
        // Look for action item patterns
        let patterns = [
            "TODO", "todo", "To do",
            "Action:", "ACTION:",
            "- [ ]", "• ", "- "
        ]
        
        var actionItems: [String] = []
        let lines = text.components(separatedBy: .newlines)
        
        for line in lines {
            for pattern in patterns {
                if line.contains(pattern) {
                    let item = line.replacingOccurrences(of: pattern, with: "").trimmingCharacters(in: .whitespaces)
                    if !item.isEmpty {
                        actionItems.append(item)
                        break
                    }
                }
            }
        }
        
        return actionItems
    }
    
    private func extractLinks(from text: String) -> [String] {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: text, range: NSRange(location: 0, length: text.utf16.count)) ?? []
        
        return matches.compactMap { match in
            if let range = Range(match.range, in: text) {
                return String(text[range])
            }
            return nil
        }
    }
    
    // MARK: - Helper Methods
    
    private func extractTimestamp(from line: String) -> Date? {
        // Simple time extraction - would be more sophisticated in production
        let timePattern = #"\d{1,2}:\d{2}\s*(AM|PM|am|pm)?"#
        if let regex = try? NSRegularExpression(pattern: timePattern),
           let _ = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
            // For demo, return current date with extracted time
            return Date()
        }
        return nil
    }
    
    private func extractSender(from line: String) -> String? {
        // Extract sender name (simplified)
        let components = line.components(separatedBy: " ")
        if components.count > 1 {
            return components.first
        }
        return nil
    }
    
    // MARK: - Integration
    
    private func sendToAIPipeline(_ content: ProcessedScreenContent) async {
        logger.info("Sending screen content to AI pipeline from \(content.appName)")
        
        // Send to AppStore for processing
        let appStore = AppStore.shared
        appStore.ingestScreenCaptureData(content.extractedText, appName: content.appName)
        
        // Create actions from unresponded messages
        let screenContext = ScreenContext(
            appName: content.appName,
            channelName: nil, // Would extract from content.windowTitle
            windowTitle: content.windowTitle
        )
        
        for message in content.unrespondedMessages {
            logger.info("Creating action for unresponded message from \(message.sender ?? "Unknown") with \(message.urgencyLevel.rawValue) priority")
            let _ = appStore.actionManager.createAction(from: message, context: screenContext)
        }
        
        // Check for responses to existing actions
        appStore.actionManager.checkForResponses(in: content)
        
        // Look for new commitments in outgoing messages
        for message in content.parsedContent.messages {
            // Simple heuristic: if message is from current user (not in participants list typically)
            if !content.unrespondedMessages.contains(where: { $0.sender == message.sender }) {
                if let _ = appStore.actionManager.createCommitmentAction(from: message.content, context: screenContext) {
                    logger.info("Created commitment action from outgoing message")
                }
            }
        }
    }
    
    private func updateStatistics(_ content: ProcessedScreenContent) async {
        await MainActor.run {
            captureStatistics.totalCaptures += 1
            captureStatistics.totalOCRTime += content.processingTime
            captureStatistics.averageOCRTime = captureStatistics.totalOCRTime / Double(captureStatistics.totalCaptures)
            
            if content.hasInterestingContent {
                captureStatistics.interestingCaptures += 1
            }
            
            captureStatistics.unrespondedMessageCount += content.unrespondedMessages.count
            captureStatistics.lastUpdateTime = Date()
        }
    }
    
    private func setupCache() {
        processedContentCache.countLimit = 100 // Keep last 100 captures
        processedContentCache.totalCostLimit = 50 * 1024 * 1024 // 50MB max
    }
    
    // MARK: - Public API
    
    func addMonitoredApp(_ appName: String) {
        monitoredApps.insert(appName)
        logger.info("Added \(appName) to monitored apps")
        
        // Restart monitoring if active
        if isMonitoring {
            Task {
                await stopMonitoring()
                try? await startMonitoring()
            }
        }
    }
    
    func removeMonitoredApp(_ appName: String) {
        monitoredApps.remove(appName)
        logger.info("Removed \(appName) from monitored apps")
        
        // Restart monitoring if active
        if isMonitoring {
            Task {
                await stopMonitoring()
                if !monitoredApps.isEmpty {
                    try? await startMonitoring()
                }
            }
        }
    }
    
    func getRecentCaptures(limit: Int = 10) -> [ProcessedScreenContent] {
        // In production, this would query from a database
        return []
    }
}

// MARK: - Supporting Types

class ProcessedScreenContent: NSObject {
    let id: UUID
    let appName: String
    let windowTitle: String
    let extractedText: String
    let parsedContent: ParsedContent
    let unrespondedMessages: [UnrespondedMessage]
    let keyInformation: KeyInformation
    let timestamp: Date
    let processingTime: TimeInterval
    let hasInterestingContent: Bool
    
    init(id: UUID, appName: String, windowTitle: String, extractedText: String, parsedContent: ParsedContent, unrespondedMessages: [UnrespondedMessage], keyInformation: KeyInformation, timestamp: Date, processingTime: TimeInterval, hasInterestingContent: Bool) {
        self.id = id
        self.appName = appName
        self.windowTitle = windowTitle
        self.extractedText = extractedText
        self.parsedContent = parsedContent
        self.unrespondedMessages = unrespondedMessages
        self.keyInformation = keyInformation
        self.timestamp = timestamp
        self.processingTime = processingTime
        self.hasInterestingContent = hasInterestingContent
        super.init()
    }
}

struct ParsedContent {
    let messages: [Message]
    let channels: [String]
    let mentions: [String]
    let rawText: String
}

struct Message {
    let sender: String
    var content: String
    let timestamp: Date
    let isUnread: Bool
}

struct UnrespondedMessage {
    let id: UUID
    let appName: String
    let sender: String?
    let content: String
    let timestamp: Date?
    let urgencyLevel: Priority
    let suggestedAction: String
}

struct KeyInformation {
    let commitments: [String]
    let deadlines: [String]
    let actionItems: [String]
    let links: [String]
}

struct CaptureStatistics {
    var totalCaptures: Int = 0
    var interestingCaptures: Int = 0
    var totalOCRTime: TimeInterval = 0
    var averageOCRTime: TimeInterval = 0
    var unrespondedMessageCount: Int = 0
    var lastUpdateTime: Date?
}

enum CaptureError: LocalizedError {
    case permissionDenied
    case serviceUnavailable
    case captureConfigurationFailed
    case ocrFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Screen recording permission denied"
        case .serviceUnavailable:
            return "Screen capture service unavailable"
        case .captureConfigurationFailed:
            return "Failed to configure screen capture"
        case .ocrFailed(let reason):
            return "OCR processing failed: \(reason)"
        }
    }
}