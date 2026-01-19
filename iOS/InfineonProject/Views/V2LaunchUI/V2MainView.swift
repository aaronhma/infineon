//
//  V2MainView.swift
//  InfineonProject
//
//  Created by Aaron Ma on 1/16/26.
//

import AaronUI
import SwiftUI

struct V2MainView: View {
  @AppStorage("showOnboarding") private var showOnboarding = true

  @State var appData = V2AppData()

  @State private var showingSignOutConfirmation = false

  var body: some View {
    ZStack {
      VStack(spacing: 0) {
        if let profile = appData.watchingProfile, !appData.animateProfile {
          Group {
            switch appData.activeTab {
            case .home:
              HomeView()
            case .new:
              VehicleView()
            case .account:
              NavigationStack {
                List {
                  Section {
                    Text("No settings yet.")
                  }

                  Section {
                    Button(role: .destructive) {
                      Haptics.impact()
                      showingSignOutConfirmation = true
                    } label: {
                      Label {
                        Text("Sign out")
                      } icon: {
                        SettingsBoxView(icon: "rectangle.portrait.and.arrow.right", color: .red)
                      }
                    }
                    .confirmationDialog(
                      "Are you sure you want to sign out?",
                      isPresented: $showingSignOutConfirmation,
                      titleVisibility: .visible
                    ) {
                      Button("Sign out", role: .destructive) {
                        Haptics.impact()

                        Task {
                          try? await supabase.signOut()
                          showOnboarding = true
                        }
                      }
                      Button("Cancel", role: .cancel) {}
                    }
                  }
                }
                .navigationTitle("Account")
              }
            }
          }
          .frame(maxHeight: .infinity)
        } else {
          Spacer(minLength: 0)
        }

        V2LaunchUITabView()
      }
      .coordinateSpace(.named("MAINVIEW"))

      if appData.hideMainView {
        Rectangle()
          .fill(.black)
          .ignoresSafeArea()
      }

      ZStack {
        if appData.showProfileView {
          V2ProfileSelectView()
        }
      }
      .animation(.snappy, value: appData.showProfileView)

      if !appData.isSplashFinished {
        ProgressView()
          .task {
            try? await Task.sleep(for: .seconds(1))
            appData.isSplashFinished = true
            appData.showProfileView = appData.isSplashFinished
            appData.hideMainView = appData.showProfileView
          }
      }
    }
    .environment(appData)
    .preferredColorScheme(.dark)
  }
}

#Preview {
  V2MainView()
}
