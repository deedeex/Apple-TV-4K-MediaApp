//
//  SMBImageCache.swift
//  MediaApp
//
//  Pobiera z NAS-a dane HEIC/JPEG i dekoduje miniatury (ImageIO,
//  CGImageSourceCreateThumbnailAtIndex zamiast pełnego UIImage(data:) —
//  pojedyncze zdjęcie z iPhone'a to nawet kilkanaście megapikseli, a
//  dekodowanie w pełnej rozdzielczości dla małego kafelka siatki zacinałoby
//  przewijanie dużej, rekurencyjnie zebranej galerii).
//
//  Obie warstwy cache'u to NSCache (ograniczone, samo-czyszczące się pod
//  presją pamięci), nie zwykłe słowniki — ten sam wzorzec co w
//  VideoThumbnailGenerator, żeby duża galeria nie rosła w pamięci bez
//  ograniczeń tak jak wcześniej zakładka Wideo (crash OOM Code 9).
//  Zdekodowane miniatury idą do współdzielonego ImageCache; surowe,
//  pobrane bajty (cały plik) mają własny, mniejszy NSCache — to znacznie
//  cięższe obiekty, trzymane głównie po to, żeby nie ściągać tego samego
//  zdjęcia dwa razy, gdy najpierw widać je w siatce, a potem na pełnym ekranie.
//

import Foundation
import ImageIO
import UIKit

actor SMBImageCache {
    static let shared = SMBImageCache()

    private let rawDataCache: NSCache<NSURL, NSData> = {
        let cache = NSCache<NSURL, NSData>()
        cache.countLimit = 20
        return cache
    }()

    private var inFlight: [URL: Task<Data, Error>] = [:]

    func data(for url: URL) async throws -> Data {
        if let cached = rawDataCache.object(forKey: url as NSURL) {
            return cached as Data
        }

        if let existing = inFlight[url] {
            return try await existing.value
        }

        let task = Task<Data, Error> {
            try await SMBManager.shared.downloadData(at: url)
        }
        inFlight[url] = task
        defer { inFlight[url] = nil }

        let data = try await task.value
        rawDataCache.setObject(data as NSData, forKey: url as NSURL)
        return data
    }

    /// Klucz wariantu w ImageCache/DiskThumbnailCache dla danego maxPixelSize
    /// — `nonisolated` i `static`, żeby wywołujący (np. MediaPagerView przy
    /// jawnym ImageCache.remove(for:variant:) poza oknem pre-ładowania) mógł
    /// policzyć DOKŁADNIE ten sam klucz bez duplikowania tej formuły.
    nonisolated static func variant(for maxPixelSize: CGFloat) -> String {
        String(Int(maxPixelSize.rounded()))
    }

    /// Zwraca zdekodowaną, zmniejszoną do `maxPixelSize` miniaturę — pobiera
    /// i cachuje surowe dane tak samo jak `data(for:)`, ale dekoduje je od
    /// razu w docelowym rozmiarze, bez trzymania pełnej bitmapy w pamięci.
    func thumbnail(for url: URL, maxPixelSize: CGFloat) async throws -> UIImage {
        let pixelSize = Int(maxPixelSize.rounded())
        let variant = Self.variant(for: maxPixelSize)

        if let cached = ImageCache.shared.image(for: url, variant: variant) {
            return cached
        }

        // Drugi poziom — trwały cache na dysku (przeżywa restart aplikacji),
        // sprawdzany PRZED sięgnięciem po sieć.
        if let onDisk = await DiskThumbnailCache.shared.image(for: url, variant: variant) {
            ImageCache.shared.insert(onDisk, for: url, variant: variant)
            return onDisk
        }

        let imageData = try await data(for: url)
        let image = try Self.makeThumbnail(from: imageData, maxPixelSize: pixelSize)
        ImageCache.shared.insert(image, for: url, variant: variant)
        await DiskThumbnailCache.shared.store(image, for: url, variant: variant)
        return image
    }

    private static func makeThumbnail(from data: Data, maxPixelSize: Int) throws -> UIImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw SMBError.thumbnailDecodingFailed
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]

        guard let cgThumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw SMBError.thumbnailDecodingFailed
        }

        return UIImage(cgImage: stripAlphaIfPresent(cgThumbnail))
    }

    /// Część zdjęć z iPhone'a (HEIC) niesie kanał alfa mimo w pełni
    /// nieprzezroczystej treści — CGImageSourceCreateThumbnailAtIndex
    /// zachowuje go w wygenerowanej miniaturze bez pytania. Przy zapisie do
    /// DiskThumbnailCache jako JPEG (który w ogóle nie wspiera alfy)
    /// ImageIO loguje ostrzeżenie o niepotrzebnym PODWOJENIU pamięci przy
    /// dekodowaniu takiego obrazu — przerysowanie raz, tutaj, do kontekstu
    /// BEZ kanału alfa eliminuje to u źródła. Warunkowe (sprawdzenie
    /// alphaInfo) — bez tego każde zdjęcie, nawet już opaque, płaciłoby
    /// niepotrzebnie kosztem dodatkowego przerysowania pełnowymiarowej
    /// (do 3840px) bitmapy.
    private static func stripAlphaIfPresent(_ cgImage: CGImage) -> CGImage {
        switch cgImage.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return cgImage
        default:
            break
        }

        let width = cgImage.width
        let height = cgImage.height
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return cgImage }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? cgImage
    }
}
