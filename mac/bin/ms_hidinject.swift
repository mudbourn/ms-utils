import Foundation
import CoreGraphics

// Usage: hidinject <keycode> [mod1 mod2 ...]
// Mods: cmd, shift, alt, ctrl
// Example: hidinject 97 cmd
// Example: hidinject 0 cmd shift

func flagsForMods(_ mods: [String]) -> CGEventFlags {
    var flags: CGEventFlags = []
    for mod in mods {
        switch mod.lowercased() {
        case "cmd", "command":   flags.insert(.maskCommand)
        case "shift":            flags.insert(.maskShift)
        case "alt", "option":    flags.insert(.maskAlternate)
        case "ctrl", "control":  flags.insert(.maskControl)
        default: break
        }
    }
    return flags
}

let args = CommandLine.arguments
guard args.count >= 2, let keycode = Int(args[1]) else {
    fputs("Usage: hidinject <keycode> [cmd] [shift] [alt] [ctrl]\n", stderr)
    exit(1)
}

let mods = Array(args.dropFirst(2))
let flags = flagsForMods(mods)
let cgKeycode = CGKeyCode(keycode)

guard let src = CGEventSource(stateID: .hidSystemState) else {
    fputs("Failed to create event source\n", stderr)
    exit(1)
}

// Small delay so modifier state is clean
Thread.sleep(forTimeInterval: 0.02)

let keyDown = CGEvent(keyboardEventSource: src, virtualKey: cgKeycode, keyDown: true)!
let keyUp   = CGEvent(keyboardEventSource: src, virtualKey: cgKeycode, keyDown: false)!

keyDown.flags = flags
keyUp.flags   = flags

keyDown.post(tap: .cghidEventTap)
Thread.sleep(forTimeInterval: 0.05)
keyUp.post(tap: .cghidEventTap)

exit(0)
