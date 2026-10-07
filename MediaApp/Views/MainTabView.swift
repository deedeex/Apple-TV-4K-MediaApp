//
//  MainTabView.swift
//  MediaApp
//

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var session: SessionManager

    // Właściciel biblioteki (zdjęcia + wideo) — skanowanie NAS-a startuje od
    // razu przy wejściu do MainTabView (w tle) i trwa przez całą sesję, a nie
    // dopiero gdy użytkownik przełączy się na daną zakładkę albo do niej
    // wróci (patrz komentarz w MediaLibraryStore.swift).
    @StateObject private var mediaLibrary = MediaLibraryStore()

    var body: some View {
        // "Wszystko" jako PIERWSZA zakładka — TabView bez jawnego selection:
        // domyślnie zaznacza pierwszą pozycję w kolejności deklaracji, więc
        // to jednocześnie ustawia ją jako domyślnie ładowaną przy starcie.
        TabView {
            AllGalleryView()
                .tabItem {
                    Label("Wszystko", systemImage: "square.grid.2x2.fill")
                }
            PhotoGalleryView()
                .tabItem {
                    Label("Zdjęcia", systemImage: "photo.on.rectangle.angled")
                }
            VideoGalleryView()
                .tabItem {
                    Label("Wideo", systemImage: "play.tv.fill")
                }
            SettingsView()
                .tabItem {
                    Label("Ustawienia", systemImage: "gearshape")
                }
        }
        .environmentObject(mediaLibrary)
        .onAppear {
            mediaLibrary.start()
        }
        // SetupView jako .fullScreenCover NAD tym widokiem (nie podmiana
        // korzenia w RootView) — MainTabView/mediaLibrary zostają żywe pod
        // spodem przez cały czas edycji, więc Menu na pilocie naturalnie
        // zamyka okładkę i wraca tutaj. Patrz obszerny komentarz przy
        // isEditingSetup w SessionManager.swift o tym, jaki konkretny bug to
        // naprawia.
        .fullScreenCover(isPresented: $session.isEditingSetup) {
            SetupView()
        }
        .onChange(of: session.configVersion) { _, _ in
            // Odpala się WYŁĄCZNIE po udanym zapisaniu nowej konfiguracji
            // (nie przy zwykłym anulowaniu edycji przez Menu) — patrz
            // komentarz przy configVersion w SessionManager.swift. mediaLibrary
            // NIE jest tworzone od nowa (w przeciwieństwie do wcześniejszego
            // zachowania z podmianą korzenia), więc trzeba jawnie zlecić
            // odświeżenie pod ewentualnie nowym serwerem/ścieżką.
            mediaLibrary.reload()
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(SessionManager())
        .environmentObject(MediaLibraryStore())
}
