//
//  DrivingScoreCalculator.swift
//  InfineonProject
//
//  Created by Aaron Ma on 2/20/26.
//

import Foundation

/// The result of scoring a single trip across three dimensions.
struct TripScore {
  /// Overall driving score (0-100), weighted combination of sub-scores.
  let overall: Int
  /// Measures driver focus: phone, drowsiness, eye behavior (0-100).
  let attentiveness: Int
  /// Measures driving behavior: speeding, max speed, avg speed (0-100).
  let safety: Int
  /// Measures impairment indicators: intoxication score, drinking (0-100).
  let impairment: Int
  /// Whether enough face detections exist for confident attentiveness/impairment scoring.
  let isConfident: Bool
  /// Whether the camera captured any face data at all.
  let isCameraAvailable: Bool
}

/// Aggregated daily score across multiple trips.
struct DailyScore {
  let overall: Int
  let attentiveness: Int
  let safety: Int
  let impairment: Int
  let tripCount: Int
  let totalDurationSeconds: TimeInterval
}

/// Pure scoring engine with no UI dependencies.
/// All penalty constants are exposed as static properties for easy tuning.
enum DrivingScoreCalculator {

  // MARK: - Attentiveness Penalties (per event per hour)

  static let phonePenaltyPerHour: Double = 15
  static let phoneMaxPenalty: Double = 50

  static let drowsyPenaltyPerHour: Double = 8
  static let drowsyMaxPenalty: Double = 30

  static let unstablePenaltyPerHour: Double = 6
  static let unstableMaxPenalty: Double = 25

  static let blinkingPenaltyPerHour: Double = 3
  static let blinkingMaxPenalty: Double = 15

  // MARK: - Safety Penalties

  static let speedingPenaltyPerHour: Double = 5
  static let speedingMaxPenalty: Double = 40

  static let avgSpeedThreshold: Double = 75
  static let avgSpeedPenaltyPerMph: Double = 0.5
  static let avgSpeedMaxPenalty: Double = 15

  // Max speed tier penalties: (upper bound, penalty)
  static let maxSpeedTiers: [(upperBound: Int, penalty: Double)] = [
    (80, 0),
    (90, 10),
    (100, 20),
  ]
  static let maxSpeedExtremePenalty: Double = 30

  // MARK: - Impairment Penalties

  /// Exponential-curve penalties indexed by intoxication score (0-6).
  static let intoxicationPenalties: [Double] = [0, 5, 15, 30, 50, 65, 80]

  static let drinkingPenaltyPerHour: Double = 20
  static let drinkingMaxPenalty: Double = 40

  // MARK: - Overall Weights

  static let attentivenessWeight: Double = 0.30
  static let safetyWeight: Double = 0.25
  static let impairmentWeight: Double = 0.45

  // MARK: - Thresholds

  /// Trips shorter than this are considered too short to score meaningfully.
  static let minimumTripDurationSeconds: TimeInterval = 120

  /// Minimum face detections for confident attentiveness/impairment scoring.
  static let minimumFaceDetections = 5

  // MARK: - Per-Trip Scoring

  static func score(for trip: Trip) -> TripScore {
    let durationSeconds = trip.duration
    let durationHours = durationSeconds / 3600.0

    let hasCriticalEvent =
      trip.maxIntoxicationScore >= 4
      || trip.phoneDistractionEventCount > 0
      || trip.drinkingEventCount > 0

    // Very short trips get a perfect score unless something critical happened
    if durationSeconds < minimumTripDurationSeconds && !hasCriticalEvent {
      return TripScore(
        overall: 100,
        attentiveness: 100,
        safety: 100,
        impairment: 100,
        isConfident: true,
        isCameraAvailable: true
      )
    }

    let isCameraAvailable = trip.faceDetectionCount > 0
    let isConfident = trip.faceDetectionCount >= minimumFaceDetections

    // Attentiveness
    let attentiveness = calculateAttentiveness(
      phoneCount: trip.phoneDistractionEventCount,
      drowsyCount: trip.drowsyEventCount,
      unstableCount: trip.unstableEyesEventCount,
      blinkingCount: trip.excessiveBlinkingEventCount,
      durationHours: durationHours
    )

    // Safety
    let safety = calculateSafety(
      speedingCount: trip.speedingEventCount,
      maxSpeed: trip.maxSpeedMph,
      avgSpeed: trip.avgSpeedMph,
      durationHours: durationHours
    )

    // Impairment
    let impairment = calculateImpairment(
      intoxicationScore: trip.maxIntoxicationScore,
      drinkingCount: trip.drinkingEventCount,
      durationHours: durationHours
    )

    // Overall: if camera unavailable, only safety contributes
    let overall: Int
    if !isCameraAvailable {
      overall = safety
    } else {
      overall = Int(
        (Double(attentiveness) * attentivenessWeight)
          + (Double(safety) * safetyWeight)
          + (Double(impairment) * impairmentWeight)
      )
    }

    return TripScore(
      overall: overall,
      attentiveness: attentiveness,
      safety: safety,
      impairment: impairment,
      isConfident: isConfident,
      isCameraAvailable: isCameraAvailable
    )
  }

  // MARK: - Daily Aggregation

  /// Duration-weighted aggregation of trip scores. Longer trips count more.
  static func dailyScore(for trips: [Trip]) -> DailyScore {
    guard !trips.isEmpty else {
      return DailyScore(
        overall: 100,
        attentiveness: 100,
        safety: 100,
        impairment: 100,
        tripCount: 0,
        totalDurationSeconds: 0
      )
    }

    var weightedOverall: Double = 0
    var weightedAttentiveness: Double = 0
    var weightedSafety: Double = 0
    var weightedImpairment: Double = 0
    var totalDuration: TimeInterval = 0

    for trip in trips {
      let tripScore = score(for: trip)
      // Use at least 1 second of weight so zero-duration trips don't vanish
      let weight = max(trip.duration, 1)
      totalDuration += weight

      weightedOverall += Double(tripScore.overall) * weight
      weightedAttentiveness += Double(tripScore.attentiveness) * weight
      weightedSafety += Double(tripScore.safety) * weight
      weightedImpairment += Double(tripScore.impairment) * weight
    }

    return DailyScore(
      overall: Int(weightedOverall / totalDuration),
      attentiveness: Int(weightedAttentiveness / totalDuration),
      safety: Int(weightedSafety / totalDuration),
      impairment: Int(weightedImpairment / totalDuration),
      tripCount: trips.count,
      totalDurationSeconds: totalDuration
    )
  }

  // MARK: - Sub-Score Calculations

  private static func calculateAttentiveness(
    phoneCount: Int,
    drowsyCount: Int,
    unstableCount: Int,
    blinkingCount: Int,
    durationHours: Double
  ) -> Int {
    let effectiveDuration = max(durationHours, 1.0 / 60.0)

    let phoneRate = Double(phoneCount) / effectiveDuration
    let drowsyRate = Double(drowsyCount) / effectiveDuration
    let unstableRate = Double(unstableCount) / effectiveDuration
    let blinkingRate = Double(blinkingCount) / effectiveDuration

    let penalty =
      min(phoneRate * phonePenaltyPerHour, phoneMaxPenalty)
      + min(drowsyRate * drowsyPenaltyPerHour, drowsyMaxPenalty)
      + min(unstableRate * unstablePenaltyPerHour, unstableMaxPenalty)
      + min(blinkingRate * blinkingPenaltyPerHour, blinkingMaxPenalty)

    return max(0, 100 - Int(penalty))
  }

  private static func calculateSafety(
    speedingCount: Int,
    maxSpeed: Int,
    avgSpeed: Double,
    durationHours: Double
  ) -> Int {
    let effectiveDuration = max(durationHours, 1.0 / 60.0)

    let speedingRate = Double(speedingCount) / effectiveDuration
    let speedingPenalty = min(speedingRate * speedingPenaltyPerHour, speedingMaxPenalty)

    // Max speed tier penalty
    var maxSpeedPenalty = maxSpeedExtremePenalty
    for tier in maxSpeedTiers {
      if maxSpeed <= tier.upperBound {
        maxSpeedPenalty = tier.penalty
        break
      }
    }

    // High average speed penalty
    let avgSpeedPenalty = min(
      max(0, (avgSpeed - avgSpeedThreshold) * avgSpeedPenaltyPerMph), avgSpeedMaxPenalty)

    let penalty = speedingPenalty + maxSpeedPenalty + avgSpeedPenalty
    return max(0, 100 - Int(penalty))
  }

  private static func calculateImpairment(
    intoxicationScore: Int,
    drinkingCount: Int,
    durationHours: Double
  ) -> Int {
    let effectiveDuration = max(durationHours, 1.0 / 60.0)

    // Clamp intoxication score to valid range
    let clampedScore = min(max(intoxicationScore, 0), intoxicationPenalties.count - 1)
    let intoxicationPenalty = intoxicationPenalties[clampedScore]

    let drinkingRate = Double(drinkingCount) / effectiveDuration
    let drinkingPenalty = min(drinkingRate * drinkingPenaltyPerHour, drinkingMaxPenalty)

    let penalty = intoxicationPenalty + drinkingPenalty
    return max(0, 100 - Int(penalty))
  }

  // MARK: - Utilities

  /// Returns the color category for a score value.
  static func scoreCategory(for score: Int) -> ScoreCategory {
    if score >= 80 { return .good }
    if score >= 50 { return .moderate }
    return .poor
  }

  enum ScoreCategory {
    case good
    case moderate
    case poor
  }

  /// Computes the rate per hour for a given event count and trip duration in seconds.
  static func ratePerHour(count: Int, durationSeconds: TimeInterval) -> Double {
    let hours = max(durationSeconds / 3600.0, 1.0 / 60.0)
    return Double(count) / hours
  }
}
