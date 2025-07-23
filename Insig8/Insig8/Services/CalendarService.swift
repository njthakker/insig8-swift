import Foundation
import EventKit
import Combine

@MainActor
class CalendarService: ObservableObject {
    @Published var events: [EKEvent] = []
    @Published var isAuthorized = false
    @Published var isLoading = false
    
    private let eventStore = EKEventStore()
    private var calendars: [EKCalendar] = []
    
    init() {
        checkAuthorizationStatus()
    }
    
    func checkAuthorizationStatus() {
        let status = EKEventStore.authorizationStatus(for: .event)
        
        switch status {
        case .notDetermined:
            requestAccess()
        case .authorized, .fullAccess:
            isAuthorized = true
            loadCalendars()
        case .denied, .restricted, .writeOnly:
            isAuthorized = false
        @unknown default:
            isAuthorized = false
        }
    }
    
    func requestAccess() {
        eventStore.requestFullAccessToEvents { granted, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isAuthorized = granted
                if granted {
                    self.loadCalendars()
                }
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
}