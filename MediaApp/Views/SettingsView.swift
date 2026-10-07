//
//  SettingsView.swift
//  MediaApp
//
//  Zakładka Ustawienia — układ jak w galeriach: po lewej boczna kolumna
//  sekcji (ten sam styl wierszy co lista miesięcy, SidebarRowButtonStyle),
//  po prawej zawartość wybranej sekcji. Sekcja zmienia się już przy
//  przesunięciu fokusu na jej wiersz (jak podgląd), a w prawo pilotem
//  przechodzi się do jej przycisków.
//
//  Serwer — dane połączenia z NAS, "Odśwież bibliotekę" (pełny skan NAS na
//  żądanie; automatycznie skan idzie przy starcie aplikacji i przy powrocie
//  do niej po ≥24 h, patrz MediaLibraryStore.refreshIfStale) i "Zmień
//  ustawienia serwera" (SetupView z wypełnionym formularzem).
//
//  Pamięć podręczna — ile zajmuje cache poziomu 1 (RAM, ImageCache) i
//  poziomu 2 (dysk, DiskThumbnailCache), plus przycisk czyszczący oba.
//  Liczone tylko przy wejściu w tę zakładkę (bez timera w tle). Cache listy
//  plików biblioteki (MediaLibraryCache) celowo NIE jest czyszczony — bez
//  niego każdy start czekałby na pełny skan NAS.
//
//  Tło — wybór koloru gradientu tła (BackgroundTheme, AppBackground.swift),
//  zapisywany w @AppStorage, więc przetrwa restart aplikacji. Zmiana działa
//  od razu we wszystkich zakładkach.
//

import SwiftUI

private enum SettingsSection: String, CaseIterable, Identifiable {
    case server
    case cache
    case background

    var id: String { rawValue }

    var title: String {
        switch self {
        case .server: "Serwer"
        case .cache: "Pamięć podręczna"
        case .background: "Tło"
        }
    }

    var systemImage: String {
        switch self {
        case .server: "server.rack"
        case .cache: "internaldrive"
        case .background: "paintpalette"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var session: SessionManager
    @EnvironmentObject private var library: MediaLibraryStore

    private let config = SMBServerConfig.loadFromStorage()

    @State private var selectedSection: SettingsSection = .server
    @FocusState private var focusedSection: SettingsSection?

    @AppStorage(BackgroundTheme.storageKey) private var backgroundTheme: BackgroundTheme = .indigo

    @State private var ramUsage = ImageCache.shared.usage
    /// nil = jeszcze liczone (pierwsze przeliczenie katalogu na dysku).
    @State private var diskUsage: (bytes: Int64, files: Int)?
    @State private var isClearingCache = false
    @State private var isConfirmingClear = false
    @State private var isConfirmingRefresh = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            sidebar
                // Ta sama szerokość co lista miesięcy w galeriach. PEŁNA
                // wysokość (maxHeight: .infinity) jest konieczna: focus engine
                // szuka celu "w lewo" w pasie wysokości bieżącego elementu, a
                // .focusSection() pomaga tylko, gdy obszar sekcji ten pas
                // przecina. Bez tego kolumna miała wysokość samych trzech
                // wierszy (u góry ekranu) i z przycisków niżej nie dało się
                // przejść w lewo. Lista miesięcy (ScrollView) rozciąga się sama.
                .frame(width: 430)
                .frame(maxHeight: .infinity, alignment: .top)
                .focusSection()

            VStack(alignment: .leading, spacing: 40) {
                Text(selectedSection.title)
                    .font(.system(size: 48, weight: .bold))

                switch selectedSection {
                case .server: serverSection
                case .cache: cacheSection
                case .background: backgroundSection
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 80)
            .focusSection()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Wybór sekcji podąża za fokusem w kolumnie — przy przejściu w prawo,
        // do przycisków sekcji, focusedSection staje się nil, a wybór zostaje.
        .onChange(of: focusedSection) { oldValue, newValue in
            guard let newValue else { return }
            if oldValue == nil {
                // Fokus dopiero WCHODZI do kolumny (z panelu po prawej albo z
                // paska zakładek) — focus engine wybiera wtedy wiersz najbliższy
                // geometrycznie, niekoniecznie bieżącą sekcję. Przekierowanie na
                // wybrany wiersz, zamiast przełączania sekcji samym powrotem
                // w lewo.
                if newValue != selectedSection {
                    focusedSection = selectedSection
                }
            } else {
                selectedSection = newValue
            }
        }
        .task { await refreshCacheUsage() }
        // Wyjaśnienie przed skanem — ta sama forma co przy czyszczeniu
        // pamięci podręcznej niżej (patrz komentarz tam: tekst musi zmieścić
        // się w alercie bez przewijania).
        .alert("Odświeżyć bibliotekę?", isPresented: $isConfirmingRefresh) {
            Button("Odśwież") {
                library.reload()
            }
            Button("Anuluj", role: .cancel) {}
        } message: {
            Text("""
            Skanuje folder na NAS i aktualizuje listę zdjęć i wideo: dodaje nowe pliki i usuwa te, których już nie ma. Nie usuwa miniatur ani niczego na NAS.

            Dzieje się to też automatycznie: przy uruchomieniu aplikacji i po powrocie do niej po co najmniej 24 godzinach.

            Kiedy warto: nowe zdjęcia są już na NAS, a chcesz je zobaczyć od razu.

            Skan trwa kilka sekund — w tym czasie można normalnie przeglądać.
            """)
        }
        .alert("Wyczyścić pamięć podręczną?", isPresented: $isConfirmingClear) {
            Button("Wyczyść", role: .destructive) {
                Task { await clearCache() }
            }
            Button("Anuluj", role: .cancel) {}
        } message: {
            // Wyjaśnienie W TREŚCI alertu, a nie jako osobna ikonka "i" przy
            // przycisku: tvOS nie ma kursora/hover (tooltip), a dodatkowy
            // fokusowalny przycisk tylko wydłużałby nawigację pilotem.
            // Systemowy alert tvOS nie przewija treści — nadmiar ucina
            // wielokropkiem, więc tekst musi zmieścić się w jego stałej
            // wysokości (sprawdzone na Apple TV: ~12 linii).
            Text("""
            Usuwa miniatury z pamięci i dysku Apple TV. Pliki na NAS zostają nietknięte.

            Kiedy warto:
            • zdjęcie zmieniono na NAS, a widać starą wersję,
            • po zmianie serwera lub folderu,
            • brakuje miejsca na Apple TV,
            • miniatura wyświetla się nieprawidłowo.

            Potem miniatury będą ponownie pobierane z NAS, więc siatka przez jakiś czas będzie ładować się wolniej.
            """)
        }
    }

    // MARK: - Boczna kolumna

    private var sidebar: some View {
        VStack(spacing: 4) {
            ForEach(SettingsSection.allCases) { section in
                let isSelected = section == selectedSection
                Button {
                    selectedSection = section
                } label: {
                    HStack(spacing: 20) {
                        Image(systemName: section.systemImage)
                            .frame(width: 44)
                        // Ten sam rozmiar co nazwy miesięcy w MonthSidebarList.
                        // .minimumScaleFactor jak tam — "Pamięć podręczna" obok
                        // ikony i ptaszka nie mieściła się i była ucinana.
                        Text(section.title)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer()
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.accentColor)
                            .opacity(isSelected ? 1 : 0)
                    }
                    .font(.system(size: 32))
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 20)
                }
                .buttonStyle(SidebarRowButtonStyle())
                .focused($focusedSection, equals: section)
            }
        }
    }

    // MARK: - Sekcja: Serwer

    @ViewBuilder
    private var serverSection: some View {
        if let config {
            // useNativeGlassEffect: true — patrz obszerny komentarz w
            // LiquidGlassCard.swift o tym, dlaczego TYLKO tutaj (statyczna
            // karta, bez sąsiedztwa siatki/fokusu w ruchu).
            LiquidGlassCard(useNativeGlassEffect: true) {
                VStack(alignment: .leading, spacing: 16) {
                    infoRow(title: "Host", value: config.host)
                    infoRow(title: "Udział", value: config.shareName)
                    infoRow(title: "Użytkownik", value: config.username)
                    if !config.remotePath.isEmpty {
                        infoRow(title: "Ścieżka", value: config.remotePath)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }

        HStack(spacing: 40) {
            Button {
                isConfirmingRefresh = true
            } label: {
                HStack(spacing: 20) {
                    if library.isScanning {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    // W trakcie automatycznego skanu (przy starcie aplikacji
                    // albo po powrocie do niej po ≥24 h) przycisk jest
                    // nieaktywny — napis mówi wprost, dlaczego.
                    Text(library.isScanning ? "Skanowanie NAS…" : "Odśwież bibliotekę")
                }
                .sectionButtonLabel()
            }
            .buttonStyle(.card)
            // Zablokowane w trakcie trwającego skanu (także skanu w tle po
            // powrocie do aplikacji) — load() i tak ignoruje równoległe
            // wywołania, ale nieaktywny przycisk ze spinnerem jasno
            // pokazuje, że skan już trwa.
            .disabled(library.isScanning)

            Button {
                session.beginEditingSetup()
            } label: {
                HStack(spacing: 20) {
                    Image(systemName: "pencil")
                    Text("Zmień ustawienia serwera")
                }
                .sectionButtonLabel()
            }
            .buttonStyle(.card)
        }
    }

    // MARK: - Sekcja: Pamięć podręczna

    @ViewBuilder
    private var cacheSection: some View {
        LiquidGlassCard(useNativeGlassEffect: true) {
            VStack(alignment: .leading, spacing: 16) {
                infoRow(title: "W pamięci (RAM)", value: ramUsageText)
                infoRow(title: "Na dysku", value: diskUsageText)
            }
            .frame(maxWidth: .infinity)
        }

        Text("Miniatury zdjęć i wideo zapisywane na Apple TV, żeby siatka ładowała się szybko bez ponownego pobierania z NAS.")
            .font(.system(size: 26))
            .foregroundStyle(.secondary)

        Button {
            isConfirmingClear = true
        } label: {
            HStack(spacing: 20) {
                if isClearingCache {
                    ProgressView()
                } else {
                    Image(systemName: "trash")
                }
                Text("Wyczyść pamięć podręczną")
            }
            .sectionButtonLabel()
        }
        .buttonStyle(.card)
        .disabled(isClearingCache)
    }

    // MARK: - Sekcja: Tło

    /// Przybliżona szerokość karty koloru — tylko do skalowania podglądu
    /// gradientu. Faktyczną szerokość wyznaczają elastyczne kolumny siatki.
    private static let approximateSwatchWidth: CGFloat = 250

    private var backgroundSection: some View {
        // ScrollView, bo kart nie mieści się na jednym ekranie — tvOS
        // przewija go sam, gdy fokus przechodzi na kartę poza widokiem.
        ScrollView {
            // Kolumny ELASTYCZNE (.flexible), nie o stałej szerokości: przy
            // stałych 4 × 270 pt siatka razem z boczną kolumną i marginesami
            // była szersza niż bezpieczny obszar ekranu (~1760 pt z 1920),
            // a przepełniony HStack SwiftUI centruje — cała zakładka, łącznie
            // z boczną kolumną, przesuwała się w lewo tylko w sekcji Tło.
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 30), count: 4),
                alignment: .leading,
                spacing: 30
            ) {
                ForEach(BackgroundTheme.allCases) { theme in
                    Button {
                        backgroundTheme = theme
                    } label: {
                        VStack(alignment: .leading, spacing: 0) {
                            // Podgląd gradientu w skali — promień proporcjonalny
                            // do szerokości próbki względem ekranu (1920 pt).
                            BackgroundGradient(theme: theme, endRadius: 1400 * Self.approximateSwatchWidth / 1920)
                                .frame(height: 120)
                            HStack {
                                Text(theme.name)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                Spacer()
                                if theme == backgroundTheme {
                                    Image(systemName: "checkmark")
                                }
                            }
                            .font(.system(size: 24, weight: .semibold))
                            .padding(16)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.card)
                }
            }
            // Zapas na powiększenie karty z fokusem (efekt .card), żeby nie
            // była przycinana na krawędziach przewijanego obszaru. Margines
            // WEWNĄTRZ ScrollView zamiast .scrollClipDisabled() — to drugie
            // wyłącza przycinanie całkiem i przy przewijaniu w dół górny
            // rząd kart wyjeżdżał na nagłówek sekcji ("Tło").
            .padding(.vertical, 24)
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Pamięć podręczna

    private var ramUsageText: String {
        let count = ramUsage.count
        let bytes = Int64(ramUsage.bytes).formatted(.byteCount(style: .memory))
        let limit = Int64(ImageCache.byteLimit).formatted(.byteCount(style: .memory))
        return "\(count.formatted()) \(polishPlural(count, "obraz", "obrazy", "obrazów")) · \(bytes) z \(limit)"
    }

    private var diskUsageText: String {
        guard let diskUsage else { return "Liczenie…" }
        // .memory (jednostki binarne, 1 GB = 1024³ B) jak w wierszu RAM —
        // .file liczy dziesiętnie (1 GB = 1000³ B), przez co limit 30 GiB
        // wyświetlał się jako "32,21 GB".
        let bytes = diskUsage.bytes.formatted(.byteCount(style: .memory))
        let limit = DiskThumbnailCache.maxBytes.formatted(.byteCount(style: .memory))
        return "\(diskUsage.files.formatted()) \(polishPlural(diskUsage.files, "plik", "pliki", "plików")) · \(bytes) z \(limit)"
    }

    private func refreshCacheUsage() async {
        ramUsage = ImageCache.shared.usage
        diskUsage = await DiskThumbnailCache.shared.usage()
    }

    private func clearCache() async {
        isClearingCache = true
        ImageCache.shared.removeAll()
        await DiskThumbnailCache.shared.removeAll()
        await refreshCacheUsage()
        isClearingCache = false
    }

    /// Polska odmiana po liczebniku: 1 plik, 2–4 pliki (poza 12–14),
    /// 5+ plików.
    private func polishPlural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        if n == 1 { return one }
        let lastDigit = n % 10, lastTwo = n % 100
        if (2...4).contains(lastDigit) && !(12...14).contains(lastTwo) { return few }
        return many
    }

    private func infoRow(title: String, value: String) -> some View {
        HStack(spacing: 40) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            // Skracanie w ŚRODKU — przy długiej ścieżce widać jej początek
            // i koniec (zwykle najważniejszy, docelowy folder).
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.system(size: 34))
    }
}

private extension View {
    /// Wspólny wygląd etykiet przycisków w sekcjach Ustawień.
    func sectionButtonLabel() -> some View {
        font(.system(size: 30, weight: .semibold))
            .frame(width: 520)
            .padding(.vertical, 20)
    }
}

#Preview {
    SettingsView()
        .environmentObject(SessionManager())
        .environmentObject(MediaLibraryStore())
}
