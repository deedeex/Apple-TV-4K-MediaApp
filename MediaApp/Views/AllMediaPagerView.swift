//
//  AllMediaPagerView.swift
//  MediaApp
//
//  Pełnoekranowa przeglądarka MIESZANA (zdjęcia + Live Photo + wideo) dla
//  zakładki "Wszystko" — jedyne miejsce w aplikacji, gdzie przewijanie w
//  pełnym ekranie faktycznie przechodzi między typami w kolejności
//  chronologicznej, a nie w obrębie jednego typu (patrz AllMonthGridView —
//  wcześniejsza wersja z dwoma osobnymi widokami/podzbiorami była bezpieczna,
//  ale przeskakiwała wideo przy przewijaniu zdjęć; to świadoma, bardziej
//  ryzykowna przebudowa na wyraźną prośbę).
//
//  CELOWO NOWY, SAMODZIELNY plik — nie modyfikuje MediaPagerView.swift ani
//  VideoPlaybackView.swift, które zostają w pełni nietknięte dla dedykowanych
//  zakładek Zdjęcia/Wideo. Całe nowe ryzyko tej przebudowy jest odizolowane
//  tutaj, w miejscu używanym wyłącznie przez zakładkę "Wszystko".
//
//  KLUCZOWA RÓŻNICA względem VideoPlaybackView: prawdziwe wideo odtwarzane
//  jest tu przez PlayerLayerView (goły AVPlayerLayer), NIE przez AVKit-owy
//  VideoPlayer. VideoPlaybackView może bezpiecznie używać VideoPlayer,
//  bo jego korzeń NIE trzyma wymuszonego fokusu (żaden Button/.defaultFocus)
//  — a ten pager, tak jak MediaPagerView, MUSI trzymać wymuszony fokus na
//  jednym, stałym Buttonie (patrz komentarz w MediaPagerView.swift o tym,
//  dlaczego to jedyny niezawodny sposób na klikanie środka pilota). VideoPlayer
//  wewnątrz widoku z wymuszonym fokusem rodzica to dokładnie wzorzec
//  udokumentowany w PlayerLayerView.swift jako przyczyna realnego zawieszenia
//  pilota (dwa silniki fokusu walczące o ten sam input) — dlatego tu NIE
//  VideoPlayer, tylko SystemVideoPlayerView: AVPlayerViewController bez
//  kontrolek i bez interakcji (wcześniej PlayerLayerView, ale goły
//  AVPlayerLayer szarpał przy wideo 4K60 HDR — patrz komentarz w
//  SystemVideoPlayerView.swift). Live Photo zostają na PlayerLayerView. Kompromis: brak
//  natywnego paska transportu/scrubbingu przy prawdziwym wideo w tej
//  zakładce (jest w dedykowanej zakładce Wideo) — akceptowalna cena za
//  bezpieczeństwo fokusu.
//
//  Nakładka końca wideo (Poprzednie/Odtwórz ponownie/Następne) jest tu
//  CELOWO tylko dekoracją (.allowsHitTesting(false), bez własnego Buttona/
//  @FocusState) — sterowana tym samym, jedynym Buttonem/.onMoveCommand co
//  cała reszta pagera. Osobny, zagnieżdżony Button (jak w VideoPlaybackView,
//  które NIE ma nadrzędnego wymuszonego fokusu) byłby tu nowym, nigdzie
//  wcześniej nie przetestowanym wzorcem "Button w Buttonie" — a przewijanie
//  (lewo/prawo) i klik środka pilota już w pełni realizują to samo bez
//  dokładania kolejnego fokusowalnego elementu.
//
//  Swipe DZIAŁA nawet w trakcie odtwarzania wideo (bez blokady, w
//  przeciwieństwie do VideoPlaybackView) — ten guard tam istnieje tylko
//  dlatego, że AVKit-owy VideoPlayer sam przechwytuje gesty pilota do
//  scrubbingu. PlayerLayerView nie ma żadnych własnych gestów, więc nie ma
//  z czym konkurować.
//

import SwiftUI
import AVKit

struct AllMediaPagerView: View {
    let items: [NASMediaItem]
    @Binding var selection: NASMediaItem.ID?

    @State private var currentIndex: Int
    @FocusState private var isFocused: Bool

    /// Patrz obszerny komentarz przy analogicznym init w MediaPagerView.swift
    /// — jawne liczenie startowego currentIndex TUTAJ (nie w .onAppear)
    /// eliminuje widoczne mignięcie items[0] przy wejściu w pełny ekran.
    init(items: [NASMediaItem], selection: Binding<NASMediaItem.ID?>) {
        self.items = items
        self._selection = selection
        _currentIndex = State(initialValue: items.firstIndex(where: { $0.id == selection.wrappedValue }) ?? 0)
    }

    // MARK: Live Photo (patrz MediaPagerView.swift — identyczna logika)

    @State private var isPlayingLive = false
    @State private var isPreparingLiveVideo = false
    @State private var livePlayer: AVPlayer?

    /// Patrz komentarz przy prefetchedIndices w MediaPagerView.swift —
    /// identyczna logika, tylko pomija indeksy pozycji typu .video (dla nich
    /// nie ma czego pre-ładować przez SMBImageCache — to nie są obrazy).
    private static let prefetchRadius = 4
    @State private var prefetchedPhotoIndices: Set<Int> = []

    // MARK: Wideo (patrz VideoPlaybackView.swift — ta sama logika, inny odtwarzacz)

    @State private var videoPlayer: AVPlayer?
    /// Patrz komentarz przy streamLoader w VideoPlaybackView.swift.
    @State private var streamLoader: SMBStreamingAssetLoader?
    @State private var videoErrorMessage: String?
    @State private var videoDidFinish = false
    @State private var lastFrameImage: UIImage?

    private var currentItem: NASMediaItem? {
        items.indices.contains(currentIndex) ? items[currentIndex] : nil
    }

    private var hasPreviousItem: Bool { currentIndex > 0 }
    private var hasNextItem: Bool { currentIndex < items.count - 1 }

    var body: some View {
        // Patrz obszerny komentarz na górze pliku i w MediaPagerView.swift o
        // tym, dlaczego Button (nie goły .focusable) i dlaczego .frame/
        // .ignoresSafeArea/.focusEffectDisabled PO .buttonStyle.
        Button(action: primaryAction) {
            // Przezroczysta etykieta — cała zawartość (czarne tło + zdjęcie)
            // jest w .overlay NAD Buttonem, patrz komentarz przy
            // pageContent.
            Color.clear
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .focusEffectDisabled()
        .overlay {
            pageContent
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        // Wideo POZA etykietą Buttona (NAD nim, nie w videoPage) — treść
        // etykiety sfokusowanego Buttona tvOS składa (i przekolorowuje,
        // patrz nakładka niżej) jako jedną całość, więc osadzone w niej
        // wideo nie może iść systemową, bezpośrednią ścieżką wyświetlania
        // i każda klatka jest składana na GPU razem z UI. Przy plikach 4K
        // 60 kl./s HDR (~100 Mb/s) na nagrzanym Apple TV dawało to
        // szarpanie od ~3. sekundy — niezależnie od tego, czy był to goły
        // AVPlayerLayer, czy AVPlayerViewController (sprawdzone logami:
        // zero I/O w tle, przerysowań i zacięć głównego wątku w trakcie).
        // W zakładce Wideo VideoPlayer nie siedzi w żadnym Buttonie i ten
        // sam plik leci płynnie.
        // NAD Buttonem (.overlay), nie pod nim (.background): sfokusowany
        // Button na tvOS 26 rysuje pod przezroczystą etykietą własne,
        // jasne, rozmyte tło, które przykrywało wideo położone pod spodem
        // (obraz prawie cały biały). Overlay bez hit-testingu i
        // niefokusowalny — pilot nadal obsługuje wyłącznie Button.
        .background(Color.black.ignoresSafeArea())
        .overlay {
            if let currentItem, isVideo(currentItem), !videoDidFinish, let videoPlayer {
                SystemVideoPlayerView(player: videoPlayer)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .focusable(false)
            }
        }
        // Nakładka końca wideo POZA etykietą Buttona (nie w videoPage) —
        // tvOS przekolorowuje zawartość sfokusowanego Buttona (a ten pager
        // ma fokus cały czas), przez co .secondary "Poprzednie"/"Następne"
        // robiło się ciemne/czarne zamiast szarego jak w VideoPlaybackView.
        // Jako zwykły overlay (bez hit-testingu, niefokusowalny) dostaje to
        // samo, neutralne środowisko co nakładka w zakładce Wideo.
        .overlay {
            if let currentItem, isVideo(currentItem), videoDidFinish {
                videoEndOverlay
            }
        }
        .focused($isFocused)
        .defaultFocus($isFocused, true)
        // Patrz obszerny komentarz w FocusRestorationDisabler.swift.
        .background(FocusRestorationDisabler())
        .onMoveCommand { direction in
            switch direction {
            case .left: goToPrevious()
            case .right: goToNext()
            default: break
            }
        }
        .onPlayPauseCommand {
            primaryAction()
        }
        .onAppear {
            if let selection, let index = items.firstIndex(where: { $0.id == selection }) {
                currentIndex = index
            }
            isFocused = true
            updatePhotoPrefetchWindowIfNotPlayingVideo()
        }
        .onChange(of: currentIndex) { _, newValue in
            stopLivePhotoPlayback()
            guard items.indices.contains(newValue) else { return }
            selection = items[newValue].id
            updatePhotoPrefetchWindowIfNotPlayingVideo()
        }
        // Sprzątanie przy zamknięciu CAŁEGO pagera (Menu/wstecz) — bez tego
        // stary AVPlayer był tylko odrywany od @State (poniżej i w .task),
        // a jego faktyczne zatrzymanie/zwolnienie zależało od ARC (dealloc
        // AVPlayer), co na tvOS bywa niedeterministyczne w czasie. Jeśli
        // kolejne wideo (nowa prezentacja tego pagera, np. po powrocie do
        // siatki i wejściu w inną pozycję) próbowało wystartować zanim
        // poprzednia sesja sprzętowego dekodera faktycznie się zamknęła,
        // dawało to dźwięk bez obrazu (audio działa niezależnie od
        // dekodowania wideo) — stąd jawne .pause()/.replaceCurrentItem(nil)
        // tutaj, zamiast liczyć wyłącznie na dealloc.
        .onDisappear {
            videoPlayer?.pause()
            videoPlayer?.replaceCurrentItem(with: nil)
            stopStreaming()
            livePlayer?.pause()
            livePlayer?.replaceCurrentItem(with: nil)
        }
        // Odtwarzanie wideo — patrz komentarz przy load() w
        // VideoPlaybackView.swift. Odpala się przy KAŻDEJ zmianie
        // currentIndex (nie tylko dla wideo) i od razu wychodzi, jeśli
        // bieżąca pozycja to nie .video — reset stanu wideo jest wtedy i tak
        // tani/nieszkodliwy.
        .task(id: currentIndex) {
            videoErrorMessage = nil
            videoDidFinish = false
            lastFrameImage = nil
            // Jawne zatrzymanie/odłączenie STAREGO odtwarzacza PRZED
            // odrzuceniem referencji — patrz komentarz przy .onDisappear
            // wyżej o tym, dlaczego samo `videoPlayer = nil` (poprzednia
            // wersja) nie wystarczało.
            videoPlayer?.pause()
            videoPlayer?.replaceCurrentItem(with: nil)
            videoPlayer = nil
            stopStreaming()

            guard let currentItem, case .video = currentItem.type else { return }

            // Strumieniowo z NAS-a, bez pre-ładowania następnego wideo —
            // patrz komentarz w load() w VideoPlaybackView.swift.
            let (newPlayer, loader) = SMBStreamingAssetLoader.makePlayer(for: currentItem.imageURL)
            streamLoader = loader
            videoPlayer = newPlayer

            let failureWatch = Task {
                guard let item = newPlayer.currentItem,
                      let message = await SMBStreamingAssetLoader.failureMessage(of: item)
                else { return }
                videoErrorMessage = message
                videoPlayer = nil
            }
            defer { failureWatch.cancel() }

            for await _ in NotificationCenter.default.notifications(
                named: .AVPlayerItemDidPlayToEndTime,
                object: newPlayer.currentItem
            ) {
                videoDidFinish = true
                // Odroczone pre-ładowanie zdjęć — patrz
                // updatePhotoPrefetchWindowIfNotPlayingVideo().
                updatePhotoPrefetchWindow(around: currentIndex)
                await captureLastFrame(of: newPlayer)
            }
        }
    }

    /// Zawartość strony NAD Buttonem (w .overlay), a nie w jego etykiecie
    /// — tvOS 26 rysuje pod etykietą sfokusowanego Buttona własne jasne tło
    /// i rozjaśnia samą etykietę, więc czarne tło w środku Buttona
    /// wychodziło ciemnoszare. Overlay bez hit-testingu i bez elementów
    /// fokusowalnych — pilota nadal obsługuje wyłącznie Button. Wideo i
    /// nakładka końca wideo to kolejne overlaye nad tym.
    @ViewBuilder
    private var pageContent: some View {
        ZStack {
            Color.black

            if let currentItem {
                switch currentItem.type {
                case .photo, .livePhoto:
                    LivePhotoViewer(
                        item: currentItem,
                        isPlayingLive: isPlayingLive,
                        isPreparingVideo: isPreparingLiveVideo,
                        player: livePlayer,
                        onVideoFinished: stopLivePhotoPlayback
                    )
                case .video:
                    videoPage
                }
            }
        }
    }

    // MARK: - Strona wideo

    @ViewBuilder
    private var videoPage: some View {
        if videoDidFinish {
            ZStack {
                if let lastFrameImage {
                    // Patrz obszerny komentarz w VideoPlaybackView.swift o
                    // Color jako rodzeństwie (nie .overlay) — ten sam fix.
                    ZStack {
                        Image(uiImage: lastFrameImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                        Color.black.opacity(0.35)
                    }
                }
            }
        } else if videoPlayer != nil {
            // Samo wideo jest w .overlay nad Buttonem (patrz komentarz w
            // body) — tu tylko przezroczyste miejsce na nie.
            Color.clear
        } else if let videoErrorMessage {
            LiquidGlassCard(useNativeGlassEffect: true) {
                VStack(spacing: 16) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.largeTitle)
                    Text(videoErrorMessage)
                        .multilineTextAlignment(.center)
                }
            }
        } else {
            ProgressView("Wczytywanie wideo…")
        }
    }

    /// Czysto dekoracyjna — patrz obszerny komentarz na górze pliku o tym,
    /// dlaczego bez własnego Buttona/@FocusState (w przeciwieństwie do
    /// analogicznej nakładki w VideoPlaybackView.swift).
    @ViewBuilder
    private var videoEndOverlay: some View {
        VStack {
            Spacer()
            HStack(spacing: 40) {
                if hasPreviousItem {
                    Label("Poprzednie", systemImage: "chevron.left")
                        .foregroundStyle(.secondary)
                }
                // Statycznie odwzorowany wygląd sfokusowanego Buttona z
                // VideoPlaybackView (biała "pigułka", ciemny tekst, cień),
                // żeby obie zakładki wyglądały tak samo — sam Button tu
                // celowo nie jest możliwy, patrz komentarz na górze pliku.
                Label("Odtwórz ponownie", systemImage: "arrow.counterclockwise")
                    .fontWeight(.medium)
                    .foregroundStyle(Color(white: 0.1))
                    .padding(.horizontal, 32)
                    .padding(.vertical, 18)
                    .background(Capsule(style: .continuous).fill(Color(white: 0.92)))
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
                if hasNextItem {
                    Label("Następne", systemImage: "chevron.right")
                        .labelStyle(.trailingIcon)
                        .foregroundStyle(.secondary)
                }
            }
            .videoEndOverlayBackground()
            .padding(.bottom, 60)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Nawigacja

    private func goToPrevious() {
        guard currentIndex > 0 else { return }
        withAnimation(.easeInOut) { currentIndex -= 1 }
    }

    private func goToNext() {
        guard currentIndex < items.count - 1 else { return }
        withAnimation(.easeInOut) { currentIndex += 1 }
    }

    /// Klik środka pilota / przycisk Play-Pause — co robi, zależy od typu
    /// bieżącej pozycji: dla zdjęcia/Live Photo odtwarza Live Photo, dla
    /// zakończonego wideo odtwarza je ponownie od początku. W trakcie
    /// aktywnego odtwarzania wideo nie robi nic (PlayerLayerView i tak nie
    /// ma własnych kontrolek play/pauza — wideo po prostu leci od razu po
    /// wjechaniu na nie, patrz .task(id: currentIndex) wyżej).
    private func primaryAction() {
        guard let currentItem else { return }
        switch currentItem.type {
        case .photo, .livePhoto:
            playCurrentLivePhotoIfNeeded()
        case .video:
            if videoDidFinish {
                replayVideo()
            }
        }
    }

    // MARK: - Live Photo (patrz MediaPagerView.swift)

    private func playCurrentLivePhotoIfNeeded() {
        guard !isPlayingLive, !isPreparingLiveVideo,
              let currentItem,
              case .livePhoto(let videoURL) = currentItem.type
        else { return }

        isPreparingLiveVideo = true
        Task {
            defer { isPreparingLiveVideo = false }
            do {
                let localURL = try await SMBVideoCache.shared.localFileURL(for: videoURL)
                livePlayer = AVPlayer(url: localURL)
                withAnimation { isPlayingLive = true }
            } catch {
                // Nie udało się pobrać wideo z NAS-a — zostajemy na zdjęciu.
            }
        }
    }

    private func stopLivePhotoPlayback() {
        withAnimation(.easeInOut(duration: 0.5)) {
            isPlayingLive = false
        }
        // Jawne .pause()/.replaceCurrentItem(nil) — patrz komentarz przy
        // .onDisappear/.task(id: currentIndex) o tym, dlaczego samo
        // odrzucenie referencji (poprzednia wersja) nie wystarczało.
        livePlayer?.pause()
        livePlayer?.replaceCurrentItem(with: nil)
        livePlayer = nil
    }

    // MARK: - Wideo (patrz VideoPlaybackView.swift)

    private func stopStreaming() {
        guard let streamLoader else { return }
        self.streamLoader = nil
        Task { await streamLoader.cancelAll() }
    }

    private func replayVideo() {
        guard let videoPlayer else { return }
        videoDidFinish = false
        videoPlayer.seek(to: .zero)
        videoPlayer.play()
    }

    /// Wyciąga klatkę tuż przed końcem — patrz obszerny komentarz przy
    /// captureLastFrame w VideoPlaybackView.swift (identyczna logika).
    private func captureLastFrame(of player: AVPlayer) async {
        guard let currentItem = player.currentItem else { return }
        let asset = currentItem.asset
        let duration = currentItem.duration
        guard duration.isNumeric, duration > .zero else { return }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 3840, height: 2160)

        let targetTime = CMTimeSubtract(duration, CMTime(seconds: 1.0, preferredTimescale: 600))
        let safeTime = CMTimeMaximum(targetTime, .zero)

        guard let cgImage = try? await generator.image(at: safeTime).image else { return }
        lastFrameImage = UIImage(cgImage: cgImage)
    }

    // MARK: - Pre-ładowanie zdjęć (patrz MediaPagerView.swift)

    /// Patrz obszerny komentarz przy updatePrefetchWindow w
    /// MediaPagerView.swift — identyczna logika, tylko pomija indeksy typu
    /// .video (nie ma dla nich czego pre-ładować tym pipeline'em).
    /// Pre-ładowanie sąsiednich zdjęć ODROCZONE, gdy bieżąca pozycja to
    /// wideo — rusza dopiero po jego zakończeniu (patrz .task(id:
    /// currentIndex)) albo po przejściu na zdjęcie. Ściąganie z SMB i
    /// dekodowanie kilku pełnoekranowych zdjęć (HEIC idzie przez ten sam
    /// sprzętowy dekoder HEVC co wideo) w trakcie odtwarzania to jedyna
    /// różnica względem VideoPlaybackView, gdzie to samo wideo leci płynnie,
    /// a tutaj po kilku sekundach zaczynało szarpać.
    private func updatePhotoPrefetchWindowIfNotPlayingVideo() {
        if let currentItem, isVideo(currentItem) { return }
        updatePhotoPrefetchWindow(around: currentIndex)
    }

    private func updatePhotoPrefetchWindow(around index: Int) {
        guard items.indices.contains(index) else { return }

        let lowerBound = max(items.startIndex, index - Self.prefetchRadius)
        let upperBound = min(items.index(before: items.endIndex), index + Self.prefetchRadius)
        let newWindow = Set(lowerBound...upperBound)

        for staleIndex in prefetchedPhotoIndices.subtracting(newWindow) {
            ImageCache.shared.remove(for: items[staleIndex].imageURL, variant: fullScreenVariant)
        }

        for newIndex in newWindow.subtracting(prefetchedPhotoIndices) where newIndex != index {
            let item = items[newIndex]
            guard isPhotoLike(item) else { continue }
            let url = item.imageURL
            Task.detached(priority: .utility) {
                _ = try? await SMBImageCache.shared.thumbnail(for: url, maxPixelSize: AsyncImageSMB.fullScreenMaxPixelSize)
            }
        }

        prefetchedPhotoIndices = newWindow
    }

    private var fullScreenVariant: String {
        SMBImageCache.variant(for: AsyncImageSMB.fullScreenMaxPixelSize)
    }

    // MARK: - Pomocnicze

    private func isPhotoLike(_ item: NASMediaItem) -> Bool {
        switch item.type {
        case .photo, .livePhoto: return true
        case .video: return false
        }
    }

    private func isVideo(_ item: NASMediaItem) -> Bool {
        if case .video = item.type { return true }
        return false
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.title
            configuration.icon
        }
    }
}

private extension LabelStyle where Self == TrailingIconLabelStyle {
    static var trailingIcon: TrailingIconLabelStyle { TrailingIconLabelStyle() }
}
