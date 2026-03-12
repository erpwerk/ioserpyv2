import SwiftUI

struct ContentView: View {
    let targetURL = URL(string: "https://stevenpetersen.de/agent.html")!
    
    var body: some View {
        WebView(url: targetURL)
            .edgesIgnoringSafeArea(.all)
    }
}
