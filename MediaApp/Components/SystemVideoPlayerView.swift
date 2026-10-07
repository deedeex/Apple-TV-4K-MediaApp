//
//  SystemVideoPlayerView.swift
//  MediaApp
//
//  AVPlayerViewController BEZ żadnych kontrolek i bez obsługi pilota — do
//  pełnoekranowego wideo w zakładce Wszystko (AllMediaPagerView).
//
//  Dlaczego nie PlayerLayerView (goły AVPlayerLayer): przy wymagających
//  plikach (np. iPhone 4K 60 kl./s HLG HDR, ~100 Mb/s) obraz z gołej
//  warstwy osadzonej w hierarchii SwiftUI zaczynał po ~3 s szarpać, podczas
//  gdy ten sam plik w zakładce Wideo (VideoPlayer = AVPlayerViewController)
//  leciał płynnie. Pomiary (tymczasowe logi) wykluczyły wszystko po stronie
//  aplikacji (brak I/O w tle, brak przerysowań, brak zacięć głównego
//  wątku, brak stalli) — została tylko różnica w ścieżce renderowania:
//  AVPlayerViewController ma zoptymalizowaną systemową ścieżkę wyświetlania
//  wideo, goła warstwa jest składana razem z resztą UI na GPU (przy
//  Apple TV w stanie termicznym "serious" to już się nie mieściło).
//
//  Dlaczego nie VideoPlayer (SwiftUI): patrz komentarz na górze
//  PlayerLayerView.swift — VideoPlayer z kontrolkami rejestruje własne gesty
//  pilota (pasek transportu, Now Playing, pan gesture focus engine) i w
//  pagerze z wymuszonym fokusem na jednym Buttonie oba silniki fokusu
//  walczyły o input, zawieszając pilota. Tu kontrolki są wyłączone
//  (showsPlaybackControls = false — bez paska transportu nie ma jego
//  gestów), widok kontrolera ma wyłączoną interakcję (UIKit nie daje
//  fokusu widokom z isUserInteractionEnabled == false), a po stronie
//  SwiftUI dodatkowo .allowsHitTesting(false)/.focusable(false) — cały
//  input zostaje przy Buttonie pagera.
//
//  Live Photo nadal używa PlayerLayerView — to krótkie klipy niskiej
//  rozdzielczości, bez tego problemu.
//

import SwiftUI
import AVKit

struct SystemVideoPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspect
        controller.view.isUserInteractionEnabled = false
        controller.view.backgroundColor = .black
        controller.player = player
        context.coordinator.ensureObserving(controller, player: player)
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
        }
        context.coordinator.ensureObserving(controller, player: player)
    }

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        controller.player = nil
        coordinator.invalidate()
    }

    /// Ten sam mechanizm co Coordinator w PlayerLayerView.swift: play()
    /// dopiero, gdy pierwsza klatka jest faktycznie gotowa do wyświetlenia
    /// (isReadyForDisplay), a nie z .onAppear — patrz obszerny komentarz
    /// tam o wyścigu "dźwięk bez obrazu".
    final class Coordinator {
        private var observation: NSKeyValueObservation?
        private weak var observedPlayer: AVPlayer?

        func ensureObserving(_ controller: AVPlayerViewController, player: AVPlayer) {
            guard observedPlayer !== player else { return }
            observation?.invalidate()
            observedPlayer = player
            observation = controller.observe(\.isReadyForDisplay, options: [.new, .initial]) { _, change in
                guard change.newValue == true else { return }
                player.play()
            }
        }

        func invalidate() {
            observation?.invalidate()
            observation = nil
            observedPlayer = nil
        }
    }
}
