//
//  SupabaseService.swift
//  InfineonProject
//
//  Created by Aaron Ma on 1/13/26.
//

import SwiftUI
import Supabase

@Observable
class SupabaseService {
    var client = SupabaseClient(supabaseURL: URL(string: Constants.Supabase.supabaseURL)!, supabaseKey: Constants.Supabase.supabasePublishableKey)
}
