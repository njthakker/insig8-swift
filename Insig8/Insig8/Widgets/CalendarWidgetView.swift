import SwiftUI
import EventKit
import Combine

struct CalendarWidgetView: View {
    @EnvironmentObject var appStore: AppStore
    @StateObject private var calendarService = CalendarService()
    
    var body: some View {
        VStack {
            if !calendarService.isAuthorized {
                CalendarPermissionView(calendarService: calendarService)
            } else {
                CalendarEventsListView(calendarService: calendarService)
            }
        }
        .onAppear {
            calendarService.checkAuthorizationStatus()
        }
    }
}

struct CalendarPermissionView: View {
    @ObservedObject var calendarService: CalendarService
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text("Calendar Access Required")
                .font(.title2)
            
            VStack(spacing: 12) {
                Text("Insig8 needs calendar access to show your events:")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("1.")
                            .fontWeight(.semibold)
                        Text("Open System Settings")
                    }
                    .font(.caption)
                    
                    HStack {
                        Text("2.")
                            .fontWeight(.semibold)
                        Text("Go to Privacy & Security > Calendar")
                    }
                    .font(.caption)
                    
                    HStack {
                        Text("3.")
                            .fontWeight(.semibold)
                        Text("Enable access for Insig8")
                    }
                    .font(.caption)
                }
                .foregroundColor(.secondary)
            }
            
            VStack(spacing: 12) {
                Button("Open System Settings") {
                    print("Opening System Settings for calendar permissions")
                    calendarService.requestAccess()
                }
                .buttonStyle(.borderedProminent)
                
                Button("I've granted access - Recheck") {
                    print("Rechecking calendar permissions")
                    calendarService.recheckPermissions()
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct CalendarDeniedView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "calendar.badge.minus")
                .font(.system(size: 48))
                .foregroundColor(.red)
            
            Text("Calendar Access Denied")
                .font(.title2)
            
            Text("Please enable calendar access in System Settings")
                .font(.body)
                .foregroundColor(.secondary)
            
            Button("Open System Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct CalendarEventsListView: View {
    @ObservedObject var calendarService: CalendarService
    @EnvironmentObject var appStore: AppStore
    
    var body: some View {
        VStack(spacing: 12) {
            // Header with today's events
            if !calendarService.eventsForToday().isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Today")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Spacer()
                        Text("\(calendarService.eventsForToday().count) events")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    ForEach(calendarService.eventsForToday().prefix(3), id: \.eventIdentifier) { event in
                        CalendarEventRow(event: event, isCompact: true)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                
                Divider()
                    .padding(.horizontal, 16)
            }
            
            // All events list
            if calendarService.isLoading {
                VStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading events...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredEvents.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "calendar")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text(appStore.searchQuery.isEmpty ? "No upcoming events" : "No events found")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    
                    if !appStore.searchQuery.isEmpty {
                        Button("Clear search") {
                            appStore.searchQuery = ""
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredEvents, id: \.eventIdentifier) { event in
                            CalendarEventRow(event: event)
                                .padding(.horizontal, 16)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .onAppear {
            if calendarService.isAuthorized {
                calendarService.loadUpcomingEvents()
            }
        }
    }
    
    private var filteredEvents: [EKEvent] {
        if appStore.searchQuery.isEmpty {
            return calendarService.events
        } else {
            return calendarService.searchEvents(query: appStore.searchQuery)
        }
    }
}

struct CalendarEventRow: View {
    let event: EKEvent
    let isCompact: Bool
    
    init(event: EKEvent, isCompact: Bool = false) {
        self.event = event
        self.isCompact = isCompact
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Calendar color indicator
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(NSColor(cgColor: event.calendar.cgColor) ?? .systemBlue))
                .frame(width: 4, height: isCompact ? 32 : 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title ?? "Untitled Event")
                    .font(isCompact ? .caption : .body)
                    .lineLimit(1)
                
                HStack {
                    Text(timeString)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let location = event.location, !location.isEmpty {
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(location)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer()
            
            if event.isAllDay {
                Text("All Day")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(4)
            }
        }
        .padding(.vertical, isCompact ? 6 : 8)
        .padding(.horizontal, 12)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onTapGesture {
            openInCalendar()
        }
    }
    
    private var timeString: String {
        if event.isAllDay {
            return DateFormatter.localizedString(from: event.startDate, dateStyle: .medium, timeStyle: .none)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, h:mm a"
            return formatter.string(from: event.startDate)
        }
    }
    
    private func openInCalendar() {
        if let identifier = event.eventIdentifier,
           let url = URL(string: "x-apple-calevent://\(identifier)") {
            NSWorkspace.shared.open(url)
        }
    }
}

