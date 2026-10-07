//
//  PhotoGalleryView.swift
//  MediaApp
//
//  Dane i miniatury pochodzą ze współdzielonego MediaLibraryStore
//  (wstrzykniętego z MainTabView), który zaczyna skanować NAS od razu po
//  zalogowaniu, a nie dopiero po wejściu w tę zakładkę — patrz komentarz w
//  MediaLibraryStore.swift o tym, dlaczego lokalny @State tutaj wcześniej
//  powodował ponowny pełny skan NAS-a przy każdym powrocie do zakładki.
//

import SwiftUI

struct PhotoGalleryView: View {
    @EnvironmentObject private var session: SessionManager
    @EnvironmentObject private var library: MediaLibraryStore

    @State private var selectedGroupID: String?
    /// `nil` domyślnie — patrz obszerny komentarz przy GalleryEntryFocus w
    /// MonthGroup.swift o tym, dlaczego to musi być opcjonalne, nie
    /// `.start`: zwykłe przełączenie zakładki na górnym pasku też odtwarza
    /// ten widok od zera (więc ta wartość też resetuje się do stanu
    /// początkowego), a `nil` jest jedynym sposobem odróżnienia "widok się
    /// po prostu pojawił" od "użytkownik jawnie nawigował do innego
    /// miesiąca" w PhotoMonthGridView.
    @State private var entryFocus: GalleryEntryFocus?
    @State private var isTransitioningMonth = false
    @Namespace private var focusNamespace
    /// Raportowane przez PhotoMonthGridView (onFocusedRowChange) wyłącznie do
    /// wyliczenia widoczności plakietki AdjacentMonthIndicator — renderowanej
    /// TUTAJ, poza PhotoMonthGridView, celowo (patrz komentarz przy
    /// onFocusedRowChange w PhotoMonthGridView.swift).
    @State private var focusedRowIndex: Int?
    @State private var rowCount = 0

    /// Biblioteka pogrupowana wg miesiąca — patrz MonthGroup.swift. Konieczne
    /// przy bardzo dużych bibliotekach: stack trace z realnego zawieszenia
    /// pilota (CPU 100%, `bt` w momencie freeze'u) pokazał wątek utknięty
    /// CAŁKOWICIE wewnątrz UIKit-owego Focus Engine (_UIFocusRegionEvaluator/
    /// _UIFocusMap, zero klatek z MediaApp) — jego algorytm oceny przesłaniania
    /// regionów fokusa nie skaluje się do setek tysięcy kafelków w jednym,
    /// ciągłym przewijanym widoku, niezależnie od .focusSection() w środku
    /// (próbowane wcześniej, nie wystarczyło). W hierarchii widoku może więc
    /// naraz istnieć tylko JEDEN miesiąc — stąd siatka pokazuje zawsze
    /// pojedynczy wybrany MonthGroup (patrz PhotoMonthGridView), a lista
    /// wszystkich miesięcy jest tylko bocznym filtrem (MonthSidebarList),
    /// nie osobnym ekranem z pełną biblioteką.
    ///
    /// Samo grupowanie liczone jest w MediaLibraryStore (patrz komentarz przy
    /// photoMonthGroups tam) — TUTAJ to tylko odczyt gotowej, scache'owanej
    /// tablicy, a nie MediaGrouping.byMonth(library.photos) na nowo. To drugie
    /// (poprzednia wersja tego pliku) kosztowało niewiele przy pojedynczym
    /// wywołaniu, ale onFocusedRowChange ustawia tu @State przy KAŻDEJ zmianie
    /// wiersza z fokusem w siatce — czyli praktycznie przy każdym ruchu
    /// pilota góra/dół, nawet w obrębie tych samych, już wyrenderowanych 25
    /// kafelków — co przerenderowywało ten widok i przeliczało grupowanie
    /// całej (potencjalnie dziesiątki tysięcy pozycji) biblioteki od zera,
    /// kilka razy na przerenderowanie (selectedGroup/hasNextMonth/
    /// hasPreviousMonth/MonthSidebarList niżej), stąd 100% CPU i zacinanie
    /// fokusu mimo w pełni załadowanych miniatur.
    private var monthGroups: [MonthGroup] {
        library.photoMonthGroups
    }

    private var selectedGroup: MonthGroup? {
        monthGroups.first { $0.id == selectedGroupID } ?? monthGroups.first
    }

    private var selectedGroupIndex: Int? {
        monthGroups.firstIndex { $0.id == selectedGroup?.id }
    }

    private var hasNextMonth: Bool {
        guard let selectedGroupIndex else { return false }
        return monthGroups.indices.contains(selectedGroupIndex + 1)
    }

    private var hasPreviousMonth: Bool {
        guard let selectedGroupIndex else { return false }
        return monthGroups.indices.contains(selectedGroupIndex - 1)
    }

    private var fitsOnOneScreen: Bool {
        rowCount > 0 && rowCount <= GalleryLayout.maxRowsPerScreen
    }

    private var showPreviousMonthIndicator: Bool {
        hasPreviousMonth && (fitsOnOneScreen || focusedRowIndex == 0)
    }

    private var showNextMonthIndicator: Bool {
        hasNextMonth && (fitsOnOneScreen || focusedRowIndex == rowCount - 1)
    }

    var body: some View {
        // BEZ NavigationStack — nie ma tu ani jednego .navigationDestination/
        // NavigationLink, więc był to czysty, pusty wrapper. Podejrzenie
        // (nie potwierdzone jako jedyna przyczyna — patrz komentarz przy
        // entryFocus wyżej o rzeczywistym źródle problemu): NavigationStack
        // jest wspierany przez UINavigationController, który przy KAŻDYM
        // (re)montowaniu (a to dzieje się przy każdym przełączeniu zakładki
        // na górnym pasku) sam, na poziomie UIKit, wykonuje własne
        // wyszukiwanie "initial focus" w swojej zawartości — CAŁKOWICIE
        // niezależnie od SwiftUI @FocusState/.defaultFocus. To tłumaczyłoby,
        // czemu żadna poprawka na poziomie @FocusState nie miała wpływu na
        // fokus uciekający z paska zakładek w głąb siatki przy przełączaniu.
        content
            .onChange(of: library.photos.isEmpty) { _, isEmpty in
                if !isEmpty {
                    selectedGroupID = monthGroups.first?.id
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if library.isLoading {
            ProgressView("Skanowanie NAS w poszukiwaniu zdjęć i wideo…\nTo może chwilę potrwać przy dużej bibliotece.")
                .multilineTextAlignment(.center)
        } else if let errorMessage = library.errorMessage {
            // useNativeGlassEffect: true — statyczny ekran błędu.
            LiquidGlassCard(useNativeGlassEffect: true) {
                VStack(spacing: 16) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.largeTitle)
                    Text(errorMessage)
                        .multilineTextAlignment(.center)
                    Button("Spróbuj ponownie") {
                        library.reload()
                    }
                    Button("Zmień ustawienia serwera") {
                        session.beginEditingSetup()
                    }
                }
            }
        } else if library.photos.isEmpty {
            Text("Brak zdjęć w tym katalogu na NAS (razem z podfolderami).")
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 0) {
                MonthSidebarList(groups: monthGroups, selectedGroupID: selectedGroupID) { id in
                    entryFocus = .start
                    selectedGroupID = id
                }
                // 430 (nie 520) — proporcjonalnie zmniejszone w stosunku 5:6,
                // odkąd siatka ma 6 kolumn zamiast 5 (patrz columnCount w
                // PhotoMonthGridView.swift), żeby zrobić miejsce na szóstą
                // kolumnę kafelków.
                .frame(width: 430)
                .focusSection()
                // Dodatkowe zabezpieczenie na czas przełączania miesiąca:
                // przy wjeździe "od dołu" (entryFocus == .end) fokus ląduje
                // na właściwym kaflu dopiero po scrollTo w PhotoMonthGridView
                // (LazyVStack musi najpierw wyrenderować ostatni wiersz) —
                // w tej krótkiej przerwie boczna lista nie może przejąć
                // fokusu. onFocusReady zdejmuje blokadę, gdy siatka ma już
                // ostateczny fokus.
                .disabled(isTransitioningMonth)

                Group {
                    if let selectedGroup {
                        // CELOWO bez .id(selectedGroup.id) — PhotoMonthGridView
                        // ma być tym SAMYM widokiem przy zmianie miesiąca
                        // (patrz .task(id:) w środku), żeby aktualnie
                        // sfokusowany kafelek nigdy nie znikał bez
                        // zastępstwa. Zniszczenie i odtworzenie całego
                        // widoku (jak było wcześniej) dawało Focus Engine
                        // moment "nic nie ma fokusu", w którym uciekał do
                        // paska zakładek/bocznej listy.
                        PhotoMonthGridView(
                            group: selectedGroup,
                            entryFocus: entryFocus,
                            onReachEnd: goToNextMonth,
                            onReachStart: goToPreviousMonth,
                            onFocusReady: { isTransitioningMonth = false },
                            onFocusedRowChange: { row, count in
                                focusedRowIndex = row
                                rowCount = count
                            }
                        )
                    }
                }
                .frame(maxWidth: .infinity)
                // BEZ .prefersDefaultFocus — tvOS stosował je nie tylko przy
                // pierwszym wejściu do zakładki, ale przy KAŻDEJ jej
                // aktywacji (przełączanie zakładek lewo/prawo na górnym
                // pasku), więc fokus od razu "spadał" z paska na siatkę,
                // uniemożliwiając swobodne przeglądanie samych zakładek. Bez
                // tego fokus zostaje na pasku, dopóki nie naciśniesz w dół
                // celowo — silnik fokusu sam wtedy wybierze najbliższy
                // geometrycznie element (siatka albo boczna kolumna).
                .focusSection()
                // Plakietka sąsiedniego miesiąca renderowana jako osobna
                // warstwa NAD siatką (nie wewnątrz PhotoMonthGridView) —
                // patrz komentarz przy onFocusedRowChange w
                // PhotoMonthGridView.swift o tym, dlaczego.
                .overlay(alignment: .top) {
                    if showPreviousMonthIndicator {
                        AdjacentMonthIndicator(direction: .previous)
                            .padding(.top, 24)
                    }
                }
                .overlay(alignment: .bottom) {
                    if showNextMonthIndicator {
                        AdjacentMonthIndicator(direction: .next)
                            .padding(.bottom, 24)
                    }
                }
            }
            .focusScope(focusNamespace)
        }
    }

    /// Wywoływane przez PhotoMonthGridView dopiero po potwierdzeniu (na
    /// podstawie indeksu wiersza z fokusem), że użytkownik naprawdę dotarł
    /// do końca/początku siatki bieżącego miesiąca — w dół na starszy
    /// (kolejny w monthGroups), w górę na nowszy (poprzedni).
    private func goToNextMonth() {
        guard let currentIndex = monthGroups.firstIndex(where: { $0.id == selectedGroup?.id }),
              monthGroups.indices.contains(currentIndex + 1) else { return }
        isTransitioningMonth = true
        entryFocus = .start
        selectedGroupID = monthGroups[currentIndex + 1].id
    }

    private func goToPreviousMonth() {
        guard let currentIndex = monthGroups.firstIndex(where: { $0.id == selectedGroup?.id }),
              monthGroups.indices.contains(currentIndex - 1) else { return }
        isTransitioningMonth = true
        entryFocus = .end
        selectedGroupID = monthGroups[currentIndex - 1].id
    }
}
