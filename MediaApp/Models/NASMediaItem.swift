//
//  NASMediaItem.swift
//  MediaApp
//

import Foundation

nonisolated enum MediaType: Codable, Equatable {
    case photo
    case video
    case livePhoto(videoURL: URL)
}

/// Codable, żeby dało się zapisać ostatni wynik skanowania na dysku
/// (MediaLibraryCache) i pokazać go natychmiast przy starcie aplikacji,
/// zamiast czekać kilkanaście sekund na świeży listing po SMB za każdym
/// razem — patrz komentarz w MediaLibraryStore.swift. `nonisolated`, bo
/// projekt kompiluje się z -default-isolation=MainActor — bez tego
/// konformancja do Codable byłaby związana z głównym aktorem i nie dałoby
/// się jej użyć z tła (patrz komentarz w MediaLibraryCache.swift).
nonisolated struct NASMediaItem: Identifiable, Codable, Equatable {
    /// Stały identyfikator = zdalny adres pliku (unikalny: zdjęcie/Live
    /// Photo ma adres zdjęcia, samodzielne wideo — adres wideo). Wcześniej
    /// było tu `let id = UUID()`, losowane przy KAŻDYM utworzeniu/odczycie —
    /// więc po każdym świeżym skanie NAS (i po wczytaniu cache'a) wszystkie
    /// pozycje dostawały nowe id, SwiftUI uznawał całą siatkę za nowe widoki
    /// i przebudowywał ją od zera (widoczne jako "przeładowanie" ekranu i
    /// utrata fokusu kilka sekund po starcie aplikacji).
    var id: URL { imageURL }
    let baseFileName: String
    /// Zdalny adres w formie smb://host/udział/ścieżka/plik — nie plik lokalny.
    let imageURL: URL
    let type: MediaType
    /// Data modyfikacji pliku z SMB (najbliższe dostępne przybliżenie „daty
    /// zrobienia" bez parsowania EXIF/metadanych wideo) — używana do
    /// grupowania biblioteki wg miesiąca. Może być nil, jeśli SMB jej nie
    /// zwróciło; takie pozycje lądują w grupie „Nieznana data".
    let captureDate: Date?
}
