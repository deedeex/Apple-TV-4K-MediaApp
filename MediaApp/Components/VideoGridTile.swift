//
//  VideoGridTile.swift
//  MediaApp
//
//  Kafelek siatki w zakładce Wideo. Celowo NIE używa AsyncImageSMB — to
//  komponent do dekodowania obrazów (ImageIO), a plik wideo nie jest
//  obrazem. Miniatura żyje wyłącznie jako lokalny @State (nie na modelu
//  NASMediaItem/w współdzielonej tablicy MediaLibraryStore) i jest
//  generowana przez .task(id: item.id) — SwiftUI automatycznie anuluje tę
//  pracę (pobranie z SMB + dekodowanie klatki), jeśli kafelek zniknie z
//  widoku przy szybkim przewijaniu LazyVGrid, zamiast — jak poprzednio przy
//  eager-loadingu całej biblioteki naraz — próbować wygenerować i trzymać w
//  pamięci miniatury dla wideo, których użytkownik nigdy nie zobaczył.
//
//  Bez ręcznego podświetlania na fokus (scaleEffect/padding/warunkowy
//  glassEffect w tle) — .buttonStyle(.card) daje to natywnie. Dokładanie
//  własnej logiki, która przy zmianie fokusu wstawia/usuwa podwidok,
//  konfliktowało z Focus Engine (patrz komentarz w MediaGridTile.swift) i
//  potrafiło zawiesić pilota nawet na prawdziwym Apple TV.
//
//  showBadge: domyślnie false (zakładka Wideo — wszystkie kafelki to i tak
//  wideo, ikonka play byłaby zbędnym powtórzeniem). true w zakładce
//  "Wszystko" (patrz AllMediaGridTile), gdzie miesza się zdjęcia i wideo —
//  plakietka pozwala odróżnić je na pierwszy rzut oka, tym samym stylem i
//  rozmiarem co plakietka Live Photo w MediaGridTile.swift.
//

import SwiftUI

struct VideoGridTile: View {
    let item: NASMediaItem
    let action: () -> Void
    var showBadge: Bool = false

    @State private var thumbnail: UIImage?
    @State private var thumbnailFailed = false

    /// Patrz komentarz przy init w AsyncImageSMB.swift — miniatura już w
    /// RAM widoczna od pierwszej klatki, bez czekania na .task.
    init(item: NASMediaItem, action: @escaping () -> Void, showBadge: Bool = false) {
        self.item = item
        self.action = action
        self.showBadge = showBadge
        _thumbnail = State(initialValue: ImageCache.shared.image(for: item.imageURL))
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomTrailing) {
                // RoundedRectangle jako widok BAZOWY, a nie ZStack z Image jako
                // rodzeństwem — ten sam bug i ta sama poprawka co w
                // AsyncImageSMB.swift (patrz obszerny komentarz tam): Image z
                // .scaledToFill() celowo chce być większy niż zaproponowany
                // rozmiar, a ten większy rozmiar przeciekał w negocjacji layoutu
                // przez ZStack do rodzica, rozdymając cały wiersz siatki
                // (identyczny efekt jak wcześniej w galerii zdjęć, zanim
                // naprawiliśmy to w AsyncImageSMB — tu po prostu zapomniałem, że
                // VideoGridTile ma WŁASNĄ, osobną kopię tego samego wzorca).
                // .overlay izoluje rozmiar treści od rozmiaru bazowego
                // RoundedRectangle, który zawsze zgłasza dokładnie zaproponowany
                // mu rozmiar.
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.gray.opacity(0.25))
                    .aspectRatio(1, contentMode: .fill)
                    .overlay {
                        if let thumbnail {
                            // Ten sam styl co w galerii zdjęć: .scaledToFill,
                            // żeby wypełnić cały kwadratowy kafelek (przycinając
                            // dłuższy bok) zamiast zostawiać szare pasy tła u
                            // góry/dołu albo po bokach dla niekwadratowych klatek.
                            Image(uiImage: thumbnail)
                                .resizable()
                                .scaledToFill()
                        } else if thumbnailFailed {
                            // Bez miniatury (np. plik za duży, żeby ją tanio
                            // wygenerować, albo błąd sieci) — statyczna ikona,
                            // a nie wiecznie kręcący się ProgressView.
                            VStack(spacing: 14) {
                                Image(systemName: "video")
                                    .font(.system(size: 40))
                                Text(item.baseFileName)
                                    .font(.callout)
                                    .lineLimit(1)
                                    .padding(.horizontal, 16)
                            }
                            .foregroundStyle(.white)
                        } else {
                            VStack(spacing: 14) {
                                ProgressView()
                                Text(item.baseFileName)
                                    .font(.callout)
                                    .lineLimit(1)
                                    .padding(.horizontal, 16)
                            }
                            .foregroundStyle(.white)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                if showBadge {
                    // Te same wartości co plakietka Live Photo w
                    // MediaGridTile.swift (rozmiar/marginesy/.glassEffect) —
                    // na wyraźną prośbę, żeby obie plakietki wyglądały
                    // identycznie w zakładce "Wszystko".
                    Image(systemName: "play.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                        .padding(5)
                        .glassEffect(.regular, in: Circle())
                        .padding(3)
                }
            }
        }
        .buttonStyle(.card)
        .task(id: item.id) {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        thumbnailFailed = false
        if let cached = ImageCache.shared.image(for: item.imageURL) {
            thumbnail = cached
            return
        }
        do {
            thumbnail = try await VideoThumbnailGenerator.shared.thumbnail(for: item.imageURL)
        } catch {
            // Brak miniatury (za duży plik, błąd sieci/dekodowania) nie
            // blokuje odtwarzania — Play i tak ściąga plik od nowa.
            thumbnailFailed = true
        }
    }
}
