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
                    ForEach(trips) { i in
                        NavigationLink(value: i) {
                            Text("Trip #\(i)")
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
            .navigationTitle("Home")
            .navigationDestination(for: String.self) { i in
                switch i {
                case Constants.HomeRouteAnnouncer._trips.rawValue:
                    Text("Recent trips will appear here.")
                default:
                    Text("Unknown destination: \(i)")
                }
            }
            .navigationDestination(for: Trip.self, destination: TripDetailView.init)
        }
    }
}

#Preview {
    HomeView()
}
