//
//  SessionManager.swift
//  MediaApp
//
//  Współdzielony stan „czy mamy skonfigurowany serwer NAS". Wstrzykiwany
//  przez RootView jako @EnvironmentObject, żeby dowolny widok (ekran błędu
//  SMB, stały przycisk ustawień w MainTabView) mógł otworzyć SetupView bez
//  przekazywania zamknięć przez wiele warstw.
//

import SwiftUI
import Combine

@MainActor
final class SessionManager: ObservableObject {
    @Published private(set) var isConfigured: Bool

    /// Steruje prezentacją SetupView jako .fullScreenCover NAD MainTabView
    /// (patrz MainTabView.swift) — używane przez „Zmień ustawienia serwera"
    /// w SettingsView i przez ekran błędu w PhotoGalleryView.
    ///
    /// Wcześniej ten sam przycisk wołał metodę, która zerowała isConfigured —
    /// RootView (zwykły if/else, BEZ NavigationStack/.sheet) podmieniał wtedy
    /// CAŁY korzeń widoku z MainTabView na SetupView. Problem: SetupView jako
    /// podmieniony ROOT nie miało niczego do "cofnięcia" przyciskiem Menu na
    /// pilocie — tvOS spadał do domyślnego zachowania systemowego, czyli
    /// wyjścia do ekranu głównego Apple TV, zamiast wrócić do aplikacji.
    ///
    /// beginEditingSetup() CELOWO nie odłącza SMB ani nie zeruje isConfigured —
    /// MainTabView i jego MediaLibraryStore zostają żywe pod spodem przez cały
    /// czas edycji, więc Menu na pilocie naturalnie zamyka .fullScreenCover i
    /// wraca do apki (standardowe zachowanie tvOS dla .fullScreenCover — ten
    /// sam wzorzec, co w MediaPagerView/VideoPlaybackView), a anulowanie bez
    /// zapisania nowej konfiguracji nie ma żadnych skutków ubocznych.
    @Published var isEditingSetup = false

    /// Zwiększane WYŁĄCZNIE przy udanym zapisaniu nowej konfiguracji
    /// (markConfigured(), wołane z PathPickerView.setAsRoot()). MainTabView
    /// obserwuje to przez .onChange, żeby odświeżyć bibliotekę pod nowym
    /// serwerem/ścieżką — ale TYLKO gdy edycja faktycznie się powiodła, nie
    /// przy zwykłym anulowaniu (Menu bez zapisania), bo wtedy ta wartość się
    /// nie zmienia i .onChange w ogóle się nie odpala.
    @Published private(set) var configVersion = 0

    init() {
        isConfigured = SMBServerConfig.loadFromStorage() != nil
    }

    /// Wywoływane przez PathPickerView po udanym połączeniu i wybraniu
    /// folderu głównego — zamyka .fullScreenCover (jeśli był otwarty przez
    /// beginEditingSetup()) i sygnalizuje MainTabView potrzebę odświeżenia
    /// biblioteki. Przy pierwszej konfiguracji (RootView jeszcze pokazuje
    /// SetupView jako korzeń) po prostu przełącza RootView na MainTabView.
    func markConfigured() {
        configVersion += 1
        withAnimation(.easeInOut(duration: 0.6)) {
            isConfigured = true
            isEditingSetup = false
        }
    }

    func beginEditingSetup() {
        isEditingSetup = true
    }
}
