//
//  OnboardingView.swift
//  InfineonProject
//
//  Created by Aaron Ma on 1/17/26.
//

import AVKit
import AaronUI
import AuthenticationServices
import Supabase
import SwiftUI

struct GradientView: View {
  var fromBottom: Bool

  var body: some View {
    ForEach(0..<3) { _ in
      UnevenRoundedRectangle(bottomLeadingRadius: 55, bottomTrailingRadius: 55, style: .continuous)
        .frame(height: 450)
    }
    .foregroundStyle(
      LinearGradient(
        gradient: Gradient(stops: [
          .init(color: .clear, location: 0.0), .init(color: .black.opacity(0.7), location: 1),
        ]), startPoint: .top, endPoint: .bottom)
    )
    .scaleEffect(y: fromBottom ? 1 : -1)
  }
}

struct GetStartedView: View {
  @Environment(\.colorScheme) private var colorScheme

  var height = CGFloat(300)

  @State private var isSigningIn = false
  @State private var errorMessage: String?
  @State private var authCoordinator: Coordinator?

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

        // Extract full name from Apple credential (only provided on first sign-in)
        var fullName: String?
        if let nameComponents = credential.fullName {
          let formatter = PersonNameComponentsFormatter()
          formatter.style = .default
          let formattedName = formatter.string(from: nameComponents)
          if !formattedName.isEmpty {
            fullName = formattedName
          }
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
          email: response.user.email ?? "",
          fullName: fullName
        )

        print("full name: \(fullName)")

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

  private func handleSignIn() {
    let provider = ASAuthorizationAppleIDProvider()
    let request = provider.createRequest()
    request.requestedScopes = [.fullName, .email]

    let coordinator = Coordinator(onCompletion: handleSignInResult)
    authCoordinator = coordinator

    let controller = ASAuthorizationController(authorizationRequests: [request])
    controller.delegate = coordinator
    controller.presentationContextProvider = coordinator
    controller.performRequests()
  }

  class Coordinator: NSObject, ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding
  {
    let onCompletion: (Result<ASAuthorization, Error>) -> Void

    init(onCompletion: @escaping (Result<ASAuthorization, Error>) -> Void) {
      self.onCompletion = onCompletion
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
      guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
        let window = scene.windows.first
      else {
        return ASPresentationAnchor()
      }
      return window
    }

    func authorizationController(
      controller: ASAuthorizationController,
      didCompleteWithAuthorization authorization: ASAuthorization
    ) {
      onCompletion(.success(authorization))
    }

    func authorizationController(
      controller: ASAuthorizationController,
      didCompleteWithError error: Error
    ) {
      onCompletion(.failure(error))
    }
  }

  var body: some View {
    ZStack {
      Button {
        handleSignIn()
      } label: {
        RoundedRectangle(cornerRadius: 55, style: .continuous)
          .frame(height: height)
          .foregroundStyle(
            LinearGradient(
              gradient: Gradient(colors: [.white]),
              startPoint: .leading,
              endPoint: .trailing)
          )
          .overlay(alignment: .top) {
            Group {
              if isSigningIn {
                ProgressView()
                  .controlSize(.extraLarge)
                  .tint(.white)
              } else {
                HStack {
                  Image(systemName: "apple.logo")
                  Text("Continue with Apple")
                }
                .foregroundStyle(.black)
                .font(.title2)
                .bold()
              }
            }
            .padding(.top, 60)
          }
      }
      .buttonStyle(.plain)
    }
    .alert(
      "Sign In Error",
      isPresented: .init(
        get: { errorMessage != nil },
        set: { if !$0 { errorMessage = nil } }
      )
    ) {
      Button("OK") {
        errorMessage = nil
      }
    } message: {
      if let errorMessage {
        Text(errorMessage)
      }
    }
  }
}

struct DataModel: Identifiable {
  var id = UUID()
  var video: String
  var title: String
  var description: String
}

private let videos: [DataModel] = [
  .init(
    video: "driving", title: "Infineon Special Project",
    description: "Track driving drowsiness in real-time"),
  .init(
    video: "vantage", title: "Get there, safely",
    description: "You'll get notified of any infractions"),
  .init(
    video: "walking", title: "Let's go",
    description: "By continuing, you agree to our Terms and Privacy Policy."),
]

struct OnboardingView: View {
  @State private var finalOffset = CGFloat.zero
  @State private var currentDrag = CGFloat.zero
  @State private var lastView = CGFloat.zero

  var body: some View {
    GeometryReader { geo in
      let imageHeight = geo.size.height / 1.2

      VStack(spacing: 8) {
        ForEach(videos.indices, id: \.self) { idx in
          let video = videos[idx]

          ZStack(alignment: .top) {
            LoopingPlayerView(videoName: video.video, videoType: "mp4")
              .frame(width: geo.size.width, height: imageHeight)
              .clipShape(.rect(cornerRadius: 55, style: .continuous))
              .overlay(alignment: .bottom) {
                ZStack(alignment: .bottom) {
                  GradientView(fromBottom: true)

                  VStack {
                    Text(video.title)
                      .font(.title)
                      .fontWidth(.expanded)
                      .multilineTextAlignment(.center)
                      .offset(y: -5)

                    Text(video.description)
                      .multilineTextAlignment(.center)
                      .opacity(0.7)
                      .padding(.horizontal, 30)
                  }
                  .bold()
                  .foregroundStyle(.white)
                  .padding(.bottom, 35)
                  .padding(.horizontal)
                }
              }
              .overlay(alignment: .top) {
                if idx != 0 {
                  let progress = -(finalOffset + currentDrag) / (imageHeight + 10)
                  let isPastLast = progress > CGFloat(videos.count - 1)
                  let opacity = isPastLast ? 0 : max(0, min(1, abs(progress - CGFloat(idx))))

                  ZStack(alignment: .top) {
                    GradientView(fromBottom: false)

                    Text("Continue")
                      .bold()
                      .font(.title2)
                      .foregroundStyle(.white)
                      .padding(.top, 60)
                      .onTapGesture {
                        Haptics.impact()
                        finalOffset -= imageHeight + 10
                      }
                  }
                  .opacity(opacity)
                }
              }
          }
        }

        GetStartedView(height: 250 + abs(currentDrag))
      }
      .background(.black)
      .offset(y: finalOffset + currentDrag)
      .animation(.smooth, value: finalOffset)
      .animation(.smooth, value: currentDrag)
      .gesture(
        DragGesture(minimumDistance: 10)
          .onChanged { value in
            let nextOffset = finalOffset + value.translation.height
            let maxOffset = CGFloat.zero
            let minOffset = -CGFloat(videos.count - 1) * (imageHeight + 10)
            let isOverTop = nextOffset > maxOffset
            let isOverBottom = nextOffset < minOffset

            if isOverTop || isOverBottom {
              currentDrag = value.translation.height / 5
            } else {
              currentDrag = value.translation.height
            }
          }
          .onEnded { value in
            let nextOffset = finalOffset - (imageHeight + 10)

            if value.translation.height < -100 && nextOffset >= -lastView {
              finalOffset = nextOffset
            } else if value.translation.height > 100 {
              if finalOffset + imageHeight <= 0 {
                finalOffset += imageHeight + 10
              } else {
                finalOffset = 0
              }
            }

            Haptics.impact()

            currentDrag = 0
          }
      )
      .onAppear {
        let height = geo.size.height / 1.2
        lastView = CGFloat(videos.count - 1) * (height + 10)
      }
    }
    .ignoresSafeArea()
  }
}

#Preview {
  OnboardingView()
}
