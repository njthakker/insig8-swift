import SwiftUI
import Combine

struct TranslationWidgetView: View {
    @StateObject private var translationStore = TranslationStore()
    @EnvironmentObject var appStore: AppStore
    @State private var targetLanguage = "es" // Spanish by default
    
    var body: some View {
        VStack(spacing: 20) {
            // Language selector
            HStack {
                LanguagePicker(
                    title: "From",
                    selection: $translationStore.sourceLanguage,
                    languages: TranslationStore.languages
                )
                
                Button(action: swapLanguages) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                
                LanguagePicker(
                    title: "To",
                    selection: $translationStore.targetLanguage,
                    languages: TranslationStore.languages
                )
            }
            .padding()
            
            Divider()
            
            // Translation content
            HSplitView {
                // Source text
                VStack(alignment: .leading) {
                    Text("Original")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextEditor(text: $appStore.searchQuery)
                        .font(.body)
                        .onChange(of: appStore.searchQuery) { oldValue, newValue in
                            translationStore.translate(text: newValue)
                        }
                }
                .padding()
                
                // Translated text
                VStack(alignment: .leading) {
                    Text("Translation")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if translationStore.isTranslating {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        TextEditor(text: .constant(translationStore.translatedText))
                            .font(.body)
                    }
                }
                .padding()
            }
        }
    }
    
    private func swapLanguages() {
        let temp = translationStore.sourceLanguage
        translationStore.sourceLanguage = translationStore.targetLanguage
        translationStore.targetLanguage = temp
        
        // Swap texts if there's a translation
        if !translationStore.translatedText.isEmpty {
            appStore.searchQuery = translationStore.translatedText
        }
    }
}

struct LanguagePicker: View {
    let title: String
    @Binding var selection: String
    let languages: [(code: String, name: String)]
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Picker("", selection: $selection) {
                ForEach(languages, id: \.code) { language in
                    Text(language.name).tag(language.code)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 150)
        }
    }
}

// TranslationStore implementation
@MainActor
class TranslationStore: ObservableObject {
    @Published var sourceLanguage = "auto" // Auto-detect
    @Published var targetLanguage = "en"
    @Published var translatedText = ""
    @Published var isTranslating = false
    
    static let languages: [(code: String, name: String)] = [
        ("auto", "Auto-detect"),
        ("en", "English"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("it", "Italian"),
        ("pt", "Portuguese"),
        ("ru", "Russian"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("zh", "Chinese"),
        ("ar", "Arabic"),
        ("hi", "Hindi")
    ]
    
    private var translationTask: Task<Void, Never>?
    
    func translate(text: String) {
        // Cancel previous task
        translationTask?.cancel()
        
        guard !text.isEmpty else {
            translatedText = ""
            return
        }
        
        isTranslating = true
        
        translationTask = Task {
            do {
                // Simulate API call - replace with actual translation API
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
                
                if !Task.isCancelled {
                    // Placeholder translation - implement actual API call
                    self.translatedText = "[Translation of: \(text)]"
                    self.isTranslating = false
                }
            } catch {
                self.isTranslating = false
            }
        }
    }
}