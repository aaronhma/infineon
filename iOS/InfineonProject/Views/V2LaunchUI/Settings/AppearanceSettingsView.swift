//
//  AppearanceSettingsView.swift
//  InfineonProject
//
//  Created by Aaron Ma on 2/19/26.
//

import AaronUI
import SwiftUI

private enum AppTheme: String, CaseIterable {
  case system = "System"
  case light = "Light"
  case dark = "Dark"

  var icon: String {
    switch self {
    case .system:
      "circle.righthalf.filled"
    case .light:
      "sun.max.fill"
    case .dark:
      "moon.fill"
    }
  }

  var colorScheme: ColorScheme? {
    switch self {
    case .system:
      nil
    case .light:
      .light
    case .dark:
      .dark
    }
  }
}

enum AppLanguage: String, Identifiable, CaseIterable {
  case system
  case english = "en"
  case spanish = "es"
  case french = "fr"
  case german = "de"
  case persian = "fa"
  case chineseSimplified = "zh-Hans"
  case chineseTraditional = "zh-Hant"

  var id: String { rawValue }

  var localeIdentifier: String? {
    switch self {
    case .system: nil
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
    case .system:
      String(localized: "System", bundle: .main)
    case .english:
      Locale.current.localizedString(forIdentifier: "en_US") ?? "English (US)"
    case .spanish:
      Locale.current.localizedString(forIdentifier: "es") ?? "Spanish"
    case .french:
      Locale.current.localizedString(forIdentifier: "fr") ?? "French"
    case .german:
      Locale.current.localizedString(forIdentifier: "de") ?? "German"
    case .persian:
      Locale.current.localizedString(forIdentifier: "fa") ?? "Persian"
    case .chineseSimplified:
      Locale.current.localizedString(forIdentifier: "zh-Hans") ?? "Chinese (Simplified)"
    case .chineseTraditional:
      Locale.current.localizedString(forIdentifier: "zh-Hant") ?? "Chinese (Traditional)"
    }
  }
}

struct ThemeSwitcher<Content: View>: View {
  @ViewBuilder var content: Content
  @AppStorage("_appTheme") private var appTheme = AppTheme.system

  var body: some View {
    content
      .preferredColorScheme(appTheme.colorScheme)
  }
}

struct LocaleSwitcher<Content: View>: View {
  @ViewBuilder var content: Content
  @AppStorage("_appLanguage") private var appLanguage = AppLanguage.system.rawValue

  private var currentLocale: Locale {
    guard let language = AppLanguage(rawValue: appLanguage),
      let identifier = language.localeIdentifier
    else {
      return .current
    }
    return Locale(identifier: identifier)
  }

  var body: some View {
    content
      .environment(\.locale, currentLocale)
  }
}

struct AppearanceSettingsView: View {
  @AppStorage("_appTheme") private var appTheme = AppTheme.system
  @AppStorage("_appLanguage") private var appLanguage = AppLanguage.system.rawValue

  private var currentLanguage: AppLanguage {
    AppLanguage(rawValue: appLanguage) ?? .system
  }

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
        Picker(selection: $appLanguage) {
          ForEach(AppLanguage.allCases) { language in
            Text(language.localizedName)
              .tag(language.rawValue)
          }
        } label: {
          Label {
            Text("Language")
          } icon: {
            SettingsBoxView(
              icon: "globe", color: .pink
            )
          }
        }
      }
    }
    .navigationTitle("Appearance")
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
              : AnyShapeStyle(
                .background
              )
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
