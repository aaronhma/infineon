//
//  HomeView.swift
//  InfineonProject
//
//  Created by Aaron Ma on 1/12/26.
//

import AaronUI
import SwiftUI

struct HomeView: View {
  var vehicle: V2Profile

  @State private var trips: [Trip] = []
  @State private var todayTrips: [Trip] = []
  @State private var isLoading = true
  @State private var errorMessage: String?

  @State private var progressOuter = CGFloat.zero
  @State private var progressMiddle = CGFloat.zero
  @State private var progressInner = CGFloat.zero

  @Namespace private var namespace

  // Computed properties for today's stats
  private var todayTripCount: Int {
    todayTrips.count
  }

  private var todayOkCount: Int {
    todayTrips.filter { $0.status == .ok }.count
  }

  private var todayWarningCount: Int {
    todayTrips.filter { $0.status == .warning }.count
  }

  private var todayDangerCount: Int {
    todayTrips.filter { $0.status == .danger }.count
  }

  private var todayScore: Int {
    guard todayTripCount > 0 else { return 100 }
    // Score based on trip statuses: ok = 100, warning = 50, danger = 0
    let totalScore = todayOkCount * 100 + todayWarningCount * 50 + todayDangerCount * 0
    return totalScore / todayTripCount
  }

  var body: some View {
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
            Task {
              await loadTrips()
            }
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
    .navigationDestination(for: String.self) { destination in
      switch destination {
      case Constants.HomeRouteAnnouncer.trips.rawValue:
        allTripsView
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

  private var tripsList: some View {
    List {
      // Today's summary section
      Section {
        VStack {
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text("Driving Score")
                .font(.title3)
                .bold()

              Text("\(todayScore)/100")
                .foregroundStyle(scoreColor)
                .contentTransition(.numericText(value: Double(todayScore)))
                .padding(.bottom)

              Text("Today's Trips")
                .font(.title3)
                .bold()

              Text("\(todayOkCount)/\(todayTripCount)")
                .foregroundStyle(todayOkCount == todayTripCount ? .green : .orange)
                .contentTransition(.numericText(value: Double(todayOkCount)))

              Spacer(minLength: 0)
            }

            Spacer(minLength: 0)

            RingsView(
              size: 100,
              lineWidth: 15,
              progressOuter: $progressOuter,
              progressMiddle: $progressMiddle,
              progressInner: $progressInner
            )
          }
        }
        .onAppear {
          updateRings()
        }
        .onChange(of: todayTrips.count) {
          updateRings()
        }
      } header: {
        HStack {
          Text("Today")
            .foregroundStyle(Color.primary)
            .font(.title2)

          Spacer()

          if !todayTrips.isEmpty {
            Text("\(todayTripCount) trip\(todayTripCount == 1 ? "" : "s")")
              .foregroundStyle(.secondary)
          }
        }
        .lineLimit(1)
        .bold()
      }

      // Recent trips section
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

            Image(systemName: "chevron.right")
              .foregroundStyle(.secondary)

            Spacer()
          }
          .lineLimit(1)
          .font(.title2)
          .bold()
        }
        .frame(maxWidth: .infinity)
        .foregroundStyle(.primary)
      }
    }
  }

  private var allTripsView: some View {
    List {
      ForEach(trips) { trip in
        NavigationLink(value: trip) {
          TripInfoView(trip: trip, namespace: namespace)
        }
      }
    }
    .navigationTitle("All Trips")
  }

  private var scoreColor: Color {
    if todayScore >= 80 {
      return .green
    } else if todayScore >= 50 {
      return .orange
    } else {
      return .red
    }
  }

  private func updateRings() {
    withAnimation(.easeInOut(duration: 0.5)) {
      // Outer ring: overall score
      progressOuter = CGFloat(todayScore) / 100.0

      // Middle ring: percentage of trips that are OK
      progressMiddle = todayTripCount > 0 ? CGFloat(todayOkCount) / CGFloat(todayTripCount) : 1.0

      // Inner ring: inverse of danger trips (1.0 = no danger, 0.0 = all danger)
      progressInner =
        todayTripCount > 0 ? 1.0 - (CGFloat(todayDangerCount) / CGFloat(todayTripCount)) : 1.0
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

// Make Trip conform to Hashable for NavigationLink
extension Trip: Hashable {
  static func == (lhs: Trip, rhs: Trip) -> Bool {
    lhs.id == rhs.id
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
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
