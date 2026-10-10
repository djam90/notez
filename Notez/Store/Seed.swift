import Foundation
import SwiftData

enum Seed {
    private static let key = "seed.welcome.v1"

    /// Creates a welcome page on first launch. Returns it if created.
    @discardableResult
    static func welcomeIfNeeded(in context: ModelContext, defaults: UserDefaults = AppLaunch.defaults) -> Note? {
        guard !defaults.bool(forKey: key) else { return nil }
        defaults.set(true, forKey: key)
        guard (try? context.fetchCount(FetchDescriptor<Note>())) == 0 else { return nil }

        let welcome = Note(title: "Welcome to Notez")
        welcome.icon = "👋"
        welcome.body = NoteBody(markdown: welcomeMarkdown)
        context.insert(welcome)

        let child = Note(title: "Sub-pages live here", parent: welcome)
        child.body = NoteBody(markdown: "Any page can hold other pages. Drag pages in the sidebar to re-nest them.")
        context.insert(child)

        try? context.save()
        return welcome
    }

    private static let welcomeMarkdown = """
    Notez is for dumping thoughts fast. Type `/` for blocks, or use markdown shortcuts as you type.

    ## Shortcuts

    | Action | Mac / iPad keyboard |
    | --- | --- |
    | New page | ⌘N |
    | New sub-page | ⌘⇧N |
    | Jump to any page | ⌘K |
    | Insert image | ⌘⇧I or paste / drop |
    | Copy page as Markdown | ⌘⌥C |

    ## Try it

    - [x] Open Notez
    - [ ] Paste a screenshot
    - [ ] Type `/table` to add a table

    > Pasting markdown from anywhere converts it into rich text.
    """
}
