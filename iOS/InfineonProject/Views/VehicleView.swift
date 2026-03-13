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
import Supabase
import SwiftUI

struct VehicleView: View {
  var vehicle: V2Profile

  @Namespace private var namespace

  @State private var showingFaceDetectionsSheet = false
  @State private var showingAlertSheet = false

  @State private var showingLiveCameraSheet = false
  @State private var showingTripsSheet = false
  @State private var showingShazamHistorySheet = false
  @State private var showingLiveLocationSheet = false
  @State private var showingVehicleSettingsSheet = false
  @State private var showingBluetoothSheet = false

  @State private var showingVehicleAccessSheet = false
  @State private var showingAccountSheet = false

  @State var currentLiveActivity: Activity<VehicleLiveActivityAttributes>?

  // Location preview data
  @StateObject private var previewLocationManager = UserLocationManager()
  @State private var vehicleStreetName: String?
  @State private var vehicleTravelTime: String?
  @State private var cachedRoute: MKRoute?
  @State private var cachedVehicleCoordinate: CLLocationCoordinate2D?
  @State private var cachedUserCoordinate: CLLocationCoordinate2D?

  // Buzzer preview data
  @State private var cachedBuzzerActive: Bool?
  @State private var cachedBuzzerType: String?

  // Realtime refresh task
  @State private var realtimeRefreshTask: Task<Void, Never>?

  // Scroll tracking
  @State private var scrollOffset: CGFloat = 0

  private var scrollBlurAmount: CGFloat {
    max(0, min(scrollOffset / 30.0, 10))
  }

  private var scrollDimAmount: Double {
    max(0, min(Double(scrollOffset) / 200.0, 0.5))
  }

  var body: some View {
    NavigationStack {
      ZStack(alignment: .top) {
        VehicleAnimationView(
          isParked: !(vehicle.realtimeData?.isMoving ?? false),
          speed: vehicle.realtimeData?.speedMph ?? 0
        )
        .frame(height: 350)
        .blur(radius: scrollBlurAmount)
        .opacity(1.0 - scrollDimAmount)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .topLeading) {
          VStack(alignment: .leading) {
            Text(vehicle.name)
              .font(.largeTitle)
              .bold()

            if let data = vehicle.realtimeData {
              Text(data.updatedAt, style: .relative)
                .foregroundStyle(.secondary)

              Text(data.isMoving ? "\(data.speedMph) MPH" : "Parked")
                .contentTransition(.numericText(value: 0))
                .foregroundStyle(.secondary)

              //                HStack {
              //                  Text(
              //                    "\(Text("\(data.speedMph)").font(.title2).foregroundStyle(.primary))/\(data.speedLimitMph)MPH"
              //                  )
              //                  .contentTransition(.numericText(value: 0))
              //                  .foregroundStyle(
              //                    data.isSpeeding ? .red : .secondary
              //                  )
              //
              //                  if data.isSpeeding {
              //                    Image(
              //                      systemName: "exclamationmark.triangle.fill"
              //                    )
              //                    .foregroundStyle(.red)
              //                  }
              //                }
            }
          }
          .blur(radius: scrollBlurAmount)
          .opacity(1.0 - scrollDimAmount)
          .padding(.horizontal)
        }

        ScrollView {
          VStack(spacing: 0) {
            Color.clear.frame(height: 290)

            VStack(alignment: .leading, spacing: 25) {
              // BLE connected banner
              if bluetooth.isConnected {
                Label {
                  VStack(alignment: .leading) {
                    Text("Bluetooth Connection")
                      .bold()
                    Text("Offline mode enabled")
                      .font(.caption)
                  }
                } icon: {
                  SettingsBoxView(icon: "antenna.radiowaves.left.and.right", color: .blue)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.15), in: .rect(cornerRadius: 10))
              }

              // Currently playing song
              if let songTitle = vehicle.realtimeData?.currentSongTitle {
                VStack(spacing: 0) {
                  HStack {
                    VStack(alignment: .leading) {
                      MarqueeView {
                        Text(songTitle)
                          .font(.subheadline)
                          .lineLimit(1)
                      }
                      if let artist = vehicle.realtimeData?.currentSongArtist {
                        MarqueeView {
                          Text(artist)
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                            .lineLimit(1)
                        }
                      }
                    }
                    Spacer()
                    SettingsBoxView(icon: "music.note", color: .pink)
                  }
                  .padding(.horizontal)
                  .padding(.vertical, 12)

                  AaronButtonView("All Songs", systemImage: "music.note.list", applyGlass: false) {
                    showingShazamHistorySheet.toggle()
                  }
                  .contentShape(.capsule)
                  .buttonStyle(
                    FluidZoomTransitionStyle(
                      id: "shazamHistorySheet", namespace: namespace, shape: .capsule,
                      applyGlass: false)
                  )
                  .padding()
                }
                .background(Color(.secondarySystemBackground))
                .clipShape(.rect(cornerRadius: 12))
              }

              // Driver alert
              if let data = vehicle.realtimeData {
                driverAlertSection(data: data)
              }

              // Face Detections
              Button {
                showingFaceDetectionsSheet.toggle()
              } label: {
                Label {
                  Text("Face Detections")
                } icon: {
                  SettingsBoxView(
                    icon: "person.crop.rectangle.stack.fill",
                    color: .blue
                  )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
              }
              .tint(.primary)
              .contentShape(.rect)
              .buttonStyle(
                FluidZoomTransitionStyle(
                  id: "faceDetectionsSheet", namespace: namespace, shape: .rect, applyGlass: false))

              Button {
                showingTripsSheet.toggle()
              } label: {
                Label {
                  VStack(alignment: .leading) {
                    Text("Trips")
                  }
                } icon: {
                  SettingsBoxView(
                    icon: "airplane.up.right",
                    color: .indigo
                  )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
              }
              .tint(.primary)
              .contentShape(.rect)
              .buttonStyle(
                FluidZoomTransitionStyle(
                  id: "tripsSheet", namespace: namespace, shape: .rect, applyGlass: false))

              // Live Data Section
              if let data = vehicle.realtimeData {
                Group {
                  Button {
                    showingLiveCameraSheet.toggle()
                  } label: {
                    Label {
                      VStack(alignment: .leading) {
                        Text("Live Camera")
                      }
                    } icon: {
                      SettingsBoxView(
                        icon: "video.fill",
                        color: .green
                      )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                  }
                  .tint(.primary)
                  .contentShape(.rect)
                  .buttonStyle(
                    FluidZoomTransitionStyle(
                      id: "liveCameraSheet", namespace: namespace, shape: .rect, applyGlass: false))

                  Button {
                    showingAlertSheet.toggle()
                  } label: {
                    Label {
                      VStack(alignment: .leading) {
                        Text("Alert")
                      }
                    } icon: {
                      SettingsBoxView(
                        icon: "bell.fill",
                        color: .red
                      )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                  }
                  .tint(.primary)
                  .contentShape(.rect)
                  .buttonStyle(
                    FluidZoomTransitionStyle(
                      id: "alertSheet", namespace: namespace, shape: .rect, applyGlass: false)
                  )
                  .task {
                    await fetchBuzzerStatus()
                  }

                  Button {
                    showingLiveLocationSheet.toggle()
                  } label: {
                    Label {
                      VStack(alignment: .leading) {
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
                      }
                    } icon: {
                      SettingsBoxView(
                        icon: "location.fill",
                        color: .blue
                      )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                  }
                  .tint(.primary)
                  .contentShape(.rect)
                  .buttonStyle(
                    FluidZoomTransitionStyle(
                      id: "liveLocationSheet", namespace: namespace, shape: .rect, applyGlass: false
                    )
                  )
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

                  Button {
                    showingBluetoothSheet.toggle()
                  } label: {
                    Label {
                      HStack {
                        Text("Phone Connection")
                        Spacer()
                        if bluetooth.isConnected {
                          Text("Connected")
                            .font(.caption)
                            .foregroundStyle(.green)
                        } else if bluetooth.bleEnabled {
                          Text(bluetooth.statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                      }
                    } icon: {
                      SettingsBoxView(
                        icon: bluetooth.isConnected
                          ? "antenna.radiowaves.left.and.right"
                          : "antenna.radiowaves.left.and.right.slash",
                        color: bluetooth.isConnected ? .green : .gray
                      )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                  }
                  .tint(.primary)
                  .contentShape(.rect)
                  .buttonStyle(
                    FluidZoomTransitionStyle(
                      id: "bluetoothSheet", namespace: namespace, shape: .rect,
                      applyGlass: false))

                  Button {
                    showingVehicleSettingsSheet.toggle()
                  } label: {
                    Label {
                      Text("Vehicle Settings")
                    } icon: {
                      SettingsBoxView(icon: "car.fill", color: .blue)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                  }
                  .tint(.primary)
                  .contentShape(.rect)
                  .buttonStyle(
                    FluidZoomTransitionStyle(
                      id: "vehicleSettingsSheet", namespace: namespace, shape: .rect,
                      applyGlass: false))

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
            }
            .padding(.horizontal)
            .padding(.bottom, 50)
            .frame(maxWidth: .infinity)
          }
        }
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: CGFloat.self) { geo in
          geo.contentOffset.y
        } action: { _, newValue in
          scrollOffset = newValue
        }
      }
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button {
            Haptics.impact()
            showingVehicleAccessSheet.toggle()
          } label: {
            Image(systemName: "person.2.fill")
          }
          .containerShape(.capsule)
          .contentShape(.capsule)
          .buttonBorderShape(.capsule)
          .clipShape(Capsule())
          .buttonStyle(
            FluidZoomTransitionStyle(
              id: "accessSheet", namespace: namespace, shape: .capsule, applyGlass: false))
        }

        ToolbarItem(placement: .topBarTrailing) {
          Button {
            Haptics.impact()
            showingAccountSheet.toggle()
          } label: {
            ProfileToolbarImage()
          }
          .containerShape(.circle)
          .contentShape(.circle)
          .buttonBorderShape(.circle)
          .clipShape(Circle())
          .buttonStyle(
            FluidZoomTransitionStyle(
              id: "settingsSheet", namespace: namespace, shape: .circle, applyGlass: false))
        }
      }
    }
    .sheet(isPresented: $showingLiveCameraSheet) {
      VehicleLiveCameraView(vehicleId: vehicle.vehicle.id)
        .navigationTransition(.zoom(sourceID: "liveCameraSheet", in: namespace))
    }
    .sheet(isPresented: $showingTripsSheet) {
      HomeView(vehicle: vehicle)
        .navigationTransition(.zoom(sourceID: "tripsSheet", in: namespace))
    }
    .sheet(isPresented: $showingShazamHistorySheet) {
      ShazamHistoryView(vehicleId: vehicle.vehicle.id)
        .navigationTransition(.zoom(sourceID: "shazamHistorySheet", in: namespace))
    }
    .sheet(isPresented: $showingLiveLocationSheet) {
      Group {
        if let data = vehicle.realtimeData {
          VehicleLiveLocationView(
            vehicleData: data,
            vehicleName: vehicle.name,
            cachedRoute: cachedRoute,
            cachedStreetName: vehicleStreetName,
            cachedUserLocation: cachedUserCoordinate
          )
        } else {
          Text("Unable to load location.")
        }
      }
      .navigationTransition(.zoom(sourceID: "liveLocationSheet", in: namespace))
    }
    .sheet(isPresented: $showingVehicleSettingsSheet) {
      VehicleSettingsView(vehicle: vehicle.vehicle)
        .navigationTransition(.zoom(sourceID: "vehicleSettingsSheet", in: namespace))
    }
    .sheet(isPresented: $showingBluetoothSheet) {
      BluetoothConnectionView()
        .navigationTransition(.zoom(sourceID: "bluetoothSheet", in: namespace))
    }
    .sheet(isPresented: $showingAlertSheet) {
      VehicleAlertControlView(
        vehicleId: vehicle.vehicle.id,
        vehicleName: vehicle.name,
        initialBuzzerActive: cachedBuzzerActive,
        initialBuzzerType: cachedBuzzerType
      )
      .navigationTransition(.zoom(sourceID: "alertSheet", in: namespace))
    }
    .sheet(isPresented: $showingVehicleAccessSheet) {
      VehicleAccessSheet(vehicle: vehicle.vehicle)
        .navigationTransition(.zoom(sourceID: "accessSheet", in: namespace))
    }
    .sheet(isPresented: $showingFaceDetectionsSheet) {
      FaceDetectionsView(vehicle: vehicle.vehicle)
        .navigationTransition(.zoom(sourceID: "faceDetectionsSheet", in: namespace))
    }
    .sheet(isPresented: $showingAccountSheet) {
      V2AccountView()
        .navigationTransition(.zoom(sourceID: "settingsSheet", in: namespace))
    }
    .task(id: vehicle.vehicle.id) {
      // Periodic refresh of realtime data as fallback to realtime subscription
      await startRealtimeRefresh()
    }
    .onDisappear {
      realtimeRefreshTask?.cancel()
      realtimeRefreshTask = nil
    }
  }

  // MARK: - Realtime Refresh

  private func startRealtimeRefresh() async {
    realtimeRefreshTask?.cancel()
    realtimeRefreshTask = Task {
      while !Task.isCancelled {
        // Skip if BLE connected (BLE has its own polling)
        if !bluetooth.isConnected {
          // Periodically refresh realtime data from Supabase as fallback
          await supabase.loadVehicleRealtimeData(vehicleId: vehicle.vehicle.id)
        }
        try? await Task.sleep(for: .seconds(3))
      }
    }
  }

  // MARK: - Driver Alert Section

  @ViewBuilder
  private func driverAlertSection(data: VehicleRealtime) -> some View {
    // Speeding alert
    if data.isSpeeding {
      Label {
        VStack(alignment: .leading) {
          Text("Speeding!")
            .bold()
          Text("\(data.speedMph) MPH in a \(data.speedLimitMph) MPH zone")
            .font(.caption)
        }
      } icon: {
        SettingsBoxView(icon: "speedometer", color: .red)
      }
      .padding()
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.red.opacity(0.15), in: .rect(cornerRadius: 10))
    }

    // Phone distraction alert (highest priority)
    if data.isPhoneDetected == true
      || data.driverStatus.lowercased() == "distracted_phone"
    {
      Label {
        VStack(alignment: .leading) {
          Text("Phone Detected!")
            .bold()
          Text("Driver is looking at phone - dangerous!")
            .font(.caption)
        }
      } icon: {
        SettingsBoxView(icon: "iphone.gen3.radiowaves.left.and.right", color: .red)
      }
      .padding()
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.red.opacity(0.15), in: .rect(cornerRadius: 10))
    }
    // Drinking alert
    else if data.isDrinkingDetected == true
      || data.driverStatus.lowercased() == "distracted_drinking"
    {
      Label {
        VStack(alignment: .leading) {
          Text("Drinking Detected")
            .bold()
          Text("Driver is drinking - stay focused")
            .font(.caption)
        }
      } icon: {
        SettingsBoxView(icon: "cup.and.saucer.fill", color: .orange)
      }
      .padding()
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.orange.opacity(0.1), in: .rect(cornerRadius: 10))
    }
    // Impaired alert
    else if data.intoxicationScore >= 4
      || data.driverStatus.lowercased() == "impaired"
    {
      Label {
        VStack(alignment: .leading) {
          Text("Driver May Be Impaired")
            .bold()
          Text("Intoxication score: \(data.intoxicationScore)/6")
            .font(.caption)
        }
      } icon: {
        SettingsBoxView(icon: "exclamationmark.triangle.fill", color: .red)
      }
      .padding()
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.red.opacity(0.1), in: .rect(cornerRadius: 10))
    }
    // Drowsy alert
    else if data.intoxicationScore >= 2 || data.driverStatus.lowercased() == "drowsy" {
      Label {
        VStack(alignment: .leading) {
          Text("Driver May Be Drowsy")
            .bold()
          Text("Consider taking a break")
            .font(.caption)
        }
      } icon: {
        SettingsBoxView(icon: "moon.fill", color: .orange)
      }
      .padding()
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.orange.opacity(0.1), in: .rect(cornerRadius: 10))
    }
  }

  // MARK: - Helper Methods

  private func intoxicationColor(for score: Int) -> Color {
    if score >= 4 { return .red }
    if score >= 2 { return .orange }
    return .green
  }

  private func fetchBuzzerStatus() async {
    // When BLE is connected, buzzer state is local — skip Supabase fetch
    guard !bluetooth.isConnected else { return }

    do {
      let response: [VehicleRealtime] = try await supabase.client
        .from("vehicle_realtime")
        .select()
        .eq("vehicle_id", value: vehicle.vehicle.id)
        .execute()
        .value

      if let data = response.first {
        cachedBuzzerActive = data.buzzerActive
        cachedBuzzerType = data.buzzerType
      }
    } catch {
      // Keep cached values as nil, will fetch fresh in VehicleAlertControlView
    }
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

// MARK: - Profile Toolbar Image

struct ProfileToolbarImage: View {
  var body: some View {
    if let avatarPath = supabase.userProfile?.avatarPath,
      let avatarURL = supabase.getUserAvatarURL(path: avatarPath)
    {
      AsyncImage(url: avatarURL) { phase in
        switch phase {
        case .success(let image):
          image
            .resizable()
            .scaledToFill()
            .frame(width: 30, height: 30)
            .clipShape(.circle)
        default:
          defaultImage
        }
      }
    } else {
      defaultImage
    }
  }

  private var defaultImage: some View {
    Circle()
      .fill(.gray.gradient)
      .frame(width: 30, height: 30)
      .overlay {
        Image(systemName: "person.fill")
          .font(.caption)
          .foregroundStyle(.white)
      }
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
  @Environment(\.dismiss) private var dismiss

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
    NavigationStack {
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
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 32))
                .padding()
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
            if let userCoord = newLocation, let vehicleCoord = vehicleCoordinate,
              !hasCalculatedRoute
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
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          CloseButton {
            dismiss()
          }
        }
      }
    }
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

// MARK: - Vehicle Alert Control View

struct VehicleAlertControlView: View {
  @Environment(\.dismiss) private var dismiss

  let vehicleId: String
  let vehicleName: String
  let initialBuzzerActive: Bool?
  let initialBuzzerType: String?

  @State private var buzzerActive = false
  @State private var buzzerType: BuzzerType = .alert
  @State private var isLoading = false
  @State private var errorMessage: String?
  @State private var policeRotation: Double = 0
  @State private var policeLightsOn = true

  // Custom equalizer parameters
  @State private var customFrequency: Double = 800
  @State private var customOnDuration: Double = 0.5
  @State private var customOffDuration: Double = 0.5
  @State private var customDutyCycle: Double = 50
  @State private var isCustomExpanded = false

  enum BuzzerType: String, CaseIterable {
    case alert = "alert"
    case emergency = "emergency"
    case warning = "warning"
    case custom = "custom"

    var icon: String {
      switch self {
      case .alert: return "bell.fill"
      case .emergency: return "exclamationmark.triangle.fill"
      case .warning: return "exclamationmark.circle.fill"
      case .custom: return "slider.horizontal.3"
      }
    }

    var color: Color {
      switch self {
      case .alert: return .orange
      case .emergency: return .red
      case .warning: return .yellow
      case .custom: return .purple
      }
    }

    var displayName: String {
      rawValue.capitalized
    }

    /// Cases shown in the segmented picker (excludes custom — it has its own UI)
    static var pickerCases: [BuzzerType] {
      [.alert, .emergency, .warning]
    }
  }

  var body: some View {
    NavigationStack {
      List {
        Section {
          VStack(spacing: 20) {
            // Buzzer icon with animation
            ZStack {
              // Police lights - revolving around the circle
              if buzzerActive {
                ForEach(0..<8, id: \.self) { index in
                  Circle()
                    .fill(index % 2 == 0 ? Color.red : Color.blue)
                    .frame(width: 14, height: 14)
                    .opacity(policeLightsOn ? 1.0 : 0.3)
                    .offset(y: -80)
                    .rotationEffect(.degrees(Double(index) * 45 + policeRotation))
                    .shadow(
                      color: (index % 2 == 0 ? Color.red : Color.blue).opacity(0.8),
                      radius: policeLightsOn ? 8 : 2
                    )
                }
              }

              // Pulsing background circle with shadow
              if buzzerActive {
                Circle()
                  .fill(buzzerType.color.opacity(0.2))
                  .frame(width: 120, height: 120)
                  .shadow(color: buzzerType.color.opacity(0.6), radius: 20)
                  .scaleEffect(buzzerActive ? 1.2 : 1.0)
                  .animation(
                    .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                    value: buzzerActive
                  )
              }

              Image(systemName: buzzerType.icon)
                .font(.system(size: 60))
                .foregroundStyle(buzzerActive ? buzzerType.color : .gray)
                .symbolEffect(.bounce, value: buzzerActive)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .task(id: buzzerActive) {
              // Continuous haptics while buzzer is active
              guard buzzerActive else { return }
              while buzzerActive {
                Haptics.impact()
                try? await Task.sleep(for: .seconds(2.5))
              }
            }
            .task(id: buzzerActive) {
              // Revolving police lights animation
              guard buzzerActive else { return }
              while buzzerActive {
                withAnimation(.linear(duration: 1.2)) {
                  policeRotation += 360
                }
                try? await Task.sleep(for: .seconds(1.2))
              }
            }
            .task(id: buzzerActive) {
              // Flashing police lights
              guard buzzerActive else { return }
              while buzzerActive {
                withAnimation(.easeInOut(duration: 0.4)) {
                  policeLightsOn.toggle()
                }
                try? await Task.sleep(for: .seconds(0.4))
              }
            }

            // Status text
            Text(buzzerActive ? "Buzzer Active" : "Buzzer Inactive")
              .font(.title2)
              .bold()
              .foregroundStyle(buzzerActive ? buzzerType.color : .secondary)

            if buzzerActive {
              Text("The vehicle buzzer is currently sounding")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }
          }
          .frame(maxWidth: .infinity)
          .listRowBackground(Color.clear)
        }

        // Buzzer type picker
        if !buzzerActive {
          Section {
            Picker("Type", selection: $buzzerType) {
              ForEach(BuzzerType.pickerCases, id: \.self) { type in
                Text(type.displayName)
                  .tag(type)
              }
            }
            .pickerStyle(.segmented)
          } header: {
            Text("Buzzer Type")
          } footer: {
            Text(buzzerTypeDescription)
          }

          // Custom Equalizer
          Section {
            DisclosureGroup("Custom Equalizer", isExpanded: $isCustomExpanded) {
              VStack(spacing: 20) {
                // Equalizer bars
                HStack(alignment: .bottom, spacing: 12) {
                  EqualizerBar(
                    label: "FREQ",
                    value: $customFrequency,
                    range: 100...5000,
                    unit: "Hz",
                    displayValue: "\(Int(customFrequency))",
                    color: frequencyColor
                  )

                  EqualizerBar(
                    label: "ON",
                    value: $customOnDuration,
                    range: 0.05...2.0,
                    unit: "s",
                    displayValue: String(format: "%.2f", customOnDuration),
                    color: .green
                  )

                  EqualizerBar(
                    label: "OFF",
                    value: $customOffDuration,
                    range: 0.05...2.0,
                    unit: "s",
                    displayValue: String(format: "%.2f", customOffDuration),
                    color: .blue
                  )

                  EqualizerBar(
                    label: "DUTY",
                    value: $customDutyCycle,
                    range: 10...100,
                    unit: "%",
                    displayValue: "\(Int(customDutyCycle))",
                    color: .purple
                  )
                }
                .frame(height: 200)
                .padding(.vertical, 8)

                // Presets
                ScrollView(.horizontal) {
                  HStack(spacing: 8) {
                    ForEach(BuzzerPreset.allCases, id: \.self) { preset in
                      Button {
                        withAnimation(.snappy) {
                          customFrequency = Double(preset.frequency)
                          customOnDuration = preset.onDuration
                          customOffDuration = preset.offDuration
                          customDutyCycle = Double(preset.dutyCycle)
                        }
                        Haptics.impact()
                      } label: {
                        Text(preset.name)
                          .font(.caption)
                          .bold()
                          .padding(.horizontal, 12)
                          .padding(.vertical, 6)
                          .background(preset.color.opacity(0.2))
                          .foregroundStyle(preset.color)
                          .clipShape(.capsule)
                      }
                    }
                  }
                }
                .scrollIndicators(.hidden)

                // Play custom button
                Button {
                  Haptics.impact()
                  buzzerType = .custom
                  Task { await toggleBuzzer() }
                } label: {
                  HStack {
                    Image(systemName: "play.fill")
                    Text("Play Custom Tone")
                      .bold()
                  }
                  .frame(maxWidth: .infinity)
                  .padding(.vertical, 10)
                  .foregroundStyle(.white)
                  .background(frequencyColor.gradient, in: .rect(cornerRadius: 32))
                }
                .buttonStyle(.plain)
              }
            }
            .tint(frequencyColor)
          } header: {
            Text("Sound Design")
          } footer: {
            Text(
              "Drag the bars to customize frequency, timing, and intensity. "
                + "The buzzer hardware resonates best around 4000Hz."
            )
          }
        }

        // Control button
        Section {
          Button {
            Haptics.impact()
            Task {
              await toggleBuzzer()
            }
          } label: {
            HStack {
              Spacer()
              if isLoading {
                ProgressView()
                  .tint(.white)
              } else {
                Image(systemName: buzzerActive ? "stop.fill" : "play.fill")
                Text(buzzerActive ? "Stop Buzzer" : "Start Buzzer")
                  .bold()
              }
              Spacer()
            }
            .padding()
            .foregroundStyle(.white)
          }
          .listRowBackground(buzzerActive ? Color.red : buzzerType.color)
          .disabled(isLoading)
        }

        // Error message
        if let errorMessage {
          Section {
            Label {
              Text(errorMessage)
                .foregroundStyle(.red)
            } icon: {
              Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            }
          }
        }

        // Info section
        Section {
          Label {
            VStack(alignment: .leading) {
              Text("Remote Control")
                .font(.headline)
              Text(
                "This will activate the buzzer on \(vehicleName). The buzzer will sound continuously until stopped."
              )
              .font(.caption)
              .foregroundStyle(.secondary)
            }
          } icon: {
            Image(systemName: "info.circle.fill")
              .foregroundStyle(.blue)
          }
        }
      }
      .navigationTitle("Alert Control")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          CloseButton {
            dismiss()
          }
        }
      }
      .task {
        // Use cached values if available, otherwise fetch fresh
        if let initialActive = initialBuzzerActive,
          let initialType = initialBuzzerType,
          let type = BuzzerType(rawValue: initialType)
        {
          buzzerActive = initialActive
          buzzerType = type
        } else {
          await fetchBuzzerState()
        }
      }
    }
  }

  private var frequencyColor: Color {
    let normalized = (customFrequency - 100) / 4900
    if normalized < 0.33 { return .blue }
    if normalized < 0.66 { return .purple }
    return .red
  }

  private var buzzerTypeDescription: String {
    switch buzzerType {
    case .alert:
      return "Moderate urgency - 800Hz, 0.5s pattern"
    case .emergency:
      return "High urgency - 1200Hz, fast 0.3s pattern"
    case .warning:
      return "Low urgency - 600Hz, slow 0.7s pattern"
    case .custom:
      return
        "Custom - \(Int(customFrequency))Hz, \(String(format: "%.2f", customOnDuration))s pattern"
    }
  }

  private func fetchBuzzerState() async {
    // When BLE is connected, buzzer state is managed locally — skip Supabase
    guard !bluetooth.isConnected else { return }

    do {
      let response: [VehicleRealtime] = try await supabase.client
        .from("vehicle_realtime")
        .select()
        .eq("vehicle_id", value: vehicleId)
        .execute()
        .value

      if let data = response.first {
        buzzerActive = data.buzzerActive ?? false
        if let typeString = data.buzzerType,
          let type = BuzzerType(rawValue: typeString)
        {
          buzzerType = type
        }
      }
    } catch {
      errorMessage = "Failed to fetch buzzer state: \(error.localizedDescription)"
    }
  }

  private func toggleBuzzer() async {
    isLoading = true
    errorMessage = nil

    // Use BLE direct command when connected
    if bluetooth.isConnected {
      if buzzerActive {
        bluetooth.writeBuzzerCommand(active: false)
        buzzerActive = false
        Haptics.notification(.success)
      } else if buzzerType == .custom {
        bluetooth.writeCustomBuzzerCommand(
          active: true,
          frequency: Int(customFrequency),
          onDuration: customOnDuration,
          offDuration: customOffDuration,
          dutyCycle: Int(customDutyCycle)
        )
        buzzerActive = true
        Haptics.notification(.warning)
      } else {
        bluetooth.writeBuzzerCommand(active: true, type: buzzerType.rawValue)
        buzzerActive = true
        Haptics.notification(.warning)
      }
      isLoading = false
      return
    }

    // Fall back to Supabase RPC
    do {
      if buzzerActive {
        struct DeactivateResponse: Codable {
          let success: Bool
        }

        let _: DeactivateResponse = try await supabase.client.rpc(
          "deactivate_vehicle_buzzer",
          params: ["p_vehicle_id": vehicleId]
        ).execute().value

        buzzerActive = false
        Haptics.notification(.success)
      } else {
        struct ActivateResponse: Codable {
          let success: Bool
        }

        let _: ActivateResponse = try await supabase.client.rpc(
          "activate_vehicle_buzzer",
          params: [
            "p_vehicle_id": vehicleId,
            "p_buzzer_type": buzzerType.rawValue,
          ]
        ).execute().value

        buzzerActive = true
        Haptics.notification(.warning)
      }
    } catch {
      errorMessage =
        "Failed to \(buzzerActive ? "stop" : "start") buzzer: \(error.localizedDescription)"
      Haptics.notification(.error)
    }

    isLoading = false
  }
}

// MARK: - Equalizer Bar

private struct EqualizerBar: View {
  let label: String
  @Binding var value: Double
  let range: ClosedRange<Double>
  let unit: String
  let displayValue: String
  let color: Color

  @State private var isDragging = false

  private var normalized: Double {
    (value - range.lowerBound) / (range.upperBound - range.lowerBound)
  }

  var body: some View {
    VStack(spacing: 6) {
      // Value label
      Text(displayValue)
        .font(.system(.caption2, design: .monospaced, weight: .bold))
        .foregroundStyle(isDragging ? color : .primary)

      Text(unit)
        .font(.system(size: 9))
        .foregroundStyle(.secondary)

      // Vertical bar
      GeometryReader { geo in
        let barHeight = geo.size.height
        let fillHeight = barHeight * normalized

        ZStack(alignment: .bottom) {
          // Background track
          RoundedRectangle(cornerRadius: 6)
            .fill(Color(.tertiarySystemFill))

          // Filled portion
          RoundedRectangle(cornerRadius: 6)
            .fill(
              LinearGradient(
                colors: [color.opacity(0.6), color],
                startPoint: .bottom,
                endPoint: .top
              )
            )
            .frame(height: fillHeight)

          // Glow effect at the top of the bar
          RoundedRectangle(cornerRadius: 6)
            .fill(color)
            .frame(height: max(4, fillHeight))
            .blur(radius: isDragging ? 8 : 4)
            .opacity(isDragging ? 0.8 : 0.4)
            .frame(height: fillHeight, alignment: .top)
            .clipped()

          // Knob indicator
          Circle()
            .fill(.white)
            .shadow(color: color.opacity(0.6), radius: isDragging ? 6 : 3)
            .frame(width: isDragging ? 20 : 14, height: isDragging ? 20 : 14)
            .offset(y: -(fillHeight - 7))
        }
        .clipShape(.rect(cornerRadius: 6))
        .gesture(
          DragGesture(minimumDistance: 0)
            .onChanged { drag in
              isDragging = true
              let fraction = 1.0 - (drag.location.y / barHeight)
              let clamped = min(max(fraction, 0), 1)
              value = range.lowerBound + clamped * (range.upperBound - range.lowerBound)
            }
            .onEnded { _ in
              isDragging = false
              Haptics.impact()
            }
        )
      }
      .frame(maxWidth: .infinity)

      // Label
      Text(label)
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.secondary)
    }
  }
}

// MARK: - Buzzer Presets

private enum BuzzerPreset: CaseIterable {
  case siren
  case heartbeat
  case alarm
  case gentle
  case rapid

  var name: String {
    switch self {
    case .siren: "Siren"
    case .heartbeat: "Heartbeat"
    case .alarm: "Alarm"
    case .gentle: "Gentle"
    case .rapid: "Rapid"
    }
  }

  var frequency: Int {
    switch self {
    case .siren: 1500
    case .heartbeat: 400
    case .alarm: 2500
    case .gentle: 300
    case .rapid: 1000
    }
  }

  var onDuration: Double {
    switch self {
    case .siren: 0.3
    case .heartbeat: 0.15
    case .alarm: 0.1
    case .gentle: 1.0
    case .rapid: 0.08
    }
  }

  var offDuration: Double {
    switch self {
    case .siren: 0.3
    case .heartbeat: 0.6
    case .alarm: 0.1
    case .gentle: 1.0
    case .rapid: 0.08
    }
  }

  var dutyCycle: Int {
    switch self {
    case .siren: 60
    case .heartbeat: 40
    case .alarm: 80
    case .gentle: 30
    case .rapid: 50
    }
  }

  var color: Color {
    switch self {
    case .siren: .red
    case .heartbeat: .pink
    case .alarm: .orange
    case .gentle: .mint
    case .rapid: .indigo
    }
  }
}

#Preview("Alert Control") {
  NavigationStack {
    VehicleAlertControlView(
      vehicleId: "test-vehicle",
      vehicleName: "Test Vehicle",
      initialBuzzerActive: nil,
      initialBuzzerType: nil
    )
  }
}

// MARK: - Live Camera View

struct VehicleLiveCameraView: View {
  @Environment(\.dismiss) private var dismiss

  let vehicleId: String

  @State private var currentFrame: UIImage?
  @State private var isStreaming = false
  @State private var error: String?
  @State private var pollTask: Task<Void, Never>?
  @State private var fallbackPollTask: Task<Void, Never>?
  @State private var isFetchingFrame = false
  @State private var consecutiveErrors = 0
  @State private var lastFrameDate = Date.now
  @State private var vehicleData: VehicleRealtime?
  @State private var dataTask: Task<Void, Never>?
  @State private var httpCameraFrame: UIImage?
  @State private var httpPollTask: Task<Void, Never>?

  private var activeFrame: UIImage? {
    if bluetooth.isConnected {
      return httpCameraFrame
    }
    return currentFrame
  }

  private var isBLE: Bool { bluetooth.isConnected }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        // Camera feed
        ZStack {
          if let frame = activeFrame {
            Image(uiImage: frame)
              .resizable()
              .aspectRatio(contentMode: .fit)
              .overlay(alignment: .topLeading) {
                if isBLE {
                  Text("BLE")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.8))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                    .padding(8)
                }
              }
          } else if isStreaming {
            ProgressView(isBLE ? "Waiting for camera feed..." : "Connecting to camera...")
              .controlSize(.extraLarge)
          } else if let error {
            ContentUnavailableView {
              Label("Stream Unavailable", systemImage: "video.slash")
            } description: {
              Text(error)
            } actions: {
              Button("Retry") {
                self.error = nil
                startPolling()
              }
              .buttonStyle(.borderedProminent)
              .possibleGlassEffect(.accentColor, in: .capsule)
            }
          }
        }

        // Vehicle stats — always visible
        if let data = vehicleData {
          ScrollView {
            VStack(spacing: 12) {
              // Speed row
              HStack {
                Label("Speed", systemImage: "speedometer")
                Spacer()
                Text(
                  "\(Text("\(data.speedMph)").foregroundStyle(.primary))/\(data.speedLimitMph)MPH"
                )
                .bold()
                .contentTransition(.numericText(value: 0))
                .foregroundStyle(
                  data.isSpeeding ? .red : .secondary
                )
              }

              Divider()

              // Heading
              HStack {
                Label("Heading", systemImage: "location.north.fill")
                Spacer()
                HStack(spacing: 4) {
                  Image(systemName: "location.north.fill")
                    .rotationEffect(.degrees(Double(data.headingDegrees)))
                    .foregroundStyle(.blue)
                  Text("\(data.headingDegrees)° \(data.compassDirection)")
                }
              }

              Divider()

              // Status (moving/parked)
              HStack {
                Label("Status", systemImage: "location.circle.fill")
                Spacer()
                HStack(spacing: 6) {
                  Circle()
                    .fill(data.isMoving ? .green : .gray)
                    .frame(width: 8, height: 8)
                  Text(data.isMoving ? "Moving" : "Parked")
                }
              }

              Divider()

              // Driver status
              HStack {
                Label("Driver Status", systemImage: "person.fill")
                Spacer()
                DriverStatusBadge(status: data.driverStatus)
              }

              Divider()

              // Risk score
              HStack {
                Label("Risk Score", systemImage: "exclamationmark.triangle.fill")
                Spacer()
                Text("\(data.intoxicationScore)/6")
                  .foregroundStyle(intoxicationColor(for: data.intoxicationScore))
                  .bold()
              }

              Divider()

              // GPS satellites
              if let satellites = data.satellites {
                HStack {
                  Label("GPS Satellites", systemImage: "location.fill")
                  Spacer()
                  HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                      .foregroundStyle(satellites > 0 ? .green : .gray)
                    Text("\(satellites)")
                      .foregroundStyle(satellites > 0 ? .primary : .secondary)
                  }
                }

                Divider()
              }

              // Accelerometer / gyroscope
              if let accMag = data.accMag, let gyroMag = data.gyroMag {
                Divider()

                HStack {
                  Label("Accelerometer", systemImage: "waveform.path.ecg")
                  Spacer()
                  Text(accMag, format: .number.precision(.fractionLength(2)))
                    .bold()
                    + Text(" g")
                    .foregroundStyle(.secondary)
                }

                Divider()

                HStack {
                  Label("Gyroscope", systemImage: "gyroscope")
                  Spacer()
                  Text(gyroMag, format: .number.precision(.fractionLength(1)))
                    .bold()
                    + Text(" °/s")
                    .foregroundStyle(.secondary)
                }
              }

              // Crash alert
              if data.crashDetected == true {
                Divider()

                HStack(spacing: 12) {
                  Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.title2)
                  VStack(alignment: .leading, spacing: 2) {
                    Text("Crash Detected")
                      .bold()
                      .foregroundStyle(.red)
                    if let severity = data.crashSeverity {
                      Text(severity.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    if let peakG = data.crashPeakG {
                      Text("Peak: \(peakG, format: .number.precision(.fractionLength(2))) g")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                  }
                  Spacer()
                }
                .padding()
                .background(Color.red.opacity(0.1), in: .rect(cornerRadius: 10))
              }

              Divider()

              // Last updated
              HStack {
                Label("Last Updated", systemImage: "clock.fill")
                Spacer()
                Text(data.updatedAt, style: .relative)
                  .foregroundStyle(.secondary)
                  .font(.caption)
              }
            }
            .padding()
            .font(.subheadline)
          }
          .background(Color(.systemBackground))
        }
      }
      .navigationTitle("Live Camera")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          CloseButton {
            dismiss()
          }
        }

        ToolbarItem(placement: .topBarTrailing) {
          Circle()
            .fill(activeFrame != nil ? .green : (isStreaming ? .yellow : .red))
            .frame(width: 15, height: 15)
        }
      }
      .onAppear {
        startPolling()
        startFetchingData()
      }
      .onDisappear {
        stopPolling()
        stopFetchingData()
      }
    }
  }

  private func startPolling() {
    stopPolling()
    // BLE: poll HTTP camera server on the Pi's local network
    if bluetooth.isConnected {
      isStreaming = true
      httpPollTask = Task {
        while !Task.isCancelled {
          if let camURL = bluetooth.latestRealtime?.cam,
            let url = URL(string: camURL)
          {
            do {
              let (data, _) = try await URLSession.shared.data(from: url)
              if let image = UIImage(data: data) {
                httpCameraFrame = image
                lastFrameDate = .now
                consecutiveErrors = 0
              }
            } catch {
              consecutiveErrors += 1
              if consecutiveErrors > 15 && httpCameraFrame == nil {
                self.error = "Cannot reach camera server on Pi."
                isStreaming = false
                return
              }
            }
          }
          try? await Task.sleep(for: .milliseconds(200))
        }
      }
      return
    }
    isStreaming = true
    consecutiveErrors = 0

    // Primary: broadcast-driven fetches with auto-reconnect
    pollTask = Task {
      while !Task.isCancelled {
        let channel = await supabase.client.realtimeV2.channel("live-frames:\(vehicleId)")
        let broadcastStream = await channel.broadcast(event: "new_frame")
        await channel.subscribe()

        await fetchLatestFrame()

        for await _ in broadcastStream {
          guard !Task.isCancelled else { break }
          await fetchLatestFrame()
        }

        await supabase.client.realtimeV2.removeChannel(channel)

        // Broadcast stream ended (channel disconnected) — reconnect after a brief pause
        guard !Task.isCancelled else { break }
        try? await Task.sleep(for: .seconds(1))
      }
    }

    // Fallback: periodic polling in case broadcast stalls silently
    fallbackPollTask = Task {
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(2))
        guard !Task.isCancelled else { break }
        // Only poll if no frame arrived recently
        if Date.now.timeIntervalSince(lastFrameDate) > 1.5 {
          await fetchLatestFrame()
        }
      }
    }
  }

  private func fetchLatestFrame() async {
    // Skip if already fetching — prevents queue buildup and lag
    guard !isFetchingFrame else { return }
    isFetchingFrame = true
    defer { isFetchingFrame = false }

    do {
      let data = try await supabase.client.storage
        .from("live-frames")
        .download(path: "\(vehicleId)/latest.jpg")

      if let image = UIImage(data: data) {
        currentFrame = image
        consecutiveErrors = 0
        lastFrameDate = .now
      }
    } catch {
      consecutiveErrors += 1
      if consecutiveErrors > 15 && currentFrame == nil {
        self.error = "Make sure ENABLE_STREAM=true on the vehicle."
        isStreaming = false
      }
    }
  }

  private func stopPolling() {
    pollTask?.cancel()
    pollTask = nil
    fallbackPollTask?.cancel()
    fallbackPollTask = nil
    httpPollTask?.cancel()
    httpPollTask = nil
    isStreaming = false
  }

  private func startFetchingData() {
    stopFetchingData()

    dataTask = Task {
      while !Task.isCancelled {
        if bluetooth.isConnected, let rt = bluetooth.latestRealtime {
          // Use BLE realtime data directly
          vehicleData = rt.toVehicleRealtime(vehicleId: vehicleId)
        } else {
          do {
            let response: [VehicleRealtime] = try await supabase.client
              .from("vehicle_realtime")
              .select()
              .eq("vehicle_id", value: vehicleId)
              .execute()
              .value

            if let data = response.first {
              vehicleData = data
            }
          } catch {
            // Silently continue if fetch fails
          }
        }

        try? await Task.sleep(for: .milliseconds(500))
      }
    }
  }

  private func stopFetchingData() {
    dataTask?.cancel()
    dataTask = nil
  }

  private func intoxicationColor(for score: Int) -> Color {
    if score >= 4 { return .red }
    if score >= 2 { return .orange }
    return .green
  }
}

#Preview("Live Camera") {
  NavigationStack {
    VehicleLiveCameraView(vehicleId: "test-vehicle")
  }
}
