//
//  MonthGroup.swift
//  MediaApp
//
//  Grupowanie biblioteki wg miesiąca. Konieczne przy bardzo dużych
//  bibliotekach (setki tysięcy zdjęć) — jeden płaski, ciągły widok w tej
//  skali zawiesza Focus Engine na tvOS (_UIFocusRegionEvaluator nie
//  skaluje się do setek tysięcy jednocześnie znanych fokusowalnych
//  elementów, potwierdzone stack trace'em z realnego zawieszenia). Dzięki
//  podziałowi na miesiące każdy ekran siatki pokazuje tylko ograniczoną
//  część biblioteki naraz.
//

import Foundation

nonisolated struct MonthGroup: Identifiable, Hashable {
    /// "2026-09" dla znanych miesięcy albo "unknown" dla pozycji bez daty.
    let id: String
    /// Pełny tytuł z rokiem ("Październik 2026") — nagłówek siatki itp.
    let title: String
    /// Rok miesiąca, `nil` dla grupy "Nieznana data". Boczna lista
    /// (MonthSidebarList) grupuje po nim miesiące w sekcje lat.
    let year: Int?
    /// Sama nazwa miesiąca bez roku ("Październik") — dla wierszy bocznej
    /// listy, gdzie rok jest już w nagłówku sekcji.
    let monthName: String
    let items: [NASMediaItem]

    static func == (lhs: MonthGroup, rhs: MonthGroup) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Od którego końca ma dostać fokus siatka miesiąca zaraz po przełączeniu —
/// `.start` przy wejściu z bocznej listy albo doscrollowaniu w dół do
/// kolejnego (starszego) miesiąca, `.end` przy doscrollowaniu w górę do
/// poprzedniego (nowszego) miesiąca, żeby fokus "wjeżdżał" od strony, z
/// której użytkownik faktycznie przyszedł.
///
/// W widokach siatek (PhotoMonthGridView i inne) ten parametr jest OPCJONALNY
/// (`GalleryEntryFocus?`, nie `GalleryEntryFocus`) — `nil` oznacza "po prostu
/// wyświetl ten miesiąc, NIE wymuszaj fokusu na żadnym kaflu", a wartość
/// niepusta oznacza "użytkownik właśnie jawnie nawigował (boczna lista albo
/// koniec/początek siatki), wymuś fokus". To rozróżnienie jest kluczowe: tvOS
/// niszczy i tworzy od nowa całą zawartość zakładki przy KAŻDYM przełączeniu
/// górnego paska (patrz komentarz w PhotoGalleryView.swift), więc widok
/// siatki montuje się od nowa również przy zwykłym przełączeniu zakładki, nie
/// tylko przy faktycznej nawigacji do innego miesiąca — bez tego
/// rozróżnienia nie dało się odróżnić jednego od drugiego, więc zwykłe
/// przejrzenie zakładek wyrywało fokus z paska w głąb siatki.
enum GalleryEntryFocus {
    case start
    case end
}

/// Przybliżona liczba wierszy siatki, jaka mieści się na ekranie tvOS bez
/// przewijania (kwadratowe kafelki, 6 kolumn) — używane przez
/// PhotoGalleryView/VideoGalleryView do decyzji, czy pokazać plakietkę
/// sąsiedniego miesiąca "od razu" (patrz AdjacentMonthIndicator), gdy cała
/// zawartość mieści się na ekranie niezależnie od pozycji fokusu.
enum GalleryLayout {
    static let maxRowsPerScreen = 2
}

nonisolated enum MediaGrouping {
    /// Grupuje po miesiącu wg `captureDate` (data modyfikacji pliku z SMB —
    /// najbliższe dostępne przybliżenie „daty zrobienia" bez parsowania
    /// EXIF/metadanych wideo), od najnowszego. Pozycje bez daty lądują w
    /// osobnej grupie „Nieznana data" na końcu.
    static func byMonth(_ items: [NASMediaItem]) -> [MonthGroup] {
        let calendar = Calendar.current
        // Klucz liczbowy rok*100+miesiąc, a nie String(format:) dla KAŻDEJ
        // pozycji — formatowanie tekstu było najdroższą częścią pętli przy
        // ~50 tys. pozycji. Tekstowe id ("2026-09") powstaje raz na miesiąc.
        var buckets: [Int: [NASMediaItem]] = [:]
        var unknown: [NASMediaItem] = []

        for item in items {
            guard let date = item.captureDate else {
                unknown.append(item)
                continue
            }
            let comps = calendar.dateComponents([.year, .month], from: date)
            buckets[(comps.year ?? 0) * 100 + (comps.month ?? 0), default: []].append(item)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        let monthFormatter = DateFormatter()
        monthFormatter.locale = Locale(identifier: "pl_PL")
        monthFormatter.dateFormat = "LLLL"

        var groups = buckets.keys.sorted(by: >).map { key -> MonthGroup in
            let year = key / 100
            let month = key % 100
            let id = String(format: "%04d-%02d", year, month)
            let monthDate = calendar.date(from: DateComponents(year: year, month: month))
            let title = monthDate.map { formatter.string(from: $0).capitalized } ?? id
            let monthName = monthDate.map { monthFormatter.string(from: $0).capitalized } ?? id
            // Wewnątrz miesiąca sortujemy WG DATY malejąco (najnowsze
            // pierwsze) — bez tego pozycje zachowywały kolejność z
            // fetchMediaLibrary(), czyli alfabetycznie po nazwie pliku, więc
            // w siatce (wiersze zapełniane od góry-lewej) najstarsze zdjęcia
            // lądowały na górze zamiast najnowszych. Wszystkie pozycje w tym
            // buckecie mają już captureDate (nil trafia do `unknown`
            // wyżej) — .distantPast to tylko nieosiągalne zabezpieczenie.
            let items = (buckets[key] ?? []).sorted(by: isNewer)
            return MonthGroup(id: id, title: title, year: year, monthName: monthName, items: items)
        }

        if !unknown.isEmpty {
            groups.append(MonthGroup(id: "unknown", title: "Nieznana data", year: nil, monthName: "Nieznana data", items: unknown))
        }

        return groups
    }

    /// Łączy dwa wyniki byMonth (np. zdjęcia i wideo) w jedną chronologię
    /// dla zakładki "Wszystko" — wynik identyczny jak byMonth(a + b), ale
    /// bez ponownego liczenia miesiąca dla każdej pozycji: miesiące
    /// łączone po id, a pozycje (już posortowane w obu grupach) scalane
    /// liniowo.
    static func merge(_ lhs: [MonthGroup], _ rhs: [MonthGroup]) -> [MonthGroup] {
        var byID: [String: MonthGroup] = [:]
        for group in lhs { byID[group.id] = group }
        for group in rhs {
            if let existing = byID[group.id] {
                let items = group.id == "unknown"
                    ? existing.items + group.items
                    : mergeSorted(existing.items, group.items)
                byID[group.id] = MonthGroup(id: group.id, title: group.title, year: group.year, monthName: group.monthName, items: items)
            } else {
                byID[group.id] = group
            }
        }
        // "rrrr-mm" sortuje się poprawnie leksykograficznie; "unknown" na końcu.
        return byID.values.sorted { lhs, rhs in
            if lhs.id == "unknown" { return false }
            if rhs.id == "unknown" { return true }
            return lhs.id > rhs.id
        }
    }

    private static func isNewer(_ lhs: NASMediaItem, _ rhs: NASMediaItem) -> Bool {
        (lhs.captureDate ?? .distantPast) > (rhs.captureDate ?? .distantPast)
    }

    private static func mergeSorted(_ a: [NASMediaItem], _ b: [NASMediaItem]) -> [NASMediaItem] {
        var result: [NASMediaItem] = []
        result.reserveCapacity(a.count + b.count)
        var i = 0, j = 0
        while i < a.count, j < b.count {
            if isNewer(b[j], a[i]) {
                result.append(b[j]); j += 1
            } else {
                result.append(a[i]); i += 1
            }
        }
        result.append(contentsOf: a[i...])
        result.append(contentsOf: b[j...])
        return result
    }
}
