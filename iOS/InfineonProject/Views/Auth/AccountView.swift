//
//  AccountView.swift
//  InfineonProject
//
//  Created by Aaron Ma on 1/13/26.
//

import AaronUI
import SwiftUI

struct AccountView: View {
  @State private var showingSettingsSheet = false
  @State private var showingSignOutConfirmation = false

  var body: some View {
    Button {
      Haptics.impact()
      showingSettingsSheet.toggle()
    } label: {
      Image(systemName: "person.fill")
    }
    .sheet(isPresented: $showingSettingsSheet) {
      NavigationStack {
        List {
          Section {
            Text("No settings yet.")
          }

          Section {
            Button(role: .destructive) {
              Haptics.impact()
              showingSignOutConfirmation = true
            } label: {
              Label {
                Text("Sign out")
              } icon: {
                SettingsBoxView(icon: "rectangle.portrait.and.arrow.right", color: .red)
              }
            }
            .confirmationDialog(
              "Are you sure you want to sign out?", isPresented: $showingSignOutConfirmation,
              titleVisibility: .visible
            ) {
              Button("Sign out", role: .destructive) {
                Haptics.impact()

                Task {
                  try? await supabase.signOut()
                }
              }
              Button("Cancel", role: .cancel) {}
            }
          }
        }
        .navigationTitle("Account")
        .toolbar {
          ToolbarItem(placement: .topBarLeading) {
            CloseButton {
              showingSettingsSheet.toggle()
            }
          }
        }
      }
    }
  }
}

#Preview {
  NavigationStack {
    Text("Tap on the toolbar item on the top right.")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          AccountView()
        }
      }
  }
}
