import Foundation
import EventKit
import Combine
import AppKit
import SwiftUI

@MainActor
class CalendarService: ObservableObject {
    @Published var events: [EKEvent] = []
    @Published var isAuthorized = false
    @Published var isLoading = false
    
    private let eventStore = EKEventStore()
    private var calendars: [EKCalendar] = []
    
    init() {
        checkAuthorizationStatus()
        print("Calendar service initialized - authorization status: \(EKEventStore.authorizationStatus(for: .event))")
    }
    
    func checkAuthorizationStatus() {
        let status = EKEventStore.authorizationStatus(for: .event)
        print("Calendar authorization status: \(status)")
        
        switch status {
        case .notDetermined:
            print("Calendar access not determined - will request on button tap")
            isAuthorized = false
        case .fullAccess:
            print("Calendar access authorized")
            isAuthorized = true
            loadCalendars()
        case .denied, .restricted, .writeOnly:
            print("Calendar access denied/restricted")
            isAuthorized = false
        @unknown default:
            print("Calendar access unknown status")
            isAuthorized = false
        }
    }
    
    func requestAccess() {
        print("Calendar access requested - checking current status...")
        
        let currentStatus = EKEventStore.authorizationStatus(for: .event)
        print("Current calendar authorization status: \(currentStatus)")
        
        switch currentStatus {
        case .fullAccess:
            print("Already have full calendar access")
            isAuthorized = true
            loadCalendars()
            return
            
        case .denied, .restricted:
            print("Calendar access previously denied or restricted")
            showSystemSettingsAlert()
            return
            
        case .notDetermined:
            print("Calendar access not determined - attempting permission request to register app")
            attemptPermissionRequest()
            return
            
        case .writeOnly:
            print("Only write access available - requesting full access via System Settings")
            showSystemSettingsAlert()
            return
            
        @unknown default:
            print("Unknown calendar authorization status")
            showSystemSettingsAlert()
            return
        }
    }
    
    private func attemptPermissionRequest() {
        print("Attempting direct permission request without sandboxing restrictions...")
        
        // Force app to become regular app with dock icon for permission dialog
        print("Changing app to regular activation policy...")
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        
        // Ensure we're frontmost
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        
        print("App should now be visible in dock and frontmost")
        
        // Wait a moment for app to fully activate
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("Now requesting calendar permission...")
            
            self.eventStore.requestFullAccessToEvents { [weak self] granted, error in
                DispatchQueue.main.async {
                    print("=== PERMISSION RESULT ===")
                    print("Granted: \(granted)")
                    print("Error: \(String(describing: error))")
                    print("Current status: \(EKEventStore.authorizationStatus(for: .event))")
                    print("========================")
                    
                    if granted {
                        print("SUCCESS: Calendar access granted!")
                        Task { @MainActor in
                            await self?.updateAuthorizationStatus(true)
                            self?.loadCalendars()
                        }
                    } else {
                        print("Permission denied - checking if app is now visible in System Settings")
                        self?.checkPermissionStatus()
                    }
                    
                    // Return to accessory mode after a delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        print("Returning to accessory mode...")
                        NSApp.setActivationPolicy(.accessory)
                    }
                }
            }
        }
    }
    
    private func checkPermissionStatus() {
        let currentStatus = EKEventStore.authorizationStatus(for: .event)
        print("Checking permission status after request: \(currentStatus)")
        
        switch currentStatus {
        case .fullAccess:
            print("Full access granted!")
            Task { @MainActor in
                self.isAuthorized = true
                self.loadCalendars()
            }
        case .denied:
            print("Access denied - directing to System Settings")
            showSystemSettingsAlert()
        case .restricted:
            print("Access restricted - directing to System Settings")
            showSystemSettingsAlert()
        case .writeOnly:
            print("Write-only access - requesting full access via System Settings")
            showSystemSettingsAlert()
        case .notDetermined:
            print("Still not determined - this may be a macOS 26 beta issue")
            showSystemSettingsAlert()
        @unknown default:
            print("Unknown status - directing to System Settings")
            showSystemSettingsAlert()
        }
    }
    
    private func showSystemSettingsAlert() {
        print("Showing System Settings alert")
        
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Calendar Access Required"
            alert.informativeText = "Insig8 needs calendar access to show your events.\n\n1. Open System Settings\n2. Go to Privacy & Security > Calendar\n3. Enable access for Insig8\n\nIf Insig8 doesn't appear in the list, try clicking 'Grant Access' again first."
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Cancel")
            alert.alertStyle = .informational
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                self.openSystemSettings()
            }
        }
    }
    
    private func loadCalendars() {
        calendars = eventStore.calendars(for: .event)
        loadUpcomingEvents()
    }
    
    func loadUpcomingEvents(days: Int = 30) {
        guard isAuthorized else { return }
        
        isLoading = true
        
        let startDate = Date()
        let endDate = Calendar.current.date(byAdding: .day, value: days, to: startDate) ?? Date()
        
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)
        let events = eventStore.events(matching: predicate)
        
        Task { @MainActor in
            self.events = events.sorted { $0.startDate < $1.startDate }
            self.isLoading = false
        }
    }
    
    func searchEvents(query: String) -> [EKEvent] {
        return events.filter { event in
            event.title.lowercased().contains(query.lowercased()) ||
            event.location?.lowercased().contains(query.lowercased()) == true ||
            event.notes?.lowercased().contains(query.lowercased()) == true
        }
    }
    
    func eventsForToday() -> [EKEvent] {
        let today = Date()
        let calendar = Calendar.current
        
        return events.filter { event in
            calendar.isDate(event.startDate, inSameDayAs: today)
        }
    }
    
    func recheckPermissions() {
        print("Rechecking calendar permissions...")
        checkAuthorizationStatus()
    }
    
    private func openSystemSettings() {
        print("Opening System Settings for Calendar permissions")
        let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!
        NSWorkspace.shared.open(settingsURL)
    }
    
    func createEvent(title: String, startDate: Date, endDate: Date, location: String? = nil, notes: String? = nil) {
        guard isAuthorized else { return }
        
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.location = location
        event.notes = notes
        event.calendar = eventStore.defaultCalendarForNewEvents
        
        do {
            try eventStore.save(event, span: .thisEvent)
            loadUpcomingEvents() // Refresh events
        } catch {
            print("Error creating event: \(error.localizedDescription)")
        }
    }
    
    @MainActor
    private func updateAuthorizationStatus(_ authorized: Bool) async {
        isAuthorized = authorized
    }
}