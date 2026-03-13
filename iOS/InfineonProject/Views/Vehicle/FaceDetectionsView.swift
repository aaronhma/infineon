//
//  FaceDetectionsView.swift
//  InfineonProject
//
//  Created by Aaron Ma on 1/13/26.
//

import AaronUI
import SwiftUI

enum DetectionEventFilter: Hashable {
  case all
  case drowsy
  case phone
  case drinking
  case riskScore(Int)

  var displayName: String {
    switch self {
    case .all:
      return "All Events"
    case .drowsy:
      return "Drowsy"
    case .phone:
      return "Phone"
    case .drinking:
      return "Drinking"
    case .riskScore(let score):
      return "Risk \(score)+"
    }
  }

  var icon: String {
    switch self {
    case .all: return "person.crop.rectangle.stack.fill"
    case .drowsy: return "moon.fill"
    case .phone: return "iphone.gen3"
    case .drinking: return "cup.and.saucer.fill"
    case .riskScore: return "exclamationmark.triangle.fill"
    }
  }

  var color: Color {
    switch self {
    case .all: return .blue
    case .drowsy: return .yellow
    case .phone: return .red
    case .drinking: return .orange
    case .riskScore: return .purple
    }
  }
}

struct FaceDetectionsView: View {
  @Environment(\.dismiss) private var dismiss

  let vehicle: Vehicle

  @State private var allDetections: [FaceDetection] = []
  @State private var isLoading = true
  @State private var errorMessage: String?
  @State private var selectedFilter: DetectionEventFilter = .all

  private let columns = [
    GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 8)
  ]

  private var filteredDetections: [FaceDetection] {
    switch selectedFilter {
    case .all:
      return allDetections
    case .drowsy:
      return allDetections.filter { $0.isDrowsy }
    case .phone:
      return allDetections.filter { $0.isPhoneDetected == true }
    case .drinking:
      return allDetections.filter { $0.isDrinkingDetected == true }
    case .riskScore(let minScore):
      return allDetections.filter { $0.intoxicationScore >= minScore }
    }
  }

  private var filterTitle: String {
    selectedFilter.displayName
  }

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
              Task { await loadData() }
            }
          }
        } else if allDetections.isEmpty {
          ContentUnavailableView {
            Label("No Detections", systemImage: "face.dashed")
          } description: {
            Text("No face detections recorded for this vehicle yet.")
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
        ToolbarItem(placement: .topBarLeading) {
          CloseButton {
            dismiss()
          }
        }

        ToolbarItem(placement: .topBarTrailing) {
          Menu {
            Button {
              Haptics.impact()
              selectedFilter = .all
            } label: {
              Label("All Events", systemImage: selectedFilter == .all ? "checkmark" : "")
            }

            Divider()

            // Event type filters
            Button {
              Haptics.impact()
              selectedFilter = .drowsy
            } label: {
              Label("Drowsy", systemImage: "moon.fill")
                .foregroundStyle(.yellow)
            }

            Button {
              Haptics.impact()
              selectedFilter = .phone
            } label: {
              Label("Phone", systemImage: "iphone.gen3")
                .foregroundStyle(.red)
            }

            Button {
              Haptics.impact()
              selectedFilter = .drinking
            } label: {
              Label("Drinking", systemImage: "cup.and.saucer.fill")
                .foregroundStyle(.orange)
            }

            Divider()

            // Risk score filters
            ForEach(0..<6, id: \.self) { score in
              Button {
                Haptics.impact()
                selectedFilter = .riskScore(score)
              } label: {
                Label("Risk \(score)+", systemImage: "exclamationmark.triangle.fill")
                  .foregroundStyle(score >= 4 ? .red : (score >= 2 ? .orange : .green))
              }
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
  }

  private func loadData() async {
    isLoading = true
    errorMessage = nil

    do {
      let fetchedDetections = try await supabase.fetchFaceDetections(for: vehicle.id)
      await MainActor.run {
        allDetections = fetchedDetections
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

  var body: some View {
    ZStack {
      if let imagePath = detection.imagePath {
        ThumbnailImageView(imagePath: imagePath)
      } else {
        ZStack {
          Image(systemName: "person.crop.rectangle.stack.fill")
            .font(.system(size: 30))
            .foregroundStyle(.tertiary)
          Text("No Image")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(width: 100, height: 100)
        .background(.secondary.opacity(0.1))
        .clipShape(.rect(cornerRadius: 8))
      }

      // Detection indicators overlay
      VStack(alignment: .trailing, spacing: 2) {
        if detection.isDrowsy {
          Image(systemName: "moon.fill")
            .font(.system(size: 10))
            .foregroundStyle(.yellow)
        }
        if detection.isPhoneDetected == true {
          Image(systemName: "iphone.gen3")
            .font(.system(size: 10))
            .foregroundStyle(.red)
        }
        if detection.isDrinkingDetected == true {
          Image(systemName: "cup.and.saucer.fill")
            .font(.system(size: 10))
            .foregroundStyle(.orange)
        }
      }
      .padding(4)
      .background(.ultraThinMaterial, in: .rect(cornerRadius: 4))
    }
  }
}

struct ThumbnailImageView: View {
  let imagePath: String
  @State private var imageURL: URL?

  var body: some View {
    Group {
      if let imageURL {
        AsyncImage(url: imageURL) { phase in
          switch phase {
          case .success(let image):
            image
              .resizable()
              .aspectRatio(contentMode: .fill)
              .frame(width: 100, height: 100)
              .clipShape(.rect(cornerRadius: 8))
          case .failure, .empty:
            placeholder
          @unknown default:
            placeholder
          }
        }
      } else {
        placeholder
      }
    }
    .task {
      imageURL = try? await supabase.getFaceImageURL(path: imagePath)
    }
  }

  private var placeholder: some View {
    ZStack {
      Image(systemName: "person.crop.rectangle.stack.fill")
        .font(.system(size: 30))
        .foregroundStyle(.tertiary)
      Text("No Image")
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    .frame(width: 100, height: 100)
    .background(.secondary.opacity(0.1))
    .clipShape(.rect(cornerRadius: 8))
  }
}

struct FaceDetectionDetailView: View {
  let detection: FaceDetection
  @Environment(\.dismiss) private var dismiss

  @State private var imageURL: URL?
  @State private var isLoadingImage = true

  @State private var imageLoadError: String?

  var body: some View {
    List {
      // Image section
      Section {
        if isLoadingImage {
          HStack {
            Spacer()
            ProgressView("Loading image...")
            Spacer()
          }
          .frame(height: 250)
        } else if let imageURL {
          AsyncImage(url: imageURL) { phase in
            switch phase {
            case .success(let image):
              image
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 300)
                .clipShape(.rect(cornerRadius: 12))
            case .failure:
              ContentUnavailableView {
                Label("Image Unavailable", systemImage: "photo")
              } description: {
                Text("Could not load the snapshot")
              }
              .frame(height: 250)
            @unknown default:
              EmptyView()
            }
          }
        } else if let error = imageLoadError {
          ContentUnavailableView {
            Label("No Image", systemImage: "photo")
          } description: {
            Text("No snapshot available for this detection.")
          }
          .frame(height: 250)
        }
      }

      // Detection info
      Section("Detection Info") {
        LabeledContent("Time") {
          Text(detection.createdAt.formatted(.dateTime))
        }

        LabeledContent("Risk Score") {
          Text("\(detection.intoxicationScore)/6")
            .foregroundStyle(
              detection.intoxicationScore >= 4
                ? .red
                : (detection.intoxicationScore >= 2 ? .orange : .green)
            )
        }
      }

      // Detection flags
      Section("Detection Flags") {
        HStack {
          if detection.isDrowsy {
            Label("Drowsy", systemImage: "moon.fill")
              .foregroundStyle(.yellow)
          }
          if detection.isPhoneDetected == true {
            Label("Phone", systemImage: "iphone.gen3")
              .foregroundStyle(.red)
          }
          if detection.isDrinkingDetected == true {
            Label("Drinking", systemImage: "cup.and.saucer.fill")
              .foregroundStyle(.orange)
          }
          if detection.isExcessiveBlinking {
            Label("Excessive Blinking", systemImage: "eye")
              .foregroundStyle(.orange)
          }
          if detection.isUnstableEyes {
            Label("Unstable Eyes", systemImage: "eye.trianglebadge.exclamationmark")
              .foregroundStyle(.red)
          }
        }
      }

      // Location context
      if detection.latitude != nil && detection.longitude != nil {
        Section("Location") {
          LabeledContent("Coordinates") {
            Text(
              "\(detection.latitude!, specifier: "%.4f"), \(detection.longitude!, specifier: "%.4f")"
            )
          }

          if let heading = detection.headingDegrees, let direction = detection.compassDirection {
            LabeledContent("Heading") {
              HStack(spacing: 4) {
                Image(systemName: "location.north.fill")
                  .rotationEffect(.degrees(Double(heading)))
                  .foregroundStyle(.blue)
                Text("\(heading)° \(direction)")
              }
            }
          }
        }
      }
    }
    .navigationTitle("Detection Detail")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        CloseButton {
          dismiss()
        }
      }
    }
    .task {
      await loadImage()
    }
  }

  private func loadImage() async {
    guard let imagePath = detection.imagePath else {
      isLoadingImage = false
      imageLoadError = nil
      return
    }

    do {
      let url = try await supabase.getFaceImageURL(path: imagePath)
      await MainActor.run {
        self.imageURL = url
        self.isLoadingImage = false
      }
    } catch {
      await MainActor.run {
        self.imageLoadError = error.localizedDescription
        self.isLoadingImage = false
      }
    }
  }
}

#Preview {
  NavigationStack {
    FaceDetectionsView(
      vehicle: Vehicle(
        id: "test-vehicle-id",
        createdAt: .now,
        updatedAt: .now,
        name: "Test Vehicle",
        description: nil,
        inviteCode: "TEST123",
        ownerId: UUID(),
        enableYolo: true,
        enableStream: true,
        enableShazam: false,
        enableMicrophone: true,
        enableCamera: true,
        enableDashcam: true
      ))
  }
}
