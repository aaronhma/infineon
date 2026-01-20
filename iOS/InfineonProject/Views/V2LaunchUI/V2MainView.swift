//
//  V2MainView.swift
//  InfineonProject
//
//  Created by Aaron Ma on 1/16/26.
//

import AaronUI
import SwiftUI

struct V2MainView: View {
  @State var appData = V2AppData()

  @State private var showingSignOutConfirmation = false

  var body: some View {
    ZStack {
      VStack(spacing: 0) {
        if let profile = appData.watchingProfile, !appData.animateProfile {
          Group {
            switch appData.activeTab {
            case .home:
              VehicleView(vehicle: profile)
            case .new:
              HomeView(vehicle: profile)
            case .account:
              NavigationStack {
                List {
                  Section {
                    VStack(
                      alignment: .leading,
                      spacing: 8
                    ) {
                      Text("InfineonProject")
                        .font(.headline)

                      Text("© 2026 Aaron Ma.")
                        .font(.subheadline)
                        .foregroundColor(.gray)

                      Text(
                        "Made with 💖 from Cupertino, CA."
                      )
                      .font(.subheadline)
                      .foregroundColor(.gray)

                      Link(
                        destination: URL(
                          string: "https://github.com/aaronhma"
                        )!
                      ) {
                        Text("@aaronhma")
                      }
                      .foregroundStyle(.primary)
                    }
                    .padding(.vertical, 4)
                  }

                  Section("AaronUI") {
                    Text(
                      "This app was made with AaronUI, the world's best way to build high-quality iOS apps quickly. This package is available for purchase for $99/year."
                    )

                    NavigationLink {
                      List {
                        Section("Open Source Components") {
                          Text("swift-asn1")
                          Text("swift-clocks")
                          Text("swift-concurrency-extras")
                          Text("swift-crypto")
                          Text("swift-http-types")
                          Text("xctest-dynamic-overlay")
                        }
                      }
                      .navigationTitle("Open Source Components")
                      .navigationBarTitleDisplayMode(.inline)
                    } label: {
                      Text("Open-Source Components")
                    }
                  }

                  Section {
                    Button(role: .destructive) {
                      Haptics.impact()
                      showingSignOutConfirmation = true
                    } label: {
                      Label {
                        Text("Sign out")
                      } icon: {
                        SettingsBoxView(
                          icon: "rectangle.portrait.and.arrow.right",
                          color: .red
                        )
                      }
                    }
                    .confirmationDialog(
                      "Are you sure you want to sign out?",
                      isPresented: $showingSignOutConfirmation,
                      titleVisibility: .visible
                    ) {
                      Button(
                        "Sign out",
                        role: .destructive
                      ) {
                        Haptics.impact()

                        Task {
                          try? await supabase
                            .signOut()
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

        if appData.watchingProfile != nil {
          V2LaunchUITabView()
        }
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
          .controlSize(.extraLarge)
          .task {
            await supabase.loadVehicles()
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
