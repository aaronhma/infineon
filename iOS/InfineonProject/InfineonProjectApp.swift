//
//  InfineonProjectApp.swift
//  InfineonProject
//
//  Created by Aaron Ma on 1/12/26.
//

import SwiftData
import SwiftUI

@main
struct InfineonProjectApp: App {
  @AppStorage("showOnboarding") private var showOnboarding = true

  //    init() {
  //        Task {
  //            try await supabase.signOut()
  //        }
  //
  //        showOnboarding = true
  //    }

  var sharedModelContainer: ModelContainer = {
    let schema = Schema([
      Trip.self
    ])
    let modelConfiguration = ModelConfiguration(
      schema: schema,
      isStoredInMemoryOnly: false
    )

    do {
      return try ModelContainer(
        for: schema,
        configurations: [modelConfiguration]
      )
    } catch {
      fatalError("Could not create ModelContainer: \(error)")
    }
  }()

  var body: some Scene {
    WindowGroup {
      V2MainView()
        .fullScreenCover(isPresented: $showOnboarding) {
          OnboardingView()
        }
      //      RootView()
    }
    .modelContainer(sharedModelContainer)
  }
}

struct RootView: View {
  var body: some View {
    Group {
      if supabase.isLoading {
        ProgressView("Loading...")
          .controlSize(.extraLarge)
      } else if supabase.isLoggedIn {
        MainView()
        //                ContentView()
      } else {
        AuthView()
      }
    }
    .transition(.blurReplace)
    .animation(.easeInOut(duration: 0.3), value: supabase.isLoggedIn)
    .animation(.easeInOut(duration: 0.3), value: supabase.isLoading)
  }
}
