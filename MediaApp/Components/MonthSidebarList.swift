//
//  MonthSidebarList.swift
//  MediaApp
//
//  Boczna kolumna z latami/miesiącami jako filtr nawigacyjny dla zakładek
//  Zdjęcia/Wideo — pozwala przeskoczyć do wybranego okresu, ale w hierarchii
//  widoku nadal renderowany jest naraz tylko JEDEN miesiąc (patrz komentarz
//  w PhotoGalleryView.swift o Focus Engine). Sama lista miesięcy to tylko
//  kilkadziesiąt wierszy, więc jest dla Focus Engine nieszkodliwa.
//
//  Wygląd wierszy — celowo całkowicie płaski i nieanimowany:
//  - BEZ .glassEffect (tvOS 26 „Liquid Glass") — nie przywracać szkła w tej
//    kolumnie. Wcześniejsza próba szklanego PANELU za CAŁĄ listą też została
//    wycofana (renderował się jako mniejszy, "pływający" prostokąt).
//  - BEZ systemowego efektu fokusu (.buttonStyle(.plain)/.card na tvOS
//    powiększają i "unoszą" wiersz z animacją przy każdym ruchu pilota
//    góra/dół) — zamiast tego własny SidebarRowButtonStyle (osobny plik,
//    współdzielony z bocznym menu Ustawień): fokus to tylko płaskie tło,
//    bez skalowania i bez animacji.
//  - Wybrany miesiąc oznaczony WYŁĄCZNIE ptaszkiem i kolorem tekstu, bez
//    stałego tła — inaczej przy przewijaniu listy widać naraz dwa
//    podświetlenia (wybrany + z fokusem), co myli.
//  - Miesiące pogrupowane w sekcje lat: rok raz jako nagłówek (niefokusowalny
//    Text, więc pilot góra/dół go po prostu przeskakuje), w wierszach sama
//    nazwa miesiąca. Grupa "Nieznana data" (year == nil) ląduje na końcu we
//    własnej sekcji bez nagłówka.
//  - Ta sama grubość czcionki dla wszystkich wierszy — pogrubiony wybrany
//    wiersz plus ptaszek nie mieścił się w szerokości i .minimumScaleFactor
//    zmniejszał mu czcionkę względem pozostałych.
//
//  ScrollView + ręczne wiersze zamiast List — List (na tvOS wspierany przez
//  UICollectionView pod spodem) ma udokumentowaną skłonność do samodzielnego,
//  natywnego (poniżej SwiftUI @FocusState) przejmowania fokusu na swój
//  pierwszy wiersz przy (re)zamontowaniu. Ostatecznie NIE był to główny
//  winowajca fokusu uciekającego z paska zakładek (patrz obszerny komentarz
//  przy entryFocus w PhotoGalleryView.swift o rzeczywistej przyczynie), ale
//  zmiana zostaje — usuwa jedno realne źródło niepewności i jest spójna z
//  resztą aplikacji: siatki (PhotoMonthGridView i inne) od dawna są ręcznymi
//  wierszami z tego samego, już wcześniej sprawdzonego powodu.
//

import SwiftUI

struct MonthSidebarList: View {
    let groups: [MonthGroup]
    let selectedGroupID: String?
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(yearSections, id: \.year) { section in
                    if let year = section.year {
                        Text(String(year))
                            .font(.system(size: 38, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.top, section.year == yearSections.first?.year ? 0 : 24)
                            .padding(.bottom, 4)
                    }
                    ForEach(section.groups) { group in
                        row(for: group)
                    }
                }
            }
        }
    }

    /// Kolejne miesiące tego samego roku zebrane w sekcje. `groups` jest już
    /// posortowane malejąco (MediaGrouping.byMonth), więc wystarczy łączyć
    /// sąsiednie pozycje — kilkadziesiąt elementów, liczone na bieżąco.
    private var yearSections: [(year: Int?, groups: [MonthGroup])] {
        var sections: [(year: Int?, groups: [MonthGroup])] = []
        for group in groups {
            if let last = sections.indices.last, sections[last].year == group.year {
                sections[last].groups.append(group)
            } else {
                sections.append((year: group.year, groups: [group]))
            }
        }
        return sections
    }

    @ViewBuilder
    private func row(for group: MonthGroup) -> some View {
        let isSelected = group.id == selectedGroupID
        Button {
            onSelect(group.id)
        } label: {
            HStack {
                // Jawne rozmiary (nie .title3/domyślny) skalowane w tym
                // samym stosunku 5:6 co szerokość kolumny (520→430, patrz
                // PhotoGalleryView.swift). .lineLimit(1) +
                // .minimumScaleFactor tylko jako zabezpieczenie dla
                // wyjątkowo długich nazw — patrz nagłówek pliku.
                Text(group.monthName)
                    .font(.system(size: 32))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer()
                Text("\(group.items.count)")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                // Stała szerokość slotu na ptaszek — żeby liczby
                // były wyrównane niezależnie od zaznaczenia.
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
                    .opacity(isSelected ? 1 : 0)
            }
            .foregroundStyle(isSelected ? Color.accentColor : .primary)
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
        }
        .buttonStyle(SidebarRowButtonStyle())
    }
}
