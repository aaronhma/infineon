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

struct ThemeSwitcher<Content: View>: View {
  @ViewBuilder var content: Content
  @AppStorage("_appTheme") private var appTheme = AppTheme.system

  var body: some View {
    content
      .preferredColorScheme(appTheme.colorScheme)
  }
}

struct AppearanceSettingsView: View {
  @AppStorage("_appTheme") private var appTheme = AppTheme.system

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 50) {
        HStack {
          ForEach(AppTheme.allCases, id: \.self) {
            appearanceButton($0)
          }
        }

        Picker(selection: .constant("English")) {
          Text("English")
            .tag("English")
        } label: {
          Label {
            Text("Language")
          } icon: {
            SettingsBoxView(
              icon: "globe", color: .pink
            )
          }
        }
        .pickerStyle(.navigationLink)
        .modifier(BackgroundShadowModifier())
      }
      .padding(.horizontal)
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
          .fill(appTheme == theme ? AnyShapeStyle(.secondary) : AnyShapeStyle(.ultraThinMaterial))
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
    .modifier(BackgroundShadowModifier())
  }
}

#Preview {
  NavigationStack {
    AppearanceSettingsView()
  }
}
