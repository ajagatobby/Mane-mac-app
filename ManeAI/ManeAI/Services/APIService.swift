//
//  APIService.swift
//  ManeAI
//
//  HTTP client for communicating with the NestJS sidecar
//

import Foundation
import Combine

// MARK: - Media Type

enum MediaType: String, Codable, CaseIterable {
    case text
    case image
    case audio
    
    var icon: String {
        switch self {
        case .text: return "doc.text"
        case .image: return "photo"
        case .audio: return "waveform"
        }
    }
    
    var displayName: String {
        switch self {
        case .text: return "Text"
        case .image: return "Image"
        case .audio: return "Audio"
        }
    }
}

// MARK: - API Models

struct IngestRequest: Codable {
    let content: String?
    let filePath: String
    let mediaType: MediaType?
    let metadata: [String: String]?
}

struct IngestResponse: Codable {
    let id: String
    let fileName: String
    let filePath: String
    let mediaType: MediaType
    let success: Bool
    let message: String
}

struct ChatRequest: Codable {
    let query: String
    let stream: Bool?
}

struct ChatResponse: Codable {
    let answer: String
    let sources: [ChatSource]
}

struct ChatSource: Codable, Identifiable {
    var id: String { filePath }
    let fileName: String
    let filePath: String
    let mediaType: MediaType?
    let thumbnailPath: String?
    let relevance: Double
}

struct SearchRequest: Codable {
    let query: String
    let limit: Int?
}

struct SearchResult: Codable, Identifiable {
    let id: String
    let content: String
    let fileName: String
    let filePath: String
    let mediaType: MediaType?
    let thumbnailPath: String?
    let score: Double
}

struct SearchResponse: Codable {
    let results: [SearchResult]
}

struct DocumentListResponse: Codable {
    let documents: [DocumentItem]
    let total: Int
}

struct DocumentItem: Codable, Identifiable {
    let id: String
    let fileName: String
    let filePath: String
    let mediaType: MediaType?
    let thumbnailPath: String?
    let metadata: [String: String]?
}

struct HealthResponse: Codable {
    let status: String
    let timestamp: String
    let uptime: Double
}

struct OllamaStatus: Codable {
    let available: Bool
    let model: String
    let url: String
}

// MARK: - API Errors

enum APIError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case decodingError(Error)
    case serverError(Int, String)
    case sidecarNotRunning
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        case .sidecarNotRunning:
            return "Sidecar is not running"
        }
    }
}

// MARK: - API Service

@MainActor
class APIService: ObservableObject {
    
    private let baseURL: URL
    private let session: URLSession
    private let maxRetries = 3
    private let retryDelay: TimeInterval = 1.0
    
    @Published var isConnected = false
    
    init(baseURL: URL = URL(string: "http://127.0.0.1:3000")!) {
        self.baseURL = baseURL
        
        let config = URLSessionConfiguration.default
        // Increased timeout for CLIP/Whisper model loading and processing
        config.timeoutIntervalForRequest = 180  // 3 minutes for media processing
        config.timeoutIntervalForResource = 600 // 10 minutes for large files
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Health Check
    
    func checkHealth() async throws -> HealthResponse {
        let response: HealthResponse = try await get(path: "/health")
        isConnected = true
        return response
    }
    
    // MARK: - Ingest Endpoints
    
    func ingestDocument(content: String? = nil, filePath: String, mediaType: MediaType? = nil, metadata: [String: String]? = nil) async throws -> IngestResponse {
        let request = IngestRequest(content: content, filePath: filePath, mediaType: mediaType, metadata: metadata)
        return try await post(path: "/ingest", body: request)
    }
    
    /// Ingest a media file (image, audio) - no content needed
    func ingestMediaFile(filePath: String, mediaType: MediaType? = nil, metadata: [String: String]? = nil) async throws -> IngestResponse {
        let request = IngestRequest(content: nil, filePath: filePath, mediaType: mediaType, metadata: metadata)
        return try await post(path: "/ingest", body: request)
    }
    
    func deleteDocument(id: String) async throws {
        let _: EmptyResponse = try await delete(path: "/ingest/\(id)")
    }
    
    func listDocuments() async throws -> DocumentListResponse {
        return try await get(path: "/ingest")
    }
    
    func getDocumentCount() async throws -> Int {
        let response: [String: Int] = try await get(path: "/ingest/count")
        return response["count"] ?? 0
    }
    
    // MARK: - Chat Endpoints
    
    func chat(query: String) async throws -> ChatResponse {
        let request = ChatRequest(query: query, stream: false)
        return try await post(path: "/chat", body: request)
    }
    
    func chatStream(query: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let url = baseURL.appendingPathComponent("/chat")
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    
                    let body = ChatRequest(query: query, stream: true)
                    request.httpBody = try JSONEncoder().encode(body)
                    
                    let (bytes, response) = try await session.bytes(for: request)
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw APIError.networkError(NSError(domain: "Invalid response", code: 0))
                    }
                    
                    if httpResponse.statusCode != 200 {
                        throw APIError.serverError(httpResponse.statusCode, "Stream failed")
                    }
                    
                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let jsonString = String(line.dropFirst(6))
                            if let data = jsonString.data(using: .utf8),
                               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                
                                if let done = json["done"] as? Bool, done {
                                    continuation.finish()
                                    return
                                }
                                
                                if let content = json["content"] as? String {
                                    continuation.yield(content)
                                }
                                
                                if let error = json["error"] as? String {
                                    throw APIError.serverError(500, error)
                                }
                            }
                        }
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    func search(query: String, limit: Int = 5) async throws -> SearchResponse {
        let request = SearchRequest(query: query, limit: limit)
        return try await post(path: "/chat/search", body: request)
    }
    
    func getOllamaStatus() async throws -> OllamaStatus {
        return try await get(path: "/chat/status")
    }
    
    // MARK: - Private HTTP Methods
    
    private func get<T: Decodable>(path: String) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        return try await performRequest(request)
    }
    
    private func post<T: Decodable, B: Encodable>(path: String, body: B) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        
        return try await performRequest(request)
    }
    
    private func delete<T: Decodable>(path: String) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        return try await performRequest(request)
    }
    
    private func performRequest<T: Decodable>(_ request: URLRequest, attempt: Int = 0) async throws -> T {
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.networkError(NSError(domain: "Invalid response", code: 0))
            }
            
            if httpResponse.statusCode >= 400 {
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw APIError.serverError(httpResponse.statusCode, message)
            }
            
            do {
                let decoder = JSONDecoder()
                return try decoder.decode(T.self, from: data)
            } catch {
                throw APIError.decodingError(error)
            }
            
        } catch let error as APIError {
            throw error
        } catch {
            // Retry on network errors
            if attempt < maxRetries {
                try await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
                return try await performRequest(request, attempt: attempt + 1)
            }
            throw APIError.networkError(error)
        }
    }
}

// Helper for empty responses
private struct EmptyResponse: Decodable {}
