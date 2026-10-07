//
//  AsyncImageSMB.swift
//  MediaApp
//

import SwiftUI

struct AsyncImageSMB: View {
    /// Nazwana stała (nie magiczna liczba w kilku miejscach) — MediaPagerView
    /// pre-ładuje w tle DOKŁADNIE ten sam wariant do cache'u (patrz
    /// prefetchNeighbors tam), więc musi się odwoływać do tej samej wartości,
    /// a nie do osobno wpisanego literału "3840", który mógłby się kiedyś
    /// rozjechać przy zmianie tutaj.
    static let fullScreenMaxPixelSize: CGFloat = 3840

    let url: URL
    /// Docelowy maks. wymiar w pikselach — mały dla kafelków siatki, większy
    /// dla podglądu pełnoekranowego. Dekodowanie i tak nigdy nie przekracza
    /// rozdzielczości ekranu Apple TV (4K), więc domyślna wartość jest bezpieczna wszędzie.
    var maxPixelSize: CGFloat = fullScreenMaxPixelSize
    /// .fill dla kafelków siatki (przycina, wypełnia kwadrat), .fit dla
    /// podglądu pełnoekranowego (pokazuje całe zdjęcie, bez przycinania).
    var contentMode: ContentMode = .fill

    @State private var image: Image?
    @State private var failed = false

    /// Obraz już w RAM (ImageCache) pokazywany od PIERWSZEJ klatki —
    /// wcześniej zawsze startowało od spinnera, a obraz pojawiał się
    /// dopiero po .task (kolejna klatka) i dodatkowo z animacją przenikania.
    init(url: URL, maxPixelSize: CGFloat = fullScreenMaxPixelSize, contentMode: ContentMode = .fill) {
        self.url = url
        self.maxPixelSize = maxPixelSize
        self.contentMode = contentMode
        let cached = ImageCache.shared.image(for: url, variant: SMBImageCache.variant(for: maxPixelSize))
        _image = State(initialValue: cached.map(Image.init(uiImage:)))
    }

    var body: some View {
        // Rectangle jako BAZOWY widok, a nie ZStack z Image jako
        // równorzędnym rodzeństwem — kluczowe przy contentMode: .fill.
        // Rectangle zawsze zgłasza w negocjacji layoutu DOKŁADNIE
        // zaproponowany mu rozmiar, nigdy więcej. Image z
        // .aspectRatio(contentMode: .fill) celowo chce być WIĘKSZY niż
        // zaproponowany rozmiar (żeby "wypełnić" kadr, przycinając nadmiar)
        // — w ZStacku ten większy rozmiar przeciekał w górę przez
        // negocjację layoutu do rodzica (np. kwadratowego kafelka w
        // MediaGridTile), rozdymając cały wiersz siatki (każdy kafelek
        // domagał się ogromnego rozmiaru zamiast równego podziału HStacka).
        // .clipped() przycina tylko RYSOWANIE, nie przycina zgłaszanego
        // rozmiaru — stąd realna, widoczna na urządzeniu rozjechana siatka.
        // .overlay (nie ZStack) izoluje rozmiar Image'a od rozmiaru bazowego
        // Rectangle — to standardowy, bezpieczny wzorzec SwiftUI na "wypełnij
        // i przytnij" bez rozdymania layoutu rodzica.
        Rectangle()
            // Szara zaślepka tylko w trybie .fill (kafelki siatki — obraz i
            // tak ją w całości zakrywa). W trybie .fit (pełny ekran) obraz
            // nie wypełnia całego prostokąta i szarość była widoczna po
            // bokach zdjęcia zamiast czarnego tła przeglądarki.
            .fill(contentMode == .fill ? AnyShapeStyle(.gray.opacity(0.3)) : AnyShapeStyle(.clear))
            .overlay {
                if let image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .transition(.opacity)
                } else if failed {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
            .clipped()
            .task(id: url) {
                await load()
            }
    }

    private func load() async {
        failed = false
        if let cached = ImageCache.shared.image(for: url, variant: SMBImageCache.variant(for: maxPixelSize)) {
            image = Image(uiImage: cached)
            return
        }
        image = nil
        let start = ContinuousClock.now
        do {
            let uiImage = try await SMBImageCache.shared.thumbnail(for: url, maxPixelSize: maxPixelSize)
            // Przenikanie tylko przy wolnym wczytaniu (sieć) — obraz z dysku
            // przychodzi w kilkanaście ms i animacja tylko opóźniałaby jego
            // pełne pojawienie się.
            if start.duration(to: .now) > .milliseconds(150) {
                withAnimation(.easeInOut) { image = Image(uiImage: uiImage) }
            } else {
                image = Image(uiImage: uiImage)
            }
        } catch {
            failed = true
        }
    }
}
