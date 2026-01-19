//
//  ProfileSetupView.swift
//  InfineonProject
//
//  Created by Aaron Ma on 1/19/26.
//

import AaronUI
import SwiftUI

struct OnboardingProgressView: View {
  @Binding var current: Int
  var total: Int
  var cornerRadius = CGFloat(32)

  var body: some View {
    GeometryReader {
      let width = $0.size.width

      ZStack(alignment: .trailing) {
        RoundedRectangle(cornerRadius: cornerRadius)
          .fill(.gray)

        LinearGradient(
          colors: [
            .green,
            .orange,
            .indigo,
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
        .mask {
          HStack {
            RoundedRectangle(cornerRadius: cornerRadius)
              .frame(
                width: CGFloat(current) / CGFloat(total) * width
              )

            if current != total {
              Spacer()
            }
          }
        }
        .animation(.easeInOut, value: current)
      }
    }
    .frame(height: 10)
    .padding(.horizontal)
  }
}

struct AirBrowserAIFeature: Identifiable {
  var id = UUID()
  var name: String
  var icon: String
  var description: String
  var isEnabled: Bool
}

struct ProfileSetupView: View {
  @State private var currentTab = TabOptions.name

  @State private var name = "d"

  @State private var enabledAirAIFeatures = [
    AirBrowserAIFeature(
      name: "Unidentified Face",
      icon: "faceid",
      description: "Notify when a new driver is detected",
      isEnabled: true
    ),
    AirBrowserAIFeature(
      name: "Collision",
      icon: "car.side.rear.and.collision.and.car.side.front",
      description: "Notify when a car crash is detected",
      isEnabled: true
    ),
    AirBrowserAIFeature(
      name: "Driver Drowsiness",
      icon: "eye.half.closed",
      description: "Notify when the driver is drowsy",
      isEnabled: true
    ),
    AirBrowserAIFeature(
      name: "Follow Speed Limit",
      icon: "gauge.with.dots.needle.100percent",
      description:
        "Notify when speed limit is exceeded",
      isEnabled: true
    ),
    AirBrowserAIFeature(
      name: "Drunk Driving",
      icon: "wineglass.fill",
      description: "Notify when alcohol or drink driving is detected",
      isEnabled: true
    ),
    AirBrowserAIFeature(
      name: "FSD",
      icon: "car.side.fill",
      description:
        "Notify when FSD is engaged or disengaged",
      isEnabled: true
    ),
  ]

  private enum TabOptions: Int, CaseIterable {
    case name = 1
    case chooseNotifications = 2
    case allowNotifications = 3
  }

  private var currentStepUncompleted: Bool {
    switch currentTab {
    case .name:
      name.isEmpty
    case .chooseNotifications:
      false
    case .allowNotifications:
      false
    }
  }

  var body: some View {
    if currentTab != .allowNotifications {
      HStack {
        Group {
          if currentTab.rawValue > 1 {
            Button {
              if let prev = TabOptions(
                rawValue: currentTab.rawValue - 1
              ) {
                withAnimation(.bouncy) {
                  currentTab = prev
                }
              }
            } label: {
              Image(systemName: "chevron.left")
            }
            .bold()
            .foregroundStyle(.primary)
          }
        }
        .transition(.blurReplace)

        OnboardingProgressView(
          current: .constant(currentTab.rawValue),
          total: TabOptions.allCases.count
        )

        Text("\(currentTab.rawValue)/\(TabOptions.allCases.count)")
          .foregroundStyle(.secondary)
          .contentTransition(.numericText(value: 0))
      }
      .padding(.horizontal)
    }

    Group {
      switch currentTab {
      case .name:
        nameView()
      case .chooseNotifications:
        chooseNotificationsView()
      case .allowNotifications:
        AllowNotificationsView(
          config: NotificationConfig(
            title: "Stay connected", content: "Get notified when important events happen",
            notificationTitle: "YO WHATS UP", notificationContent: "CLICK ME OR ELSE",
            primaryButtonTitle: "continue", secondaryButtonTitle: "skip for now"),
          fontDesignStyle: .expanded
        ) {
          Image(.benji)
            .resizable()
            .frame(width: 40, height: 40)
            .clipShape(.rect(cornerRadius: 12))
        } onPermissionChange: { isApproved in
        } onPrimaryButtonTap: {
        } onSecondaryButtonTap: {
        }
      }
    }
    .transition(.blurReplace)
    .frame(maxWidth: .infinity)
    .frame(maxHeight: .infinity)
    .overlay(alignment: .bottom) {
      if currentTab != .allowNotifications {
        AaronButtonView(
          text: "continue",
          disabled: currentStepUncompleted
        ) {
          if let next = TabOptions(
            rawValue: currentTab.rawValue + 1
          ) {
            withAnimation(.bouncy) {
              currentTab = next
            }
          }
        }
        .padding(.horizontal)
      }
    }
  }

  @ViewBuilder
  private func nameView() -> some View {
    ScrollView {
      VStack(alignment: .leading) {
        Text("what should we call you?")
          .fontWidth(.expanded)
          .bold()
          .font(.title)
          .multilineTextAlignment(.leading)
          .padding(.horizontal)

        VStack {
          Image(.benji)
            .resizable()
            .scaledToFit()
            .frame(width: 50, height: 50)

          TextField("your name", text: $name)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .multilineTextAlignment(.center)

        Spacer(minLength: 0)
      }
    }
  }

  @ViewBuilder
  private func chooseNotificationsView() -> some View {
    ScrollView {
      VStack(alignment: .leading) {
        Text("fire...when should we notify you?")
          .fontWidth(.expanded)
          .bold()
          .font(.title)
          .multilineTextAlignment(.leading)
          .padding(.horizontal)

        ForEach($enabledAirAIFeatures) { $i in
          VStack(alignment: .leading) {
            Toggle(isOn: $i.isEnabled) {
              Label {
                Text(i.name)
                  .bold()
              } icon: {
                SettingsBoxView(icon: i.icon, color: .indigo)
              }
            }
            .id($i.id)

            Text(i.description)
              .padding(.top, 5)
              .foregroundStyle(.secondary)
          }
          .padding(.vertical, 5)

          if i.name != "FSD" {
            Divider()
          }
        }
        .padding(.horizontal)

        Spacer(minLength: 0)
      }
    }
  }
}

#Preview {
  ProfileSetupView()
}
