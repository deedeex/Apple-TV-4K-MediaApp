//
//  LivePhotoViewer.swift
//  MediaApp
//
//  Pojedyncza strona w MediaPagerView. Czysto prezentacyjna — cały stan
//  odtwarzania Live Photo (isPlayingLive/isPreparingVideo/player) żyje w
//  MediaPagerView, bo to ONO trzyma fokus (.focusable/.defaultFocus).
//  .onPlayPauseCommand działa tylko na widoku, który faktycznie ma fokus
//  (lub jego przodkach) — umieszczenie go tutaj, na zagnieżdżonym dziecku,
//  nigdy by nie zadziałało (to był dokładnie ten bug: "klikam Play, nic się
//  nie dzieje"). Poza tym celowo NIE zawiera żadnego Button/ScrollView —
//  cokolwiek fokusowalnego blokowałoby przesuwanie między stronami.
//
//  Z tego samego powodu wideo Live Photo odtwarzamy przez gołe
//  PlayerLayerView, a NIE przez AVKit-owy VideoPlayer — VideoPlayer wciąga
//  własny silnik fokusu/gestów pilota (pasek transportu, swipe w dół =
//  system Now Playing), który potrafi zawiesić się w konflikcie z fokusem
//  wymuszonym ręcznie na rodzicu (patrz komentarz w PlayerLayerView.swift).
//

import SwiftUI
import AVKit

struct LivePhotoViewer: View {
    let item: NASMediaItem
    let isPlayingLive: Bool
    let isPreparingVideo: Bool
    let player: AVPlayer?
    /// Wywoływane, gdy odtwarzanie wideo Live Photo dobiegnie końca —
    /// MediaPagerView resetuje wtedy swój stan i wraca do zdjęcia.
    let onVideoFinished: () -> Void

    private var isLivePhoto: Bool {
        if case .livePhoto = item.type { return true }
        return false
    }

    var body: some View {
        ZStack {
            if !isPlayingLive {
                AsyncImageSMB(url: item.imageURL, contentMode: .fit)
                    .transition(.opacity)

                if isLivePhoto {
                    liveBadge
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(40)
                }
            } else if let player {
                // BEZ .onAppear { player.play() } — patrz obszerny komentarz
                // przy Coordinator w PlayerLayerView.swift.
                PlayerLayerView(player: player)
                    .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { _ in
                        onVideoFinished()
                    }
            }
        }
        .animation(.easeInOut, value: isPlayingLive)
    }

    /// Czysto dekoracyjna plakietka — LiquidGlassCard nie zawiera żadnej
    /// kontrolki, więc nie wchodzi w łańcuch Focus Engine.
    ///
    /// useNativeGlassEffect: true — PUNKTOWY test w JEDNYM z dwóch miejsc
    /// wprost wymienionych w komentarzu w LiquidGlassCard.swift jako
    /// potwierdzone wcześniej zawieszenie pilota na prawdziwym Apple TV
    /// (razem z AdjacentMonthIndicator, który na razie zostaje przy
    /// .ultraThinMaterial — testujemy jedno na raz, żeby w razie problemu
    /// wiedzieć dokładnie, co go spowodowało). WYMAGA bardzo dokładnego
    /// testu na prawdziwym urządzeniu: otwórz Live Photo na pełnym ekranie i
    /// poprzełączaj się (lewo/prawo) między nim a zwykłymi zdjęciami/innymi
    /// Live Photo kilkanaście razy, obserwując responsywność pilota — ta
    /// plakietka pojawia się/znika dokładnie w trakcie takich przejść.
    @ViewBuilder
    private var liveBadge: some View {
        LiquidGlassCard(useNativeGlassEffect: true) {
            HStack {
                if isPreparingVideo {
                    ProgressView()
                } else {
                    Image(systemName: "livephoto.play")
                }
                Text("Live")
            }
            .font(.headline)
            .foregroundStyle(.white)
        }
    }
}
