//
//  JoinVehicleView.swift
//  InfineonProject
//
//  Created by Aaron Ma on 1/13/26.
//

import SwiftUI

struct JoinVehicleView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var inviteCode = ""
    @State private var isJoining = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

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
                            // Limit to 6 characters and uppercase
                            inviteCode = String(newValue.uppercased().prefix(6))
                        }
                } header: {
                    Text("Enter the 6-digit invite code")
                } footer: {
                    Text("Ask the vehicle owner for the invite code to get access to real-time vehicle data.")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                if let successMessage {
                    Section {
                        Label(successMessage, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                Section {
                    Button {
                        joinVehicle()
                    } label: {
                        HStack {
                            Spacer()
                            if isJoining {
                                ProgressView()
                                    .progressViewStyle(.circular)
                            } else {
                                Text("Join Vehicle")
                                    .bold()
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(inviteCode.count != 6 || isJoining)
                    .listRowInsets(EdgeInsets())
                }
            }
            .navigationTitle("Join Vehicle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func joinVehicle() {
        guard inviteCode.count == 6 else { return }

        isJoining = true
        errorMessage = nil
        successMessage = nil

        Task {
            do {
                let response = try await supabase.joinVehicleByInviteCode(inviteCode)

                await MainActor.run {
                    isJoining = false

                    if response.success {
                        successMessage = "Successfully joined \(response.vehicleName ?? "vehicle")!"
                        // Dismiss after a short delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            dismiss()
                        }
                    } else {
                        errorMessage = response.error ?? "Failed to join vehicle"
                    }
                }
            } catch {
                await MainActor.run {
                    isJoining = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

#Preview {
    JoinVehicleView()
}
