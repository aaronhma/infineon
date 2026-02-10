//
//  FaceDetectionsView.swift
//  InfineonProject
//
//  Created by Aaron Ma on 1/13/26.
//

import AaronUI
import SwiftUI

enum DetectionFilter: Hashable {
  case all
  case driver(UUID)
  case unidentified

  var displayName: String {
    switch self {
    case .all:
      return "All Drivers"
    case .driver:
      return "Driver"
    case .unidentified:
      return "Unidentified"
    }
  }
}

struct FaceDetectionsView: View {
  let vehicle: Vehicle

  @State private var allDetections: [FaceDetection] = []
  @State private var driverProfiles: [DriverProfile] = []
  @State private var isLoading = true
  @State private var errorMessage: String?
  @State private var selectedFilter: DetectionFilter = .all

  private let columns = [
    GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 8)
  ]

  private var filteredDetections: [FaceDetection] {
    switch selectedFilter {
    case .all:
      return allDetections
    case .driver(let profileId):
      return allDetections.filter { $0.driverProfileId == profileId }
    case .unidentified:
      return allDetections.filter { $0.driverProfileId == nil }
    }
  }

  private var filterTitle: String {
    switch selectedFilter {
    case .all:
      return "All Drivers"
    case .driver(let profileId):
      return driverProfiles.first { $0.id == profileId }?.name ?? "Driver"
    case .unidentified:
      return "Unidentified"
    }
  }

  var body: some View {
    Group {
      if isLoading {
        ProgressView("Loading detections...")
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
      } else if filteredDetections.isEmpty {
        ContentUnavailableView {
          Label("No Detections", systemImage: "face.dashed")
        } description: {
          if selectedFilter == .all {
            Text("No face detections recorded for this vehicle yet.")
          } else {
            Text("No detections found for this filter.")
          }
        } actions: {
          if selectedFilter != .all {
            Button("Show All") {
              selectedFilter = .all
            }
          }
        }
      } else {
        ScrollView {
          LazyVGrid(columns: columns, spacing: 8) {
            ForEach(filteredDetections) { detection in
              NavigationLink {
                FaceDetectionDetailView(detection: detection)
              } label: {
                FaceDetectionThumbnail(detection: detection)
              }
              .buttonStyle(.plain)
            }
          }
          .padding()
        }
      }
    }
    .navigationTitle("Face Detections")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Menu {
          Button {
            Haptics.impact()
            selectedFilter = .all
          } label: {
            Label("All Drivers", systemImage: selectedFilter == .all ? "checkmark" : "")
          }

          Divider()

          ForEach(driverProfiles) { profile in
            Button {
              Haptics.impact()
              selectedFilter = .driver(profile.id)
            } label: {
              Label(
                profile.name, systemImage: selectedFilter == .driver(profile.id) ? "checkmark" : "")
            }
          }

          if !driverProfiles.isEmpty {
            Divider()
          }

          Button {
            Haptics.impact()
            selectedFilter = .unidentified
          } label: {
            Label("Unidentified", systemImage: selectedFilter == .unidentified ? "checkmark" : "")
          }
        } label: {
          HStack(spacing: 4) {
            Text(filterTitle)
              .lineLimit(1)
            Image(systemName: "chevron.down")
              .bold()
              .font(.caption)
          }
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

  private func loadData() async {
    isLoading = true
    errorMessage = nil

    do {
      async let fetchedDetections = supabase.fetchFaceDetections(for: vehicle.id)
      async let fetchedProfiles = supabase.fetchDriverProfiles(for: vehicle.id)

      let (detections, profiles) = try await (fetchedDetections, fetchedProfiles)

      await MainActor.run {
        allDetections = detections
        driverProfiles = profiles
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

struct FaceDetectionThumbnail: View {
  let detection: FaceDetection

  @State private var image: UIImage?
  @State private var isLoading = true

  var statusColor: Color {
    if detection.intoxicationScore >= 4 {
      return .red
    } else if detection.intoxicationScore >= 2 {
      return .orange
    } else {
      return .green
    }
  }

  var body: some View {
    ZStack(alignment: .bottomTrailing) {
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
            Image(systemName: "photo")
              .foregroundStyle(.secondary)
          }
      }

      // Status indicator
      Circle()
        .fill(statusColor)
        .frame(width: 12, height: 12)
        .padding(6)
    }
    .frame(minWidth: 100, minHeight: 100)
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .stroke(statusColor.opacity(0.5), lineWidth: 2)
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

struct FaceDetectionDetailView: View {
  let detection: FaceDetection

  @State private var image: UIImage?
  @State private var isLoadingImage = true
  @State private var driverProfile: DriverProfile?
  @State private var showingDriverDetections = false

  var body: some View {
    ScrollView {
      VStack(spacing: 20) {
        // Image section
        imageSection

        // Metadata sections
        VStack(spacing: 16) {
          // Driver Profile section (if identified)
          if let profile = driverProfile {
            driverProfileSection(profile: profile)
          } else if detection.driverProfileId != nil {
            // Loading state
            GroupBox("Driver") {
              HStack {
                ProgressView()
                Text("Loading profile...")
                  .foregroundStyle(.secondary)
              }
            }
          } else {
            // Unidentified
            GroupBox("Driver") {
              HStack {
                Image(systemName: "person.crop.circle.badge.questionmark")
                  .font(.title2)
                  .foregroundStyle(.orange)
                Text("Unidentified")
                  .foregroundStyle(.secondary)
                Spacer()
              }
            }
          }

          eyeStateSection
          alertsSection
          drivingContextSection
          timestampSection
        }
        .padding(.horizontal)
      }
    }
    .navigationTitle("Detection Details")
    .navigationBarTitleDisplayMode(.inline)
    .task {
      await loadImage()
      await loadDriverProfile()
    }
    .sheet(isPresented: $showingDriverDetections) {
      if let profile = driverProfile, let vehicleId = detection.vehicleId {
        DriverDetectionsView(profile: profile, vehicleId: vehicleId)
      }
    }
  }

  @ViewBuilder
  private func driverProfileSection(profile: DriverProfile) -> some View {
    GroupBox("Driver") {
      Button {
        showingDriverDetections = true
      } label: {
        HStack(spacing: 12) {
          // Profile avatar
          Circle()
            .fill(Color.blue.opacity(0.2))
            .frame(width: 44, height: 44)
            .overlay {
              Text(profile.name.prefix(1).uppercased())
                .font(.headline)
                .foregroundStyle(.blue)
            }

          VStack(alignment: .leading, spacing: 2) {
            Text(profile.name)
              .font(.headline)
              .foregroundStyle(.primary)
            Text("View all detections")
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          Spacer()

          Image(systemName: "chevron.right")
            .foregroundStyle(.secondary)
        }
      }
      .buttonStyle(.plain)
    }
  }

  private func loadDriverProfile() async {
    guard let profileId = detection.driverProfileId,
      let vehicleId = detection.vehicleId
    else { return }

    do {
      let profiles = try await supabase.fetchDriverProfiles(for: vehicleId)
      await MainActor.run {
        driverProfile = profiles.first { $0.id == profileId }
      }
    } catch {
      print("Error loading driver profile: \(error)")
    }
  }

  @ViewBuilder
  private var imageSection: some View {
    ZStack {
      if let image {
        Image(uiImage: image)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .clipShape(RoundedRectangle(cornerRadius: 12))
      } else if isLoadingImage {
        Rectangle()
          .fill(Color.gray.opacity(0.2))
          .aspectRatio(4 / 3, contentMode: .fit)
          .overlay {
            ProgressView("Loading image...")
          }
          .clipShape(RoundedRectangle(cornerRadius: 12))
      } else {
        Rectangle()
          .fill(Color.gray.opacity(0.2))
          .aspectRatio(4 / 3, contentMode: .fit)
          .overlay {
            VStack {
              Image(systemName: "photo")
                .font(.largeTitle)
              Text("Image unavailable")
                .font(.caption)
            }
            .foregroundStyle(.secondary)
          }
          .clipShape(RoundedRectangle(cornerRadius: 12))
      }
    }
    .padding(.horizontal)
  }

  @ViewBuilder
  private var eyeStateSection: some View {
    GroupBox("Eye State") {
      VStack(spacing: 12) {
        HStack {
          Label("Left Eye", systemImage: "eye")
          Spacer()
          Text(detection.leftEyeState ?? "Unknown")
            .foregroundStyle(detection.leftEyeState == "OPEN" ? .green : .orange)
          if let ear = detection.leftEyeEar {
            Text("(\(ear, specifier: "%.3f"))")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        HStack {
          Label("Right Eye", systemImage: "eye")
          Spacer()
          Text(detection.rightEyeState ?? "Unknown")
            .foregroundStyle(detection.rightEyeState == "OPEN" ? .green : .orange)
          if let ear = detection.rightEyeEar {
            Text("(\(ear, specifier: "%.3f"))")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        if let avgEar = detection.avgEar {
          HStack {
            Label("Avg EAR", systemImage: "chart.bar")
            Spacer()
            Text("\(avgEar, specifier: "%.4f")")
              .monospacedDigit()
          }
        }
      }
    }
  }

  @ViewBuilder
  private var alertsSection: some View {
    GroupBox("Driver Alerts") {
      VStack(spacing: 12) {
        HStack {
          Label("Intoxication Score", systemImage: "gauge.with.needle")
          Spacer()
          Text("\(detection.intoxicationScore)/6")
            .bold()
            .foregroundStyle(intoxicationColor)
        }

        if detection.isDrowsy {
          Label("Drowsy", systemImage: "moon.fill")
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        if detection.isExcessiveBlinking {
          Label("Excessive Blinking", systemImage: "eye.trianglebadge.exclamationmark")
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        if detection.isUnstableEyes {
          Label("Unstable Eyes", systemImage: "exclamationmark.triangle")
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        if !detection.isDrowsy && !detection.isExcessiveBlinking && !detection.isUnstableEyes {
          Label("No alerts", systemImage: "checkmark.circle")
            .foregroundStyle(.green)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
  }

  @ViewBuilder
  private var drivingContextSection: some View {
    GroupBox("Driving Context") {
      VStack(spacing: 12) {
        if let speed = detection.speedMph {
          HStack {
            Label("Speed", systemImage: "speedometer")
            Spacer()
            Text("\(speed) mph")
              .foregroundStyle(detection.isSpeeding == true ? .red : .primary)
          }
        }

        if let heading = detection.headingDegrees, let direction = detection.compassDirection {
          HStack {
            Label("Heading", systemImage: "location.north")
            Spacer()
            Text("\(heading)° \(direction)")
          }
        }

        if detection.isSpeeding == true {
          Label("Speeding", systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
  }

  @ViewBuilder
  private var timestampSection: some View {
    GroupBox("Timestamp") {
      VStack(spacing: 8) {
        HStack {
          Label("Captured", systemImage: "clock")
          Spacer()
          Text(detection.createdAt.formatted(date: .abbreviated, time: .standard))
        }

        if let sessionId = detection.sessionId {
          HStack {
            Label("Session", systemImage: "number")
            Spacer()
            Text(sessionId.uuidString)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
    }
  }

  private var intoxicationColor: Color {
    if detection.intoxicationScore >= 4 {
      return .red
    } else if detection.intoxicationScore >= 2 {
      return .orange
    } else {
      return .green
    }
  }

  private func loadImage() async {
    guard let imagePath = detection.imagePath else {
      isLoadingImage = false
      return
    }

    do {
      let data = try await supabase.downloadFaceImage(path: imagePath)
      await MainActor.run {
        image = UIImage(data: data)
        isLoadingImage = false
      }
    } catch {
      print("Error loading image: \(error)")
      await MainActor.run {
        isLoadingImage = false
      }
    }
  }
}

// MARK: - Driver Detections View

struct DriverDetectionsView: View {
  let profile: DriverProfile
  let vehicleId: String

  @Environment(\.dismiss) private var dismiss
  @State private var detections: [FaceDetection] = []
  @State private var isLoading = true
  @State private var errorMessage: String?

  private let columns = [
    GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 8)
  ]

  var body: some View {
    NavigationStack {
      Group {
        if isLoading {
          ProgressView("Loading detections...")
        } else if let errorMessage {
          ContentUnavailableView {
            Label("Error", systemImage: "exclamationmark.triangle")
          } description: {
            Text(errorMessage)
          } actions: {
            Button("Retry") {
              Task {
                await loadDetections()
              }
            }
          }
        } else if detections.isEmpty {
          ContentUnavailableView {
            Label("No Detections", systemImage: "face.dashed")
          } description: {
            Text("No detections found for \(profile.name).")
          }
        } else {
          ScrollView {
            VStack(alignment: .leading, spacing: 16) {
              // Profile header
              HStack(spacing: 12) {
                Circle()
                  .fill(Color.blue.opacity(0.2))
                  .frame(width: 60, height: 60)
                  .overlay {
                    Text(profile.name.prefix(1).uppercased())
                      .font(.title)
                      .fontWeight(.semibold)
                      .foregroundStyle(.blue)
                  }

                VStack(alignment: .leading) {
                  Text(profile.name)
                    .font(.title2)
                    .fontWeight(.semibold)
                  Text("\(detections.count) detection\(detections.count == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)
                }
              }
              .padding(.horizontal)

              // Detections grid
              LazyVGrid(columns: columns, spacing: 8) {
                ForEach(detections) { detection in
                  NavigationLink {
                    FaceDetectionDetailView(detection: detection)
                  } label: {
                    FaceDetectionThumbnail(detection: detection)
                  }
                  .buttonStyle(.plain)
                }
              }
              .padding(.horizontal)
            }
            .padding(.vertical)
          }
        }
      }
      .navigationTitle("Driver Detections")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") {
            dismiss()
          }
        }
      }
      .task {
        await loadDetections()
      }
      .refreshable {
        await loadDetections()
      }
    }
  }

  private func loadDetections() async {
    isLoading = true
    errorMessage = nil

    do {
      let fetched = try await supabase.fetchDetectionsForDriver(
        profileId: profile.id, vehicleId: vehicleId)
      await MainActor.run {
        detections = fetched
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

#Preview {
  NavigationStack {
    FaceDetectionsView(
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
}
