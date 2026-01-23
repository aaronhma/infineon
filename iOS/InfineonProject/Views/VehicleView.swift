//
//  VehicleView.swift
//  InfineonProject
//
//  Created by Aaron Ma on 1/12/26.
//

import AaronUI
import ActivityKit
import RealityKit
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
    if data.intoxicationScore >= 4
      || data.driverStatus
        .lowercased() == "impaired"
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
  VehicleView(
    vehicle: V2Profile(
      id: "111", name: "AA", icon: "benji", vehicleId: "111",
      vehicle: Vehicle(
        id: "", createdAt: .now, updatedAt: .now, name: "", description: "", inviteCode: "",
        ownerId: UUID())))
}
