//
//  PhotoMonthGridView.swift
//  MediaApp
//
//  Siatka zdjęć dla JEDNEGO miesiąca (patrz MonthGroup.swift/PhotoGalleryView).
//  Ręczne wiersze (HStack) w .focusSection() zamiast LazyVGrid — patrz
//  obszerny komentarz historyczny w PhotoGalleryView.swift o tym, dlaczego.
//  Przy pojedynczym miesiącu liczba pozycji jest już wystarczająco mała,
//  żeby Focus Engine sobie poradził nawet bez tego zabiegu, ale zostajemy
//  przy nim jako dodatkowe zabezpieczenie przy bardzo płodnych miesiącach.
//

import SwiftUI

struct PhotoMonthGridView: View {
    let group: MonthGroup
    /// Patrz obszerny komentarz przy GalleryEntryFocus w MonthGroup.swift —
    /// `nil` (nie `.start`!) oznacza "sam widok się pojawił, bez jawnej
    /// nawigacji", więc NIE wymuszaj fokusu.
    var entryFocus: GalleryEntryFocus?
    var onReachEnd: (() -> Void)? = nil
    var onReachStart: (() -> Void)? = nil
    var onFocusReady: (() -> Void)? = nil
    /// Wyłącznie do wyświetlenia plakietki "Poprzedni/Następny miesiąc" w
    /// RODZICU (patrz PhotoGalleryView) — celowo poza tym widokiem, żeby nie
    /// dotykać wewnętrznej struktury ScrollView/.onMoveCommand odpowiedzialnej
    /// za samą nawigację (dodanie tu dodatkowej warstwy/.overlay wcześniej
    /// psuło swipe i fokus, mimo że plakietka była czysto informacyjna).
    var onFocusedRowChange: ((Int?, Int) -> Void)? = nil

    private static let columnCount = 6

    @State private var selectedItem: NASMediaItem?
    @State private var selectedID: NASMediaItem.ID?
    @FocusState private var focusedItemID: NASMediaItem.ID?
    /// Patrz obszerny komentarz przy .onChange(of: selectedItem == nil) i
    /// .prefersDefaultFocus niżej — próba samego @FocusState (nawet z
    /// wielokrotnym, opóźnionym ustawianiem) nie wystarczała: tvOS po
    /// powrocie z fullScreenCover (.buttonStyle(.card) ma własną, systemową
    /// pamięć "ostatnio wybranej karty") przywracał fokus na kafel sprzed
    /// wejścia w pełny ekran, nadpisując nasze ustawienie z opóźnieniem
    /// rzędu pół sekundy. .prefersDefaultFocus to jedyny mechanizm SwiftUI,
    /// który realnie uczestniczy w USTALANIU/PRZYWRACANIU fokusu (nie tylko
    /// go odczytuje po fakcie), więc ma szansę wygrać z tą systemową pamięcią.
    @Namespace private var returnFocusNamespace
    @State private var pendingReturnFocusID: NASMediaItem.ID?
    /// Wiersz, w którym fokus BYŁ przed bieżącym ruchem pilota — ustawiane
    /// ręcznie na końcu .onMoveCommand, bo w momencie jego odpalenia
    /// `focusedRowIndex` już odzwierciedla pozycję PO ruchu (Focus Engine
    /// zdążył przesunąć fokus, zanim komenda do nas dotarła). Bez tego
    /// "właśnie wjechałem na ostatni wiersz" i "już tam byłem i próbuję
    /// dalej" wyglądają identycznie — przełączanie następowało o wiersz za
    /// wcześnie.
    @State private var lastObservedRowIndex: Int?
    /// Mapa id → pozycja w group.items, żeby focusedRowIndex był O(1) zamiast
    /// przeszukiwania całej biblioteki miesiąca. KRYTYCZNE: focusedRowIndex
    /// jest teraz celem .onChange (patrz niżej), więc SwiftUI odczytuje go
    /// przy KAŻDYM przerenderowaniu, nie tylko przy ruchu pilota — bez tego
    /// cache'a każdy taki odczyt przeszukiwałby cały (potencjalnie
    /// kilkutysięczny) miesiąc od nowa, co przy przesuwaniu fokusu dawało
    /// 100% CPU i zacinanie (dokładnie ten sam rodzaj problemu, przez który
    /// w ogóle powstał podział biblioteki na miesiące — patrz komentarz w
    /// PhotoGalleryView.swift). Liczone raz w init i odświeżane w
    /// .onChange(of: group.id) — SYNCHRONICZNIE (nie w .task), więc nigdy
    /// nie ma klatki z pustą/nieaktualną mapą.
    @State private var itemIndexByID: [NASMediaItem.ID: Int]

    init(
        group: MonthGroup,
        entryFocus: GalleryEntryFocus? = nil,
        onReachEnd: (() -> Void)? = nil,
        onReachStart: (() -> Void)? = nil,
        onFocusReady: (() -> Void)? = nil,
        onFocusedRowChange: ((Int?, Int) -> Void)? = nil
    ) {
        self.group = group
        self.entryFocus = entryFocus
        self.onReachEnd = onReachEnd
        self.onReachStart = onReachStart
        self.onFocusReady = onFocusReady
        self.onFocusedRowChange = onFocusedRowChange
        _itemIndexByID = State(initialValue: Self.buildIndex(group.items))
    }

    private static func buildIndex(_ items: [NASMediaItem]) -> [NASMediaItem.ID: Int] {
        Dictionary(uniqueKeysWithValues: items.enumerated().map { ($1.id, $0) })
    }

    private var rows: [[NASMediaItem]] {
        stride(from: 0, to: group.items.count, by: Self.columnCount).map {
            Array(group.items[$0..<min($0 + Self.columnCount, group.items.count)])
        }
    }

    /// Liczba wierszy bez budowania całej tablicy `rows` — tania arytmetyka
    /// zamiast O(n) chunkowania, dla miejsc, którym wystarczy sama liczba
    /// (patrz komentarz przy itemIndexByID o tym, dlaczego to ważne).
    private var rowCount: Int {
        group.items.isEmpty ? 0 : (group.items.count + Self.columnCount - 1) / Self.columnCount
    }

    private var lastRowIndex: Int? {
        rowCount > 0 ? rowCount - 1 : nil
    }

    /// Indeks wiersza, w którym aktualnie jest fokus — O(1) przez
    /// itemIndexByID (patrz komentarz tam).
    private var focusedRowIndex: Int? {
        guard let focusedItemID, let itemIndex = itemIndexByID[focusedItemID] else { return nil }
        return itemIndex / Self.columnCount
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Zwykły Text WEWNĄTRZ ScrollView (nie .navigationTitle) —
                    // dzięki temu przewija się naturalnie razem z siatką, zamiast
                    // wisieć jako pływający, częściowo przezroczysty pasek tvOS,
                    // który nakłada się na kafelki podczas scrollowania.
                    Text(group.title)
                        .font(.system(size: 48, weight: .bold))
                        .padding(.horizontal, 60)
                        .padding(.top, 40)

                    LazyVStack(spacing: 40) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                            HStack(spacing: 40) {
                                ForEach(row) { item in
                                    MediaGridTile(item: item) {
                                        selectedID = item.id
                                        selectedItem = item
                                    }
                                    .frame(maxWidth: .infinity)
                                    .focused($focusedItemID, equals: item.id)
                                    .prefersDefaultFocus(item.id == pendingReturnFocusID, in: returnFocusNamespace)
                                }
                                if row.count < Self.columnCount {
                                    ForEach(0..<(Self.columnCount - row.count), id: \.self) { _ in
                                        Color.clear.frame(maxWidth: .infinity)
                                    }
                                }
                            }
                            .focusSection()
                            .id(index)
                        }
                    }
                    .padding(.horizontal, 60)
                    .padding(.bottom, 60)
                    .focusScope(returnFocusNamespace)
                }
            }
            .onChange(of: focusedRowIndex) { _, newRow in
                // Wyłącznie raportowanie do rodzica (plakietka sąsiedniego
                // miesiąca) — nie podejmuje żadnych decyzji o przełączaniu.
                // rowCount (nie rows.count!) — tania arytmetyka, nie
                // przebudowuje całej tablicy przy każdym ruchu fokusu.
                onFocusedRowChange?(newRow, rowCount)
            }
            // Klucz to group.items.map(\.id), NIE group.id — MediaLibraryStore
            // ładuje bibliotekę w DWÓCH krokach (najpierw MediaLibraryCache z
            // dysku, zaraz potem świeży skan SMB, patrz komentarz w
            // MediaLibraryStore.swift), a NASMediaItem.id to UUID generowany
            // NA NOWO przy każdym skanowaniu — więc dla TEGO SAMEGO miesiąca
            // (ten sam group.id, np. "2026-09") drugi krok podmienia całą
            // tablicę items na nowe obiekty z nowymi UUID-ami, mimo że
            // group.id się nie zmienia. Kluczowanie po samym group.id
            // (poprzednia wersja) nie wykrywało tej podmiany — itemIndexByID
            // zostawało z mapą starych, już nieistniejących UUID-ów, więc
            // focusedItemID (wskazujący na NOWY obiekt) nigdy nie trafiał w tę
            // mapę, focusedRowIndex był trwale nil, a plakietka "Następny/
            // Poprzedni miesiąc" nigdy się nie pokazywała — ale TYLKO dla
            // miesiąca widocznego od razu po starcie (ten jeden PhotoMonthGridView
            // przeżywał całą podmianę cache→świeży skan bez przemontowania).
            // Ręczne przejście na inny miesiąc i z powrotem "naprawiało" to
            // przypadkiem, bo group.id faktycznie się wtedy zmieniał.
            .onChange(of: group.items.map(\.id)) { _, _ in
                // Odświeżenie mapy id→indeks SYNCHRONICZNIE przy zmianie
                // miesiąca (nie w .task, żeby nie było klatki z nieaktualną
                // mapą, zanim .task zdąży ją przeliczyć).
                itemIndexByID = Self.buildIndex(group.items)
            }
            // MediaPagerView na żywo aktualizuje selectedID przy KAŻDEJ
            // zmianie strony (przewijanie lewo/prawo w pełnym ekranie) — ale
            // to NIE to samo co focusedItemID (@FocusState sterujące
            // faktycznym fokusem w siatce), więc bez tej synchronizacji
            // powrót z pełnego ekranu (Menu/wstecz) zostawiał fokus tam,
            // gdzie był PRZED wejściem (na kaflu, w który kliknięto), a nie
            // na ostatnio oglądanej pozycji.
            //
            // Klucz to selectedItem (moment ZAMKNIĘCIA fullScreenCover, gdy
            // wraca do nil), NIE selectedID (pierwsza wersja tej poprawki) —
            // selectedID zmienia się WIELOKROTNIE w trakcie przewijania
            // WEWNĄTRZ pełnego ekranu, czyli gdy ta siatka jest wciąż
            // przysłonięta przez fullScreenCover i (prawdopodobnie) nie ma
            // aktywnego układu — scrollTo/fokus wywołane wtedy cicho nic nie
            // robiły. Robienie tego dopiero przy faktycznym zamknięciu
            // gwarantuje, że siatka jest już naprawdę widoczna.
            //
            // Task { sleep } między scrollTo a ustawieniem focusedItemID —
            // ten sam wzorzec co przy entryFocus == .end w .task niżej:
            // LazyVStack renderuje leniwie, więc wiersz z nową pozycją
            // (mogła być wiele stron dalej niż to, co było wyrenderowane
            // przed wejściem w pełny ekran) fizycznie nie istnieje w
            // hierarchii w tej samej klatce, w której scrollTo go dopiero
            // zamawia — .focused() na jeszcze nieistniejącym kaflu nic by
            // nie dało.
            // selectedItem == nil (Bool), NIE selectedItem wprost — NASMediaItem
            // nie jest Equatable, więc .onChange(of: selectedItem) się nie
            // kompiluje.
            .onChange(of: selectedItem == nil) { _, isDismissed in
                guard isDismissed, let targetID = selectedID, let itemIndex = itemIndexByID[targetID] else { return }
                proxy.scrollTo(itemIndex / Self.columnCount, anchor: .center)
                // pendingReturnFocusID USTAWIONE NATYCHMIAST (nie w Task) —
                // .prefersDefaultFocus musi mieć poprawną wartość zanim
                // system w ogóle zacznie ustalać/przywracać fokus po
                // zamknięciu fullScreenCover, nie moment później.
                pendingReturnFocusID = targetID
                // focusedItemID nadal ustawiane wielokrotnie (belt-and-
                // suspenders) — patrz komentarz przy pendingReturnFocusID
                // wyżej o tym, czemu samo to nie wystarczało (systemowa
                // pamięć "ostatnio wybranej karty" .buttonStyle(.card)
                // nadpisywała je z opóźnieniem rzędu pół sekundy).
                Task {
                    for delayMs: UInt64 in [150, 350, 600] {
                        try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
                        focusedItemID = targetID
                    }
                }
            }
            // .task(id: group.id) zamiast zwykłego .task — reaguje na każdą
            // zmianę miesiąca, ale (w przeciwieństwie do niszczenia widoku
            // przez .id(group.id) w rodzicu, jak było wcześniej) NIE
            // odtwarza całego widoku od zera, więc aktualnie sfokusowany
            // kafelek nigdy nie znika bez zastępstwa — to właśnie ten
            // moment "nic nie ma fokusu" pozwalał Focus Engine uciec do
            // paska zakładek/bocznej listy miesięcy.
            .task(id: group.id) {
                // Wymuszenie fokusu/scrolla TYLKO gdy rodzic jawnie o to
                // poprosił (entryFocus != nil — patrz obszerny komentarz przy
                // GalleryEntryFocus w MonthGroup.swift). To .task ODPALA SIĘ
                // też wtedy, gdy ten widok po prostu się pojawił (np. tvOS
                // zniszczył i stworzył od nowa całą zakładkę przy zwykłym
                // przełączeniu paska na górze — dzieje się to przy KAŻDYM
                // przełączeniu, nie tylko pierwszym wejściu), a wtedy
                // entryFocus jest `nil` i NIC nie wymuszamy — fokus zostaje
                // tam, gdzie faktycznie jest (np. na pasku zakładek).
                if let entryFocus {
                    // Scroll do góry ZAWSZE na start — odkąd widok siatki nie
                    // jest już niszczony przy zmianie miesiąca (patrz komentarz
                    // przy .task wyżej), to ten sam ScrollView co poprzednio,
                    // więc bez tego zostawałby przewinięty tam, gdzie ostatnio
                    // przeglądałeś TEN miesiąc (stąd wybór z bocznej listy
                    // pokazywał środek biblioteki zamiast początku).
                    if rowCount > 0 {
                        proxy.scrollTo(0, anchor: .top)
                    }
                    // Pierwszy element — ten wiersz jest od razu wyrenderowany,
                    // więc to natychmiastowy, ważny cel fokusu. Dla .end poniżej
                    // przekierowujemy go zaraz na faktyczny ostatni element
                    // (dopiero po scrollTo, bo LazyVStack renderuje leniwie i
                    // ostatni wiersz do tego momentu fizycznie nie istnieje w
                    // hierarchii).
                    focusedItemID = group.items.first?.id
                    lastObservedRowIndex = 0
                    if entryFocus == .end {
                        if let lastRowIndex {
                            proxy.scrollTo(lastRowIndex, anchor: .bottom)
                        }
                        try? await Task.sleep(nanoseconds: 150_000_000)
                        focusedItemID = group.items.last?.id
                        lastObservedRowIndex = lastRowIndex
                    }
                }
                // Jawne wywołanie (nie tylko .onChange) — .onChange nie
                // odpali się, jeśli nowy miesiąc przypadkiem ląduje na tym
                // samym indeksie wiersza co poprzedni (ta sama WARTOŚĆ), a
                // rowCount (potrzebne do fitsOnOneScreen w rodzicu) i tak
                // mogło się zmienić. Zostaje POZA warunkiem — to tylko
                // raportowanie stanu do rodzica, nieszkodliwe nawet przy
                // powtórce.
                onFocusedRowChange?(focusedRowIndex, rowCount)
                onFocusReady?()
            }
        }
        .onMoveCommand { direction in
            // Przełączenie miesiąca ma nastąpić DOPIERO gdy fokus już BYŁ na
            // ostatnim/pierwszym wierszu PRZED tym ruchem (czyli naprawdę
            // nie miał gdzie pójść) — nie przy samym wjeździe na niego.
            // Patrz komentarz przy lastObservedRowIndex.
            let current = focusedRowIndex
            switch direction {
            case .down:
                if current == lastRowIndex, lastObservedRowIndex == lastRowIndex {
                    onReachEnd?()
                }
            case .up:
                // BEZ current == 0 (w przeciwieństwie do .down wyżej) — nad
                // siatką jest zawsze pasek zakładek (Zdjęcia/Wideo/Ustawienia),
                // czyli JEST tam ważny cel fokusu, w przeciwieństwie do "w dół",
                // gdzie pod ostatnim wierszem nie ma nic. Silnik fokusu tvOS
                // przenosi więc fokus do paska ZANIM ten handler się odpali —
                // focusedRowIndex/current bywa wtedy już `nil` (fokus opuścił
                // siatkę), nie `0`, więc wymaganie current == 0 nigdy by się
                // nie spełniło i "poprzedni miesiąc" nigdy by się nie
                // przełączał, tylko fokus uciekałby do paska zakładek. Samo
                // lastObservedRowIndex == 0 (stan SPRZED tego ruchu) wystarczy.
                //
                // UWAGA: to oznacza, że fokus na chwilę widocznie miga na
                // pasku zakładek, zanim miesiąc się przełączy — próbowaliśmy
                // to wyeliminować niewidocznym "wartownikiem" (fokusowalny
                // Color.clear tuż nad pierwszym wierszem, w tej samej
                // .focusSection()), ale to spowodowało REGRESJĘ: pusty ekran
                // po przejściu do kolejnego miesiąca (ScrollView zostawał
                // przewinięty w miejscu, LazyVStack nie zdążył wyrenderować
                // wiersza 0). Wycofane — ten (nieco mniej ładny wizualnie,
                // ale funkcjonalnie niezawodny) wariant zostaje jako
                // stabilna baza, dopóki nie znajdziemy poprawki bez tej
                // wady (prawdopodobnie wymagającej zejścia do UIKit —
                // UIFocusGuide/shouldUpdateFocusInContext — a nie samego SwiftUI).
                if lastObservedRowIndex == 0 {
                    onReachStart?()
                }
            default:
                break
            }
            lastObservedRowIndex = current
        }
        .fullScreenCover(item: $selectedItem) { _ in
            MediaPagerView(items: group.items, selection: $selectedID)
                // Czarne tło samej prezentacji pełnoekranowej (domyślnie
                // tvOS daje tu ciemnoszary materiał, widoczny przy
                // otwieraniu/zamykaniu i przejściach między pozycjami).
                .presentationBackground(.black)
        }
    }
}
