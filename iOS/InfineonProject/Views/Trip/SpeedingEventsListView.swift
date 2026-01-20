//
//  SpeedingEventsListView.swift
//  InfineonProject
//
//  Created by Aaron Ma on 1/20/26.
//

import SwiftUI

struct SpeedingEventsListView: View {
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
          Label("No Events", systemImage: "speedometer")
        } description: {
          Text("No speeding events recorded for this trip.")
        }
      } else {
        eventsList
      }
    }
    .navigationTitle("Speeding Events")
    .navigationBarTitleDisplayMode(.inline)
    .task {
      await loadEvents()
    }
  }

  private var eventsList: some View {
    List {
      Section {
        Text(
          "\(events.count) speeding event\(events.count == 1 ? "" : "s") detected during this trip."
        )
        .font(.subheadline)
        .foregroundStyle(.secondary)
      }

      Section("Events") {
        ForEach(events) { event in
          NavigationLink(value: TripEventDetail(event: event, eventType: .speeding)) {
            SpeedingEventRow(event: event)
          }
        }
      }
    }
  }

  private func loadEvents() async {
    isLoading = true
    errorMessage = nil

    do {
      let fetchedEvents = try await supabase.fetchSpeedingEvents(
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

// MARK: - Speeding Event Row

struct SpeedingEventRow: View {
  let event: FaceDetection

  var body: some View {
    HStack(spacing: 12) {
      // Icon with speed
      ZStack {
        Circle()
          .fill(Color.orange.gradient)
          .frame(width: 40, height: 40)

        if let speed = event.speedMph {
          Text("\(speed)")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
        } else {
          Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 18))
            .foregroundStyle(.white)
        }
      }

      // Info
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text(event.createdAt.formatted(.dateTime.hour().minute().second()))
            .font(.headline)

          if let speed = event.speedMph {
            Text("\(speed) mph")
              .font(.caption)
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(.red.opacity(0.2))
              .foregroundStyle(.red)
              .clipShape(.capsule)
          }
        }

        Text(event.createdAt.formatted(.dateTime.weekday(.wide).month().day()))
          .font(.subheadline)
          .foregroundStyle(.secondary)

        // Direction info
        if let heading = event.headingDegrees, let direction = event.compassDirection {
          Label("\(direction) (\(heading)°)", systemImage: "location.north.fill")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Spacer()
    }
    .padding(.vertical, 4)
  }
}

#Preview {
  NavigationStack {
    SpeedingEventsListView(trip: Trip.sample)
  }
}
