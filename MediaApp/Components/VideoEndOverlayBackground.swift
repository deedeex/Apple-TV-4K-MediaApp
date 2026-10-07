//
//  VideoEndOverlayBackground.swift
//  MediaApp
//
//  Wspólne tło nakładki końca wideo (Poprzednie / Odtwórz ponownie /
//  Następne) w AllMediaPagerView i VideoPlaybackView. Bez niego przyciski
//  leżały bezpośrednio na ostatniej klatce wideo i w zależności od jej
//  jasności bywały prawie niewidoczne (szczególnie przygaszone .secondary
//  "Poprzednie"/"Następne"). Jedna szara, zaokrąglona po bokach kapsuła za
//  wszystkimi trzema — stała, niezależna od treści wideo. Celowo płaskie
//  tło zamiast .glassEffect: szkło przepuszcza i soczewkuje tło, więc nie
//  dawałoby gwarantowanego kontrastu.
//

import SwiftUI

extension View {
    func videoEndOverlayBackground() -> some View {
        padding(.horizontal, 48)
            .padding(.vertical, 24)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(white: 0.18).opacity(0.85))
            )
    }
}
