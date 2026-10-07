//
//  SetupView.swift
//  MediaApp
//
//  Ekran pierwszej konfiguracji — logowanie do udziału SMB na Synology.
//  Zbiera tylko dane dostępowe (host/użytkownik/hasło/udział); wybór
//  folderu głównego dzieje się osobno w PathPickerView, po udanym
//  połączeniu. Dane nie-poufne trafiają do @AppStorage (współdzielone
//  klucze z SMBServerConfig), hasło wyłącznie do Keychain.
//

import SwiftUI
import UIKit

struct SetupView: View {
    @EnvironmentObject private var session: SessionManager

    @AppStorage(SMBCredentialsKeys.host) private var host: String = ""
    @AppStorage(SMBCredentialsKeys.username) private var username: String = ""
    @AppStorage(SMBCredentialsKeys.shareName) private var shareName: String = ""
    @State private var password: String = ""

    @State private var isConnecting = false
    @State private var errorMessage: String?

    /// Konfiguracja (bez remotePath) po udanym teście połączenia —
    /// obecność wartości steruje nawigacją do PathPickerView.
    @State private var connectedConfig: SMBServerConfig?

    private enum Field: Hashable {
        case host, username, password, shareName, connect
    }
    @FocusState private var focusedField: Field?

    private var canSubmit: Bool {
        !isConnecting
            && !host.trimmingCharacters(in: .whitespaces).isEmpty
            && !username.trimmingCharacters(in: .whitespaces).isEmpty
            && !password.isEmpty
            && !shareName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 48) {
                        header

                        // useNativeGlassEffect: true — statyczna karta, bez
                        // sąsiedztwa przewijanej siatki, ten sam poziom
                        // ryzyka co już przetestowana karta w SettingsView
                        // (patrz obszerny komentarz w LiquidGlassCard.swift).
                        LiquidGlassCard(useNativeGlassEffect: true) {
                            VStack(spacing: 32) {
                                field(
                                    title: "Adres hosta",
                                    placeholder: "np. 192.168.1.10 lub nas.local",
                                    text: $host,
                                    field: .host,
                                    contentType: .URL,
                                    keyboardType: .URL
                                )
                                field(
                                    title: "Użytkownik",
                                    placeholder: "np. dawid",
                                    text: $username,
                                    field: .username,
                                    contentType: .username,
                                    keyboardType: .default
                                )
                                secureField(title: "Hasło", text: $password, field: .password)
                                field(
                                    title: "Nazwa udziału",
                                    placeholder: "np. photo",
                                    text: $shareName,
                                    field: .shareName,
                                    contentType: nil,
                                    keyboardType: .default
                                )

                                if let errorMessage {
                                    Text(errorMessage)
                                        .font(.system(size: 26, weight: .semibold))
                                        .foregroundStyle(.red)
                                        .multilineTextAlignment(.center)
                                        .transition(.opacity)
                                }

                                connectButton
                            }
                            .frame(maxWidth: 900)
                        }
                    }
                    .padding(.horizontal, 120)
                    .padding(.vertical, 80)
                }
            }
            .animation(.easeInOut, value: errorMessage)
            .navigationDestination(item: $connectedConfig) { config in
                PathPickerView(baseConfig: config)
            }
            .onAppear { prefillFromStorage() }
        }
    }

    /// Host/użytkownik/udział wracają automatycznie, bo są w @AppStorage —
    /// dociągamy tu tylko hasło (żyje wyłącznie w Keychain, nie w AppStorage),
    /// więc po powrocie z „Zmień ustawienia serwera" formularz jest w pełni
    /// wypełniony i wystarczy kliknąć „Połącz", żeby zmienić np. samą ścieżkę.
    private func prefillFromStorage() {
        guard let saved = SMBServerConfig.loadFromStorage() else { return }
        host = saved.host
        username = saved.username
        shareName = saved.shareName
        password = saved.password
    }

    private var header: some View {
        VStack(spacing: 16) {
            Image(systemName: "server.rack")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("Połącz z serwerem NAS")
                .font(.system(size: 56, weight: .bold))
            Text("Podaj dane logowania do udziału SMB na Twoim Synology. Folder główny wybierzesz w następnym kroku.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Pola formularza

    @ViewBuilder
    private func field(
        title: String,
        placeholder: String,
        text: Binding<String>,
        field: Field,
        contentType: UITextContentType?,
        keyboardType: UIKeyboardType
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField(placeholder, text: text)
                .font(.system(size: 36))
                .textContentType(contentType)
                .keyboardType(keyboardType)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($focusedField, equals: field)
                .padding(.vertical, 20)
                .padding(.horizontal, 28)
                .background(fieldBackground(isFocused: focusedField == field))
        }
    }

    @ViewBuilder
    private func secureField(title: String, text: Binding<String>, field: Field) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.secondary)

            SecureField(title, text: text)
                .font(.system(size: 36))
                .textContentType(.password)
                .focused($focusedField, equals: field)
                .padding(.vertical, 20)
                .padding(.horizontal, 28)
                .background(fieldBackground(isFocused: focusedField == field))
        }
    }

    private func fieldBackground(isFocused: Bool) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isFocused ? Color.accentColor : Color.white.opacity(0.15), lineWidth: isFocused ? 4 : 1)
            )
            .scaleEffect(isFocused ? 1.04 : 1.0)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isFocused)
    }

    // MARK: - Przycisk Połącz

    private var connectButton: some View {
        Button {
            connect()
        } label: {
            Group {
                if isConnecting {
                    ProgressView()
                        .progressViewStyle(.circular)
                } else {
                    Text("Połącz")
                        .font(.system(size: 32, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
        }
        .buttonStyle(.card)
        .focused($focusedField, equals: .connect)
        .disabled(!canSubmit)
    }

    // MARK: - Logika połączenia

    private func connect() {
        guard canSubmit else { return }
        errorMessage = nil
        isConnecting = true

        // remotePath celowo puste — wybierany dopiero w PathPickerView.
        let config = SMBServerConfig(
            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            shareName: shareName.trimmingCharacters(in: .whitespacesAndNewlines),
            domain: "",
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password,
            remotePath: ""
        )

        Task {
            do {
                try await SMBManager.shared.connect(using: config)
                isConnecting = false
                connectedConfig = config
            } catch {
                isConnecting = false
                withAnimation {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

#Preview {
    SetupView()
        .environmentObject(SessionManager())
}
