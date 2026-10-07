//
//  MediaLibrary.swift
//  MediaApp
//

import Foundation

/// Wynik jednego skanowania NAS-a rozdzielony na dwie zakładki: `photos`
/// (zdjęcia, w tym Live Photo z powiązanym wideo) i `videos` (samodzielne
/// pliki wideo, bez pary zdjęciowej). Wideo będące częścią Live Photo
/// NIGDY nie trafia do `videos` — patrz SMBManager.fetchMediaLibrary.
nonisolated struct MediaLibrary: Sendable, Codable {
    var photos: [NASMediaItem]
    var videos: [NASMediaItem]
}
