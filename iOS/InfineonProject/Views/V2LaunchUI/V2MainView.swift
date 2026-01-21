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
              V2AccountView()
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
