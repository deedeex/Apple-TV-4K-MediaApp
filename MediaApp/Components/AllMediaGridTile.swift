//
//  AllMediaGridTile.swift
//  MediaApp
//
//  Kafelek w zakładce "Wszystko" (patrz AllGalleryView) — dispatch do
//  właściwego, już istniejącego kafelka wg typu pozycji: zdjęcia/Live Photo
//  idą przez MediaGridTile (dekodowanie ImageIO), wideo przez VideoGridTile
//  (dekodowanie klatki przez AVAssetImageGenerator) — to dwa różne
//  pipeline'y dekodowania miniatur, nie da się użyć jednego dla obu typów
//  (patrz komentarz w VideoGridTile.swift o tym, dlaczego NIE używa
//  AsyncImageSMB — plik wideo nie jest obrazem, ImageIO by go nie otworzył).
//
//  showBadge: true na VideoGridTile TYLKO tutaj — w tym mieszanym widoku
//  plakietka play jest potrzebna, żeby odróżnić kafelek wideo od zdjęcia na
//  pierwszy rzut oka. W zakładce Wideo (gdzie i tak wszystko jest wideo)
//  VideoGridTile zostaje bez zmian, bez plakietki (showBadge domyślnie false).
//

import SwiftUI

struct AllMediaGridTile: View {
    let item: NASMediaItem
    let action: () -> Void

    var body: some View {
        switch item.type {
        case .photo, .livePhoto:
            MediaGridTile(item: item, action: action)
        case .video:
            VideoGridTile(item: item, action: action, showBadge: true)
        }
    }
}
