//
//  AdjacentMonthIndicator.swift
//  MediaApp
//
//  Czysto informacyjna plakietka "Poprzedni/Następny miesiąc" pokazywana na
//  górze/dole siatki miesiąca (patrz PhotoMonthGridView/VideoMonthGridView),
//  gdy fokus dotarł do krawędzi galerii — albo cała zawartość miesiąca
//  mieści się na jednym ekranie — i sąsiedni miesiąc rzeczywiście istnieje.
//  Celowo nieklikalna (.allowsHitTesting(false)) — nie zmienia mechaniki
//  przechodzenia między miesiącami, tylko o niej informuje.
//
//  Próba zamiany wariantu .previous na prawdziwy, fokusowalny Button (żeby
//  swipe w górę z pierwszego wiersza trafiał w NIEGO zamiast uciekać do
//  paska zakładek/bocznej listy) WYCOFANA — dawała NIEDETERMINISTYCZNE
//  zachowanie (czasem ucieczka do paska, czasem do bocznej listy, fokus
//  nigdy faktycznie nie trafiał w plakietkę), gorsze niż stabilny,
//  przewidywalny stan sprzed próby. Patrz obszerny komentarz przy
//  .onMoveCommand w PhotoMonthGridView.swift o całej historii prób
//  (UIFocusGuide, ten Button) i czemu zostały porzucone.
//
//  .ultraThinMaterial zamiast .glassEffect — ten widok był już wcześniej
//  oznaczony jako NAJBARDZIEJ ryzykowny test .glassEffect w całej aplikacji
//  (łączy statyczny .glassEffect z warunkowym wstawianiem/usuwaniem
//  DOKŁADNIE w momencie, gdy fokus dociera do krawędzi siatki — Focus
//  Engine robi wtedy własny snapshot do przejścia, co gdzie indziej w tej
//  appce już raz dało realne zawieszenie pilota). Ta zmiana materiału
//  zostaje nawet po wycofaniu próby z Buttonem — czysty, bezkosztowy
//  spadek ryzyka.
//

import SwiftUI

struct AdjacentMonthIndicator: View {
    enum Direction {
        case previous
        case next

        var title: String {
            switch self {
            case .previous: return "Poprzedni miesiąc"
            case .next: return "Następny miesiąc"
            }
        }

        var systemImage: String {
            switch self {
            case .previous: return "chevron.up"
            case .next: return "chevron.down"
            }
        }
    }

    let direction: Direction

    var body: some View {
        Label(direction.title, systemImage: direction.systemImage)
            .font(.headline)
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 4)
            .allowsHitTesting(false)
            .focusable(false)
            .accessibilityHidden(true)
    }
}
