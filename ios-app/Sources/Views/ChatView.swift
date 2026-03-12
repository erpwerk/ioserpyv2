import SwiftUI
import PhotosUI

struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel()
    @State private var showingFilePicker = false
    @State private var showingImagePicker = false
    @State private var showingActionSheet = false
    @State private var showingSettings = false
    @State private var showSidebar = false
    @State private var selectedItem: PhotosPickerItem?
    
    var body: some View {
        ZStack {
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
            
            // Sidebar Overlay
            if showSidebar {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation { showSidebar = false }
                    }
                
                HStack {
                    sidebar
                        .frame(width: 280)
                        .transition(.move(edge: .leading))
                    Spacer()
                }
            }
        }
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
            Button(action: { withAnimation { showSidebar = true } }) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
            }
            
            Spacer()
            
            Text("ERPY")
                .font(.headline)
                .foregroundColor(.white)
            
            Spacer()
            
            HStack(spacing: 12) {
                Menu {
                    Picker("Modell", selection: $viewModel.selectedModel) {
                        ForEach(viewModel.models, id: \.self) { model in
                            Text(model.uppercased()).tag(model)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(viewModel.selectedModel.uppercased())
                            .font(.caption2)
                            .fontWeight(.bold)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8))
                    }
                    .foregroundColor(.blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(6)
                }

                Button(action: { showingSettings = true }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.gray)
                }
            }
        }
        .padding()
        .background(Color(white: 0.05))
    }
    
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Chat Verlauf")
                .font(.title2)
                .bold()
                .foregroundColor(.white)
                .padding(.top, 60)
            
            Button(action: {
                viewModel.clearHistory()
                withAnimation { showSidebar = false }
            }) {
                HStack {
                    Image(systemName: "plus.bubble")
                    Text("Neuer Chat")
                }
                .foregroundColor(.blue)
            }
            
            Divider().background(Color.white.opacity(0.2))
            
            ScrollView {
                // Placeholder for multiple conversations
                VStack(alignment: .leading, spacing: 15) {
                    Text("Aktueller Chat")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    if let firstMsg = viewModel.messages.first {
                        Text(firstMsg.content.prefix(30) + "...")
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .padding(10)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
            }
            
            Spacer()
        }
        .padding()
        .background(Color(white: 0.12))
        .edgesIgnoringSafeArea(.vertical)
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
