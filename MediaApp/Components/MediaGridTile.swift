//
//  MediaGridTile.swift
//  MediaApp
//
//  Pojedynczy kafelek siatki galerii. Celowo osobny widok (a nie inline
//  domknięcie w ForEach), ale BEZ własnej logiki podświetlania na fokus —
//  .buttonStyle(.card) już samo daje natywny efekt uniesienia/blasku na
//  tvOS. Wcześniej dokładaliśmy tu jeszcze ręczny scaleEffect/padding i
//  WARUNKOWO wstawiany/usuwany (if isFocused) podwidok z .glassEffect w tle
//  — czyli zmienialiśmy strukturę hierarchii widoku dokładnie w momencie,
//  gdy Focus Engine robi własny snapshot do przejścia. To powodowało
//  ostrzeżenie "_UIReplicantView as a subview of UIHostingController.view"
//  i realne zawieszenie pilota (_UIFocusEnginePanGestureRecognizer blocking
//  its subgraph…) przy swipe'ach — również na fizycznym Apple TV, nie tylko
//  w Symulatorze. Stąd zostajemy przy samym natywnym stylu .card.
//
//  Plakietka poniżej: PUNKTOWY, ostrożny test natywnego .glassEffect (tvOS 26
//  „Liquid Glass") zamiast .ultraThinMaterial — patrz obszerny komentarz w
//  LiquidGlassCard.swift o tym, dlaczego to w ogóle ryzykowne (.glassEffect
//  potrafiło wywoływać zawieszenie pilota nawet jako widok statyczny, m.in.
//  właśnie w siatce galerii). Ta plakietka to najmniej ryzykowny kandydat w
//  całej siatce: obecność zależy WYŁĄCZNIE od typu pliku (wideo/Live Photo),
//  nie od stanu fokusu — nie znika/pojawia się w trakcie przesuwania fokusu
//  między kaflami (w przeciwieństwie do AdjacentMonthIndicator, który się
//  warunkowo wstawia/usuwa dokładnie w takim momencie — tam .glassEffect
//  NIE jest jeszcze testowany). Wymaga potwierdzenia na prawdziwym Apple TV.
//

import SwiftUI

struct MediaGridTile: View {
    /// Rozmiar miniatury kafelka — współdzielony z pre-generowaniem
    /// miniatur nowych plików (MediaLibraryStore), żeby trafiało w ten sam
    /// wariant cache'u, którego potem szuka kafelek.
    static let thumbnailMaxPixelSize: CGFloat = 420

    let item: NASMediaItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomTrailing) {
                // .fill (nie .fit) — kafelek to zawsze kwadrat (aspectRatio 1
                // niżej), a większość zdjęć/wideo nie jest kwadratowa, więc
                // .fit zostawiał szare pasy tła-placeholder u góry/dołu (kadr
                // poziomy) albo po bokach (kadr pionowy). .fill "przybliża"
                // zdjęcie tak, żeby wypełniło cały kwadrat, przycinając
                // nadmiar dłuższego boku — .clipShape niżej i tak przycina do
                // zaokrąglonego kwadratu, więc same krawędzie i tak nigdy nie
                // były w pełni widoczne.
                AsyncImageSMB(url: item.imageURL, maxPixelSize: Self.thumbnailMaxPixelSize, contentMode: .fill)
                    .aspectRatio(1, contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                if let badge {
                    // Jeszcze ~20% mniejsza niż poprzednia iteracja (.footnote
                    // → jawny rozmiar 18pt) i jeszcze bliżej samego rogu, na
                    // wyraźną prośbę.
                    Image(systemName: badge)
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                        .padding(5)
                        .glassEffect(.regular, in: Circle())
                        .padding(3)
                }
            }
        }
        .buttonStyle(.card)
    }

    private var badge: String? {
        switch item.type {
        case .photo: return nil
        case .video: return "play.fill"
        case .livePhoto: return "livephoto"
        }
    }
}
