//
//  Trip.swift
//  InfineonProject
//
//  Created by Aaron Ma on 1/12/26.
//

import MapKit
import SwiftUI

/// A wrapper struct for VehicleTrip that provides convenient computed properties for UI display
struct Trip: Identifiable {
  let vehicleTrip: VehicleTrip

  var id: UUID { vehicleTrip.id }
  var timeStarted: Date { vehicleTrip.startedAt }
  var timeEnded: Date? { vehicleTrip.endedAt }
  var status: VehicleTrip.TripStatus { vehicleTrip.tripStatus }

  // Trip statistics
  var maxSpeedMph: Int { vehicleTrip.maxSpeedMph }
  var avgSpeedMph: Double { vehicleTrip.avgSpeedMph }
  var maxIntoxicationScore: Int { vehicleTrip.maxIntoxicationScore }
  var speedingEventCount: Int { vehicleTrip.speedingEventCount }
  var drowsyEventCount: Int { vehicleTrip.drowsyEventCount }
  var excessiveBlinkingEventCount: Int { vehicleTrip.excessiveBlinkingEventCount }
  var unstableEyesEventCount: Int { vehicleTrip.unstableEyesEventCount }
  var faceDetectionCount: Int { vehicleTrip.faceDetectionCount }
  var sessionId: UUID { vehicleTrip.sessionId }
  // GPS route
  var routeCoordinates: [CLLocationCoordinate2D] {
    vehicleTrip.routeWaypoints?.map { $0.coordinate } ?? []
  }
  // Distraction events
  var phoneDistractionEventCount: Int { vehicleTrip.phoneDistractionEventCount ?? 0 }
  var drinkingEventCount: Int { vehicleTrip.drinkingEventCount ?? 0 }
  var distractedGazeEventCount: Int { vehicleTrip.distractedGazeEventCount ?? 0 }
  // Crash detection
  var crashDetected: Bool { vehicleTrip.crashDetected ?? false }
  var crashSeverity: String? { vehicleTrip.crashSeverity }

  init(vehicleTrip: VehicleTrip) {
    self.vehicleTrip = vehicleTrip
  }

  var tripStatus: String {
    status.displayName
  }

  var tripColor: Color {
    status.color
  }

  var tripIcon: String {
    status.icon
  }

  /// Duration of the trip in seconds, or time since start if still ongoing
  var duration: TimeInterval {
    let endTime = timeEnded ?? Date()
    return endTime.timeIntervalSince(timeStarted)
  }

  /// Formatted duration string
  var formattedDuration: String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.hour, .minute, .second]
    formatter.unitsStyle = .abbreviated
    return formatter.string(from: duration) ?? "0s"
  }

  /// Whether the trip is still ongoing (no end time)
  var isOngoing: Bool {
    timeEnded == nil
  }

  /// Smart driving score computed from all trip event data.
  var score: TripScore {
    DrivingScoreCalculator.score(for: self)
  }
}

// MARK: - Navigation Destinations

enum TripEventDestination: Hashable {
  case drowsinessEvents(trip: Trip)
  case excessiveBlinkingEvents(trip: Trip)
  case unstableEyesEvents(trip: Trip)
  case speedingEvents(trip: Trip)
  case phoneDistractionEvents(trip: Trip)
  case drinkingEvents(trip: Trip)
  case distractedGazeEvents(trip: Trip)
}

struct TripEventDetail: Hashable {
  let event: FaceDetection
  let eventType: EventType

  enum EventType: String, Hashable {
    case drowsiness
    case excessiveBlinking
    case unstableEyes
    case speeding
    case phoneDistraction
    case drinking
    case distractedGaze

    var displayName: String {
      switch self {
      case .drowsiness: "Drowsiness"
      case .excessiveBlinking: "Excessive Blinking"
      case .unstableEyes: "Unstable Eyes"
      case .speeding: "Speeding"
      case .phoneDistraction: "Phone Distraction"
      case .drinking: "Drinking"
      case .distractedGaze: "Distracted Gaze"
      }
    }

    var icon: String {
      switch self {
      case .drowsiness: "moon.fill"
      case .excessiveBlinking: "eye"
      case .unstableEyes: "eye.trianglebadge.exclamationmark"
      case .speeding: "exclamationmark.triangle.fill"
      case .phoneDistraction: "iphone.gen3"
      case .drinking: "cup.and.saucer.fill"
      case .distractedGaze: "eye.slash.fill"
      }
    }

    var color: Color {
      switch self {
      case .drowsiness: .yellow
      case .excessiveBlinking: .orange
      case .unstableEyes: .red
      case .speeding: .orange
      case .phoneDistraction: .red
      case .drinking: .orange
      case .distractedGaze: .red
      }
    }
  }
}

// MARK: - Hashable

extension Trip: Hashable {
  static func == (lhs: Trip, rhs: Trip) -> Bool {
    lhs.id == rhs.id
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}

// MARK: - Sample Data

extension Trip {
  /// Sample trip for previews
  static let sample = Trip(
    vehicleTrip: VehicleTrip(
      id: UUID(),
      createdAt: .now,
      vehicleId: "sample",
      sessionId: UUID(),
      driverProfileId: nil,
      startedAt: .now.addingTimeInterval(-3600),
      endedAt: .now,
      status: "ok",
      maxSpeedMph: 65,
      avgSpeedMph: 45.5,
      maxIntoxicationScore: 0,
      speedingEventCount: 0,
      drowsyEventCount: 0,
      excessiveBlinkingEventCount: 0,
      unstableEyesEventCount: 0,
      faceDetectionCount: 10,
      speedSampleCount: 100,
      speedSampleSum: 4550,
      phoneDistractionEventCount: 0,
      drinkingEventCount: 0,
      distractedGazeEventCount: nil,
      routeWaypoints: nil,
      crashDetected: nil,
      crashSeverity: nil
    )
  )

  static let sampleWarning = Trip(
    vehicleTrip: VehicleTrip(
      id: UUID(),
      createdAt: .now,
      vehicleId: "sample",
      sessionId: UUID(),
      driverProfileId: nil,
      startedAt: .now.addingTimeInterval(-1800),
      endedAt: .now,
      status: "warning",
      maxSpeedMph: 80,
      avgSpeedMph: 55.0,
      maxIntoxicationScore: 2,
      speedingEventCount: 3,
      drowsyEventCount: 1,
      excessiveBlinkingEventCount: 2,
      unstableEyesEventCount: 1,
      faceDetectionCount: 15,
      speedSampleCount: 50,
      speedSampleSum: 2750,
      phoneDistractionEventCount: 2,
      drinkingEventCount: 1,
      distractedGazeEventCount: nil,
      routeWaypoints: nil,
      crashDetected: nil,
      crashSeverity: nil
    )
  )

  static let sampleDanger = Trip(
    vehicleTrip: VehicleTrip(
      id: UUID(),
      createdAt: .now,
      vehicleId: "sample",
      sessionId: UUID(),
      driverProfileId: nil,
      startedAt: .now.addingTimeInterval(-900),
      endedAt: nil,
      status: "danger",
      maxSpeedMph: 95,
      avgSpeedMph: 70.0,
      maxIntoxicationScore: 5,
      speedingEventCount: 8,
      drowsyEventCount: 3,
      excessiveBlinkingEventCount: 5,
      unstableEyesEventCount: 4,
      faceDetectionCount: 20,
      speedSampleCount: 30,
      speedSampleSum: 2100,
      phoneDistractionEventCount: 5,
      drinkingEventCount: 3,
      distractedGazeEventCount: nil,
      routeWaypoints: nil,
      crashDetected: nil,
      crashSeverity: nil
    )
  )
}
