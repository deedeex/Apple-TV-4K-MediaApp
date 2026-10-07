//
//  VideoGalleryView.swift
//  MediaApp
//
//  Zakładka Wideo — siatka samodzielnych plików wideo (bez pary Live Photo,
//  patrz SMBManager.fetchMediaLibrary). Dane i miniatury pochodzą ze
//  współdzielonego MediaLibraryStore (wstrzykniętego z MainTabView), który
//  zaczyna skanować NAS i generować miniatury w tle od razu po zalogowaniu,
//  a nie dopiero po wejściu w tę zakładkę.
//

import SwiftUI

struct VideoGalleryView: View {
    @EnvironmentObject private var library: MediaLibraryStore

    @State private var selectedGroupID: String?
    /// `nil` domyślnie — patrz obszerny komentarz w PhotoGalleryView.swift i
    /// przy GalleryEntryFocus w MonthGroup.swift.
    @State private var entryFocus: GalleryEntryFocus?
    @State private var isTransitioningMonth = false
    @Namespace private var focusNamespace
    /// Patrz komentarz przy focusedRowIndex/rowCount w PhotoGalleryView.swift.
    @State private var focusedRowIndex: Int?
    @State private var rowCount = 0

    /// Grupowanie wg miesiąca — patrz obszerny komentarz przy `monthGroups`
    /// w PhotoGalleryView.swift (ten sam powód: Focus Engine na tvOS nie
    /// skaluje się do dużej, płaskiej siatki — w hierarchii może naraz
    /// istnieć tylko JEDEN miesiąc, lista miesięcy to tylko boczny filtr).
    /// Scache'owane w MediaLibraryStore (videoMonthGroups), NIE liczone tu
    /// na nowo przy każdym ruchu fokusu — patrz komentarz przy monthGroups w
    /// PhotoGalleryView.swift o tym, dlaczego to kluczowe.
    private var monthGroups: [MonthGroup] {
        library.videoMonthGroups
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
        // BEZ NavigationStack — patrz obszerny komentarz w
        // PhotoGalleryView.swift o tym, dlaczego (podejrzenie: UIKit-owy
        // UINavigationController pod spodem sam wymuszał initial focus przy
        // każdym przemontowaniu, niezależnie od SwiftUI @FocusState).
        content
            .onChange(of: library.videos.isEmpty) { _, isEmpty in
                if !isEmpty {
                    selectedGroupID = monthGroups.first?.id
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if library.isLoading {
            ProgressView("Skanowanie NAS w poszukiwaniu wideo…\nTo może chwilę potrwać przy dużej bibliotece.")
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
                }
            }
        } else if library.videos.isEmpty {
            Text("Brak samodzielnych plików wideo na NAS (razem z podfolderami).")
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 0) {
                MonthSidebarList(groups: monthGroups, selectedGroupID: selectedGroupID) { id in
                    entryFocus = .start
                    selectedGroupID = id
                }
                // 430 (nie 520) — patrz komentarz w PhotoGalleryView.swift:
                // proporcjonalnie zmniejszone w stosunku 5:6, odkąd siatka ma
                // 6 kolumn zamiast 5.
                .frame(width: 430)
                .focusSection()
                // Patrz komentarz przy .disabled(isTransitioningMonth) w
                // PhotoGalleryView.swift.
                .disabled(isTransitioningMonth)

                Group {
                    if let selectedGroup {
                        // Patrz komentarz przy braku .id() w PhotoGalleryView.swift.
                        VideoMonthGridView(
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
                // Patrz komentarz w PhotoGalleryView.swift o tym, dlaczego
                // BEZ .prefersDefaultFocus.
                .focusSection()
                // Patrz komentarz przy .overlay w PhotoGalleryView.swift.
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

    /// Patrz analogiczny komentarz przy goToNextMonth/goToPreviousMonth w
    /// PhotoGalleryView.swift.
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
