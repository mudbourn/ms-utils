/**
 * LogPanel — shared factory for ms-utils dev-tool log panels.
 *
 * Encapsulates the near-identical boilerplate copied across Console, Watcher,
 * Keys, and Window panels: pause toggle, entry selection, copy, context menu,
 * keyboard shortcuts, header drag, scroll management, and theme injection.
 *
 * Each panel supplies its own buildRow(), channel name, and optional overrides.
 *
 * Usage (in an HTML <script type="module">):
 *
 *   import { createLogPanel } from "./modules/log-panel.js";
 *
 *   const lp = createLogPanel({
 *     channel: "msConsole",
 *     buildRow(entry) { ... return HTMLElement; },
 *     // optional overrides:
 *     entrySelector: "#log .entry, #log .step",
 *     extractCopyText(el) { return "..."; },
 *     clearAction: "clearLog",
 *   });
 *
 *   // Expose for inline handlers
 *   window.togglePause = lp.togglePause;
 *   window.appendEntry = lp.appendEntry;
 *   window.loadHistory = lp.loadHistory;
 *   window.closePanel  = lp.closePanel;
 *   window.clearLog    = lp.clearLog;
 *   window.playSlot    = lp.playSlot;
 */

// ── Theme ────────────────────────────────────────────────────────────────
function hexToRgb(hex) {
    hex = hex.replace(/^#/, "");
    if (hex.length === 3) hex = hex[0]+hex[0]+hex[1]+hex[1]+hex[2]+hex[2];
    const n = parseInt(hex, 16);
    return { r: (n >> 16) & 255, g: (n >> 8) & 255, b: n & 255 };
}

function applyTheme(t) {
    if (!t) return;
    const r = document.documentElement.style;
    if (t.bg) r.setProperty("--bg", t.bg);
    if (t.surface) r.setProperty("--surface", t.surface);
    if (t.surface2) r.setProperty("--surface2", t.surface2);
    if (t.hover) r.setProperty("--hover", t.hover);
    if (t.accent) r.setProperty("--accent", t.accent);
    if (t.accentHi) r.setProperty("--accent-hi", t.accentHi);
    if (t.success) r.setProperty("--success", t.success);
    if (t.dangerBg) r.setProperty("--danger-bg", t.dangerBg);
    if (t.danger) r.setProperty("--danger", t.danger);
    if (t.warning) r.setProperty("--warning", t.warning);
    if (t.text) r.setProperty("--text", t.text);
    if (t.text && !t.text2) {
        const c = hexToRgb(t.text);
        if (c) r.setProperty("--text2", `rgba(${c.r},${c.g},${c.b},0.85)`);
    }
    if (t.text && !t.text3) {
        const c = hexToRgb(t.text);
        if (c) r.setProperty("--text3", `rgba(${c.r},${c.g},${c.b},0.55)`);
    }
    if (t.accent && t.hover && !t.border) {
        const a = hexToRgb(t.accent);
        const h = hexToRgb(t.hover);
        if (a && h) {
            const mr = Math.round(a.r * 0.5 + h.r * 0.5);
            const mg = Math.round(a.g * 0.5 + h.g * 0.5);
            const mb = Math.round(a.b * 0.5 + h.b * 0.5);
            r.setProperty("--border", `rgba(${mr},${mg},${mb},0.55)`);
            r.setProperty("--border-dim", `rgba(${mr},${mg},${mb},0.18)`);
        }
    }
    if (t.accent && !t.accentGlow) {
        const a = hexToRgb(t.accent);
        if (a) r.setProperty("--accent-glow", `rgba(${a.r},${a.g},${a.b},0.4)`);
    }
    if (t.accent && !t.accentGlowFaint) {
        const a = hexToRgb(t.accent);
        if (a) r.setProperty("--accent-glow-faint", `rgba(${a.r},${a.g},${a.b},0.12)`);
    }
    if (t.danger && !t.dangerGlow) {
        const d = hexToRgb(t.danger);
        if (d) r.setProperty("--danger-glow", `rgba(${d.r},${d.g},${d.b},0.6)`);
    }
    if (t.danger && !t.dangerBorder) {
        const d = hexToRgb(t.danger);
        if (d) r.setProperty("--danger-border", `rgba(${d.r},${d.g},${d.b},0.3)`);
    }
    if (t.text2) r.setProperty("--text2", t.text2);
    if (t.text3) r.setProperty("--text3", t.text3);
    if (t.border) r.setProperty("--border", t.border);
    if (t.borderDim) r.setProperty("--border-dim", t.borderDim);
    if (t.accentGlow) r.setProperty("--accent-glow", t.accentGlow);
    if (t.accentGlowFaint) r.setProperty("--accent-glow-faint", t.accentGlowFaint);
    if (t.dangerGlow) r.setProperty("--danger-glow", t.dangerGlow);
    if (t.dangerBorder) r.setProperty("--danger-border", t.dangerBorder);
    if (t.key) r.setProperty("--key", t.key);
    if (t.mouse) r.setProperty("--mouse", t.mouse);
    if (t.scroll) r.setProperty("--scroll", t.scroll);
    if (t.radius !== undefined) {
        r.setProperty("--radius", t.radius + "px");
        r.setProperty("--radius-s", Math.max(0, t.radius - 1) + "px");
    }
    if (t.font) {
        if (t.fontURL) {
            let el = document.getElementById("_ms-custom-font");
            if (!el) {
                el = document.createElement("style");
                el.id = "_ms-custom-font";
                document.head.appendChild(el);
            }
            el.textContent = `@font-face { font-family: "${t.font}"; src: url("${t.fontURL}"); }`;
        }
        document.body.style.fontFamily = `"${t.font}", Almendra, Palatino, Georgia, serif`;
    }
}

// ── Default copy text extractor ──────────────────────────────────────────
function defaultExtractCopyText(el) {
    const ts = el.querySelector(".ts")?.textContent || "";
    const badge = (el.querySelector(".badge")?.textContent || "").toUpperCase();
    const msg = el.querySelector(".msg")?.textContent || "";
    return msg ? `${ts} [${badge}] ${msg}` : `${ts} [${badge}]`;
}

// ── Time helpers ─────────────────────────────────────────────────────────
function pad2(n) { return String(n).padStart(2, "0"); }

function nowTs() {
    const d = new Date();
    return (
        pad2(d.getHours()) + ":" +
        pad2(d.getMinutes()) + ":" +
        pad2(d.getSeconds())
    );
}

// ── Scroll primitives ────────────────────────────────────────────────────
function _isNearBottom(logEl, thresh) {
    if (!logEl) return false;
    return (
        logEl.scrollHeight - logEl.scrollTop - logEl.clientHeight <=
        thresh
    );
}

function _trimLog(logEl, max) {
    while (logEl.childElementCount > max) {
        logEl.removeChild(logEl.firstElementChild);
    }
}

// ── Factory ──────────────────────────────────────────────────────────────
/**
 * @param {Object} config
 * @param {string} config.channel        - WebKit message handler name
 * @param {function} config.buildRow     - (entry) => HTMLElement
 * @param {string} [config.entrySelector="#log .entry, #log .step"]
 * @param {function} [config.extractCopyText] - (el) => string
 * @param {string} [config.clearAction="clearLog"] - global fn name for Clear
 * @param {number} [config.maxEntries=300]
 * @param {number} [config.scrollThresh=48]
 * @returns {Object} controller with methods to expose as globals
 */
window.createLogPanel = function createLogPanel(config) {
    const {
        channel,
        buildRow,
        entrySelector = "#log .entry, #log .step",
        extractCopyText = defaultExtractCopyText,
        clearAction = "clearLog",
        maxEntries = 300,
        scrollThresh = 48,
    } = config;

    // ── Host bridge ────────────────────────────────────────────────────
    function sendToHost(msg) {
        const s = typeof msg === "string" ? msg : JSON.stringify(msg);
        if (window.shellPost) {
            // Running inside the Macro Lab shell — route through msShell channel
            const data = typeof msg === "string" ? JSON.parse(msg) : msg;
            window.shellPost(channel, data.action || "unknown", data);
        } else {
            try {
                window.webkit.messageHandlers[channel].postMessage(s);
            } catch (e) {}
        }
    }

    function playSlot(slot) {
        sendToHost({ action: "playSlot", slot });
    }

    // ── Pause state ────────────────────────────────────────────────────
    let _paused = false;
    function togglePause() {
        _paused = !_paused;
        const btn = document.getElementById("pause-btn");
        if (btn) btn.textContent = _paused ? "Resume" : "Pause";
    }

    // ── Selection state ────────────────────────────────────────────────
    const _selected = new Set();
    let _lastClicked = null;

    function _getEntries() {
        return Array.from(document.querySelectorAll(entrySelector));
    }

    function _updateSelectionVisuals() {
        for (const el of _getEntries()) {
            el.classList.toggle("selected", _selected.has(el));
        }
    }

    function _handleEntryClick(e) {
        const row = e.currentTarget;
        const entries = _getEntries();
        const idx = entries.indexOf(row);
        if (idx === -1) return;
        playSlot("interact");

        if (e.shiftKey && _lastClicked !== null) {
            const lo = Math.min(_lastClicked, idx);
            const hi = Math.max(_lastClicked, idx);
            for (let i = lo; i <= hi; i++) _selected.add(entries[i]);
        } else if (e.metaKey || e.ctrlKey) {
            if (_selected.has(row)) _selected.delete(row);
            else _selected.add(row);
        } else {
            if (_selected.has(row) && _selected.size === 1) {
                _selected.delete(row);
            } else {
                _selected.clear();
                _selected.add(row);
            }
        }
        _lastClicked = idx;
        _updateSelectionVisuals();
    }

    function _copySelected() {
        if (_selected.size === 0) return;
        const lines = [];
        for (const el of _getEntries()) {
            if (_selected.has(el)) {
                lines.push(extractCopyText(el));
            }
        }
        const text = lines.join("\n");
        try { navigator.clipboard.writeText(text); } catch (_) {}
        playSlot("update");
    }

    function _selectAll() {
        _selected.clear();
        for (const el of _getEntries()) _selected.add(el);
        _updateSelectionVisuals();
    }

    // ── Context menu ───────────────────────────────────────────────────
    function closeCtxMenu() {
        document.getElementById("ctx-menu").classList.remove("open");
    }

    function showCtxMenu(x, y, items) {
        const el = document.getElementById("ctx-menu");
        el.innerHTML = "";
        for (const item of items) {
            if (item === "divider") {
                const d = document.createElement("div");
                d.className = "ctx-divider";
                el.appendChild(d);
                continue;
            }
            const row = document.createElement("div");
            row.className = "ctx-item";
            row.textContent = item.label;
            row.addEventListener("mouseenter", () => playSlot("hover"));
            row.addEventListener("click", (e) => {
                e.stopPropagation();
                playSlot("interact");
                closeCtxMenu();
                item.action();
            });
            el.appendChild(row);
        }
        el.classList.add("open");
        const mw = el.offsetWidth || 140;
        const mh = el.offsetHeight || 80;
        const vw = window.innerWidth;
        const vh = window.innerHeight;
        el.style.left = Math.min(x, vw - mw - 4) + "px";
        el.style.top = Math.min(y, vh - mh - 4) + "px";
    }

    // Suppress native context menu, show custom menu
    document.addEventListener("contextmenu", (e) => {
        e.preventDefault();
        const row = e.target.closest(".entry, .step");
        const items = [];
        if (row && !_selected.has(row)) {
            _selected.clear();
            _selected.add(row);
            _updateSelectionVisuals();
        }
        if (_selected.size > 0) {
            items.push({ label: "Copy", action: _copySelected });
            items.push("divider");
        }
        items.push({ label: "Select All", action: _selectAll });
        items.push({
            label: "Clear",
            action: () => {
                if (typeof window[clearAction] === "function") window[clearAction]();
            },
        });
        showCtxMenu(e.clientX, e.clientY, items);
    });

    document.addEventListener("click", () => closeCtxMenu());

    // ── Keyboard shortcuts ─────────────────────────────────────────────
    document.addEventListener("keydown", (e) => {
        if (e.key === "Escape") closeCtxMenu();
        const inInput = e.target.tagName === "INPUT" || e.target.tagName === "TEXTAREA";
        if ((e.metaKey || e.ctrlKey) && e.key === "a" && !inInput) {
            e.preventDefault();
            _selectAll();
        }
        if ((e.metaKey || e.ctrlKey) && e.key === "c" && !inInput && _selected.size > 0) {
            e.preventDefault();
            _copySelected();
        }
    });

    // ── Header drag ────────────────────────────────────────────────────
    (function () {
        let _drag = null;
        const header = document.getElementById("header");
        if (!header) return;
        header.addEventListener("mousedown", (e) => {
            if (e.button !== 0) return;
            if (e.target.closest(".header-btns")) return;
            _drag = { ox: e.screenX, oy: e.screenY };
            const onMove = (ev) => {
                if (!_drag) return;
                sendToHost({
                    action: "move",
                    dx: ev.screenX - _drag.ox,
                    dy: ev.screenY - _drag.oy,
                });
                _drag.ox = ev.screenX;
                _drag.oy = ev.screenY;
            };
            const onUp = () => {
                _drag = null;
                window.removeEventListener("mousemove", onMove);
                window.removeEventListener("mouseup", onUp);
            };
            window.addEventListener("mousemove", onMove);
            window.addEventListener("mouseup", onUp);
        });
    })();

    // ── Default appendEntry / loadHistory (single #log) ────────────────
    function appendEntry(entry) {
        if (_paused) return;
        const log = document.getElementById("log");
        if (!log) return;
        const atBottom = _isNearBottom(log, scrollThresh);
        log.appendChild(buildRow(entry));
        _trimLog(log, maxEntries);
        if (atBottom) log.scrollTop = log.scrollHeight;
    }

    function loadHistory(entries) {
        const log = document.getElementById("log");
        if (!log) return;
        log.innerHTML = "";
        const capped =
            entries && entries.length > maxEntries
                ? entries.slice(-maxEntries)
                : entries || [];
        const frag = document.createDocumentFragment();
        capped.forEach((e) => frag.appendChild(buildRow(e)));
        log.appendChild(frag);
        log.scrollTop = log.scrollHeight;
    }

    // ── Actions ────────────────────────────────────────────────────────
    function clearLog() {
        const log = document.getElementById("log");
        if (log) log.innerHTML = "";
        sendToHost({ action: "clear" });
    }

    function closePanel() {
        sendToHost({ action: "close" });
    }

    // ── Resize guard (popout boundary protection) ─────────────────────
    // Borderless popout windows don't get native resize handles, but yabai
    // or other window managers can still resize them.  Enforce minimum
    // dimensions by sending a clampSize action to the host when the window
    // shrinks below threshold.
    (function () {
        let _clampTimer = null;
        const MIN_W = 400, MIN_H = 300;
        window.addEventListener("resize", function () {
            if (window.__msResizing) return;  // Lua eventtap handles clamping
            if (_clampTimer) clearTimeout(_clampTimer);
            _clampTimer = setTimeout(function () {
                _clampTimer = null;
                const w = window.innerWidth, h = window.innerHeight;
                if (w < MIN_W || h < MIN_H) {
                    sendToHost({ action: "clampSize", w: Math.max(w, MIN_W), h: Math.max(h, MIN_H) });
                }
            }, 50);
        });
    })();

    // ── Resize grab zones (popout windows) ────────────────────────────
    // Adds edge/corner grab zones for drag-to-resize on popout windows.
    // The zones are injected into <body> outside #popout-root.
    (function () {
        var zones = [
            { cls: "resize-n", edge: "n", css: "top:0;left:6px;right:6px;height:4px;cursor:ns-resize;" },
            { cls: "resize-s", edge: "s", css: "bottom:0;left:6px;right:6px;height:4px;cursor:ns-resize;" },
            { cls: "resize-e", edge: "e", css: "right:0;top:6px;bottom:6px;width:4px;cursor:ew-resize;" },
            { cls: "resize-w", edge: "w", css: "left:0;top:6px;bottom:6px;width:4px;cursor:ew-resize;" },
            { cls: "resize-ne", edge: "ne", css: "top:0;right:0;width:8px;height:8px;cursor:nesw-resize;" },
            { cls: "resize-nw", edge: "nw", css: "top:0;left:0;width:8px;height:8px;cursor:nwse-resize;" },
            { cls: "resize-se", edge: "se", css: "bottom:0;right:0;width:8px;height:8px;cursor:nwse-resize;" },
            { cls: "resize-sw", edge: "sw", css: "bottom:0;left:0;width:8px;height:8px;cursor:nesw-resize;" },
        ];
        zones.forEach(function(z) {
            var el = document.createElement("div");
            el.className = "resize-zone " + z.cls;
            el.setAttribute("data-edge", z.edge);
            el.style.cssText = "position:fixed;z-index:9999;background:transparent;" + z.css;
            el.addEventListener("mousedown", function(e) {
                if (e.button !== 0) return;
                window.__msResizing = true;
                sendToHost({ action: "resizeStart", edge: z.edge });
                document.body.classList.add("resizing");
                var onUp = function() {
                    window.__msResizing = false;
                    document.body.classList.remove("resizing");
                    window.removeEventListener("mouseup", onUp);
                };
                window.addEventListener("mouseup", onUp);
            });
            document.body.appendChild(el);
        });
        // Add resizing CSS if not already present
        if (!document.getElementById("resize-zone-style")) {
            var style = document.createElement("style");
            style.id = "resize-zone-style";
            style.textContent = "body.resizing * { pointer-events: none !important; }";
            document.head.appendChild(style);
        }
    })();

    // ── Controller ─────────────────────────────────────────────────────
    return {
        sendToHost,
        playSlot,
        togglePause,
        appendEntry,
        loadHistory,
        clearLog,
        closePanel,
        getSelected: () => _selected,
        isPaused: () => _paused,
        applyTheme,
        hexToRgb,
        pad2,
        nowTs,
        // Primitives for panels that override appendEntry/loadHistory
        isNearBottom: (logEl) => _isNearBottom(logEl, scrollThresh),
        trimLog: (logEl) => _trimLog(logEl, maxEntries),
        buildRow,
        maxEntries,
        _handleEntryClick,
        _updateSelectionVisuals,
    };
}
