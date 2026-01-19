//
//  VehicleListView.swift
//  InfineonProject
//
//  Created by Aaron Ma on 1/13/26.
//

import SwiftUI

struct VehicleListView: View {
  @State private var showingJoinVehicle = false
  @State private var selectedVehicle: Vehicle?

  var body: some View {
    NavigationStack {
      Group {
        if supabase.vehicles.isEmpty {
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
        } else {
          List {
            ForEach(supabase.vehicles) { vehicle in
              VehicleRowView(
                vehicle: vehicle,
                realtimeData: supabase.vehicleRealtimeData[vehicle.id]
              )
              .onTapGesture {
                selectedVehicle = vehicle
              }
            }
            .onDelete(perform: deleteVehicles)
          }
        }
      }
      .navigationTitle("My Vehicles")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button {
            showingJoinVehicle = true
          } label: {
            Image(systemName: "plus")
          }
        }
      }
      .sheet(isPresented: $showingJoinVehicle) {
        JoinVehicleView()
      }
      .sheet(item: $selectedVehicle) { vehicle in
        VehicleDetailView(
          vehicle: vehicle,
          realtimeData: supabase.vehicleRealtimeData[vehicle.id]
        )
      }
      .refreshable {
        await supabase.loadVehicles()
      }
    }
  }

  private func deleteVehicles(at offsets: IndexSet) {
    for index in offsets {
      let vehicle = supabase.vehicles[index]
      Task {
        try? await supabase.leaveVehicle(vehicle.id)
      }
    }
  }
}

struct VehicleRowView: View {
  let vehicle: Vehicle
  let realtimeData: VehicleRealtime?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(vehicle.name ?? vehicle.id)
          .font(.headline)

        Spacer()

        if let data = realtimeData {
          DriverStatusBadge(status: data.driverStatus)
        }
      }

      if let data = realtimeData {
        HStack(spacing: 16) {
          // Speed
          HStack(spacing: 4) {
            Image(systemName: "speedometer")
              .foregroundStyle(data.isSpeeding ? .red : .secondary)
            Text("\(data.speedMph) mph")
              .foregroundStyle(data.isSpeeding ? .red : .primary)
          }

          // Heading
          HStack(spacing: 4) {
            Image(systemName: "location.north.fill")
              .rotationEffect(.degrees(Double(data.headingDegrees)))
              .foregroundStyle(.secondary)
            Text("\(data.headingDegrees)° \(data.compassDirection)")
          }

          Spacer()

          // Last updated
          Text(data.updatedAt.formatted(date: .abbreviated, time: .standard))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .font(.subheadline)
      } else {
        Text("No data available")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 4)
  }
}

struct VehicleDetailView: View {
  @Environment(\.dismiss) private var dismiss

  let vehicle: Vehicle
  let realtimeData: VehicleRealtime?

  @State private var unidentifiedCount: Int = 0
  @State private var showingUnidentifiedFaces = false

  private func loadUnidentifiedCount() async {
    do {
      let count = try await supabase.getUnidentifiedFacesCount(for: vehicle.id)

      await MainActor.run {
        withAnimation(.bouncy) {
          unidentifiedCount = count
        }
      }
    } catch {
      print("Error loading unidentified count: \(error)")
    }
  }

  var body: some View {
    NavigationStack {
      List {
        // Unidentified Faces Banner
        if unidentifiedCount > 0 {
          Section {
            Button {
              showingUnidentifiedFaces.toggle()
            } label: {
              HStack(spacing: 12) {
                Image(systemName: "face.smiling")
                  .font(.title2)
                  .foregroundStyle(.orange)
                  .frame(width: 40)

                VStack(alignment: .leading, spacing: 2) {
                  Text("\(unidentifiedCount) unidentified face\(unidentifiedCount == 1 ? "" : "s")")
                    .font(.headline)
                    .foregroundStyle(.primary)

                  Text("Add a profile")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                  .foregroundStyle(.secondary)
              }
              .frame(maxWidth: .infinity)
              .padding(.vertical, 4)
            }
          }
        }

        // Vehicle Info
        Section("Vehicle Info") {
          LabeledContent("ID", value: vehicle.id)
          LabeledContent("Name", value: vehicle.name ?? "Unknown")
          LabeledContent("Invite Code", value: vehicle.inviteCode)
        }

        // Face Detections Gallery
        Section("Face Detections") {
          NavigationLink {
            FaceDetectionsView(vehicle: vehicle)
          } label: {
            Label("View Face Snapshots", systemImage: "person.crop.rectangle.stack")
          }
        }

        // Real-time Data
        if let data = realtimeData {
          Section("Speed & Direction") {
            LabeledContent("Current Speed", value: "\(data.speedMph) mph")
            LabeledContent("Speed Limit", value: "\(data.speedLimitMph) mph")
            LabeledContent("Heading", value: "\(data.headingDegrees)° \(data.compassDirection)")

            if data.isSpeeding {
              Label("Speeding!", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            }
          }

          Section("Driver Status") {
            HStack {
              Text("Status")
              Spacer()
              DriverStatusBadge(status: data.driverStatus)
            }
            LabeledContent("Intoxication Score", value: "\(data.intoxicationScore)/6")

            if data.intoxicationScore >= 4 {
              Label(
                "High Risk - Driver may be impaired!", systemImage: "exclamationmark.triangle.fill"
              )
              .foregroundStyle(.red)
            } else if data.intoxicationScore >= 2 {
              Label("Moderate Risk - Driver may be drowsy", systemImage: "moon.fill")
                .foregroundStyle(.orange)
            }
          }

          Section("Activity") {
            LabeledContent("Moving", value: data.isMoving ? "Yes" : "No")
            HStack {
              Text("Last Updated")
              Spacer()
              Text(data.updatedAt, style: .relative)
                .foregroundStyle(.secondary)
            }
          }
        } else {
          Section {
            ContentUnavailableView {
              Label("No Data", systemImage: "antenna.radiowaves.left.and.right.slash")
            } description: {
              Text("Vehicle is not currently transmitting data.")
            }
          }
        }
      }
      .navigationTitle(vehicle.name ?? "Vehicle")
      .navigationBarTitleDisplayMode(.inline)
      .sheet(isPresented: $showingUnidentifiedFaces) {
        UnidentifiedFacesView(vehicle: vehicle)
      }
      .task {
        await loadUnidentifiedCount()
      }
    }
  }
}

#Preview {
  VehicleListView()
}
