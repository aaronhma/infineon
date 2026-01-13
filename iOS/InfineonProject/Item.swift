//
//  Item.swift
//  InfineonProject
//
//  Created by Aaron Ma on 1/12/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
