//
//  VehicleView.swift
//  InfineonProject
//
//  Created by Aaron Ma on 1/12/26.
//

import AaronUI
import ActivityKit
import CoreLocation
import MapKit
import SwiftUI

struct VehicleView: View {
  var vehicle: V2Profile

  @State private var showingUnidentifiedFaces = false
  @State private var showingVehicleAccessSheet = false

  @State var currentLiveActivity: Activity<VehicleLiveActivityAttributes>?

  var body: some View {
    NavigationStack {
      List {
        // Vehicle image section
        Section {
          AnimatedVehicleView()
            .frame(height: 200)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }

        // Driver alert
        if let data = vehicle.realtimeData {
          driverAlertSection(data: data)
        }

        // Face Detection Section
        Section {
          if vehicle.unidentifiedFacesCount > 0 {
            Button {
              showingUnidentifiedFaces = true
            } label: {
              Label {
                VStack(alignment: .leading) {
                  Text(
                    "\(vehicle.unidentifiedFacesCount) Unidentified Face\(vehicle.unidentifiedFacesCount == 1 ? "" : "s")"
                  )
                  Text("Tap to identify drivers")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
              } icon: {
                Image(systemName: "face.smiling")
                  .foregroundStyle(.orange)
              }
            }
            .tint(.primary)
          }

          NavigationLink {
            FaceDetectionsView(vehicle: vehicle.vehicle)
          } label: {
            Label {
              VStack(alignment: .leading) {
                Text("Face Detections")
                Text("View all driver snapshots")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            } icon: {
              Image(
                systemName: "person.crop.rectangle.stack.fill"
              )
              .foregroundStyle(.blue)
            }
          }
          .tint(.primary)
        } header: {
          Text("Driver Monitoring")
        }

        // Live Data Section
        if let data = vehicle.realtimeData {
          Section("Live Data") {
            NavigationLink {
              VehicleLiveLocationView(vehicleData: data, vehicleName: vehicle.name)
            } label: {
              Label {
                Text("Live Location")

                if let lat = data.latitude, let lon = data.longitude {
                  Text("\(lat, specifier: "%.4f"), \(lon, specifier: "%.4f")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                  Text("No GPS data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
              } icon: {
                SettingsBoxView(
                  icon: "location.fill",
                  color: .blue
                )
              }
            }

            LabeledContent("Speed") {
              HStack {
                Text("\(data.speedMph) mph")
                  .foregroundStyle(
                    data.isSpeeding ? .red : .primary
                  )
                if data.isSpeeding {
                  Image(
                    systemName: "exclamationmark.triangle.fill"
                  )
                  .foregroundStyle(.red)
                }
              }
            }

            LabeledContent(
              "Speed Limit",
              value: "\(data.speedLimitMph) mph"
            )

            LabeledContent("Heading") {
              HStack {
                Image(systemName: "location.north.fill")
                  .rotationEffect(
                    .degrees(
                      Double(data.headingDegrees)
                    )
                  )
                  .foregroundStyle(.blue)
                Text(
                  "\(data.headingDegrees)° \(data.compassDirection)"
                )
              }
            }

            LabeledContent("Status") {
              HStack {
                Circle()
                  .fill(data.isMoving ? .green : .gray)
                  .frame(width: 8, height: 8)
                Text(data.isMoving ? "Moving" : "Parked")
              }
            }

            LabeledContent("Driver Status") {
              DriverStatusBadge(status: data.driverStatus)
            }

            LabeledContent("Risk Score") {
              Text("\(data.intoxicationScore)/6")
                .foregroundStyle(
                  intoxicationColor(
                    for: data.intoxicationScore
                  )
                )
            }

            // GPS Satellites
            if let satellites = data.satellites {
              LabeledContent("GPS Satellites") {
                HStack {
                  Image(systemName: "location.fill")
                    .foregroundStyle(satellites > 0 ? .green : .gray)
                  Text("\(satellites)")
                    .foregroundStyle(satellites > 0 ? .primary : .secondary)
                }
              }
            }

            // Distraction indicators
            if data.isPhoneDetected == true || data.isDrinkingDetected == true {
              LabeledContent("Distraction") {
                HStack(spacing: 8) {
                  if data.isPhoneDetected == true {
                    Label("Phone", systemImage: "iphone.gen3")
                      .font(.caption)
                      .padding(.horizontal, 6)
                      .padding(.vertical, 2)
                      .background(Color.red.opacity(0.2))
                      .foregroundStyle(.red)
                      .clipShape(.capsule)
                  }
                  if data.isDrinkingDetected == true {
                    Label("Drinking", systemImage: "cup.and.saucer.fill")
                      .font(.caption)
                      .padding(.horizontal, 6)
                      .padding(.vertical, 2)
                      .background(Color.orange.opacity(0.2))
                      .foregroundStyle(.orange)
                      .clipShape(.capsule)
                  }
                }
              }
            }

            LabeledContent("Last Updated") {
              Text(data.updatedAt, style: .relative)
                .foregroundStyle(.secondary)
            }
          }
          .onAppear {
            Task {
              do {
                currentLiveActivity = try Activity<VehicleLiveActivityAttributes>
                  .request(
                    attributes: VehicleLiveActivityAttributes(
                      name: vehicle.name,
                      speedLimit: 65
                    ),
                    content: .init(
                      state: .init(
                        speed: data.speedMph, riskScore: data.intoxicationScore,
                        driverStatus: data.driverStatus),
                      staleDate: .now
                        .addingTimeInterval(
                          60 * 60
                        ))
                  )
              } catch {
                print(error.localizedDescription)
              }
            }
          }
          .onChange(of: data.speedMph) {
            Task {
              if let currentLiveActivity {
                await currentLiveActivity.update(
                  ActivityContent(
                    state: .init(
                      speed: data.speedMph, riskScore: data.intoxicationScore,
                      driverStatus: data.driverStatus),
                    staleDate: .now
                      .addingTimeInterval(60 * 60)))
              }
            }
          }
        }

        // Vehicle Info Section
        Section("Vehicle Info") {
          LabeledContent(
            "Name",
            value: vehicle.name
          )
          LabeledContent("ID", value: vehicle.vehicle.id)
          LabeledContent(
            "Invite Code",
            value: vehicle.vehicle.inviteCode
          )
          if let description = vehicle.vehicle.description {
            LabeledContent(
              "Description",
              value: description
            )
          }
        }
      }
      .navigationTitle(vehicle.name)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            Haptics.impact()
            showingVehicleAccessSheet.toggle()
          } label: {
            Image(systemName: "person.2.fill")
          }
        }
      }
    }
    .sheet(isPresented: $showingVehicleAccessSheet) {
      VehicleAccessSheet(vehicle: vehicle.vehicle)
    }
    .sheet(isPresented: $showingUnidentifiedFaces) {
      UnidentifiedFacesView(vehicle: vehicle.vehicle)
    }
  }

  // MARK: - Driver Alert Section

  @ViewBuilder
  private func driverAlertSection(data: VehicleRealtime) -> some View {
    // Phone distraction alert (highest priority)
    if data.isPhoneDetected == true
      || data.driverStatus.lowercased() == "distracted_phone"
    {
      Section {
        Label {
          VStack(alignment: .leading) {
            Text("Phone Detected!")
              .bold()
            Text("Driver is looking at phone - dangerous!")
              .font(.caption)
          }
        } icon: {
          Image(systemName: "iphone.gen3.radiowaves.left.and.right")
            .foregroundStyle(.red)
        }
      }
      .listRowBackground(Color.red.opacity(0.15))
    }
    // Drinking alert
    else if data.isDrinkingDetected == true
      || data.driverStatus.lowercased() == "distracted_drinking"
    {
      Section {
        Label {
          VStack(alignment: .leading) {
            Text("Drinking Detected")
              .bold()
            Text("Driver is drinking - stay focused")
              .font(.caption)
          }
        } icon: {
          Image(systemName: "cup.and.saucer.fill")
            .foregroundStyle(.orange)
        }
      }
      .listRowBackground(Color.orange.opacity(0.1))
    }
    // Impaired alert
    else if data.intoxicationScore >= 4
      || data.driverStatus.lowercased() == "impaired"
    {
      Section {
        Label {
          VStack(alignment: .leading) {
            Text("Driver May Be Impaired")
              .bold()
            Text("Intoxication score: \(data.intoxicationScore)/6")
              .font(.caption)
          }
        } icon: {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
        }
      }
      .listRowBackground(Color.red.opacity(0.1))
    }
    // Drowsy alert
    else if data.intoxicationScore >= 2 || data.driverStatus.lowercased() == "drowsy" {
      Section {
        Label {
          VStack(alignment: .leading) {
            Text("Driver May Be Drowsy")
              .bold()
            Text("Consider taking a break")
              .font(.caption)
          }
        } icon: {
          Image(systemName: "moon.fill")
            .foregroundStyle(.orange)
        }
      }
      .listRowBackground(Color.orange.opacity(0.1))
    }
  }

  // MARK: - Helper Methods

  private func intoxicationColor(for score: Int) -> Color {
    if score >= 4 { return .red }
    if score >= 2 { return .orange }
    return .green
  }
}

// MARK: - Animated Vehicle View

struct AnimatedVehicleView: View {
  @State private var rotation: Angle = .zero
  @State private var scale: CGFloat = 1.0
  @State private var offset: CGSize = .zero

  var body: some View {
    ZStack {
      Image("modelY")
        .resizable()
        .aspectRatio(contentMode: .fit)
    }
  }
}

// MARK: - Driver Status Badge (reused from VehicleListView)

struct DriverStatusBadge: View {
  let status: String

  private var statusColor: Color {
    switch status.lowercased() {
    case "alert": return .green
    case "drowsy": return .orange
    case "impaired": return .red
    case "distracted_phone": return .red
    case "distracted_drinking": return .orange
    default: return .gray
    }
  }

  private var statusIcon: String {
    switch status.lowercased() {
    case "alert": return "checkmark.circle.fill"
    case "drowsy": return "moon.fill"
    case "impaired": return "exclamationmark.triangle.fill"
    case "distracted_phone": return "iphone.gen3"
    case "distracted_drinking": return "cup.and.saucer.fill"
    default: return "questionmark.circle.fill"
    }
  }

  private var displayName: String {
    switch status.lowercased() {
    case "distracted_phone": return "Phone"
    case "distracted_drinking": return "Drinking"
    default: return status.capitalized
    }
  }

  var body: some View {
    Label(displayName, systemImage: statusIcon)
      .font(.caption)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(statusColor.opacity(0.2))
      .foregroundStyle(statusColor)
      .clipShape(.capsule)
  }
}

// MARK: - Vehicle Live Location View

struct VehicleLiveLocationView: View {
  let vehicleData: VehicleRealtime
  let vehicleName: String

  @State private var mapCameraPosition: MapCameraPosition = .automatic
  @State private var route: MKRoute?
  @State private var streetName: String = "Loading..."
  @State private var travelTime: String = "Calculating..."
  @State private var userLocation: CLLocationCoordinate2D?

  private var vehicleCoordinate: CLLocationCoordinate2D? {
    guard let lat = vehicleData.latitude, let lon = vehicleData.longitude else {
      return nil
    }
    return CLLocationCoordinate2D(latitude: lat, longitude: lon)
  }

  var body: some View {
    Group {
      if let vehicleCoord = vehicleCoordinate {
        Map(position: $mapCameraPosition) {
          // Vehicle marker
          Annotation(vehicleName, coordinate: vehicleCoord) {
            ZStack {
              Circle()
                .fill(.blue)
                .frame(width: 44, height: 44)
              Image(systemName: "car.fill")
                .font(.title2)
                .foregroundStyle(.white)
            }
          }

          // User location marker (if available)
          UserAnnotation()

          // Route polyline
          if let route {
            MapPolyline(route.polyline)
              .stroke(.blue, lineWidth: 5)
          }
        }
        .mapControls {
          MapUserLocationButton()
          MapCompass()
          MapScaleView()
        }
        .mapStyle(.standard(elevation: .realistic))
        .safeAreaInset(edge: .bottom) {
          locationInfoCard
        }
        .task {
          await reverseGeocode(coordinate: vehicleCoord)
          await getUserLocationAndCalculateRoute(to: vehicleCoord)
        }
      } else {
        ContentUnavailableView {
          Label("No Location Data", systemImage: "location.slash")
        } description: {
          Text("Vehicle GPS coordinates are not available.")
        }
      }
    }
    .navigationTitle("Vehicle Location")
    .navigationBarTitleDisplayMode(.inline)
  }

  private var locationInfoCard: some View {
    VStack(spacing: 4) {
      Text(streetName)
        .font(.headline)
        .bold()

      HStack(spacing: 4) {
        Image(systemName: "clock")
          .font(.caption)
        Text(travelTime)
          .font(.subheadline)
      }
      .foregroundStyle(.secondary)

      if vehicleData.isMoving {
        HStack(spacing: 4) {
          Circle()
            .fill(.green)
            .frame(width: 8, height: 8)
          Text("Moving at \(vehicleData.speedMph) mph \(vehicleData.compassDirection)")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
    .padding()
    .frame(maxWidth: .infinity)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    .padding()
  }

  private func reverseGeocode(coordinate: CLLocationCoordinate2D) async {
    let geocoder = CLGeocoder()
    let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

    do {
      let placemarks = try await geocoder.reverseGeocodeLocation(location)
      if let placemark = placemarks.first {
        await MainActor.run {
          var components: [String] = []
          if let street = placemark.thoroughfare {
            components.append(street)
          }
          if let city = placemark.locality {
            components.append(city)
          }
          streetName = components.isEmpty ? "Unknown Location" : components.joined(separator: ", ")
        }
      }
    } catch {
      await MainActor.run {
        streetName = "Unknown Location"
      }
    }
  }

  private func getUserLocationAndCalculateRoute(to destination: CLLocationCoordinate2D) async {
    let locationManager = CLLocationManager()

    // Check authorization
    switch locationManager.authorizationStatus {
    case .authorizedWhenInUse, .authorizedAlways:
      break
    case .notDetermined:
      locationManager.requestWhenInUseAuthorization()
      // Wait briefly for authorization
      try? await Task.sleep(for: .seconds(1))
    default:
      await MainActor.run {
        travelTime = "Location access required"
      }
      return
    }

    // Get current location
    guard let currentLocation = locationManager.location else {
      await MainActor.run {
        travelTime = "Unable to get your location"
        // Center on vehicle only
        mapCameraPosition = .region(
          MKCoordinateRegion(
            center: destination,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
          ))
      }
      return
    }

    let userCoord = currentLocation.coordinate
    await MainActor.run {
      userLocation = userCoord
    }

    // Calculate route
    let request = MKDirections.Request()
    request.source = MKMapItem(placemark: MKPlacemark(coordinate: userCoord))
    request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
    request.transportType = .automobile

    let directions = MKDirections(request: request)

    do {
      let response = try await directions.calculate()
      if let calculatedRoute = response.routes.first {
        await MainActor.run {
          route = calculatedRoute
          travelTime = formatTravelTime(calculatedRoute.expectedTravelTime)

          // Adjust map to show entire route
          let rect = calculatedRoute.polyline.boundingMapRect
          mapCameraPosition = .rect(rect.insetBy(dx: -rect.width * 0.2, dy: -rect.height * 0.2))
        }
      }
    } catch {
      await MainActor.run {
        travelTime = "Route unavailable"
        // Center on vehicle
        mapCameraPosition = .region(
          MKCoordinateRegion(
            center: destination,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
          ))
      }
    }
  }

  private func formatTravelTime(_ seconds: TimeInterval) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.hour, .minute]
    formatter.unitsStyle = .full
    formatter.maximumUnitCount = 2

    if let formatted = formatter.string(from: seconds) {
      return "\(formatted) away"
    }
    return "Calculating..."
  }
}

#Preview {
  VehicleView(
    vehicle: V2Profile(
      id: "111", name: "AA", icon: "benji", vehicleId: "111",
      vehicle: Vehicle(
        id: "", createdAt: .now, updatedAt: .now, name: "", description: "", inviteCode: "",
        ownerId: UUID())))
}

#Preview("Live Location") {
  NavigationStack {
    VehicleLiveLocationView(
      vehicleData: VehicleRealtime(
        vehicleId: "test",
        updatedAt: .now,
        latitude: 37.3349,
        longitude: -122.0090,
        speedMph: 45,
        speedLimitMph: 65,
        headingDegrees: 270,
        compassDirection: "W",
        isSpeeding: false,
        isMoving: true,
        driverStatus: "alert",
        intoxicationScore: 0,
        satellites: 12,
        isPhoneDetected: false,
        isDrinkingDetected: false
      ),
      vehicleName: "Test Vehicle"
    )
  }
}
