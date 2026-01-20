//
//  InfineonProjectApp.swift
//  InfineonProject
//
//  Created by Aaron Ma on 1/12/26.
//

//import SwiftData
import SwiftUI

@main
struct InfineonProjectApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @Environment(\.scenePhase) private var scenePhase
  @AppStorage(
    "lastSelectedVehicleId"
  ) private var lastSelectedVehicleId: String?

  private func handleShortcut(url: URL) {
    if url.scheme == "infineon" {
      print(url.absoluteString)
    }
    if url.absoluteString.contains("feedback") {
      let email = "hi@aaronhma.com"
      let subject = "Infineon Project App Improvements"
      let body = "DEVICE LOGS:\n\nInfineon Project iOS App Beta v0.0.1"

      var components = URLComponents()
      components.scheme = "mailto"
      components.path = email
      components.queryItems = [
        URLQueryItem(name: "subject", value: subject),
        URLQueryItem(name: "body", value: body),
      ]

      print("EMAIL: ", components.url!.absoluteString)

      if let mailURL = components.url,
        UIApplication.shared
          .canOpenURL(mailURL)
      {
        UIApplication.shared.open(mailURL)
      }
    } else {
      print("ERROR")
    }
  }

  // TODO: Eventually add offline support
  //  var sharedModelContainer: ModelContainer = {
  //    let schema = Schema([
  //      Trip.self
  //    ])
  //    let modelConfiguration = ModelConfiguration(
  //      schema: schema,
  //      isStoredInMemoryOnly: false
  //    )
  //
  //    do {
  //      return try ModelContainer(
  //        for: schema,
  //        configurations: [modelConfiguration]
  //      )
  //    } catch {
  //      fatalError("Could not create ModelContainer: \(error)")
  //    }
  //  }()

  func updateShortcutItems() {
    guard let vehicleId = lastSelectedVehicleId,
      let vehicle = supabase.vehicles.first(
        where: {
          $0.id == vehicleId
        })
    else {
      UIApplication.shared.shortcutItems = []
      return
    }

    let vehicleAction = UIApplicationShortcutItem(
      type: "openVehicle",
      localizedTitle: vehicle.name ?? "Vehicle",
      localizedSubtitle: "Open recent vehicle",
      icon: UIApplicationShortcutIcon(systemImageName: "car.fill"),
      userInfo: ["vehicleId": vehicleId as NSString]
    )
    UIApplication.shared.shortcutItems = [vehicleAction]
  }

  var body: some Scene {
    WindowGroup {
      RootView()
        .onOpenURL(perform: handleShortcut)
    }
    //    .modelContainer(sharedModelContainer)
    .onChange(of: scenePhase) {
      if scenePhase == .background {
        updateShortcutItems()
      }
    }
  }
}

struct RootView: View {
  @State private var showProfileSetup = false

  var body: some View {
    Group {
      if supabase.isLoading {
        ProgressView("Loading...")
          .controlSize(.extraLarge)
      } else if supabase.isLoggedIn {
        // TODO: ask group to choose between these 3 designs
        V2MainView()
        //          MainView()
        //          ContentView()
      } else {
        OnboardingView()
      }
    }
    .transition(.blurReplace)
    .animation(.easeInOut(duration: 0.3), value: supabase.isLoggedIn)
    .animation(.easeInOut(duration: 0.3), value: supabase.isLoading)
    .fullScreenCover(isPresented: $showProfileSetup) {
      ProfileSetupView {
        showProfileSetup = false
      }
    }
    .onChange(of: supabase.isLoggedIn, initial: true) { _, isLoggedIn in
      // Show profile setup if user is logged in and needs to set up their profile
      if isLoggedIn && supabase.needsProfileSetup {
        showProfileSetup = true
      }
    }
    .onChange(of: supabase.userProfile?.displayName) { _, displayName in
      // Dismiss profile setup when profile is completed
      if displayName != nil && !displayName!.isEmpty {
        showProfileSetup = false
      }
    }
  }
}
