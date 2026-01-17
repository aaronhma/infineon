//
//  V2LaunchUITabView.swift
//  InfineonProject
//
//  Created by Aaron Ma on 1/16/26.
//

import AaronUI
import SwiftUI

enum V2Tab: String, CaseIterable {
  case home = "Home"
  case new = "New & Hot"
  case account = "Account"

  var icon: String {
    switch self {
    case .home:
      "house.fill"
    case .new:
      "play.rectangle.on.rectangle"
    case .account:
      "__profileImage__"
    }
  }
}

struct V2Profile: Identifiable {
  var id = UUID()
  var name: String
  var icon: String

  var sourceAnchorID: String {
    id.uuidString + "SOURCE"
  }

  var destinationAnchorID: String {
    id.uuidString + "DESTINATION"
  }
}

var mockProfiles: [V2Profile] = [
  .init(name: "Benji", icon: "benji"), .init(name: "Benji 2", icon: "benji"),
]

@Observable
class V2AppData {
  var isSplashFinished = false
  var activeTab = V2Tab.home
  var showProfileView = false
  var tabProfileRect: CGRect = .zero
  var watchingProfile: V2Profile?
  var animateProfile = false
}

private struct NoAnimationButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
  }
}

struct V2LaunchUITabView: View {
  @Environment(V2AppData.self) private var appData

  var body: some View {
    HStack(spacing: 0) {
      ForEach(V2Tab.allCases, id: \.rawValue) { tab in
        Button {
          Haptics.impact()
          appData.activeTab = tab
        } label: {
          VStack(spacing: 2) {
            Group {
              if tab.icon == "__profileImage__" {
                GeometryReader { proxy in
                  let rect = proxy.frame(in: .named("MAINVIEW"))

                  Image(.benji)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 25, height: 25)
                    .clipShape(.rect(cornerRadius: 4))

                  Color.clear
                    .preference(key: RectKey.self, value: rect)
                    .onPreferenceChange(RectKey.self) {
                      appData.tabProfileRect = $0
                    }
                }
                .frame(width: 35, height: 35)
              } else {
                Image(systemName: tab.icon)
                  .font(.title3)
                  .frame(width: 35, height: 35)
              }
            }
            .keyframeAnimator(initialValue: 1, trigger: appData.activeTab) { content, scale in
              content
                .scaleEffect(appData.activeTab == tab ? scale : 1)
            } keyframes: { _ in
              CubicKeyframe(1.2, duration: 0.2)
              CubicKeyframe(1, duration: 0.2)
            }

            Text(tab.rawValue)
              .font(.caption2)
          }
          .frame(maxWidth: .infinity)
          .foregroundStyle(.white)
          .animation(.snappy) { content in
            content
              .opacity(appData.activeTab == tab ? 1 : 0.6)
          }
          .contentShape(.rect)
        }
        .buttonStyle(NoAnimationButtonStyle())
      }
    }
    .padding(.bottom, 10)
    .padding(.top, 5)
    .background {
      Rectangle()
        .fill(.ultraThinMaterial)
        .ignoresSafeArea()
    }
  }
}

#Preview {
  @Previewable @State var appData = V2AppData()

  ZStack {
    VStack {
      Spacer(minLength: 0)

      V2LaunchUITabView()
    }
    .coordinateSpace(.named("MAINVIEW"))

    if !appData.isSplashFinished {
      ProgressView()
    }
  }
  .environment(appData)
  .preferredColorScheme(.dark)
}
