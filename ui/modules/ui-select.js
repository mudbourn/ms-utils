    (function() {
    "use strict";

    /* -- ui-select.js -- */
/**
 * createSelect, themed dropdown, the shell's replacement for <select>.
 *
 * A native <select> is only half-themeable: the closed control takes CSS, but
 * the *open* popup is drawn by macOS and no stylesheet reaches it, so it breaks
 * out of the shell's look mid-interaction. This is the control panel-macros.js
 * grew to avoid that, lifted out so the other surfaces can stop reinventing it.
 *
 * It presents the surface the native element did, `.value`, an "options"
 * setter, and a "change" event, so a replacement is a swap, not a rewrite.
 *
 * Usage:
 *
 *   const sel = createSelect({
 *     options: [{ value: "screen", label: "Screen" }, ...],  // or ["a", "b"]
 *     value:   "screen",
 *     minWidth: 120,
 *     onChange(v) { ... },        // or listen for "change"
 *   });
 *   host.appendChild(sel);
 *   sel.value = "window";         // set without firing "change"
 *   sel.setOptions([...]);        // rebuild; keeps .value if still present
 *
 * Sound is optional: playSlot() is called when present and skipped otherwise,
 * so popout windows that never load the sound bridge behave normally.
 */

// -- Styles --
// Travels with the module: the popout windows (ms_keys, ms_window) do not
// load the shell's stylesheet, and this control has to look the same in both.
// Selectors match the .macro-select names already in ms_shell.html so the two
// cannot drift apart visually, that file's copy is now the duplicate, kept
// only so existing markup keeps rendering while it is migrated.
const SELECT_CSS = `
.macro-select { position: relative; display: flex; align-items: center; gap: 6px; background: var(--surface2); border: 1px solid var(--border-dim); border-radius: var(--radius); color: var(--text); font-size: 11px; padding: 4px 8px; outline: none; font-family: inherit; cursor: pointer; min-width: 120px; }
.macro-select:hover { border-color: var(--border); }
.macro-select:focus, .macro-select.open { border-color: var(--accent); }
.macro-select-label { flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.macro-select-arrow { display: flex; align-items: center; font-size: 8px; color: var(--text3); flex-shrink: 0; }
.macro-select-arrow .icon { width: 12px; height: 12px; }
.macro-select-menu { display: none; position: absolute; top: calc(100% + 3px); left: 0; min-width: 100%; max-height: 260px; overflow-y: auto; background: var(--surface2); border: 1px solid var(--border); border-radius: var(--radius); z-index: 100; box-shadow: 0 4px 16px rgba(0,0,0,0.5); }
.macro-select.open .macro-select-menu { display: block; }
.macro-select-item { padding: 5px 10px; font-size: 11px; color: var(--text2); white-space: nowrap; cursor: pointer; transition: background 0.12s, color 0.12s; }
.macro-select-item:hover { background: var(--hover); color: var(--text); }
.macro-select-item.active { color: var(--accent); }
.macro-select-menu::-webkit-scrollbar { width: 4px; }
.macro-select-menu::-webkit-scrollbar-track { background: transparent; }
.macro-select-menu::-webkit-scrollbar-thumb { background: var(--border-dim); border-radius: 2px; }
`;

// Idempotent, safe to call from every panel that uses a select.
function injectSelectStyles(doc) {
    doc = doc || document;
    if (doc.getElementById("ui-select-css")) return;
    const style = doc.createElement("style");
    style.id = "ui-select-css";
    style.textContent = SELECT_CSS;
    (doc.head || doc.documentElement).appendChild(style);
}

// -- Factory --
function createSelect(opts) {
    opts = opts || {};
    injectSelectStyles(opts.doc);

    const doc = opts.doc || document;
    const root = doc.createElement("div");
    root.className = "macro-select" + (opts.className ? " " + opts.className : "");
    root.tabIndex = 0;
    if (opts.minWidth) root.style.minWidth = opts.minWidth + "px";

    const label = doc.createElement("span");
    label.className = "macro-select-label";
    root.appendChild(label);

    const arrow = doc.createElement("span");
    arrow.className = "macro-select-arrow";
    // The shell's chevdown SVG where it is reachable, the glyph where it is
    // not: ICONS lives in ms_shell.html, and the popout windows this module
    // also serves never load it. Same reason SELECT_CSS travels with the
    // module, the control has to render in both documents.
    if (window.ICONS && window.ICONS.chevdown && typeof window.icon === "function") {
        arrow.innerHTML = window.icon("chevdown");
    } else {
        arrow.textContent = "▾";
    }
    root.appendChild(arrow);

    const menu = doc.createElement("div");
    menu.className = "macro-select-menu";
    root.appendChild(menu);

    let _opts = [];
    let _value = "";

    function play(slot) { if (window.playSlot) window.playSlot(slot); }

    // Bare strings are accepted so a list of enum values needs no massaging;
    // value and label are the same string in that case.
    function normalise(list) {
        return (list || []).map((o) =>
            (o && typeof o === "object")
                ? { value: String(o.value), label: String(o.label == null ? o.value : o.label) }
                : { value: String(o), label: String(o) }
        );
    }

    function labelFor(v) {
        for (const o of _opts) if (o.value === v) return o.label;
        return _opts.length ? _opts[0].label : (opts.placeholder || "");
    }

    function close() {
        root.classList.remove("open");
        // Inline geometry is only meaningful while open; clearing it puts the
        // menu back to the stylesheet's absolute positioning so a closed
        // control carries no stale coordinates.
        menu.style.position = "";
        menu.style.left = "";
        menu.style.top = "";
        menu.style.bottom = "";
        menu.style.minWidth = "";
        menu.style.maxHeight = "";
    }

    // The menu is positioned in viewport coordinates while open, not inside
    // the control.
    //
    // Absolute positioning keeps it in the panel's scrolling body, and that
    // body clips, so a dropdown near the bottom of a panel had its list cut
    // off by the panel edge rather than overlapping it. Nothing in the panel
    // stack can be given `overflow: visible` to fix that: the scroll is the
    // point. `fixed` takes the menu out of the clip entirely.
    //
    // It flips above the control when there is more room up than down, which
    // is what a native popup does and the only reason the bottom-most rows
    // are usable at all.
    function place() {
        const r   = root.getBoundingClientRect();
        const vh  = doc.documentElement.clientHeight;
        const gap = 3;
        const below = vh - r.bottom - gap;
        const above = r.top - gap;
        const flip  = below < Math.min(260, menu.scrollHeight) && above > below;

        menu.style.position = "fixed";
        menu.style.left     = r.left + "px";
        menu.style.minWidth = r.width + "px";
        menu.style.maxHeight = Math.max(80, Math.min(260, flip ? above : below)) + "px";
        if (flip) {
            menu.style.top    = "auto";
            menu.style.bottom = (vh - r.top + gap) + "px";
        } else {
            menu.style.bottom = "auto";
            menu.style.top    = (r.bottom + gap) + "px";
        }
    }

    function render() {
        label.textContent = labelFor(_value);
        menu.innerHTML = "";
        _opts.forEach((o) => {
            const item = doc.createElement("div");
            item.className = "macro-select-item" + (o.value === _value ? " active" : "");
            item.textContent = o.label;
            item.addEventListener("mouseenter", () => play("hover"));
            item.addEventListener("click", (e) => {
                e.stopPropagation();
                play("interact");
                close();
                // Re-picking the current value is a no-op, not a change: a
                // "change" event here would re-run whatever the consumer does
                // on selection, which for the tool editor is a param write.
                if (o.value === _value) return;
                _value = o.value;
                render();
                if (opts.onChange) opts.onChange(_value);
                root.dispatchEvent(new Event("change"));
            });
            menu.appendChild(item);
        });
    }

    root.setOptions = function(list) {
        _opts = normalise(list);
        // Keep the selection if it survived the rebuild; otherwise fall to the
        // first option, matching what a native <select> does.
        if (!_opts.some((o) => o.value === _value)) {
            _value = _opts.length ? _opts[0].value : "";
        }
        render();
    };

    // Assignment sets without firing "change", same as the native element,
    // and consumers rely on it to sync the control to external state.
    Object.defineProperty(root, "value", {
        get: () => _value,
        set: (v) => { _value = v == null ? "" : String(v); render(); },
    });

    Object.defineProperty(root, "options", { get: () => _opts.slice() });

    root.addEventListener("mouseenter", () => play("hover"));
    root.addEventListener("click", (e) => {
        e.stopPropagation();
        if (root.classList.contains("open")) { close(); return; }
        play("interact");
        root.classList.add("open");
        // After the class, so the menu has been laid out and scrollHeight is
        // real, measuring a display:none element gives zero and every menu
        // would open downward.
        place();
    });
    // A viewport-positioned menu does not travel with the panel it came from,
    // so anything that moves the control closes it rather than leaving the
    // list floating over the wrong row. Capture phase: the scroll happens on
    // the panel body, which does not bubble.
    doc.addEventListener("scroll", close, true);
    window.addEventListener("resize", close);
    root.addEventListener("keydown", (e) => {
        if (e.key === "Escape") close();
        // The shell binds single keys globally; an open dropdown must not feed
        // them through as shortcuts.
        e.stopPropagation();
    });
    doc.addEventListener("click", close);

    root.setOptions(opts.options || []);
    if (opts.value !== undefined && opts.value !== null) root.value = opts.value;
    else if (!_opts.length && opts.placeholder) label.textContent = opts.placeholder;

    return root;
}

    window.createSelect       = createSelect;
    window.injectSelectStyles = injectSelectStyles;
    window.SELECT_CSS         = SELECT_CSS;

    })();
