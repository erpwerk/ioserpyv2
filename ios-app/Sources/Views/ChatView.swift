import SwiftUI

struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel()
    
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
    }
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("ERPY V2")
                    .font(.headline)
                    .foregroundColor(.white)
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("Online")
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
                Button(action: { /* File Picker */ }) {
                    Image(systemName: "plus")
                        .font(.system(size: 20))
                        .foregroundColor(.blue)
                }

                TextField("Nachricht...", text: $viewModel.inputText)
                    .padding(12)
                    .background(Color(white: 0.1))
                    .cornerRadius(20)
                    .foregroundColor(.white)
                
                if viewModel.inputText.isEmpty {
                    Button(action: { viewModel.startSpeechRecognition() }) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.blue)
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
            
            Text(message.content)
                .padding(12)
                .background(message.role == "user" ? Color.blue : Color(white: 0.15))
                .foregroundColor(.white)
                .cornerRadius(16)
            
            if message.role == "assistant" { Spacer() }
        }
    }
}
