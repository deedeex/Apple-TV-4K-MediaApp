//
//  SMBVideoCache.swift
//  MediaApp
//
//  AVPlayer/AVAssetImageGenerator nie potrafią czytać smb:// bezpośrednio,
//  więc klip trzeba najpierw ściągnąć do lokalnego pliku tymczasowego.
//  Obecnie używane już TYLKO dla krótkich klipów Live Photo — zwykłe wideo
//  (VideoPlaybackView, AllMediaPagerView) i miniatury wideo idą
//  strumieniowo przez SMBStreamingAssetLoader, bez pobierania całego pliku. Pobieranie idzie strumieniowo na dysk
//  (SMBManager.downloadFile — AMSMB2 downloadItem, porcje ~1MiB) — NIE
//  ładujemy całego pliku do pamięci jako Data. Pojedynczy plik wideo to
//  nawet kilka GB; robienie tego jako Data (a tym bardziej kilka takich
//  pobrań naraz przy szybkim przewijaniu galerii) gwarantowało crash OOM.
//
//  inFlight deduplikuje równoległe żądania tego samego URL-a — bez tego
//  kliknięcie Play na pliku, którego miniatura akurat się generuje w tle,
//  odpalało DRUGIE, całkowicie zbędne pobranie tego samego pliku.
//
//  Katalog tymczasowy nie ma żadnego wymuszonego przez system limitu ani
//  gwarancji sprzątania w trakcie działania appki (patrz komentarz przy
//  maxCachedFiles) — dlatego ewikcja LRU poniżej, tak samo jak w
//  DiskThumbnailCache/ImageCache dla zdjęć.
//

import Foundation

actor SMBVideoCache {
    static let shared = SMBVideoCache()

    /// Maks. liczba jednocześnie trzymanych na dysku plików wideo. Trzyma
    /// "Odtwórz ponownie" (VideoPlaybackView.replay()) i pre-ładowanie
    /// następnego wideo (prefetchNextVideo()) działające bez ponownego
    /// pobierania z NAS-a — bez ręcznego, kruchego liczenia W VideoPlaybackView,
    /// KIEDY dokładnie dany plik przestaje być potrzebny. Ta wcześniejsza
    /// wersja (jawne removeLocalFile() wołane przez VideoPlaybackView przy
    /// zmianie wideo) miała realny wyścig: jeśli użytkownik wracał do
    /// poprzedniego wideo, zanim pre-ładowanie "następnego" zdążyło się
    /// zapisać na dysk, ten plik zostawał osierocony (próba usunięcia trafiała
    /// w nieistniejący jeszcze wpis). Zwykły, odporny na wyścigi limit
    /// liczbowy z ewikcją najdawniej UŻYWANEGO (nie: najdawniej pobranego —
    /// patrz touch()) eliminuje ten problem strukturalnie, bez pilnowania
    /// dokładnego momentu "już na pewno nieużywane".
    private static let maxCachedFiles = 3

    private var localURLs: [URL: URL] = [:]
    /// Kolejność użycia — na KOŃCU najświeższe. Wyłącznie do ewikcji (patrz
    /// touch/evictIfNeeded); do samego odczytu służy localURLs.
    private var usageOrder: [URL] = []
    private var inFlight: [URL: Task<URL, Error>] = [:]

    func localFileURL(for remoteURL: URL) async throws -> URL {
        if let cached = localURLs[remoteURL], FileManager.default.fileExists(atPath: cached.path) {
            touch(remoteURL)
            return cached
        }

        if let existing = inFlight[remoteURL] {
            return try await existing.value
        }

        let task = Task<URL, Error> {
            let ext = remoteURL.pathExtension.isEmpty ? "mov" : remoteURL.pathExtension
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext)

            try await SMBManager.shared.downloadFile(at: remoteURL, to: destination)
            return destination
        }
        inFlight[remoteURL] = task
        defer { inFlight[remoteURL] = nil }

        let destination = try await task.value
        localURLs[remoteURL] = destination
        touch(remoteURL)
        evictIfNeeded()
        return destination
    }

    /// Przesuwa remoteURL na koniec kolejki użycia (najświeższe) — zarówno
    /// przy nowym pobraniu, jak i przy trafieniu w już pobrany plik (np.
    /// powrót do wcześniej oglądanego wideo), żeby "ostatnio używane"
    /// naprawdę znaczyło "ostatnio używane", a nie tylko "ostatnio pobrane".
    private func touch(_ remoteURL: URL) {
        usageOrder.removeAll { $0 == remoteURL }
        usageOrder.append(remoteURL)
    }

    /// Usuwa najdawniej używane pliki ponad maxCachedFiles — wołane po
    /// każdym nowym pobraniu, więc kolejka nigdy nie rośnie bez ograniczeń.
    private func evictIfNeeded() {
        while usageOrder.count > Self.maxCachedFiles {
            let oldest = usageOrder.removeFirst()
            if let localURL = localURLs.removeValue(forKey: oldest) {
                try? FileManager.default.removeItem(at: localURL)
            }
        }
    }
}
