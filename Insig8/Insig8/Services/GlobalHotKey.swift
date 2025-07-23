import AppKit
import Carbon

class GlobalHotKey {
    private var eventHotKeyRef: EventHotKeyRef?
    private let keyCombo: KeyCombo
    private let handler: () -> Void
    
    private static var hotKeyID: UInt32 = 0
    private static var eventHandler: EventHandlerRef?
    private static var registeredHotKeys: [UInt32: GlobalHotKey] = [:]
    
    init(keyCombo: KeyCombo, handler: @escaping () -> Void) {
        self.keyCombo = keyCombo
        self.handler = handler
        registerHotKey()
    }
    
    deinit {
        unregisterHotKey()
    }
    
    private func registerHotKey() {
        // Set up event handler if not already done
        if GlobalHotKey.eventHandler == nil {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            
            let handler: EventHandlerUPP = { _, event, _ in
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                
                if status == noErr {
                    if let hotKey = GlobalHotKey.registeredHotKeys[hotKeyID.id] {
                        DispatchQueue.main.async {
                            hotKey.handler()
                        }
                    }
                }
                
                return noErr
            }
            
            InstallEventHandler(GetEventDispatcherTarget(), handler, 1, &eventType, nil, &GlobalHotKey.eventHandler)
        }
        
        // Convert key code and modifiers
        let carbonKeyCode = keyCodeToCarbonKeyCode(keyCombo.key)
        let carbonModifiers = modifiersToCarbonModifiers(keyCombo.modifiers)
        
        // Register hot key
        let hotKeyID = EventHotKeyID(signature: OSType(0x4855424B /* HUBK */), id: GlobalHotKey.hotKeyID)
        GlobalHotKey.hotKeyID += 1
        
        let status = RegisterEventHotKey(
            carbonKeyCode,
            carbonModifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &eventHotKeyRef
        )
        
        if status == noErr {
            GlobalHotKey.registeredHotKeys[hotKeyID.id] = self
        }
    }
    
    private func unregisterHotKey() {
        if let ref = eventHotKeyRef {
            UnregisterEventHotKey(ref)
            eventHotKeyRef = nil
        }
    }
    
    private func keyCodeToCarbonKeyCode(_ key: KeyCombo.KeyCode) -> UInt32 {
        switch key {
        case .space: return 49
        case .enter: return 36
        case .period: return 47
        // Add more key codes as needed
        }
    }
    
    private func modifiersToCarbonModifiers(_ modifiers: KeyCombo.KeyModifiers) -> UInt32 {
        var carbonModifiers: UInt32 = 0
        
        if modifiers.contains(.command) {
            carbonModifiers |= UInt32(cmdKey)
        }
        if modifiers.contains(.option) {
            carbonModifiers |= UInt32(optionKey)
        }
        if modifiers.contains(.control) {
            carbonModifiers |= UInt32(controlKey)
        }
        if modifiers.contains(.shift) {
            carbonModifiers |= UInt32(shiftKey)
        }
        
        return carbonModifiers
    }
}