//
//  SidecarManager.swift
//  ManeAI
//
//  Manages the lifecycle of the NestJS sidecar process
//

import Foundation
import Combine

/// Manages the NestJS sidecar process lifecycle
@MainActor
class SidecarManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var isRunning = false
    @Published private(set) var isHealthy = false
    @Published private(set) var lastError: String?
    @Published private(set) var logs: [String] = []
    
    // MARK: - Configuration
    
    let port: Int
    let baseURL: URL
    
    // MARK: - Private Properties
    
    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var healthCheckTimer: Timer?
    private var restartAttempts = 0
    private let maxRestartAttempts = 5
    private let restartDelay: TimeInterval = 2.0
    
    // MARK: - Paths
    
    private var nodePath: String {
        // Check for bundled Node.js in Resources/node/
        if let bundledNode = Bundle.main.path(forResource: "node", ofType: nil, inDirectory: "node") {
            log("Using bundled Node.js: \(bundledNode)")
            return bundledNode
        }
        
        // Check for bundled Node.js in Resources/ (alternative location)
        if let resourcePath = Bundle.main.resourcePath {
            let nodePaths = [
                "\(resourcePath)/node/node",
                "\(resourcePath)/node"
            ]
            for path in nodePaths {
                if FileManager.default.fileExists(atPath: path) {
                    log("Using bundled Node.js: \(path)")
                    return path
                }
            }
        }
        
        // Fall back to common system Node.js locations
        let systemPaths = [
            "/opt/homebrew/bin/node",  // Homebrew on Apple Silicon
            "/usr/local/bin/node",      // Homebrew on Intel / manual install
            "/usr/bin/node"             // System install
        ]
        
        for path in systemPaths {
            if FileManager.default.fileExists(atPath: path) {
                log("Using system Node.js: \(path)")
                return path
            }
        }
        
        // Last resort
        return "/usr/local/bin/node"
    }
    
    private var sidecarPath: String? {
        // Look for sidecar in the app bundle - Resources/sidecar/dist/main.js
        if let path = Bundle.main.path(forResource: "main", ofType: "js", inDirectory: "sidecar/dist") {
            return path
        }
        
        // Alternative: check Resources directory directly
        if let resourcePath = Bundle.main.resourcePath {
            let sidecarMain = "\(resourcePath)/sidecar/dist/main.js"
            if FileManager.default.fileExists(atPath: sidecarMain) {
                return sidecarMain
            }
        }
        
        return nil
    }
    
    private var dbPath: String {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        
        let maneAIDir = appSupport.appendingPathComponent("ManePaw", isDirectory: true)
        let dbDir = maneAIDir.appendingPathComponent("lancedb", isDirectory: true)
        
        // Ensure directory exists
        try? FileManager.default.createDirectory(
            at: dbDir,
            withIntermediateDirectories: true
        )
        
        return dbDir.path
    }
    
    // MARK: - Initialization
    
    init(port: Int = 3000) {
        self.port = port
        self.baseURL = URL(string: "http://127.0.0.1:\(port)")!
    }
    
    // MARK: - Lifecycle
    
    /// Start the sidecar process
    func start() async {
        guard !isRunning else {
            log("Sidecar is already running")
            return
        }
        
        // For development, check if sidecar exists
        guard let sidecarMainPath = sidecarPath else {
            log("⚠️ Sidecar not found in bundle. Running in development mode.")
            log("To test, run the backend separately: cd mane-ai-backend && pnpm start:dev")
            
            // In development, just check if the backend is already running
            await checkHealth()
            return
        }
        
        log("Starting sidecar from: \(sidecarMainPath)")
        log("Database path: \(dbPath)")
        
        await startProcess(sidecarPath: sidecarMainPath)
    }
    
    /// Stop the sidecar process
    func stop() {
        log("Stopping sidecar...")
        
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
        
        if let currentProcess = process, currentProcess.isRunning {
            currentProcess.terminate()
            
            // Give it time to clean up
            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                if currentProcess.isRunning {
                    currentProcess.interrupt()
                }
                await MainActor.run {
                    self.process = nil
                }
            }
        }
        
        isRunning = false
        isHealthy = false
        restartAttempts = 0
    }
    
    // MARK: - Private Methods
    
    private func startProcess(sidecarPath: String) async {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: nodePath)
        
        // Set arguments
        task.arguments = [
            sidecarPath,
            "--db-path", dbPath,
            "--port", String(port)
        ]
        
        // Set environment
        var environment = ProcessInfo.processInfo.environment
        environment["NODE_ENV"] = "production"
        
        // Set NODE_PATH for the sidecar's node_modules
        if let resourcePath = Bundle.main.resourcePath {
            let nodeModulesPath = "\(resourcePath)/sidecar/node_modules"
            environment["NODE_PATH"] = nodeModulesPath
            log("NODE_PATH set to: \(nodeModulesPath)")
        }
        
        // Set working directory to sidecar folder for proper module resolution
        let sidecarURL = URL(fileURLWithPath: sidecarPath)
        let sidecarDir = sidecarURL.deletingLastPathComponent().deletingLastPathComponent().path
        task.currentDirectoryURL = URL(fileURLWithPath: sidecarDir)
        log("Working directory set to: \(sidecarDir)")
        
        task.environment = environment
        
        // Set up pipes for output
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe
        self.outputPipe = outputPipe
        self.errorPipe = errorPipe
        
        // Handle output
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                Task { @MainActor in
                    self?.log("[Sidecar] \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
                }
            }
        }
        
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                Task { @MainActor in
                    self?.log("[Sidecar Error] \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
                }
            }
        }
        
        // Handle termination
        task.terminationHandler = { [weak self] process in
            Task { @MainActor in
                self?.handleTermination(exitCode: process.terminationStatus)
            }
        }
        
        do {
            try task.run()
            self.process = task
            isRunning = true
            log("Sidecar process started with PID: \(task.processIdentifier)")
            
            // Wait a moment for the server to start
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            // Start health checks
            startHealthChecks()
            
        } catch {
            log("Failed to start sidecar: \(error.localizedDescription)")
            lastError = error.localizedDescription
            isRunning = false
            
            // Attempt restart
            await attemptRestart()
        }
    }
    
    private func handleTermination(exitCode: Int32) {
        log("Sidecar terminated with exit code: \(exitCode)")
        isRunning = false
        isHealthy = false
        
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        
        if exitCode != 0 {
            lastError = "Sidecar crashed with exit code \(exitCode)"
            Task {
                await attemptRestart()
            }
        }
    }
    
    private func attemptRestart() async {
        guard restartAttempts < maxRestartAttempts else {
            log("Max restart attempts reached. Giving up.")
            lastError = "Sidecar failed to start after \(maxRestartAttempts) attempts"
            return
        }
        
        restartAttempts += 1
        let delay = restartDelay * Double(restartAttempts)
        log("Attempting restart \(restartAttempts)/\(maxRestartAttempts) in \(delay) seconds...")
        
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        
        await start()
    }
    
    private func startHealthChecks() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkHealth()
            }
        }
        
        // Immediate first check
        Task {
            await checkHealth()
        }
    }
    
    func checkHealth() async {
        let healthURL = baseURL.appendingPathComponent("health")
        
        do {
            let (_, response) = try await URLSession.shared.data(from: healthURL)
            
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                if !isHealthy {
                    log("✅ Sidecar is healthy")
                }
                isHealthy = true
                lastError = nil
                restartAttempts = 0
            } else {
                isHealthy = false
                lastError = "Health check returned non-200 status"
            }
        } catch {
            if isHealthy {
                log("⚠️ Health check failed: \(error.localizedDescription)")
            }
            isHealthy = false
        }
    }
    
    private func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logMessage = "[\(timestamp)] \(message)"
        logs.append(logMessage)
        print(logMessage)
        
        // Keep only last 100 log entries
        if logs.count > 100 {
            logs.removeFirst(logs.count - 100)
        }
    }
}
