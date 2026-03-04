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

  @State private var showingUnidentifiedFacesSheet = false
  @State private var showingFaceDetectionsSheet = false
  @State private var showingAlertSheet = false

  @State private var showingLiveCameraSheet = false
  @State private var showingTripsSheet = false
  @State private var showingShazamHistorySheet = false
  @State private var showingLiveLocationSheet = false
  @State private var showingVehicleSettingsSheet = false

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

  // Currently playing song
  @State private var currentSong: String? = "Why'd You Only Call Me When You're High?"
  @State private var currentArtist: String? = "Arctic Monkeys"

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
              // Currently playing song
              if let currentSong {
                VStack(spacing: 0) {
                  HStack {
                    VStack(alignment: .leading) {
                      MarqueeView {
                        Text(currentSong)
                          .font(.subheadline)
                          .lineLimit(1)
                      }
                      if let currentArtist {
                        MarqueeView {
                          Text(currentArtist)
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

                  HStack(spacing: 4) {
                    HStack(spacing: 0) {
                      Button("Previous", systemImage: "backward.end.fill") {
                        Haptics.impact()
                      }
                      .frame(maxWidth: .infinity)
                      Button("Pause", systemImage: "pause.fill") {
                        Haptics.impact()
                      }
                      .frame(maxWidth: .infinity)
                      Button("Next", systemImage: "forward.end.fill") {
                        Haptics.impact()
                      }
                      .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, 12)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(.rect(cornerRadius: 8))

                    HStack(spacing: 0) {
                      Button("Previous Source", systemImage: "chevron.left") {
                        Haptics.impact()
                      }
                      .frame(maxWidth: .infinity)
                      Button("Volume", systemImage: "speaker.wave.2.fill") {
                        Haptics.impact()
                      }
                      .frame(maxWidth: .infinity)
                      Button("Next Source", systemImage: "chevron.right") {
                        Haptics.impact()
                      }
                      .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, 12)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(.rect(cornerRadius: 8))
                  }
                  .labelStyle(.iconOnly)
                  .buttonStyle(.plain)
                  .foregroundStyle(.secondary)
                  .padding(.horizontal, 8)
                  .padding(.bottom, 8)

                  AaronButtonView(text: "All Songs") {
                    showingShazamHistorySheet.toggle()
                  }
                  .contentShape(.capsule)
                  .buttonStyle(
                    FluidZoomTransitionStyle(
                      id: "shazamHistorySheet", namespace: namespace, shape: .capsule,
                      applyGlass: false)
                  )
                  .padding()
                  .onTapGesture {
                    showingShazamHistorySheet.toggle()
                  }
                }
                .background(Color(.secondarySystemBackground))
                .clipShape(.rect(cornerRadius: 12))
              }

              // Driver alert
              if let data = vehicle.realtimeData {
                driverAlertSection(data: data)
              }

              // Face Detection Section
              if vehicle.unidentifiedFacesCount > 0 {
                Button {
                  showingUnidentifiedFacesSheet.toggle()
                } label: {
                  Label {
                    VStack(alignment: .leading) {
                      Text(
                        "\(vehicle.unidentifiedFacesCount) Unidentified Face\(vehicle.unidentifiedFacesCount == 1 ? "" : "s")"
                      )
                    }
                  } icon: {
                    SettingsBoxView(
                      icon: "face.smiling",
                      color: .orange
                    )
                  }
                }
                .tint(.primary)
                .contentShape(.rect)
                .buttonStyle(
                  FluidZoomTransitionStyle(
                    id: "unidentifiedFacesSheet", namespace: namespace, shape: .rect,
                    applyGlass: false))
              }

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
                    showingVehicleSettingsSheet.toggle()
                  } label: {
                    Label {
                      Text("Vehicle Settings")
                    } icon: {
                      SettingsBoxView(icon: "car.fill", color: .blue)
                    }
                  }
                  .tint(.primary)
                  .contentShape(.rect)
                  .buttonStyle(
                    FluidZoomTransitionStyle(
                      id: "vehicleSettingsSheet", namespace: namespace, shape: .rect,
                      applyGlass: false))

                  LabeledContent("Speed") {
                    HStack {
                      Text(
                        "\(Text("\(data.speedMph)").font(.title2).foregroundStyle(.primary))/\(data.speedLimitMph)MPH"
                      )
                      .contentTransition(.numericText(value: 0))
                      .foregroundStyle(
                        data.isSpeeding ? .red : .secondary
                      )

                      if data.isSpeeding {
                        Image(
                          systemName: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.red)
                      }
                    }
                  }

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
            .padding([.horizontal, .bottom])
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
          .buttonStyle(
            FluidZoomTransitionStyle(id: "accessSheet", namespace: namespace, shape: .capsule))
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
          .buttonStyle(
            FluidZoomTransitionStyle(id: "settingsSheet", namespace: namespace, shape: .circle))
        }
      }
      //      .dynamicIslandToast(isPresented: .constant(vehicleStreetName != nil), toast: .init(symbol: "xmark.circle.fill", symbolForegroundStyle: (.green, .white), title: "Distracted Driving", message: "Driver was alerted"))
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
    .sheet(isPresented: $showingUnidentifiedFacesSheet) {
      UnidentifiedFacesView(vehicle: vehicle.vehicle)
        .navigationTransition(.zoom(sourceID: "unidentifiedFacesSheet", in: namespace))
    }
    .sheet(isPresented: $showingAccountSheet) {
      V2AccountView()
        .navigationTransition(.zoom(sourceID: "settingsSheet", in: namespace))
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

  enum BuzzerType: String, CaseIterable {
    case alert = "alert"
    case emergency = "emergency"
    case warning = "warning"

    var icon: String {
      switch self {
      case .alert: return "bell.fill"
      case .emergency: return "exclamationmark.triangle.fill"
      case .warning: return "exclamationmark.circle.fill"
      }
    }

    var color: Color {
      switch self {
      case .alert: return .orange
      case .emergency: return .red
      case .warning: return .yellow
      }
    }

    var displayName: String {
      rawValue.capitalized
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
              ForEach(BuzzerType.allCases, id: \.self) { type in
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

  private var buzzerTypeDescription: String {
    switch buzzerType {
    case .alert:
      return "Moderate urgency - 800Hz, 0.5s pattern"
    case .emergency:
      return "High urgency - 1200Hz, fast 0.3s pattern"
    case .warning:
      return "Low urgency - 600Hz, slow 0.7s pattern"
    }
  }

  private func fetchBuzzerState() async {
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

    do {
      if buzzerActive {
        // Deactivate buzzer
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
        // Activate buzzer
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

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        // Camera feed
        ZStack {
          if let frame = currentFrame {
            Image(uiImage: frame)
              .resizable()
              .aspectRatio(contentMode: .fit)
          } else if isStreaming {
            ProgressView("Connecting to camera...")
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

        // Vehicle stats
        if currentFrame != nil, let data = vehicleData {
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
            .fill(currentFrame != nil ? .green : (isStreaming ? .yellow : .red))
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
    isStreaming = false
  }

  private func startFetchingData() {
    stopFetchingData()

    dataTask = Task {
      while !Task.isCancelled {
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
