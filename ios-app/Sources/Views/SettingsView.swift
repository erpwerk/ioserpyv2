import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("API-Keys")) {
                    SecureField("OpenAI API Key", text: $viewModel.openAIKey)
                    SecureField("Google Gemini API Key", text: $viewModel.geminiKey)
                    SecureField("Search API Key (Tavily/Serper)", text: $viewModel.searchKey)
                }
                
                Section {
                    Button("Chat-Verlauf löschen", role: .destructive) {
                        viewModel.clearHistory()
                        dismiss()
                    }
                }
                
                Section {
                    Button("Fertig") {
                        dismiss()
                    }
                    .foregroundColor(.blue)
                }
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
