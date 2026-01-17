//
//  V2MainView.swift
//  InfineonProject
//
//  Created by Aaron Ma on 1/16/26.
//

import SwiftUI

struct V2MainView: View {
  @State var appData = V2AppData()

  var body: some View {
    ZStack {
      VStack {
        Spacer(minLength: 0)

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

      ZStack {
        if let profile = appData.watchingProfile, !appData.animateProfile {
          Group {
            switch appData.activeTab {
            case .home:
              HomeView()
            case .new:
              VehicleView()
            case .account:
              Text("Long hold to change tabs.")
            }
          }
        }
      }

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
