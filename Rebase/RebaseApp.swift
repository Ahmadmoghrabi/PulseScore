import SwiftUI

// `@main` tells Swift "this is where the program starts" — like `public static void main`
// in Java, but attached to a type instead of a free function.
//
// `App` is a protocol (think: a Java interface, but it can also carry default behavior).
// Conforming to it just means providing one computed property, `body`, that describes
// the app's scenes. SwiftUI reads that description and builds/manages the actual
// UIKit windows for us — we never touch a window or view controller directly.
@main
struct RebaseApp: App {
    var body: some Scene {
        // A `WindowGroup` is a scene that manages one window containing our root view.
        // On iPhone there's only ever one window, but the same code scales to iPad/Mac.
        WindowGroup {
            ContentView()
        }
    }
}
