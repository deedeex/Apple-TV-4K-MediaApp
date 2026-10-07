//
//  MediaLibraryCache.swift
//  MediaApp
//
//  Trwały (na dysku, nie tylko w pamięci) cache OSTATNIEGO WYNIKU skanowania
//  NAS-a — nie miniatur, te mają własny cache (ImageCache/DiskThumbnailCache).
//  fetchMediaLibrary() to zawsze pełny, rekurencyjny listing katalogu po SMB
//  (przy ~75 tys. plików realnie kilkanaście sekund) — bez tego cache'a
//  aplikacja pokazuje ten sam komunikat "Skanowanie NAS…" przy KAŻDYM
//  starcie, nawet jeśli biblioteka się nie zmieniła. Dzięki temu plikowi
//  MediaLibraryStore może pokazać poprzednio znaną listę natychmiast, a
//  świeży skan (i tak zawsze wykonywany zaraz potem w tle) tylko dopisuje/
//  koryguje dane, gdy już przyjdzie — patrz MediaLibraryStore.load().
//
//  Projekt kompiluje się z -default-isolation=MainActor (patrz build
//  settings), więc bez jawnego `nonisolated` te funkcje wołane przez
//  `await` z MediaLibraryStore i tak wykonałyby się NA GŁÓWNYM aktorze —
//  kodowanie/dekodowanie kilkudziesięciu tysięcy pozycji JSON-a blokowałoby
//  UI dokładnie tak samo, jak wcześniejszy skan po SMB. `nonisolated`
//  zrzuca je na globalny executor w tle.
//

import Foundation

enum MediaLibraryCache {
    private nonisolated static var fileURL: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("media-library-cache.json")
    }

    // @concurrent — przy NonisolatedNonsendingByDefault samo
    // `nonisolated async` wykonuje się na aktorze WOŁAJĄCEGO (tu: głównym),
    // więc dekodowanie JSON-a z ~75 tys. pozycji blokowało UI.
    @concurrent nonisolated static func load() async -> MediaLibrary? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(MediaLibrary.self, from: data)
    }

    @concurrent nonisolated static func save(_ library: MediaLibrary) async {
        guard let data = try? JSONEncoder().encode(library) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
