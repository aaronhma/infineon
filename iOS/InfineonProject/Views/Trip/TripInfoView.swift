//
//  TripInfoView.swift
//  InfineonProject
//
//  Created by Aaron Ma on 1/12/26.
//

import AaronUI
import SwiftUI

struct TripInfoView: View {
  var trip: Trip
  var namespace: Namespace.ID

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Circle()
        .fill(trip.tripColor.gradient)
        .frame(width: 44, height: 44)
        .overlay {
          Image(systemName: trip.tripIcon)
            .font(.system(size: 22))
            .foregroundStyle(.white)
        }
        .stableMatchedTransition(id: trip.id, in: namespace)

      VStack(alignment: .leading, spacing: 6) {
        // Title row
        HStack {
          Text(trip.tripStatus)
            .font(.headline)

          if trip.isOngoing {
            Text("LIVE")
              .font(.caption2)
              .bold()
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(.red)
              .foregroundStyle(.white)
              .clipShape(.capsule)
          }

          Spacer()

          Text(trip.formattedDuration)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }

        // Date
        Text(
          trip.timeStarted.formatted(.dateTime.weekday(.abbreviated).month().day().hour().minute())
        )
        .font(.subheadline)
        .foregroundStyle(.secondary)

        // Stats row
        HStack(spacing: 16) {
          if trip.maxSpeedMph > 0 {
            Label("\(trip.maxSpeedMph) mph", systemImage: "speedometer")
              .foregroundStyle(.secondary)
          }

          if trip.speedingEventCount > 0 {
            Label("\(trip.speedingEventCount)", systemImage: "exclamationmark.triangle.fill")
              .foregroundStyle(.orange)
          }

          if trip.drowsyEventCount > 0 {
            Label("\(trip.drowsyEventCount)", systemImage: "moon.fill")
              .foregroundStyle(.yellow)
          }

          if trip.excessiveBlinkingEventCount > 0 {
            Label("\(trip.excessiveBlinkingEventCount)", systemImage: "eye")
              .foregroundStyle(.orange)
          }

          if trip.unstableEyesEventCount > 0 {
            Label(
              "\(trip.unstableEyesEventCount)", systemImage: "eye.trianglebadge.exclamationmark"
            )
            .foregroundStyle(.red)
          }
        }
        .font(.caption)
      }
    }
    .padding(.vertical, 4)
  }
}

#Preview {
  @Previewable @Namespace var namespace

  List {
    TripInfoView(trip: Trip.sample, namespace: namespace)
    TripInfoView(trip: Trip.sampleWarning, namespace: namespace)
    TripInfoView(trip: Trip.sampleDanger, namespace: namespace)
  }
}
