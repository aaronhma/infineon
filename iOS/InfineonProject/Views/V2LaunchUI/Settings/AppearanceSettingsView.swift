//
//  AppearanceSettingsView.swift
//  InfineonProject
//
//  Created by Aaron Ma on 2/19/26.
//

import AaronUI
import SwiftUI

// MARK: - Bundle Language Switching

private let _mainBundlePath = Bundle.main.bundlePath
private var _activeLanguageBundle: Bundle?
private var _bundleSwapped = false

private final class _LanguageBundle: Bundle, @unchecked Sendable {
  override func localizedString(forKey key: String, value: String?, table tableName: String?)
    -> String
  {
    if let bundle = _activeLanguageBundle {
      return bundle.localizedString(forKey: key, value: value, table: tableName)
    }
    return super.localizedString(forKey: key, value: value, table: tableName)
  }
}

extension Bundle {
  static func setLanguage(_ languageCode: String?) {
    if !_bundleSwapped {
      object_setClass(Bundle.main, _LanguageBundle.self)
      _bundleSwapped = true
    }
    guard let code = languageCode,
      let lookup = Bundle(path: _mainBundlePath),
      let lpath = lookup.path(forResource: code, ofType: "lproj")
    else {
      _activeLanguageBundle = nil
      return
    }
    _activeLanguageBundle = Bundle(path: lpath)
  }
}

// MARK: - App Theme

private enum AppTheme: String, CaseIterable {
  case system = "System"
  case light = "Light"
  case dark = "Dark"

  var icon: String {
    switch self {
    case .system: "circle.righthalf.filled"
    case .light: "sun.max.fill"
    case .dark: "moon.fill"
    }
  }

  var colorScheme: ColorScheme? {
    switch self {
    case .system: nil
    case .light: .light
    case .dark: .dark
    }
  }
}

// MARK: - App Language

enum AppLanguage: String, Identifiable, CaseIterable {
  case english = "en"
  case spanish = "es"
  case french = "fr"
  case german = "de"
  case persian = "fa"
  case chineseSimplified = "zh-Hans"
  case chineseTraditional = "zh-Hant"

  var id: String { rawValue }

  var localeIdentifier: String {
    switch self {
    case .english: "en_US"
    case .spanish: "es"
    case .french: "fr"
    case .german: "de"
    case .persian: "fa"
    case .chineseSimplified: "zh-Hans"
    case .chineseTraditional: "zh-Hant"
    }
  }

  var localizedName: String {
    switch self {
    case .english: Locale.current.localizedString(forIdentifier: "en_US") ?? "English (US)"
    case .spanish: Locale.current.localizedString(forIdentifier: "es") ?? "Spanish"
    case .french: Locale.current.localizedString(forIdentifier: "fr") ?? "French"
    case .german: Locale.current.localizedString(forIdentifier: "de") ?? "German"
    case .persian: Locale.current.localizedString(forIdentifier: "fa") ?? "Persian"
    case .chineseSimplified:
      Locale.current.localizedString(forIdentifier: "zh-Hans") ?? "Chinese (Simplified)"
    case .chineseTraditional:
      Locale.current.localizedString(forIdentifier: "zh-Hant") ?? "Chinese (Traditional)"
    }
  }
}

// MARK: - Language Manager

@Observable
final class LanguageManager {
  @ObservationIgnored
  @AppStorage("_appLanguage") private var _storedLanguage = AppLanguage.english.rawValue

  private(set) var renderID = UUID()

  var currentLanguage: AppLanguage {
    AppLanguage(rawValue: _storedLanguage) ?? .english
  }

  var locale: Locale {
    Locale(identifier: currentLanguage.localeIdentifier)
  }

  init() {
    Bundle.setLanguage(currentLanguage.localeIdentifier)
  }

  func setLanguage(_ language: AppLanguage) {
    _storedLanguage = language.rawValue
    Bundle.setLanguage(language.localeIdentifier)
    renderID = UUID()
  }
}

// MARK: - Switchers

struct ThemeSwitcher<Content: View>: View {
  @ViewBuilder var content: Content
  @AppStorage("_appTheme") private var appTheme = AppTheme.system

  var body: some View {
    content
      .preferredColorScheme(appTheme.colorScheme)
  }
}

// MARK: - Appearance Settings

struct AppearanceSettingsView: View {
  @AppStorage("_appTheme") private var appTheme = AppTheme.system
  @Environment(LanguageManager.self) private var languageManager

  @State private var pendingLanguage: AppLanguage?
  @State private var showLanguageConfirmation = false

  var body: some View {
    List {
      Section {
        HStack {
          ForEach(AppTheme.allCases, id: \.self) {
            appearanceButton($0)
          }
        }
      }
      .listRowInsets(EdgeInsets())
      .listRowBackground(Color.clear)
      .listRowSeparator(.hidden)
      .listSectionSeparator(.hidden)

      Section {
        Picker(
          selection: .init(
            get: { languageManager.currentLanguage },
            set: { newValue in
              if newValue != languageManager.currentLanguage {
                Haptics.impact()
                pendingLanguage = newValue
                showLanguageConfirmation = true
              }
            }
          )
        ) {
          ForEach(AppLanguage.allCases) { language in
            Text(language.localizedName)
              .tag(language)
          }
        } label: {
          Label {
            Text("Language")
          } icon: {
            SettingsBoxView(icon: "globe", color: .pink)
          }
        }
      }
    }
    .navigationTitle("Appearance")
    .confirmationDialog(
      "Change Language",
      isPresented: $showLanguageConfirmation,
      presenting: pendingLanguage,
      actions: { language in
        Button("Yes") {
          languageManager.setLanguage(language)
          pendingLanguage = nil
        }
        Button("No", role: .cancel) {
          pendingLanguage = nil
        }
      },
      message: { language in
        Text("Switch language to \(language.localizedName)?")
      }
    )
  }

  @ViewBuilder
  private func appearanceButton(_ theme: AppTheme) -> some View {
    Button {
      appTheme = theme
    } label: {
      VStack {
        RoundedRectangle(cornerRadius: 16)
          .fill(
            appTheme == theme
              ? AnyShapeStyle(.ultraThinMaterial)
              : AnyShapeStyle(.background)
          )
          .frame(height: 120)
          .frame(maxWidth: .infinity)
          .overlay {
            Image(systemName: theme.icon)
              .font(.title)
              .foregroundStyle(Color.primary)
          }

        Text(theme.rawValue)
          .foregroundStyle(Color.primary)
      }
    }
    .buttonStyle(.plain)
    .modifier(BackgroundShadowModifier())
  }
}

#Preview("Light Mode") {
  NavigationStack {
    AppearanceSettingsView()
      .preferredColorScheme(.light)
  }
}

#Preview("Dark Mode") {
  NavigationStack {
    AppearanceSettingsView()
      .preferredColorScheme(.dark)
  }
}
