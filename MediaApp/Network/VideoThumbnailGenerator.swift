//
//  VideoThumbnailGenerator.swift
//  MediaApp
//
//  Asynchronicznie generuje miniaturę (pojedynczą klatkę) dla pliku wideo
//  z NAS-a przez AVAssetImageGenerator. Zamiast ściągać cały plik (nawet
//  ~1GB) przez SMBVideoCache tylko po to, żeby wyciągnąć jedną klatkę,
//  korzysta z SMBStreamingAssetLoader — AVFoundation samo, przez swój
//  wbudowany demuxer MP4/MOV, prosi tylko o te zakresy bajtów, których
//  faktycznie potrzebuje (nagłówek/moov, potem bajty klatki w okolicy 1.
//  sekundy). Realistycznie to kilkaset KB–kilka MB transferu, nie cały plik.
//  Dotyczy formatów natywnie wspieranych przez AVFoundation (MP4/MOV/HEVC/
//  M4V) — MKV/AVI i tak nie są dekodowalne przez AVAssetImageGenerator na
//  tvOS, streaming tego nie zmienia, po prostu szybciej zawiedzie.
//
//  Wynik trafia do ImageCache (NSCache, ograniczony countLimit) zamiast
//  zwykłego słownika — poprzednia wersja trzymała wszystkie wygenerowane
//  miniatury bezterminowo, co przy skanowaniu całej biblioteki wideo od
//  razu powodowało crash OOM (Code 9).
//
//  maxConcurrent ogranicza, ile generowań może się dziać naraz. Ten actor
//  jest reentrant na punktach await — bez tego limitu szybkie przewinięcie
//  całej galerii wideo (zanim miniatury zdążą się załadować) odpalało
//  dziesiątki równoległych operacji jednocześnie.
//

import Foundation
import AVFoundation
import UIKit

actor VideoThumbnailGenerator {
    static let shared = VideoThumbnailGenerator()

    private static let maxPixelSize: CGFloat = 400
    private static let maxConcurrent = 2

    private var inFlight: [URL: Task<UIImage, Error>] = [:]
    private var runningCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func thumbnail(for videoURL: URL) async throws -> UIImage {
        if let cached = ImageCache.shared.image(for: videoURL) { return cached }

        // Drugi poziom — trwały cache na dysku (przeżywa restart aplikacji),
        // sprawdzany PRZED wygenerowaniem klatki z NAS-a.
        if let onDisk = await DiskThumbnailCache.shared.image(for: videoURL) {
            ImageCache.shared.insert(onDisk, for: videoURL)
            return onDisk
        }

        if let existing = inFlight[videoURL] {
            return try await existing.value
        }

        // Slot czeka się WEWNĄTRZ Taska (nie tutaj) — gdyby await na slot
        // był przed wstawieniem do inFlight, dwa równoległe żądania tego
        // samego URL-a mogłyby oba przejść przez pusty inFlight, zanim
        // pierwsze zdąży się wpisać (reentrancy actora na punkcie await),
        // i deduplikacja by nie zadziałała. Tu między sprawdzeniem a
        // wstawieniem nie ma żadnego await, więc to bezpieczne.
        let task = Task<UIImage, Error> {
            await self.acquireSlot()
            defer { Task { await self.releaseSlot() } }

            let relativePath = SMBManager.shared.relativePath(for: videoURL)
            return try await Self.generateFrame(relativePath: relativePath, fileExtension: videoURL.pathExtension)
        }
        inFlight[videoURL] = task
        defer { inFlight[videoURL] = nil }

        let image = try await task.value
        ImageCache.shared.insert(image, for: videoURL)
        await DiskThumbnailCache.shared.store(image, for: videoURL)
        return image
    }

    // MARK: - Limit równoległości

    private func acquireSlot() async {
        if runningCount < Self.maxConcurrent {
            runningCount += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
        runningCount += 1
    }

    private func releaseSlot() {
        runningCount -= 1
        if !waiters.isEmpty {
            waiters.removeFirst().resume()
        }
    }

    // MARK: - Dekodowanie klatki

    private static func generateFrame(relativePath: String, fileExtension: String) async throws -> UIImage {
        let (asset, loader) = SMBStreamingAssetLoader.makeAsset(relativePath: relativePath, fileExtension: fileExtension)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)

        do {
            let (cgImage, _) = try await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600))
            await loader.cancelAll()
            return UIImage(cgImage: cgImage)
        } catch {
            await loader.cancelAll()
            throw error
        }
    }
}
