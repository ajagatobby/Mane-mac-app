//
//  OverlayPanel.swift
//  ManeAI
//
//  Production-quality NSPanel subclass for Raycast-style overlay
//  Uses proper window levels and focus management for macOS overlay behavior
//

import AppKit
import SwiftUI

/// A custom NSPanel subclass designed for Raycast-like overlay behavior.
/// This panel floats above all windows (including full-screen apps),
/// accepts keyboard input, and auto-dismisses when focus is lost.
class OverlayPanel: NSPanel {
    
    /// Callback invoked when the panel is dismissed via resignKey
    var onDismiss: (() -> Void)?
    
    init(contentRect: NSRect, backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(
            contentRect: contentRect,
            // Use borderless + nonactivatingPanel for clean overlay without window chrome
            styleMask: [.borderless, .nonactivatingPanel],
            backing: backing,
            defer: flag
        )
        
        configurePanel()
    }
    
    private func configurePanel() {
        // MARK: - Window Level & Collection Behavior
        
        // Float above everything including full-screen apps
        // .mainMenu level is higher than .floating and works with full-screen spaces
        self.level = .mainMenu
        
        // Allow panel to appear on all spaces and alongside full-screen apps
        // .canJoinAllSpaces - panel follows user across Mission Control spaces
        // .fullScreenAuxiliary - panel can appear over full-screen apps
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        // MARK: - Visual Appearance
        
        // Fully transparent window background - SwiftUI handles all visuals
        self.backgroundColor = .clear
        self.isOpaque = false
        
        // Disable window shadow - SwiftUI applies its own shadow
        self.hasShadow = false
        
        // MARK: - Behavior Configuration
        
        // Allow dragging by clicking anywhere on the panel background
        self.isMovableByWindowBackground = true
        
        // Keep panel in memory when closed (for fast re-opening)
        self.isReleasedWhenClosed = false
        
        // Mark as floating panel for proper AppKit handling
        self.isFloatingPanel = true
        
        // Animation behavior for smooth transitions
        self.animationBehavior = .utilityWindow
        
        // Accept mouse events for hover states
        self.acceptsMouseMovedEvents = true
    }
    
    // MARK: - Window Behavior Overrides
    
    /// Allow the panel to become the key window to accept keyboard input
    /// Essential for text fields and keyboard navigation
    override var canBecomeKey: Bool {
        return true
    }
    
    /// Allow panel to become main window for proper focus handling
    override var canBecomeMain: Bool {
        return true
    }
    
    /// Auto-dismiss when the panel loses key window status (user clicked elsewhere)
    /// This is the "proper" Raycast behavior - panel disappears when you click outside
    override func resignKey() {
        super.resignKey()
        // Hide the panel instead of closing to preserve state
        self.orderOut(nil)
        // Notify manager of dismissal
        onDismiss?()
    }
    
    // MARK: - Presentation Methods
    
    /// Show the panel with fade-in animation
    func present(at position: NSPoint? = nil) {
        if let position = position {
            self.setFrameOrigin(position)
        } else {
            centerOnScreen()
        }
        
        // Start invisible for fade-in
        self.alphaValue = 0
        self.makeKeyAndOrderFront(nil)
        
        // Animate appearance
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1
        }
    }
    
    /// Hide the panel with fade-out animation
    func dismiss(completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
            completion?()
        })
    }
    
    /// Center the panel on the main screen, positioned near the top (Raycast-style)
    func centerOnScreen() {
        guard let screen = NSScreen.main else {
            self.center()
            return
        }
        
        let screenFrame = screen.visibleFrame
        let panelFrame = self.frame
        
        // Center horizontally, position near top (about 100 points from top)
        let x = screenFrame.origin.x + (screenFrame.width - panelFrame.width) / 2
        let y = screenFrame.origin.y + screenFrame.height - panelFrame.height - 100
        
        self.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
