//
//  MediaLibraryStore.swift
//  MediaApp
//
//  Współdzielony stan zakładek Zdjęcia, Wideo i Wszystko. Wstrzykiwany z MainTabView
//  jako @EnvironmentObject, żeby biblioteka była gotowa od razu po wejściu
//  do głównego widoku, a nie dopiero gdy użytkownik kliknie w daną zakładkę.
//
//  Wcześniej PhotoGalleryView i VideoGalleryView skanowały NAS OSOBNO —
//  każda przez własny lokalny @State w .task, który resetował się (i skanował
//  od nowa) za każdym razem, gdy tvOS niszczył i odtwarzał widok zakładki
//  (powrót do zakładki po przełączeniu, restart aplikacji). fetchMediaLibrary()
//  sam w sobie NIE ma cache'a — to zawsze pełny, rekurencyjny listing
//  katalogu po SMB (przy ~75 tys. plików realnie kilkanaście sekund), więc
//  PODWÓJNIE (raz dla zdjęć, raz dla wideo) i przy każdym powrocie do
//  zakładki. Jeden wspólny store, uruchamiany raz przy starcie MainTabView i
//  trzymany w hierarchii przez cały czas życia sesji, eliminuje obie te
//  redundancje — fetchMediaLibrary() i tak zwraca photos+videos w jednym
//  wywołaniu. Dodatkowo load() korzysta z MediaLibraryCache (dysk, nie
//  pamięć) — dzięki temu restart CAŁEJ aplikacji też nie oznacza kilkunastu
//  sekund komunikatu "Skanowanie NAS…" za każdym razem, tylko pokazuje
//  ostatnio znaną listę od razu i odświeża ją w tle.
//
//  Celowo NIE generuje tu miniatur dla całej biblioteki naraz — to
//  wcześniej powodowało crash OOM (Code 9), bo miniatury (każda wymagająca
//  ściągnięcia całego pliku wideo z NAS-a) były trzymane bezterminowo dla
//  wszystkich wideo, niezależnie od tego, czy użytkownik w ogóle je widział.
//  Generowanie miniatur jest teraz leniwe i związane z widocznością kafelka
//  — patrz VideoGridTile/MediaGridTile (.task(id:)) i ImageCache.
//

import SwiftUI
import Combine

@MainActor
final class MediaLibraryStore: ObservableObject {
    @Published private(set) var photos: [NASMediaItem] = []
    @Published private(set) var videos: [NASMediaItem] = []
    /// Podział wg miesiąca, przeliczany WYŁĄCZNIE tutaj, w apply() — przy
    /// faktycznej zmianie biblioteki (co najwyżej dwa razy na sesję: cache,
    /// potem świeży listing z SMB, patrz load() niżej) —
    /// zamiast jako computed var liczony na nowo w PhotoGalleryView/
    /// VideoGalleryView. Ten drugi wariant był kiedyś tutaj i przy
    /// dużej bibliotece (dziesiątki tysięcy plików) dawał 100% CPU i
    /// zacinanie przy KAŻDYM ruchu fokusu między wierszami siatki —
    /// mimo że w widoku siatki fizycznie widać tylko 25 kafelków — bo
    /// onFocusedRowChange przy każdej zmianie wiersza przestawiał @State
    /// w PhotoGalleryView, co przerenderowywało cały widok i liczyło
    /// MediaGrouping.byMonth(library.photos) od zera (kilka razy na
    /// jedno przerenderowanie — patrz selectedGroup/hasNextMonth/
    /// hasPreviousMonth/MonthSidebarList w PhotoGalleryView.swift), za
    /// każdym razem dla CAŁEJ biblioteki, nie tylko bieżącego miesiąca.
    @Published private(set) var photoMonthGroups: [MonthGroup] = []
    @Published private(set) var videoMonthGroups: [MonthGroup] = []
    /// Zdjęcia + wideo połączone w jedną chronologię, dla zakładki
    /// "Wszystko" (AllGalleryView) — przeliczane tym samym mechanizmem i z
    /// tego samego powodu co photoMonthGroups/videoMonthGroups wyżej (patrz
    /// komentarz tam).
    @Published private(set) var allMonthGroups: [MonthGroup] = []
    /// true TYLKO, gdy nie ma jeszcze czego pokazać (pierwszy start bez
    /// zapamiętanej listy) — galerie pokazują wtedy pełnoekranowy spinner.
    /// Skan przy już wyświetlonej bibliotece NIE ustawia tego (patrz
    /// isScanning) — inaczej siatka znikałaby na czas skanu.
    @Published private(set) var isLoading = true
    /// Trwa sam skan NAS (listing + porównanie z obecną listą), w tym w tle
    /// przy widocznej siatce — spinner na przycisku "Odśwież bibliotekę".
    @Published private(set) var isScanning = false
    @Published private(set) var errorMessage: String?

    private var didStart = false
    /// Trwa load() (wczytanie cache'a, skan, zapis) — blokada przed
    /// równoległymi wywołaniami.
    private var isLoadInProgress = false
    /// Moment ostatniego UDANEGO skanu — patrz refreshIfStale().
    private var lastScanDate: Date?
    /// Trwające pre-generowanie miniatur nowych plików — patrz
    /// pregenerateThumbnails(for:).
    private var pregenerationTask: Task<Void, Never>?
    private static let pregenerationLimit = 200

    /// Uruchamia skanowanie tylko raz — kolejne wywołania (np. ponowne
    /// pojawienie się MainTabView) nie odpalają go od nowa. Do wymuszenia
    /// odświeżenia służy reload().
    func start() {
        guard !didStart else { return }
        didStart = true
        Task { await load() }
    }

    func reload() {
        Task { await load() }
    }

    /// Skan w tle przy powrocie aplikacji na pierwszy plan (MainTabView,
    /// scenePhase == .active), jeśli ostatni udany skan jest starszy niż
    /// `maxAge`. tvOS przy wyjściu na ekran główny nie zamyka aplikacji,
    /// tylko ją zawiesza — po powrocie proces jest wznawiany, a nie
    /// uruchamiany od nowa, więc start() się nie powtarza i bez tego nowe
    /// pliki z NAS nie pojawiłyby się nawet po kilku dniach. Próg chroni
    /// przed skanowaniem przy każdym krótkim wyjściu z aplikacji.
    func refreshIfStale(maxAge: TimeInterval) {
        guard didStart, !isLoadInProgress else { return }
        if let lastScanDate, Date().timeIntervalSince(lastScanDate) < maxAge { return }
        reload()
    }

    private func load() async {
        // Blokada przed równoległymi wywołaniami (np. przycisk + powrót z
        // tła). Osobna od isScanning, bo obejmuje też wczytanie cache'a i
        // zapis — a isScanning (spinner na przycisku) tylko sam skan NAS.
        guard !isLoadInProgress else { return }
        isLoadInProgress = true
        defer { isLoadInProgress = false }
        errorMessage = nil

        // Najpierw pokaż natychmiast to, co wiedzieliśmy przy ostatnim
        // udanym skanowaniu (patrz MediaLibraryCache) — dużo szybsze niż
        // czekanie na SMB, a świeży listing i tak leci zaraz potem niżej.
        // Tylko gdy naprawdę nic jeszcze nie mamy (pierwsze uruchomienie
        // aplikacji albo wcześniej nieudany reload) — inaczej reload()
        // nadpisywałby już wyświetlone, żywe dane przestarzałym cache'em.
        if photos.isEmpty, videos.isEmpty, let cached = await MediaLibraryCache.load() {
            await apply(photos: cached.photos, videos: cached.videos)
        }
        let hasDataOnScreen = !photos.isEmpty || !videos.isEmpty
        isLoading = !hasDataOnScreen
        // Stan PRZED skanem (z cache'a albo z poprzedniego skanu) — do
        // wykrycia, które pozycje są nowe.
        let knownIDs = Set((photos + videos).map(\.id))

        isScanning = true
        defer { isScanning = false }
        do {
            let library = try await SMBManager.shared.fetchMediaLibrary()
            let changed = await apply(photos: library.photos, videos: library.videos)
            isScanning = false
            // Przy pustym stanie wyjściowym (pierwsze uruchomienie bez
            // zapamiętanej listy) "nowe" byłoby wszystko — pomijamy, pierwszy
            // ekran siatki i tak wygeneruje najnowsze miniatury sam.
            if !knownIDs.isEmpty {
                let newItems = (library.photos + library.videos).filter { !knownIDs.contains($0.id) }
                pregenerateThumbnails(for: newItems)
            }
            lastScanDate = Date()
            isLoading = false
            // Zapis ~11 MB JSON-a tylko przy faktycznej zmianie — przy
            // typowym starcie (nic nowego na NAS) zapisany plik i tak jest
            // identyczny.
            if changed {
                await MediaLibraryCache.save(library)
            }
        } catch {
            isLoading = false
            // Mamy już coś widoczne na ekranie (z cache'a albo z wcześniejszego
            // skanu)? Nie zasłaniaj tego komunikatem o błędzie — po prostu
            // zostaje nieodświeżone.
            if !hasDataOnScreen {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Generuje w tle miniatury kafelków dla plików, które pojawiły się na
    /// NAS od poprzedniego skanu (np. kilkadziesiąt zdjęć z iPhone'a z
    /// ostatniej doby), żeby po otwarciu aplikacji pokazały się od razu, a
    /// nie kafelek po kafelku. Bez tego miniatury powstają dopiero, gdy
    /// kafelek pojawi się na ekranie (leniwie).
    ///
    /// - Najwyżej `pregenerationLimit` NAJNOWSZYCH pozycji — przy wrzuceniu
    ///   na NAS całego archiwum nie pobieramy tysięcy oryginałów na zapas.
    /// - Ściśle PO KOLEI (await na każdą miniaturę): cały ruch SMB idzie
    ///   przez jedną kolejkę FIFO (SMBIOGate), więc gdyby wrzucić 200 żądań
    ///   naraz, kafelki faktycznie widoczne na ekranie czekałyby za nimi
    ///   wszystkimi. Po kolei = widoczny kafelek czeka najwyżej na jedno
    ///   pobranie.
    /// - Miniatury, które już są w cache'u (L1/L2), kończą się od razu bez
    ///   ruchu sieciowego — SMBImageCache/VideoThumbnailGenerator same to
    ///   sprawdzają.
    private func pregenerateThumbnails(for newItems: [NASMediaItem]) {
        guard !newItems.isEmpty else { return }
        let newest = newItems
            .sorted { ($0.captureDate ?? .distantPast) > ($1.captureDate ?? .distantPast) }
            .prefix(Self.pregenerationLimit)

        pregenerationTask?.cancel()
        pregenerationTask = Task.detached(priority: .utility) {
            for item in newest {
                guard !Task.isCancelled else { return }
                switch item.type {
                case .photo, .livePhoto:
                    _ = try? await SMBImageCache.shared.thumbnail(
                        for: item.imageURL,
                        maxPixelSize: MediaGridTile.thumbnailMaxPixelSize
                    )
                case .video:
                    _ = try? await VideoThumbnailGenerator.shared.thumbnail(for: item.imageURL)
                }
            }
        }
    }

    /// Jedyne miejsce, które ustawia bibliotekę i jej podział na miesiące.
    ///
    /// - Gdy świeży skan nie różni się niczym od tego, co już jest na
    ///   ekranie (typowy przypadek: cache z poprzedniego uruchomienia ==
    ///   świeży listing), NIC nie jest publikowane — bez tego cała siatka
    ///   przebudowywała się kilka sekund po starcie.
    /// - Grupowanie (MediaGrouping.byMonth — dla ~75 tys. pozycji kilka
    ///   sekund) liczone POZA głównym wątkiem, a "wszystko" scalane z gotowych
    ///   grup zdjęć i wideo zamiast liczone trzeci raz od zera. Wcześniej
    ///   działo się w didSet photos/videos na głównym wątku, cztery razy
    ///   (zdjęcia, wideo i dwa razy "wszystko"), co zamrażało UI na ~5 s
    ///   zaraz po wczytaniu listy z NAS.
    ///
    /// Zwraca, czy biblioteka faktycznie się zmieniła.
    @discardableResult
    private func apply(photos newPhotos: [NASMediaItem], videos newVideos: [NASMediaItem]) async -> Bool {
        guard newPhotos != photos || newVideos != videos else { return false }

        let groups = await Task.detached(priority: .userInitiated) {
            let photoGroups = MediaGrouping.byMonth(newPhotos)
            let videoGroups = MediaGrouping.byMonth(newVideos)
            return (
                photos: photoGroups,
                videos: videoGroups,
                all: MediaGrouping.merge(photoGroups, videoGroups)
            )
        }.value

        photos = newPhotos
        videos = newVideos
        photoMonthGroups = groups.photos
        videoMonthGroups = groups.videos
        allMonthGroups = groups.all
        return true
    }
}
