//
//  SupabaseService.swift
//  InfineonProject
//
//  Created by Aaron Ma on 1/13/26.
//

import Supabase
import SwiftData
import SwiftUI

// MARK: - Models

struct Vehicle: Codable, Identifiable {
  let id: String
  let createdAt: Date
  let updatedAt: Date
  let name: String?
  let description: String?
  let inviteCode: String
  let ownerId: UUID?

  // Feature toggles
  var enableYolo: Bool
  var enableStream: Bool
  var enableShazam: Bool
  var enableMicrophone: Bool
  var enableCamera: Bool

  enum CodingKeys: String, CodingKey {
    case id
    case createdAt = "created_at"
    case updatedAt = "updated_at"
    case name, description
    case inviteCode = "invite_code"
    case ownerId = "owner_id"
    case enableYolo = "enable_yolo"
    case enableStream = "enable_stream"
    case enableShazam = "enable_shazam"
    case enableMicrophone = "enable_microphone"
    case enableCamera = "enable_camera"
  }

  init(
    id: String,
    createdAt: Date,
    updatedAt: Date,
    name: String?,
    description: String?,
    inviteCode: String,
    ownerId: UUID?,
    enableYolo: Bool = true,
    enableStream: Bool = true,
    enableShazam: Bool = true,
    enableMicrophone: Bool = true,
    enableCamera: Bool = true
  ) {
    self.id = id
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.name = name
    self.description = description
    self.inviteCode = inviteCode
    self.ownerId = ownerId
    self.enableYolo = enableYolo
    self.enableStream = enableStream
    self.enableShazam = enableShazam
    self.enableMicrophone = enableMicrophone
    self.enableCamera = enableCamera
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    createdAt = try container.decode(Date.self, forKey: .createdAt)
    updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    name = try container.decodeIfPresent(String.self, forKey: .name)
    description = try container.decodeIfPresent(String.self, forKey: .description)
    inviteCode = try container.decode(String.self, forKey: .inviteCode)
    ownerId = try container.decodeIfPresent(UUID.self, forKey: .ownerId)
    enableYolo = try container.decodeIfPresent(Bool.self, forKey: .enableYolo) ?? true
    enableStream = try container.decodeIfPresent(Bool.self, forKey: .enableStream) ?? true
    enableShazam = try container.decodeIfPresent(Bool.self, forKey: .enableShazam) ?? true
    enableMicrophone = try container.decodeIfPresent(Bool.self, forKey: .enableMicrophone) ?? true
    enableCamera = try container.decodeIfPresent(Bool.self, forKey: .enableCamera) ?? true
  }
}

struct VehicleAccess: Codable, Identifiable {
  let id: UUID
  let createdAt: Date
  let userId: UUID
  let vehicleId: String
  let accessLevel: String

  enum CodingKeys: String, CodingKey {
    case id
    case createdAt = "created_at"
    case userId = "user_id"
    case vehicleId = "vehicle_id"
    case accessLevel = "access_level"
  }
}

struct VehicleRealtime: Codable, Identifiable {
  var id: String { vehicleId }
  let vehicleId: String
  let updatedAt: Date
  let latitude: Double?
  let longitude: Double?
  let speedMph: Int
  let speedLimitMph: Int
  let headingDegrees: Int
  let compassDirection: String
  let isSpeeding: Bool
  let isMoving: Bool
  let driverStatus: String
  let intoxicationScore: Int
  // GPS data
  let satellites: Int?
  // Distraction detection
  let isPhoneDetected: Bool?
  let isDrinkingDetected: Bool?
  // Remote buzzer control
  let buzzerActive: Bool?
  let buzzerType: String?
  let buzzerUpdatedAt: Date?

  enum CodingKeys: String, CodingKey {
    case vehicleId = "vehicle_id"
    case updatedAt = "updated_at"
    case latitude, longitude
    case speedMph = "speed_mph"
    case speedLimitMph = "speed_limit_mph"
    case headingDegrees = "heading_degrees"
    case compassDirection = "compass_direction"
    case isSpeeding = "is_speeding"
    case isMoving = "is_moving"
    case driverStatus = "driver_status"
    case intoxicationScore = "intoxication_score"
    case satellites
    case isPhoneDetected = "is_phone_detected"
    case isDrinkingDetected = "is_drinking_detected"
    case buzzerActive = "buzzer_active"
    case buzzerType = "buzzer_type"
    case buzzerUpdatedAt = "buzzer_updated_at"
  }

  init(
    vehicleId: String,
    updatedAt: Date,
    latitude: Double?,
    longitude: Double?,
    speedMph: Int,
    speedLimitMph: Int,
    headingDegrees: Int,
    compassDirection: String,
    isSpeeding: Bool,
    isMoving: Bool,
    driverStatus: String,
    intoxicationScore: Int,
    satellites: Int?,
    isPhoneDetected: Bool?,
    isDrinkingDetected: Bool?,
    buzzerActive: Bool? = nil,
    buzzerType: String? = nil,
    buzzerUpdatedAt: Date? = nil
  ) {
    self.vehicleId = vehicleId
    self.updatedAt = updatedAt
    self.latitude = latitude
    self.longitude = longitude
    self.speedMph = speedMph
    self.speedLimitMph = speedLimitMph
    self.headingDegrees = headingDegrees
    self.compassDirection = compassDirection
    self.isSpeeding = isSpeeding
    self.isMoving = isMoving
    self.driverStatus = driverStatus
    self.intoxicationScore = intoxicationScore
    self.satellites = satellites
    self.isPhoneDetected = isPhoneDetected
    self.isDrinkingDetected = isDrinkingDetected
    self.buzzerActive = buzzerActive
    self.buzzerType = buzzerType
    self.buzzerUpdatedAt = buzzerUpdatedAt
  }
}

struct JoinVehicleResponse: Codable {
  let success: Bool
  let vehicleId: String?
  let vehicleName: String?
  let error: String?

  enum CodingKeys: String, CodingKey {
    case success
    case vehicleId = "vehicle_id"
    case vehicleName = "vehicle_name"
    case error
  }
}

struct FaceDetection: Codable, Identifiable {
  let id: UUID
  let createdAt: Date
  let vehicleId: String?
  let driverProfileId: UUID?
  let faceClusterId: UUID?  // Groups similar faces together
  let faceBbox: FaceBbox?
  let leftEyeState: String?
  let leftEyeEar: Double?
  let rightEyeState: String?
  let rightEyeEar: Double?
  let avgEar: Double?
  let isDrowsy: Bool
  let isExcessiveBlinking: Bool
  let isUnstableEyes: Bool
  let intoxicationScore: Int
  let speedMph: Int?
  let headingDegrees: Int?
  let compassDirection: String?
  let isSpeeding: Bool?
  let imagePath: String?
  let sessionId: UUID?
  // Distraction detection
  let isPhoneDetected: Bool?
  let isDrinkingDetected: Bool?

  enum CodingKeys: String, CodingKey {
    case id
    case createdAt = "created_at"
    case vehicleId = "vehicle_id"
    case driverProfileId = "driver_profile_id"
    case faceClusterId = "face_cluster_id"
    case faceBbox = "face_bbox"
    case leftEyeState = "left_eye_state"
    case leftEyeEar = "left_eye_ear"
    case rightEyeState = "right_eye_state"
    case rightEyeEar = "right_eye_ear"
    case avgEar = "avg_ear"
    case isDrowsy = "is_drowsy"
    case isExcessiveBlinking = "is_excessive_blinking"
    case isUnstableEyes = "is_unstable_eyes"
    case intoxicationScore = "intoxication_score"
    case speedMph = "speed_mph"
    case headingDegrees = "heading_degrees"
    case compassDirection = "compass_direction"
    case isSpeeding = "is_speeding"
    case imagePath = "image_path"
    case sessionId = "session_id"
    case isPhoneDetected = "is_phone_detected"
    case isDrinkingDetected = "is_drinking_detected"
  }
}

/// Represents a cluster of similar unidentified faces
struct FaceCluster: Codable, Identifiable {
  var id: UUID { clusterId }
  let clusterId: UUID
  let faceCount: Int
  let firstSeen: Date
  let lastSeen: Date
  let representativeImagePath: String?

  enum CodingKeys: String, CodingKey {
    case clusterId = "cluster_id"
    case faceCount = "face_count"
    case firstSeen = "first_seen"
    case lastSeen = "last_seen"
    case representativeImagePath = "representative_image_path"
  }
}

/// Response from assign_profile_to_cluster function
struct AssignClusterResponse: Codable {
  let success: Bool
  let updatedCount: Int
  let clusterId: UUID
  let profileId: UUID

  enum CodingKeys: String, CodingKey {
    case success
    case updatedCount = "updated_count"
    case clusterId = "cluster_id"
    case profileId = "profile_id"
  }
}

struct FaceBbox: Codable {
  let xMin: Int
  let yMin: Int
  let xMax: Int
  let yMax: Int

  enum CodingKeys: String, CodingKey {
    case xMin = "x_min"
    case yMin = "y_min"
    case xMax = "x_max"
    case yMax = "y_max"
  }
}

struct DriverProfile: Codable, Identifiable {
  let id: UUID
  let createdAt: Date
  let updatedAt: Date
  let vehicleId: String
  let name: String
  let notes: String?
  let profileImagePath: String?
  let createdBy: UUID?

  enum CodingKeys: String, CodingKey {
    case id
    case createdAt = "created_at"
    case updatedAt = "updated_at"
    case vehicleId = "vehicle_id"
    case name
    case notes
    case profileImagePath = "profile_image_path"
    case createdBy = "created_by"
  }
}

struct VehicleTrip: Codable, Identifiable {
  let id: UUID
  let createdAt: Date
  let vehicleId: String
  let sessionId: UUID
  let driverProfileId: UUID?
  let startedAt: Date
  let endedAt: Date?
  let status: String
  let maxSpeedMph: Int
  let avgSpeedMph: Double
  let maxIntoxicationScore: Int
  let speedingEventCount: Int
  let drowsyEventCount: Int
  let excessiveBlinkingEventCount: Int
  let unstableEyesEventCount: Int
  let faceDetectionCount: Int
  let speedSampleCount: Int
  let speedSampleSum: Int
  // Distraction event counts
  let phoneDistractionEventCount: Int?
  let drinkingEventCount: Int?

  enum CodingKeys: String, CodingKey {
    case id
    case createdAt = "created_at"
    case vehicleId = "vehicle_id"
    case sessionId = "session_id"
    case driverProfileId = "driver_profile_id"
    case startedAt = "started_at"
    case endedAt = "ended_at"
    case status
    case maxSpeedMph = "max_speed_mph"
    case avgSpeedMph = "avg_speed_mph"
    case maxIntoxicationScore = "max_intoxication_score"
    case speedingEventCount = "speeding_event_count"
    case drowsyEventCount = "drowsy_event_count"
    case excessiveBlinkingEventCount = "excessive_blinking_event_count"
    case unstableEyesEventCount = "unstable_eyes_event_count"
    case faceDetectionCount = "face_detection_count"
    case speedSampleCount = "speed_sample_count"
    case speedSampleSum = "speed_sample_sum"
    case phoneDistractionEventCount = "phone_distraction_event_count"
    case drinkingEventCount = "drinking_event_count"
  }

  /// Returns the trip status as an enum for easier handling
  var tripStatus: TripStatus {
    TripStatus(rawValue: status) ?? .ok
  }

  enum TripStatus: String, Codable, CaseIterable {
    case ok
    case warning
    case danger

    var displayName: String {
      switch self {
      case .ok: "OK"
      case .warning: "Warning"
      case .danger: "Danger"
      }
    }

    var color: Color {
      switch self {
      case .ok: .green
      case .warning: .yellow
      case .danger: .red
      }
    }

    var icon: String {
      switch self {
      case .ok: "checkmark"
      case .warning: "exclamationmark.triangle.fill"
      case .danger: "xmark"
      }
    }
  }
}

struct MusicDetection: Codable, Identifiable {
  let id: UUID
  let vehicleId: String
  let sessionId: UUID?
  let title: String
  let artist: String
  let album: String?
  let releaseYear: String?
  let genres: [String]?
  let label: String?
  let shazamUrl: String?
  let appleMusicUrl: String?
  let spotifyUrl: String?
  let detectedAt: Date
  let createdAt: Date

  enum CodingKeys: String, CodingKey {
    case id
    case vehicleId = "vehicle_id"
    case sessionId = "session_id"
    case title, artist, album
    case releaseYear = "release_year"
    case genres, label
    case shazamUrl = "shazam_url"
    case appleMusicUrl = "apple_music_url"
    case spotifyUrl = "spotify_url"
    case detectedAt = "detected_at"
    case createdAt = "created_at"
  }
}

struct NotificationPreferences: Codable, Equatable {
  var unidentifiedFace: Bool
  var collision: Bool
  var driverDrowsiness: Bool
  var speedLimit: Bool
  var drunkDriving: Bool
  var fsd: Bool

  enum CodingKeys: String, CodingKey {
    case unidentifiedFace = "unidentified_face"
    case collision
    case driverDrowsiness = "driver_drowsiness"
    case speedLimit = "speed_limit"
    case drunkDriving = "drunk_driving"
    case fsd
  }

  static var allEnabled: NotificationPreferences {
    NotificationPreferences(
      unidentifiedFace: true,
      collision: true,
      driverDrowsiness: true,
      speedLimit: true,
      drunkDriving: true,
      fsd: true
    )
  }
}

struct UserProfile: Codable, Identifiable, Equatable {
  var id: UUID { userId }
  let userId: UUID
  let createdAt: Date
  let updatedAt: Date
  let displayName: String?
  let avatarPath: String?
  let notificationPreferences: NotificationPreferences?
  let notificationsEnabled: Bool?
  let pushToken: String?

  enum CodingKeys: String, CodingKey {
    case userId = "user_id"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
    case displayName = "display_name"
    case avatarPath = "avatar_path"
    case notificationPreferences = "notification_preferences"
    case notificationsEnabled = "notifications_enabled"
    case pushToken = "push_token"
  }

  /// Returns true if the profile needs setup (no display name set)
  var needsSetup: Bool {
    displayName == nil || displayName?.isEmpty == true
  }
}

struct VehicleAccessUser: Codable, Identifiable {
  var id: UUID { accessId ?? userId }
  let accessId: UUID?
  let userId: UUID
  let displayName: String?
  let email: String?
  let avatarPath: String?
  let accessLevel: String?
  private let _isOwner: Bool?

  var isOwner: Bool {
    _isOwner ?? false
  }

  enum CodingKeys: String, CodingKey {
    case accessId = "access_id"
    case userId = "user_id"
    case displayName = "display_name"
    case email
    case avatarPath = "avatar_path"
    case accessLevel = "access_level"
    case _isOwner = "is_owner"
  }
}

// MARK: - SupabaseService

@Observable
class SupabaseService {
  let client: SupabaseClient

  // Auth state
  var isLoggedIn = false
  var isLoading = true
  var isRefreshingSession = false
  var currentUser: User?

  // User profile state
  var userProfile: UserProfile?

  // Push notification token
  var deviceToken: String?

  /// Returns true if the user needs to set up their profile (first-time user or no display name)
  var needsProfileSetup: Bool {
    userProfile?.needsSetup ?? true
  }

  // Vehicle state
  var vehicles: [Vehicle] = []
  var vehicleRealtimeData: [String: VehicleRealtime] = [:]

  // Realtime channel
  private var realtimeChannel: RealtimeChannelV2?

  // Cache
  private var modelContext: ModelContext?

  init() {
    self.client = SupabaseClient(
      supabaseURL: URL(string: Constants.Supabase.supabaseURL)!,
      supabaseKey: Constants.Supabase.supabasePublishableKey,
      options: SupabaseClientOptions(
        db: .init(decoder: JSONDecoder.supabaseDecoder),
        auth: .init(emitLocalSessionAsInitialSession: true)  // see https://github.com/supabase/supabase-swift/pull/822
      )
    )

    // Listen for auth state changes
    Task {
      await listenToAuthChanges()
    }
  }

  // MARK: - Cache Methods

  func configureCache(modelContext: ModelContext) {
    self.modelContext = modelContext
  }

  /// Loads cached vehicles and realtime data from SwiftData into the in-memory arrays.
  func loadCachedData() {
    loadCachedVehicles()
    loadCachedVehicleRealtimeData()
  }

  private func loadCachedVehicles() {
    guard let modelContext else { return }
    do {
      let descriptor = FetchDescriptor<CachedVehicle>(
        sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
      )
      let cached = try modelContext.fetch(descriptor)
      if !cached.isEmpty {
        self.vehicles = cached.map { $0.toVehicle() }
      }
    } catch {
      print("Error loading cached vehicles: \(error)")
    }
  }

  private func saveCachedVehicles(_ vehicles: [Vehicle]) {
    guard let modelContext else { return }
    do {
      let descriptor = FetchDescriptor<CachedVehicle>()
      let existing = try modelContext.fetch(descriptor)
      let existingById = Dictionary(
        uniqueKeysWithValues: existing.map { ($0.id, $0) }
      )

      let currentIds = Set(vehicles.map(\.id))

      // Delete cached vehicles no longer in the list
      for cached in existing where !currentIds.contains(cached.id) {
        modelContext.delete(cached)
      }

      // Insert or update
      for vehicle in vehicles {
        if let cached = existingById[vehicle.id] {
          cached.update(from: vehicle)
        } else {
          modelContext.insert(CachedVehicle(from: vehicle))
        }
      }

      try modelContext.save()
    } catch {
      print("Error saving cached vehicles: \(error)")
    }
  }

  private func loadCachedVehicleRealtimeData() {
    guard let modelContext else { return }
    do {
      let descriptor = FetchDescriptor<CachedVehicleRealtime>()
      let cached = try modelContext.fetch(descriptor)
      for item in cached {
        self.vehicleRealtimeData[item.vehicleId] = item.toVehicleRealtime()
      }
    } catch {
      print("Error loading cached realtime data: \(error)")
    }
  }

  private func saveCachedVehicleRealtime(_ data: VehicleRealtime) {
    guard let modelContext else { return }
    do {
      let vehicleId = data.vehicleId
      var descriptor = FetchDescriptor<CachedVehicleRealtime>(
        predicate: #Predicate { $0.vehicleId == vehicleId }
      )
      descriptor.fetchLimit = 1
      let existing = try modelContext.fetch(descriptor)

      if let cached = existing.first {
        cached.update(from: data)
      } else {
        modelContext.insert(CachedVehicleRealtime(from: data))
      }

      try modelContext.save()
    } catch {
      print("Error saving cached realtime data: \(error)")
    }
  }

  private func deleteCachedVehicle(_ vehicleId: String) {
    guard let modelContext else { return }
    do {
      var vehicleDescriptor = FetchDescriptor<CachedVehicle>(
        predicate: #Predicate { $0.id == vehicleId }
      )
      vehicleDescriptor.fetchLimit = 1
      for v in try modelContext.fetch(vehicleDescriptor) {
        modelContext.delete(v)
      }

      var realtimeDescriptor = FetchDescriptor<CachedVehicleRealtime>(
        predicate: #Predicate { $0.vehicleId == vehicleId }
      )
      realtimeDescriptor.fetchLimit = 1
      for r in try modelContext.fetch(realtimeDescriptor) {
        modelContext.delete(r)
      }

      try modelContext.save()
    } catch {
      print("Error deleting cached vehicle: \(error)")
    }
  }

  private func deleteAllCachedData() {
    guard let modelContext else { return }
    do {
      try modelContext.delete(model: CachedVehicle.self)
      try modelContext.delete(model: CachedVehicleRealtime.self)
      try modelContext.save()
    } catch {
      print("Error clearing cache: \(error)")
    }
  }

  // MARK: - Auth Methods

  private func listenToAuthChanges() async {
    for await state in client.auth.authStateChanges {
      await MainActor.run {
        switch state.event {
        case .initialSession:
          // see https://github.com/supabase/supabase-swift/pull/822
          if let session = state.session {
            if session.isExpired {
              // Session exists but has expired. Supabase will try to refresh it
              // in the background and emit a `tokenRefreshed` or `signedOut` event.
              // Show loading state until we receive the result.
              self.isRefreshingSession = true
              self.isLoading = true
            } else {
              // Session exists and is valid, let user in
              self.currentUser = session.user
              self.isLoggedIn = true
              self.isLoading = false
              self.isRefreshingSession = false

              Task {
                await self.loadUserProfile()
                await self.loadVehicles()
              }
            }
          } else {
            // No session exists, user needs to sign in
            self.currentUser = nil
            self.isLoggedIn = false
            self.isLoading = false
            self.isRefreshingSession = false
          }

        case .signedIn:
          self.currentUser = state.session?.user
          self.isLoggedIn = state.session != nil
          self.isLoading = false
          self.isRefreshingSession = false

          if self.isLoggedIn {
            Task {
              await self.loadUserProfile()
              await self.loadVehicles()
            }
          }

        case .tokenRefreshed:
          // Token was successfully refreshed after expiration
          self.currentUser = state.session?.user
          self.isLoggedIn = state.session != nil
          self.isLoading = false
          self.isRefreshingSession = false

          if self.isLoggedIn {
            Task {
              await self.loadUserProfile()
              await self.loadVehicles()
            }
          }

        case .signedOut:
          self.currentUser = nil
          self.isLoggedIn = false
          self.isLoading = false
          self.isRefreshingSession = false
          self.userProfile = nil
          self.vehicles = []
          self.vehicleRealtimeData = [:]
          self.deleteAllCachedData()
          self.unsubscribeFromRealtime()

        default:
          break
        }
      }
    }
  }

  func loadOrCreateUser(userId: UUID, email: String, fullName: String? = nil) async {
    await MainActor.run {
      self.isLoggedIn = true
    }
    await loadUserProfile(initialDisplayName: fullName)
    await loadVehicles()
  }

  func signOut() async throws {
    try await client.auth.signOut()
    await MainActor.run {
      self.isLoggedIn = false
      self.currentUser = nil
      self.userProfile = nil
      self.vehicles = []
      self.vehicleRealtimeData = [:]
      self.deleteAllCachedData()
    }
  }

  // MARK: - User Profile Methods

  /// Loads the user's profile, creating one if it doesn't exist
  /// - Parameter initialDisplayName: Optional display name to set when creating a new profile (e.g., from Apple Sign In)
  func loadUserProfile(initialDisplayName: String? = nil) async {
    guard let userId = currentUser?.id else { return }

    do {
      // Try to fetch existing profile
      let profiles: [UserProfile] =
        try await client
        .from("user_profiles")
        .select()
        .eq("user_id", value: userId)
        .execute()
        .value

      if let existingProfile = profiles.first {
        // If profile exists but has no display name, and we have one to set, update it
        if existingProfile.displayName == nil || existingProfile.displayName?.isEmpty == true,
          let initialDisplayName, !initialDisplayName.isEmpty
        {
          try? await updateUserProfile(displayName: initialDisplayName)
        } else {
          await MainActor.run {
            self.userProfile = existingProfile
          }
        }
      } else {
        // Create a new profile if one doesn't exist
        var insertData: [String: String] = ["user_id": userId.uuidString]
        if let initialDisplayName, !initialDisplayName.isEmpty {
          insertData["display_name"] = initialDisplayName
        }

        do {
          let newProfile: UserProfile =
            try await client
            .from("user_profiles")
            .insert(insertData)
            .select()
            .single()
            .execute()
            .value

          await MainActor.run {
            self.userProfile = newProfile
          }
        } catch {
          // Handle race condition: profile may have been created by another call
          // Re-fetch the profile instead
          let existingProfiles: [UserProfile] =
            try await client
            .from("user_profiles")
            .select()
            .eq("user_id", value: userId)
            .execute()
            .value

          if let profile = existingProfiles.first {
            await MainActor.run {
              self.userProfile = profile
            }
          }
        }
      }
    } catch {
      print("Error loading user profile: \(error)")
    }
  }

  /// Updates the user's profile with the provided values
  func updateUserProfile(
    displayName: String? = nil,
    avatarPath: String? = nil,
    notificationPreferences: NotificationPreferences? = nil,
    notificationsEnabled: Bool? = nil,
    pushToken: String? = nil
  ) async throws {
    guard let userId = currentUser?.id else { return }

    // Build the update dictionary with only non-nil values
    var updateData: [String: AnyJSON] = [:]

    if let displayName {
      updateData["display_name"] = .string(displayName)
    }
    if let avatarPath {
      updateData["avatar_path"] = .string(avatarPath)
    }
    if let notificationsEnabled {
      updateData["notifications_enabled"] = .bool(notificationsEnabled)
    }
    if let pushToken {
      updateData["push_token"] = .string(pushToken)
    }
    if let notificationPreferences {
      let prefsData = try JSONEncoder().encode(notificationPreferences)
      let prefsJSON = try JSONDecoder().decode(AnyJSON.self, from: prefsData)
      updateData["notification_preferences"] = prefsJSON
    }

    let profile: UserProfile =
      try await client
      .from("user_profiles")
      .update(updateData)
      .eq("user_id", value: userId)
      .select()
      .single()
      .execute()
      .value

    await MainActor.run {
      self.userProfile = profile
    }
  }

  /// Uploads a user avatar image and returns the storage path
  func uploadUserAvatar(imageData: Data) async throws -> String {
    guard let userId = currentUser?.id else {
      throw NSError(
        domain: "SupabaseService", code: 401,
        userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
    }

    let fileName = "\(userId.uuidString)/avatar.jpg"

    // Remove existing avatar if it exists (upsert)
    try? await client.storage
      .from("user-avatars")
      .remove(paths: [fileName])

    // Upload new avatar
    try await client.storage
      .from("user-avatars")
      .upload(fileName, data: imageData, options: .init(contentType: "image/jpeg", upsert: true))

    return fileName
  }

  /// Gets the public URL for a user avatar
  func getUserAvatarURL(path: String) -> URL? {
    try? client.storage
      .from("user-avatars")
      .getPublicURL(path: path)
  }

  // MARK: - Vehicle Methods

  func loadVehicles() async {
    do {
      // Get vehicles the user has access to via the vehicle_access join
      let accessList: [VehicleAccess] =
        try await client
        .from("vehicle_access")
        .select()
        .execute()
        .value

      let vehicleIds = accessList.map { $0.vehicleId }

      if vehicleIds.isEmpty {
        await MainActor.run {
          self.vehicles = []
          self.saveCachedVehicles([])
        }
        return
      }

      // Fetch vehicle details
      let vehicleList: [Vehicle] =
        try await client
        .from("vehicles")
        .select()
        .in("id", values: vehicleIds)
        .execute()
        .value

      await MainActor.run {
        self.vehicles = vehicleList
        self.saveCachedVehicles(vehicleList)
      }

    } catch {
      print("Error loading vehicles: \(error)")
    }
  }

  func loadVehicleRealtimeData(vehicleId: String) async {
    do {
      let realtimeData: VehicleRealtime =
        try await client
        .from("vehicle_realtime")
        .select()
        .eq("vehicle_id", value: vehicleId)
        .single()
        .execute()
        .value

      await MainActor.run {
        self.vehicleRealtimeData[vehicleId] = realtimeData
        self.saveCachedVehicleRealtime(realtimeData)
      }
    } catch {
      print("Error loading vehicle realtime data: \(error)")
    }
  }

  func joinVehicleByInviteCode(_ inviteCode: String) async throws -> JoinVehicleResponse {
    let response: JoinVehicleResponse =
      try await client
      .rpc("join_vehicle_by_invite_code", params: ["p_invite_code": inviteCode.uppercased()])
      .execute()
      .value

    if response.success {
      // Reload vehicles to include the new one
      await loadVehicles()
    }

    return response
  }

  func leaveVehicle(_ vehicleId: String) async throws {
    guard let userId = currentUser?.id else { return }

    try await client
      .from("vehicle_access")
      .delete()
      .eq("vehicle_id", value: vehicleId)
      .eq("user_id", value: userId)
      .execute()

    await MainActor.run {
      self.vehicles.removeAll { $0.id == vehicleId }
      self.vehicleRealtimeData.removeValue(forKey: vehicleId)
      self.deleteCachedVehicle(vehicleId)
    }
  }

  func fetchVehicleAccessUsers(vehicleId: String) async throws -> [VehicleAccessUser] {
    let users: [VehicleAccessUser] =
      try await client
      .rpc("get_vehicle_access_users", params: ["p_vehicle_id": vehicleId])
      .execute()
      .value

    return users
  }

  func removeUserAccess(vehicleId: String, userId: UUID) async throws {
    try await client
      .rpc(
        "remove_vehicle_access",
        params: ["p_vehicle_id": vehicleId, "p_user_id": userId.uuidString]
      )
      .execute()
  }

  // MARK: - Vehicle Update Methods

  /// Updates a vehicle's name and/or description
  func updateVehicle(
    vehicleId: String,
    name: String? = nil,
    description: String? = nil,
    enableYolo: Bool? = nil,
    enableStream: Bool? = nil,
    enableShazam: Bool? = nil,
    enableMicrophone: Bool? = nil,
    enableCamera: Bool? = nil
  ) async throws {
    var updateData: [String: AnyJSON] = [:]

    if let name {
      updateData["name"] = .string(name)
    }
    if let description {
      updateData["description"] = .string(description)
    }
    if let enableYolo {
      updateData["enable_yolo"] = .bool(enableYolo)
    }
    if let enableStream {
      updateData["enable_stream"] = .bool(enableStream)
    }
    if let enableShazam {
      updateData["enable_shazam"] = .bool(enableShazam)
    }
    if let enableMicrophone {
      updateData["enable_microphone"] = .bool(enableMicrophone)
    }
    if let enableCamera {
      updateData["enable_camera"] = .bool(enableCamera)
    }

    guard !updateData.isEmpty else { return }

    let updatedVehicles: [Vehicle] =
      try await client
      .from("vehicles")
      .update(updateData)
      .eq("id", value: vehicleId)
      .select()
      .execute()
      .value

    await MainActor.run {
      if let updatedVehicle = updatedVehicles.first,
        let index = self.vehicles.firstIndex(where: { $0.id == vehicleId })
      {
        self.vehicles[index] = updatedVehicle
      }
      self.saveCachedVehicles(self.vehicles)
    }
  }

  // MARK: - Face Detection Methods

  func fetchFaceDetections(for vehicleId: String, limit: Int = 50) async throws -> [FaceDetection] {
    let detections: [FaceDetection] =
      try await client
      .from("face_detections")
      .select()
      .eq("vehicle_id", value: vehicleId)
      .order("created_at", ascending: false)
      .limit(limit)
      .execute()
      .value

    return detections
  }

  func downloadFaceImage(path: String) async throws -> Data {
    let data = try await client.storage
      .from("face-snapshots")
      .download(path: path)

    return data
  }

  func getFaceImageURL(path: String) async throws -> URL {
    let signedURL = try await client.storage
      .from("face-snapshots")
      .createSignedURL(path: path, expiresIn: 3600)  // 1 hour expiry

    return signedURL
  }

  // MARK: - Driver Profile Methods

  func fetchDriverProfiles(for vehicleId: String) async throws -> [DriverProfile] {
    let profiles: [DriverProfile] =
      try await client
      .from("driver_profiles")
      .select()
      .eq("vehicle_id", value: vehicleId)
      .order("name", ascending: true)
      .execute()
      .value

    return profiles
  }

  func createDriverProfile(vehicleId: String, name: String, notes: String?, imagePath: String?)
    async throws -> DriverProfile
  {
    struct CreateProfileRequest: Encodable {
      let vehicle_id: String
      let name: String
      let notes: String?
      let profile_image_path: String?
      let created_by: UUID?
    }

    let request = CreateProfileRequest(
      vehicle_id: vehicleId,
      name: name,
      notes: notes,
      profile_image_path: imagePath,
      created_by: currentUser?.id
    )

    let profile: DriverProfile =
      try await client
      .from("driver_profiles")
      .insert(request)
      .select()
      .single()
      .execute()
      .value

    return profile
  }

  func assignDriverToDetection(detectionId: UUID, driverProfileId: UUID) async throws {
    struct UpdateRequest: Encodable {
      let driver_profile_id: UUID
    }

    try await client
      .from("face_detections")
      .update(UpdateRequest(driver_profile_id: driverProfileId))
      .eq("id", value: detectionId)
      .execute()
  }

  func fetchUnidentifiedFaces(for vehicleId: String, limit: Int = 20) async throws
    -> [FaceDetection]
  {
    let detections: [FaceDetection] =
      try await client
      .from("face_detections")
      .select()
      .eq("vehicle_id", value: vehicleId)
      .filter("driver_profile_id", operator: "is", value: "null")
      .filter("image_path", operator: "not.is", value: "null")
      .order("created_at", ascending: false)
      .limit(limit)
      .execute()
      .value

    return detections
  }

  func getUnidentifiedFacesCount(for vehicleId: String) async throws -> Int {
    let response =
      try await client
      .from("face_detections")
      .select("id", head: true, count: .exact)
      .eq("vehicle_id", value: vehicleId)
      .filter("driver_profile_id", operator: "is", value: "null")
      .filter("image_path", operator: "not.is", value: "null")
      .execute()

    return response.count ?? 0
  }

  // MARK: - Face Clustering Methods

  /// Fetch all unidentified face clusters for a vehicle
  /// Each cluster groups similar-looking faces together
  func fetchUnidentifiedFaceClusters(for vehicleId: String) async throws -> [FaceCluster] {
    let clusters: [FaceCluster] =
      try await client
      .rpc("get_unidentified_face_clusters", params: ["p_vehicle_id": vehicleId])
      .execute()
      .value

    return clusters
  }

  /// Assign a driver profile to an entire cluster of faces
  /// This will update all faces in the cluster with the given profile ID
  func assignProfileToCluster(clusterId: UUID, profileId: UUID) async throws
    -> AssignClusterResponse
  {
    let response: AssignClusterResponse =
      try await client
      .rpc(
        "assign_profile_to_cluster",
        params: [
          "p_cluster_id": clusterId.uuidString,
          "p_profile_id": profileId.uuidString,
        ]
      )
      .execute()
      .value

    return response
  }

  /// Fetch all face detections belonging to a specific cluster
  func fetchDetectionsForCluster(clusterId: UUID, vehicleId: String, limit: Int = 50) async throws
    -> [FaceDetection]
  {
    let detections: [FaceDetection] =
      try await client
      .from("face_detections")
      .select()
      .eq("vehicle_id", value: vehicleId)
      .eq("face_cluster_id", value: clusterId)
      .order("created_at", ascending: false)
      .limit(limit)
      .execute()
      .value

    return detections
  }

  /// Get count of unidentified face clusters for a vehicle
  func getUnidentifiedClustersCount(for vehicleId: String) async throws -> Int {
    let clusters = try await fetchUnidentifiedFaceClusters(for: vehicleId)
    return clusters.count
  }

  func fetchDetectionsForDriver(profileId: UUID, vehicleId: String, limit: Int = 50) async throws
    -> [FaceDetection]
  {
    let detections: [FaceDetection] =
      try await client
      .from("face_detections")
      .select()
      .eq("vehicle_id", value: vehicleId)
      .eq("driver_profile_id", value: profileId)
      .order("created_at", ascending: false)
      .limit(limit)
      .execute()
      .value

    return detections
  }

  func uploadProfileImage(vehicleId: String, imageData: Data) async throws -> String {
    let fileName = "\(vehicleId)/profiles/\(UUID().uuidString).jpg"

    try await client.storage
      .from("face-snapshots")
      .upload(fileName, data: imageData, options: .init(contentType: "image/jpeg"))

    return fileName
  }

  // MARK: - Vehicle Trip Methods

  func fetchTrips(for vehicleId: String, limit: Int = 50) async throws -> [VehicleTrip] {
    let trips: [VehicleTrip] =
      try await client
      .from("vehicle_trips")
      .select()
      .eq("vehicle_id", value: vehicleId)
      .order("started_at", ascending: false)
      .limit(limit)
      .execute()
      .value

    return trips
  }

  func fetchTripsForToday(for vehicleId: String) async throws -> [VehicleTrip] {
    let calendar = Calendar.current
    let startOfDay = calendar.startOfDay(for: Date())

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    let startOfDayString = formatter.string(from: startOfDay)

    let trips: [VehicleTrip] =
      try await client
      .from("vehicle_trips")
      .select()
      .eq("vehicle_id", value: vehicleId)
      .gte("started_at", value: startOfDayString)
      .order("started_at", ascending: false)
      .execute()
      .value

    return trips
  }

  func fetchDrowsyEvents(for sessionId: UUID, vehicleId: String) async throws -> [FaceDetection] {
    let detections: [FaceDetection] =
      try await client
      .from("face_detections")
      .select()
      .eq("vehicle_id", value: vehicleId)
      .eq("session_id", value: sessionId)
      .eq("is_drowsy", value: true)
      .order("created_at", ascending: false)
      .execute()
      .value

    return detections
  }

  func fetchSpeedingEvents(for sessionId: UUID, vehicleId: String) async throws -> [FaceDetection] {
    let detections: [FaceDetection] =
      try await client
      .from("face_detections")
      .select()
      .eq("vehicle_id", value: vehicleId)
      .eq("session_id", value: sessionId)
      .eq("is_speeding", value: true)
      .order("created_at", ascending: false)
      .execute()
      .value

    return detections
  }

  func fetchExcessiveBlinkingEvents(for sessionId: UUID, vehicleId: String) async throws
    -> [FaceDetection]
  {
    let detections: [FaceDetection] =
      try await client
      .from("face_detections")
      .select()
      .eq("vehicle_id", value: vehicleId)
      .eq("session_id", value: sessionId)
      .eq("is_excessive_blinking", value: true)
      .order("created_at", ascending: false)
      .execute()
      .value

    return detections
  }

  func fetchUnstableEyesEvents(for sessionId: UUID, vehicleId: String) async throws
    -> [FaceDetection]
  {
    let detections: [FaceDetection] =
      try await client
      .from("face_detections")
      .select()
      .eq("vehicle_id", value: vehicleId)
      .eq("session_id", value: sessionId)
      .eq("is_unstable_eyes", value: true)
      .order("created_at", ascending: false)
      .execute()
      .value

    return detections
  }

  func fetchPhoneDistractionEvents(for sessionId: UUID, vehicleId: String) async throws
    -> [FaceDetection]
  {
    let detections: [FaceDetection] =
      try await client
      .from("face_detections")
      .select()
      .eq("vehicle_id", value: vehicleId)
      .eq("session_id", value: sessionId)
      .eq("is_phone_detected", value: true)
      .order("created_at", ascending: false)
      .execute()
      .value

    return detections
  }

  func fetchDrinkingEvents(for sessionId: UUID, vehicleId: String) async throws
    -> [FaceDetection]
  {
    let detections: [FaceDetection] =
      try await client
      .from("face_detections")
      .select()
      .eq("vehicle_id", value: vehicleId)
      .eq("session_id", value: sessionId)
      .eq("is_drinking_detected", value: true)
      .order("created_at", ascending: false)
      .execute()
      .value

    return detections
  }

  // MARK: - Music Detection Methods

  func fetchMusicDetections(for vehicleId: String, limit: Int = 100) async throws
    -> [MusicDetection]
  {
    let detections: [MusicDetection] =
      try await client
      .from("music_detections")
      .select()
      .eq("vehicle_id", value: vehicleId)
      .order("detected_at", ascending: false)
      .limit(limit)
      .execute()
      .value

    return detections
  }

  // MARK: - Realtime Subscription

  func subscribeToVehicleRealtime(vehicleId: String) async {
    // Unsubscribe from existing channel
    unsubscribeFromRealtime()

    // Load initial realtime data
    await loadVehicleRealtimeData(vehicleId: vehicleId)

    let channel = client.realtimeV2.channel("vehicle_realtime_\(vehicleId)")

    let changes = channel.postgresChange(
      AnyAction.self,
      schema: "public",
      table: "vehicle_realtime",
      filter: "vehicle_id=eq.\(vehicleId)"
    )

    await channel.subscribe()

    self.realtimeChannel = channel

    // Listen for changes
    Task {
      for await change in changes {
        await handleRealtimeChange(change)
      }
    }
  }

  private func handleRealtimeChange(_ change: AnyAction) async {
    do {
      switch change {
      case .insert(let action):
        let data = try action.decodeRecord(
          as: VehicleRealtime.self, decoder: JSONDecoder.supabaseDecoder)
        await MainActor.run {
          if self.vehicles.contains(where: { $0.id == data.vehicleId }) {
            self.vehicleRealtimeData[data.vehicleId] = data
            self.saveCachedVehicleRealtime(data)
          }
        }
      case .update(let action):
        let data = try action.decodeRecord(
          as: VehicleRealtime.self, decoder: JSONDecoder.supabaseDecoder)
        await MainActor.run {
          if self.vehicles.contains(where: { $0.id == data.vehicleId }) {
            self.vehicleRealtimeData[data.vehicleId] = data
            self.saveCachedVehicleRealtime(data)
          }
        }
      case .delete:
        break
      }
    } catch {
      print("Error decoding realtime change: \(error)")
    }
  }

  func unsubscribeFromRealtime() {
    Task {
      await realtimeChannel?.unsubscribe()
      realtimeChannel = nil
    }
  }
}

// MARK: - JSON Decoder Extension

extension JSONDecoder {
  static var supabaseDecoder: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let dateString = try container.decode(String.self)

      // Try ISO8601 with fractional seconds
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let date = formatter.date(from: dateString) {
        return date
      }

      // Try without fractional seconds
      formatter.formatOptions = [.withInternetDateTime]
      if let date = formatter.date(from: dateString) {
        return date
      }

      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Cannot decode date: \(dateString)"
      )
    }
    return decoder
  }
}

// MARK: - Environment Key

struct SupabaseServiceKey: EnvironmentKey {
  static let defaultValue = SupabaseService()
}

extension EnvironmentValues {
  var supabaseService: SupabaseService {
    get { self[SupabaseServiceKey.self] }
    set { self[SupabaseServiceKey.self] = newValue }
  }
}

// Global instance for convenience
let supabase = SupabaseService()
