//
//  PathPickerView.swift
//  MediaApp
//
//  Drugi krok konfiguracji — po udanym zalogowaniu do udziału SMB
//  (SetupView) użytkownik przegląda jego zawartość przez AMSMB2 i wybiera
//  folder główny. Każdy poziom to osobna instancja tego widoku wypychana
//  na NavigationStack, więc "cofnij" (Menu na pilocie) działa natywnie;
//  dodatkowo jest jawny przycisk "Wstecz" w nagłówku.
//

import SwiftUI

struct PathPickerView: View {
    let baseConfig: SMBServerConfig
    var path: String = ""

    @EnvironmentObject private var session: SessionManager
    @Environment(\.dismiss) private var dismiss

    @State private var entries: [SMBDirectoryEntry] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isSaving = false

    private var displayPath: String {
        path.isEmpty ? "/" : "/\(path)"
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 40) {
                // useNativeGlassEffect: true — statyczna karta nagłówka, poza
                // przewijaną listą folderów niżej. Patrz komentarz w
                // LiquidGlassCard.swift.
                LiquidGlassCard(useNativeGlassEffect: true) {
                    VStack(spacing: 20) {
                        HStack {
                            if !path.isEmpty {
                                Button {
                                    dismiss()
                                } label: {
                                    Label("Wstecz", systemImage: "chevron.left")
                                        .font(.system(size: 24, weight: .semibold))
                                }
                                .buttonStyle(.card)
                            }
                            Spacer()
                        }

                        Text("Wybierz folder główny")
                            .font(.system(size: 44, weight: .bold))
                        Text(displayPath)
                            .font(.title3)
                            .foregroundStyle(.secondary)

                        setFolderButton
                    }
                    .frame(maxWidth: 900)
                }

                content
            }
            .padding(.horizontal, 100)
            .padding(.vertical, 70)
        }
        .task { await load() }
    }

    // MARK: - Przycisk „Ustaw ten folder jako główny"

    private var setFolderButton: some View {
        Button {
            setAsRoot()
        } label: {
            Group {
                if isSaving {
                    ProgressView()
                        .progressViewStyle(.circular)
                } else {
                    Label("Ustaw ten folder jako główny", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 26, weight: .semibold))
                }
            }
            .frame(maxWidth: 700)
            .padding(.vertical, 18)
        }
        .buttonStyle(.card)
        .disabled(isSaving || isLoading)
    }

    // MARK: - Lista zawartości katalogu

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView("Wczytywanie zawartości…")
        } else if let errorMessage {
            // useNativeGlassEffect: true — statyczny ekran błędu.
            LiquidGlassCard(useNativeGlassEffect: true) {
                VStack(spacing: 16) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.largeTitle)
                    Text(errorMessage)
                        .multilineTextAlignment(.center)
                    Button("Spróbuj ponownie") {
                        Task { await load() }
                    }
                }
            }
        } else if entries.isEmpty {
            Text("Ten folder jest pusty.")
                .foregroundStyle(.secondary)
        } else {
            ScrollView {
                LazyVStack(spacing: 20) {
                    ForEach(entries) { entry in
                        if entry.isDirectory {
                            NavigationLink {
                                PathPickerView(baseConfig: baseConfig, path: entry.path)
                            } label: {
                                row(entry: entry)
                            }
                            .buttonStyle(.card)
                        } else {
                            row(entry: entry)
                                .opacity(0.4)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private func row(entry: SMBDirectoryEntry) -> some View {
        HStack(spacing: 20) {
            Image(systemName: entry.isDirectory ? "folder.fill" : "doc")
                .font(.title2)
            Text(entry.name)
                .font(.title3)
                .lineLimit(1)
            Spacer()
            if entry.isDirectory {
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 28)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Logika

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            entries = try await SMBManager.shared.listDirectory(atPath: path)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func setAsRoot() {
        isSaving = true
        var finalConfig = baseConfig
        finalConfig.remotePath = path
        SMBServerConfig.save(finalConfig)
        session.markConfigured()
    }
}

#Preview {
    NavigationStack {
        PathPickerView(baseConfig: SMBServerConfig(
            host: "nas.local",
            shareName: "photo",
            domain: "",
            username: "demo",
            password: "demo",
            remotePath: ""
        ))
    }
    .environmentObject(SessionManager())
}
