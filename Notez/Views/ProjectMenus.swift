import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Icon and tint choices for projects. Stored on `Project` as plain strings so
/// unknown values from a newer build just fall back to the defaults.
enum ProjectStyle {
    static let icons: [(symbol: String, name: String)] = [
        ("folder", "Folder"), ("tray", "Tray"), ("briefcase", "Briefcase"), ("house", "House"),
        ("person", "Person"), ("person.2", "People"), ("heart", "Heart"), ("star", "Star"),
        ("book", "Book"), ("graduationcap", "School"), ("lightbulb", "Idea"), ("hammer", "Hammer"),
        ("paintbrush", "Paintbrush"), ("chevron.left.forwardslash.chevron.right", "Code"),
        ("cart", "Cart"), ("dollarsign.circle", "Money"), ("airplane", "Travel"), ("leaf", "Leaf"),
        ("dumbbell", "Fitness"), ("gamecontroller", "Games"), ("music.note", "Music"), ("camera", "Camera"),
    ]

    static let colors: [(key: String, name: String, color: Color)] = [
        ("", "Default", .secondary), ("red", "Red", .red), ("orange", "Orange", .orange),
        ("yellow", "Yellow", .yellow), ("green", "Green", .green), ("mint", "Mint", .mint),
        ("teal", "Teal", .teal), ("blue", "Blue", .blue), ("indigo", "Indigo", .indigo),
        ("purple", "Purple", .purple), ("pink", "Pink", .pink), ("brown", "Brown", .brown),
        ("gray", "Gray", .gray),
    ]

    static func color(_ key: String) -> Color {
        colors.first { $0.key == key }?.color ?? .secondary
    }

    /// A symbol pre-coloured for menus. Menus draw SF Symbols as monochrome
    /// templates and ignore `foregroundStyle`, so the colour has to be baked
    /// into a non-template image.
    static func menuImage(_ symbol: String, color key: String) -> Image {
        #if os(macOS)
        let tint = key.isEmpty ? NSColor.secondaryLabelColor : NSColor(color(key))
        let config = NSImage.SymbolConfiguration(paletteColors: [tint])
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            image.isTemplate = false
            return Image(nsImage: image)
        }
        #else
        let tint = key.isEmpty ? UIColor.secondaryLabel : UIColor(color(key))
        if let image = UIImage(systemName: symbol)?.withTintColor(tint, renderingMode: .alwaysOriginal) {
            return Image(uiImage: image)
        }
        #endif
        return Image(systemName: symbol)
    }
}

/// Icon + colour pickers for a project header's context menu.
struct ProjectStyleMenu: View {
    let project: Project
    let store: NotesStore

    var body: some View {
        Picker("Icon", systemImage: "square.grid.2x2", selection: Binding(
            get: { project.icon },
            set: { store.setIcon($0, for: project) }
        )) {
            ForEach(ProjectStyle.icons, id: \.symbol) { icon in
                Label {
                    Text(icon.name)
                } icon: {
                    ProjectStyle.menuImage(icon.symbol, color: project.color)
                }
                .tag(icon.symbol)
            }
        }
        .pickerStyle(.menu)
        Picker("Color", systemImage: "paintpalette", selection: Binding(
            get: { project.color },
            set: { store.setColor($0, for: project) }
        )) {
            ForEach(ProjectStyle.colors, id: \.key) { option in
                Label {
                    Text(option.name)
                } icon: {
                    ProjectStyle.menuImage(option.key.isEmpty ? "circle" : "circle.fill", color: option.key)
                }
                .tag(option.key)
            }
        }
        .pickerStyle(.menu)
    }
}

/// "Move to Project" submenu, shared by the sidebar row and the page ⋯ menu.
struct MoveToProjectMenu: View {
    let note: Note
    let store: NotesStore
    let projects: [Project]

    var body: some View {
        if !projects.isEmpty {
            Menu("Move to Project", systemImage: "folder") {
                ForEach(projects) { project in
                    Button {
                        store.move(note, into: nil, project: project)
                    } label: {
                        Label {
                            Text(project.displayName)
                        } icon: {
                            ProjectStyle.menuImage(project.icon, color: project.color)
                        }
                    }
                    .disabled(note.parent == nil && note.project?.id == project.id)
                }
                Divider()
                Button("No Project", systemImage: "doc.text") { store.move(note, into: nil) }
                    .disabled(note.parent == nil && note.project == nil)
            }
        }
    }
}
