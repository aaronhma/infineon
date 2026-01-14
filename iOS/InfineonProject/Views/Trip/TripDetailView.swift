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

  // Apple Park
  private let startLocation = CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090)
  // Golden Gate Bridge
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

            Text(trip.timeStarted.formatted(.dateTime))
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
          }
          .frame(maxWidth: .infinity, alignment: .center)
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)

        Section("Distracted Driving") {
          Text("No infractions.")
        }

        Section("Speed Violations") {
          Text("No infractions.")
        }

        Section("Trip Route") {
          Map(position: $mapCameraPosition) {
            // Start marker (Apple Park)
            Marker("Apple Park", coordinate: startLocation)
              .tint(.green)

            // End marker (Golden Gate Bridge)
            Marker("Golden Gate Bridge", coordinate: endLocation)
              .tint(.red)

            // Route polyline
            if let route {
              MapPolyline(route.polyline)
                .stroke(.blue, lineWidth: 5)
            }
          }
          .mapStyle(.standard(elevation: .realistic))
          .frame(height: 250)
          .clipShape(RoundedRectangle(cornerRadius: 12))
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

        // Set camera to show the entire route
        if let route {
          let rect = route.polyline.boundingMapRect
          let padding = UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40)
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
