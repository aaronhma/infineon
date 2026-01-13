//
//  AuthView.swift
//  InfineonProject
//
//  Created by Aaron Ma on 1/13/26.
//

import SwiftUI
import AuthenticationServices
import Supabase

struct AuthView: View {
    @State private var isSigningIn = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()

            VStack {
                LinearGradient(
                    colors: [.black, .black.opacity(0.8), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 250)
                Spacer()
                LinearGradient(
                    colors: [.clear, .black.opacity(0.8), .black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 250)
            }
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading) {
                    Text("Infineon Project")
                        .bold()
                        .font(.largeTitle)
                        .fontDesign(.serif)
                        .foregroundStyle(.white)

                    Text("Driver Safety Monitor")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }

                Spacer()

                VStack(spacing: 16) {
                    Text("Sign in to manage your car's drivers.")
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    if isSigningIn {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                            .frame(height: 55)
                    } else {
                        SignInWithAppleButton(.continue) { request in
                            request.requestedScopes = [.email, .fullName]
                        } onCompletion: { result in
                            handleSignInResult(result)
                        }
                        .frame(height: 55)
                        .signInWithAppleButtonStyle(.white)
                        .clipShape(.capsule)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 50)
        }
    }

    private func handleSignInResult(_ result: Result<ASAuthorization, Error>) {
        Task {
            do {
                guard
                    let credential = try result.get().credential as? ASAuthorizationAppleIDCredential
                else {
                    await MainActor.run {
                        errorMessage = "Invalid credentials"
                    }
                    return
                }

                guard
                    let idToken = credential.identityToken
                        .flatMap({ String(data: $0, encoding: .utf8) })
                else {
                    await MainActor.run {
                        errorMessage = "Could not get identity token"
                    }
                    return
                }

                await MainActor.run {
                    isSigningIn = true
                    errorMessage = nil
                    supabase.isLoading = true
                }

                let response = try await supabase.client.auth.signInWithIdToken(
                    credentials: .init(
                        provider: .apple,
                        idToken: idToken
                    )
                )

                // Wait for user to be loaded
                await supabase.loadOrCreateUser(
                    userId: response.user.id,
                    email: response.user.email ?? ""
                )

                await MainActor.run {
                    isSigningIn = false
                    supabase.isLoading = false
                }
            } catch {
                await MainActor.run {
                    isSigningIn = false
                    supabase.isLoading = false
                    errorMessage = error.localizedDescription
                }
                print("Sign in error: \(error)")
            }
        }
    }
}

#Preview {
    AuthView()
}
