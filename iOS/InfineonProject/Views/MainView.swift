//
//  MainView.swift
//  InfineonProject
//
//  Created by Aaron Ma on 1/13/26.
//

import AaronUI
import SwiftUI

struct MainView: View {
  @State private var showingJoinVehicleSheet = false

  private func deleteVehicles(at offsets: IndexSet) {
    for index in offsets {
      let vehicle = supabase.vehicles[index]
      Task {
        try? await supabase.leaveVehicle(vehicle.id)
      }
    }
  }

  var body: some View {
    NavigationStack {
      Group {
        if supabase.vehicles.isEmpty {
          ContentUnavailableView {
            Label("No Vehicles", systemImage: "car.fill")
          } description: {
            Text("Scan a QR code or enter the invite code you've received.")
          } actions: {
            Button("Add Vehicle", systemImage: "plus") {
              Haptics.impact()
              showingJoinVehicleSheet = true
            }
            .foregroundStyle(.white)
            .bold()
            .padding(.vertical, 8)
            .padding(.horizontal, 15)
            .possibleGlassEffect(.accentColor, in: .capsule)
            .buttonStyle(.borderedProminent)
          }
        } else {
          List {
            ForEach(supabase.vehicles) { vehicle in
              NavigationLink {
                VehicleDetailView(
                  vehicle: vehicle,
                  realtimeData: supabase.vehicleRealtimeData[vehicle.id]
                )
              } label: {
                VehicleRowView(
                  vehicle: vehicle,
                  realtimeData: supabase.vehicleRealtimeData[vehicle.id]
                )
              }
            }
            .onDelete(perform: deleteVehicles)
          }
        }
      }
      .transition(.blurReplace)
      .navigationTitle("Vehicles")
      .toolbarTitleDisplayMode(.inlineLarge)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          AccountView()
        }
      }
      .sheet(isPresented: $showingJoinVehicleSheet) {
        JoinVehicleView()
      }
      .refreshable {
        await supabase.loadVehicles()
      }
    }
  }
}

#Preview {
  MainView()
}
