import CoreData
import Foundation
import SwiftData
import Testing
@testable import Notez

@Suite struct NoteModelTests {
    let store: TestStore
    init() throws { store = try TestStore() }

    @Test func treeHelpersFollowTheParentChain() {
        let work = store.project("Work")
        let root = store.note("Plans", project: work)
        let child = store.note("Q4", parent: root)
        let grandchild = store.note("Launch", parent: child)

        #expect(grandchild.ancestors.map(\.title) == ["Plans", "Q4"])
        #expect(root.ancestors.isEmpty)
        #expect(grandchild.rootProject?.id == work.id)
        #expect(grandchild.location == "Work / Plans / Q4")
        #expect(root.location == "Work")
        #expect(grandchild.isDescendant(of: root))
        #expect(!root.isDescendant(of: grandchild))
        #expect(!root.isDescendant(of: root))
    }

    @Test func sortedChildrenFollowSortIndex() {
        let root = store.note("Root")
        store.note("b", parent: root, sortIndex: 2)
        store.note("a", parent: root, sortIndex: 1)
        store.note("c", parent: root, sortIndex: 3)
        #expect(root.sortedChildren.map(\.title) == ["a", "b", "c"])
    }

    @Test func untitledFallbacks() {
        #expect(Note().displayTitle == "Untitled")
        #expect(Project(name: "").displayName == "Untitled Project")
    }

    @Test func previewIsOneLineAndCapped() {
        let note = Note()
        note.setPreview(from: "line one\nline two")
        #expect(note.preview == "line one line two")
        // How the editor sends nested blocks.
        note.setPreview(from: "Heading\n\n\none\n\n  two\n")
        #expect(note.preview == "Heading one two")
        note.setPreview(from: String(repeating: "x", count: 500))
        #expect(note.preview.count == 160)
    }

    @Test func deletingAPageCascadesToSubpagesBodiesAndImages() throws {
        let root = store.note("Root", text: "body")
        let child = store.note("Child", parent: root, text: "child body")
        store.note("Grandchild", parent: child)
        store.context.insert(Asset(data: Data([1, 2, 3]), mimeType: "image/png", note: child))
        try store.context.save()
        let survivor = store.note("Other", text: "kept")

        store.context.delete(root)
        try store.context.save()

        #expect(store.count(Note.self) == 1)
        #expect(store.count(NoteBody.self) == 1)
        #expect(store.count(Asset.self) == 0)
        #expect(store.context.note(survivor.id) != nil)
    }

    @Test func deletingAProjectKeepsItsPages() throws {
        let work = store.project("Work")
        let page = store.note("Plans", project: work)
        store.context.delete(work)
        try store.context.save()
        #expect(store.count(Note.self) == 1)
        #expect(page.project == nil)
    }
}

/// CLAUDE.md hard rule 5: SwiftData's CloudKit sync rejects models that break
/// these, possibly only once sync is switched on, long after the change.
@Suite struct CloudKitCompatibilityTests {
    let model: NSManagedObjectModel
    init() throws { model = try #require(NSManagedObjectModel.makeManagedObjectModel(for: NotezSchema.models)) }

    @Test func everyAttributeIsOptionalOrHasADefault() {
        for entity in model.entities {
            for (name, attribute) in entity.attributesByName {
                #expect(attribute.isOptional || attribute.defaultValue != nil, "\(entity.name ?? "?").\(name)")
            }
        }
    }

    @Test func everyRelationshipIsOptionalWithAnInverse() {
        for entity in model.entities {
            for (name, relationship) in entity.relationshipsByName {
                #expect(relationship.isOptional, "\(entity.name ?? "?").\(name) must be optional")
                #expect(relationship.inverseRelationship != nil, "\(entity.name ?? "?").\(name) needs an inverse")
            }
        }
    }

    @Test func nothingIsUnique() {
        for entity in model.entities {
            #expect(entity.uniquenessConstraints.isEmpty, "\(entity.name ?? "?") has a unique constraint")
        }
    }
}
