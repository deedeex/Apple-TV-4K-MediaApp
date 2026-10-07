//
//  SettingsView.swift
//  MediaApp
//
//  Stała zakładka w MainTabView — pozwala w dowolnym momencie wrócić do
//  SetupView, żeby zmienić dane serwera NAS (np. tylko ścieżkę), bez
//  konieczności trafienia najpierw na błąd SMB. Zapisane dane dostępowe
//  zostają nietknięte — SetupView doczyta je i wypełni nimi formularz.
//
//  Przycisk "Odśwież bibliotekę" — MediaLibraryStore skanuje NAS tylko RAZ
//  na sesję (start(), wołane z MainTabView.onAppear, ma strażnika didStart —
//  patrz komentarz tam), więc pliki dodane na NAS-ie po starcie aplikacji
//  same się nie pojawią, dopóki nie zrestartujesz appki. To jedyne miejsce
//  w normalnym przeglądaniu (poza przyciskiem "Spróbuj ponownie" na ekranie
//  BŁĘDU w PhotoGalleryView/VideoGalleryView), które pozwala wymusić świeży
//  skan bez zamykania aplikacji.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var session: SessionManager
    @EnvironmentObject private var library: MediaLibraryStore

    private let config = SMBServerConfig.loadFromStorage()

    var body: some View {
        VStack(spacing: 40) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Ustawienia serwera")
                .font(.system(size: 48, weight: .bold))

            if let config {
                // useNativeGlassEffect: true — patrz obszerny komentarz w
                // LiquidGlassCard.swift o tym, dlaczego TYLKO tutaj (statyczna
                // karta, bez sąsiedztwa siatki/fokusu w ruchu) i dlaczego to
                // na razie ostrożny test, nie domyślne zachowanie wszędzie.
                LiquidGlassCard(useNativeGlassEffect: true) {
                    VStack(alignment: .leading, spacing: 16) {
                        infoRow(title: "Host", value: config.host)
                        infoRow(title: "Udział", value: config.shareName)
                        infoRow(title: "Użytkownik", value: config.username)
                        if !config.remotePath.isEmpty {
                            infoRow(title: "Ścieżka", value: config.remotePath)
                        }
                    }
                    .frame(maxWidth: 1100)
                }
            }

            Button {
                library.reload()
            } label: {
                HStack {
                    if library.isLoading {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text("Odśwież bibliotekę")
                }
                .font(.system(size: 30, weight: .semibold))
                .frame(maxWidth: 520)
                .padding(.vertical, 20)
            }
            .buttonStyle(.card)
            // Zablokowane w trakcie trwającego skanu — reload() i tak nie ma
            // własnej ochrony przed wielokrotnym wywołaniem (w przeciwieństwie
            // do start()), więc bez tego kilka szybkich kliknięć odpalałoby
            // kilka równoległych pełnych skanów NAS-a naraz.
            .disabled(library.isLoading)

            Button {
                session.beginEditingSetup()
            } label: {
                Text("Zmień ustawienia serwera")
                    .font(.system(size: 30, weight: .semibold))
                    .frame(maxWidth: 520)
                    .padding(.vertical, 20)
            }
            .buttonStyle(.card)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(80)
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

#Preview {
    SettingsView()
        .environmentObject(SessionManager())
        .environmentObject(MediaLibraryStore())
}
