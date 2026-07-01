import Foundation
import CoreGraphics

// Usage:
//   hidinject key <keycode> [cmd] [shift] [alt] [ctrl]
//   hidinject mouse <x> <y>
//   hidinject mouserel <dx> <dy>
//   hidinject click <x> <y> [left|right|middle]
//   hidinject mdown <x> <y> [left|right|middle]
//   hidinject mup <x> <y> [left|right|middle]
//   hidinject dragrel <dx> <dy> [left|right|middle]

let tap: CGEventTapLocation = .cghidEventTap

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

func fail(_ msg: String) -> Never {
    fputs(msg + "\n", stderr)
    exit(1)
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    fail("Usage: hidinject <key|mouse|mouserel|click|mdown|mup|dragrel> ...")
}

guard let src = CGEventSource(stateID: .hidSystemState) else {
    fail("Failed to create event source")
}

let cmd = args[1].lowercased()

switch cmd {

// ── Keyboard ──────────────────────────────────────────────────────────────
case "key":
    guard args.count >= 3, let keycode = Int(args[2]) else {
        fail("Usage: hidinject key <keycode> [cmd] [shift] [alt] [ctrl]")
    }
    let mods  = Array(args.dropFirst(3))
    let flags = flagsForMods(mods)
    Thread.sleep(forTimeInterval: 0.02)

    let down = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(keycode), keyDown: true)!
    let up   = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(keycode), keyDown: false)!
    down.flags = flags
    up.flags   = flags
    down.post(tap: tap)
    Thread.sleep(forTimeInterval: 0.05)
    up.post(tap: tap)

// ── Mouse move (absolute) ─────────────────────────────────────────────────
case "mouse":
    guard args.count >= 4,
          let x = Double(args[2]), let y = Double(args[3]) else {
        fail("Usage: hidinject mouse <x> <y>")
    }
    let pos = CGPoint(x: x, y: y)
    let move = CGEvent(mouseEventSource: src, mouseType: .mouseMoved,
                       mouseCursorPosition: pos, mouseButton: .left)!
    move.post(tap: tap)

// ── Mouse move (relative) ─────────────────────────────────────────────────
case "mouserel":
    guard args.count >= 4,
          let dx = Double(args[2]), let dy = Double(args[3]) else {
        fail("Usage: hidinject mouserel <dx> <dy>")
    }
    let cur = CGEvent(source: nil)?.location ?? CGPoint.zero
    let pos = CGPoint(x: cur.x + dx, y: cur.y + dy)
    let move = CGEvent(mouseEventSource: src, mouseType: .mouseMoved,
                       mouseCursorPosition: pos, mouseButton: .left)!
    move.post(tap: tap)

// ── Mouse click (down + up) ───────────────────────────────────────────────
case "click":
    guard args.count >= 4,
          let x = Double(args[2]), let y = Double(args[3]) else {
        fail("Usage: hidinject click <x> <y> [left|right|middle]")
    }
    let btn = args.count >= 5 ? mouseButtonFor(args[4]) : .left
    let pos = CGPoint(x: x, y: y)
    let (downType, upType): (CGEventType, CGEventType) = {
        switch btn {
        case .right:  return (.rightMouseDown, .rightMouseUp)
        case .center: return (.otherMouseDown, .otherMouseUp)
        default:      return (.leftMouseDown, .leftMouseUp)
        }
    }()

    // Move to position first
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

// ── Mouse button down ─────────────────────────────────────────────────────
case "mdown":
    guard args.count >= 4,
          let x = Double(args[2]), let y = Double(args[3]) else {
        fail("Usage: hidinject mdown <x> <y> [left|right|middle]")
    }
    let btn = args.count >= 5 ? mouseButtonFor(args[4]) : .left
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

// ── Mouse button up ───────────────────────────────────────────────────────
case "mup":
    guard args.count >= 4,
          let x = Double(args[2]), let y = Double(args[3]) else {
        fail("Usage: hidinject mup <x> <y> [left|right|middle]")
    }
    let btn = args.count >= 5 ? mouseButtonFor(args[4]) : .left
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

// ── Relative drag (camera move) ─────────────────────────────────────
case "dragrel":
    guard args.count >= 4,
          let dx = Double(args[2]), let dy = Double(args[3]) else {
        fail("Usage: hidinject dragrel <dx> <dy> [left|right|middle]")
    }
    let dBtn = args.count >= 5 ? mouseButtonFor(args[4]) : .right
    let cur = CGEvent(source: nil)?.location ?? CGPoint.zero
    let newPos = CGPoint(x: cur.x + dx, y: cur.y + dy)
    let dragType: CGEventType = {
        switch dBtn {
        case .right:  return .rightMouseDragged
        case .center: return .otherMouseDragged
        default:      return .leftMouseDragged
        }
    }()
    let drag = CGEvent(mouseEventSource: src, mouseType: dragType,
                       mouseCursorPosition: newPos, mouseButton: dBtn)!
    drag.post(tap: tap)

default:
    fail("Unknown command: \(cmd)\nAvailable: key, mouse, mouserel, click, mdown, mup, dragrel")
}

exit(0)
