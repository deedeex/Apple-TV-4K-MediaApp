//
//  SMBStreamingAssetLoader.swift
//  MediaApp
//
//  Karmi AVFoundation danymi bezpośrednio z SMB na żądanie — tylko te
//  zakresy bajtów, o które faktycznie poprosi demuxer AVFoundation (np.
//  nagłówek/moov atom, potem konkretne bajty klatki w okolicy 1. sekundy) —
//  zamiast ściągać cały plik z góry. Realistycznie kilkaset KB–kilka MB
//  transferu zamiast całego pliku wideo (nawet ~1GB).
//
//  Wątkowość: AVAssetResourceLoader trzyma delegata WYŁĄCZNIE słabo (weak)
//  — wywołujący (VideoThumbnailGenerator) musi trzymać silną referencję do
//  SMBStreamingAssetLoader przez cały czas życia assetu, inaczej ładowanie
//  po cichu się nie powiedzie. Callbacki delegata przychodzą synchronicznie
//  na dedykowanej kolejce GCD, ale same NIC nie blokują — od razu zwracają
//  się i oddają robotę do wewnętrznego `actor Coordinator` przez Task{}.
//  Cała mutowalna logika (cache rozmiaru pliku, lista aktywnych zadań) żyje
//  WYŁĄCZNIE w tym actorze — dzięki temu jest bezpieczna dla współbieżnego
//  dostępu bez ręcznych locków, a co ważniejsze: nigdzie w tym łańcuchu nie
//  ma .sync ani semafora czekającego na actor z jego własnej kolejki, więc
//  nie ma ryzyka zakleszczenia. Zakończone/anulowane zadania są sprzątane
//  z activeTasks od razu (nie tylko przy cancelAll), więc słownik nie
//  rośnie bez ograniczeń w trakcie dłuższej sesji ładowania.
//

import Foundation
import AVFoundation
import Combine
import UniformTypeIdentifiers

final class SMBStreamingAssetLoader: NSObject, AVAssetResourceLoaderDelegate {
    private let coordinator: Coordinator

    /// Domyślny rozmiar porcji — dla miniatur wideo (demuxer prosi o
    /// niewielkie, rozrzucone zakresy: nagłówek, okolice 1. sekundy).
    static let defaultChunkSize: Int64 = 512 * 1024
    /// Porcja przy odtwarzaniu — AVPlayer czyta plik sekwencyjnie i dużo
    /// (wideo 4K60 HDR z iPhone'a to ~10 MB/s), a każda porcja to osobne
    /// żądanie SMB przez wspólną bramkę I/O, więc większe porcje = mniej
    /// narzutu na żądanie i większy zapas przepustowości.
    static let playbackChunkSize: Int64 = 2 * 1024 * 1024

    private init(relativePath: String, fileExtension: String, chunkSize: Int64) {
        self.coordinator = Coordinator(relativePath: relativePath, fileExtension: fileExtension, chunkSize: chunkSize)
    }

    /// Odtwarzacz wideo czytający plik z NAS-a NA BIEŻĄCO (zakresami bajtów,
    /// w miarę odtwarzania), zamiast najpierw ściągać cały plik
    /// (SMBVideoCache) — duże wideo 4K startuje po ~sekundzie zamiast po
    /// kilku sekundach pobierania kilkuset MB. Używane przez
    /// VideoPlaybackView i AllMediaPagerView (Live Photo nadal przez
    /// SMBVideoCache — to krótkie klipy).
    ///
    /// Wywołujący MUSI trzymać zwrócony loader przez cały czas życia
    /// odtwarzacza (patrz makeAsset) i wołać na nim cancelAll() przy
    /// zmianie wideo/zamknięciu, żeby nie zostawić transferów SMB w tle.
    static func makePlayer(for remoteURL: URL) -> (AVPlayer, SMBStreamingAssetLoader) {
        let (asset, loader) = makeAsset(
            relativePath: SMBManager.shared.relativePath(for: remoteURL),
            fileExtension: remoteURL.pathExtension,
            chunkSize: playbackChunkSize
        )
        return (AVPlayer(playerItem: AVPlayerItem(asset: asset)), loader)
    }

    /// Czeka, aż element odtwarzacza przejdzie w stan .failed (np. NAS
    /// przestał odpowiadać w trakcie doczytywania) i zwraca komunikat
    /// błędu. Przy pobieraniu całego pliku z góry błąd SMB wychodził z
    /// try/await przed utworzeniem odtwarzacza — przy strumieniowaniu
    /// pojawia się dopiero tutaj. Kończy się nil po anulowaniu zadania.
    static func failureMessage(of item: AVPlayerItem) async -> String? {
        for await status in item.publisher(for: \.status).values where status == .failed {
            return item.error?.localizedDescription ?? "Nie udało się odtworzyć wideo z serwera NAS."
        }
        return nil
    }

    /// Buduje AVURLAsset podpięty pod ten delegat. WYWOŁUJĄCY musi trzymać
    /// silną referencję do zwróconego loadera (drugi element krotki) przez
    /// cały czas używania assetu — AVAssetResourceLoader nie robi tego za nas.
    static func makeAsset(
        relativePath: String,
        fileExtension: String,
        chunkSize: Int64 = defaultChunkSize
    ) -> (AVURLAsset, SMBStreamingAssetLoader) {
        // Zmyślony, niestandardowy schemat — smb:// samo w sobie nie jest
        // niczym, co AVFoundation umiałoby załadować natywnie, ale to i tak
        // musi być schemat spoza standardowych (http/https/file), żeby
        // AVFoundation w ogóle oddało kontrolę delegatowi zamiast próbować
        // (i od razu failować) własnego ładowania. Sama ścieżka do pliku na
        // SMB żyje w Coordinatorze, nie w tym URL-u.
        var components = URLComponents()
        components.scheme = "smbstream"
        components.host = "local"
        components.path = "/" + UUID().uuidString

        let loader = SMBStreamingAssetLoader(relativePath: relativePath, fileExtension: fileExtension, chunkSize: chunkSize)
        let asset = AVURLAsset(url: components.url!)
        let queue = DispatchQueue(label: "pl.czajkowski.MediaApp.smbstream")
        asset.resourceLoader.setDelegate(loader, queue: queue)
        return (asset, loader)
    }

    /// Odwołuje wszystkie jeszcze trwające żądania. Wołane przez
    /// VideoThumbnailGenerator, gdy generowanie klatki się kończy (sukcesem
    /// albo błędem) — żeby nie zostawić sierocych transferów SMB w tle po
    /// tym, jak przestały być komukolwiek potrzebne.
    func cancelAll() async {
        await coordinator.cancelAll()
    }

    // MARK: - AVAssetResourceLoaderDelegate (wywoływane na kolejce GCD z setDelegate)

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        Task { await coordinator.handle(loadingRequest) }
        return true
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
        Task { await coordinator.cancelRequest(loadingRequest) }
    }

    // MARK: - Coordinator (cała mutowalna logika, izolowana w actorze)

    private actor Coordinator {
        private let relativePath: String
        private let contentType: String
        private var cachedContentLength: Int64?
        private var activeTasks: [ObjectIdentifier: Task<Void, Never>] = [:]

        private let chunkSize: Int64

        init(relativePath: String, fileExtension: String, chunkSize: Int64) {
            self.chunkSize = chunkSize
            self.relativePath = relativePath
            self.contentType = UTType(filenameExtension: fileExtension)?.identifier ?? "public.movie"
        }

        func handle(_ loadingRequest: AVAssetResourceLoadingRequest) {
            let key = ObjectIdentifier(loadingRequest)
            let task = Task { [weak self] in
                await self?.process(loadingRequest)
                await self?.clearTask(for: key)
            }
            activeTasks[key] = task
        }

        func cancelRequest(_ loadingRequest: AVAssetResourceLoadingRequest) {
            let key = ObjectIdentifier(loadingRequest)
            activeTasks[key]?.cancel()
            activeTasks[key] = nil
        }

        func cancelAll() {
            for task in activeTasks.values { task.cancel() }
            activeTasks.removeAll()
        }

        private func clearTask(for key: ObjectIdentifier) {
            activeTasks[key] = nil
        }

        private func process(_ loadingRequest: AVAssetResourceLoadingRequest) async {
            guard !Task.isCancelled, !loadingRequest.isCancelled else { return }

            do {
                if let infoRequest = loadingRequest.contentInformationRequest {
                    let size = try await resolvedContentLength()
                    infoRequest.contentType = contentType
                    infoRequest.contentLength = size
                    infoRequest.isByteRangeAccessSupported = true
                }

                if let dataRequest = loadingRequest.dataRequest {
                    try await respond(to: dataRequest, parent: loadingRequest)
                }

                guard !loadingRequest.isCancelled else { return }
                loadingRequest.finishLoading()
            } catch {
                guard !loadingRequest.isCancelled else { return }
                loadingRequest.finishLoading(with: error)
            }
        }

        private func resolvedContentLength() async throws -> Int64 {
            if let cachedContentLength { return cachedContentLength }
            guard let size = try await SMBManager.shared.fileSize(atRelativePath: relativePath) else {
                throw SMBError.invalidRemotePath
            }
            cachedContentLength = size
            return size
        }

        private func respond(
            to dataRequest: AVAssetResourceLoadingDataRequest,
            parent loadingRequest: AVAssetResourceLoadingRequest
        ) async throws {
            let size = try await resolvedContentLength()

            var offset = dataRequest.currentOffset
            let end: Int64 = dataRequest.requestsAllDataToEndOfResource
                ? size
                : min(dataRequest.requestedOffset + Int64(dataRequest.requestedLength), size)

            while offset < end {
                guard !Task.isCancelled, !loadingRequest.isCancelled else { return }

                let chunkEnd = min(offset + chunkSize, end)
                let data = try await SMBManager.shared.downloadRange(
                    atRelativePath: relativePath,
                    range: offset..<chunkEnd
                )
                guard !data.isEmpty else { break }

                dataRequest.respond(with: data)
                offset += Int64(data.count)
            }
        }
    }
}
