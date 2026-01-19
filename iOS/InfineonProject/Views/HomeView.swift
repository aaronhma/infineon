//
//  HomeView.swift
//  InfineonProject
//
//  Created by Aaron Ma on 1/12/26.
//

import AaronUI
import SwiftUI

struct HomeView: View {
  @State var progressOuter = CGFloat.zero
  @State var progressMiddle = CGFloat.zero
  @State var progressInner = CGFloat.zero

  @Namespace private var namespace

  let trips: [Trip] = (0..<35).map { _ in
    let statuses = Trip.Status.allCases
    let randomStatus = statuses.randomElement() ?? .ok
    return Trip(status: randomStatus)
  }

  var body: some View {
    NavigationStack {
      List {
        Section {
          VStack {
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text("Driving")
                  .font(.title3)
                  .bold()

                Text("5/100")
                  .foregroundStyle(.red)
                  .contentTransition(.numericText(value: 0))
                  .padding(.bottom)

                Text("Today's Goal")
                  .font(.title3)
                  .bold()

                Text(
                  "5/10"
                )
                .foregroundStyle(.green)
                .contentTransition(.numericText(value: 0))

                Spacer(minLength: 0)
              }

              Spacer(minLength: 0)

              RingsView(
                size: 100,
                lineWidth: 15,
                progressOuter: $progressOuter,
                progressMiddle: $progressMiddle,
                progressInner: $progressInner
              )
            }
          }
        } header: {
          HStack {
            Text("Today")
              .foregroundStyle(Color.primary)
              .font(.title2)

            Spacer()

            Button("Update") {
              progressOuter = CGFloat.random(in: 0...1)
              progressMiddle = CGFloat.random(in: 0...1)
              progressInner = CGFloat.random(in: 0...1)
            }
          }
          .lineLimit(1)
          .bold()
        }

        Section {
          ForEach(trips.prefix(8)) { trip in
            NavigationLink(value: trip) {
              TripInfoView(trip: trip, namespace: namespace)
            }
          }
        } header: {
          NavigationLink(value: "_trips") {
            HStack {
              Text("Recent Trips")

              Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)

              Spacer()
            }
            .lineLimit(1)
            .font(.title2)
            .bold()
          }
          .frame(maxWidth: .infinity)
          .foregroundStyle(.primary)
        }
      }
      .navigationTitle("Trips")
      .navigationDestination(for: String.self) { i in
        switch i {
        case Constants.HomeRouteAnnouncer.trips.rawValue:
          List {
            ForEach(trips) { trip in
              //                            NavigationLink(value: trip) {
              //                                TripInfoView(trip: trip, namespace: namespace)
              //                            }
            }
            .navigationTitle("Trips")
          }
        default:
          Text("Unknown destination: \(i)")
        }
      }
      .navigationDestination(for: Trip.self) { trip in
        TripDetailView(trip: trip, namespace: namespace)
        //                    .navigationTransition(.zoom(sourceID: trip.id, in: namespace))
      }
    }
  }
}

#Preview {
  HomeView()
}
