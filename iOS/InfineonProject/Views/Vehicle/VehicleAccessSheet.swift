//
//  VehicleAccessSheet.swift
//  InfineonProject
//
//  Created by Aaron Ma on 1/19/26.
//

import AaronUI
import Supabase
import SwiftUI

struct VehicleAccessSheet: View {
  let vehicle: Vehicle

  @Environment(\.dismiss) private var dismiss

  @State private var accessUsers: [VehicleAccessUser] = []
  @State private var isLoading = true
  @State private var errorMessage: String?
  @State private var showShareAccessViewSheet = false

  private var currentUserId: UUID? {
    supabase.currentUser?.id
  }

  private var isOwner: Bool {
    guard let currentUserId else { return false }
    return vehicle.ownerId == currentUserId
  }

  private var ownerUser: VehicleAccessUser? {
    accessUsers.first { $0.isOwner }
  }

  private var otherUsers: [VehicleAccessUser] {
    accessUsers.filter { !$0.isOwner }
  }

  var body: some View {
    NavigationStack {
      Group {
        if isLoading {
          ProgressView("Loading...")
        } else if let errorMessage {
          ContentUnavailableView {
            Label("Error", systemImage: "exclamationmark.triangle")
          } description: {
            Text(errorMessage)
          } actions: {
            Button("Retry") {
              Task {
                await loadAccessUsers()
              }
            }
          }
        } else {
          List {
            if let owner = ownerUser {
              Section("Owner") {
                AccessUserRow(
                  user: owner,
                  canRemove: false,
                  isSelf: owner.userId == currentUserId,
                  onRemove: {})
              }
            }

            Section {
              if otherUsers.isEmpty {
                Text("No one else has access to this vehicle.")
                  .foregroundStyle(.secondary)
              } else {
                ForEach(otherUsers) { user in
                  let canRemove = isOwner || user.userId == currentUserId
                  AccessUserRow(
                    user: user,
                    canRemove: canRemove,
                    isSelf: user.userId == currentUserId
                  ) {
                    Task { await removeAccess(for: user) }
                  }
                }
              }
            } header: {
              Text("Authorized Drivers")
            } footer: {
              if isOwner {
                Text(
                  "As the owner, you can remove access from anyone."
                )
              } else {
                Text("You can only remove your own access.")
              }
            }
          }
        }
      }
      .navigationTitle("Vehicle Access")
      .sheet(isPresented: $showShareAccessViewSheet) {
        ShareAccessView(vehicle: vehicle)
      }
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          CloseButton {
            dismiss()
          }
        }

        ToolbarItem(placement: .topBarTrailing) {
          Button("Share", systemImage: "square.and.arrow.up") {
            Haptics.impact()
            showShareAccessViewSheet.toggle()
          }
        }
      }
      .task {
        await loadAccessUsers()
      }
      //      .refreshable {
      //        await loadAccessUsers()
      //      }
    }
  }

  private func loadAccessUsers() async {
    isLoading = true
    errorMessage = nil

    do {
      let users = try await supabase.fetchVehicleAccessUsers(
        vehicleId: vehicle.id
      )
      await MainActor.run {
        accessUsers = users
        isLoading = false
      }
    } catch {
      await MainActor.run {
        errorMessage = error.localizedDescription
        isLoading = false
      }
    }
  }

  private func removeAccess(for user: VehicleAccessUser) async {
    do {
      if user.userId == currentUserId {
        try await supabase.leaveVehicle(vehicle.id)
        await MainActor.run { dismiss() }
      } else {
        try await supabase.removeUserAccess(vehicleId: vehicle.id, userId: user.userId)
        await loadAccessUsers()
      }
    } catch {
      await MainActor.run { errorMessage = error.localizedDescription }
    }
  }
}

struct AccessUserRow: View {
  let user: VehicleAccessUser
  let canRemove: Bool
  let isSelf: Bool
  let onRemove: () -> Void

  @State private var avatarImage: UIImage?
  @State private var showingConfirmation = false

  var body: some View {
    HStack(spacing: 12) {
      Group {
        if let avatarImage {
          Image(uiImage: avatarImage)
            .resizable()
            .aspectRatio(contentMode: .fill)
        } else {
          Circle()
            .fill(Color.blue.opacity(0.2))
            .overlay {
              Text(initials)
                .font(.headline)
                .foregroundStyle(.blue)
            }
        }
      }
      .frame(width: 44, height: 44)
      .clipShape(.circle)

      VStack(alignment: .leading, spacing: 2) {
        Text(user.displayName ?? user.email ?? "Unknown User")
          .font(.body)

        if user.isOwner {
          Text("Owner")
            .font(.caption)
            .foregroundStyle(.secondary)
        } else if let email = user.email, user.displayName != nil {
          Text(email)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Spacer()

      if canRemove {
        Button {
          Haptics.impact()
          showingConfirmation = true
        } label: {
          Image(systemName: "minus.circle.fill")
            .foregroundStyle(.red)
        }
        .buttonStyle(.plain)
      }
    }
    .confirmationDialog(
      isSelf ? "Leave Vehicle" : "Remove Access",
      isPresented: $showingConfirmation
    ) {
      Button(isSelf ? "Leave Vehicle" : "Remove", role: .destructive) {
        onRemove()
      }
    } message: {
      if isSelf {
        Text("Are you sure you want to leave this vehicle? You will need an invite code to rejoin.")
      } else {
        Text(
          "Are you sure you want to remove \(user.displayName ?? user.email ?? "this user")'s access?"
        )
      }
    }
    .task {
      await loadAvatar()
    }
  }

  private var initials: String {
    if let displayName = user.displayName, !displayName.isEmpty {
      return String(displayName.prefix(1)).uppercased()
    } else if let email = user.email, !email.isEmpty {
      return String(email.prefix(1)).uppercased()
    }
    return "?"
  }

  private func loadAvatar() async {
    guard let avatarPath = user.avatarPath else { return }

    do {
      let url = try supabase.client.storage.from("user-avatars").getPublicURL(
        path: avatarPath
      )
      let (data, _) = try await URLSession.shared.data(from: url)
      await MainActor.run {
        avatarImage = UIImage(data: data)
      }
    } catch {
      print("Error loading avatar: \(error)")
    }
  }
}

#Preview {
  VehicleAccessSheet(
    vehicle: Vehicle(
      id: "test",
      createdAt: .now,
      updatedAt: .now,
      name: "Test Vehicle",
      description: nil,
      inviteCode: "ABC123",
      ownerId: nil
    )
  )
}
