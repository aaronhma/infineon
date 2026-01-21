//
//  UnidentifiedFacesView.swift
//  InfineonProject
//
//  Created by Aaron Ma on 1/13/26.
//

import AaronUI
import SwiftUI

struct UnidentifiedFacesView: View {
  let vehicle: Vehicle

  @Environment(\.dismiss) private var dismiss

  @State private var unidentifiedFaces: [FaceDetection] = []
  @State private var driverProfiles: [DriverProfile] = []
  @State private var isLoading = true
  @State private var errorMessage: String?
  @State private var selectedFace: FaceDetection?
  @State private var showingCreateProfile = false

  private let columns = [
    GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 8)
  ]

  var body: some View {
    NavigationStack {
      Group {
        if isLoading {
          ProgressView("Loading faces...")
        } else if let errorMessage {
          ContentUnavailableView {
            Label("Error", systemImage: "exclamationmark.triangle")
          } description: {
            Text(errorMessage)
          } actions: {
            Button("Retry") {
              Task {
                await loadData()
              }
            }
          }
        } else if unidentifiedFaces.isEmpty {
          ContentUnavailableView {
            Label("All Identified", systemImage: "checkmark.circle")
          } description: {
            Text("All detected faces have been identified.")
          }
        } else {
          ScrollView {
            VStack(alignment: .leading, spacing: 16) {
              // Existing profiles section
              if !driverProfiles.isEmpty {
                Section {
                  ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                      ForEach(driverProfiles) { profile in
                        DriverProfileChip(profile: profile)
                      }
                    }
                    .padding(.horizontal)
                  }
                } header: {
                  Text("Existing Profiles")
                    .font(.headline)
                    .padding(.horizontal)
                }
              }

              // Unidentified faces section
              Section {
                LazyVGrid(columns: columns, spacing: 8) {
                  ForEach(unidentifiedFaces) { face in
                    UnidentifiedFaceThumbnail(detection: face)
                      .onTapGesture {
                        Haptics.impact()
                        selectedFace = face
                      }
                  }
                }
                .padding(.horizontal)
              } header: {
                Text("Unidentified Faces (\(unidentifiedFaces.count))")
                  .font(.headline)
                  .padding(.horizontal)
              }
            }
            .padding(.vertical)
          }
        }
      }
      .navigationTitle("Identify Faces")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          CloseButton {
            dismiss()
          }
        }

        ToolbarItem(placement: .primaryAction) {
          Button {
            Haptics.impact()
            showingCreateProfile = true
          } label: {
            Image(systemName: "plus")
          }
        }
      }
      .sheet(item: $selectedFace) { face in
        AssignProfileView(
          vehicle: vehicle,
          detection: face,
          existingProfiles: driverProfiles,
          onAssigned: {
            Task {
              await loadData()
            }
          }
        )
      }
      .sheet(isPresented: $showingCreateProfile) {
        CreateProfileView(vehicle: vehicle) { _ in
          Task {
            await loadData()
          }
        }
      }
      .task {
        await loadData()
      }
      .refreshable {
        await loadData()
      }
    }
  }

  private func loadData() async {
    isLoading = true
    errorMessage = nil

    do {
      async let faces = supabase.fetchUnidentifiedFaces(for: vehicle.id)
      async let profiles = supabase.fetchDriverProfiles(for: vehicle.id)

      let (fetchedFaces, fetchedProfiles) = try await (faces, profiles)

      await MainActor.run {
        unidentifiedFaces = fetchedFaces
        driverProfiles = fetchedProfiles
        isLoading = false
      }
    } catch {
      await MainActor.run {
        errorMessage = error.localizedDescription
        isLoading = false
      }
    }
  }
}

struct DriverProfileChip: View {
  let profile: DriverProfile

  @State private var image: UIImage?

  var body: some View {
    VStack(spacing: 4) {
      if let image {
        Image(uiImage: image)
          .resizable()
          .aspectRatio(contentMode: .fill)
          .frame(width: 50, height: 50)
          .clipShape(Circle())
      } else {
        Circle()
          .fill(Color.blue.opacity(0.2))
          .frame(width: 50, height: 50)
          .overlay {
            Text(profile.name.prefix(1).uppercased())
              .font(.title2)
              .fontWeight(.semibold)
              .foregroundStyle(.blue)
          }
      }

      Text(profile.name)
        .font(.caption)
        .lineLimit(1)
    }
    .task {
      await loadImage()
    }
  }

  private func loadImage() async {
    guard let imagePath = profile.profileImagePath else { return }

    do {
      let data = try await supabase.downloadFaceImage(path: imagePath)
      await MainActor.run {
        image = UIImage(data: data)
      }
    } catch {
      print("Error loading profile image: \(error)")
    }
  }
}

struct UnidentifiedFaceThumbnail: View {
  let detection: FaceDetection

  @State private var image: UIImage?
  @State private var isLoading = true

  var body: some View {
    ZStack {
      if let image {
        Image(uiImage: image)
          .resizable()
          .aspectRatio(contentMode: .fill)
          .frame(minWidth: 100, minHeight: 100)
          .clipped()
      } else if isLoading {
        Rectangle()
          .fill(Color.gray.opacity(0.2))
          .overlay {
            ProgressView()
          }
      } else {
        Rectangle()
          .fill(Color.gray.opacity(0.2))
          .overlay {
            Image(systemName: "person.crop.circle.badge.questionmark")
              .font(.title)
              .foregroundStyle(.secondary)
          }
      }
    }
    .frame(minWidth: 100, minHeight: 100)
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .stroke(Color.orange.opacity(0.5), lineWidth: 2)
    )
    .task {
      await loadImage()
    }
  }

  private func loadImage() async {
    guard let imagePath = detection.imagePath else {
      isLoading = false
      return
    }

    do {
      let data = try await supabase.downloadFaceImage(path: imagePath)
      await MainActor.run {
        image = UIImage(data: data)
        isLoading = false
      }
    } catch {
      print("Error loading thumbnail: \(error)")
      await MainActor.run {
        isLoading = false
      }
    }
  }
}

struct AssignProfileView: View {
  let vehicle: Vehicle
  let detection: FaceDetection
  let existingProfiles: [DriverProfile]
  let onAssigned: () -> Void

  @Environment(\.dismiss) private var dismiss

  @State private var selectedProfile: DriverProfile?
  @State private var showingCreateNew = false
  @State private var isAssigning = false
  @State private var image: UIImage?

  var body: some View {
    NavigationStack {
      VStack(spacing: 20) {
        // Face preview
        if let image {
          Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxHeight: 200)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
          Rectangle()
            .fill(Color.gray.opacity(0.2))
            .aspectRatio(1, contentMode: .fit)
            .frame(maxHeight: 200)
            .overlay {
              ProgressView()
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }

        Text("Who is this?")
          .font(.headline)

        // Profile selection
        if existingProfiles.isEmpty {
          Text("No profiles yet. Create one to identify this face.")
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        } else {
          ScrollView {
            LazyVStack(spacing: 8) {
              ForEach(existingProfiles) { profile in
                ProfileSelectionRow(
                  profile: profile,
                  isSelected: selectedProfile?.id == profile.id
                )
                .onTapGesture {
                  selectedProfile = profile
                }
              }
            }
          }
        }

        Spacer()

        // Actions
        VStack(spacing: 12) {
          if !existingProfiles.isEmpty && selectedProfile != nil {
            Button {
              Haptics.impact()

              Task {
                await assignProfile()
              }
            } label: {
              if isAssigning {
                ProgressView()
                  .frame(maxWidth: .infinity)
              } else {
                Text("Assign to \(selectedProfile?.name ?? "")")
                  .frame(maxWidth: .infinity)
              }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isAssigning)
          }

          Button {
            Haptics.impact()

            showingCreateNew = true
          } label: {
            Label("Create New Profile", systemImage: "plus")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
        }
      }
      .padding()
      .navigationTitle("Identify Face")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          CloseButton {
            dismiss()
          }
        }
      }
      .sheet(isPresented: $showingCreateNew) {
        CreateProfileView(
          vehicle: vehicle,
          initialImage: image,
          initialImagePath: detection.imagePath
        ) { profile in
          // Assign this detection to the new profile
          Task {
            do {
              try await supabase.assignDriverToDetection(
                detectionId: detection.id,
                driverProfileId: profile.id
              )
              await MainActor.run {
                onAssigned()
                dismiss()
              }
            } catch {
              print("Error assigning to new profile: \(error)")
            }
          }
        }
      }
      .task {
        await loadImage()
      }
    }
  }

  private func loadImage() async {
    guard let imagePath = detection.imagePath else { return }

    do {
      let data = try await supabase.downloadFaceImage(path: imagePath)
      await MainActor.run {
        image = UIImage(data: data)
      }
    } catch {
      print("Error loading image: \(error)")
    }
  }

  private func assignProfile() async {
    guard let profile = selectedProfile else { return }

    isAssigning = true

    do {
      try await supabase.assignDriverToDetection(
        detectionId: detection.id,
        driverProfileId: profile.id
      )
      await MainActor.run {
        onAssigned()
        dismiss()
      }
    } catch {
      print("Error assigning profile: \(error)")
      await MainActor.run {
        isAssigning = false
      }
    }
  }
}

struct ProfileSelectionRow: View {
  let profile: DriverProfile
  let isSelected: Bool

  @State private var image: UIImage?

  var body: some View {
    HStack(spacing: 12) {
      if let image {
        Image(uiImage: image)
          .resizable()
          .aspectRatio(contentMode: .fill)
          .frame(width: 44, height: 44)
          .clipShape(Circle())
      } else {
        Circle()
          .fill(Color.blue.opacity(0.2))
          .frame(width: 44, height: 44)
          .overlay {
            Text(profile.name.prefix(1).uppercased())
              .font(.headline)
              .foregroundStyle(.blue)
          }
      }

      Text(profile.name)
        .font(.body)

      Spacer()

      if isSelected {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(.blue)
      }
    }
    .padding()
    .background(isSelected ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .task {
      await loadImage()
    }
  }

  private func loadImage() async {
    guard let imagePath = profile.profileImagePath else { return }

    do {
      let data = try await supabase.downloadFaceImage(path: imagePath)
      await MainActor.run {
        image = UIImage(data: data)
      }
    } catch {
      print("Error loading profile image: \(error)")
    }
  }
}

struct CreateProfileView: View {
  let vehicle: Vehicle
  var initialImage: UIImage?
  var initialImagePath: String?
  let onCreate: (DriverProfile) -> Void

  @Environment(\.dismiss) private var dismiss

  @State private var name = ""
  @State private var notes = ""
  @State private var isCreating = false
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      Form {
        if let image = initialImage {
          Section {
            HStack {
              Spacer()
              Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 150)
                .clipShape(RoundedRectangle(cornerRadius: 8))
              Spacer()
            }
          }
        }

        Section("Profile Info") {
          TextField("Name", text: $name)
            .textContentType(.name)

          TextField("Notes (optional)", text: $notes, axis: .vertical)
            .lineLimit(3...6)
        }

        if let errorMessage {
          Section {
            Text(errorMessage)
              .foregroundStyle(.red)
          }
        }
      }
      .navigationTitle("New Driver Profile")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          CloseButton {
            dismiss()
          }
        }

        ToolbarItem(placement: .confirmationAction) {
          Button("Create") {
            Haptics.impact()

            Task {
              await createProfile()
            }
          }
          .disabled(name.isEmpty || isCreating)
        }
      }
    }
  }

  private func createProfile() async {
    isCreating = true
    errorMessage = nil

    do {
      let profile = try await supabase.createDriverProfile(
        vehicleId: vehicle.id,
        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
        notes: notes.isEmpty ? nil : notes,
        imagePath: initialImagePath
      )

      await MainActor.run {
        onCreate(profile)
        dismiss()
      }
    } catch {
      await MainActor.run {
        errorMessage = error.localizedDescription
        isCreating = false
      }
    }
  }
}

#Preview {
  UnidentifiedFacesView(
    vehicle: Vehicle(
      id: "test",
      createdAt: .now,
      updatedAt: .now,
      name: "Test Vehicle",
      description: nil,
      inviteCode: "ABC123",
      ownerId: nil
    ))
}
