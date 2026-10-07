//
//  MediaPagerView.swift
//  MediaApp
//
//  Pełnoekranowa przeglądarka mediów prezentowana z PhotoGalleryView przez
//  .fullScreenCover. Celowo NIE używa TabView(.page) — wbudowana obsługa
//  gestów pilota Siri w tym stylu okazała się niewiarygodna w kontekście
//  fullScreenCover. Zamiast tego: ręczny pager sterowany .onMoveCommand,
//  z fokusem wymuszonym przez .defaultFocus na tym właśnie widoku.
//
//  Stan odtwarzania Live Photo (isPlayingLive/isPreparingVideo/player) żyje
//  TUTAJ, a nie w LivePhotoViewer — .onPlayPauseCommand reaguje tylko na
//  widoku, który faktycznie ma fokus, a to jest ten Button (patrz body),
//  nie zagnieżdżony w nim LivePhotoViewer. Stąd wcześniejszy bug: klikanie
//  Play na pilocie nic nie robiło, bo handler siedział na dziecku bez fokusu.
//
//  Pre-ładowanie pełnoekranowych podglądów sąsiednich zdjęć (patrz
//  prefetchNeighbors/prefetchedIndices) — żeby swipe między zdjęciami był
//  płynny, a nie czekał na żywo na SMB + dekodowanie za każdym razem. WAŻNE:
//  cały ruch SMB w aplikacji jest zserializowany przez SMBIOGate (patrz
//  komentarz tam) — jedno żądanie naraz, niezależnie od tego, ile Tasków tu
//  odpalimy równolegle. Prefetch więc realnie doładowuje się stopniowo w
//  tle, nie wszystkie 4 sąsiednie zdjęcia naraz, i kolejkuje się za innym
//  ruchem SMB (np. miniaturami w siatce pod spodem).
//

import SwiftUI
import AVKit

struct MediaPagerView: View {
    let items: [NASMediaItem]
    @Binding var selection: NASMediaItem.ID?

    @State private var currentIndex: Int
    @FocusState private var isFocused: Bool

    /// Jawny init zamiast domyślnego currentIndex = 0 + korekty w .onAppear —
    /// przy tej drugiej wersji PIERWSZA wyrenderowana klatka pokazywała
    /// zawsze items[0] (pierwsze zdjęcie miesiąca), zanim .onAppear zdążyło
    /// poprawić currentIndex na właściwy indeks. Wcześniej było to
    /// niezauważalne (korekta i pierwszy render praktycznie się zlewały),
    /// ale po dodaniu FocusRestorationDisabler (patrz tam) — dodatkowego
    /// UIViewControllerRepresentable osadzonego w .background — SwiftUI
    /// zaczęło realnie flushować tę pierwszą, błędną klatkę na ekran, zanim
    /// .onAppear zdążyło zadziałać. Liczenie właściwego indeksu TUTAJ,
    /// synchronicznie, eliminuje to u źródła niezależnie od tego, kiedy
    /// dokładnie .onAppear się odpali.
    init(items: [NASMediaItem], selection: Binding<NASMediaItem.ID?>) {
        self.items = items
        self._selection = selection
        _currentIndex = State(initialValue: items.firstIndex(where: { $0.id == selection.wrappedValue }) ?? 0)
    }

    @State private var isPlayingLive = false
    @State private var isPreparingVideo = false
    @State private var player: AVPlayer?

    /// Ile pozycji w każdą stronę od bieżącego zdjęcia trzymamy pre-załadowane
    /// w RAM (razem z bieżącym to maks. 9 na raz — "±4" z prośby użytkownika).
    private static let prefetchRadius = 4

    /// Indeksy, dla których TA strona aktywnie trzyma pełnoekranowy wariant w
    /// ImageCache (bieżący + okno ±4) — używane wyłącznie do liczenia różnicy
    /// względem nowego okna przy zmianie currentIndex: co wypada poza okno,
    /// jest jawnie usuwane z RAM (patrz ImageCache.remove), co wchodzi nowo,
    /// jest doładowywane w tle. Bez tego NSCache sam decydowałby, co ewentualnie
    /// wyrzucić, wg własnej heurystyki — nie dając twardej gwarancji "tylko
    /// okno ±4 na raz" ani deterministycznego czyszczenia przy przewijaniu.
    @State private var prefetchedIndices: Set<Int> = []

    var body: some View {
        // Button (nie goły .focusable + .onTapGesture/.onLongPressGesture) —
        // to jedyny na tvOS niezawodny sposób na odpalenie akcji JEDNYM
        // kliknięciem środka clickpada. Ręczne rozpoznawanie gestów na gołym
        // .focusable (obie próby: .onTapGesture i .onLongPressGesture)
        // wymagało DWÓCH kliknięć — pierwsze było pochłaniane przez systemowe
        // rozpoznawanie naciśnięcia/puszczenia, które Button ma poprawnie
        // okablowane, a ręczne gesty nie. Poza tym bez zmian: to nadal JEDYNY
        // fokusowalny element tej strony (patrz komentarz w
        // LivePhotoViewer.swift), więc .onMoveCommand i .onPlayPauseCommand
        // nadal działają tak samo jak wcześniej na gołym .focusable — Button
        // jest fokusowalny z tych samych powodów.
        Button(action: playCurrentLivePhotoIfNeeded) {
            // Przezroczysta etykieta — cała zawartość (czarne tło + zdjęcie)
            // jest w .overlay NAD Buttonem, patrz komentarz przy
            // pageContent.
            Color.clear
        }
        .buttonStyle(.plain)
        // .frame/.ignoresSafeArea PO .buttonStyle, nie na etykiecie w środku
        // Buttona — wymuszanie rozmiaru na samej etykiecie nie wystarczyło:
        // Button na tvOS ma własny, wewnętrzny margines/dopełnienie wokół
        // etykiety niezależny od tego, jak duża jest sama etykieta, więc
        // finalny, klikalny/renderowany obszar Buttona i tak wychodził
        // mniejszy niż cały ekran — widoczne jako margines z zaokrąglonymi
        // rogami, przez który było widać siatkę pod spodem. Wymuszenie tutaj,
        // na już ukształtowanym (buttonStyle + rozmiar) widoku, naprawia to
        // u źródła zamiast na etykiecie.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        // Systemowy efekt podświetlenia fokusu (halo/skalowanie) dodatkowo
        // dokładał tu wizualną "ramkę" — nie ma sensu na widoku, który jest
        // JEDYNYM elementem ekranu i ZAWSZE ma fokus (.defaultFocus niżej),
        // więc podświetlanie "co jest aktualnie w fokusie" jest tu zbędne i
        // tylko szkodzi.
        .focusEffectDisabled()
        .overlay {
            pageContent
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .focused($isFocused)
        .defaultFocus($isFocused, true)
        // Patrz obszerny komentarz w FocusRestorationDisabler.swift — bez
        // tego powrót do siatki po przewinięciu tutaj w pełnym ekranie
        // zostawiał fokus na kaflu sprzed wejścia, nie na ostatnio
        // oglądanej pozycji (system sam przywracał stary fokus z
        // opóźnieniem, nadpisując wszystko, co ustawiała siatka).
        .background(FocusRestorationDisabler())
        .onMoveCommand { direction in
            switch direction {
            case .left: goToPrevious()
            case .right: goToNext()
            default: break
            }
        }
        .onPlayPauseCommand {
            playCurrentLivePhotoIfNeeded()
        }
        .onAppear {
            if let selection, let index = items.firstIndex(where: { $0.id == selection }) {
                currentIndex = index
            }
            isFocused = true
            updatePrefetchWindow(around: currentIndex)
        }
        .onChange(of: currentIndex) { _, newValue in
            stopPlayback()
            guard items.indices.contains(newValue) else { return }
            selection = items[newValue].id
            updatePrefetchWindow(around: newValue)
        }
    }

    /// Zawartość strony NAD Buttonem (w .overlay), a nie w jego etykiecie
    /// — tvOS 26 rysuje pod etykietą sfokusowanego Buttona własne jasne tło
    /// i rozjaśnia samą etykietę, więc czarne tło w środku Buttona
    /// wychodziło ciemnoszare. Overlay bez hit-testingu i bez elementów
    /// fokusowalnych — pilota nadal obsługuje wyłącznie Button.
    @ViewBuilder
    private var pageContent: some View {
        ZStack {
            Color.black

            if items.indices.contains(currentIndex) {
                // BEZ .id(item.id)/.transition() — LivePhotoViewer nie trzyma
                // własnego @State (wszystko dostaje z zewnątrz), a
                // AsyncImageSMB już reaguje na zmianę url przez własne
                // .task(id: url). Wymuszanie .id() niszczyło i odtwarzało
                // całe poddrzewo przy KAŻDYM swipe między zdjęciami — pod
                // rodzicem, który na siłę trzyma systemowy fokus
                // (.focusable/.defaultFocus). To dokładnie wzorzec z
                // ostrzeżenia "_UIReplicantView as a subview of
                // UIHostingController.view": wstawianie/usuwanie widoku pod
                // stale skupionym rodzicem w trakcie animowanego przejścia —
                // silnik fokusu próbuje zrobić snapshot i się zawiesza
                // (_UIFocusEnginePanGestureRecognizer blocking its subgraph…).
                LivePhotoViewer(
                    item: items[currentIndex],
                    isPlayingLive: isPlayingLive,
                    isPreparingVideo: isPreparingVideo,
                    player: player,
                    onVideoFinished: stopPlayback
                )
            }
        }
    }

    private func goToPrevious() {
        guard currentIndex > 0 else { return }
        withAnimation(.easeInOut) { currentIndex -= 1 }
    }

    private func goToNext() {
        guard currentIndex < items.count - 1 else { return }
        withAnimation(.easeInOut) { currentIndex += 1 }
    }

    private func playCurrentLivePhotoIfNeeded() {
        guard !isPlayingLive, !isPreparingVideo,
              items.indices.contains(currentIndex),
              case .livePhoto(let videoURL) = items[currentIndex].type
        else { return }

        isPreparingVideo = true
        Task {
            defer { isPreparingVideo = false }
            do {
                let localURL = try await SMBVideoCache.shared.localFileURL(for: videoURL)
                player = AVPlayer(url: localURL)
                withAnimation { isPlayingLive = true }
            } catch {
                // Nie udało się pobrać wideo z NAS-a — zostajemy na zdjęciu.
            }
        }
    }

    private func stopPlayback() {
        withAnimation(.easeInOut(duration: 0.5)) {
            isPlayingLive = false
        }
        player = nil
    }

    /// Przesuwa okno pre-ładowania na `±prefetchRadius` wokół `index` —
    /// wywoływane przy starcie i przy KAŻDEJ zmianie currentIndex (patrz
    /// .onAppear/.onChange wyżej). To zwykłe odejmowanie zbiorów
    /// (newWindow \ prefetchedIndices = nowe do doładowania, odwrotnie =
    /// wypadłe do usunięcia z RAM) — bieżący indeks jest w oknie, ale
    /// celowo pomijany przy samym odpalaniu pobierania: ten element i tak
    /// ładuje AsyncImageSMB wewnątrz LivePhotoViewer, więc osobne żądanie
    /// tutaj byłoby zbędnym duplikatem tej samej pracy.
    private func updatePrefetchWindow(around index: Int) {
        guard items.indices.contains(index) else { return }

        let lowerBound = max(items.startIndex, index - Self.prefetchRadius)
        let upperBound = min(items.index(before: items.endIndex), index + Self.prefetchRadius)
        let newWindow = Set(lowerBound...upperBound)

        for staleIndex in prefetchedIndices.subtracting(newWindow) {
            ImageCache.shared.remove(for: items[staleIndex].imageURL, variant: fullScreenVariant)
        }

        for newIndex in newWindow.subtracting(prefetchedIndices) where newIndex != index {
            let url = items[newIndex].imageURL
            Task.detached(priority: .utility) {
                _ = try? await SMBImageCache.shared.thumbnail(for: url, maxPixelSize: AsyncImageSMB.fullScreenMaxPixelSize)
            }
        }

        prefetchedIndices = newWindow
    }

    /// Ten sam klucz wariantu, jakiego SMBImageCache.thumbnail(for:maxPixelSize:)
    /// używa wewnętrznie do wpisów w ImageCache/DiskThumbnailCache — patrz
    /// SMBImageCache.variant(for:), żeby nie duplikować tu tej formuły.
    private var fullScreenVariant: String {
        SMBImageCache.variant(for: AsyncImageSMB.fullScreenMaxPixelSize)
    }
}
