//
//  ImageCache.swift
//  MediaApp
//
//  Ograniczony pamięciowo cache zdekodowanych miniatur, współdzielony przez
//  zakładki Zdjęcia (SMBImageCache) i Wideo (VideoThumbnailGenerator).
//  NSCache (nie zwykły słownik!) — automatycznie zwalnia obiekty pod presją
//  pamięci, a countLimit twardo ogranicza, ile miniatur w ogóle może być
//  trzymane naraz. To jest bezpośrednia poprawka na crash OOM (Code 9),
//  gdzie poprzednio miniatury żyły bezterminowo w zwykłych tablicach.
//
//  Klucz to URL + opcjonalny „wariant" (np. rozmiar w pikselach) — to samo
//  zdjęcie bywa proszone o dwa różne rozmiary (mała miniatura w siatce,
//  duży podgląd pełnoekranowy) i te dwie wersje nie mogą się nawzajem
//  nadpisywać w cache'u.
//
//  To tylko poziom 1 (RAM, znika przy restarcie aplikacji). Poziom 2 to
//  DiskThumbnailCache — trwały cache na dysku, sprawdzany przez
//  SMBImageCache/VideoThumbnailGenerator, gdy tu jest miss.
//
//  countLimit SAM W SOBIE nie wystarczy jako jedyny limit: ten sam cache
//  trzyma zarówno małe miniatury siatki (~420px, ~0.7 MB po zdekodowaniu),
//  jak i pełnoekranowy podgląd Live Photo (AsyncImageSMB bez override —
//  maxPixelSize aż do 3840px, czyli nawet ~30–40 MB na obraz). Samo
//  podniesienie countLimit bez limitu bajtowego pozwoliłoby cache'owi urosnąć
//  do setek MB, gdyby akurat trafiła tam mieszanka dużych podglądów —
//  dokładnie ten sam rodzaj problemu co OOM Code 9 wspomniany wyżej.
//  totalCostLimit (rzeczywiste zdekodowane bajty, liczone per obraz w
//  insert()) jest więc twardym limitem pamięci NIEZALEŻNYM od countLimit —
//  NSCache ewikcjonuje wg tego, które ograniczenie zostanie przekroczone
//  pierwsze.
//

import UIKit
import os

final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    static let countLimit = 500
    static let byteLimit = 1024 * 1024 * 1024 // ~1 GB zdekodowanych bajtów

    private let cache = NSCache<NSString, UIImage>()
    private let tracker = UsageTracker()

    private init() {
        cache.countLimit = Self.countLimit
        cache.totalCostLimit = Self.byteLimit
        cache.delegate = tracker
    }

    /// Ile obrazów i bajtów jest TERAZ w cache'u — do wyświetlenia w
    /// Ustawieniach. NSCache sam tego nie udostępnia (zna tylko limity),
    /// więc liczy to UsageTracker niżej.
    var usage: (count: Int, bytes: Int) {
        tracker.usage
    }

    /// Opróżnia cały cache RAM (przycisk "Wyczyść pamięć podręczną" w
    /// Ustawieniach). Obrazy już wyświetlone na ekranie zostają — żyją w
    /// @State widoków, nie tutaj.
    func removeAll() {
        cache.removeAllObjects()
    }

    func image(for url: URL, variant: String = "default") -> UIImage? {
        cache.object(forKey: key(for: url, variant: variant))
    }

    func insert(_ image: UIImage, for url: URL, variant: String = "default") {
        let key = key(for: url, variant: variant)
        let cost = byteCost(of: image)
        // Rejestracja PRZED setObject i poza jego wywołaniem — NSCache woła
        // delegata (eviction) synchronicznie z wnętrza setObject, a lock w
        // UsageTracker nie jest reentrant.
        tracker.didInsert(image, key: key, cost: cost)
        cache.setObject(image, forKey: key, cost: cost)
    }

    /// Jawne usunięcie pojedynczego wpisu — używane przez MediaPagerView do
    /// wymuszenia okna "±4 od bieżącego zdjęcia" dla pełnoekranowego
    /// pre-ładowania (patrz komentarz w MediaPagerView.swift o
    /// prefetchedIndices). NSCache.countLimit/totalCostLimit same w sobie
    /// NIE dają takiej gwarancji — ewikcjonują wg własnej heurystyki, kiedy
    /// PRZEKROCZONY zostanie limit, a nie "dokładnie te elementy, które
    /// wypadły z okna" w dowolnym momencie poniżej limitu.
    func remove(for url: URL, variant: String = "default") {
        cache.removeObject(forKey: key(for: url, variant: variant))
    }

    /// Rzeczywisty rozmiar zdekodowanej bitmapy w pamięci (bytesPerRow *
    /// height), nie rozmiar pliku na dysku — to jest to, co faktycznie zajmuje
    /// RAM i to, wg czego NSCache ma rozliczać totalCostLimit.
    private func byteCost(of image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }

    private func key(for url: URL, variant: String) -> NSString {
        "\(url.absoluteString)#\(variant)" as NSString
    }
}

/// Licznik zawartości ImageCache. Delegat NSCache dostaje powiadomienie o
/// KAŻDYM usunięciu obiektu — przez limit, presję pamięci systemu,
/// remove(for:) i removeAll() — więc zliczanie "dodane minus usunięte" daje
/// dokładny stan. Lock, bo ImageCache jest używany równolegle z wielu
/// wątków (kafelki ładujące się jednocześnie).
private final class UsageTracker: NSObject, NSCacheDelegate, @unchecked Sendable {
    private struct Entry {
        let key: NSString
        let cost: Int
    }

    private struct State {
        var entries: [ObjectIdentifier: Entry] = [:]
        var idByKey: [NSString: ObjectIdentifier] = [:]
        var bytes = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var usage: (count: Int, bytes: Int) {
        state.withLock { ($0.entries.count, $0.bytes) }
    }

    func didInsert(_ image: UIImage, key: NSString, cost: Int) {
        let id = ObjectIdentifier(image)
        state.withLock { state in
            // Ten sam klucz z nowym obrazem — stary wpis i tak zniknie z
            // NSCache, niezależnie od tego, czy delegat dostanie za niego
            // powiadomienie.
            if let oldID = state.idByKey[key], oldID != id, let old = state.entries.removeValue(forKey: oldID) {
                state.bytes -= old.cost
            }
            if let existing = state.entries[id] {
                state.bytes -= existing.cost
            }
            state.entries[id] = Entry(key: key, cost: cost)
            state.idByKey[key] = id
            state.bytes += cost
        }
    }

    func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject obj: Any) {
        guard let image = obj as? UIImage else { return }
        let id = ObjectIdentifier(image)
        state.withLock { state in
            guard let entry = state.entries.removeValue(forKey: id) else { return }
            state.bytes -= entry.cost
            if state.idByKey[entry.key] == id {
                state.idByKey[entry.key] = nil
            }
        }
    }
}
