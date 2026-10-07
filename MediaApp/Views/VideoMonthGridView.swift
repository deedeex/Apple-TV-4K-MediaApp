//
//  VideoMonthGridView.swift
//  MediaApp
//
//  Siatka wideo dla JEDNEGO miesiąca — analogicznie do PhotoMonthGridView,
//  patrz tamten komentarz i MonthGroup.swift/VideoGalleryView.
//

import SwiftUI

struct VideoMonthGridView: View {
    let group: MonthGroup
    /// Patrz obszerny komentarz przy GalleryEntryFocus w MonthGroup.swift.
    var entryFocus: GalleryEntryFocus?
    var onReachEnd: (() -> Void)? = nil
    var onReachStart: (() -> Void)? = nil
    var onFocusReady: (() -> Void)? = nil
    /// Patrz komentarz przy onFocusedRowChange w PhotoMonthGridView.swift.
    var onFocusedRowChange: ((Int?, Int) -> Void)? = nil

    private static let columnCount = 6

    @State private var selectedVideo: NASMediaItem?
    @FocusState private var focusedItemID: NASMediaItem.ID?
    /// Patrz komentarz przy lastObservedRowIndex w PhotoMonthGridView.swift.
    @State private var lastObservedRowIndex: Int?
    /// Patrz komentarz przy itemIndexByID w PhotoMonthGridView.swift.
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

    /// Patrz komentarz przy rowCount w PhotoMonthGridView.swift.
    private var rowCount: Int {
        group.items.isEmpty ? 0 : (group.items.count + Self.columnCount - 1) / Self.columnCount
    }

    private var lastRowIndex: Int? {
        rowCount > 0 ? rowCount - 1 : nil
    }

    /// Patrz komentarz przy focusedRowIndex w PhotoMonthGridView.swift.
    private var focusedRowIndex: Int? {
        guard let focusedItemID, let itemIndex = itemIndexByID[focusedItemID] else { return nil }
        return itemIndex / Self.columnCount
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(group.title)
                        .font(.system(size: 48, weight: .bold))
                        .padding(.horizontal, 60)
                        .padding(.top, 40)

                    LazyVStack(spacing: 40) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                            HStack(spacing: 40) {
                                ForEach(row) { video in
                                    VideoGridTile(item: video) {
                                        selectedVideo = video
                                    }
                                    .frame(maxWidth: .infinity)
                                    .focused($focusedItemID, equals: video.id)
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
                }
            }
            .onChange(of: focusedRowIndex) { _, newRow in
                // Wyłącznie raportowanie do rodzica (plakietka sąsiedniego
                // miesiąca) — nie podejmuje żadnych decyzji o przełączaniu.
                onFocusedRowChange?(newRow, rowCount)
            }
            // Klucz to group.items.map(\.id), NIE group.id — patrz obszerny
            // komentarz przy analogicznym .onChange w PhotoMonthGridView.swift
            // o tym, dlaczego (MediaLibraryStore ładuje bibliotekę w dwóch
            // krokach — cache, potem świeży skan SMB — regenerując UUID-y
            // wszystkich NASMediaItem przy drugim kroku, mimo że group.id dla
            // danego miesiąca się nie zmienia).
            .onChange(of: group.items.map(\.id)) { _, _ in
                itemIndexByID = Self.buildIndex(group.items)
            }
            // Patrz komentarz przy .task(id:) w PhotoMonthGridView.swift —
            // widok siatki NIE jest niszczony przy zmianie miesiąca, więc
            // fokus nigdy nie zostaje bez celu (stąd wcześniej ucieczka do
            // paska zakładek/bocznej listy).
            .task(id: group.id) {
                // Wymuszenie fokusu/scrolla TYLKO gdy rodzic jawnie o to
                // poprosił — patrz obszerny komentarz przy GalleryEntryFocus
                // w MonthGroup.swift i przy analogicznym .task w
                // PhotoMonthGridView.swift.
                if let entryFocus {
                    // Scroll do góry ZAWSZE na start — patrz komentarz w
                    // PhotoMonthGridView.swift.
                    if rowCount > 0 {
                        proxy.scrollTo(0, anchor: .top)
                    }
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
                // Patrz komentarz przy analogicznym wywołaniu w
                // PhotoMonthGridView.swift.
                onFocusedRowChange?(focusedRowIndex, rowCount)
                onFocusReady?()
            }
        }
        .onMoveCommand { direction in
            // Patrz komentarz przy lastObservedRowIndex w
            // PhotoMonthGridView.swift.
            let current = focusedRowIndex
            switch direction {
            case .down:
                if current == lastRowIndex, lastObservedRowIndex == lastRowIndex {
                    onReachEnd?()
                }
            case .up:
                // BEZ current == 0 — patrz obszerny komentarz przy analogicznym
                // .onMoveCommand w PhotoMonthGridView.swift: nad siatką jest
                // zawsze pasek zakładek, więc silnik fokusu ucieka tam ZANIM
                // ten handler się odpali, a current wtedy to `nil`, nie `0`.
                // (Próba wyeliminowania samego mignięcia fokusu na pasku przez
                // niewidocznego "wartownika" wycofana — powodowała regresję,
                // patrz komentarz w PhotoMonthGridView.swift.)
                if lastObservedRowIndex == 0 {
                    onReachStart?()
                }
            default:
                break
            }
            lastObservedRowIndex = current
        }
        .fullScreenCover(item: $selectedVideo) { video in
            VideoPlaybackView(items: group.items, initialItem: video)
                // Czarne tło samej prezentacji pełnoekranowej (domyślnie
                // tvOS daje tu ciemnoszary materiał, widoczny przy
                // otwieraniu/zamykaniu i przejściach między pozycjami).
                .presentationBackground(.black)
        }
    }
}
