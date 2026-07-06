import Foundation
import CoreGraphics
import ApplicationServices
import AppKit
import IOKit.hid

public enum PermissionStatus: Sendable {
    case authorized
    case denied
    case notDetermined
}

@MainActor
public final class PermissionCenter {
    public static let shared = PermissionCenter()
    private static let axPromptOptionKey = "AXTrustedCheckOptionPrompt"
    
    private init() {}
    
    // MARK: - 1. Listen Event Access (For Recording)
    
    public func checkListenEventAccess() -> PermissionStatus {
        if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted {
            return .authorized
        }

        if #available(macOS 14.4, *) {
            return CGPreflightListenEventAccess() ? .authorized : .denied
        } else {
            return .denied
        }
    }
    
    public func requestListenEventAccess() -> Bool {
        if IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) {
            return true
        }

        if #available(macOS 14.4, *) {
            return CGRequestListenEventAccess()
        } else {
            return false
        }
    }
    
    // MARK: - 2. Post Event Access (For Playback)
    
    public func checkPostEventAccess() -> PermissionStatus {
        if #available(macOS 14.4, *) {
            return CGPreflightPostEventAccess() ? .authorized : .denied
        } else {
            return AXIsProcessTrusted() ? .authorized : .denied
        }
    }
    
    public func requestPostEventAccess() -> Bool {
        if #available(macOS 14.4, *) {
            return CGRequestPostEventAccess()
        } else {
            let options = [Self.axPromptOptionKey: true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }
    }
    
    // MARK: - 3. Screen Capture Access (For Pixel Matching/OCR)
    
    public func checkScreenCaptureAccess() -> PermissionStatus {
        if #available(macOS 10.15, *) {
            return CGPreflightScreenCaptureAccess() ? .authorized : .denied
        } else {
            return .authorized
        }
    }
    
    public func requestScreenCaptureAccess() -> Bool {
        if #available(macOS 10.15, *) {
            return CGRequestScreenCaptureAccess()
        } else {
            return true
        }
    }
    
    // MARK: - 4. Accessibility Access (For UIElement / Window Introspection)
    
    public func checkAccessibilityAccess() -> PermissionStatus {
        return AXIsProcessTrusted() ? .authorized : .denied
    }
    
    public func requestAccessibilityAccess() -> Bool {
        let options = [Self.axPromptOptionKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
    
    // MARK: - Convenience methods
    
    public func checkAllRequiredPermissions() -> Bool {
        return checkListenEventAccess() == .authorized &&
               checkPostEventAccess() == .authorized &&
               checkAccessibilityAccess() == .authorized &&
               checkScreenCaptureAccess() == .authorized
    }
}
