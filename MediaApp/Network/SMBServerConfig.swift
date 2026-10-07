//
//  SMBServerConfig.swift
//  MediaApp
//
//  Konfiguracja serwera Synology wprowadzana w SetupView. Parametry
//  nie-poufne żyją w UserDefaults (przez @AppStorage w SetupView),
//  hasło trafia wyłącznie do Keychain (KeychainStore).
//

import Foundation

/// Klucze UserDefaults współdzielone z @AppStorage w SetupView —
/// jedno źródło prawdy, żeby nazwy się nie rozjechały.
enum SMBCredentialsKeys {
    static let host = "smb.host"
    static let username = "smb.username"
    static let shareName = "smb.shareName"
    static let remotePath = "smb.remotePath"
}

struct SMBServerConfig: Sendable, Equatable, Hashable {
    var host: String
    var shareName: String
    var domain: String
    var username: String
    var password: String
    var remotePath: String

    var baseURL: URL? {
        URL(string: "smb://\(host)")
    }

    /// Odczytuje aktualną konfigurację zapisaną przez SetupView. Zwraca nil,
    /// dopóki użytkownik nie przeszedł pomyślnie pierwszej konfiguracji.
    static func loadFromStorage() -> SMBServerConfig? {
        let defaults = UserDefaults.standard
        guard
            let host = defaults.string(forKey: SMBCredentialsKeys.host), !host.isEmpty,
            let shareName = defaults.string(forKey: SMBCredentialsKeys.shareName), !shareName.isEmpty,
            let username = defaults.string(forKey: SMBCredentialsKeys.username), !username.isEmpty,
            let password = KeychainStore.readPassword(), !password.isEmpty
        else { return nil }

        let remotePath = defaults.string(forKey: SMBCredentialsKeys.remotePath) ?? ""

        return SMBServerConfig(
            host: host,
            shareName: shareName,
            domain: "",
            username: username,
            password: password,
            remotePath: remotePath
        )
    }

    /// Zapisuje konfigurację — wywoływane przez SetupView dopiero po udanym
    /// teście połączenia, żeby nie utrwalać błędnych danych.
    static func save(_ config: SMBServerConfig) {
        let defaults = UserDefaults.standard
        defaults.set(config.host, forKey: SMBCredentialsKeys.host)
        defaults.set(config.shareName, forKey: SMBCredentialsKeys.shareName)
        defaults.set(config.username, forKey: SMBCredentialsKeys.username)
        defaults.set(config.remotePath, forKey: SMBCredentialsKeys.remotePath)
        KeychainStore.savePassword(config.password)
    }
}
