import ScreenCaptureKit
import AVFoundation
import OSLog

@Observable final class AudioCaptureService: NSObject, SCStreamOutput, SCStreamDelegate {
    private let logger = Logger(subsystem: "com.insig8", category: "AudioCapture")
    private var stream: SCStream?
    let outputFormat: AVAudioFormat
    let sampleBufferStream: AsyncStream<CMSampleBuffer>
    private var continuation: AsyncStream<CMSampleBuffer>.Continuation!

    override init() {
        // 48 kHz stereo PCM – SpeechTranscriber's preferred format
        outputFormat = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        
        // Create the async stream
        var tempContinuation: AsyncStream<CMSampleBuffer>.Continuation!
        sampleBufferStream = AsyncStream { continuation in
            tempContinuation = continuation
            continuation.onTermination = { _ in }
        }
        
        super.init()
        continuation = tempContinuation
    }
    
    func start() async throws {
        let config = SCStreamConfiguration()
        config.capturesAudio     = true            // speaker
        config.captureMicrophone = true            // mic
        config.sampleRate        = 48_000
        config.channelCount      = 2
        config.width            = 1              // Minimal video to prevent errors
        config.height           = 1
        config.pixelFormat      = kCVPixelFormatType_32BGRA

        // Get the main display
        let displays = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true).displays
        guard let mainDisplay = displays.first else {
            throw NSError(domain: "AudioCaptureService", code: 1, userInfo: [NSLocalizedDescriptionKey: "No display found"])
        }
        
        // Create content filter with minimal video capture to avoid stream errors
        let filter = SCContentFilter(display: mainDisplay, excludingWindows: [])
        stream = SCStream(filter: filter, configuration: config, delegate: self)
        
        // Add stream outputs with proper error handling
        do {
            try stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global())
            try stream?.addStreamOutput(self, type: .microphone, sampleHandlerQueue: .global())
            try await stream?.startCapture()
            logger.info("Audio capture started successfully")
        } catch {
            logger.error("Failed to start audio capture: \(error)")
            throw error
        }
    }

    func stop() {
        Task { [stream] in
            if let stream = stream {
                do {
                    try await stream.stopCapture()
                    logger.info("Stream stopped successfully")
                } catch {
                    logger.error("Error stopping stream: \(error)")
                }
            }
            continuation.finish()
            logger.info("Audio capture stopped")
        }
        
        // Clear stream reference immediately
        stream = nil
    }

    // MARK: - SCStreamOutput
    func stream(_ s: SCStream,
                didOutputSampleBuffer sb: CMSampleBuffer,
                of type: SCStreamOutputType) {
        // Only process audio samples, ignore video
        if type == .audio || type == .microphone {
            continuation.yield(sb)
        }
    }
    
    // MARK: - SCStreamDelegate
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        logger.error("Stream stopped with error: \(error)")
        continuation.finish()
    }
    
    func streamDidBecomeActive(_ stream: SCStream) {
        logger.info("Stream became active")
    }
    
    func streamDidBecomeInactive(_ stream: SCStream) {
        logger.info("Stream became inactive")
    }
    
}