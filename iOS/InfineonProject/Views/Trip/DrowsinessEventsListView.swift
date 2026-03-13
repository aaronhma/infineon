//
//  DrowsinessEventsListView.swift
//  InfineonProject
//
//  Created by Aaron Ma on 1/20/26.
//

import SwiftUI

struct DrowsinessEventsListView: View {
  let trip: Trip

  @State private var events: [FaceDetection] = []
  @State private var isLoading = true
  @State private var errorMessage: String?

  var body: some View {
    Group {
      if isLoading {
        ProgressView("Loading events...")
      } else if let errorMessage {
        ContentUnavailableView {
          Label("Error", systemImage: "exclamationmark.triangle")
        } description: {
          Text(errorMessage)
        } actions: {
          Button("Retry") {
            Task {
              await loadEvents()
            }
          }
        }
      } else if events.isEmpty {
        ContentUnavailableView {
          Label("No Events", systemImage: "moon.fill")
        } description: {
          Text("No drowsiness events recorded for this trip.")
        }
      } else {
        eventsList
      }
    }
    .navigationTitle("Drowsiness Events")
    .navigationBarTitleDisplayMode(.inline)
    .task {
      await loadEvents()
    }
  }

  private var eventsList: some View {
    List {
      Section {
        Text(
          "\(events.count) drowsiness event\(events.count == 1 ? "" : "s") detected during this trip."
        )
        .font(.subheadline)
        .foregroundStyle(.secondary)
      }

      Section("Events") {
        ForEach(events) { event in
          NavigationLink(value: TripEventDetail(event: event, eventType: .drowsiness)) {
            EventRow(event: event, eventType: .drowsiness)
          }
        }
      }
    }
  }

  private func loadEvents() async {
    isLoading = true
    errorMessage = nil

    do {
      let fetchedEvents = try await supabase.fetchDrowsyEvents(
        for: trip.sessionId,
        vehicleId: trip.vehicleTrip.vehicleId
      )

      await MainActor.run {
        self.events = fetchedEvents
        self.isLoading = false
      }
    } catch {
      await MainActor.run {
        self.errorMessage = error.localizedDescription
        self.isLoading = false
      }
    }
  }
}

#Preview {
  NavigationStack {
    DrowsinessEventsListView(trip: Trip.sample)
  }
}
