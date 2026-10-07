//
//  SidebarRowButtonStyle.swift
//  MediaApp
//
//  Płaski styl wiersza bocznej kolumny — lista miesięcy (MonthSidebarList)
//  i menu sekcji Ustawień (SettingsView). Własny ButtonStyle wyłącza na
//  tvOS systemowy efekt fokusu (skalowanie/"uniesienie" wiersza z animacją
//  przy każdym ruchu pilota góra/dół); fokus sygnalizuje tylko płaskie
//  tło, zmieniane bez animacji. Patrz też nagłówek MonthSidebarList.swift.
//

import SwiftUI

struct SidebarRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SidebarRow(configuration: configuration)
    }

    private struct SidebarRow: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(isFocused ? 0.2 : 0))
                )
                .opacity(configuration.isPressed ? 0.7 : 1)
                .animation(nil, value: isFocused)
                .animation(nil, value: configuration.isPressed)
        }
    }
}
