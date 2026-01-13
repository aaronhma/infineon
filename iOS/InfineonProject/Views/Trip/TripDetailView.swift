//
//  TripDetailView.swift
//  InfineonProject
//
//  Created by Aaron Ma on 1/12/26.
//

import SwiftUI
import AaronUI
import MapKit

struct TripDetailView: View {
    var trip: Trip
    var namespace: Namespace.ID
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    trip.tripColor,
                    trip.tripColor.opacity(0.9),
                    .clear,
                    .clear,
                    .clear,
                    .clear,
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            List {
                Section {
                    VStack(spacing: 10) {
                        Circle()
                            .fill(trip.tripColor.gradient)
                            .frame(width: 100, height: 100)
                            .overlay {
                                Image(systemName: trip.tripIcon)
                                    .font(.system(size: 60))
                                    .foregroundStyle(.white)
                            }
                                        
                        Text(trip.tripStatus)
                            .font(.title2)
                            .bold()
                            .titleVisibilityAnchor()
                        
                        Text(trip.timeStarted.formatted(.dateTime))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                
                Section("Distracted Driving") {
                    Text("No infractions.")
                }
                
                Section("Speed Violations") {
                    Text("No infractions.")
                }
                
                Section("Trip Route") {
                    Map(
                        coordinateRegion:
                                .constant(
                                    MKCoordinateRegion(
                                        center: CLLocationCoordinate2D(
                                            latitude: 37.7749,
                                            longitude: -122.4194
                                        ),
                                        span: MKCoordinateSpan(
                                            latitudeDelta: 0.001,
                                            longitudeDelta: 0.001
                                        )
                                    )
                                ),
                        interactionModes: [.all]
                    )
                    //                        .aspectRatio(16 / 9, contentMode: .fit)
                    .frame(height: 250)
                    .listRowInsets(EdgeInsets())
                }
            }
        }
        .scrollAwareTitle(trip.tripStatus)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTransition(.zoom(sourceID: trip.id, in: namespace))
    }
}

#Preview {
    @Previewable @Namespace var namespace
    
    NavigationStack {
        TripDetailView(trip: Trip.sample, namespace: namespace)
    }
}
