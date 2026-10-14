import AppKit
import Carbon

@MainActor
final class HotKey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var action: (() -> Void)?
    private var identifier: UInt32 = 1
    func register(keyCode: UInt32 = UInt32(kVK_ANSI_X), modifiers: UInt32 = UInt32(cmdKey | shiftKey), identifier: UInt32 = 1) -> Bool {
        self.identifier = identifier
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<HotKey>.fromOpaque(context).takeUnretainedValue()
            var pressed = EventHotKeyID()
            guard let event, GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed) == noErr else { return OSStatus(eventNotHandledErr) }
            let matches = MainActor.assumeIsolated { pressed.signature == 0x53485455 && pressed.id == owner.identifier }
            guard matches else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated { owner.action?() }
            return noErr
        }, 1, &type, context, &handler)
        guard installed == noErr else { return false }
        let id = EventHotKeyID(signature: 0x53485455, id: identifier)
        return RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKey) == noErr
    }
    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
