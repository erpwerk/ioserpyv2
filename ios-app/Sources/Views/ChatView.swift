import SwiftUI
import PhotosUI

struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel()
    @State private var showingFilePicker = false
    @State private var showingImagePicker = false
    @State private var showingActionSheet = false
    @State private var showingSettings = false
    @State private var selectedItem: PhotosPickerItem?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(message: message)
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) { _ in
                    if let last = viewModel.messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            // Input
            inputArea
        }
        .background(Color.black.edgesIgnoringSafeArea(.all))
        .actionSheet(isPresented: $showingActionSheet) {
            ActionSheet(title: Text("Anhang auswählen"), buttons: [
                .default(Text("Foto auswählen"), action: { showingImagePicker = true }),
                .default(Text("Datei auswählen (PDF)"), action: { showingFilePicker = true }),
                .cancel()
            ])
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(viewModel: viewModel)
        }
        .fileImporter(isPresented: $showingFilePicker, allowedContentTypes: [.pdf]) { result in
            // ... (Handle file)
        }
    }
    
    private var header: some View {
        HStack {
            Button(action: { showingSettings = true }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.gray)
            }
            
            VStack(alignment: .leading) {
                Text("ERPY Standalone")
                    .font(.headline)
                    .foregroundColor(.white)
                HStack(spacing: 4) {
                    Circle()
                        .fill(viewModel.openAIKey.isEmpty && viewModel.geminiKey.isEmpty ? Color.red : Color.green)
                        .frame(width: 8, height: 8)
                    Text(viewModel.openAIKey.isEmpty && viewModel.geminiKey.isEmpty ? "Keys missing" : "Ready")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            Spacer()
            
            Picker("Modell", selection: $viewModel.selectedModel) {
                ForEach(viewModel.models, id: \.self) { model in
                    Text(model.uppercased()).tag(model)
                }
            }
            .pickerStyle(MenuPickerStyle())
            .accentColor(.blue)
        }
        .padding()
        .background(Color(white: 0.05))
    }
    
    private var inputArea: some View {
        VStack(spacing: 0) {
            Divider().background(Color.white.opacity(0.1))
            HStack(spacing: 12) {
                Button(action: { showingActionSheet = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 20))
                        .foregroundColor(.blue)
                }

                TextField("Nachricht...", text: $viewModel.inputText)
                    .padding(12)
                    .background(Color(white: 0.1))
                    .cornerRadius(20)
                    .foregroundColor(.white)
                
                if viewModel.inputText.isEmpty || viewModel.isRecording {
                    Button(action: { viewModel.toggleRecording() }) {
                        Image(systemName: viewModel.isRecording ? "mic.circle.fill" : "mic.fill")
                            .font(.system(size: 24))
                            .foregroundColor(viewModel.isRecording ? .red : .blue)
                            .scaleEffect(viewModel.isRecording ? 1.2 : 1.0)
                            .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: viewModel.isRecording)
                    }
                } else {
                    Button(action: { viewModel.sendMessage() }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.blue)
                    }
                }
            }
            .padding()
            .background(Color(white: 0.05))
        }
    }
}

struct MessageBubble: View {
    let message: Message
    
    var body: some View {
        HStack {
            if message.role == "user" { Spacer() }
            
            VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 8) {
                if let imageUrl = message.imageUrl, let url = URL(string: imageUrl) {
                    AsyncImage(url: url) { image in
                        image.resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 250)
                            .cornerRadius(12)
                    } placeholder: {
                        ProgressView().frame(width: 250, height: 250)
                    }
                }
                
                if !message.content.isEmpty {
                    Text(message.content)
                        .padding(12)
                        .background(message.role == "user" ? Color.blue : Color(white: 0.15))
                        .foregroundColor(.white)
                        .cornerRadius(16)
                }
            }
            
            if message.role == "assistant" { Spacer() }
        }
    }
}
