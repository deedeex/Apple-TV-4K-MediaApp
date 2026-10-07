//
//  SMBManager.swift
//  MediaApp
//
//  Realne pobieranie listy plików i zawartości z serwera Synology przez
//  bibliotekę AMSMB2 (SPM: https://github.com/amosavian/AMSMB2).
//  Konfiguracja jest wczytywana dynamicznie z SMBServerConfig.loadFromStorage()
//  zamiast statycznego placeholdera — SetupView zapisuje ją po pierwszym
//  udanym połączeniu.
//

import Foundation
import AMSMB2

enum SMBError: LocalizedError {
    case invalidServerURL
    case connectionFailed
    case invalidRemotePath
    case missingCredentials
    case thumbnailDecodingFailed
    case timedOut

    var errorDescription: String? {
        switch self {
        case .invalidServerURL: return String(localized: "Nieprawidłowy adres serwera SMB.")
        case .connectionFailed: return String(localized: "Nie udało się połączyć z serwerem SMB. Sprawdź adres, użytkownika i hasło.")
        case .invalidRemotePath: return String(localized: "Nieprawidłowa ścieżka pliku na serwerze.")
        case .missingCredentials: return String(localized: "Brak zapisanej konfiguracji serwera NAS.")
        case .thumbnailDecodingFailed: return String(localized: "Nie udało się zdekodować miniatury.")
        case .timedOut: return String(localized: "Serwer NAS nie odpowiada (przekroczono limit czasu). Sprawdź połączenie sieciowe i spróbuj ponownie.")
        }
    }
}

/// Owija operację sieciową limitem czasu. AMSMB2 potrafi utknąć na
/// zablokowanym odczycie z gniazda (np. gdy połączenie padnie bez wysłania
/// RST) bez rzucenia błędu i bez zużycia CPU/RAM — bez tego rekurencyjne
/// listowanie dużego katalogu albo connectShare potrafi wirować w
/// nieskończoność, mimo że sieć realnie już nie działa.
///
/// Uwaga: anulowanie przegranego taska w TaskGroup NIE przerywa faktycznie
/// zablokowanego wywołania C (AMSMB2/libsmb2 nie sprawdza kooperacyjnie
/// Task.isCancelled w środku blokującego odczytu socketu) — ono po prostu
/// zostaje porzucone w tle. Dlatego SMBManager, gdy złapie .timedOut, zawsze
/// unieważnia bieżące połączenie (SMB2Manager), żeby kolejna próba dostała
/// świeży socket zamiast czekać za tym samym, martwym.
private func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw SMBError.timedOut
        }
        defer { group.cancelAll() }
        return try await group.next()!
    }
}

/// Asynchroniczny mutex serializujący operacje sieciowe AMSMB2.
///
/// SMBManager jest actorem, ale to NIE wystarcza, żeby zagwarantować, że w
/// danej chwili trwa najwyżej jedno żądanie SMB: każdy `await` wewnątrz
/// metody actora jest punktem zawieszenia, w którym inne wywołanie (np.
/// generowanie miniatury kafelka w trakcie trwającego fetchMediaLibrary)
/// może wejść na tego samego actora (reentrancy) i odpalić RÓWNOLEGŁE
/// żądanie na tym samym SMB2Manager/gnieździe. AMSMB2/libsmb2 nie jest
/// bezpieczne dla nakładających się żądań na jednym połączeniu — to
/// prowadziło do realnych EXC_BAD_ACCESS (i najpewniej części zawieszeń)
/// w warstwie C. Ta bramka wymusza pełną serializację.
private actor SMBIOGate {
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    private func lock() async {
        if !isLocked {
            isLocked = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func unlock() {
        if waiters.isEmpty {
            isLocked = false
        } else {
            waiters.removeFirst().resume()
        }
    }

    /// Zwalnia bramkę, jak tylko MY przestajemy czekać (timeout albo
    /// zakończenie operacji) — a nie dopiero, gdy faktycznie skończy się
    /// porzucone w tle wywołanie AMSMB2, bo ono może nigdy nie wrócić.
    func withLock<T: Sendable>(
        timeoutSeconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        await lock()
        defer { Task { await self.unlock() } }
        return try await withTimeout(seconds: timeoutSeconds, operation: operation)
    }
}

actor SMBManager {
    static let shared = SMBManager()

    private var client: SMB2Manager?
    private var activeConfig: SMBServerConfig?
    private let ioGate = SMBIOGate()

    private init() {}

    /// Jedyne miejsce, które faktycznie woła AMSMB2 — serializuje przez
    /// ioGate (patrz komentarz przy SMBIOGate) i ogranicza czekanie
    /// timeoutem. Gdy poddamy się czekaniu, unieważniamy bieżące
    /// połączenie: następna próba (np. przycisk „Spróbuj ponownie”) dostaje
    /// świeży SMB2Manager zamiast czekać w nieskończoność na tym samym,
    /// potencjalnie zawieszonym na stałe gnieździe.
    private func performIO<T: Sendable>(
        seconds: TimeInterval = 30,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        do {
            return try await ioGate.withLock(timeoutSeconds: seconds, operation: operation)
        } catch SMBError.timedOut {
            client = nil
            activeConfig = nil
            throw SMBError.timedOut
        }
    }

    // MARK: - Połączenie

    /// Łączy się z serwerem przy użyciu podanej konfiguracji i — jeśli się
    /// powiedzie — ustawia ją jako aktywną. Używane bezpośrednio przez
    /// SetupView do testowania danych logowania, zanim zostaną zapisane.
    @discardableResult
    func connect(using config: SMBServerConfig) async throws -> SMB2Manager {
        if let client, activeConfig == config { return client }

        guard let url = config.baseURL else { throw SMBError.invalidServerURL }

        if let client { try? await performIO(seconds: 10) { try await client.disconnectShare() } }

        let credential = URLCredential(user: config.username, password: config.password, persistence: .forSession)
        guard let manager = SMB2Manager(url: url, domain: config.domain, credential: credential) else {
            throw SMBError.connectionFailed
        }

        try await performIO(seconds: 20) { try await manager.connectShare(name: config.shareName) }
        client = manager
        activeConfig = config
        return manager
    }

    /// Zwraca aktywne połączenie, łącząc się w razie potrzeby na podstawie
    /// konfiguracji zapisanej wcześniej przez SetupView.
    private func connectedClient() async throws -> SMB2Manager {
        guard let storedConfig = SMBServerConfig.loadFromStorage() else {
            throw SMBError.missingCredentials
        }
        return try await connect(using: storedConfig)
    }

    func disconnect() async {
        if let client { try? await performIO(seconds: 10) { try await client.disconnectShare() } }
        client = nil
        activeConfig = nil
    }

    // MARK: - Lista mediów

    private static let photoExtensions: Set<String> = ["heic", "heif", "jpg", "jpeg", "png"]
    private static let videoExtensions: Set<String> = ["mp4", "mkv", "avi", "mov", "hevc", "m4v"]

    private struct GroupedFiles {
        var photoURL: URL?
        var videoURL: URL?
        var photoDate: Date?
        var videoDate: Date?
    }

    private struct FileEntry {
        let path: String
        let date: Date?
    }

    /// Skanuje katalog skonfigurowany w SetupView (remotePath) rekurencyjnie
    /// i rozdziela wynik na dwie tablice: `photos` (zdjęcia, w tym Live
    /// Photo) i `videos` (samodzielne pliki wideo). Wideo trafia do `photos`
    /// jako część Live Photo tylko wtedy, gdy ma dokładnie tę samą ścieżkę
    /// i nazwę bazową co jakieś zdjęcie (np. IMG_1234.HEIC + IMG_1234.MOV w
    /// tym samym folderze) — w przeciwnym razie ląduje w `videos`.
    func fetchMediaLibrary() async throws -> MediaLibrary {
        let client = try await connectedClient()
        guard let config = activeConfig else { throw SMBError.missingCredentials }

        // Duży rekurencyjny skan — performIO (wołane wewnątrz
        // fetchFileListFromSMB) sam unieważni połączenie, jeśli utknie bez
        // odpowiedzi, więc retry z UI dostanie świeży SMB2Manager.
        let rawFiles = try await fetchFileListFromSMB(client: client, path: config.remotePath)
        var groups: [String: GroupedFiles] = [:]

        for file in rawFiles {
            let ext = (file.path as NSString).pathExtension.lowercased()
            // Klucz grupowania to pełna ścieżka bez rozszerzenia (nie sama
            // nazwa pliku) — przy rekurencyjnym skanie dwa różne podfoldery
            // mogą mieć plik o tej samej nazwie i nie powinny się przez to
            // przypadkiem połączyć w jeden Live Photo.
            let groupKey = (file.path as NSString).deletingPathExtension
            let remoteFileURL = remoteURL(forRelativePath: file.path, config: config)

            if Self.photoExtensions.contains(ext) {
                groups[groupKey, default: GroupedFiles()].photoURL = remoteFileURL
                groups[groupKey, default: GroupedFiles()].photoDate = file.date
            } else if Self.videoExtensions.contains(ext) {
                groups[groupKey, default: GroupedFiles()].videoURL = remoteFileURL
                groups[groupKey, default: GroupedFiles()].videoDate = file.date
            }
        }

        var photos: [NASMediaItem] = []
        var videos: [NASMediaItem] = []

        for (groupKey, files) in groups {
            let baseName = (groupKey as NSString).lastPathComponent
            // Data zdjęcia ma pierwszeństwo — dla pary Live Photo to ona
            // reprezentuje całą pozycję w grupowaniu wg miesiąca.
            let date = files.photoDate ?? files.videoDate

            switch (files.photoURL, files.videoURL) {
            case let (.some(photoURL), .some(videoURL)):
                // Para o tej samej nazwie bazowej — wideo jest częścią Live
                // Photo, więc zostaje "wewnątrz" zdjęcia i NIE trafia do videos.
                photos.append(NASMediaItem(baseFileName: baseName, imageURL: photoURL, type: .livePhoto(videoURL: videoURL), captureDate: date))
            case let (.some(photoURL), .none):
                photos.append(NASMediaItem(baseFileName: baseName, imageURL: photoURL, type: .photo, captureDate: date))
            case let (.none, .some(videoURL)):
                videos.append(NASMediaItem(baseFileName: baseName, imageURL: videoURL, type: .video, captureDate: date))
            case (.none, .none):
                continue
            }
        }

        // Remis po nazwie (ta sama nazwa w różnych podfolderach) rozstrzygany
        // pełnym adresem — inaczej kolejność zależała od losowej kolejności
        // iteracji słownika `groups` i każdy skan różnił się od cache'a,
        // przez co MediaLibraryStore.apply() przy każdym starcie niepotrzebnie
        // przeliczał i publikował całą bibliotekę od nowa.
        let byNameThenURL: (NASMediaItem, NASMediaItem) -> Bool = {
            $0.baseFileName != $1.baseFileName
                ? $0.baseFileName < $1.baseFileName
                : $0.imageURL.absoluteString < $1.imageURL.absoluteString
        }
        photos.sort(by: byNameThenURL)
        videos.sort(by: byNameThenURL)

        return MediaLibrary(photos: photos, videos: videos)
    }

    /// Rekurencyjnie listuje wszystkie pliki w `path` i jego podkatalogach.
    /// AMSMB2 sam robi przejście po drzewie (recursive: true) i zwraca w
    /// .pathKey pełną ścieżkę względem udziału (nie samą nazwę pliku), więc
    /// zagnieżdżenie folderów jest tu w pełni przezroczyste.
    private func fetchFileListFromSMB(client: SMB2Manager, path: String) async throws -> [FileEntry] {
        let entries = try await performIO(seconds: 60) {
            try await client.contentsOfDirectory(atPath: path, recursive: true)
        }

        return entries.compactMap { entry -> FileEntry? in
            if let type = entry[.fileResourceTypeKey] as? URLFileResourceType, type == .directory {
                return nil
            }
            if let isDirectory = entry[.isDirectoryKey] as? Bool, isDirectory {
                return nil
            }
            guard let path = entry[.pathKey] as? String else { return nil }
            // Data modyfikacji jest już w tym samym wpisie zwróconym przez
            // rekurencyjne listowanie — zero dodatkowych round-tripów do NAS-a.
            let date = entry[.contentModificationDateKey] as? Date
            return FileEntry(path: path, date: date)
        }
    }

    // MARK: - Przeglądanie katalogów (PathPickerView)

    /// Listuje zawartość dowolnego katalogu na aktywnym połączeniu — używane
    /// przez PathPickerView do wyboru folderu głównego, zanim SMBServerConfig
    /// zostanie zapisany. Celowo korzysta z `client`, a nie `connectedClient()`,
    /// bo w trakcie konfiguracji dane logowania jeszcze nie są w storage.
    func listDirectory(atPath path: String) async throws -> [SMBDirectoryEntry] {
        guard let client else { throw SMBError.missingCredentials }
        let entries = try await performIO { try await client.contentsOfDirectory(atPath: path) }

        let items: [SMBDirectoryEntry] = entries.compactMap { entry in
            guard let name = entry[.nameKey] as? String, name != ".", name != ".." else { return nil }

            let isDirectory = (entry[.fileResourceTypeKey] as? URLFileResourceType == .directory)
                || (entry[.isDirectoryKey] as? Bool == true)

            let fullPath = path.isEmpty ? name : "\(path)/\(name)"
            return SMBDirectoryEntry(path: fullPath, name: name, isDirectory: isDirectory)
        }

        return items.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    // MARK: - Pobieranie zawartości plików

    func downloadData(atRelativePath path: String) async throws -> Data {
        let client = try await connectedClient()
        return try await performIO { try await client.contents(atPath: path) }
    }

    func downloadData(at url: URL) async throws -> Data {
        try await downloadData(atRelativePath: relativePath(for: url))
    }

    /// Pobiera plik strumieniowo bezpośrednio na dysk (AMSMB2 downloadItem,
    /// porcje ~1MiB) — w przeciwieństwie do downloadData/downloadData(at:)
    /// NIE materializuje całego pliku w pamięci jako Data. Konieczne dla
    /// wideo (setki MB do kilku GB) — użycie downloadData tam powodowało
    /// crash OOM, szczególnie przy kilku równoległych pobraniach naraz.
    func downloadFile(atRelativePath path: String, to destination: URL) async throws {
        let client = try await connectedClient()
        // Duże pliki wideo (setki MB–kilka GB) legalnie potrafią ściągać się
        // dłużej niż standardowe okno — wyższy limit, żeby nie ucinać
        // działającego, tylko wolnego transferu.
        try await performIO(seconds: 300) {
            try await client.downloadItem(atPath: path, to: destination, progress: nil)
        }
    }

    func downloadFile(at url: URL, to destination: URL) async throws {
        try await downloadFile(atRelativePath: relativePath(for: url), to: destination)
    }

    /// Pobiera dokładnie wskazany zakres bajtów pliku — używane przez
    /// SMBStreamingAssetLoader, żeby AVFoundation mogło czytać wideo z NAS-a
    /// „na żądanie" (tylko potrzebne fragmenty), zamiast całego pliku naraz.
    func downloadRange(atRelativePath path: String, range: Range<Int64>) async throws -> Data {
        let client = try await connectedClient()
        return try await performIO { try await client.contents(atPath: path, range: range) }
    }

    /// Rozmiar pliku bez pobierania go (zwykły „stat"). Używane przez
    /// VideoThumbnailGenerator, żeby nie ściągać wielogigabajtowych plików
    /// wideo tylko po to, żeby wyciągnąć z nich jedną klatkę na miniaturę.
    func fileSize(atRelativePath path: String) async throws -> Int64? {
        let client = try await connectedClient()
        let attributes = try await performIO { try await client.attributesOfItem(atPath: path) }
        return attributes.fileSize
    }

    func fileSize(at url: URL) async throws -> Int64? {
        try await fileSize(atRelativePath: relativePath(for: url))
    }

    // MARK: - Adresy smb://

    /// Buduje adres smb://host/udział/ścieżka do zapisania w NASMediaItem.
    private func remoteURL(forRelativePath path: String, config: SMBServerConfig) -> URL {
        var components = URLComponents()
        components.scheme = "smb"
        components.host = config.host

        let encodedSegments = "\(config.shareName)/\(path)"
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
        components.percentEncodedPath = "/" + encodedSegments.joined(separator: "/")

        return components.url ?? URL(fileURLWithPath: path)
    }

    /// Odwraca remoteURL(forRelativePath:) — zdejmuje host i nazwę udziału,
    /// zwracając ścieżkę względną, jakiej oczekuje contentsOfDirectory/contents(atPath:).
    nonisolated func relativePath(for url: URL) -> String {
        var parts = url.pathComponents.filter { $0 != "/" }
        guard !parts.isEmpty else { return "" }
        parts.removeFirst() // nazwa udziału SMB
        return parts.joined(separator: "/")
    }
}
