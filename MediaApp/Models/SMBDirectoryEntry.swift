//
//  SMBDirectoryEntry.swift
//  MediaApp
//

import Foundation

/// Pojedynczy wpis (plik lub folder) zwrócony przez SMBManager.listDirectory —
/// używany przez PathPickerView do przeglądania udziału podczas konfiguracji.
struct SMBDirectoryEntry: Identifiable, Sendable, Hashable {
    /// Pełna ścieżka względem udziału — unikalna, więc służy też jako id.
    let path: String
    let name: String
    let isDirectory: Bool

    var id: String { path }
}
