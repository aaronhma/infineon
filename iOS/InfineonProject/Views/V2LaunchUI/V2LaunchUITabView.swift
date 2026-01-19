//
//  V2LaunchUITabView.swift
//  InfineonProject
//
//  Created by Aaron Ma on 1/16/26.
//

import AaronUI
import SwiftUI

enum V2Tab: String, CaseIterable {
  case home = "Vehicle"
  case new = "Trips"
  case account = "Account"

  var icon: String {
    switch self {
    case .home:
      "car.side.fill"
    case .new:
      "airplane.up.forward"
    case .account:
      "__profileImage__"
    }
  }
}

struct V2Profile: Identifiable {
  var id = UUID()
  var name: String
  var icon: String
  var vehicleId: String
  var unidentifiedFacesCount = 0

  var sourceAnchorID: String {
    id.uuidString + "SOURCE"
  }

  var destinationAnchorID: String {
    id.uuidString + "DESTINATION"
  }

  var vehicle: Vehicle {
    supabase.vehicles.first { $0.id == vehicleId }!
  }

  var realtimeData: VehicleRealtime? {
    supabase.vehicleRealtimeData[vehicleId]
  }
}

var mockProfiles: [V2Profile] = [
  .init(name: "Benji", icon: "benji", vehicleId: "BENJI123"),
  .init(name: "Model Y", icon: "modelY", vehicleId: "BENJI123"),
]

@Observable
class V2AppData {
  var isSplashFinished = false
  var activeTab = V2Tab.home
  var hideMainView = false
  var showProfileView = false
  var tabProfileRect: CGRect = .zero
  var watchingProfile: V2Profile?
  var animateProfile = false
  var fromTabBar = false
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
                  let rect = proxy.frame(
                    in: .named("MAINVIEW")
                  )

                  if let profile = appData.watchingProfile, !appData.animateProfile {
                    Image(profile.icon)
                      .resizable()
                      .aspectRatio(contentMode: .fill)
                      .frame(width: 25, height: 25)
                      .clipShape(.rect(cornerRadius: 4))
                      .frame(maxWidth: .infinity, maxHeight: .infinity)
                  }

                  Color.clear
                    .preference(
                      key: RectKey.self,
                      value: rect
                    )
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
            .keyframeAnimator(
              initialValue: 1,
              trigger: appData.activeTab
            ) {
              content,
              scale in
              content
                .scaleEffect(
                  appData.activeTab == tab ? scale : 1
                )
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
        .simultaneousGesture(
          LongPressGesture().onEnded { _ in
            guard tab == .account else { return }

            withAnimation(.snappy(duration: 0.3)) {
              appData.showProfileView = true
              appData.hideMainView = true
              appData.fromTabBar = true
            }
          })
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
