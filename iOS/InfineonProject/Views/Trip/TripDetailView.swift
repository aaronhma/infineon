//
//  TripDetailView.swift
//  InfineonProject
//
//  Created by Aaron Ma on 1/12/26.
//

import AaronUI
import MapKit
import SwiftUI

struct TripDetailView: View {
  var trip: Trip
  var previewRouteCoordinates: [CLLocationCoordinate2D] = []

  @State private var allDetections: [FaceDetection] = []
  @State private var mapCameraPosition: MapCameraPosition = .automatic

  private var flaggedEvents: [FaceDetection] {
    allDetections.filter { event in
      event.isDrowsy
        || event.isExcessiveBlinking
        || event.isUnstableEyes
        || event.isSpeeding == true
        || event.isPhoneDetected == true
        || event.isDrinkingDetected == true
    }
  }

  private var routeCoordinates: [CLLocationCoordinate2D] {
    if !trip.routeCoordinates.isEmpty { return trip.routeCoordinates }
    let detected = allDetections.compactMap { event -> CLLocationCoordinate2D? in
      guard let lat = event.latitude, let lng = event.longitude else { return nil }
      return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
    return detected.isEmpty ? previewRouteCoordinates : detected
  }

  var body: some View {
    List {
      // Hero header
      Section {
        VStack(spacing: 16) {
          // Score ring
          TripScoreRing(score: trip.score.overall, size: 120)

          // Status label
          Text(trip.tripStatus)
            .font(.title3.bold())
            .titleVisibilityAnchor()

          if trip.isOngoing {
            HStack(spacing: 4) {
              Circle()
                .fill(.red)
                .frame(width: 6, height: 6)
              Text("Trip in progress")
                .font(.caption)
            }
            .foregroundStyle(.red)
          }

          if trip.crashDetected {
            Label(
              "Crash Detected\(trip.crashSeverity.map { " (\($0))" } ?? "")",
              systemImage: "exclamationmark.triangle.fill"
            )
            .font(.caption.bold())
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.red)
            .foregroundStyle(.white)
            .clipShape(.capsule)
          }

          // Time + duration pills
          HStack(spacing: 8) {
            Label(
              trip.timeStarted.formatted(.dateTime.month(.abbreviated).day().hour().minute()),
              systemImage: "calendar"
            )
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.secondary.opacity(0.1))
            .clipShape(.capsule)

            Label(trip.formattedDuration, systemImage: "clock.fill")
              .font(.caption2)
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
              .background(.secondary.opacity(0.1))
              .clipShape(.capsule)
          }
          .foregroundStyle(.secondary)

          // Sub-score bars
          TripScoreBreakdown(trip: trip)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
      }
      .listRowBackground(Color.clear)

      // Trip Statistics
      Section("Trip Statistics") {
        LabeledContent("Max Speed") {
          Text("\(trip.maxSpeedMph) mph")
            .foregroundStyle(trip.maxSpeedMph > 65 ? .red : .primary)
        }

        LabeledContent("Average Speed") {
          Text(trip.avgSpeedMph.formatted(.number.precision(.fractionLength(1))))
            + Text(" mph")
        }

        LabeledContent("Face Detections") {
          Text("\(trip.faceDetectionCount)")
        }

        LabeledContent("Session ID") {
          Text(trip.sessionId.uuidString)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      // Driver Monitoring
      Section("Driver Monitoring") {
        if trip.drowsyEventCount > 0 {
          NavigationLink(value: TripEventDestination.drowsinessEvents(trip: trip)) {
            Label {
              VStack(alignment: .leading) {
                Text(
                  "\(trip.drowsyEventCount) Drowsiness Event\(trip.drowsyEventCount == 1 ? "" : "s")"
                )
                Text("Tap to view details")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            } icon: {
              Image(systemName: "moon.fill")
                .foregroundStyle(.yellow)
            }
          }
        } else {
          Label("No drowsiness detected", systemImage: "checkmark.circle.fill")
            .foregroundStyle(.green)
        }

        if trip.excessiveBlinkingEventCount > 0 {
          NavigationLink(value: TripEventDestination.excessiveBlinkingEvents(trip: trip)) {
            Label {
              VStack(alignment: .leading) {
                Text(
                  "\(trip.excessiveBlinkingEventCount) Excessive Blinking Event\(trip.excessiveBlinkingEventCount == 1 ? "" : "s")"
                )
                Text("Tap to view details")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            } icon: {
              Image(systemName: "eye")
                .foregroundStyle(.orange)
            }
          }
        } else {
          Label("No excessive blinking detected", systemImage: "checkmark.circle.fill")
            .foregroundStyle(.green)
        }

        if trip.unstableEyesEventCount > 0 {
          NavigationLink(value: TripEventDestination.unstableEyesEvents(trip: trip)) {
            Label {
              VStack(alignment: .leading) {
                Text(
                  "\(trip.unstableEyesEventCount) Unstable Eyes Event\(trip.unstableEyesEventCount == 1 ? "" : "s")"
                )
                Text("Tap to view details")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            } icon: {
              Image(systemName: "eye.trianglebadge.exclamationmark")
                .foregroundStyle(.red)
            }
          }
        } else {
          Label("No unstable eyes detected", systemImage: "checkmark.circle.fill")
            .foregroundStyle(.green)
        }

        LabeledContent("Max Risk Score") {
          Text("\(trip.maxIntoxicationScore)/6")
            .foregroundStyle(riskScoreColor)
        }
      }

      // Distraction Events
      Section("Distraction Events") {
        if trip.phoneDistractionEventCount > 0 {
          NavigationLink(value: TripEventDestination.phoneDistractionEvents(trip: trip)) {
            Label {
              VStack(alignment: .leading) {
                Text(
                  "\(trip.phoneDistractionEventCount) Phone Distraction\(trip.phoneDistractionEventCount == 1 ? "" : "s")"
                )
                Text("Tap to view details")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            } icon: {
              Image(systemName: "iphone.gen3")
                .foregroundStyle(.red)
            }
          }
        } else {
          Label("No phone distractions", systemImage: "checkmark.circle.fill")
            .foregroundStyle(.green)
        }

        if trip.drinkingEventCount > 0 {
          NavigationLink(value: TripEventDestination.drinkingEvents(trip: trip)) {
            Label {
              VStack(alignment: .leading) {
                Text(
                  "\(trip.drinkingEventCount) Drinking Event\(trip.drinkingEventCount == 1 ? "" : "s")"
                )
                Text("Tap to view details")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            } icon: {
              Image(systemName: "cup.and.saucer.fill")
                .foregroundStyle(.orange)
            }
          }
        } else {
          Label("No drinking detected", systemImage: "checkmark.circle.fill")
            .foregroundStyle(.green)
        }
      }

      // Speed Violations
      Section("Speed Violations") {
        if trip.speedingEventCount > 0 {
          NavigationLink(value: TripEventDestination.speedingEvents(trip: trip)) {
            Label {
              VStack(alignment: .leading) {
                Text(
                  "\(trip.speedingEventCount) Speeding Event\(trip.speedingEventCount == 1 ? "" : "s")"
                )
                Text("Tap to view details")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            } icon: {
              Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            }
          }
        } else {
          Label("No speeding violations", systemImage: "checkmark.circle.fill")
            .foregroundStyle(.green)
        }
      }

      // Trip Route
      Section("Trip Route") {
        Map(position: $mapCameraPosition) {
          if routeCoordinates.count >= 2 {
            MapPolyline(coordinates: routeCoordinates)
              .stroke(.blue, lineWidth: 4)
          }

          if let first = routeCoordinates.first {
            Annotation("Start", coordinate: first) {
              Image(systemName: "flag.fill")
                .padding(6)
                .background(.green.gradient)
                .foregroundStyle(.white)
                .clipShape(.circle)
            }
          }

          if let last = routeCoordinates.last, routeCoordinates.count > 1 {
            Annotation("End", coordinate: last) {
              Image(systemName: "flag.checkered")
                .padding(6)
                .background(.red.gradient)
                .foregroundStyle(.white)
                .clipShape(.circle)
            }
          }

          ForEach(flaggedEvents) { event in
            if let lat = event.latitude, let lng = event.longitude {
              Annotation(
                eventLabel(for: event),
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng)
              ) {
                EventMapPin(event: event)
              }
            }
          }
        }
        .mapStyle(.standard(elevation: .realistic))
        .frame(height: 300)
        .clipShape(.rect(cornerRadius: 12))
        .listRowInsets(EdgeInsets())
      }
    }
    .scrollAwareTitle(trip.tripStatus)
    .navigationBarTitleDisplayMode(.inline)
    .task {
      await loadDetections()
    }
    .onAppear {
      if !previewRouteCoordinates.isEmpty {
        fitMapToRoute()
      }
    }
  }

  private var riskScoreColor: Color {
    if trip.maxIntoxicationScore >= 4 {
      return .red
    } else if trip.maxIntoxicationScore >= 2 {
      return .orange
    } else {
      return .green
    }
  }

  private func loadDetections() async {
    do {
      let detections = try await supabase.fetchAllDetectionsWithLocation(
        for: trip.sessionId,
        vehicleId: trip.vehicleTrip.vehicleId
      )

      await MainActor.run {
        allDetections = detections
        fitMapToRoute()
      }
    } catch {
      print("Error loading detections: \(error)")
    }
  }

  private func fitMapToRoute() {
    guard !routeCoordinates.isEmpty else { return }

    var minLat = routeCoordinates[0].latitude
    var maxLat = routeCoordinates[0].latitude
    var minLng = routeCoordinates[0].longitude
    var maxLng = routeCoordinates[0].longitude

    for coord in routeCoordinates {
      minLat = min(minLat, coord.latitude)
      maxLat = max(maxLat, coord.latitude)
      minLng = min(minLng, coord.longitude)
      maxLng = max(maxLng, coord.longitude)
    }

    let center = CLLocationCoordinate2D(
      latitude: (minLat + maxLat) / 2,
      longitude: (minLng + maxLng) / 2
    )

    let span = MKCoordinateSpan(
      latitudeDelta: max((maxLat - minLat) * 1.4, 0.005),
      longitudeDelta: max((maxLng - minLng) * 1.4, 0.005)
    )

    mapCameraPosition = .region(MKCoordinateRegion(center: center, span: span))
  }

  private func eventLabel(for event: FaceDetection) -> String {
    if event.isDrowsy { return "Drowsy" }
    if event.isPhoneDetected == true { return "Phone" }
    if event.isSpeeding == true { return "Speeding" }
    if event.isDrinkingDetected == true { return "Drinking" }
    if event.isExcessiveBlinking { return "Blinking" }
    if event.isUnstableEyes { return "Unstable Eyes" }
    return "Event"
  }
}

// MARK: - Trip Score Breakdown

struct TripScoreBreakdown: View {
  let trip: Trip

  private var tripScore: TripScore { trip.score }

  var body: some View {
    VStack(spacing: 12) {
      // Confidence banner
      if !tripScore.isCameraAvailable {
        HStack(spacing: 4) {
          Image(systemName: "video.slash")
          Text("Camera data unavailable")
        }
        .font(.caption2)
        .foregroundStyle(.orange)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.orange.opacity(0.1))
        .clipShape(.capsule)
      } else if !tripScore.isConfident {
        HStack(spacing: 4) {
          Image(systemName: "exclamationmark.circle")
          Text("Low confidence")
        }
        .font(.caption2)
        .foregroundStyle(.orange)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.orange.opacity(0.1))
        .clipShape(.capsule)
      }

      // Sub-score cards
      HStack(spacing: 8) {
        SubScoreCard(
          label: "Attentiveness",
          score: tripScore.attentiveness,
          icon: "eye.fill",
          color: .cyan,
          factors: attentivenessFactors
        )

        SubScoreCard(
          label: "Safety",
          score: tripScore.safety,
          icon: "shield.fill",
          color: .blue,
          factors: safetyFactors
        )

        SubScoreCard(
          label: "Impairment",
          score: tripScore.impairment,
          icon: "brain.head.profile.fill",
          color: .purple,
          factors: impairmentFactors
        )
      }
    }
  }

  private var attentivenessFactors: [(String, String)] {
    var factors: [(String, String)] = []
    let dur = trip.duration

    if trip.phoneDistractionEventCount > 0 {
      factors.append(
        (
          "Phone",
          formatRate(
            DrivingScoreCalculator.ratePerHour(
              count: trip.phoneDistractionEventCount, durationSeconds: dur))
        ))
    }
    if trip.drowsyEventCount > 0 {
      factors.append(
        (
          "Drowsy",
          formatRate(
            DrivingScoreCalculator.ratePerHour(count: trip.drowsyEventCount, durationSeconds: dur))
        ))
    }
    if trip.unstableEyesEventCount > 0 {
      factors.append(
        (
          "Eyes",
          formatRate(
            DrivingScoreCalculator.ratePerHour(
              count: trip.unstableEyesEventCount, durationSeconds: dur))
        ))
    }
    if trip.excessiveBlinkingEventCount > 0 {
      factors.append(
        (
          "Blink",
          formatRate(
            DrivingScoreCalculator.ratePerHour(
              count: trip.excessiveBlinkingEventCount, durationSeconds: dur))
        ))
    }
    return factors
  }

  private var safetyFactors: [(String, String)] {
    var factors: [(String, String)] = []
    let dur = trip.duration

    if trip.speedingEventCount > 0 {
      factors.append(
        (
          "Speed",
          formatRate(
            DrivingScoreCalculator.ratePerHour(count: trip.speedingEventCount, durationSeconds: dur)
          )
        ))
    }
    if trip.maxSpeedMph > 80 {
      factors.append(("Peak", "\(trip.maxSpeedMph)"))
    }
    return factors
  }

  private var impairmentFactors: [(String, String)] {
    var factors: [(String, String)] = []
    let dur = trip.duration

    if trip.maxIntoxicationScore > 0 {
      factors.append(("Risk", "\(trip.maxIntoxicationScore)/6"))
    }
    if trip.drinkingEventCount > 0 {
      factors.append(
        (
          "Drink",
          formatRate(
            DrivingScoreCalculator.ratePerHour(count: trip.drinkingEventCount, durationSeconds: dur)
          )
        ))
    }
    return factors
  }

  private func formatRate(_ rate: Double) -> String {
    let precision: Int = rate < 1 ? 1 : 0
    return "\(rate.formatted(.number.precision(.fractionLength(precision))))/hr"
  }
}

// MARK: - Sub-Score Card

struct SubScoreCard: View {
  let label: String
  let score: Int
  let icon: String
  let color: Color
  let factors: [(String, String)]

  private var effectiveColor: Color {
    switch DrivingScoreCalculator.scoreCategory(for: score) {
    case .good: color
    case .moderate: .orange
    case .poor: .red
    }
  }

  @State private var ringProgress = CGFloat.zero

  var body: some View {
    VStack(spacing: 6) {
      Image(systemName: icon)
        .font(.system(size: 14))
        .foregroundStyle(effectiveColor)

      Text("\(score)")
        .font(.title3.bold())
        .contentTransition(.numericText(value: Double(score)))
        .foregroundStyle(effectiveColor)

      Text(label)
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(.secondary)
        .lineLimit(1)

      ProgressRing(
        size: 40,
        lineWidth: 4,
        progress: $ringProgress,
        foregroundStyle: effectiveColor
      )
      .onAppear {
        ringProgress = CGFloat(score) / 100.0
      }

      if !factors.isEmpty {
        VStack(spacing: 1) {
          ForEach(factors, id: \.0) { factor in
            Text("\(factor.0) \(factor.1)")
              .font(.system(size: 8, weight: .medium))
              .foregroundStyle(.tertiary)
          }
        }
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 8)
    .background(.secondary.opacity(0.05))
    .clipShape(.rect(cornerRadius: 10))
  }
}

// MARK: - Event Map Pin

struct EventMapPin: View {
  let event: FaceDetection

  private var icon: String {
    if event.isDrowsy { return "moon.fill" }
    if event.isPhoneDetected == true { return "iphone.gen3" }
    if event.isSpeeding == true { return "bolt.fill" }
    if event.isDrinkingDetected == true { return "cup.and.saucer.fill" }
    if event.isExcessiveBlinking { return "eye" }
    if event.isUnstableEyes { return "eye.trianglebadge.exclamationmark" }
    return "exclamationmark.circle.fill"
  }

  private var color: Color {
    if event.isDrowsy { return .yellow }
    if event.isPhoneDetected == true { return .red }
    if event.isSpeeding == true { return .orange }
    if event.isDrinkingDetected == true { return .orange }
    if event.isExcessiveBlinking { return .teal }
    if event.isUnstableEyes { return .red }
    return .gray
  }

  var body: some View {
    Image(systemName: icon)
      .font(.system(size: 12, weight: .bold))
      .foregroundStyle(.white)
      .padding(6)
      .background(color.gradient)
      .clipShape(.circle)
      .shadow(color: color.opacity(0.4), radius: 4, y: 2)
  }
}

// Sample route for previews
private let sampleRouteAppleParkToGoldenGate: [CLLocationCoordinate2D] = [
  CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090),
  CLLocationCoordinate2D(latitude: 37.3415, longitude: -122.0310),
  CLLocationCoordinate2D(latitude: 37.3530, longitude: -122.0480),
  CLLocationCoordinate2D(latitude: 37.3680, longitude: -122.0590),
  CLLocationCoordinate2D(latitude: 37.3900, longitude: -122.0760),
  CLLocationCoordinate2D(latitude: 37.4150, longitude: -122.0870),
  CLLocationCoordinate2D(latitude: 37.4430, longitude: -122.1100),
  CLLocationCoordinate2D(latitude: 37.4650, longitude: -122.1400),
  CLLocationCoordinate2D(latitude: 37.4900, longitude: -122.1700),
  CLLocationCoordinate2D(latitude: 37.5200, longitude: -122.2000),
  CLLocationCoordinate2D(latitude: 37.5500, longitude: -122.2300),
  CLLocationCoordinate2D(latitude: 37.5800, longitude: -122.2700),
  CLLocationCoordinate2D(latitude: 37.6100, longitude: -122.3000),
  CLLocationCoordinate2D(latitude: 37.6400, longitude: -122.3300),
  CLLocationCoordinate2D(latitude: 37.6700, longitude: -122.3600),
  CLLocationCoordinate2D(latitude: 37.7000, longitude: -122.3900),
  CLLocationCoordinate2D(latitude: 37.7300, longitude: -122.4100),
  CLLocationCoordinate2D(latitude: 37.7600, longitude: -122.4300),
  CLLocationCoordinate2D(latitude: 37.7850, longitude: -122.4500),
  CLLocationCoordinate2D(latitude: 37.8080, longitude: -122.4650),
  CLLocationCoordinate2D(latitude: 37.8199, longitude: -122.4783),
]

#Preview {
  @Previewable @Namespace var namespace

  NavigationStack {
    TripDetailView(
      trip: Trip.sample,
      previewRouteCoordinates: sampleRouteAppleParkToGoldenGate
    )
  }
}

#Preview("Warning Trip Score") {
  NavigationStack {
    TripDetailView(
      trip: Trip.sampleWarning,
      previewRouteCoordinates: sampleRouteAppleParkToGoldenGate
    )
  }
}

#Preview("Danger Trip Score") {
  NavigationStack {
    TripDetailView(
      trip: Trip.sampleDanger,
      previewRouteCoordinates: sampleRouteAppleParkToGoldenGate
    )
  }
}
