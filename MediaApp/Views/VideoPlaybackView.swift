//
//  VideoPlaybackView.swift
//  MediaApp
//
//  Pełnoekranowe odtwarzanie wideo z zakładki Wideo (nie Live Photo — tym
//  zajmuje się LivePhotoViewer). Prezentowane przez .fullScreenCover, więc
//  Menu/< na pilocie zamyka je natywnie i wraca do siatki.
//
//  Dostaje całą listę wideo, nie tylko jedno — po dojściu odtwarzania do
//  końca AVPlayer po prostu się zatrzymuje, więc kolejne kliknięcie w prawo
//  (próba przewinięcia o 10s) nic by nie zrobiło. Zamiast tego, gdy wideo
//  się skończy, znika VideoPlayer, a jego miejsce zajmuje zwykła nakładka
//  SwiftUI z fokusem: lewo/prawo przełącza na poprzednie/kolejne wideo w
//  bibliotece, a przycisk Play/Pause albo kliknięcie środkowe (przycisk
//  „Odtwórz ponownie”) odtwarza bieżące wideo od nowa.
//
//  VideoPlayer MUSI zniknąć z hierarchii (a nie tylko zostać przysłonięty),
//  bo to osobny silnik fokusu (AVPlayerViewController pod spodem) — trzymanie
//  go zamontowanego obok focusable nakładki SwiftUI prowadzi do realnego
//  zawieszenia pilota (_UIFocusEnginePanGestureRecognizer blokuje się na
//  dziesiątki sekund, próbując pogodzić dwie hierarchie fokusu naraz).
//

import SwiftUI
import AVKit

struct VideoPlaybackView: View {
    let items: [NASMediaItem]

    @State private var currentIndex: Int
    @State private var player: AVPlayer?
    /// Źródło danych odtwarzacza (strumieniowanie z NAS-a) — patrz
    /// SMBStreamingAssetLoader.makePlayer. Trzymane, bo AVFoundation trzyma
    /// je tylko słabo, i anulowane przy zmianie wideo/zamknięciu.
    @State private var streamLoader: SMBStreamingAssetLoader?
    @State private var errorMessage: String?
    @State private var didFinishPlaying = false
    /// Ostatnia klatka odtwarzanego wideo — pokazywana w tle nakładki końca
    /// odtwarzania ZAMIAST czarnego ekranu. Wyciągana z tego samego AVAsset
    /// co odtwarzanie (strumieniowanego z NAS-a — doczytuje tylko okolice
    /// końca pliku, które AVPlayer i tak właśnie przeczytał).
    @State private var lastFrameImage: UIImage?

    @FocusState private var isEndOverlayFocused: Bool

    init(items: [NASMediaItem], initialItem: NASMediaItem) {
        self.items = items
        _currentIndex = State(initialValue: items.firstIndex(where: { $0.id == initialItem.id }) ?? 0)
    }

    private var currentItem: NASMediaItem? {
        items.indices.contains(currentIndex) ? items[currentIndex] : nil
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if didFinishPlaying {
                if let lastFrameImage {
                    // Color jako RODZEŃSTWO w ZStacku (nie .overlay doczepiony
                    // do już dopasowanego obrazu) — Color zawsze wypełnia
                    // CAŁĄ dostępną przestrzeń, więc przyciemnienie pokrywa
                    // dokładnie ten sam obszar co obraz, niezależnie od jego
                    // proporcji. Poprzednio .overlay(...) doczepiony PO
                    // .aspectRatio(fit) + .ignoresSafeArea() na obrazie
                    // portretowym (pillarboxed) dawał niedopasowany rozmiar —
                    // przyciemnienie pokrywało tylko część kadru, zostawiając
                    // widoczny "szew" z jaśniejszym paskiem z boku.
                    ZStack {
                        // .fit (nie .fill), tak samo jak VideoPlayer wyżej —
                        // żeby przejście do nakładki końca nie "doskakiwało"
                        // kadru przez inne przycięcie niż w trakcie odtwarzania.
                        Image(uiImage: lastFrameImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                        // Przyciemnienie pod nakładką — sama klatka wideo
                        // bywa zbyt jasna/kontrastowa, żeby czytelnie
                        // wyświetlić na niej etykiety/przycisk poniżej.
                        Color.black.opacity(0.35)
                    }
                    .ignoresSafeArea()
                }
                endOfPlaybackOverlay
            } else if let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onAppear {
                        player.automaticallyWaitsToMinimizeStalling = true
                        player.play()
                    }
            } else if let errorMessage {
                // useNativeGlassEffect: true — statyczny ekran błędu.
                LiquidGlassCard(useNativeGlassEffect: true) {
                    VStack(spacing: 16) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.largeTitle)
                        Text(errorMessage)
                            .multilineTextAlignment(.center)
                    }
                }
            } else {
                ProgressView("Wczytywanie wideo…")
            }
        }
        .onMoveCommand { direction in
            guard didFinishPlaying else { return }
            switch direction {
            case .left: goToPrevious()
            case .right: goToNext()
            default: break
            }
        }
        .onPlayPauseCommand {
            guard didFinishPlaying else { return }
            replay()
        }
        .onChange(of: didFinishPlaying) { _, finished in
            isEndOverlayFocused = finished
        }
        .task(id: currentIndex) { await load() }
        .onDisappear {
            player?.pause()
            stopStreaming()
        }
    }

    @ViewBuilder
    private var endOfPlaybackOverlay: some View {
        VStack {
            Spacer()
            HStack(spacing: 40) {
                if currentIndex > 0 {
                    Label("Poprzednie", systemImage: "chevron.left")
                        .foregroundStyle(.secondary)
                }
                Button(action: replay) {
                    Label("Odtwórz ponownie", systemImage: "arrow.counterclockwise")
                }
                .focused($isEndOverlayFocused)
                if currentIndex < items.count - 1 {
                    Label("Następne", systemImage: "chevron.right")
                        .labelStyle(.trailingIcon)
                        .foregroundStyle(.secondary)
                }
            }
            .videoEndOverlayBackground()
            .padding(.bottom, 60)
        }
    }

    private func goToPrevious() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
    }

    private func goToNext() {
        guard currentIndex < items.count - 1 else { return }
        currentIndex += 1
    }

    private func replay() {
        guard let player else { return }
        didFinishPlaying = false
        player.seek(to: .zero)
        player.play()
    }

    private func load() async {
        errorMessage = nil
        didFinishPlaying = false
        lastFrameImage = nil
        player?.pause()
        player = nil
        stopStreaming()

        guard let currentItem else { return }

        // Strumieniowo z NAS-a zamiast pobierania całego pliku z góry —
        // patrz SMBStreamingAssetLoader.makePlayer. Bez pre-ładowania
        // następnego wideo (dawniej prefetchNextVideo): pełne pobranie
        // innego pliku zajmowałoby na kilka sekund wspólną, zserializowaną
        // bramkę SMB (SMBIOGate) i wstrzymywało doczytywanie bieżącego.
        let (newPlayer, loader) = SMBStreamingAssetLoader.makePlayer(for: currentItem.imageURL)
        streamLoader = loader
        player = newPlayer

        let failureWatch = Task {
            guard let item = newPlayer.currentItem,
                  let message = await SMBStreamingAssetLoader.failureMessage(of: item)
            else { return }
            errorMessage = message
            player = nil
        }
        defer { failureWatch.cancel() }

        for await _ in NotificationCenter.default.notifications(
            named: .AVPlayerItemDidPlayToEndTime,
            object: newPlayer.currentItem
        ) {
            didFinishPlaying = true
            await captureLastFrame(of: newPlayer)
        }
    }

    private func stopStreaming() {
        guard let streamLoader else { return }
        self.streamLoader = nil
        Task { await streamLoader.cancelAll() }
    }

    /// Wyciąga klatkę tuż przed końcem odtwarzanego assetu i wstawia do
    /// lastFrameImage. Błąd tutaj nie jest krytyczny — nakładka końca
    /// odtwarzania po prostu zostaje na czarnym tle, tak jak wcześniej.
    ///
    /// Odsunięcie od `duration` to CAŁA SEKUNDA, nie ułamek — przy mniejszym
    /// odstępie (próbowane: 0.2s) AVAssetImageGenerator potrafi zwrócić
    /// klatkę częściowo zdekodowaną/"rozmazaną" (widoczne jako ciemny obszar
    /// po jednej stronie kadru, poprawny pasek po drugiej): tak blisko
    /// samego końca pliku dekoder czasem nie ma kompletnych danych
    /// referencyjnych (klatki P/B odwołujące się do sąsiednich klatek), żeby
    /// poprawnie złożyć cały obraz. Sekunda zapasu daje mu margines na
    /// trafienie w czystą, w pełni zdekodowalną klatkę.
    private func captureLastFrame(of player: AVPlayer) async {
        guard let currentItem = player.currentItem else { return }
        let asset = currentItem.asset
        let duration = currentItem.duration
        guard duration.isNumeric, duration > .zero else { return }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        // Apple TV 4K i tak nie wyświetli więcej niż natywną rozdzielczość
        // ekranu — to ograniczenie nic nie kosztuje jakościowo, a przy
        // okazji ogranicza ryzyko nietypowego formatu pikseli przy
        // dekodowaniu z bardzo wysokorozdzielczych/HDR źródeł.
        generator.maximumSize = CGSize(width: 3840, height: 2160)

        let targetTime = CMTimeSubtract(duration, CMTime(seconds: 1.0, preferredTimescale: 600))
        let safeTime = CMTimeMaximum(targetTime, .zero)

        guard let cgImage = try? await generator.image(at: safeTime).image else { return }
        lastFrameImage = UIImage(cgImage: cgImage)
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
