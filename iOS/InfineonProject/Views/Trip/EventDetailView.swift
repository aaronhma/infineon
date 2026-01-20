//
//  EventDetailView.swift
//  InfineonProject
//
//  Created by Aaron Ma on 1/20/26.
//

import SwiftUI

struct EventDetailView: View {
  let event: FaceDetection
  let eventType: TripEventDetail.EventType

  @State private var imageURL: URL?
  @State private var isLoadingImage = true
  @State private var imageLoadError: String?

  private var eventTitle: String {
    "\(eventType.displayName) Event"
  }

  private var eventIcon: String {
    eventType.icon
  }

  private var eventColor: Color {
    eventType.color
  }

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
            case .empty:
              ProgressView()
                .frame(height: 250)
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
          .listRowInsets(EdgeInsets())
        } else if let error = imageLoadError {
          ContentUnavailableView {
            Label("Error", systemImage: "exclamationmark.triangle")
          } description: {
            Text(error)
          }
          .frame(height: 250)
        }
      }

      // Event info section
      Section("Event Details") {
        LabeledContent("Time") {
          Text(event.createdAt.formatted(.dateTime))
        }

        LabeledContent("Event Type") {
          Label(eventTitle, systemImage: eventIcon)
            .foregroundStyle(eventColor)
        }

        LabeledContent("Risk Score") {
          Text("\(event.intoxicationScore)/6")
            .foregroundStyle(riskScoreColor)
        }
      }

      // Eye state section
      Section("Eye Analysis") {
        if let leftState = event.leftEyeState {
          LabeledContent("Left Eye") {
            HStack {
              Text(leftState)
              if let ear = event.leftEyeEar {
                Text("(\(ear, specifier: "%.3f"))")
                  .foregroundStyle(.secondary)
              }
            }
          }
        }

        if let rightState = event.rightEyeState {
          LabeledContent("Right Eye") {
            HStack {
              Text(rightState)
              if let ear = event.rightEyeEar {
                Text("(\(ear, specifier: "%.3f"))")
                  .foregroundStyle(.secondary)
              }
            }
          }
        }

        if let avgEar = event.avgEar {
          LabeledContent("Average EAR") {
            Text(avgEar, format: .number.precision(.fractionLength(4)))
          }
        }
      }

      // Indicators section
      Section("Detection Indicators") {
        indicatorRow("Drowsy", isActive: event.isDrowsy, icon: "moon.fill", color: .yellow)
        indicatorRow(
          "Excessive Blinking", isActive: event.isExcessiveBlinking, icon: "eye", color: .orange)
        indicatorRow(
          "Unstable Eyes", isActive: event.isUnstableEyes,
          icon: "eye.trianglebadge.exclamationmark",
          color: .red)
      }

      // Driving context section
      if event.speedMph != nil || event.compassDirection != nil {
        Section("Driving Context") {
          if let speed = event.speedMph {
            LabeledContent("Speed") {
              HStack {
                Text("\(speed) mph")
                if event.isSpeeding == true {
                  Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                }
              }
            }
          }

          if let heading = event.headingDegrees, let direction = event.compassDirection {
            LabeledContent("Heading") {
              Text("\(heading)° \(direction)")
            }
          }
        }
      }

      // Technical section
      Section("Technical Info") {
        if let imagePath = event.imagePath {
          LabeledContent("Image Path") {
            Text(imagePath)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(2)
          }
        }

        LabeledContent("Event ID") {
          Text(event.id.uuidString.prefix(8) + "...")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
    .navigationTitle(eventTitle)
    .navigationBarTitleDisplayMode(.inline)
    .task {
      await loadImage()
    }
  }

  @ViewBuilder
  private func indicatorRow(_ title: String, isActive: Bool, icon: String, color: Color)
    -> some View
  {
    HStack {
      Image(systemName: icon)
        .foregroundStyle(isActive ? color : .secondary)

      Text(title)

      Spacer()

      if isActive {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(color)
      } else {
        Image(systemName: "circle")
          .foregroundStyle(.secondary)
      }
    }
  }

  private var riskScoreColor: Color {
    if event.intoxicationScore >= 4 {
      return .red
    } else if event.intoxicationScore >= 2 {
      return .orange
    } else {
      return .green
    }
  }

  private func loadImage() async {
    guard let imagePath = event.imagePath else {
      await MainActor.run {
        isLoadingImage = false
        imageLoadError = "No image available"
      }
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

// Make FaceDetection conform to Hashable for NavigationLink
extension FaceDetection: Hashable {
  static func == (lhs: FaceDetection, rhs: FaceDetection) -> Bool {
    lhs.id == rhs.id
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}

#Preview {
  NavigationStack {
    EventDetailView(
      event: FaceDetection(
        id: UUID(),
        createdAt: .now,
        vehicleId: "test",
        driverProfileId: nil,
        faceBbox: nil,
        leftEyeState: "CLOSED",
        leftEyeEar: 0.15,
        rightEyeState: "CLOSED",
        rightEyeEar: 0.14,
        avgEar: 0.145,
        isDrowsy: true,
        isExcessiveBlinking: false,
        isUnstableEyes: true,
        intoxicationScore: 4,
        speedMph: 72,
        headingDegrees: 45,
        compassDirection: "NE",
        isSpeeding: true,
        imagePath: "test/path.jpg",
        sessionId: UUID()
      ),
      eventType: .drowsiness
    )
  }
}
