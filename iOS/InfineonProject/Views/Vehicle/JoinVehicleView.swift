//
//  JoinVehicleView.swift
//  InfineonProject
//
//  Created by Aaron Ma on 1/13/26.
//

import AaronUI
import SwiftUI

struct JoinVehicleView: View {
  @Environment(\.dismiss) private var dismiss

  @State private var inviteCode: String
  @State private var isJoining = false
  @State private var errorMessage: String?

  /// Optional initial invite code to prefill (e.g., from deep link)
  private let initialCode: String?

  init(initialCode: String? = nil) {
    self.initialCode = initialCode
    _inviteCode = State(initialValue: initialCode ?? "")
  }

  private func joinVehicle() {
    guard inviteCode.count == 6 else { return }

    isJoining = true
    errorMessage = nil

    Task {
      try? await Task.sleep(for: .milliseconds(400))

      do {
        let response = try await supabase.joinVehicleByInviteCode(
          inviteCode
        )

        await MainActor.run {
          isJoining = false

          if response.success {
            dismiss()
          } else {
            print(response.error ?? "Unknown error, please try again.")
            errorMessage = "Invalid or expired code."
          }
        }
      } catch {
        await MainActor.run {
          isJoining = false
          errorMessage = "Invalid or expired code."
          print(error.localizedDescription)
        }
      }
    }
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Invite Code", text: $inviteCode)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .font(.system(.title2, design: .monospaced))
            .multilineTextAlignment(.center)
            .onChange(of: inviteCode) { _, newValue in
              inviteCode = String(newValue.uppercased().prefix(6))

              withAnimation(.bouncy) {
                errorMessage = nil
              }
            }
        } header: {
          Text("Enter the invite code")
        } footer: {
          Text(
            "Ask the vehicle owner for the invite code to get access to real-time vehicle data."
          )
        }

        if let errorMessage {
          Section {
            Label(
              errorMessage,
              systemImage: "exclamationmark.triangle.fill"
            )
            .foregroundStyle(.red)
          }
        }

        Section {
          Button {
            Haptics.impact()

            withAnimation(.bouncy) {
              joinVehicle()
            }
          } label: {
            HStack {
              Spacer()

              if isJoining {
                ProgressView()
                  .controlSize(.extraLarge)
              } else {
                Text("Join Vehicle")
                  .bold()
              }

              Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 15)
          }
          .foregroundStyle(.white)
          .bold()
          .possibleGlassEffect(.accentColor, in: .capsule)
          .buttonStyle(.borderedProminent)
          .disabled(inviteCode.count != 6 || isJoining)
          .listRowInsets(EdgeInsets())
        }
      }
      .navigationTitle("Join Vehicle")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        if !supabase.vehicles.isEmpty {
          ToolbarItem(placement: .cancellationAction) {
            CloseButton {
              Haptics.impact()
              dismiss()
            }
          }
        }
      }
    }
  }
}

#Preview {
  JoinVehicleView()
}
