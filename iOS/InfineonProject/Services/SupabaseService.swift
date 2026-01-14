//
//  SupabaseService.swift
//  InfineonProject
//
//  Created by Aaron Ma on 1/13/26.
//

import SwiftUI
import Supabase

// MARK: - Models

struct Vehicle: Codable, Identifiable {
    let id: String
    let createdAt: Date
    let updatedAt: Date
    let name: String?
    let description: String?
    let inviteCode: String
    let ownerId: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case name, description
        case inviteCode = "invite_code"
        case ownerId = "owner_id"
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

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case vehicleId = "vehicle_id"
        case driverProfileId = "driver_profile_id"
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

// MARK: - SupabaseService

@Observable
class SupabaseService {
    let client: SupabaseClient

    // Auth state
    var isLoggedIn = false
    var isLoading = true
    var currentUser: User?

    // Vehicle state
    var vehicles: [Vehicle] = []
    var vehicleRealtimeData: [String: VehicleRealtime] = [:]

    // Realtime channel
    private var realtimeChannel: RealtimeChannelV2?

    init() {
        self.client = SupabaseClient(
            supabaseURL: URL(string: Constants.Supabase.supabaseURL)!,
            supabaseKey: Constants.Supabase.supabasePublishableKey
        )

        // Listen for auth state changes
        Task {
            await listenToAuthChanges()
        }
    }

    // MARK: - Auth Methods

    private func listenToAuthChanges() async {
        for await state in client.auth.authStateChanges {
            await MainActor.run {
                switch state.event {
                case .initialSession, .signedIn:
                    self.currentUser = state.session?.user
                    self.isLoggedIn = state.session != nil
                    self.isLoading = false

                    // Load vehicles when signed in
                    if self.isLoggedIn {
                        Task {
                            await self.loadVehicles()
                        }
                    }
                case .signedOut:
                    self.currentUser = nil
                    self.isLoggedIn = false
                    self.isLoading = false
                    self.vehicles = []
                    self.vehicleRealtimeData = [:]
                    self.unsubscribeFromRealtime()
                default:
                    break
                }
            }
        }
    }

    func loadOrCreateUser(userId: UUID, email: String) async {
        // This can be extended to create a user profile in a custom table if needed
        await MainActor.run {
            self.isLoggedIn = true
        }
        await loadVehicles()
    }

    func signOut() async throws {
        try await client.auth.signOut()
        await MainActor.run {
            self.isLoggedIn = false
            self.currentUser = nil
            self.vehicles = []
            self.vehicleRealtimeData = [:]
        }
    }

    // MARK: - Vehicle Methods

    func loadVehicles() async {
        do {
            // Get vehicles the user has access to via the vehicle_access join
            let accessList: [VehicleAccess] = try await client
                .from("vehicle_access")
                .select()
                .execute()
                .value

            let vehicleIds = accessList.map { $0.vehicleId }

            if vehicleIds.isEmpty {
                await MainActor.run {
                    self.vehicles = []
                }
                return
            }

            // Fetch vehicle details
            let vehicleList: [Vehicle] = try await client
                .from("vehicles")
                .select()
                .in("id", values: vehicleIds)
                .execute()
                .value

            await MainActor.run {
                self.vehicles = vehicleList
            }

            // Subscribe to realtime updates for these vehicles
            await subscribeToVehicleRealtime(vehicleIds: vehicleIds)

            // Fetch initial realtime data
            await loadVehicleRealtimeData(vehicleIds: vehicleIds)

        } catch {
            print("Error loading vehicles: \(error)")
        }
    }

    func loadVehicleRealtimeData(vehicleIds: [String]) async {
        guard !vehicleIds.isEmpty else { return }

        do {
            let realtimeList: [VehicleRealtime] = try await client
                .from("vehicle_realtime")
                .select()
                .in("vehicle_id", values: vehicleIds)
                .execute()
                .value

            await MainActor.run {
                for data in realtimeList {
                    self.vehicleRealtimeData[data.vehicleId] = data
                }
            }
        } catch {
            print("Error loading vehicle realtime data: \(error)")
        }
    }

    func joinVehicleByInviteCode(_ inviteCode: String) async throws -> JoinVehicleResponse {
        let response: JoinVehicleResponse = try await client
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
        }
    }

    // MARK: - Face Detection Methods

    func fetchFaceDetections(for vehicleId: String, limit: Int = 50) async throws -> [FaceDetection] {
        let detections: [FaceDetection] = try await client
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
            .createSignedURL(path: path, expiresIn: 3600) // 1 hour expiry

        return signedURL
    }

    // MARK: - Driver Profile Methods

    func fetchDriverProfiles(for vehicleId: String) async throws -> [DriverProfile] {
        let profiles: [DriverProfile] = try await client
            .from("driver_profiles")
            .select()
            .eq("vehicle_id", value: vehicleId)
            .order("name", ascending: true)
            .execute()
            .value

        return profiles
    }

    func createDriverProfile(vehicleId: String, name: String, notes: String?, imagePath: String?) async throws -> DriverProfile {
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

        let profile: DriverProfile = try await client
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

    func fetchUnidentifiedFaces(for vehicleId: String, limit: Int = 20) async throws -> [FaceDetection] {
        let detections: [FaceDetection] = try await client
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
        let response = try await client
            .from("face_detections")
            .select("id", head: true, count: .exact)
            .eq("vehicle_id", value: vehicleId)
            .filter("driver_profile_id", operator: "is", value: "null")
            .filter("image_path", operator: "not.is", value: "null")
            .execute()

        return response.count ?? 0
    }

    func fetchDetectionsForDriver(profileId: UUID, vehicleId: String, limit: Int = 50) async throws -> [FaceDetection] {
        let detections: [FaceDetection] = try await client
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

    // MARK: - Realtime Subscription

    private func subscribeToVehicleRealtime(vehicleIds: [String]) async {
        // Unsubscribe from existing channel
        unsubscribeFromRealtime()

        guard !vehicleIds.isEmpty else { return }

        let channel = client.realtimeV2.channel("vehicle_realtime_updates")

        let changes = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "vehicle_realtime"
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
                let data = try action.decodeRecord(as: VehicleRealtime.self, decoder: JSONDecoder.supabaseDecoder)
                await MainActor.run {
                    if self.vehicles.contains(where: { $0.id == data.vehicleId }) {
                        self.vehicleRealtimeData[data.vehicleId] = data
                    }
                }
            case .update(let action):
                let data = try action.decodeRecord(as: VehicleRealtime.self, decoder: JSONDecoder.supabaseDecoder)
                await MainActor.run {
                    if self.vehicles.contains(where: { $0.id == data.vehicleId }) {
                        self.vehicleRealtimeData[data.vehicleId] = data
                    }
                }
            case .delete:
                // Handle delete if needed
                break
            }
        } catch {
            print("Error decoding realtime change: \(error)")
        }
    }

    private func unsubscribeFromRealtime() {
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
