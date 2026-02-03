//
//  VehicleView.swift
//  InfineonProject
//
//  Created by Aaron Ma on 1/12/26.
//

import AaronUI
import ActivityKit
internal import Combine
import CoreLocation
import MapKit
import SwiftUI

struct VehicleView: View {
  var vehicle: V2Profile

  @State private var showingUnidentifiedFaces = false
  @State private var showingVehicleAccessSheet = false

  @State var currentLiveActivity: Activity<VehicleLiveActivityAttributes>?

  // Location preview data
  @StateObject private var previewLocationManager = UserLocationManager()
  @State private var vehicleStreetName: String?
  @State private var vehicleTravelTime: String?
  @State private var cachedRoute: MKRoute?
  @State private var cachedVehicleCoordinate: CLLocationCoordinate2D?
  @State private var cachedUserCoordinate: CLLocationCoordinate2D?

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
              VehicleLiveLocationView(
                vehicleData: data,
                vehicleName: vehicle.name,
                cachedRoute: cachedRoute,
                cachedStreetName: vehicleStreetName,
                cachedUserLocation: cachedUserCoordinate
              )
            } label: {
              Label {
                // Primary: Street name, fallback: "Live Location"
                if let streetName = vehicleStreetName {
                  Text(streetName)
                } else if data.latitude != nil && data.longitude != nil {
                  Text("Live Location")
                } else {
                  Text("Location Unavailable")
                }

                // Secondary: Travel time, fallback: coordinates, fallback: "No GPS data"
                if let travelTime = vehicleTravelTime {
                  Text(travelTime)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else if let lat = data.latitude, let lon = data.longitude {
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
            .task {
              await fetchVehicleLocationPreview(data: data)
            }
            .onChange(of: previewLocationManager.userLocation) { _, newLocation in
              if let userCoord = newLocation,
                let lat = data.latitude,
                let lon = data.longitude
              {
                Task {
                  await calculatePreviewTravelTime(
                    from: userCoord,
                    to: CLLocationCoordinate2D(latitude: lat, longitude: lon)
                  )
                }
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

        Section {
          LabeledContent(
            "Name",
            value: vehicle.name
          )
          LabeledContent("ID", value: vehicle.vehicle.id)
          if let description = vehicle.vehicle.description {
            LabeledContent(
              "Description",
              value: description
            )
          }
        } header: {
          Text("Debug")
        } footer: {
          Text("Currently chosen vehicle info. Connected to server.")
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

  private func fetchVehicleLocationPreview(data: VehicleRealtime) async {
    guard let lat = data.latitude, let lon = data.longitude else { return }

    // Reverse geocode to get street name
    let geocoder = CLGeocoder()
    let location = CLLocation(latitude: lat, longitude: lon)

    do {
      let placemarks = try await geocoder.reverseGeocodeLocation(location)
      if let placemark = placemarks.first {
        var components: [String] = []
        if let street = placemark.thoroughfare {
          components.append(street)
        }
        if let city = placemark.locality {
          components.append(city)
        }
        if !components.isEmpty {
          vehicleStreetName = components.joined(separator: ", ")
        }
      }
    } catch {
      // Keep vehicleStreetName as nil, will show fallback
    }

    // Request user location to calculate travel time
    previewLocationManager.requestLocation()
  }

  private func calculatePreviewTravelTime(
    from source: CLLocationCoordinate2D,
    to destination: CLLocationCoordinate2D
  ) async {
    // Check if we can use cached route (coordinates haven't changed significantly)
    if let cachedRoute = cachedRoute,
      let cachedUser = cachedUserCoordinate,
      let cachedVehicle = cachedVehicleCoordinate,
      isCoordinateNearby(source, cachedUser, thresholdMeters: 100),
      isCoordinateNearby(destination, cachedVehicle, thresholdMeters: 100)
    {
      // Use cached data, no need to recalculate
      let formatter = DateComponentsFormatter()
      formatter.allowedUnits = [.hour, .minute]
      formatter.unitsStyle = .short
      formatter.maximumUnitCount = 2

      if let formatted = formatter.string(from: cachedRoute.expectedTravelTime) {
        vehicleTravelTime = "\(formatted) away"
      }
      return
    }

    let request = MKDirections.Request()
    request.source = MKMapItem(placemark: MKPlacemark(coordinate: source))
    request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
    request.transportType = .automobile

    let directions = MKDirections(request: request)

    do {
      let response = try await directions.calculate()
      if let route = response.routes.first {
        // Cache the route and coordinates
        cachedRoute = route
        cachedUserCoordinate = source
        cachedVehicleCoordinate = destination

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .short
        formatter.maximumUnitCount = 2

        if let formatted = formatter.string(from: route.expectedTravelTime) {
          vehicleTravelTime = "\(formatted) away"
        }
      }
    } catch {
      // Keep vehicleTravelTime as nil, will show coordinates as fallback
    }
  }

  private func isCoordinateNearby(
    _ coord1: CLLocationCoordinate2D,
    _ coord2: CLLocationCoordinate2D,
    thresholdMeters: Double
  ) -> Bool {
    let location1 = CLLocation(latitude: coord1.latitude, longitude: coord1.longitude)
    let location2 = CLLocation(latitude: coord2.latitude, longitude: coord2.longitude)
    return location1.distance(from: location2) < thresholdMeters
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

// MARK: - CLLocationCoordinate2D Equatable

extension CLLocationCoordinate2D: @retroactive Equatable {
  public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
    lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
  }
}

// MARK: - Location Manager

@MainActor
class UserLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
  private let locationManager = CLLocationManager()

  @Published var userLocation: CLLocationCoordinate2D?
  @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
  @Published var locationError: String?

  override init() {
    super.init()
    locationManager.delegate = self
    locationManager.desiredAccuracy = kCLLocationAccuracyBest
    authorizationStatus = locationManager.authorizationStatus
  }

  func requestLocation() {
    locationError = nil

    switch authorizationStatus {
    case .notDetermined:
      locationManager.requestWhenInUseAuthorization()
    case .authorizedWhenInUse, .authorizedAlways:
      locationManager.requestLocation()
    case .denied, .restricted:
      locationError = "Location access denied. Please enable in Settings."
    @unknown default:
      locationError = "Unknown authorization status"
    }
  }

  nonisolated func locationManager(
    _ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus
  ) {
    Task { @MainActor in
      authorizationStatus = status
      if status == .authorizedWhenInUse || status == .authorizedAlways {
        locationManager.requestLocation()
      }
    }
  }

  nonisolated func locationManager(
    _ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]
  ) {
    Task { @MainActor in
      if let location = locations.last {
        userLocation = location.coordinate
      }
    }
  }

  nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    Task { @MainActor in
      locationError = error.localizedDescription
    }
  }
}

// MARK: - Vehicle Live Location View

struct VehicleLiveLocationView: View {
  let vehicleData: VehicleRealtime
  let vehicleName: String
  let cachedRoute: MKRoute?
  let cachedStreetName: String?
  let cachedUserLocation: CLLocationCoordinate2D?

  @StateObject private var locationManager = UserLocationManager()
  @State private var mapCameraPosition: MapCameraPosition = .automatic
  @State private var route: MKRoute?
  @State private var streetName: String = "Loading..."
  @State private var travelTime: String = "Locating you..."
  @State private var hasCalculatedRoute = false
  @State private var hasInitializedFromCache = false

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

          // User location
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
          if #available(iOS 26, macOS 26, watchOS 26, tvOS 26, visionOS 26, *) {
            locationInfoCard
              .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
          } else {
            locationInfoCard
              .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
              .padding()
          }
        }
        .onAppear {
          initializeFromCache(vehicleCoord: vehicleCoord)
          if cachedRoute == nil {
            locationManager.requestLocation()
          }
        }
        .task {
          if cachedStreetName == nil {
            await reverseGeocode(coordinate: vehicleCoord)
          }
        }
        .onChange(of: locationManager.userLocation) { _, newLocation in
          if let userCoord = newLocation, let vehicleCoord = vehicleCoordinate, !hasCalculatedRoute
          {
            hasCalculatedRoute = true
            Task {
              await calculateRoute(from: userCoord, to: vehicleCoord)
            }
          }
        }
        .onChange(of: locationManager.locationError) { _, error in
          if let error {
            travelTime = error
            if let vehicleCoord = vehicleCoordinate {
              mapCameraPosition = .region(
                MKCoordinateRegion(
                  center: vehicleCoord,
                  span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                ))
            }
          }
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
  }

  private func initializeFromCache(vehicleCoord: CLLocationCoordinate2D) {
    guard !hasInitializedFromCache else { return }
    hasInitializedFromCache = true

    // Use cached street name if available
    if let cachedStreetName {
      streetName = cachedStreetName
    }

    // Use cached route if available
    if let cachedRoute {
      route = cachedRoute
      hasCalculatedRoute = true

      let formatter = DateComponentsFormatter()
      formatter.allowedUnits = [.hour, .minute]
      formatter.unitsStyle = .full
      formatter.maximumUnitCount = 2

      if let formatted = formatter.string(from: cachedRoute.expectedTravelTime) {
        travelTime = "\(formatted) away"
      }

      // Set map position to show the cached route
      let rect = cachedRoute.polyline.boundingMapRect
      mapCameraPosition = .rect(rect.insetBy(dx: -rect.width * 0.2, dy: -rect.height * 0.2))
    }
  }

  private func reverseGeocode(coordinate: CLLocationCoordinate2D) async {
    let geocoder = CLGeocoder()
    let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

    do {
      let placemarks = try await geocoder.reverseGeocodeLocation(location)
      if let placemark = placemarks.first {
        var components: [String] = []
        if let street = placemark.thoroughfare {
          components.append(street)
        }
        if let city = placemark.locality {
          components.append(city)
        }
        streetName = components.isEmpty ? "Unknown Location" : components.joined(separator: ", ")
      }
    } catch {
      streetName = "Unknown Location"
    }
  }

  private func calculateRoute(
    from source: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D
  ) async {
    let request = MKDirections.Request()
    request.source = MKMapItem(placemark: MKPlacemark(coordinate: source))
    request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
    request.transportType = .automobile

    let directions = MKDirections(request: request)

    do {
      let response = try await directions.calculate()
      if let calculatedRoute = response.routes.first {
        route = calculatedRoute
        travelTime = formatTravelTime(calculatedRoute.expectedTravelTime)

        // Adjust map to show entire route
        let rect = calculatedRoute.polyline.boundingMapRect
        mapCameraPosition = .rect(rect.insetBy(dx: -rect.width * 0.2, dy: -rect.height * 0.2))
      }
    } catch {
      travelTime = "Route unavailable"
      mapCameraPosition = .region(
        MKCoordinateRegion(
          center: destination,
          span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        ))
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
      vehicleName: "Test Vehicle",
      cachedRoute: nil,
      cachedStreetName: nil,
      cachedUserLocation: nil
    )
  }
}
