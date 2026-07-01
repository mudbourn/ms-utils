import Foundation
import CoreGraphics

// Usage:
//   hidinject daemon                          — persistent stdin mode
//   hidinject key <keycode> [cmd] [shift] [alt] [ctrl]
//   hidinject mouse <x> <y>
//   hidinject mouserel <dx> <dy>
//   hidinject click <x> <y> [left|right|middle]
//   hidinject mdown <x> <y> [left|right|middle]
//   hidinject mup <x> <y> [left|right|middle]
//   hidinject dragrel <dx> <dy> <anchorX> <anchorY> [left|right|middle]

let tap: CGEventTapLocation = .cghidEventTap

guard let src = CGEventSource(stateID: .hidSystemState) else {
    fputs("Failed to create event source\n", stderr)
    exit(1)
}

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

func mouseButtonFor(_ name: String) -> CGMouseButton {
    switch name.lowercased() {
    case "right", "r":  return .right
    case "middle", "m": return .center
    default:            return .left
    }
}

// ── Command executor ─────────────────────────────────────────────────
// Returns nil on success, error string on failure.
func executeCommand(_ args: [String]) -> String? {
    guard args.count >= 1 else { return "empty command" }
    let cmd = args[0].lowercased()

    switch cmd {

    case "key":
        guard args.count >= 2, let keycode = Int(args[1]) else {
            return "Usage: key <keycode> [cmd] [shift] [alt] [ctrl]"
        }
        let mods  = Array(args.dropFirst(2))
        let flags = flagsForMods(mods)
        let down = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(keycode), keyDown: true)!
        let up   = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(keycode), keyDown: false)!
        down.flags = flags
        up.flags   = flags
        down.post(tap: tap)
        Thread.sleep(forTimeInterval: 0.05)
        up.post(tap: tap)

    case "mouse":
        guard args.count >= 3,
              let x = Double(args[1]), let y = Double(args[2]) else {
            return "Usage: mouse <x> <y>"
        }
        let pos = CGPoint(x: x, y: y)
        let move = CGEvent(mouseEventSource: src, mouseType: .mouseMoved,
                           mouseCursorPosition: pos, mouseButton: .left)!
        move.post(tap: tap)

    case "mouserel":
        guard args.count >= 3,
              let dx = Double(args[1]), let dy = Double(args[2]) else {
            return "Usage: mouserel <dx> <dy>"
        }
        let cur = CGEvent(source: nil)?.location ?? CGPoint.zero
        let pos = CGPoint(x: cur.x + dx, y: cur.y + dy)
        let move = CGEvent(mouseEventSource: src, mouseType: .mouseMoved,
                           mouseCursorPosition: pos, mouseButton: .left)!
        move.post(tap: tap)

    case "click":
        guard args.count >= 3,
              let x = Double(args[1]), let y = Double(args[2]) else {
            return "Usage: click <x> <y> [left|right|middle]"
        }
        let btn = args.count >= 4 ? mouseButtonFor(args[3]) : .left
        let pos = CGPoint(x: x, y: y)
        let (downType, upType): (CGEventType, CGEventType) = {
            switch btn {
            case .right:  return (.rightMouseDown, .rightMouseUp)
            case .center: return (.otherMouseDown, .otherMouseUp)
            default:      return (.leftMouseDown, .leftMouseUp)
            }
        }()
        let move = CGEvent(mouseEventSource: src, mouseType: .mouseMoved,
                           mouseCursorPosition: pos, mouseButton: .left)!
        move.post(tap: tap)
        Thread.sleep(forTimeInterval: 0.01)
        let down = CGEvent(mouseEventSource: src, mouseType: downType,
                           mouseCursorPosition: pos, mouseButton: btn)!
        let up   = CGEvent(mouseEventSource: src, mouseType: upType,
                           mouseCursorPosition: pos, mouseButton: btn)!
        down.post(tap: tap)
        Thread.sleep(forTimeInterval: 0.02)
        up.post(tap: tap)

    case "mdown":
        guard args.count >= 3,
              let x = Double(args[1]), let y = Double(args[2]) else {
            return "Usage: mdown <x> <y> [left|right|middle]"
        }
        let btn = args.count >= 4 ? mouseButtonFor(args[3]) : .left
        let pos = CGPoint(x: x, y: y)
        let downType: CGEventType = {
            switch btn {
            case .right:  return .rightMouseDown
            case .center: return .otherMouseDown
            default:      return .leftMouseDown
            }
        }()
        let move = CGEvent(mouseEventSource: src, mouseType: .mouseMoved,
                           mouseCursorPosition: pos, mouseButton: .left)!
        move.post(tap: tap)
        Thread.sleep(forTimeInterval: 0.01)
        let down = CGEvent(mouseEventSource: src, mouseType: downType,
                           mouseCursorPosition: pos, mouseButton: btn)!
        down.post(tap: tap)

    case "mup":
        guard args.count >= 3,
              let x = Double(args[1]), let y = Double(args[2]) else {
            return "Usage: mup <x> <y> [left|right|middle]"
        }
        let btn = args.count >= 4 ? mouseButtonFor(args[3]) : .left
        let pos = CGPoint(x: x, y: y)
        let upType: CGEventType = {
            switch btn {
            case .right:  return .rightMouseUp
            case .center: return .otherMouseUp
            default:      return .leftMouseUp
            }
        }()
        let up = CGEvent(mouseEventSource: src, mouseType: upType,
                         mouseCursorPosition: pos, mouseButton: btn)!
        up.post(tap: tap)

    case "dragrel":
        // dragrel <dx> <dy> <anchorX> <anchorY> [left|right|middle]
        guard args.count >= 5,
              let dx = Double(args[1]), let dy = Double(args[2]),
              let anchorX = Double(args[3]), let anchorY = Double(args[4]) else {
            return "Usage: dragrel <dx> <dy> <anchorX> <anchorY> [left|right|middle]"
        }
        let dBtn = args.count >= 6 ? mouseButtonFor(args[5]) : .center
        let anchor = CGPoint(x: anchorX, y: anchorY)
        let dragType: CGEventType = {
            switch dBtn {
            case .right:  return .rightMouseDragged
            case .center: return .otherMouseDragged
            default:      return .leftMouseDragged
            }
        }()
        let drag = CGEvent(mouseEventSource: src, mouseType: dragType,
                           mouseCursorPosition: anchor, mouseButton: dBtn)!
        // kCGMouseEventDeltaX = 4, kCGMouseEventDeltaY = 5
        drag.setIntegerValueField(CGEventField(rawValue: 4)!, value: Int64(dx))
        drag.setIntegerValueField(CGEventField(rawValue: 5)!, value: Int64(dy))
        drag.post(tap: tap)

    case "dragreln":
        // dragreln <count> <delayUs> <dx> <dy> <anchorX> <anchorY> [left|right|middle]
        // Fires <count> dragrel events with <delayUs> microseconds between each.
        guard args.count >= 7,
              let count = Int(args[1]), let delayUs = Int(args[2]),
              let dx = Double(args[3]), let dy = Double(args[4]),
              let anchorX = Double(args[5]), let anchorY = Double(args[6]) else {
            return "Usage: dragreln <count> <delayUs> <dx> <dy> <anchorX> <anchorY> [button]"
        }
        let dnBtn = args.count >= 8 ? mouseButtonFor(args[7]) : .center
        let dnAnchor = CGPoint(x: anchorX, y: anchorY)
        let dnDragType: CGEventType = {
            switch dnBtn {
            case .right:  return .rightMouseDragged
            case .center: return .otherMouseDragged
            default:      return .leftMouseDragged
            }
        }()
        let dnFieldX = CGEventField(rawValue: 4)!
        let dnFieldY = CGEventField(rawValue: 5)!
        for _ in 0..<count {
            let dnDrag = CGEvent(mouseEventSource: src, mouseType: dnDragType,
                                 mouseCursorPosition: dnAnchor, mouseButton: dnBtn)!
            dnDrag.setIntegerValueField(dnFieldX, value: Int64(dx))
            dnDrag.setIntegerValueField(dnFieldY, value: Int64(dy))
            dnDrag.post(tap: tap)
            if delayUs > 0 {
                usleep(UInt32(delayUs))
            }
        }

    default:
        return "Unknown command: \(cmd)"
    }
    return nil
}

// ── Entry point ──────────────────────────────────────────────────────
let args = CommandLine.arguments
guard args.count >= 2 else {
    fputs("Usage: hidinject <daemon|key|mouse|mouserel|click|mdown|mup|dragrel> ...\n", stderr)
    exit(1)
}

let mode = args[1].lowercased()

if mode == "daemon" {
    // ── Daemon mode: read commands from stdin, one per line ──────────
    // Normal line: "command arg1 arg2 ..." → "ok\n" or "err: message\n"
    // "batch" → reads lines until "end", executes all, single "ok\n"
    // EOF → exit cleanly.
    fputs("ready\n", stdout)
    fflush(stdout)

    while let line = readLine() {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { continue }

        if trimmed == "batch" {
            // Collect lines until "end", execute all, respond once
            var batch: [[String]] = []
            while let bline = readLine() {
                let btrim = bline.trimmingCharacters(in: .whitespaces)
                if btrim == "end" { break }
                if btrim.isEmpty { continue }
                batch.append(btrim.split(separator: " ").map(String.init))
            }
            for parts in batch {
                _ = executeCommand(parts)
            }
            fputs("ok\n", stdout)
            fflush(stdout)
        } else {
            let parts = trimmed.split(separator: " ").map(String.init)
            if let err = executeCommand(parts) {
                fputs("err: \(err)\n", stdout)
            } else {
                fputs("ok\n", stdout)
            }
            fflush(stdout)
        }
    }
    exit(0)
} else {
    // ── One-shot mode ────────────────────────────────────────────────
    let cmdArgs = Array(args.dropFirst(1))
    if let err = executeCommand(cmdArgs) {
        fputs(err + "\n", stderr)
        exit(1)
    }
    exit(0)
}
