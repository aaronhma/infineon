//
//  InfineonProjectApp.swift
//  InfineonProject
//
//  Created by Aaron Ma on 1/12/26.
//

import SwiftUI
import SwiftData

@main
struct InfineonProjectApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Trip.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
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
                ContentView()
            } else {
                AuthView()
            }
        }
        .transition(.blurReplace)
        .animation(.easeInOut(duration: 0.3), value: supabase.isLoggedIn)
        .animation(.easeInOut(duration: 0.3), value: supabase.isLoading)
    }
}
