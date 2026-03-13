//
//  HomeView.swift
//  InfineonProject
//
//  Created by Aaron Ma on 1/12/26.
//

import AaronUI
import SwiftUI

struct HomeView: View {
  @Environment(\.dismiss) private var dismiss

  var vehicle: V2Profile

  @State private var trips: [Trip] = []
  @State private var todayTrips: [Trip] = []
  @State private var isLoading = true
  @State private var errorMessage: String?

  @State private var progressOuter = CGFloat.zero
  @State private var progressMiddle = CGFloat.zero
  @State private var progressInner = CGFloat.zero

  @Namespace private var namespace

  private var todayTripCount: Int {
    todayTrips.count
  }

  private var todayDailyScore: DailyScore {
    DrivingScoreCalculator.dailyScore(for: todayTrips)
  }

  var body: some View {
    NavigationStack {
      Group {
        if isLoading {
          ProgressView("Loading trips...")
        } else if let errorMessage {
          ContentUnavailableView {
            Label("Error", systemImage: "exclamationmark.triangle")
          } description: {
            Text(errorMessage)
          } actions: {
            Button("Retry") {
              Task { await loadTrips() }
            }
          }
        } else if trips.isEmpty {
          ContentUnavailableView {
            Label("No Trips", systemImage: "car.side")
          } description: {
            Text("No trips recorded yet for this vehicle.")
          }
        } else {
          tripsList
        }
      }
      .navigationTitle("Trips")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          CloseButton {
            dismiss()
          }
        }
      }
      .navigationDestination(for: String.self) { destination in
        switch destination {
        case Constants.HomeRouteAnnouncer.trips.rawValue:
          AllTripsView(trips: trips, namespace: namespace)
        default:
          Text("Unknown destination: \(destination)")
        }
      }
      .navigationDestination(for: Trip.self) { trip in
        TripDetailView(trip: trip, namespace: namespace)
      }
      .navigationDestination(for: TripEventDestination.self) { destination in
        switch destination {
        case .drowsinessEvents(let trip):
          EventsListView(trip: trip, eventType: .drowsiness)
        case .excessiveBlinkingEvents(let trip):
          EventsListView(trip: trip, eventType: .excessiveBlinking)
        case .unstableEyesEvents(let trip):
          EventsListView(trip: trip, eventType: .unstableEyes)
        case .speedingEvents(let trip):
          EventsListView(trip: trip, eventType: .speeding)
        case .phoneDistractionEvents(let trip):
          EventsListView(trip: trip, eventType: .phoneDistraction)
        case .drinkingEvents(let trip):
          EventsListView(trip: trip, eventType: .drinking)
        }
      }
      .navigationDestination(for: TripEventDetail.self) { detail in
        EventDetailView(event: detail.event, eventType: detail.eventType)
      }
      .refreshable {
        await loadTrips()
      }
      .task {
        await loadTrips()
      }
    }
  }

  private var tripsList: some View {
    List {
      // Today's summary
      Section {
        VStack(spacing: 16) {
          // Score and sub-scores
          HStack(alignment: .top) {
            TripScoreRing(score: todayDailyScore.overall, size: 90)

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
              subScoreRow(
                label: "Attentiveness", score: todayDailyScore.attentiveness, color: .cyan)
              subScoreRow(label: "Safety", score: todayDailyScore.safety, color: .blue)
              subScoreRow(label: "Impairment", score: todayDailyScore.impairment, color: .purple)
            }
          }

          // Activity rings
          RingsView(
            size: 80,
            lineWidth: 12,
            progressOuter: $progressOuter,
            progressMiddle: $progressMiddle,
            progressInner: $progressInner
          )
          .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 8)
      } header: {
        HStack {
          Text("Today")
            .font(.title2.bold())
          Spacer()
          if !todayTrips.isEmpty {
            Text("\(todayTripCount) trip\(todayTripCount == 1 ? "" : "s")")
              .foregroundStyle(.secondary)
          }
        }
      }
      .onAppear { updateRings() }
      .onChange(of: todayTrips.count) { updateRings() }

      // Recent trips
      Section {
        ForEach(trips.prefix(8)) { trip in
          NavigationLink(value: trip) {
            TripInfoView(trip: trip, namespace: namespace)
          }
        }
      } header: {
        NavigationLink(value: Constants.HomeRouteAnnouncer.trips.rawValue) {
          HStack {
            Text("Recent Trips")
              .font(.title2.bold())
            Spacer()
            Image(systemName: "chevron.right")
              .font(.caption.bold())
              .foregroundStyle(.tertiary)
          }
        }
      }
    }
    .listStyle(.insetGrouped)
  }

  private func subScoreRow(label: String, score: Int, color: Color) -> some View {
    HStack(spacing: 8) {
      Text(label)
        .font(.caption)
        .foregroundStyle(.secondary)
      Text("\(score)")
        .font(.caption.bold())
        .foregroundStyle(scoreColor(for: score, baseColor: color))
    }
  }

  private func scoreColor(for score: Int, baseColor: Color) -> Color {
    switch DrivingScoreCalculator.scoreCategory(for: score) {
    case .good: baseColor
    case .moderate: .orange
    case .poor: .red
    }
  }

  private func updateRings() {
    let daily = todayDailyScore
    withAnimation(.easeInOut(duration: 0.5)) {
      progressOuter = CGFloat(daily.overall) / 100.0
      progressMiddle = CGFloat(daily.attentiveness) / 100.0
      progressInner = CGFloat(daily.safety) / 100.0
    }
  }

  private func loadTrips() async {
    isLoading = true
    errorMessage = nil

    do {
      async let allTripsTask = supabase.fetchTrips(for: vehicle.vehicleId)
      async let todayTripsTask = supabase.fetchTripsForToday(for: vehicle.vehicleId)

      let (fetchedTrips, fetchedTodayTrips) = try await (allTripsTask, todayTripsTask)

      await MainActor.run {
        self.trips = fetchedTrips.map { Trip(vehicleTrip: $0) }
        self.todayTrips = fetchedTodayTrips.map { Trip(vehicleTrip: $0) }
        self.isLoading = false
        updateRings()
      }
    } catch {
      await MainActor.run {
        self.errorMessage = error.localizedDescription
        self.isLoading = false
      }
    }
  }
}

// MARK: - All Trips View

struct AllTripsView: View {
  let trips: [Trip]
  let namespace: Namespace.ID

  var body: some View {
    List(trips) { trip in
      NavigationLink(value: trip) {
        TripInfoView(trip: trip, namespace: namespace)
      }
    }
    .navigationTitle("All Trips")
  }
}

#Preview {
  HomeView(
    vehicle: V2Profile(
      id: "test",
      name: "Test Vehicle",
      icon: "benji",
      vehicleId: "test",
      vehicle: Vehicle(
        id: "test",
        createdAt: .now,
        updatedAt: .now,
        name: "Test",
        description: nil,
        inviteCode: "TEST123",
        ownerId: nil
      )
    )
  )
}
