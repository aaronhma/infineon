//
//  VehicleView.swift
//  InfineonProject
//
//  Created by Aaron Ma on 1/12/26.
//

import AaronUI
import SwiftUI

struct VehicleView: View {
  @Environment(\.supabaseService) private var supabaseService
  @State private var selectedVehicleId: String?
  @State private var showingVehiclePicker = false
  @State private var showingJoinVehicle = false
  @State private var showingUnidentifiedFaces = false
  @State private var showingFaceDetections = false
  @State private var unidentifiedCount = 0

  private var currentVehicle: Vehicle? {
    if let selectedId = selectedVehicleId {
      return supabaseService.vehicles.first { $0.id == selectedId }
    }
    return supabaseService.vehicles.first
  }

  private var realtimeData: VehicleRealtime? {
    guard let vehicle = currentVehicle else { return nil }
    return supabaseService.vehicleRealtimeData[vehicle.id]
  }

  var body: some View {
    NavigationStack {
      Group {
        if supabaseService.vehicles.isEmpty {
          noVehiclesView
        } else {
          List {
            // Vehicle image section
            Section {
              AnimatedVehicleView(
                isMoving: realtimeData?.isMoving ?? false,
                speed: realtimeData?.speedMph ?? 0
              )
              .frame(height: 200)
              .listRowBackground(Color.clear)
              .listRowInsets(EdgeInsets())
            }

            // Driver alert
            if let data = realtimeData {
              driverAlertSection(data: data)
            }

            // Face Detection Section
            Section {
              if unidentifiedCount > 0 {
                Button {
                  showingUnidentifiedFaces = true
                } label: {
                  Label {
                    VStack(alignment: .leading) {
                      Text(
                        "\(unidentifiedCount) Unidentified Face\(unidentifiedCount == 1 ? "" : "s")"
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

              Button {
                showingFaceDetections = true
              } label: {
                Label {
                  VStack(alignment: .leading) {
                    Text("Face Detections")
                    Text("View all driver snapshots")
                      .font(.caption)
                      .foregroundStyle(.secondary)
                  }
                } icon: {
                  Image(systemName: "person.crop.rectangle.stack.fill")
                    .foregroundStyle(.blue)
                }
              }
              .tint(.primary)
            } header: {
              Text("Driver Monitoring")
            }

            // Live Data Section
            if let data = realtimeData {
              Section("Live Data") {
                LabeledContent("Speed") {
                  HStack {
                    Text("\(data.speedMph) mph")
                      .foregroundStyle(data.isSpeeding ? .red : .primary)
                    if data.isSpeeding {
                      Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    }
                  }
                }

                LabeledContent("Speed Limit", value: "\(data.speedLimitMph) mph")

                LabeledContent("Heading") {
                  HStack {
                    Image(systemName: "location.north.fill")
                      .rotationEffect(.degrees(Double(data.headingDegrees)))
                      .foregroundStyle(.blue)
                    Text("\(data.headingDegrees)° \(data.compassDirection)")
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
                    .foregroundStyle(intoxicationColor(for: data.intoxicationScore))
                }

                LabeledContent("Last Updated") {
                  Text(data.updatedAt, style: .relative)
                    .foregroundStyle(.secondary)
                }
              }
            }

            // Vehicle Info Section
            if let vehicle = currentVehicle {
              Section("Vehicle Info") {
                LabeledContent("Name", value: vehicle.name ?? "Unknown")
                LabeledContent("ID", value: vehicle.id)
                LabeledContent("Invite Code", value: vehicle.inviteCode)
                if let description = vehicle.description {
                  LabeledContent("Description", value: description)
                }
              }
            }
          }
          .refreshable {
            await supabaseService.loadVehicles()
            await loadUnidentifiedCount()
          }
        }
      }
      .navigationTitle(currentVehicle?.name ?? "Vehicle")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button("Add", systemImage: "plus") {
            showingJoinVehicle = true
          }
        }

        if supabaseService.vehicles.count > 1 {
          ToolbarItem(placement: .topBarLeading) {
            Menu {
              ForEach(supabaseService.vehicles) { vehicle in
                Button {
                  withAnimation {
                    selectedVehicleId = vehicle.id
                  }
                } label: {
                  if vehicle.id == currentVehicle?.id {
                    Label(vehicle.name ?? vehicle.id, systemImage: "checkmark")
                  } else {
                    Text(vehicle.name ?? vehicle.id)
                  }
                }
              }
            } label: {
              Label("Switch Vehicle", systemImage: "car.2.fill")
            }
          }
        }
      }
    }
    .sheet(isPresented: $showingJoinVehicle) {
      JoinVehicleView()
    }
    .sheet(isPresented: $showingUnidentifiedFaces) {
      if let vehicle = currentVehicle {
        UnidentifiedFacesView(vehicle: vehicle)
      }
    }
    .navigationDestination(isPresented: $showingFaceDetections) {
      if let vehicle = currentVehicle {
        FaceDetectionsView(vehicle: vehicle)
      }
    }
    .task {
      await loadUnidentifiedCount()
    }
    .onChange(of: selectedVehicleId) { _, _ in
      Task {
        await loadUnidentifiedCount()
      }
    }
  }

  // MARK: - No Vehicles View

  private var noVehiclesView: some View {
    ContentUnavailableView {
      Label("No Vehicles", systemImage: "car.fill")
    } description: {
      Text("Join a vehicle using an invite code to see real-time data.")
    } actions: {
      Button("Join Vehicle") {
        showingJoinVehicle = true
      }
      .buttonStyle(.borderedProminent)
    }
  }

  // MARK: - Driver Alert Section

  @ViewBuilder
  private func driverAlertSection(data: VehicleRealtime) -> some View {
    if data.intoxicationScore >= 4 || data.driverStatus.lowercased() == "impaired" {
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
    } else if data.intoxicationScore >= 2 || data.driverStatus.lowercased() == "drowsy" {
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

  private func loadUnidentifiedCount() async {
    guard let vehicle = currentVehicle else { return }
    do {
      let count = try await supabaseService.getUnidentifiedFacesCount(for: vehicle.id)
      await MainActor.run {
        withAnimation {
          unidentifiedCount = count
        }
      }
    } catch {
      print("Error loading unidentified count: \(error)")
    }
  }

  private func intoxicationColor(for score: Int) -> Color {
    if score >= 4 { return .red }
    if score >= 2 { return .orange }
    return .green
  }
}

// MARK: - Animated Vehicle View

struct AnimatedVehicleView: View {
  let isMoving: Bool
  let speed: Int

  @State private var wheelRotation: Double = 0
  @State private var vehicleOffset: CGFloat = 0

  private var rotationSpeed: Double {
    Double(max(speed, 10)) / 10
  }

  var body: some View {
    ZStack {
      Image("modelY")
        .resizable()
        .aspectRatio(contentMode: .fit)
        .overlay {
          GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            WheelView(rotation: wheelRotation)
              .frame(width: width * 0.12, height: width * 0.12)
              .position(x: width * 0.75, y: height * 0.72)

            WheelView(rotation: wheelRotation)
              .frame(width: width * 0.12, height: width * 0.12)
              .position(x: width * 0.25, y: height * 0.72)
          }
        }
        .offset(x: vehicleOffset)
    }
    .onChange(of: isMoving, initial: true) { _, newValue in
      if newValue {
        startDrivingAnimation()
      } else {
        stopDrivingAnimation()
      }
    }
  }

  private func startDrivingAnimation() {
    withAnimation(.linear(duration: 1 / rotationSpeed).repeatForever(autoreverses: false)) {
      wheelRotation = 360
    }
    withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
      vehicleOffset = 3
    }
  }

  private func stopDrivingAnimation() {
    withAnimation(.easeOut(duration: 0.5)) {
      wheelRotation = 0
      vehicleOffset = 0
    }
  }
}

// MARK: - Wheel View

struct WheelView: View {
  let rotation: Double

  var body: some View {
    Circle()
      .fill(Color(white: 0.2))
      .overlay {
        ForEach(0..<5, id: \.self) { index in
          Rectangle()
            .fill(Color(white: 0.4))
            .frame(width: 2, height: 10)
            .offset(y: -6)
            .rotationEffect(.degrees(Double(index) * 72))
        }
      }
      .rotationEffect(.degrees(rotation))
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
    default: return .gray
    }
  }

  private var statusIcon: String {
    switch status.lowercased() {
    case "alert": return "checkmark.circle.fill"
    case "drowsy": return "moon.fill"
    case "impaired": return "exclamationmark.triangle.fill"
    default: return "questionmark.circle.fill"
    }
  }

  var body: some View {
    Label(status.capitalized, systemImage: statusIcon)
      .font(.caption)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(statusColor.opacity(0.2))
      .foregroundStyle(statusColor)
      .clipShape(.capsule)
  }
}

#Preview {
  VehicleView()
}
