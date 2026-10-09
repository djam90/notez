import SwiftData

// Versioned so non-trivial model changes can migrate real data with code.
//
// Additive changes (new property with a default, new model) and removing a
// property migrate automatically, no new version needed. A rename can use
// `@Attribute(originalName:)`. Anything else, such as a type change or moving
// data between models, fails to open the store (StoreErrorView, data intact).
// For those: copy the current model classes into `NotezSchemaV1` as nested
// types, untouched. Then edit the top-level models, add `NotezSchemaV2`
// listing them, point `NotezSchema` at it and add a `.custom` stage below.

enum NotezSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Note.self, NoteBody.self, Asset.self, Project.self]
    }
}

typealias NotezSchema = NotezSchemaV1

enum NotezMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [NotezSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
