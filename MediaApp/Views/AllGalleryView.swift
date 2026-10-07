//
//  AllGalleryView.swift
//  MediaApp
//
//  Zakładka "Wszystko" — zdjęcia i wideo połączone w jedną, chronologiczną
//  siatkę wg miesiąca (patrz allMonthGroups w MediaLibraryStore.swift, gdzie
//  jest scache'owane z tego samego powodu co photoMonthGroups/videoMonthGroups).
//  Reużywa dokładnie ten sam mechanizm co PhotoGalleryView/VideoGalleryView
//  (patrz tamte komentarze o Focus Engine/pojedynczym miesiącu naraz) —
//  jedyna różnica jest w AllMonthGridView (dispatch kafelków wg typu i
//  filtrowanie podzbioru przed otwarciem pełnoekranowego podglądu).
//

import SwiftUI

struct AllGalleryView: View {
    @EnvironmentObject private var library: MediaLibraryStore

    @State private var selectedGroupID: String?
    /// `nil` domyślnie — patrz obszerny komentarz w PhotoGalleryView.swift i
    /// przy GalleryEntryFocus w MonthGroup.swift.
    @State private var entryFocus: GalleryEntryFocus?
    @State private var isTransitioningMonth = false
    @Namespace private var focusNamespace
    /// Patrz komentarz przy onFocusedRowChange w PhotoMonthGridView.swift.
    @State private var focusedRowIndex: Int?
    @State private var rowCount = 0

    private var monthGroups: [MonthGroup] {
        library.allMonthGroups
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
        // PhotoGalleryView.swift o tym, dlaczego.
        content
            // Trigger to isLoading (nie library.photos.isEmpty jak w
            // PhotoGalleryView) — tu "pusta biblioteka" zależy od DWÓCH
            // tablic naraz (zdjęcia I wideo), więc prościej i poprawniej
            // złapać moment "skan się skończył, a jeszcze nic nie
            // wybraliśmy" niż śledzić pustość jednej konkretnej tablicy.
            // Strażnik selectedGroupID == nil gwarantuje, że to ustawia
            // się tylko RAZ (pierwszy wybór), nie przy każdym reload().
            .onChange(of: library.isLoading) { _, isLoading in
                if !isLoading, selectedGroupID == nil {
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
        } else if library.photos.isEmpty && library.videos.isEmpty {
            Text("Brak zdjęć ani wideo w tym katalogu na NAS (razem z podfolderami).")
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 0) {
                MonthSidebarList(groups: monthGroups, selectedGroupID: selectedGroupID) { id in
                    entryFocus = .start
                    selectedGroupID = id
                }
                .frame(width: 430)
                .focusSection()
                .disabled(isTransitioningMonth)

                Group {
                    if let selectedGroup {
                        AllMonthGridView(
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
