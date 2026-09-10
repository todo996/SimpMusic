import SwiftUI
import ComposeApp

struct ComposeViewController: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        MainViewControllerKt.MainViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

@main
struct SimpMusicIOSApp: App {
    var body: some Scene {
        WindowGroup {
            ComposeViewController()
                .ignoresSafeArea(.keyboard)
        }
    }
}

