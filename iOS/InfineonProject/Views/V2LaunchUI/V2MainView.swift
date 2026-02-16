//
//  V2MainView.swift
//  InfineonProject
//
//  Created by Aaron Ma on 1/16/26.
//

import AaronUI
import SwiftUI

struct V2MainView: View {
  @Environment(\.colorScheme) private var colorScheme
  @State var appData = V2AppData()

  var body: some View {
    ZStack {
      VStack(spacing: 0) {
        Group {
          switch appData.activeTab {
          case .vehicle:
            if let profile = appData.watchingProfile {
              VehicleView(vehicle: profile)
            }
          case .account:
            V2AccountView()
          }
        }
        .frame(maxHeight: .infinity)

        if appData.watchingProfile != nil {
          V2LaunchUITabView()
        }
      }
      .coordinateSpace(.named("MAINVIEW"))

      Group {
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

            // Check if there's a pending vehicle from quick action
            if let pendingId = deepLinkManager.pendingVehicleId,
              let vehicle = supabase.vehicles.first(where: { $0.id == pendingId })
            {
              let profile = V2Profile(
                id: vehicle.id,
                name: vehicle.name ?? "Vehicle",
                icon: "benji",
                vehicleId: vehicle.id,
                vehicle: vehicle
              )
              appData.watchingProfile = profile
              appData.animateProfile = true
              appData.showProfileView = true
              appData.hideMainView = true
              deepLinkManager.clearPendingVehicle()
            } else {
              appData.showProfileView = appData.isSplashFinished
              appData.hideMainView = appData.showProfileView
            }
          }
      }
    }
    .preventScreenshot()
    .background {
      ContentUnavailableView(
        "Screenshot Not Allowed", systemImage: "iphone.slash", description: Text("© 2026 Aaron Ma.")
      )
    }
    .environment(appData)
    .onChange(of: deepLinkManager.pendingVehicleId) { _, pendingId in
      guard appData.isSplashFinished,
        let pendingId,
        let vehicle = supabase.vehicles.first(where: { $0.id == pendingId })
      else {
        return
      }

      let profile = V2Profile(
        id: vehicle.id,
        name: vehicle.name ?? "Vehicle",
        icon: "benji",
        vehicleId: vehicle.id,
        vehicle: vehicle
      )
      appData.watchingProfile = profile
      appData.animateProfile = true
      appData.showProfileView = true
      appData.hideMainView = true
      deepLinkManager.clearPendingVehicle()
    }
  }
}

#Preview {
  V2MainView()
}
