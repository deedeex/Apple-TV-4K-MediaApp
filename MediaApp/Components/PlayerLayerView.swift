//
//  PlayerLayerView.swift
//  MediaApp
//
//  Gołe odtwarzanie AVPlayer przez AVPlayerLayer — bez żadnego AVKit-owego
//  UI. AVKit-owy `VideoPlayer` (AVPlayerViewController pod spodem) rejestruje
//  własne gesty pilota (pasek transportu, swipe w dół pokazujący system Now
//  Playing przez PlayerRemoteXPC, pan gesture focus engine na potrzeby
//  przewijania). Gdy taki widok siedzi w hierarchii obok/pod widokiem
//  SwiftUI, który sam ręcznie zarządza fokusem (np. MediaPagerView z
//  wymuszonym .defaultFocus), oba silniki fokusu/gestów walczą o ten sam
//  input i potrafią się zawiesić na dziesiątki sekund
//  (_UIFocusEnginePanGestureRecognizer blocking its subgraph…).
//
//  Tu nie potrzebujemy żadnych kontrolek (Live Photo odtwarza się samo, bez
//  scrubbingu), więc zamiast AVKit używamy czystego CALayer — nie uczestniczy
//  w Focus Engine i nie ma własnych gestów, więc nie ma z czym konkurować.
//

import SwiftUI
import AVKit

struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        context.coordinator.ensureObserving(view.playerLayer, player: player)
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        uiView.playerLayer.player = player
        context.coordinator.ensureObserving(uiView.playerLayer, player: player)
    }

    // Bez tego SwiftUI, usuwając ten widok z hierarchii (zamknięcie
    // pełnoekranowego podglądu, zmiana pozycji w AllMediaPagerView), po
    // prostu pozwala ARC zwolnić PlayerContainerView — AVPlayerLayer, który
    // FAKTYCZNIE jest podłączony do okna/potoku renderującego, nigdy nie
    // dostaje jawnego `.player = nil`. Przy AVKit-owym VideoPlayer ten
    // krok robi sam framework; przy gołym AVPlayerLayer (patrz komentarz na
    // górze pliku o tym, czemu w ogóle) trzeba go zrobić ręcznie.
    static func dismantleUIView(_ uiView: PlayerContainerView, coordinator: Coordinator) {
        uiView.playerLayer.player = nil
        coordinator.invalidate()
    }

    final class PlayerContainerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    }

    // Odpala player.play() dopiero, gdy AVPlayerLayer.isReadyForDisplay
    // faktycznie jest true (KVO) — NIE z .onAppear po stronie wywołującej
    // (jak było wcześniej, w AllMediaPagerView i LivePhotoViewer). .onAppear
    // odpala się w momencie, w którym SwiftUI uznaje widok za "pojawiony",
    // co NIE gwarantuje, że leżąca pod spodem warstwa AVPlayerLayer jest już
    // faktycznie podłączona do okna z prawidłowym układem — to wyścig, który
    // czasem wygrywał (wideo odtwarzało się normalnie), a czasem przegrywał:
    // audio grało, ale obraz zamarzał na pierwszej klatce, bo .play() ruszał
    // dekodowanie/renderowanie zanim warstwa była naprawdę gotowa
    // przyjmować klatki (potwierdzone przez użytkownika jako niedeterministyczne
    // — czasem działa za pierwszym razem, czasem dopiero po ponownym wejściu).
    // isReadyForDisplay to właśnie ten sygnał "warstwa naprawdę gotowa".
    final class Coordinator {
        private var observation: NSKeyValueObservation?
        private weak var observedPlayer: AVPlayer?

        func ensureObserving(_ layer: AVPlayerLayer, player: AVPlayer) {
            guard observedPlayer !== player else { return }
            observation?.invalidate()
            observedPlayer = player
            // .initial — na wypadek gdyby warstwa była już gotowa w
            // momencie podpięcia obserwacji (np. przy replayVideo(), gdzie
            // ten sam AVPlayer bywa ponownie podłączany do nowej warstwy).
            observation = layer.observe(\.isReadyForDisplay, options: [.new, .initial]) { _, change in
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
