//
//  Trip.swift
//  InfineonProject
//
//  Created by Aaron Ma on 1/12/26.
//

import SwiftUI
import SwiftData

@Model
final class Trip: Identifiable {
    var id: UUID
    var timeStarted: Date
    var timeEnded: Date
    var status = Status.warning
    
    init(
        id: UUID = UUID(),
        timeStarted: Date = .now,
        timeEnded: Date = .now,
        status: Status = .warning
    ) {
        self.id = id
        self.timeStarted = timeStarted
        self.timeEnded = timeEnded
        self.status = status
    }
    
    enum Status: String, Codable, CaseIterable {
        case ok = "OK"
        case warning = "Warning"
        case danger = "Danger"
    }
    
    @Transient
    var tripStatus: String {
        return switch status {
        case .ok:
            "OK"
        case .warning:
            "Warning"
        case .danger:
            "Danger"
        }
    }
    
    @Transient
    var tripColor: Color {
        return switch status {
        case .danger:
                .red
        case .warning:
                .yellow
        case .ok:
                .green
        }
    }
    
    @Transient
    var tripIcon: String {
        return switch status {
        case .danger:
            "xmark"
        case .warning:
            "exclamationmark.triangle.fill"
        case .ok:
            "checkmark"
        }
    }
}

extension Trip {
    static let sample = Trip(status: .ok)
}
