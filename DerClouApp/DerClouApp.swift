import SwiftUI
import HeistCore
import HeistKit

@main
struct DerClouApp: App {
    var body: some Scene {
        WindowGroup {
            // Temporary: the camera experiment runs in place of the game.
            if ProcessInfo.processInfo.environment["CAMLAB"] != nil {
                LabGallery()
            } else {
                GameScreen()
            }
        }
    }
}
