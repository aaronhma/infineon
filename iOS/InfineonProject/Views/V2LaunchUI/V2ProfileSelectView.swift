//
//  V2ProfileSelectView.swift
//  InfineonProject
//
//  Created by Aaron Ma on 1/16/26.
//

import SwiftUI

struct RectAnchorKey: PreferenceKey {
  static var defaultValue: [String: Anchor<CGRect>] = [:]
  static func reduce(
    value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]
  ) {
    value.merge(nextValue()) { $1 }
  }
}

struct RectKey: PreferenceKey {
  static var defaultValue: CGRect = .zero
  static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
    value = nextValue()
  }
}

struct AnimatedPositionModifier: ViewModifier, Animatable {
  var source: CGPoint
  var center: CGPoint
  var destination: CGPoint
  var animateToCenter: Bool
  var animateToMainView: Bool
  var path: Path
  var progress: CGFloat

  var animatableData: CGFloat {
    get { progress }
    set { progress = newValue }
  }

  func body(content: Content) -> some View {
    content
      .position(
        animateToCenter
          ? animateToMainView
            ? (path.trimmedPath(from: 0, to: progress).currentPoint ?? center) : center : source)
  }
}

struct V2ProfileSelectView: View {
  @Environment(V2AppData.self) private var appData
  @State private var animateToCenter = false
  @State private var animateToMainView = false
  @State private var progress = CGFloat.zero

  func prefetchStatus() async {
    try? await Task.sleep(for: .seconds(1))
  }

  func animateCard() async {
    withAnimation(.bouncy(duration: 0.35)) {
      animateToCenter = true
    }

    await prefetchStatus()

    withAnimation(.snappy(duration: 0.6, extraBounce: 0.1), completionCriteria: .removed) {
      animateToMainView = true
      progress = 0.97
    } completion: {
    }
  }

  var body: some View {
    VStack {
      Button("Edit") {

      }
      .frame(maxWidth: .infinity, alignment: .trailing)
      .overlay {
        Text("Who's watching?")
          .font(.title3.bold())
      }

      LazyVGrid(columns: Array(repeating: GridItem(.fixed(100), spacing: 25), count: 2)) {
        ForEach(mockProfiles) { profile in
          profileCard(profile)
        }

        Button {
        } label: {
          ZStack {
            RoundedRectangle(cornerRadius: 10)
              .stroke(.white.opacity(0.8), lineWidth: 0.8)

            Image(systemName: "plus")
              .font(.largeTitle)
              .foregroundStyle(.white)
          }
          .frame(width: 100, height: 100)
          .contentShape(.rect)
        }
      }
      .frame(maxHeight: .infinity)
    }
    .padding(15)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .opacity(animateToCenter ? 0 : 1)
    .background(.black)
    .opacity(animateToMainView ? 0 : 1)
    .overlayPreferenceValue(RectAnchorKey.self) { value in
      animationLayerView(value)
    }
  }

  @ViewBuilder
  private func animationLayerView(_ value: [String: Anchor<CGRect>]) -> some View {
    GeometryReader { proxy in
      if let profile = appData.watchingProfile, let sourceAnchor = value[profile.sourceAnchorID],
        appData.animateProfile
      {
        let sRect = proxy[sourceAnchor]
        let screenRect = proxy.frame(in: .global)

        let sourcePosition = CGPoint(x: sRect.midX, y: sRect.midY)
        let centerPosition = CGPoint(x: screenRect.width / 2, y: (screenRect.height / 2) - 40)
        let destinationPosition = CGPoint(
          x: appData.tabProfileRect.midX, y: appData.tabProfileRect.midY)

        let animationPath = Path { path in
          path.move(to: sourcePosition)
          path.addQuadCurve(
            to: destinationPosition,
            control: CGPoint(
              x: centerPosition.x * 2, y: centerPosition.y - (centerPosition.y / 0.8)))
        }

        animationPath.stroke(lineWidth: 2)

        let endPosition =
          animationPath.trimmedPath(from: 0, to: 1).currentPoint ?? destinationPosition
        let currentPosition =
          animationPath.trimmedPath(from: 0, to: 0.97).currentPoint ?? destinationPosition

        let diff = CGSize(
          width: endPosition.x - currentPosition.x, height: endPosition.y - currentPosition.y)

        ZStack {
          Image(profile.icon)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(
              width: animateToMainView ? 25 : sRect.width,
              height: animateToMainView ? 25 : sRect.height
            )
            .clipShape(.rect(cornerRadius: animateToMainView ? 4 : 10))
            .modifier(
              AnimatedPositionModifier(
                source: sourcePosition, center: centerPosition, destination: destinationPosition,
                animateToCenter: animateToCenter, animateToMainView: animateToMainView,
                path: animationPath, progress: progress)
            )
            .offset(animateToMainView ? diff : .zero)

          V2LoadingView()
            .frame(width: 60, height: 60)
            .offset(y: 80)
            .opacity(animateToCenter ? 1 : 0)
        }
        .transition(.identity)
        .task {
          guard !animateToCenter else { return }

          await animateCard()
        }
      }
    }
  }

  @ViewBuilder
  private func profileCard(_ profile: V2Profile) -> some View {
    VStack(spacing: 8) {
      let status = profile.id == appData.watchingProfile?.id

      GeometryReader { _ in
        Image(profile.icon)
          .resizable()
          .aspectRatio(contentMode: .fill)
          .frame(width: 100, height: 100)
          .clipShape(.rect(cornerRadius: 10))
          .opacity(animateToCenter ? 0 : 1)
      }
      .animation(status ? .none : .bouncy(duration: 0.35), value: animateToCenter)
      .frame(width: 100, height: 100)
      .anchorPreference(
        key: RectAnchorKey.self, value: .bounds,
        transform: { anchor in
          return [profile.sourceAnchorID: anchor]
        }
      )
      .onTapGesture {
        appData.watchingProfile = profile
        appData.animateProfile = true
      }

      Text(profile.name)
        .fontWeight(.semibold)
        .lineLimit(1)
    }
  }
}

#Preview {
  V2ProfileSelectView()
    .environment(V2AppData())
    .preferredColorScheme(.dark)
}
