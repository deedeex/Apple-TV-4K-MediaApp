//
//  DiskThumbnailCache.swift
//  MediaApp
//
//  Trwały cache miniatur na dysku (Caches/ThumbnailCache) — drugi poziom
//  pod ImageCache, który jest tylko w RAM i znika przy każdym restarcie
//  aplikacji. Przy dużej bibliotece na NAS-ie odtwarzanie WSZYSTKICH miniatur
//  od zera po każdym uruchomieniu (SMB round-trip + dekodowanie
//  ImageIO/AVAssetImageGenerator dla każdego kafelka) potrafi trwać bardzo
//  długo — ten cache pozwala tego uniknąć przy kolejnych startach.
//
//  Limit twardy: 30 GB, czyszczony metodą LRU wg daty modyfikacji pliku
//  (dotykanej przy każdym odczycie) — najdawniej używane miniatury lecą
//  jako pierwsze. Żyje w katalogu Caches (nie Documents), więc system i tak
//  może go wyczyścić pod presją miejsca na dysku — dokładnie pożądane
//  zachowanie dla w pełni regenerowalnych danych.
//
//  Miniatury trzymane są jako JPEG (są już zmniejszone przez ImageIO/
//  AVAssetImageGenerator do docelowego maxPixelSize, więc nawet przy jakości
//  0.8 to niewielkie pliki) — nie oryginalne bajty zdjęcia/wideo z NAS-a.
//

import Foundation
import UIKit
import CryptoKit

actor DiskThumbnailCache {
    static let shared = DiskThumbnailCache()

    private static let maxBytes: Int64 = 30 * 1024 * 1024 * 1024 // 30 GB
    /// Po przekroczeniu limitu czyścimy DO tego poziomu (nie dokładnie do
    /// maxBytes), żeby nie odpalać ewikcji przy niemal każdym kolejnym zapisie.
    private static let targetBytesAfterEviction = Int64(Double(maxBytes) * 0.9)

    private let directory: URL
    private var totalBytes: Int64 = 0
    private var isInitialized = false

    private init() {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = cachesDir.appendingPathComponent("ThumbnailCache", isDirectory: true)
    }

    /// Odczyt POZA actorem (nonisolated + @concurrent), bez
    /// ensureInitialized():
    /// - ensureInitialized() przy pierwszym użyciu listuje i "statuje" CAŁY
    ///   katalog miniatur (dziesiątki tysięcy plików) — potrzebne tylko do
    ///   pilnowania limitu rozmiaru przy zapisie, a przy odczycie
    ///   blokowało pierwsze kafelki siatki zaraz po starcie aplikacji.
    /// - Odczyty przez actora szły jeden po drugim; kilkadziesiąt kafelków
    ///   na starcie czytało się sekwencyjnie zamiast równolegle.
    /// - preparingForDisplay() dekoduje JPEG tutaj, w tle — sam
    ///   UIImage(data:) jest leniwy i dekodował dopiero przy rysowaniu, na
    ///   głównym wątku.
    @concurrent nonisolated func image(for url: URL, variant: String = "default") async -> UIImage? {
        let path = fileURL(for: url, variant: variant)

        guard let data = FileManager.default.contents(atPath: path.path) else { return nil }
        // "Dotknięcie" pliku — najprostszy LRU bez osobnego indeksu: data
        // modyfikacji = ostatni dostęp, najstarsza leci jako pierwsza przy ewikcji.
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: path.path)
        guard let image = UIImage(data: data) else { return nil }
        return image.preparingForDisplay() ?? image
    }

    func store(_ image: UIImage, for url: URL, variant: String = "default") async {
        await ensureInitialized()
        guard let data = image.jpegData(compressionQuality: 0.8) else { return }

        let path = fileURL(for: url, variant: variant)
        let previousSize = fileSize(at: path)

        guard (try? data.write(to: path, options: .atomic)) != nil else { return }

        totalBytes += Int64(data.count) - previousSize
        if totalBytes > Self.maxBytes {
            evictLeastRecentlyUsed()
        }
    }

    // MARK: - Inicjalizacja

    private func ensureInitialized() async {
        guard !isInitialized else { return }
        isInitialized = true

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let entries = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey]
        )) ?? []

        totalBytes = entries.reduce(into: Int64(0)) { sum, url in
            sum += fileSize(at: url)
        }

        if totalBytes > Self.maxBytes {
            evictLeastRecentlyUsed()
        }
    }

    // MARK: - Ewikcja LRU

    private func evictLeastRecentlyUsed() {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        )) ?? []

        let oldestFirst = entries.sorted { lhs, rhs in
            modificationDate(at: lhs) < modificationDate(at: rhs)
        }

        for fileURL in oldestFirst {
            guard totalBytes > Self.targetBytesAfterEviction else { break }
            let size = fileSize(at: fileURL)
            if (try? FileManager.default.removeItem(at: fileURL)) != nil {
                totalBytes -= size
            }
        }
    }

    // MARK: - Pomocnicze

    private func fileSize(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    private func modificationDate(at url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate ?? .distantPast
    }

    /// Ten sam klucz co w ImageCache ("url#wariant"), tylko zhaszowany do
    /// bezpiecznej nazwy pliku (adres NAS-a bywa długi i zawiera znaki
    /// niedozwolone w nazwach plików).
    private nonisolated func fileURL(for url: URL, variant: String) -> URL {
        let key = "\(url.absoluteString)#\(variant)"
        let digest = SHA256.hash(data: Data(key.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hex).appendingPathExtension("jpg")
    }
}
