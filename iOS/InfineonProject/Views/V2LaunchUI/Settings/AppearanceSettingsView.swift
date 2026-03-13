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

  var id: String { rawValue }

  var localeIdentifier: String? {
    switch self {
    case .system: nil
    case .english: "en"
    }
  }

  var localizedName: String {
    switch self {
    case .system:
      String(localized: "System", bundle: .main)
    case .english:
      Locale.current.localizedString(forIdentifier: "en_US") ?? "English (US)"
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
  @State private var showLanguageConfirmation = false

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
        Button {
          showLanguageConfirmation = true
        } label: {
          HStack {
            Label {
              Text("Language")
            } icon: {
              SettingsBoxView(
                icon: "globe", color: .pink
              )
            }
            Spacer()
            Text(currentLanguage.localizedName)
              .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .foregroundStyle(.primary)
      }
    }
    .navigationTitle("Appearance")
    .confirmationDialog(
      "Select Language", isPresented: $showLanguageConfirmation, titleVisibility: .visible
    ) {
      ForEach(AppLanguage.allCases) { language in
        Button(language.localizedName) {
          appLanguage = language.rawValue
        }
      }
    } message: {
      Text("Changing the language will update the app's display language.")
    }
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
