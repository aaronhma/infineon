//
//  V2AccountView.swift
//  InfineonProject
//
//  Created by Aaron Ma on 1/20/26.
//

import AaronUI
import PhotosUI
import Supabase
import SwiftUI

struct V2AccountView: View {
  @Environment(\.dismiss) private var dismiss

  @Environment(V2AppData.self) private var appData

  @Namespace private var namespace

  @State private var showingSignOutConfirmation = false

  // Profile editing state
  @State private var isEditingProfile = false
  @State private var editName = ""
  @State private var selectedPhotoItem: PhotosPickerItem?
  @State private var selectedImage: UIImage?
  @State private var showingCropViewSheet = false
  @State private var croppedImage: UIImage?
  @State private var isSavingProfile = false

  // Notification settings
  @State private var notificationsEnabled = false
  @State private var notificationPreferences = NotificationPreferences.allEnabled

  enum SettingsOptions: Hashable {
    case profile
    case vehicleSettings
    case notifications
    case licensing
  }

  private func apacheLicense(_ author: String = "Aaron Ma") -> String {
    """
                                     Apache License
                               Version 2.0, January 2004
                            http://www.apache.org/licenses/

       TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

       1. Definitions.

          "License" shall mean the terms and conditions for use, reproduction,
          and distribution as defined by Sections 1 through 9 of this document.

          "Licensor" shall mean the copyright owner or entity authorized by
          the copyright owner that is granting the License.

          "Legal Entity" shall mean the union of the acting entity and all
          other entities that control, are controlled by, or are under common
          control with that entity. For the purposes of this definition,
          "control" means (i) the power, direct or indirect, to cause the
          direction or management of such entity, whether by contract or
          otherwise, or (ii) ownership of fifty percent (50%) or more of the
          outstanding shares, or (iii) beneficial ownership of such entity.

          "You" (or "Your") shall mean an individual or Legal Entity
          exercising permissions granted by this License.

          "Source" form shall mean the preferred form for making modifications,
          including but not limited to software source code, documentation
          source, and configuration files.

          "Object" form shall mean any form resulting from mechanical
          transformation or translation of a Source form, including but
          not limited to compiled object code, generated documentation,
          and conversions to other media types.

          "Work" shall mean the work of authorship, whether in Source or
          Object form, made available under the License, as indicated by a
          copyright notice that is included in or attached to the work
          (an example is provided in the Appendix below).

          "Derivative Works" shall mean any work, whether in Source or Object
          form, that is based on (or derived from) the Work and for which the
          editorial revisions, annotations, elaborations, or other modifications
          represent, as a whole, an original work of authorship. For the purposes
          of this License, Derivative Works shall not include works that remain
          separable from, or merely link (or bind by name) to the interfaces of,
          the Work and Derivative Works thereof.

          "Contribution" shall mean any work of authorship, including
          the original version of the Work and any modifications or additions
          to that Work or Derivative Works thereof, that is intentionally
          submitted to Licensor for inclusion in the Work by the copyright owner
          or by an individual or Legal Entity authorized to submit on behalf of
          the copyright owner. For the purposes of this definition, "submitted"
          means any form of electronic, verbal, or written communication sent
          to the Licensor or its representatives, including but not limited to
          communication on electronic mailing lists, source code control systems,
          and issue tracking systems that are managed by, or on behalf of, the
          Licensor for the purpose of discussing and improving the Work, but
          excluding communication that is conspicuously marked or otherwise
          designated in writing by the copyright owner as "Not a Contribution."

          "Contributor" shall mean Licensor and any individual or Legal Entity
          on behalf of whom a Contribution has been received by Licensor and
          subsequently incorporated within the Work.

       2. Grant of Copyright License. Subject to the terms and conditions of
          this License, each Contributor hereby grants to You a perpetual,
          worldwide, non-exclusive, no-charge, royalty-free, irrevocable
          copyright license to reproduce, prepare Derivative Works of,
          publicly display, publicly perform, sublicense, and distribute the
          Work and such Derivative Works in Source or Object form.

       3. Grant of Patent License. Subject to the terms and conditions of
          this License, each Contributor hereby grants to You a perpetual,
          worldwide, non-exclusive, no-charge, royalty-free, irrevocable
          (except as stated in this section) patent license to make, have made,
          use, offer to sell, sell, import, and otherwise transfer the Work,
          where such license applies only to those patent claims licensable
          by such Contributor that are necessarily infringed by their
          Contribution(s) alone or by combination of their Contribution(s)
          with the Work to which such Contribution(s) was submitted. If You
          institute patent litigation against any entity (including a
          cross-claim or counterclaim in a lawsuit) alleging that the Work
          or a Contribution incorporated within the Work constitutes direct
          or contributory patent infringement, then any patent licenses
          granted to You under this License for that Work shall terminate
          as of the date such litigation is filed.

       4. Redistribution. You may reproduce and distribute copies of the
          Work or Derivative Works thereof in any medium, with or without
          modifications, and in Source or Object form, provided that You
          meet the following conditions:

          (a) You must give any other recipients of the Work or
              Derivative Works a copy of this License; and

          (b) You must cause any modified files to carry prominent notices
              stating that You changed the files; and

          (c) You must retain, in the Source form of any Derivative Works
              that You distribute, all copyright, patent, trademark, and
              attribution notices from the Source form of the Work,
              excluding those notices that do not pertain to any part of
              the Derivative Works; and

          (d) If the Work includes a "NOTICE" text file as part of its
              distribution, then any Derivative Works that You distribute must
              include a readable copy of the attribution notices contained
              within such NOTICE file, excluding those notices that do not
              pertain to any part of the Derivative Works, in at least one
              of the following places: within a NOTICE text file distributed
              as part of the Derivative Works; within the Source form or
              documentation, if provided along with the Derivative Works; or,
              within a display generated by the Derivative Works, if and
              wherever such third-party notices normally appear. The contents
              of the NOTICE file are for informational purposes only and
              do not modify the License. You may add Your own attribution
              notices within Derivative Works that You distribute, alongside
              or as an addendum to the NOTICE text from the Work, provided
              that such additional attribution notices cannot be construed
              as modifying the License.

          You may add Your own copyright statement to Your modifications and
          may provide additional or different license terms and conditions
          for use, reproduction, or distribution of Your modifications, or
          for any such Derivative Works as a whole, provided Your use,
          reproduction, and distribution of the Work otherwise complies with
          the conditions stated in this License.

       5. Submission of Contributions. Unless You explicitly state otherwise,
          any Contribution intentionally submitted for inclusion in the Work
          by You to the Licensor shall be under the terms and conditions of
          this License, without any additional terms or conditions.
          Notwithstanding the above, nothing herein shall supersede or modify
          the terms of any separate license agreement you may have executed
          with Licensor regarding such Contributions.

       6. Trademarks. This License does not grant permission to use the trade
          names, trademarks, service marks, or product names of the Licensor,
          except as required for reasonable and customary use in describing the
          origin of the Work and reproducing the content of the NOTICE file.

       7. Disclaimer of Warranty. Unless required by applicable law or
          agreed to in writing, Licensor provides the Work (and each
          Contributor provides its Contributions) on an "AS IS" BASIS,
          WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
          implied, including, without limitation, any warranties or conditions
          of TITLE, NON-INFRINGEMENT, MERCHANTABILITY, or FITNESS FOR A
          PARTICULAR PURPOSE. You are solely responsible for determining the
          appropriateness of using or redistributing the Work and assume any
          risks associated with Your exercise of permissions under this License.

       8. Limitation of Liability. In no event and under no legal theory,
          whether in tort (including negligence), contract, or otherwise,
          unless required by applicable law (such as deliberate and grossly
          negligent acts) or agreed to in writing, shall any Contributor be
          liable to You for damages, including any direct, indirect, special,
          incidental, or consequential damages of any character arising as a
          result of this License or out of the use or inability to use the
          Work (including but not limited to damages for loss of goodwill,
          work stoppage, computer failure or malfunction, or any and all
          other commercial damages or losses), even if such Contributor
          has been advised of the possibility of such damages.

       9. Accepting Warranty or Additional Liability. While redistributing
          the Work or Derivative Works thereof, You may choose to offer,
          and charge a fee for, acceptance of support, warranty, indemnity,
          or other liability obligations and/or rights consistent with this
          License. However, in accepting such obligations, You may act only
          on Your own behalf and on Your sole responsibility, not on behalf
          of any other Contributor, and only if You agree to indemnify,
          defend, and hold each Contributor harmless for any liability
          incurred by, or claims asserted against, such Contributor by reason
          of your accepting any such warranty or additional liability.

       END OF TERMS AND CONDITIONS

       APPENDIX: How to apply the Apache License to your work.

          To apply the Apache License to your work, attach the following
          boilerplate notice, with the fields enclosed by brackets "[]"
          replaced with your own identifying information. (Don't include
          the brackets!)  The text should be enclosed in the appropriate
          comment syntax for the file format. We also recommend that a
          file or class name and description of purpose be included on the
          same "printed page" as the copyright notice for easier
          identification within third-party archives.

       Copyright 2026 \(author)

       Licensed under the Apache License, Version 2.0 (the "License");
       you may not use this file except in compliance with the License.
       You may obtain a copy of the License at

           http://www.apache.org/licenses/LICENSE-2.0

       Unless required by applicable law or agreed to in writing, software
       distributed under the License is distributed on an "AS IS" BASIS,
       WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
       See the License for the specific language governing permissions and
       limitations under the License.

    """
  }

  private func mitLicense(_ author: String = "Aaron Ma") -> String {
    """
    MIT License

    Copyright (c) 2026 \(author)

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
    """
  }

  var body: some View {
    NavigationStack {
      List {
        Section {
          VStack {
            Image("benji")
              .resizable()
              .aspectRatio(contentMode: .fill)
              .frame(width: 100, height: 100)
              .clipShape(.rect(cornerRadius: 10))

            HStack {
              Text(appData.watchingProfile!.name)
                .lineLimit(1)

              Image(systemName: "chevron.down")
                .foregroundStyle(.secondary)
            }
            .fontWeight(.semibold)
          }
          .frame(maxWidth: .infinity, alignment: .center)
        }
        .listRowBackground(Color.clear)
        .onTapGesture {
          withAnimation(.snappy(duration: 0.1)) {
            appData.showProfileView = true
            appData.hideMainView = true
            appData.fromTabBar = true
            dismiss()
          }
        }
        .listRowSeparator(.hidden)

        // Profile Section
        Section {
          NavigationLink(value: SettingsOptions.profile) {
            HStack(spacing: 16) {
              profileImageView
                .frame(width: 60, height: 60)
                .stableMatchedTransition(id: SettingsOptions.profile, in: namespace)
                .clipShape(.circle)

              VStack(alignment: .leading, spacing: 4) {
                Text(supabase.userProfile?.displayName ?? "No Name")
                  .font(.headline)

                if let email = supabase.currentUser?.email {
                  Text(email)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
              }

              Spacer()
            }
            .padding(.vertical, 4)
          }
        }

        // Settings Section
        Section {
          NavigationLink(value: SettingsOptions.vehicleSettings) {
            Label {
              Text("Vehicle Settings")
            } icon: {
              SettingsBoxView(icon: "car.fill", color: .blue)
                .stableMatchedTransition(id: SettingsOptions.vehicleSettings, in: namespace)
            }
          }

          NavigationLink(value: SettingsOptions.notifications) {
            Label {
              Text("Notifications")
            } icon: {
              SettingsBoxView(
                icon: supabase.userProfile?.notificationsEnabled ?? true
                  ? "bell.fill" : "bell.slash.fill", color: .red
              )
              .stableMatchedTransition(id: SettingsOptions.notifications, in: namespace)
            }
          }
        }

        // About Section
        Section {
          Link(destination: URL(string: "https://github.com/aaronhma")!) {
            VStack(alignment: .leading, spacing: 8) {
              Text("InfineonProject")
                .font(.headline)

              Text("© 2026 Aaron Ma.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

              Text("Made with 💖 from Cupertino, CA.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
          }
          .foregroundStyle(.primary)

          NavigationLink(value: SettingsOptions.licensing) {
            Label {
              Text("Licensing")
            } icon: {
              SettingsBoxView(icon: "graduationcap.fill", color: .indigo)
                .stableMatchedTransition(id: SettingsOptions.licensing, in: namespace)
            }
          }
        }

        Section {
          Button(role: .destructive) {
            Haptics.impact()
            showingSignOutConfirmation = true
          } label: {
            Label {
              Text("Sign Out")
            } icon: {
              SettingsBoxView(icon: "rectangle.portrait.and.arrow.right", color: .red)
            }
          }
          .confirmationDialog(
            "Are you sure you want to sign out?",
            isPresented: $showingSignOutConfirmation,
            titleVisibility: .visible
          ) {
            Button("Sign Out", role: .destructive) {
              Haptics.impact()
              Task {
                try? await supabase.signOut()
              }
            }
            Button("Cancel", role: .cancel) {}
          }
        }
      }
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          CloseButton {
            dismiss()
          }
        }
      }
      .navigationTitle("Account")
      .navigationBarTitleDisplayMode(.inline)
      .navigationDestination(for: SettingsOptions.self) { route in
        switch route {
        case .profile:
          EditProfileView()
            .navigationTransition(.zoom(sourceID: SettingsOptions.profile, in: namespace))
        case .vehicleSettings:
          VehicleSettingsView(vehicle: appData.watchingProfile!.vehicle)
            .navigationTransition(.zoom(sourceID: SettingsOptions.vehicleSettings, in: namespace))
        case .notifications:
          NotificationSettingsView()
            .navigationTransition(.zoom(sourceID: SettingsOptions.notifications, in: namespace))
        case .licensing:
          List {
            Section("License") {
              Link(destination: URL(string: "https://github.com/aaronhma")!) {
                VStack(alignment: .leading, spacing: 8) {
                  Text("InfineonProject")
                    .font(.headline)

                  Text("© 2026 Aaron Ma.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                  Text("Made with 💖 from Cupertino, CA.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
              }
              .foregroundStyle(.primary)

              NavigationLink {
                ScrollView {
                  Text(apacheLicense())
                    .padding(.horizontal)
                }
                .navigationTitle("Copyright Statement")
              } label: {
                Text("Copyright Statement")
              }
            }

            Section("AaronUI") {
              Text(
                "© 2026 Aaron Ma and the AaronUI internal project authors. This app contains code with restricted licensing."
              )

              NavigationLink {
                ScrollView {
                  Text(apacheLicense())
                    .padding(.horizontal)
                }
                .navigationTitle("AaronUI License")
              } label: {
                Text("AaronUI License")
              }
            }

            Section("Open Source Components Used") {
              NavigationLink {
                ScrollView {
                  Text(mitLicense("Supabase"))
                    .padding(.horizontal)
                }
                .navigationTitle("Supabase")
              } label: {
                Text("Supabase")
              }

              NavigationLink {
                ScrollView {
                  Text(apacheLicense("Apple, Inc."))
                    .padding(.horizontal)
                }
                .navigationTitle("swift-asn1")
              } label: {
                Text("swift-asn1")
              }

              NavigationLink {
                ScrollView {
                  Text(mitLicense("Point-Free"))
                    .padding(.horizontal)
                }
                .navigationTitle("swift-clocks")
              } label: {
                Text("swift-clocks")
              }

              NavigationLink {
                ScrollView {
                  Text(mitLicense("Point-Free"))
                    .padding(.horizontal)
                }
                .navigationTitle("swift-concurrency-extras")
              } label: {
                Text("swift-concurrency-extras")
              }

              NavigationLink {
                ScrollView {
                  Text(apacheLicense("Apple, Inc."))
                    .padding(.horizontal)
                }
                .navigationTitle("swift-crypto")
              } label: {
                Text("swift-crypto")
              }

              NavigationLink {
                ScrollView {
                  Text(apacheLicense("Apple, Inc."))
                    .padding(.horizontal)
                }
                .navigationTitle("swift-http-types")
              } label: {
                Text("swift-http-types")
              }

              NavigationLink {
                ScrollView {
                  Text(mitLicense("Point-Free, Inc."))
                    .padding(.horizontal)
                }
                .navigationTitle("xctest-dynamic-overlay")
              } label: {
                Text("xctest-dynamic-overlay")
              }
            }
          }
          .navigationTitle("Licensing")
          .navigationBarTitleDisplayMode(.inline)
          .navigationTransition(.zoom(sourceID: SettingsOptions.licensing, in: namespace))
        }
      }
    }
  }

  @ViewBuilder
  private var profileImageView: some View {
    if let avatarPath = supabase.userProfile?.avatarPath,
      let avatarURL = supabase.getUserAvatarURL(path: avatarPath)
    {
      AsyncImage(url: avatarURL) { phase in
        switch phase {
        case .success(let image):
          image
            .resizable()
            .scaledToFill()
            .clipShape(.circle)
        default:
          defaultProfileImage
        }
      }
    } else {
      defaultProfileImage
    }
  }

  private var defaultProfileImage: some View {
    Circle()
      .fill(.gray.gradient)
      .overlay {
        Image(systemName: "person.fill")
          .font(.title2)
          .foregroundStyle(.white)
      }
  }
}

// MARK: - Edit Profile View

struct EditProfileView: View {
  @Environment(\.dismiss) private var dismiss

  @State private var name = ""
  @State private var selectedPhotoItem: PhotosPickerItem?
  @State private var selectedImage: UIImage?
  @State private var showingCropViewSheet = false
  @State private var croppedImage: UIImage?
  @State private var isSaving = false
  @State private var errorMessage: String?

  var body: some View {
    List {
      Section {
        HStack {
          Spacer()

          PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
            VStack(spacing: 8) {
              profileImageView
                .frame(width: 100, height: 100)

              Text(hasNewImage ? "Change Photo" : "Edit Photo")
                .font(.subheadline)
                .foregroundStyle(.blue)
            }
          }

          Spacer()
        }
        .listRowBackground(Color.clear)
      }

      Section("Display Name") {
        TextField("Your name", text: $name)
      }

      if let errorMessage {
        Section {
          Text(errorMessage)
            .foregroundStyle(.red)
        }
      }

      Section("Debug") {
        LabeledContent("User ID") {
          if let userId = supabase.currentUser?.id.uuidString {
            Text(userId)
              .font(.caption)
              .foregroundStyle(.secondary)
              .textSelection(.enabled)
          } else {
            Text("Not available")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
    }
    .scrollDismissesKeyboard(.interactively)
    .navigationTitle("Edit Profile")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button("Save") {
          Task {
            await saveProfile()
          }
        }
        .disabled(name.isEmpty || isSaving)
      }
    }
    .onAppear {
      name = supabase.userProfile?.displayName ?? ""
    }
    .onDisappear {
      hideKeyboard()
    }
    .onChange(of: selectedPhotoItem) { _, newItem in
      guard let newItem else { return }
      Task {
        if let data = try? await newItem.loadTransferable(type: Data.self),
          let uiImage = UIImage(data: data)
        {
          selectedImage = uiImage
        }
      }
    }
    .onChange(of: selectedImage) { _, newImage in
      if newImage != nil {
        showingCropViewSheet = true
      }
    }
    .sheet(isPresented: $showingCropViewSheet) {
      if let selectedImage {
        CropView(crop: .circle, image: selectedImage) { resultImage, status in
          if status {
            croppedImage = resultImage
          }
          showingCropViewSheet = false
        }
      }
    }
    .overlay {
      if isSaving {
        Color.black.opacity(0.3)
          .ignoresSafeArea()
          .overlay {
            ProgressView("Saving...")
              .padding()
              .background(.regularMaterial, in: .rect(cornerRadius: 12))
          }
      }
    }
  }

  private var hasNewImage: Bool {
    croppedImage != nil
  }

  @ViewBuilder
  private var profileImageView: some View {
    if let croppedImage {
      Image(uiImage: croppedImage)
        .resizable()
        .scaledToFill()
        .clipShape(.circle)
    } else if let avatarPath = supabase.userProfile?.avatarPath,
      let avatarURL = supabase.getUserAvatarURL(path: avatarPath)
    {
      AsyncImage(url: avatarURL) { phase in
        switch phase {
        case .success(let image):
          image
            .resizable()
            .scaledToFill()
            .clipShape(.circle)
        default:
          defaultProfileImage
        }
      }
    } else {
      defaultProfileImage
    }
  }

  private var defaultProfileImage: some View {
    Circle()
      .fill(.gray.gradient)
      .overlay {
        Image(systemName: "person.fill")
          .font(.largeTitle)
          .foregroundStyle(.white)
      }
  }

  private func saveProfile() async {
    isSaving = true
    errorMessage = nil

    do {
      var avatarPath: String?
      if let croppedImage,
        let imageData = croppedImage.jpegData(compressionQuality: 0.8)
      {
        avatarPath = try await supabase.uploadUserAvatar(imageData: imageData)
      }

      try await supabase.updateUserProfile(
        displayName: name,
        avatarPath: avatarPath
      )

      await MainActor.run {
        isSaving = false
        dismiss()
      }
    } catch {
      await MainActor.run {
        errorMessage = error.localizedDescription
        isSaving = false
      }
    }
  }
}

// MARK: - Vehicle Settings View

struct VehicleSettingsView: View {
  @Environment(V2AppData.self) private var appData
  @Environment(\.dismiss) private var dismiss

  let vehicle: Vehicle

  @State private var vehicleName = ""
  @State private var vehicleDescription = ""
  @State private var isSaving = false
  @State private var errorMessage: String?

  private var isOwner: Bool {
    supabase.currentUser?.id == vehicle.ownerId
  }

  var body: some View {
    List {
      Section {
        LabeledContent("Vehicle ID") {
          Text(vehicle.id)
            .font(.caption)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }

        LabeledContent("Invite Code") {
          Text(vehicle.inviteCode)
            .font(.caption)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
      }

      if isOwner {
        Section("Vehicle Name") {
          TextField("Vehicle name", text: $vehicleName)
        }

        Section("Description") {
          TextField("Vehicle description", text: $vehicleDescription)
        }

        if let errorMessage {
          Section {
            Text(errorMessage)
              .foregroundStyle(.red)
          }
        }
      } else {
        Section("Vehicle Info") {
          LabeledContent("Name") {
            Text(vehicle.name ?? "Unnamed")
              .foregroundStyle(.secondary)
          }

          LabeledContent("Description") {
            Text(vehicle.description ?? "No description")
              .foregroundStyle(.secondary)
          }
        }

        Section {
          Text("Only the vehicle owner can edit these settings.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
    }
    .navigationTitle("Vehicle Settings")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if isOwner {
        ToolbarItem(placement: .confirmationAction) {
          if isSaving {
            ProgressView()
          } else {
            Button("Save") {
              Task {
                await saveVehicleSettings()
              }
            }
            .disabled(vehicleName.isEmpty)
          }
        }
      }
    }
    .onAppear {
      vehicleName = vehicle.name ?? ""
      vehicleDescription = vehicle.description ?? ""
    }
    .onDisappear {
      hideKeyboard()
    }
    .overlay {
      if isSaving {
        Color.black.opacity(0.3)
          .ignoresSafeArea()
          .overlay {
            ProgressView("Saving...")
              .padding()
              .background(.regularMaterial, in: .rect(cornerRadius: 12))
          }
      }
    }
  }

  private func saveVehicleSettings() async {
    isSaving = true
    errorMessage = nil

    do {
      try await supabase.updateVehicle(
        vehicleId: vehicle.id,
        name: vehicleName,
        description: vehicleDescription.isEmpty ? nil : vehicleDescription
      )

      // Update the profile in appData so the UI reflects the change
      await MainActor.run {
        if var profile = appData.watchingProfile {
          let updatedVehicle = supabase.vehicles.first { $0.id == vehicle.id }
          if let updatedVehicle {
            profile.vehicle = updatedVehicle
            profile.name = updatedVehicle.name ?? profile.name
            appData.watchingProfile = profile
          }
        }
        isSaving = false
        dismiss()
      }
    } catch {
      await MainActor.run {
        errorMessage = error.localizedDescription
        isSaving = false
      }
    }
  }
}

// MARK: - Notification Settings View

struct NotificationSettingsView: View {
  @State private var isLoading = true
  @State private var isSaving = false
  @State private var notificationsEnabled = false

  @State private var unidentifiedFace = true
  @State private var collision = true
  @State private var driverDrowsiness = true
  @State private var speedLimit = true
  @State private var drunkDriving = true
  @State private var fsd = true

  var body: some View {
    List {
      Section {
        Toggle(isOn: $notificationsEnabled.animation()) {
          Label {
            VStack(alignment: .leading) {
              Text("Enable Notifications")
              Text("Receive alerts for important events")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          } icon: {
            SettingsBoxView(
              icon: notificationsEnabled ? "bell.fill" : "bell.slash.fill", color: .red)
          }
        }
        .onChange(of: notificationsEnabled) {
          if notificationsEnabled {
            Task {
              await UIApplication.shared.registerForRemoteNotifications()
            }
          }
        }
      }

      if notificationsEnabled {
        Section("Notify Me When...") {
          notificationToggle(
            "Unidentified Face",
            icon: "faceid",
            description: "Notify when a new driver is detected",
            isOn: $unidentifiedFace
          )

          notificationToggle(
            "Collision",
            icon: "car.side.rear.and.collision.and.car.side.front",
            description: "Notify when a car crash is detected",
            isOn: $collision
          )

          notificationToggle(
            "Driver Drowsiness",
            icon: "eye.half.closed",
            description: "Notify when the driver is drowsy",
            isOn: $driverDrowsiness
          )

          notificationToggle(
            "Speed Limit",
            icon: "gauge.with.dots.needle.100percent",
            description: "Notify when speed limit is exceeded",
            isOn: $speedLimit
          )

          notificationToggle(
            "Drunk Driving",
            icon: "wineglass.fill",
            description: "Notify when impaired driving is detected",
            isOn: $drunkDriving
          )

          notificationToggle(
            "FSD",
            icon: "car.side.fill",
            description: "Notify when FSD is engaged or disengaged",
            isOn: $fsd
          )
        }
      }

      Section("Debug") {
        LabeledContent("Device Token") {
          if let token = supabase.deviceToken {
            Text(token)
              .font(.caption2)
              .foregroundStyle(.secondary)
              .textSelection(.enabled)
              .lineLimit(3)
          } else {
            Text("Not available")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
    }
    .navigationTitle("Notifications")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        if isSaving {
          ProgressView()
        } else {
          Button("Save") {
            Task {
              await saveNotificationSettings()
            }
          }
        }
      }
    }
    .onAppear {
      loadCurrentSettings()
    }
  }

  @ViewBuilder
  private func notificationToggle(
    _ title: String,
    icon: String,
    description: String,
    isOn: Binding<Bool>
  ) -> some View {
    Toggle(isOn: isOn) {
      Label {
        VStack(alignment: .leading) {
          Text(title)
          Text(description)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      } icon: {
        SettingsBoxView(icon: icon, color: .indigo)
      }
    }
  }

  private func loadCurrentSettings() {
    if let profile = supabase.userProfile {
      notificationsEnabled = profile.notificationsEnabled ?? false

      if let prefs = profile.notificationPreferences {
        unidentifiedFace = prefs.unidentifiedFace
        collision = prefs.collision
        driverDrowsiness = prefs.driverDrowsiness
        speedLimit = prefs.speedLimit
        drunkDriving = prefs.drunkDriving
        fsd = prefs.fsd
      }
    }
    isLoading = false
  }

  private func saveNotificationSettings() async {
    isSaving = true

    let preferences = NotificationPreferences(
      unidentifiedFace: unidentifiedFace,
      collision: collision,
      driverDrowsiness: driverDrowsiness,
      speedLimit: speedLimit,
      drunkDriving: drunkDriving,
      fsd: fsd
    )

    var pushToken: String?
    if notificationsEnabled {
      try? await Task.sleep(for: .milliseconds(300))
      pushToken = supabase.deviceToken
    }

    do {
      try await supabase.updateUserProfile(
        notificationPreferences: preferences,
        notificationsEnabled: notificationsEnabled,
        pushToken: pushToken
      )
    } catch {
      print("Error saving notification settings: \(error)")
    }

    await MainActor.run {
      isSaving = false
    }
  }
}

#Preview {
  @Previewable @State var appData = V2AppData()

  V2AccountView()
    .environment(appData)
}
