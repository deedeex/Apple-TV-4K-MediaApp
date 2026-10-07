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

final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 500
        cache.totalCostLimit = 1024 * 1024 * 1024 // ~1 GB zdekodowanych bajtów
    }

    func image(for url: URL, variant: String = "default") -> UIImage? {
        cache.object(forKey: key(for: url, variant: variant))
    }

    func insert(_ image: UIImage, for url: URL, variant: String = "default") {
        cache.setObject(image, forKey: key(for: url, variant: variant), cost: byteCost(of: image))
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
