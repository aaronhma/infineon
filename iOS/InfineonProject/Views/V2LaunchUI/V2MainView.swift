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

      if appData.showProfileView {
        Rectangle()
          .fill(.black)
          .ignoresSafeArea()
          .transition(.identity)
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
