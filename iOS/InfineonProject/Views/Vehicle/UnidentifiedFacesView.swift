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

  @State private var faceClusters: [FaceCluster] = []
  @State private var driverProfiles: [DriverProfile] = []
  @State private var isLoading = true
  @State private var errorMessage: String?
  @State private var selectedCluster: FaceCluster?
  @State private var showingCreateProfile = false

  private let columns = [
    GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 8)
  ]

  var totalFaceCount: Int {
    faceClusters.reduce(0) { $0 + $1.faceCount }
  }

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
        } else if faceClusters.isEmpty {
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

              // Info banner explaining clustering
              HStack(spacing: 12) {
                Image(systemName: "sparkles")
                  .font(.title2)
                  .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 2) {
                  Text("Smart Face Grouping")
                    .font(.subheadline)
                    .fontWeight(.medium)
                  Text(
                    "Similar faces are grouped together. Identifying one face will identify all similar faces automatically."
                  )
                  .font(.caption)
                  .foregroundStyle(.secondary)
                }
              }
              .padding()
              .background(Color.blue.opacity(0.1))
              .clipShape(RoundedRectangle(cornerRadius: 12))
              .padding(.horizontal)

              // Face clusters section
              Section {
                LazyVGrid(columns: columns, spacing: 8) {
                  ForEach(faceClusters) { cluster in
                    FaceClusterThumbnail(cluster: cluster)
                      .onTapGesture {
                        Haptics.impact()
                        selectedCluster = cluster
                      }
                  }
                }
                .padding(.horizontal)
              } header: {
                HStack {
                  Text("Unknown People (\(faceClusters.count))")
                    .font(.headline)
                  Spacer()
                  Text("\(totalFaceCount) total faces")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
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
      .sheet(item: $selectedCluster) { cluster in
        AssignClusterProfileView(
          vehicle: vehicle,
          cluster: cluster,
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
      async let clusters = supabase.fetchUnidentifiedFaceClusters(for: vehicle.id)
      async let profiles = supabase.fetchDriverProfiles(for: vehicle.id)

      let (fetchedClusters, fetchedProfiles) = try await (clusters, profiles)

      await MainActor.run {
        faceClusters = fetchedClusters
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

/// Displays a face cluster thumbnail with face count badge
struct FaceClusterThumbnail: View {
  let cluster: FaceCluster

  @State private var image: UIImage?
  @State private var isLoading = true

  var body: some View {
    ZStack(alignment: .topTrailing) {
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

      // Face count badge
      if cluster.faceCount > 1 {
        Text("\(cluster.faceCount)")
          .font(.caption2)
          .fontWeight(.bold)
          .foregroundStyle(.white)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(Color.blue)
          .clipShape(Capsule())
          .offset(x: -4, y: 4)
      }
    }
    .task {
      await loadImage()
    }
  }

  private func loadImage() async {
    guard let imagePath = cluster.representativeImagePath else {
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

/// View for assigning a profile to an entire face cluster
struct AssignClusterProfileView: View {
  let vehicle: Vehicle
  let cluster: FaceCluster
  let existingProfiles: [DriverProfile]
  let onAssigned: () -> Void

  @Environment(\.dismiss) private var dismiss

  @State private var selectedProfile: DriverProfile?
  @State private var showingCreateNew = false
  @State private var isAssigning = false
  @State private var image: UIImage?
  @State private var clusterDetections: [FaceDetection] = []
  @State private var showingAllFaces = false

  var body: some View {
    NavigationStack {
      VStack(spacing: 20) {
        // Face preview with cluster info
        VStack(spacing: 8) {
          if let image {
            Image(uiImage: image)
              .resizable()
              .aspectRatio(contentMode: .fit)
              .frame(maxHeight: 180)
              .clipShape(RoundedRectangle(cornerRadius: 12))
          } else {
            Rectangle()
              .fill(Color.gray.opacity(0.2))
              .aspectRatio(1, contentMode: .fit)
              .frame(maxHeight: 180)
              .overlay {
                ProgressView()
              }
              .clipShape(RoundedRectangle(cornerRadius: 12))
          }

          // Cluster info
          HStack(spacing: 16) {
            Label("\(cluster.faceCount) faces", systemImage: "photo.stack")
            Label(
              cluster.lastSeen.formatted(date: .abbreviated, time: .shortened), systemImage: "clock"
            )
          }
          .font(.caption)
          .foregroundStyle(.secondary)

          if cluster.faceCount > 1 {
            Button {
              showingAllFaces = true
            } label: {
              Text("View all \(cluster.faceCount) faces")
                .font(.caption)
            }
          }
        }

        Text("Who is this?")
          .font(.headline)

        // Profile selection
        if existingProfiles.isEmpty {
          Text("No profiles yet. Create one to identify this person.")
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
                await assignProfileToCluster()
              }
            } label: {
              if isAssigning {
                ProgressView()
                  .frame(maxWidth: .infinity)
              } else {
                VStack(spacing: 2) {
                  Text("Assign to \(selectedProfile?.name ?? "")")
                  if cluster.faceCount > 1 {
                    Text("Will identify \(cluster.faceCount) faces")
                      .font(.caption)
                      .foregroundStyle(.white.opacity(0.8))
                  }
                }
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
      .navigationTitle("Identify Person")
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
          initialImagePath: cluster.representativeImagePath
        ) { profile in
          // Assign this cluster to the new profile
          Task {
            do {
              _ = try await supabase.assignProfileToCluster(
                clusterId: cluster.clusterId,
                profileId: profile.id
              )
              await MainActor.run {
                onAssigned()
                dismiss()
              }
            } catch {
              print("Error assigning cluster to new profile: \(error)")
            }
          }
        }
      }
      .sheet(isPresented: $showingAllFaces) {
        ClusterFacesGalleryView(
          vehicle: vehicle,
          cluster: cluster
        )
      }
      .task {
        await loadImage()
      }
    }
  }

  private func loadImage() async {
    guard let imagePath = cluster.representativeImagePath else { return }

    do {
      let data = try await supabase.downloadFaceImage(path: imagePath)
      await MainActor.run {
        image = UIImage(data: data)
      }
    } catch {
      print("Error loading image: \(error)")
    }
  }

  private func assignProfileToCluster() async {
    guard let profile = selectedProfile else { return }

    isAssigning = true

    do {
      let result = try await supabase.assignProfileToCluster(
        clusterId: cluster.clusterId,
        profileId: profile.id
      )
      print("Assigned \(result.updatedCount) faces to profile \(profile.name)")
      await MainActor.run {
        onAssigned()
        dismiss()
      }
    } catch {
      print("Error assigning profile to cluster: \(error)")
      await MainActor.run {
        isAssigning = false
      }
    }
  }
}

/// Gallery view showing all faces in a cluster
struct ClusterFacesGalleryView: View {
  let vehicle: Vehicle
  let cluster: FaceCluster

  @Environment(\.dismiss) private var dismiss

  @State private var detections: [FaceDetection] = []
  @State private var isLoading = true

  private let columns = [
    GridItem(.adaptive(minimum: 80, maximum: 120), spacing: 8)
  ]

  var body: some View {
    NavigationStack {
      Group {
        if isLoading {
          ProgressView("Loading faces...")
        } else if detections.isEmpty {
          ContentUnavailableView {
            Label("No Faces", systemImage: "photo")
          } description: {
            Text("No faces found in this cluster.")
          }
        } else {
          ScrollView {
            LazyVGrid(columns: columns, spacing: 8) {
              ForEach(detections) { detection in
                ClusterFaceCell(detection: detection)
              }
            }
            .padding()
          }
        }
      }
      .navigationTitle("Cluster Faces (\(cluster.faceCount))")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          CloseButton {
            dismiss()
          }
        }
      }
      .task {
        await loadDetections()
      }
    }
  }

  private func loadDetections() async {
    do {
      let fetchedDetections = try await supabase.fetchDetectionsForCluster(
        clusterId: cluster.clusterId,
        vehicleId: vehicle.id
      )
      await MainActor.run {
        detections = fetchedDetections
        isLoading = false
      }
    } catch {
      print("Error loading cluster detections: \(error)")
      await MainActor.run {
        isLoading = false
      }
    }
  }
}

struct ClusterFaceCell: View {
  let detection: FaceDetection

  @State private var image: UIImage?

  var body: some View {
    Group {
      if let image {
        Image(uiImage: image)
          .resizable()
          .aspectRatio(contentMode: .fill)
          .frame(width: 80, height: 80)
          .clipped()
      } else {
        Rectangle()
          .fill(Color.gray.opacity(0.2))
          .frame(width: 80, height: 80)
          .overlay {
            ProgressView()
          }
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .task {
      await loadImage()
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
      print("Error loading face: \(error)")
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
