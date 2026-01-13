//
//  FaceDetectionsView.swift
//  InfineonProject
//
//  Created by Aaron Ma on 1/13/26.
//

import SwiftUI

struct FaceDetectionsView: View {
    let vehicle: Vehicle

    @State private var detections: [FaceDetection] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 8)
    ]

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
                            await loadDetections()
                        }
                    }
                }
            } else if detections.isEmpty {
                ContentUnavailableView {
                    Label("No Detections", systemImage: "face.dashed")
                } description: {
                    Text("No face detections recorded for this vehicle yet.")
                }
            } else {
                ScrollView {
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
                    .padding()
                }
            }
        }
        .navigationTitle("Face Detections")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadDetections()
        }
        .refreshable {
            await loadDetections()
        }
    }

    private func loadDetections() async {
        isLoading = true
        errorMessage = nil

        do {
            let fetched = try await supabase.fetchFaceDetections(for: vehicle.id)
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

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Image section
                imageSection

                // Metadata sections
                VStack(spacing: 16) {
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
                    .aspectRatio(4/3, contentMode: .fit)
                    .overlay {
                        ProgressView("Loading image...")
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .aspectRatio(4/3, contentMode: .fit)
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
                        Text(sessionId.uuidString.prefix(8) + "...")
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

#Preview {
    NavigationStack {
        FaceDetectionsView(vehicle: Vehicle(
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
