//
//  ShazamHistoryView.swift
//  InfineonProject
//
//  Created by Aaron Ma on 2/6/26.
//

import SwiftUI

struct ShazamHistoryView: View {
  let vehicleId: String

  @State private var musicDetections: [MusicDetection] = []
  @State private var isLoading = true
  @State private var errorMessage: String?

  var body: some View {
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
    .task {
      await loadMusicDetections()
    }
    .refreshable {
      await loadMusicDetections()
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

  @State private var artworkURL: URL?

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      // Album art
      //      AsyncImage(url: artworkURL) { phase in
      //        switch phase {
      //        case .empty:
      //          ZStack {
      //            RoundedRectangle(cornerRadius: 8)
      //              .fill(Color.purple.opacity(0.2))
      //              .frame(width: 80, height: 80)
      //
      //            ProgressView()
      //              .tint(.purple)
      //          }
      //        case .success(let image):
      //          image
      //            .resizable()
      //            .aspectRatio(contentMode: .fill)
      //            .frame(width: 80, height: 80)
      //            .clipShape(RoundedRectangle(cornerRadius: 8))
      //        case .failure:
      //          ZStack {
      //            RoundedRectangle(cornerRadius: 8)
      //              .fill(Color.purple.opacity(0.2))
      //              .frame(width: 80, height: 80)
      //
      //            Image(systemName: "music.note")
      //              .font(.title2)
      //              .foregroundStyle(.purple)
      //          }
      //        @unknown default:
      //          ZStack {
      //            RoundedRectangle(cornerRadius: 8)
      //              .fill(Color.purple.opacity(0.2))
      //              .frame(width: 80, height: 80)
      //
      //            Image(systemName: "music.note")
      //              .font(.title2)
      //              .foregroundStyle(.purple)
      //          }
      //        }
      //      }
      Image("benji")
        .resizable()
        .aspectRatio(contentMode: .fill)
        .frame(width: 80, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 8))

      // Song information
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

        // Links
        VStack(alignment: .leading, spacing: 12) {
          if let shazamUrl = detection.shazamUrl, let url = URL(string: shazamUrl) {
            Link(destination: url) {
              HStack {
                Image(systemName: "waveform.circle.fill")
                Text("Shazam")
              }
              .font(.caption)
              .foregroundStyle(.blue)
            }
          }

          if let appleMusicUrl = detection.appleMusicUrl, let url = URL(string: appleMusicUrl) {
            Link(destination: url) {
              HStack {
                Image(systemName: "applelogo")
                Text("Apple Music")
              }
              .font(.caption)
              .foregroundStyle(.red)
            }
          }

          if let spotifyUrl = detection.spotifyUrl, let url = URL(string: spotifyUrl) {
            Link(destination: url) {
              HStack {
                Image(systemName: "play.circle.fill")
                Text("Spotify")
              }
              .font(.caption)
              .foregroundStyle(.green)
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
    }
    .padding(.vertical, 4)
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
