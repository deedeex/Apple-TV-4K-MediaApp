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
    @Published private(set) var isLoading = true
    @Published private(set) var errorMessage: String?

    private var didStart = false

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

    private func load() async {
        errorMessage = nil

        // Najpierw pokaż natychmiast to, co wiedzieliśmy przy ostatnim
        // udanym skanowaniu (patrz MediaLibraryCache) — dużo szybsze niż
        // czekanie na SMB, a świeży listing i tak leci zaraz potem niżej.
        // Tylko gdy naprawdę nic jeszcze nie mamy (pierwsze uruchomienie
        // aplikacji albo wcześniej nieudany reload) — inaczej reload()
        // nadpisywałby już wyświetlone, żywe dane przestarzałym cache'em.
        var hasCachedData = false
        if photos.isEmpty, videos.isEmpty, let cached = await MediaLibraryCache.load() {
            await apply(photos: cached.photos, videos: cached.videos)
            hasCachedData = true
        }
        isLoading = !hasCachedData

        do {
            let library = try await SMBManager.shared.fetchMediaLibrary()
            await apply(photos: library.photos, videos: library.videos)
            isLoading = false
            await MediaLibraryCache.save(library)
        } catch {
            isLoading = false
            // Mamy już coś z cache'a widoczne na ekranie? Nie zasłaniaj
            // tego komunikatem o błędzie — po prostu zostaje nieodświeżone.
            if !hasCachedData {
                errorMessage = error.localizedDescription
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
    private func apply(photos newPhotos: [NASMediaItem], videos newVideos: [NASMediaItem]) async {
        guard newPhotos != photos || newVideos != videos else { return }

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
    }
}
