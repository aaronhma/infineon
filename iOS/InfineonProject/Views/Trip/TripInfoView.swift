//
//  TripInfoView.swift
//  InfineonProject
//
//  Created by Aaron Ma on 1/12/26.
//

import SwiftUI
import AaronUI

struct TripInfoView: View {
    var trip: Trip
    var namespace: Namespace.ID
    
    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(trip.tripColor.gradient)
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: trip.tripIcon)
                        .font(.system(size: 20))
                        .foregroundStyle(.white)
                }
                .stableMatchedTransition(id: trip.id, in: namespace)
            
            VStack(alignment: .leading) {
                Text(trip.tripStatus)
                    .font(.title2)
                    .bold()
                        
                Text(trip.timeStarted.formatted(.dateTime))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer(minLength: 0)
        }
    }
}

#Preview {
    @Previewable @Namespace var namespace
    
    TripInfoView(trip: Trip.sample, namespace: namespace)
}
