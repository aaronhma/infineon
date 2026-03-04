//
//  VehicleSettingsView.swift
//  InfineonProject
//
//  Created by Aaron Ma on 2/16/26.
//

import AaronUI
import Supabase
import SwiftUI

struct VehicleSettingsView: View {
  @Environment(V2AppData.self) private var appData
  @Environment(\.dismiss) private var dismiss

  let vehicle: Vehicle

  @State private var vehicleName = ""
  @State private var vehicleDescription = ""
  @State private var isSaving = false
  @State private var errorMessage: String?

  // Feature toggles
  @State private var enableYolo = true
  @State private var enableStream = true
  @State private var enableShazam = true
  @State private var enableMicrophone = true
  @State private var enableCamera = true
  @State private var enableDashcam = false

  private var isOwner: Bool {
    supabase.currentUser?.id == vehicle.ownerId
  }

  var body: some View {
    NavigationStack {
      List {
        Section {
          LabeledContent("Vehicle ID") {
            Text(vehicle.id)
              .font(.caption)
              .foregroundStyle(.secondary)
              .textSelection(.enabled)
          }
        } header: {
          Text("Vehicle ID")
        } footer: {
          Text("This is your hardware's unique identifier.")
        }

        Section {
          LabeledContent("Invite Code") {
            Text(vehicle.inviteCode)
              .font(.caption)
              .foregroundStyle(.secondary)
              .textSelection(.enabled)
          }
        }

        if isOwner {
          Section("Vehicle Name") {
            TextField("Vehicle name", text: $vehicleName)
          }

          Section("Description") {
            TextField("Vehicle description", text: $vehicleDescription)
          }

          if let errorMessage {
            Section {
              Text(errorMessage)
                .foregroundStyle(.red)
            }
          }
        } else {
          Section("Vehicle Info") {
            LabeledContent("Name") {
              Text(vehicle.name ?? "Unnamed")
                .foregroundStyle(.secondary)
            }

            LabeledContent("Description") {
              Text(vehicle.description ?? "No description")
                .foregroundStyle(.secondary)
            }
          }

          Section {
            Text("Only the vehicle owner can edit these settings.")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        }

        Section("Note") {
          Text("These changes will take effect when the device restarts.")
        }

        Section("Hardware") {
          featureToggle(
            "Camera",
            icon: "camera.fill",
            slashIcon: "camera.slash.fill",
            description: "Capture video from the vehicle camera",
            color: .blue,
            isOn: $enableCamera
          )

          featureToggle(
            "Microphone",
            icon: "mic.fill",
            slashIcon: "mic.slash.fill",
            description: "Record audio for music recognition",
            color: .orange,
            isOn: $enableMicrophone
          )
        }

        Section {
          featureToggle(
            "Live Camera Stream",
            icon: "video.fill",
            slashIcon: "video.slash.fill",
            description: "Stream live video to the app",
            color: .green,
            isOn: $enableStream
          )

          featureToggle(
            "AI Detection",
            icon: "eye.fill",
            slashIcon: "eye.slash.fill",
            description: "Detect phone usage and drinking with YOLO",
            color: .purple,
            isOn: $enableYolo
          )

          featureToggle(
            "Music Recognition",
            icon: "shazam.logo.fill",
            slashIcon: "shazam.logo.fill",
            description: "Identify songs playing in the vehicle",
            color: .cyan,
            isOn: $enableShazam
          )

          featureToggle(
            "Dashcam",
            icon: "record.circle",
            slashIcon: "record.circle.fill",
            description: "Record annotated dashcam video on device",
            color: .red,
            isOn: $enableDashcam
          )
        } header: {
          Text("Features")
        }
      }
      .navigationTitle("Vehicle Settings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          CloseButton {
            dismiss()
          }
        }

        if isOwner {
          ToolbarItem(placement: .topBarTrailing) {
            if isSaving {
              ProgressView()
            } else {
              Button("Save") {
                Task {
                  await saveVehicleSettings()
                }
              }
              .disabled(vehicleName.isEmpty)
            }
          }
        }
      }
      .onAppear {
        vehicleName = vehicle.name ?? ""
        vehicleDescription = vehicle.description ?? ""
        enableYolo = vehicle.enableYolo
        enableStream = vehicle.enableStream
        enableShazam = vehicle.enableShazam
        enableMicrophone = vehicle.enableMicrophone
        enableCamera = vehicle.enableCamera
        enableDashcam = vehicle.enableDashcam
      }
      .onDisappear {
        hideKeyboard()
      }
      .overlay {
        if isSaving {
          Color.black.opacity(0.3)
            .ignoresSafeArea()
            .overlay {
              ProgressView("Saving...")
                .padding()
                .background(.regularMaterial, in: .rect(cornerRadius: 12))
            }
        }
      }
    }
  }

  private func saveVehicleSettings() async {
    isSaving = true
    errorMessage = nil

    do {
      try await supabase.updateVehicle(
        vehicleId: vehicle.id,
        name: vehicleName,
        description: vehicleDescription.isEmpty ? nil : vehicleDescription,
        enableYolo: enableYolo,
        enableStream: enableStream,
        enableShazam: enableShazam,
        enableMicrophone: enableMicrophone,
        enableCamera: enableCamera,
        enableDashcam: enableDashcam
      )

      // Update the profile in appData so the UI reflects the change
      await MainActor.run {
        if var profile = appData.watchingProfile {
          let updatedVehicle = supabase.vehicles.first { $0.id == vehicle.id }
          if let updatedVehicle {
            profile.vehicle = updatedVehicle
            profile.name = updatedVehicle.name ?? profile.name
            appData.watchingProfile = profile
          }
        }
        isSaving = false
        dismiss()
      }
    } catch {
      await MainActor.run {
        errorMessage = error.localizedDescription
        isSaving = false
      }
    }
  }

  @ViewBuilder
  private func featureToggle(
    _ title: String,
    icon: String,
    slashIcon: String,
    description: String,
    color: Color,
    isOn: Binding<Bool>
  ) -> some View {
    Toggle(isOn: isOn.animation()) {
      Label {
        VStack(alignment: .leading) {
          Text(title)
          Text(description)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      } icon: {
        SettingsBoxView(icon: isOn.wrappedValue ? icon : slashIcon, color: color)
      }
    }
    .disabled(!isOwner)
  }
}

#Preview {
  VehicleSettingsView(
    vehicle: Vehicle(
      id: "", createdAt: .now, updatedAt: .now, name: "", description: "", inviteCode: "",
      ownerId: UUID()))
}
