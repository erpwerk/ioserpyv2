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
                }
                
                Section {
                    Button("Schließen") {
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
