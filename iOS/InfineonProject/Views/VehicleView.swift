//
//  VehicleView.swift
//  InfineonProject
//
//  Created by Aaron Ma on 1/12/26.
//

import SwiftUI
import AaronUI

struct VehicleView: View {
    @State private var showingVehicleSettings = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [.black.opacity(0.89), .black.opacity(0.93)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                // Fixed car image in background (dimmed)
                Image("modelY")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .opacity(0.6)
                    .padding(.bottom, 200)
                
                // Scrollable content
                ScrollView {
                    VStack(spacing: 0) {
                        // Header
                        HStack {
                            Text("Model Y")
                                .padding(.horizontal)
                                .foregroundStyle(.white)
                                .font(.title)
                                .bold()
                            
                            Spacer()
                            
                            Button {
                                showingVehicleSettings.toggle()
                            } label: {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 30))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 32)
                                    .overlay {
                                        Circle()
                                            .stroke(
                                                LinearGradient(
                                                    gradient: Gradient(
                                                        colors: [
                                                            Color.white,
                                                            Color.white.opacity(0.4)
                                                        ]
                                                    ),
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                    }
                            }
                        }
                        
                        HStack {
                            Image(systemName: "battery.75")
                                .foregroundStyle(.white)
                                .padding(.horizontal, 15)
                                .padding(.vertical, 1)
                            
                            Text("420 mi")
                                .foregroundStyle(.white)
                                .padding(.vertical, 1)
                            
                            Spacer()
                        }
                        
                        // Spacer to push action bar below the car initially
                        Spacer()
                            .frame(height: 350)
                        
                        // Action bar
                        HStack {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(.white)
                                .font(.system(size: 25))
                                .padding()
                            
                            Spacer()
                            
                            Image(systemName: "fanblades.fill")
                                .foregroundStyle(.white)
                                .font(.system(size: 25))
                                .padding()
                            
                            Spacer()
                            
                            Image(systemName: "bolt.fill")
                                .foregroundStyle(.white)
                                .font(.system(size: 25))
                                .padding()
                            
                            Spacer()
                            
                            Image(systemName: "arrowshape.turn.up.forward.fill")
                                .foregroundStyle(.white)
                                .font(.system(size: 25))
                                .padding()
                        }
                        .frame(height: 60)
                        .possibleGlassEffect(in: .capsule)
                        //                    .background(
                        //                        .ultraThinMaterial,
                        //                        in: .rect(cornerRadius: 30, style: .continuous)
                        //                    )
                        .clipShape(.rect(cornerRadius: 30, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 30, style: .continuous)
                                .stroke(.white.opacity(0.5), lineWidth: 0.5)
                        )
                        .padding()
                        
                        // Menu items
                        VStack(spacing: 0) {
                            MenuRow(icon: "slider.horizontal.3", title: "Controls")
                            
                            MenuRow(
                                icon: "fanblades",
                                title: "Climate",
                                subtitle: "Interior 22°C"
                            )
                            
                            MenuRow(icon: "location.fill", title: "Location")
                            
                            MenuRow(icon: "car.side", title: "Summon")
                            
                            MenuRow(icon: "checkmark.shield.fill", title: "Security")
                        }
                        .padding(.horizontal)
                        
                        // Extra content space for scrolling
                        Spacer()
                            .frame(height: 200)
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .sheet(isPresented: $showingVehicleSettings) {
            VehicleListView()
        }
    }
}

private struct MenuRow: View {
    let icon: String
    let title: String
    var subtitle: String?

    var body: some View {
        NavigationLink {
            Text("Coming soon!")
        } label: {
            HStack {
                Image(systemName: icon)
                    .bold()
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .bold()
                        .foregroundStyle(.white)

                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .bold()
                    .foregroundStyle(.white.opacity(0.3))
                    .font(.caption)
            }
            .padding(.vertical, 16)
        }
    }
}

#Preview {
    VehicleView()
}
