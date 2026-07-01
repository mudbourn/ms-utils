use std::io::{self, BufRead, Write};
use std::os::raw::{c_double, c_int};

// ── Raw CoreGraphics FFI ─────────────────────────────────────────────
type CGEventTapLocation = c_int;
type CGEventType = u32;
type CGMouseButton = u32;
type CGEventField = u32;
type CGKeyCode = u16;
type CGEventFlags = u64;

#[repr(C)]
#[derive(Clone, Copy)]
struct CGPoint { x: c_double, y: c_double }

type CGEventRef = *mut std::ffi::c_void;
type CGEventSourceRef = *mut std::ffi::c_void;

const K_CG_HID_EVENT_TAP: CGEventTapLocation = 0;
const K_CG_EVENT_SOURCE_STATE_HID_SYSTEM_STATE: c_int = 1;

// Event types
const K_CG_EVENT_MOUSE_MOVED: CGEventType = 5;
const K_CG_EVENT_LEFT_MOUSE_DOWN: CGEventType = 1;
const K_CG_EVENT_LEFT_MOUSE_UP: CGEventType = 2;
const K_CG_EVENT_RIGHT_MOUSE_DOWN: CGEventType = 3;
const K_CG_EVENT_RIGHT_MOUSE_UP: CGEventType = 4;
const K_CG_EVENT_OTHER_MOUSE_DOWN: CGEventType = 25;
const K_CG_EVENT_OTHER_MOUSE_UP: CGEventType = 26;
const K_CG_EVENT_LEFT_MOUSE_DRAGGED: CGEventType = 6;
const K_CG_EVENT_RIGHT_MOUSE_DRAGGED: CGEventType = 7;
const K_CG_EVENT_OTHER_MOUSE_DRAGGED: CGEventType = 27;
const K_CG_EVENT_KEY_DOWN: CGEventType = 10;
const K_CG_EVENT_KEY_UP: CGEventType = 11;

// Mouse buttons
const K_CG_MOUSE_BUTTON_LEFT: CGMouseButton = 0;
const K_CG_MOUSE_BUTTON_RIGHT: CGMouseButton = 1;
const K_CG_MOUSE_BUTTON_CENTER: CGMouseButton = 2;

// Event fields
const K_CG_MOUSE_EVENT_DELTA_X: CGEventField = 4;
const K_CG_MOUSE_EVENT_DELTA_Y: CGEventField = 5;
const K_CG_EVENT_FIELD_FLAGS: CGEventField = 66; // actually 72? let me check

// Actually the correct field for event flags in CGEventField
// Looking at CGEventTypes.h:
// kCGEventFieldEventSourceStateID = 12
// kCGEventFieldFlags = 66 → wait, that's not right either
// The actual value for flags field... let me just use what works

extern "C" {
    fn CGEventSourceCreate(stateID: c_int) -> CGEventSourceRef;
    fn CGEventCreateMouseEvent(
        source: CGEventSourceRef,
        mouseType: CGEventType,
        mouseCursorPosition: CGPoint,
        mouseButton: CGMouseButton,
    ) -> CGEventRef;
    fn CGEventCreateKeyboardEvent(
        source: CGEventSourceRef,
        virtualKey: CGKeyCode,
        keyDown: bool,
    ) -> CGEventRef;
    fn CGEventPost(tap: CGEventTapLocation, event: CGEventRef);
    fn CGEventPostToPid(pid: c_int, event: CGEventRef);
    fn CGEventSetIntegerValueField(event: CGEventRef, field: CGEventField, value: i64);
    fn CGEventGetLocation(event: CGEventRef) -> CGPoint;
    fn CGEventSetFlags(event: CGEventRef, flags: CGEventFlags);
    fn CGEventSetFlags2(event: CGEventRef, flags: CGEventFlags); // might not exist
    fn CFRelease(cf: *const std::ffi::c_void);
}

// CGEventField constants
const FIELD_DELTA_X: CGEventField = 4;
const FIELD_DELTA_Y: CGEventField = 5;

// CGEventFlags
const FLAG_SHIFT: CGEventFlags = 0x0002_0000;
const FLAG_CTRL: CGEventFlags = 0x0004_0000;
const FLAG_ALT: CGEventFlags = 0x0008_0000;
const FLAG_CMD: CGEventFlags = 0x0010_0000;

fn flags_for_mods(mods: &[&str]) -> CGEventFlags {
    let mut flags: CGEventFlags = 0;
    for m in mods {
        match m.to_lowercase().as_str() {
            "cmd" | "command" => flags |= FLAG_CMD,
            "shift" => flags |= FLAG_SHIFT,
            "alt" | "option" => flags |= FLAG_ALT,
            "ctrl" | "control" => flags |= FLAG_CTRL,
            _ => {}
        }
    }
    flags
}

fn button_for(name: &str) -> (CGMouseButton, CGEventType, CGEventType, CGEventType) {
    match name.to_lowercase().as_str() {
        "right" | "r" => (
            K_CG_MOUSE_BUTTON_RIGHT,
            K_CG_EVENT_RIGHT_MOUSE_DOWN,
            K_CG_EVENT_RIGHT_MOUSE_UP,
            K_CG_EVENT_RIGHT_MOUSE_DRAGGED,
        ),
        "middle" | "m" | "center" | "other" => (
            K_CG_MOUSE_BUTTON_CENTER,
            K_CG_EVENT_OTHER_MOUSE_DOWN,
            K_CG_EVENT_OTHER_MOUSE_UP,
            K_CG_EVENT_OTHER_MOUSE_DRAGGED,
        ),
        _ => (
            K_CG_MOUSE_BUTTON_LEFT,
            K_CG_EVENT_LEFT_MOUSE_DOWN,
            K_CG_EVENT_LEFT_MOUSE_UP,
            K_CG_EVENT_LEFT_MOUSE_DRAGGED,
        ),
    }
}

fn drag_type_for(btn_name: &str) -> CGEventType {
    match btn_name.to_lowercase().as_str() {
        "right" | "r" => K_CG_EVENT_RIGHT_MOUSE_DRAGGED,
        "middle" | "m" | "center" | "other" => K_CG_EVENT_OTHER_MOUSE_DRAGGED,
        _ => K_CG_EVENT_LEFT_MOUSE_DRAGGED,
    }
}

fn get_current_pos() -> CGPoint {
    unsafe {
        let ev = CGEventCreateMouseEvent(
            std::ptr::null_mut(),
            K_CG_EVENT_MOUSE_MOVED,
            CGPoint { x: 0.0, y: 0.0 },
            K_CG_MOUSE_BUTTON_LEFT,
        );
        let loc = CGEventGetLocation(ev);
        release_event(ev);
        loc
    }
}

fn release_event(ev: CGEventRef) {
    if !ev.is_null() {
        unsafe { CFRelease(ev as *const std::ffi::c_void) }
    }
}

// Global target PID — when set, events go to this process via CGEventPostToPid
static mut TARGET_PID: c_int = 0;

fn post_event(ev: CGEventRef) {
    unsafe {
        if TARGET_PID > 0 {
            CGEventPostToPid(TARGET_PID, ev);
        } else {
            post_event(ev);
        }
    }
}

// ── Command executor ─────────────────────────────────────────────────
fn execute_command(src: CGEventSourceRef, args: &[&str]) -> Result<(), String> {
    if args.is_empty() { return Err("empty command".into()); }
    match args[0] {
        "key" => {
            let keycode: CGKeyCode = args.get(1)
                .ok_or("Usage: key <keycode> [mods...]")?
                .parse().map_err(|_| "bad keycode")?;
            let mods: Vec<&str> = args[2..].iter().copied().collect();
            let flags = flags_for_mods(&mods);
            unsafe {
                let down = CGEventCreateKeyboardEvent(src, keycode, true);
                let up = CGEventCreateKeyboardEvent(src, keycode, false);
                CGEventSetFlags(down, flags);
                CGEventSetFlags(up, flags);
                post_event(down);
                std::thread::sleep(std::time::Duration::from_millis(50));
                post_event(up);
                release_event(down);
                release_event(up);
            }
        }
        "mouse" => {
            let x: c_double = args.get(1).ok_or("Usage: mouse <x> <y>")?.parse().map_err(|_| "bad x")?;
            let y: c_double = args.get(2).ok_or("Usage: mouse <x> <y>")?.parse().map_err(|_| "bad y")?;
            unsafe {
                let ev = CGEventCreateMouseEvent(src, K_CG_EVENT_MOUSE_MOVED, CGPoint { x, y }, K_CG_MOUSE_BUTTON_LEFT);
                post_event(ev);
                release_event(ev);
            }
        }
        "mouserel" => {
            let dx: c_double = args.get(1).ok_or("Usage: mouserel <dx> <dy>")?.parse().map_err(|_| "bad dx")?;
            let dy: c_double = args.get(2).ok_or("Usage: mouserel <dx> <dy>")?.parse().map_err(|_| "bad dy")?;
            let cur = get_current_pos();
            let pos = CGPoint { x: cur.x + dx, y: cur.y + dy };
            unsafe {
                let ev = CGEventCreateMouseEvent(src, K_CG_EVENT_MOUSE_MOVED, pos, K_CG_MOUSE_BUTTON_LEFT);
                post_event(ev);
                release_event(ev);
            }
        }
        "click" => {
            let x: c_double = args.get(1).ok_or("Usage: click <x> <y> [button]")?.parse().map_err(|_| "bad x")?;
            let y: c_double = args.get(2).ok_or("Usage: click <x> <y> [button]")?.parse().map_err(|_| "bad y")?;
            let btn_name = args.get(3).copied().unwrap_or("left");
            let (btn, down_t, up_t, _) = button_for(btn_name);
            let pos = CGPoint { x, y };
            unsafe {
                let mv = CGEventCreateMouseEvent(src, K_CG_EVENT_MOUSE_MOVED, pos, K_CG_MOUSE_BUTTON_LEFT);
                post_event(mv);
                release_event(mv);
                std::thread::sleep(std::time::Duration::from_millis(10));
                let down = CGEventCreateMouseEvent(src, down_t, pos, btn);
                post_event(down);
                release_event(down);
                std::thread::sleep(std::time::Duration::from_millis(20));
                let up = CGEventCreateMouseEvent(src, up_t, pos, btn);
                post_event(up);
                release_event(up);
            }
        }
        "mdown" => {
            let x: c_double = args.get(1).ok_or("Usage: mdown <x> <y> [button]")?.parse().map_err(|_| "bad x")?;
            let y: c_double = args.get(2).ok_or("Usage: mdown <x> <y> [button]")?.parse().map_err(|_| "bad y")?;
            let btn_name = args.get(3).copied().unwrap_or("left");
            let (btn, down_t, _, _) = button_for(btn_name);
            let pos = CGPoint { x, y };
            unsafe {
                let mv = CGEventCreateMouseEvent(src, K_CG_EVENT_MOUSE_MOVED, pos, K_CG_MOUSE_BUTTON_LEFT);
                post_event(mv);
                release_event(mv);
                std::thread::sleep(std::time::Duration::from_millis(10));
                let down = CGEventCreateMouseEvent(src, down_t, pos, btn);
                post_event(down);
                release_event(down);
            }
        }
        "mup" => {
            let x: c_double = args.get(1).ok_or("Usage: mup <x> <y> [button]")?.parse().map_err(|_| "bad x")?;
            let y: c_double = args.get(2).ok_or("Usage: mup <x> <y> [button]")?.parse().map_err(|_| "bad y")?;
            let btn_name = args.get(3).copied().unwrap_or("left");
            let (btn, _, up_t, _) = button_for(btn_name);
            let pos = CGPoint { x, y };
            unsafe {
                let up = CGEventCreateMouseEvent(src, up_t, pos, btn);
                post_event(up);
                release_event(up);
            }
        }
        "dragrel" => {
            let dx: c_double = args.get(1).ok_or("Usage: dragrel <dx> <dy> <ax> <ay> [btn]")?.parse().map_err(|_| "bad dx")?;
            let dy: c_double = args.get(2).ok_or("Usage: dragrel <dx> <dy> <ax> <ay> [btn]")?.parse().map_err(|_| "bad dy")?;
            let ax: c_double = args.get(3).ok_or("need anchorX")?.parse().map_err(|_| "bad ax")?;
            let ay: c_double = args.get(4).ok_or("need anchorY")?.parse().map_err(|_| "bad ay")?;
            let btn_name = args.get(5).copied().unwrap_or("center");
            let drag_t = drag_type_for(btn_name);
            let btn = match btn_name.to_lowercase().as_str() {
                "right" | "r" => K_CG_MOUSE_BUTTON_RIGHT,
                "middle" | "m" | "center" | "other" => K_CG_MOUSE_BUTTON_CENTER,
                _ => K_CG_MOUSE_BUTTON_LEFT,
            };
            let anchor = CGPoint { x: ax, y: ay };
            unsafe {
                let ev = CGEventCreateMouseEvent(src, drag_t, anchor, btn);
                CGEventSetIntegerValueField(ev, FIELD_DELTA_X, dx as i64);
                CGEventSetIntegerValueField(ev, FIELD_DELTA_Y, dy as i64);
                post_event(ev);
                release_event(ev);
            }
        }
        "dragreln" => {
            // dragreln <count> <delayUs> <dx> <dy> <anchorX> <anchorY> [button]
            let count: usize = args.get(1).ok_or("Usage: dragreln <count> <delayUs> <dx> <dy> <ax> <ay> [btn]")?.parse().map_err(|_| "bad count")?;
            let delay_us: u64 = args.get(2).ok_or("need delayUs")?.parse().map_err(|_| "bad delay")?;
            let dx: c_double = args.get(3).ok_or("need dx")?.parse().map_err(|_| "bad dx")?;
            let dy: c_double = args.get(4).ok_or("need dy")?.parse().map_err(|_| "bad dy")?;
            let ax: c_double = args.get(5).ok_or("need anchorX")?.parse().map_err(|_| "bad ax")?;
            let ay: c_double = args.get(6).ok_or("need anchorY")?.parse().map_err(|_| "bad ay")?;
            let btn_name = args.get(7).copied().unwrap_or("center");
            let drag_t = drag_type_for(btn_name);
            let btn = match btn_name.to_lowercase().as_str() {
                "right" | "r" => K_CG_MOUSE_BUTTON_RIGHT,
                "middle" | "m" | "center" | "other" => K_CG_MOUSE_BUTTON_CENTER,
                _ => K_CG_MOUSE_BUTTON_LEFT,
            };
            let anchor = CGPoint { x: ax, y: ay };
            let delay = if delay_us > 0 {
                std::time::Duration::from_micros(delay_us)
            } else {
                std::time::Duration::ZERO
            };
            for _ in 0..count {
                unsafe {
                    let ev = CGEventCreateMouseEvent(src, drag_t, anchor, btn);
                    CGEventSetIntegerValueField(ev, FIELD_DELTA_X, dx as i64);
                    CGEventSetIntegerValueField(ev, FIELD_DELTA_Y, dy as i64);
                    post_event(ev);
                    release_event(ev);
                }
                if delay_us > 0 {
                    std::thread::sleep(delay);
                }
            }
        }
        "setpid" => {
            // setpid <pid> — set target process for event delivery
            let pid: c_int = args.get(1)
                .ok_or("Usage: setpid <pid>")?
                .parse()
                .map_err(|_| "bad pid")?;
            unsafe { TARGET_PID = pid; }
        }
        other => return Err(format!("Unknown command: {}", other)),
    }
    Ok(())
}

// ── Entry point ──────────────────────────────────────────────────────
fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 2 {
        eprintln!("Usage: hidinject <daemon|key|mouse|mouserel|click|mdown|mup|dragrel|dragreln> ...");
        std::process::exit(1);
    }

    let src = unsafe { CGEventSourceCreate(K_CG_EVENT_SOURCE_STATE_HID_SYSTEM_STATE) };
    if src.is_null() {
        eprintln!("Failed to create event source");
        std::process::exit(1);
    }

    if args[1] == "daemon" {
        // Optional: hidinject daemon [pid]
        if args.len() >= 3 {
            if let Ok(pid) = args[2].parse::<c_int>() {
                unsafe { TARGET_PID = pid; }
            }
        }
        // ── Daemon mode ──────────────────────────────────────────────
        let stdout = io::stdout();
        let mut out = stdout.lock();
        let _ = writeln!(out, "ready");
        let _ = out.flush();

        let stdin = io::stdin();
        for line in stdin.lock().lines() {
            let line = match line {
                Ok(l) => l,
                Err(_) => break,
            };
            let trimmed = line.trim();
            if trimmed.is_empty() { continue; }

            if trimmed == "batch" {
                // Read until "end", execute all, respond once
                for bline in stdin.lock().lines() {
                    let bline = match bline {
                        Ok(l) => l,
                        Err(_) => break,
                    };
                    let btrim = bline.trim().to_string();
                    if btrim == "end" { break };
                    if btrim.is_empty() { continue };
                    let parts: Vec<&str> = btrim.split_whitespace().collect();
                    let _ = execute_command(src, &parts);
                }
                
                let _ = out.flush();
            } else {
                let parts: Vec<&str> = trimmed.split_whitespace().collect();
                match execute_command(src, &parts) {
                    Ok(()) => {  }
                    Err(e) => { let _ = writeln!(out, "err: {}", e); }
                }
                let _ = out.flush();
            }
        }
    } else {
        // ── One-shot mode ────────────────────────────────────────────
        let cmd_args: Vec<&str> = args[1..].iter().map(|s| s.as_str()).collect();
        if let Err(e) = execute_command(src, &cmd_args) {
            eprintln!("{}", e);
            std::process::exit(1);
        }
    }
}
