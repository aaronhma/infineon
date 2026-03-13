//
//  ShazamHistoryView.swift
//  InfineonProject
//
//  Created by Aaron Ma on 2/6/26.
//

import AaronUI
import SwiftUI

struct ShazamHistoryView: View {
  @Environment(\.dismiss) private var dismiss

  let vehicleId: String

  @State private var musicDetections: [MusicDetection] = []
  @State private var isLoading = true
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      Group {
        if isLoading {
          ProgressView("Loading music history...")
        } else if let errorMessage {
          ContentUnavailableView {
            Label("Failed to Load", systemImage: "exclamationmark.triangle")
          } description: {
            Text(errorMessage)
          } actions: {
            Button("Retry") {
              Task {
                await loadMusicDetections()
              }
            }
            .buttonStyle(.borderedProminent)
          }
        } else {
          List {
            Section {
              HStack {
                Image(systemName: "shazam.logo.fill")
                  .foregroundStyle(.blue.gradient)

                VStack(alignment: .leading) {
                  Text("Shazam has detected \(musicDetections.count) songs on this vehicle.")
                }
              }
            }

            Section {
              if musicDetections.isEmpty {
                ContentUnavailableView {
                  Label("No Songs Detected", systemImage: "music.note")
                } description: {
                  Text("Songs detected by Shazam will appear here")
                }
              }

              ForEach(musicDetections) { detection in
                MusicDetectionRow(detection: detection)
              }
            }
          }
        }
      }
      .navigationTitle("Shazam History")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          CloseButton {
            dismiss()
          }
        }
      }
      .task {
        await loadMusicDetections()
      }
    }
  }

  private func loadMusicDetections() async {
    isLoading = true
    errorMessage = nil

    do {
      musicDetections = try await supabase.fetchMusicDetections(for: vehicleId)
      isLoading = false
    } catch {
      errorMessage = error.localizedDescription
      isLoading = false
    }
  }
}

struct MusicDetectionRow: View {
  let detection: MusicDetection
  @Environment(\.openURL) private var openURL

  var body: some View {
    Button {
      if let shazamUrl = detection.shazamUrl, let url = URL(string: shazamUrl) {
        openURL(url)
      }
    } label: {
      VStack(alignment: .leading, spacing: 8) {
        // Title and artist
        VStack(alignment: .leading, spacing: 2) {
          Text(detection.title)
            .font(.headline)
            .lineLimit(2)

          Text(detection.artist)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }

        // Album and year
        if let album = detection.album {
          VStack(alignment: .leading, spacing: 10) {
            Label(album, systemImage: "opticaldisc")
              .font(.caption)
              .foregroundStyle(.secondary)

            if let year = detection.releaseYear {
              Label(year, systemImage: "calendar")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }

        // Genres
        if let genres = detection.genres, !genres.isEmpty {
          HStack(spacing: 6) {
            ForEach(genres, id: \.self) { genre in
              Text(genre)
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.purple.opacity(0.2))
                .foregroundStyle(.purple)
                .clipShape(.capsule)
            }
          }
        }

        // Detection time
        HStack(spacing: 4) {
          Image(systemName: "clock")
            .font(.caption2)
            .foregroundStyle(.secondary)
          Text("Detected \(detection.detectedAt, style: .relative) ago")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .padding(.vertical, 4)
    }
    .foregroundStyle(.primary)
    .contentShape(Rectangle())
  }
}

#Preview {
  NavigationStack {
    ShazamHistoryView(vehicleId: "test-vehicle")
  }
}

#Preview("Music Row") {
  List {
    MusicDetectionRow(
      detection: MusicDetection(
        id: UUID(),
        vehicleId: "test",
        sessionId: nil,
        title: "Blinding Lights",
        artist: "The Weeknd",
        album: "After Hours",
        releaseYear: "2020",
        genres: ["Pop", "R&B", "Synthwave"],
        label: "XO Records",
        shazamUrl: "https://www.shazam.com/song/1499378607/blinding-lights",
        appleMusicUrl: "https://music.apple.com/us/song/blinding-lights/1488408568",
        spotifyUrl: "https://open.spotify.com/track/0VjIjW4GlUZAMYd2vXMi3b",
        detectedAt: Date().addingTimeInterval(-3600),
        createdAt: Date()
      )
    )

    MusicDetectionRow(
      detection: MusicDetection(
        id: UUID(),
        vehicleId: "test",
        sessionId: nil,
        title: "Bohemian Rhapsody",
        artist: "Queen",
        album: "A Night at the Opera",
        releaseYear: "1975",
        genres: ["Rock", "Progressive Rock"],
        label: nil,
        shazamUrl: "https://www.shazam.com/song/1440650711/bohemian-rhapsody",
        appleMusicUrl: "https://music.apple.com/us/song/bohemian-rhapsody/1440650711",
        spotifyUrl: "https://open.spotify.com/track/7tFiyTwD0nx5a1eklYtX2J",
        detectedAt: Date().addingTimeInterval(-7200),
        createdAt: Date()
      )
    )
  }
}
