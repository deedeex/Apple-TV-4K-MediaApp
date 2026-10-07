//
//  AllMonthGridView.swift
//  MediaApp
//
//  Siatka MIESZANA (zdjęcia + wideo) dla JEDNEGO miesiąca w zakładce
//  "Wszystko" — mechanika wierszy/fokusu identyczna jak w
//  PhotoMonthGridView/VideoMonthGridView (patrz tamte komentarze), bo jest
//  całkowicie niezależna od typu pozycji. Po kliknięciu w dowolny kafelek
//  otwiera AllMediaPagerView z CAŁYM, mieszanym group.items — przewijanie w
//  pełnym ekranie faktycznie przechodzi między zdjęciami i wideo w kolejności
//  chronologicznej (patrz obszerny komentarz w AllMediaPagerView.swift o tym,
//  jak to jest zrobione bezpiecznie dla Focus Engine).
//

import SwiftUI

struct AllMonthGridView: View {
    let group: MonthGroup
    /// Patrz obszerny komentarz przy GalleryEntryFocus w MonthGroup.swift.
    var entryFocus: GalleryEntryFocus?
    var onReachEnd: (() -> Void)? = nil
    var onReachStart: (() -> Void)? = nil
    var onFocusReady: (() -> Void)? = nil
    /// Patrz komentarz przy onFocusedRowChange w PhotoMonthGridView.swift.
    var onFocusedRowChange: ((Int?, Int) -> Void)? = nil

    private static let columnCount = 6

    @State private var selectedItem: NASMediaItem?
    @State private var selectedID: NASMediaItem.ID?
    @FocusState private var focusedItemID: NASMediaItem.ID?
    /// Patrz obszerny komentarz przy pendingReturnFocusID w
    /// PhotoMonthGridView.swift.
    @Namespace private var returnFocusNamespace
    @State private var pendingReturnFocusID: NASMediaItem.ID?
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
                                ForEach(row) { item in
                                    AllMediaGridTile(item: item) {
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
                onFocusedRowChange?(newRow, rowCount)
            }
            // Patrz obszerny komentarz przy analogicznym .onChange w
            // PhotoMonthGridView.swift o tym, dlaczego klucz to
            // group.items.map(\.id), nie group.id.
            .onChange(of: group.items.map(\.id)) { _, _ in
                itemIndexByID = Self.buildIndex(group.items)
            }
            // Patrz obszerny komentarz przy analogicznym .onChange(of:
            // selectedItem) w PhotoMonthGridView.swift.
            // selectedItem == nil (Bool), NIE selectedItem wprost — patrz
            // komentarz w PhotoMonthGridView.swift (NASMediaItem nie jest
            // Equatable).
            .onChange(of: selectedItem == nil) { _, isDismissed in
                guard isDismissed, let targetID = selectedID, let itemIndex = itemIndexByID[targetID] else { return }
                proxy.scrollTo(itemIndex / Self.columnCount, anchor: .center)
                // NATYCHMIAST, nie w Task — patrz komentarz przy
                // pendingReturnFocusID w PhotoMonthGridView.swift.
                pendingReturnFocusID = targetID
                // Patrz obszerny komentarz przy analogicznym .onChange w
                // PhotoMonthGridView.swift — kilkukrotne ustawienie, bo tvOS
                // potrafi samo przywrócić fokus na kafel sprzed otwarcia
                // fullScreenCover już PO naszym jednorazowym ustawieniu.
                Task {
                    for delayMs: UInt64 in [150, 350, 600] {
                        try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
                        focusedItemID = targetID
                    }
                }
            }
            // Patrz komentarz przy .task(id:) w PhotoMonthGridView.swift.
            .task(id: group.id) {
                // Wymuszenie fokusu/scrolla TYLKO gdy rodzic jawnie o to
                // poprosił — patrz obszerny komentarz przy GalleryEntryFocus
                // w MonthGroup.swift i przy analogicznym .task w
                // PhotoMonthGridView.swift.
                if let entryFocus {
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
                if lastObservedRowIndex == 0 {
                    onReachStart?()
                }
            default:
                break
            }
            lastObservedRowIndex = current
        }
        .fullScreenCover(item: $selectedItem) { _ in
            AllMediaPagerView(items: group.items, selection: $selectedID)
                // Czarne tło samej prezentacji pełnoekranowej (domyślnie
                // tvOS daje tu ciemnoszary materiał, widoczny przy
                // otwieraniu/zamykaniu i przejściach między pozycjami).
                .presentationBackground(.black)
        }
    }
}
