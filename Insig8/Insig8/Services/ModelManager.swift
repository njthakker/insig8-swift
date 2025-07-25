import Foundation
import CoreML
import OSLog
import Combine

/// Manages CoreML model loading and lifecycle for meeting transcription
final class ModelManager: ObservableObject {
    private let logger = Logger(subsystem: "com.insig8.ModelManager", category: "Models")
    
    // MARK: - Model References
    private var parakeetASR: MLModel?
    private var sileroVAD: MLModel?
    private var titanetSpeaker: MLModel?
    
    // MARK: - Model Status
    @Published var isASRLoaded = false
    @Published var isVADLoaded = false
    @Published var isSpeakerLoaded = false
    
    // MARK: - Singleton
    static let shared = ModelManager()
    private init() {}
    
    // MARK: - Model Loading
    
    /// Load all required models for meeting transcription
    func loadAllModels() async throws {
        logger.info("Loading all CoreML models for meeting transcription")
        
        async let asrTask: Void = loadParakeetASR()
        async let vadTask: Void = loadSileroVAD()
        async let speakerTask: Void = loadTitaNetSpeaker()
        
        do {
            _ = try await (asrTask, vadTask, speakerTask)
            logger.info("All models loaded successfully")
        } catch {
            logger.error("Failed to load models: \(error.localizedDescription)")
            throw ModelError.failedToLoadModels(error)
        }
    }
    
    /// Load Parakeet ASR model for speech recognition
    func loadParakeetASR() async throws {
        guard parakeetASR == nil else { return }
        
        guard let modelURL = Bundle.main.url(forResource: "Parakeet_TDT0.6b", withExtension: "mlmodelc") else {
            logger.warning("Parakeet ASR model not found, will use fallback")
            await MainActor.run { isASRLoaded = false }
            return
        }
        
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndNeuralEngine
            
            parakeetASR = try MLModel(contentsOf: modelURL, configuration: config)
            await MainActor.run { isASRLoaded = true }
            logger.info("Parakeet ASR model loaded successfully")
        } catch {
            logger.error("Failed to load Parakeet ASR: \(error.localizedDescription)")
            await MainActor.run { isASRLoaded = false }
            throw ModelError.asrLoadFailed(error)
        }
    }
    
    /// Load Silero VAD model for voice activity detection
    func loadSileroVAD() async throws {
        guard sileroVAD == nil else { return }
        
        guard let modelURL = Bundle.main.url(forResource: "silero_vad_16k_coreml", withExtension: "mlmodelc") else {
            logger.warning("Silero VAD model not found, will use fallback")
            await MainActor.run { isVADLoaded = false }
            return
        }
        
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndNeuralEngine
            
            sileroVAD = try MLModel(contentsOf: modelURL, configuration: config)
            await MainActor.run { isVADLoaded = true }
            logger.info("Silero VAD model loaded successfully")
        } catch {
            logger.error("Failed to load Silero VAD: \(error.localizedDescription)")
            await MainActor.run { isVADLoaded = false }
            throw ModelError.vadLoadFailed(error)
        }
    }
    
    /// Load TitaNet model for speaker embeddings
    func loadTitaNetSpeaker() async throws {
        guard titanetSpeaker == nil else { return }
        
        guard let modelURL = Bundle.main.url(forResource: "titanet_large_coreml", withExtension: "mlmodelc") else {
            logger.warning("TitaNet speaker model not found, will use fallback")
            await MainActor.run { isSpeakerLoaded = false }
            return
        }
        
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndNeuralEngine
            
            titanetSpeaker = try MLModel(contentsOf: modelURL, configuration: config)
            await MainActor.run { isSpeakerLoaded = true }
            logger.info("TitaNet speaker model loaded successfully")
        } catch {
            logger.error("Failed to load TitaNet speaker: \(error.localizedDescription)")
            await MainActor.run { isSpeakerLoaded = false }
            throw ModelError.speakerLoadFailed(error)
        }
    }
    
    // MARK: - Model Access
    
    /// Get loaded Parakeet ASR model
    func getASRModel() throws -> MLModel {
        guard let model = parakeetASR else {
            throw ModelError.modelNotLoaded("Parakeet ASR")
        }
        return model
    }
    
    /// Get loaded Silero VAD model
    func getVADModel() throws -> MLModel {
        guard let model = sileroVAD else {
            throw ModelError.modelNotLoaded("Silero VAD")
        }
        return model
    }
    
    /// Get loaded TitaNet speaker model
    func getSpeakerModel() throws -> MLModel {
        guard let model = titanetSpeaker else {
            throw ModelError.modelNotLoaded("TitaNet Speaker")
        }
        return model
    }
    
    // MARK: - Model Lifecycle
    
    /// Unload all models to free memory
    func unloadAllModels() {
        parakeetASR = nil
        sileroVAD = nil
        titanetSpeaker = nil
        
        Task { @MainActor in
            isASRLoaded = false
            isVADLoaded = false
            isSpeakerLoaded = false
        }
        
        logger.info("All models unloaded")
    }
    
    /// Unload specific model to free memory
    func unloadModel(_ type: ModelType) {
        switch type {
        case .asr:
            parakeetASR = nil
            Task { @MainActor in isASRLoaded = false }
        case .vad:
            sileroVAD = nil
            Task { @MainActor in isVADLoaded = false }
        case .speaker:
            titanetSpeaker = nil
            Task { @MainActor in isSpeakerLoaded = false }
        }
        
        logger.info("Unloaded \(type.rawValue) model")
    }
    
    // MARK: - Model Validation
    
    /// Validate that all required models are present in bundle
    func validateModelAvailability() -> ModelAvailability {
        let asrAvailable = Bundle.main.url(forResource: "Parakeet_TDT0.6b", withExtension: "mlmodelc") != nil
        let vadAvailable = Bundle.main.url(forResource: "silero_vad_16k_coreml", withExtension: "mlmodelc") != nil
        let speakerAvailable = Bundle.main.url(forResource: "titanet_large_coreml", withExtension: "mlmodelc") != nil
        
        return ModelAvailability(
            asrAvailable: asrAvailable,
            vadAvailable: vadAvailable,
            speakerAvailable: speakerAvailable
        )
    }
}

// MARK: - Supporting Types

enum ModelType: String, CaseIterable {
    case asr = "ASR"
    case vad = "VAD"
    case speaker = "Speaker"
}

struct ModelAvailability {
    let asrAvailable: Bool
    let vadAvailable: Bool
    let speakerAvailable: Bool
    
    var allAvailable: Bool {
        asrAvailable && vadAvailable && speakerAvailable
    }
    
    var summary: String {
        let available = [
            asrAvailable ? "ASR" : nil,
            vadAvailable ? "VAD" : nil,
            speakerAvailable ? "Speaker" : nil
        ].compactMap { $0 }
        
        let missing = [
            !asrAvailable ? "ASR" : nil,
            !vadAvailable ? "VAD" : nil,
            !speakerAvailable ? "Speaker" : nil
        ].compactMap { $0 }
        
        var result = "Available: \(available.joined(separator: ", "))"
        if !missing.isEmpty {
            result += " | Missing: \(missing.joined(separator: ", "))"
        }
        return result
    }
}

enum ModelError: LocalizedError {
    case failedToLoadModels(Error)
    case asrLoadFailed(Error)
    case vadLoadFailed(Error)
    case speakerLoadFailed(Error)
    case modelNotLoaded(String)
    case modelNotAvailable(String)
    
    var errorDescription: String? {
        switch self {
        case .failedToLoadModels(let error):
            return "Failed to load CoreML models: \(error.localizedDescription)"
        case .asrLoadFailed(let error):
            return "Failed to load ASR model: \(error.localizedDescription)"
        case .vadLoadFailed(let error):
            return "Failed to load VAD model: \(error.localizedDescription)"
        case .speakerLoadFailed(let error):
            return "Failed to load speaker model: \(error.localizedDescription)"
        case .modelNotLoaded(let modelName):
            return "\(modelName) model is not loaded"
        case .modelNotAvailable(let modelName):
            return "\(modelName) model is not available in app bundle"
        }
    }
}