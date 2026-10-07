//
//  AppBackground.swift
//  MediaApp
//
//  Tło głównych ekranów (zakładki z siatką i boczną listą miesięcy oraz
//  Ustawienia) — delikatny radialny gradient zamiast domyślnego, szarego
//  tła TabView tvOS. Kolor wybierany w Ustawieniach → Tło (BackgroundTheme),
//  domyślnie indygo z ikony aplikacji (GlassMedia_Back: ~#2B1967 w środku,
//  ~#1B0E40 na brzegach).
//
//  Wszystkie warianty celowo ciemne i o niskim kontraście między środkiem a
//  brzegami: na tym tle leżą miniatury, biały tekst i szklane (Liquid Glass)
//  elementy — jaśniejszy lub bardziej nasycony gradient konkurowałby z
//  treścią.
//
//  Pełnoekranowe przeglądarki zdjęć/wideo NIE używają tego tła — tam
//  zostaje czyste czarne (patrz MediaPagerView/AllMediaPagerView).
//

import SwiftUI

/// Dostępne kolory tła. `rawValue` jest zapisywany w UserDefaults
/// (@AppStorage), więc NIE zmieniać istniejących wartości — zapisany wybór
/// użytkownika przestałby pasować.
/// Kolejność przypadków = kolejność kart w Ustawieniach → Tło
/// (CaseIterable): domyślne indygo, kolory w kolejności barw, szarości,
/// czerń. Białego/jasnych odcieni celowo brak — na jasnym tle biały tekst
/// i szklane elementy interfejsu byłyby nieczytelne.
enum BackgroundTheme: String, CaseIterable, Identifiable {
    case indigo
    case darkIndigo
    case red
    case burgundy
    case pink
    case orange
    case yellow
    case brown
    case olive
    case green
    case teal
    case turquoise
    case blue
    case navy
    case purple
    case darkGray
    case gray
    case lightGray
    case black

    static let storageKey = "backgroundTheme"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .indigo: String(localized: "Indygo (domyślne)")
        case .darkIndigo: String(localized: "Ciemne indygo")
        case .red: String(localized: "Czerwony")
        case .burgundy: String(localized: "Bordowy")
        case .pink: String(localized: "Różowy")
        case .orange: String(localized: "Pomarańczowy")
        case .yellow: String(localized: "Żółty")
        case .brown: String(localized: "Brązowy")
        case .olive: String(localized: "Oliwkowy")
        case .green: String(localized: "Zielony")
        case .teal: String(localized: "Morski")
        case .turquoise: String(localized: "Turkusowy")
        case .blue: String(localized: "Niebieski")
        case .navy: String(localized: "Granatowy")
        case .purple: String(localized: "Fioletowy")
        case .darkGray: String(localized: "Ciemnoszary")
        case .gray: String(localized: "Szary")
        case .lightGray: String(localized: "Jasnoszary")
        case .black: String(localized: "Czarny")
        }
    }

    /// Kolory gradientu: środek, 55% promienia, brzeg — o zbliżonej
    /// jasności we wszystkich wariantach, żeby tekst i miniatury wyglądały
    /// tak samo czytelnie niezależnie od wyboru. "Jasnoszary" jest jasny
    /// tylko na tle pozostałych szarości — nadal ciemny, z tego samego
    /// powodu.
    var stops: [Gradient.Stop] {
        // Ciemne indygo i bordowy — osobne, 4-punktowe gradienty (niżej).
        if !smoothDarkStops.isEmpty { return smoothDarkStops }

        let (center, middle, edge): (UInt32, UInt32, UInt32) = switch self {
        case .indigo: (0x2B1967, 0x1A0F45, 0x0C0722)
        case .darkIndigo: (0x1A0F40, 0x120A31, 0x0B0621)
        case .burgundy: (0x3F0E1C, 0x2C0A15, 0x1C060D)
        case .red: (0x4A1620, 0x2E0D14, 0x140508)
        case .pink: (0x4F1A3A, 0x321024, 0x16070F)
        case .orange: (0x4F2A0E, 0x321A08, 0x160B03)
        case .yellow: (0x4A3F10, 0x2E270A, 0x141104)
        case .brown: (0x3E2A1C, 0x271A11, 0x110B07)
        case .olive: (0x33381A, 0x202310, 0x0D0F06)
        case .green: (0x14402A, 0x0C2819, 0x04110A)
        case .teal: (0x0F3F40, 0x092828, 0x041111)
        case .turquoise: (0x0F3E52, 0x092734, 0x041117)
        case .blue: (0x163568, 0x0D2045, 0x050D22)
        case .navy: (0x101E4A, 0x0A1330, 0x040815)
        case .purple: (0x3C1858, 0x260F38, 0x100619)
        case .darkGray: (0x262626, 0x181818, 0x0A0A0A)
        case .gray: (0x3A3A3A, 0x262626, 0x121212)
        case .lightGray: (0x505050, 0x363636, 0x1C1C1C)
        case .black: (0x000000, 0x000000, 0x000000)
        }
        return [
            .init(color: Color(hex: center), location: 0),
            .init(color: Color(hex: middle), location: 0.55),
            .init(color: Color(hex: edge), location: 1),
        ]
    }

    /// Bardzo ciemne motywy z łagodniejszym zejściem na zewnątrz. Przy
    /// 3 punktach jak w pozostałych (np. ciemne indygo 0x10092A → 0x060312)
    /// kanały koloru miały w zewnętrznej części gradientu tylko kilkanaście
    /// poziomów jasności (z 256), więc każdy "schodek" rozciągał się na
    /// szeroki pas ekranu — widoczny banding (wyraźna granica jasne/ciemne),
    /// najbardziej w dolnych rogach, najdalej od środka gradientu. Tu brzeg
    /// jest bliższy jasnością środkowi, a dodatkowy punkt na 80% wypłaszcza
    /// spadek tam, gdzie był najbardziej stromy.
    private var smoothDarkStops: [Gradient.Stop] {
        let colors: [(UInt32, Double)] = switch self {
        // Ten sam odcień co indygo, wyraźnie ciemniejszy — gradient nadal
        // widoczny, ale subtelniejszy.
        case .darkIndigo: [(0x1A0F40, 0), (0x120A31, 0.55), (0x0E0828, 0.8), (0x0B0621, 1)]
        case .burgundy: [(0x3F0E1C, 0), (0x2C0A15, 0.55), (0x230811, 0.8), (0x1C060D, 1)]
        default: []
        }
        return colors.map { .init(color: Color(hex: $0.0), location: $0.1) }
    }
}

struct AppBackground: View {
    @AppStorage(BackgroundTheme.storageKey) private var theme: BackgroundTheme = .indigo

    var body: some View {
        BackgroundGradient(theme: theme)
            .ignoresSafeArea()
    }
}

/// Sam gradient danego motywu — używany jako tło aplikacji i jako podgląd
/// w Ustawieniach → Tło.
struct BackgroundGradient: View {
    let theme: BackgroundTheme
    /// Promień w punktach — 1400 dla całego ekranu 1920×1080; podgląd w
    /// Ustawieniach podaje mniejszy, proporcjonalny do swojego rozmiaru.
    var endRadius: CGFloat = 1400

    var body: some View {
        RadialGradient(
            stops: theme.stops,
            // Środek lekko powyżej połowy — najjaśniej w okolicy paska
            // zakładek i górnej części siatki, ciemniej w rogach.
            center: UnitPoint(x: 0.5, y: 0.35),
            startRadius: 0,
            endRadius: endRadius
        )
    }
}

extension View {
    /// Wypełnia cały dostępny obszar i kładzie pod spodem AppBackground.
    func appBackground() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { AppBackground() }
    }
}

private extension Color {
    /// Kolor z zapisu szesnastkowego 0xRRGGBB.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
