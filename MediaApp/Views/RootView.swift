//
//  RootView.swift
//  MediaApp
//
//  Decyduje, czy pokazać SetupView (brak zapisanej konfiguracji SMB),
//  czy od razu przejść do MainTabView. Właściciel SessionManager —
//  wstrzykuje go do obu gałęzi, żeby dowolny widok mógł się wylogować.
//

import SwiftUI

struct RootView: View {
    @StateObject private var session = SessionManager()

    var body: some View {
        Group {
            if session.isConfigured {
                MainTabView()
                    .transition(.opacity)
            } else {
                SetupView()
                    .transition(.opacity)
            }
        }
        .environmentObject(session)
    }
}

#Preview {
    RootView()
}
