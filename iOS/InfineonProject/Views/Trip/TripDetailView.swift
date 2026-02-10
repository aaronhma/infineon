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
  var namespace: Namespace.ID

  // Placeholder locations for map (in a real app, these would come from trip data)
  private let startLocation = CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090)
  private let endLocation = CLLocationCoordinate2D(latitude: 37.8199, longitude: -122.4783)

  @State private var route: MKRoute?
  @State private var mapCameraPosition: MapCameraPosition = .automatic

  var body: some View {
    ZStack {
      LinearGradient(
        colors: [
          trip.tripColor,
          trip.tripColor.opacity(0.9),
          .clear,
          .clear,
          .clear,
          .clear,
          .clear,
        ],
        startPoint: .top,
        endPoint: .bottom
      )
      .ignoresSafeArea()

      List {
        // Header section
        Section {
          VStack(spacing: 10) {
            Circle()
              .fill(trip.tripColor.gradient)
              .frame(width: 100, height: 100)
              .overlay {
                Image(systemName: trip.tripIcon)
                  .font(.system(size: 60))
                  .foregroundStyle(.white)
              }

            Text(trip.tripStatus)
              .font(.title2)
              .bold()
              .titleVisibilityAnchor()

            if trip.isOngoing {
              Text("Trip in progress")
                .font(.subheadline)
                .foregroundStyle(.orange)
            } else {
              Text(trip.timeStarted.formatted(.dateTime))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }

            Text("Duration: \(trip.formattedDuration)")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity, alignment: .center)
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)

        // Trip Statistics
        Section("Trip Statistics") {
          LabeledContent("Max Speed") {
            Text("\(trip.maxSpeedMph) mph")
              .foregroundStyle(trip.maxSpeedMph > 65 ? .red : .primary)
          }

          LabeledContent("Average Speed") {
            Text(trip.avgSpeedMph, format: .number.precision(.fractionLength(1)))
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

        // Driver Monitoring Section - Now with NavigationLinks
        Section("Driver Monitoring") {
          // Drowsiness events
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
            .tint(.primary)
          } else {
            Label {
              Text("No drowsiness detected")
            } icon: {
              Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            }
          }

          // Excessive blinking events
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
            .tint(.primary)
          } else {
            Label {
              Text("No excessive blinking detected")
            } icon: {
              Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            }
          }

          // Unstable eyes events
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
            .tint(.primary)
          } else {
            Label {
              Text("No unstable eyes detected")
            } icon: {
              Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            }
          }

          LabeledContent("Max Risk Score") {
            Text("\(trip.maxIntoxicationScore)/6")
              .foregroundStyle(riskScoreColor)
          }
        }

        // Distraction Events Section
        Section("Distraction Events") {
          // Phone distraction events
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
            .tint(.primary)
          } else {
            Label {
              Text("No phone distractions")
            } icon: {
              Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            }
          }

          // Drinking events
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
            .tint(.primary)
          } else {
            Label {
              Text("No drinking detected")
            } icon: {
              Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            }
          }
        }

        // Speed Violations Section - Now with NavigationLink
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
            .tint(.primary)
          } else {
            Label {
              Text("No speeding violations")
            } icon: {
              Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            }
          }
        }

        // Trip Route Section (placeholder)
        Section("Trip Route") {
          Map(position: $mapCameraPosition) {
            Marker("Start", coordinate: startLocation)
              .tint(.green)

            Marker("End", coordinate: endLocation)
              .tint(.red)

            if let route {
              MapPolyline(route.polyline)
                .stroke(.blue, lineWidth: 5)
            }
          }
          .mapStyle(.standard(elevation: .realistic))
          .frame(height: 250)
          .clipShape(.rect(cornerRadius: 12))
          .listRowInsets(EdgeInsets())
        }
      }
    }
    .scrollAwareTitle(trip.tripStatus)
    .navigationBarTitleDisplayMode(.inline)
    .navigationTransition(.zoom(sourceID: trip.id, in: namespace))
    .task {
      await calculateRoute()
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

  private func calculateRoute() async {
    let request = MKDirections.Request()
    request.source = MKMapItem(placemark: MKPlacemark(coordinate: startLocation))
    request.destination = MKMapItem(placemark: MKPlacemark(coordinate: endLocation))
    request.transportType = .automobile

    let directions = MKDirections(request: request)

    do {
      let response = try await directions.calculate()
      await MainActor.run {
        route = response.routes.first

        if let route {
          let rect = route.polyline.boundingMapRect
          mapCameraPosition = .rect(rect.insetBy(dx: -rect.width * 0.1, dy: -rect.height * 0.1))
        }
      }
    } catch {
      print("Error calculating route: \(error)")
    }
  }
}

#Preview {
  @Previewable @Namespace var namespace

  NavigationStack {
    TripDetailView(trip: Trip.sample, namespace: namespace)
  }
}
