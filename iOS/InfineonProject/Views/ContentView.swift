//
//  ContentView.swift
//  InfineonProject
//
//  Created by Aaron Ma on 1/12/26.
//

import SwiftUI

struct ContentView: View {
  @State private var searchText = ""
  @State private var showingCurrentSessionFullScreenCover = false

  @Namespace private var namespace

  private var transitionID = "com.aaronhma.InfineonProject.ContentView.transitionID"

  var body: some View {
    Group {
      if #available(iOS 26, *) {
        tabView()
          .tabBarMinimizeBehavior(.onScrollDown)
          .tabViewBottomAccessory {
            accessoryView()
              .matchedTransitionSource(id: transitionID, in: namespace)
              .onTapGesture {
                showingCurrentSessionFullScreenCover.toggle()
              }
          }
      } else {
        tabView(safeAreaBottomPadding: 60)
          .overlay(alignment: .bottom) {
            accessoryView()
              .padding(.vertical, 8)
              .background(.ultraThinMaterial, in: .rect(cornerRadius: 15, style: .continuous))
              .matchedTransitionSource(id: transitionID, in: namespace)
              .onTapGesture {
                showingCurrentSessionFullScreenCover.toggle()
              }
              .offset(y: -60)
              .padding(.horizontal, 15)
          }
          .ignoresSafeArea(.keyboard, edges: .all)
      }
    }
    .fullScreenCover(isPresented: $showingCurrentSessionFullScreenCover) {
      ScrollView {

      }
      .safeAreaInset(edge: .top, spacing: 0) {
        VStack(spacing: 10) {
          Capsule()
            .fill(.primary.secondary)
            .frame(width: 35, height: 3)

          HStack(spacing: 0) {
            accessoryIconView(size: .init(width: 80, height: 80))

            Spacer(minLength: 0)

            Group {
              Button("", systemImage: "star.circle.fill") {}

              Button("", systemImage: "ellipsis.circle.fill") {}
            }
            .font(.title)
            .foregroundStyle(Color.primary, Color.primary.opacity(0.1))
          }
          .padding(.horizontal, 15)
        }
        .navigationTransition(.zoom(sourceID: transitionID, in: namespace))
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(.background)
    }
  }

  @ViewBuilder
  private func tabView(safeAreaBottomPadding: CGFloat = .zero) -> some View {
    TabView {
      Tab("Home", systemImage: "house.fill") {
        //        HomeView()
        Text("Home View")
          .safeAreaPadding(.bottom, safeAreaBottomPadding)
      }

      Tab("Vehicle", systemImage: "car.fill") {
        //          VehicleView()
        Text("Vehicle View")
          .safeAreaPadding(.bottom, safeAreaBottomPadding)
      }

      Tab("New", systemImage: "square.grid.2x2.fill") {
        NavigationStack {
          List {
            ForEach(1..<35) { i in
              Text("Row \(i)")
            }
          }
          .navigationTitle("New")
          .safeAreaPadding(.bottom, safeAreaBottomPadding)
        }
      }

      Tab("Library", systemImage: "square.stack.fill") {
        NavigationStack {
          List {
            ForEach(1..<35) { i in
              Text("Row \(i)")
            }
          }
          .navigationTitle("Library")
          .safeAreaPadding(.bottom, safeAreaBottomPadding)
        }
      }

      Tab("Search", systemImage: "magnifyingglass", role: .search) {
        NavigationStack {
          ProgressView()
            .controlSize(.extraLarge)
            .navigationTitle("Search")
            .searchable(
              text: $searchText,
              placement: .toolbar,
              prompt: Text("Search...")
            )
            .safeAreaPadding(.bottom, safeAreaBottomPadding)
        }
      }
    }
  }

  @ViewBuilder
  private func accessoryView() -> some View {
    HStack(spacing: 15) {
      accessoryIconView(size: .init(width: 30, height: 30))

      Spacer(minLength: 0)

      Button {
      } label: {
        Image(systemName: "play.fill")
          .contentShape(.rect)
      }
      .padding(.trailing, 10)

      Button {
      } label: {
        Image(systemName: "forward.fill")
          .contentShape(.rect)
      }
    }
    .foregroundStyle(Color.primary)
    .padding(.horizontal, 15)
  }

  @ViewBuilder
  private func accessoryIconView(size: CGSize) -> some View {
    HStack(spacing: 12) {
      RoundedRectangle(cornerRadius: size.height / 4)
        .fill(.blue.gradient)
        .frame(width: size.width, height: size.height)

      VStack(alignment: .leading, spacing: 6) {
        Text("Your Current Session")
          .font(.callout)

        Text("50/100 done")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      .lineLimit(1)
    }
  }
}

#Preview {
  ContentView()
}
