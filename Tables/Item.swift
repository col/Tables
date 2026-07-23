//
//  Item.swift
//  Tables
//
//  Created by Colin Harris on 23/7/2026.
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
