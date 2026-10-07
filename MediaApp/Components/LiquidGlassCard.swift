//
//  LiquidGlassCard.swift
//  MediaApp
//
//  Karta w stylu szklanym. UWAGA: domyślnie celowo `.ultraThinMaterial`, a NIE
//  natywny modyfikator `.glassEffect` (tvOS 26 „Liquid Glass") — ten ostatni w
//  praktyce konfliktował z Focus Engine wszędzie tam, gdzie taki widok
//  pojawiał się w hierarchii z aktywnym przesuwaniem fokusu (siatka galerii,
//  plakietka „Live" w pełnoekranowym podglądzie, lista folderów w
//  PathPickerView) — obserwowane jako ostrzeżenie "_UIReplicantView as a
//  subview of UIHostingController.view" i realne zawieszenie pilota
//  (_UIFocusEnginePanGestureRecognizer blocking its subgraph…) nawet na
//  prawdziwym Apple TV. Materiał daje wizualnie zbliżony efekt bez tego ryzyka.
//
//  useNativeGlassEffect: punktowy, ostrożny test prawdziwego .glassEffect —
//  włączony NA RAZIE wyłącznie w SettingsView (karta z danymi serwera), bo to
//  jedyne miejsce w aplikacji całkowicie statyczne i z dala od siatki/fokusu
//  w ruchu (żadnego LazyVStack, przewijania ani przejść między kaflami obok).
//  Zanim rozszerzymy to na kafelki/boczną kolumnę — miejsca, które realnie
//  zawieszały pilota — wymaga to potwierdzenia na prawdziwym Apple TV, nie
//  tylko w Symulatorze.
//

import SwiftUI

struct LiquidGlassCard<Content: View>: View {
    private let content: Content
    private let useNativeGlassEffect: Bool

    init(useNativeGlassEffect: Bool = false, @ViewBuilder content: () -> Content) {
        self.useNativeGlassEffect = useNativeGlassEffect
        self.content = content()
    }

    var body: some View {
        Group {
            if useNativeGlassEffect {
                content
                    .padding(30)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            } else {
                content
                    .padding(30)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
        }
        .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
    }
}
