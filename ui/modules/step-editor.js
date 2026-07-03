/**
 * StepEditor — inline parameter editor for macro step blocks.
 *
 * Opens an editable form below a selected step block, with appropriate input
 * widgets for each parameter type (key capture, modifier chips, number spinners,
 * text inputs, dropdown selects, condition editors, array editors).
 *
 * Usage (IIFE — in ms_shell.html or other non-module contexts):
 *
 *   // Available as window.StepEditor after this script loads.
 *   var editor = new StepEditor({ canvas: stepCanvasInstance });
 *   editor.open(stepSid);  // opens editor below the step block
 *
 * The editor hooks into StepCanvas._render to persist through re-renders
 * and auto-closes on click outside or Escape key.
 */

// ── Parameter Definitions ──────────────────────────────────────────────
// Maps action names to their parameter schemas. Unrecognized actions fall back
// to type inference from the actual parameter values.

const PARAM_DEFS = {
    "ms.type":          { key: "key", mods: "mods" },
    "ms.press":         { key: "key", mods: "mods" },
    "ms.hold":          { key: "key" },
    "ms.release":       { key: "key" },
    "ms.wait":          { ms: "number" },
    "ms.cam":           { dx: "number", dy: "number" },
    "ms.Mouse":         { operation: { type: "select", options: ["Move","Click","Drag","Press","Release"] },
                          button:    { type: "select", options: ["Left","Right","Middle"] },
                          reference: { type: "select", options: ["Mouse","Screen","Window"] },
                          x: "number", y: "number" },
    "ms.click":         { button: { type: "select", options: ["Left","Right","Middle"] },
                          x: "number", y: "number" },
    "ms.scroll":        { dx: "number", dy: "number" },
    "ms.copy":          { text: "string" },
    "ms.input":         { text: "string" },
    "ms.search":        { text: "string" },
    "ms.variable":      { name: "string", value: "string" },
    "ms.watch":         { event: "string" },
    "ms.window":        { operation: "string" },
    "ms.alert":         { text: "string" },
    "ms.load":          { path: "string" },
    "ms.save":          { path: "string" },
    "ms.pixelScan":     { region: "string" },
    "if":               { condition: "condition" },
    "while":            { condition: "condition" },
    "for":              { var: "string", from: "number", to: "number" },
};

// Keys whose values should be hidden in the editor (structural, not user params).
const STRUCTURAL_KEYS = new Set(["then", "else", "body"]);

// ── Key Normalization ──────────────────────────────────────────────────
// Must match the normalizeKey function in the function picker.

function normalizeKey(e) {
    const map = {
        " ":           "space",
        "ArrowUp":     "up",
        "ArrowDown":   "down",
        "ArrowLeft":   "left",
        "ArrowRight":  "right",
        "Backspace":   "delete",
        "Escape":      "escape",
        "Enter":       "return",
        "Tab":         "tab",
        "CapsLock":    "capslock",
        "Shift":       "shift",
        "Control":     "ctrl",
        "Alt":         "alt",
        "Meta":        "cmd",
        "Delete":      "forwarddelete",
        "Home":        "home",
        "End":         "end",
        "PageUp":      "pageup",
        "PageDown":    "pagedown",
        "Insert":      "help",
        "F1": "f1", "F2": "f2", "F3": "f3", "F4": "f4",
        "F5": "f5", "F6": "f6", "F7": "f7", "F8": "f8",
        "F9": "f9", "F10": "f10", "F11": "f11", "F12": "f12",
    };
    if (map[e.key]) return map[e.key];
    if (e.key.length === 1) return e.key.toLowerCase();
    return e.key.toLowerCase();
}

function esc(s) {
    const d = document.createElement("div");
    d.appendChild(document.createTextNode(s));
    return d.innerHTML;
}

// ── CSS (injected once) ────────────────────────────────────────────────
let _cssInjected = false;

function injectCSS() {
    if (_cssInjected) return;
    _cssInjected = true;
    const style = document.createElement("style");
    style.id = "step-editor-css";
    style.textContent = `
/* ── Step Inline Editor ──────────────────────────────────────────── */
.step-editor-panel {
    background: var(--surface);
    border: 1px solid var(--border);
    border-top: 2px solid var(--accent);
    border-radius: 0 0 var(--radius) var(--radius);
    margin: 0 2px 4px 2px;
    overflow: hidden;
    max-height: 0;
    opacity: 0;
    transition: max-height 0.25s ease, opacity 0.2s ease, padding 0.25s ease;
    padding: 0 12px;
    box-sizing: border-box;
    position: relative;
}
.step-editor-panel.open {
    max-height: 500px;
    opacity: 1;
    padding: 10px 12px 12px 12px;
}

.step-editor-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-bottom: 10px;
    padding-bottom: 6px;
    border-bottom: 1px solid var(--border-dim);
}
.step-editor-title {
    font-family: "SF Mono", "Menlo", "Consolas", monospace;
    font-size: 10px;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.6px;
    color: var(--text3);
}
.step-editor-close {
    width: 18px; height: 18px;
    display: flex; align-items: center; justify-content: center;
    border-radius: var(--radius-s);
    cursor: pointer;
    opacity: 0.4;
    transition: opacity 0.1s, background 0.1s;
}
.step-editor-close:hover {
    opacity: 1;
    background: var(--hover);
}
.step-editor-close svg { width: 12px; height: 12px; }
.step-editor-close svg path { stroke: var(--text); fill: none; }

/* ── Form Grid ──────────────────────────────────────────────────── */
.step-editor-form {
    display: flex;
    flex-direction: column;
    gap: 10px;
}
.step-editor-row {
    display: flex;
    align-items: center;
    gap: 8px;
}
.step-editor-label {
    font-size: 10px;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.6px;
    color: var(--text3);
    width: 80px;
    flex-shrink: 0;
    text-align: right;
    padding-right: 4px;
}
.step-editor-control {
    flex: 1;
    min-width: 0;
    display: flex;
    align-items: center;
    gap: 4px;
}

/* ── Text Input ─────────────────────────────────────────────────── */
.step-ed-text {
    width: 100%;
    background: var(--surface2);
    border: 1px solid var(--border-dim);
    border-radius: var(--radius);
    color: var(--text);
    font-family: "SF Mono", "Menlo", "Consolas", monospace;
    font-size: 11px;
    padding: 4px 7px;
    outline: none;
    transition: border-color 0.15s;
    user-select: text;
    -webkit-user-select: text;
    box-sizing: border-box;
}
.step-ed-text:focus { border-color: var(--accent); }

/* ── Number Input ───────────────────────────────────────────────── */
.step-ed-number-wrap {
    display: flex;
    align-items: center;
    gap: 0;
    flex: 1;
}
.step-ed-number {
    width: 100%;
    background: var(--surface2);
    border: 1px solid var(--border-dim);
    border-radius: var(--radius);
    color: var(--text);
    font-family: "SF Mono", "Menlo", "Consolas", monospace;
    font-size: 11px;
    padding: 4px 7px;
    outline: none;
    transition: border-color 0.15s;
    user-select: text;
    -webkit-user-select: text;
    -moz-appearance: textfield;
    box-sizing: border-box;
}
.step-ed-number::-webkit-inner-spin-button,
.step-ed-number::-webkit-outer-spin-button { -webkit-appearance: none; margin: 0; }
.step-ed-number:focus { border-color: var(--accent); }

.step-ed-num-btn {
    width: 24px;
    height: 26px;
    display: flex;
    align-items: center;
    justify-content: center;
    background: var(--surface2);
    border: 1px solid var(--border-dim);
    color: var(--text3);
    font-size: 13px;
    font-weight: 700;
    cursor: pointer;
    transition: background 0.1s, color 0.1s, border-color 0.1s;
    user-select: none;
    -webkit-user-select: none;
    flex-shrink: 0;
}
.step-ed-num-btn:hover {
    background: var(--hover);
    color: var(--text);
    border-color: var(--border);
}
.step-ed-num-btn:first-child { border-radius: var(--radius) 0 0 var(--radius); border-right: none; }
.step-ed-num-btn:last-child  { border-radius: 0 var(--radius) var(--radius) 0; border-left: none; }
.step-ed-num-btn:only-child  { border-radius: var(--radius); }

/* ── Key Capture Button ─────────────────────────────────────────── */
.step-ed-key-btn {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    background: var(--surface2);
    border: 1px solid var(--border-dim);
    border-radius: var(--radius);
    color: var(--text);
    font-family: "SF Mono", "Menlo", "Consolas", monospace;
    font-size: 11px;
    padding: 4px 12px;
    cursor: pointer;
    transition: border-color 0.15s, background 0.15s;
    min-width: 50px;
    text-align: center;
    user-select: text;
    -webkit-user-select: text;
}
.step-ed-key-btn:hover { border-color: var(--accent); }
.step-ed-key-btn.capturing {
    border-color: var(--accent);
    background: rgba(196, 26, 26, 0.15);
    color: var(--accent-hi);
    animation: step-ed-pulse 1s ease-in-out infinite;
}
@keyframes step-ed-pulse {
    0%, 100% { opacity: 1; }
    50%      { opacity: 0.5; }
}
.step-ed-key-hint {
    font-size: 9px;
    color: var(--text3);
    opacity: 0.6;
    font-style: italic;
}

/* ── Modifier Chips ─────────────────────────────────────────────── */
.step-ed-mods {
    display: flex;
    gap: 3px;
}
.step-ed-mod-chip {
    display: flex;
    align-items: center;
    justify-content: center;
    background: var(--surface2);
    border: 1px solid var(--border-dim);
    border-radius: var(--radius);
    color: var(--text3);
    font-family: "SF Mono", "Menlo", "Consolas", monospace;
    font-size: 10px;
    font-weight: 600;
    padding: 3px 8px;
    cursor: pointer;
    transition: all 0.1s;
    user-select: none;
    -webkit-user-select: none;
    text-transform: uppercase;
    letter-spacing: 0.3px;
}
.step-ed-mod-chip:hover {
    border-color: var(--accent);
    color: var(--text);
}
.step-ed-mod-chip.on {
    background: rgba(196, 26, 26, 0.18);
    border-color: var(--accent);
    color: var(--accent-hi);
}

/* ── Select Dropdown ────────────────────────────────────────────── */
.step-ed-select {
    width: 100%;
    background: var(--surface2);
    border: 1px solid var(--border-dim);
    border-radius: var(--radius);
    color: var(--text);
    font-family: "SF Mono", "Menlo", "Consolas", monospace;
    font-size: 11px;
    padding: 4px 7px;
    outline: none;
    cursor: pointer;
    transition: border-color 0.15s;
    user-select: text;
    -webkit-user-select: text;
    -webkit-appearance: none;
    box-sizing: border-box;
}
.step-ed-select:focus { border-color: var(--accent); }
.step-ed-select option { background: var(--surface); color: var(--text); }

/* ── Condition / Expression Editor ──────────────────────────────── */
.step-ed-condition {
    width: 100%;
    background: var(--surface2);
    border: 1px solid var(--border-dim);
    border-radius: var(--radius);
    color: var(--accent-hi);
    font-family: "SF Mono", "Menlo", "Consolas", monospace;
    font-size: 11px;
    padding: 5px 8px;
    outline: none;
    resize: vertical;
    min-height: 28px;
    max-height: 100px;
    line-height: 1.5;
    transition: border-color 0.15s;
    user-select: text;
    -webkit-user-select: text;
    box-sizing: border-box;
}
.step-ed-condition:focus { border-color: var(--accent); }

/* ── Array Editor ───────────────────────────────────────────────── */
.step-ed-array {
    display: flex;
    flex-direction: column;
    gap: 4px;
    width: 100%;
}
.step-ed-array-item {
    display: flex;
    align-items: center;
    gap: 4px;
}
.step-ed-array-item .step-ed-text { flex: 1; }
.step-ed-array-remove {
    width: 20px; height: 20px;
    display: flex; align-items: center; justify-content: center;
    border-radius: var(--radius-s);
    cursor: pointer;
    opacity: 0.4;
    transition: opacity 0.1s, background 0.1s;
    flex-shrink: 0;
    color: var(--text3);
    font-size: 14px;
    font-weight: 700;
}
.step-ed-array-remove:hover { opacity: 1; background: var(--danger-bg); color: var(--danger); }
.step-ed-array-add {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    padding: 3px 8px;
    background: var(--surface2);
    border: 1px solid var(--border-dim);
    border-radius: var(--radius);
    color: var(--text3);
    font-size: 10px;
    font-weight: 600;
    cursor: pointer;
    transition: border-color 0.1s, color 0.1s;
    align-self: flex-start;
    text-transform: uppercase;
    letter-spacing: 0.3px;
}
.step-ed-array-add:hover { border-color: var(--accent); color: var(--text); }

/* ── No-params ──────────────────────────────────────────────────── */
.step-ed-no-params {
    color: var(--text3);
    font-size: 11px;
    font-style: italic;
    padding: 4px 0;
}
`;
    document.head.appendChild(style);
}

// ── StepEditor Class ───────────────────────────────────────────────────

/**
 * @param {Object} opts
 * @param {Object} opts.canvas — StepCanvas instance (IIFE or ES module)
 * @param {string} [opts.svgBase] — base URL for svg/ directory (default: "./svg/")
 * @param {function} [opts.onUpdate] — called after a param is updated (sid, params)
 */
class StepEditor {
    constructor(opts = {}) {
        injectCSS();

        this._canvas  = opts.canvas;
        this._svgBase = opts.svgBase || "./svg/";
        this._onUpdate = opts.onUpdate || (() => {});

        this._stepSid   = null;   // currently edited step's _sid
        this._stepEl    = null;   // DOM element of the step block
        this._panelEl   = null;   // the editor panel DOM element
        this._formEl    = null;   // the form container inside the panel
        this._open      = false;
        this._capturingKey = null; // active key-capture handler
        this._keyHandler = null;  // bound keydown handler for capture

        // Wire into canvas _render to persist through re-renders
        this._hookCanvasRender();

        // Global escape to close
        this._onEscape = (e) => {
            if (e.key === "Escape" && this._open) {
                e.stopPropagation();
                this.close();
            }
        };
    }

    // ── Hook into StepCanvas._render ───────────────────────────────────

    _hookCanvasRender() {
        if (!this._canvas) return;
        const origRender = this._canvas._render;
        if (typeof origRender !== "function") return;

        const editor = this;
        this._canvas._render = function() {
            origRender.call(this);
            // After re-render, re-inject the editor panel if it was open
            if (editor._open && editor._stepSid) {
                editor._reInject();
            }
        };
    }

    /**
     * Re-inject the editor panel after a canvas re-render.
     * Finds the new step element by its _sid and appends the panel to it.
     */
    _reInject() {
        if (!this._stepSid) return;
        const step = this._canvas._map[this._stepSid];
        if (!step) {
            // Step was deleted
            this.close();
            return;
        }
        const root = this._canvas._root;
        if (!root) { this.close(); return; }

        // Find the new step element
        const newEl = root.querySelector(
            `[data-sid="${this._stepSid}"] > .step-block[data-sid="${this._stepSid}"], ` +
            `.step-block[data-sid="${this._stepSid}"]`
        );
        if (!newEl) { this.close(); return; }

        this._stepEl = newEl;
        // Rebuild form with fresh step data
        this._buildForm(step);
        // Re-append panel to the step element
        if (this._panelEl && !this._panelEl.parentNode) {
            this._stepEl.parentNode.insertBefore(this._panelEl, this._stepEl.nextSibling);
        }
    }

    // ── Open / Close ───────────────────────────────────────────────────

    /**
     * Open the editor for a given step.
     * @param {string} sid — step _sid
     */
    open(sid) {
        if (!this._canvas) return;
        const step = this._canvas._map[sid];
        if (!step) return;

        // Find the step block DOM element
        const root = this._canvas._root;
        if (!root) return;
        const stepEl = root.querySelector(
            `[data-sid="${sid}"] > .step-block[data-sid="${sid}"], ` +
            `.step-block[data-sid="${sid}"]`
        );
        if (!stepEl) return;

        // Close previous
        if (this._open && this._stepSid !== sid) {
            this._removePanel();
        }

        this._stepSid = sid;
        this._stepEl  = stepEl;
        this._open    = true;

        // Create panel
        this._panelEl = document.createElement("div");
        this._panelEl.className = "step-editor-panel";

        this._buildForm(step);

        // Insert after the step block element in the DOM
        stepEl.parentNode.insertBefore(this._panelEl, stepEl.nextSibling);

        // Trigger open animation
        requestAnimationFrame(() => {
            if (this._panelEl) this._panelEl.classList.add("open");
        });

        // Close on click outside
        setTimeout(() => {
            document.addEventListener("click", this._onClickOutside = (e) => {
                if (!this._panelEl) return;
                if (!this._panelEl.contains(e.target) && !this._stepEl.contains(e.target)) {
                    this.close();
                }
            }, true);
            document.addEventListener("keydown", this._onEscape, true);
        }, 50);
    }

    /**
     * Close the editor.
     */
    close() {
        if (!this._open) return;
        this._open = false;

        // Cancel any active key capture
        this._cancelCapture();

        // Remove event listeners
        if (this._onClickOutside) {
            document.removeEventListener("click", this._onClickOutside, true);
            this._onClickOutside = null;
        }
        document.removeEventListener("keydown", this._onEscape, true);

        this._removePanel();
        this._stepSid = null;
        this._stepEl  = null;
    }

    _removePanel() {
        if (this._panelEl && this._panelEl.parentNode) {
            this._panelEl.classList.remove("open");
            // Let the transition finish, then remove
            const panel = this._panelEl;
            setTimeout(() => {
                if (panel.parentNode) panel.parentNode.removeChild(panel);
            }, 260);
        }
        this._panelEl = null;
        this._formEl  = null;
    }

    // ── Build Form ─────────────────────────────────────────────────────

    _buildForm(step) {
        if (!this._panelEl) return;
        this._panelEl.innerHTML = "";

        // Header
        const header = document.createElement("div");
        header.className = "step-editor-header";

        const title = document.createElement("div");
        title.className = "step-editor-title";
        title.textContent = step.action + " — parameters";
        header.appendChild(title);

        const closeBtn = document.createElement("div");
        closeBtn.className = "step-editor-close";
        closeBtn.innerHTML = '<svg viewBox="0 0 24 24"><path d="M18 6L6 18M6 6l12 12" stroke-width="2" stroke-linecap="round"/></svg>';
        closeBtn.addEventListener("click", (e) => { e.stopPropagation(); this.close(); });
        header.appendChild(closeBtn);

        this._panelEl.appendChild(header);

        // Form
        this._formEl = document.createElement("div");
        this._formEl.className = "step-editor-form";
        this._panelEl.appendChild(this._formEl);

        // Get param defs for this action
        const defs = this._getParamDefs(step);
        const keys = Object.keys(defs);

        if (keys.length === 0) {
            const nope = document.createElement("div");
            nope.className = "step-ed-no-params";
            nope.textContent = "No editable parameters.";
            this._formEl.appendChild(nope);
            return;
        }

        for (const key of keys) {
            const def = defs[key];
            const value = step.params ? step.params[key] : undefined;
            const row = this._buildParamRow(key, def, value, step._sid);
            if (row) this._formEl.appendChild(row);
        }
    }

    /**
     * Get parameter definitions for a step.
     * Uses the predefined map if available, otherwise infers from values.
     */
    _getParamDefs(step) {
        const action = step.action;

        // Check predefined map
        if (PARAM_DEFS[action]) {
            const defs = {};
            for (const [key, typeOrDef] of Object.entries(PARAM_DEFS[action])) {
                if (typeof typeOrDef === "string") {
                    defs[key] = { type: typeOrDef };
                } else {
                    defs[key] = typeOrDef;
                }
            }
            return defs;
        }

        // Infer from actual params
        if (!step.params) return {};
        const defs = {};
        for (const [key, value] of Object.entries(step.params)) {
            if (STRUCTURAL_KEYS.has(key)) continue;
            defs[key] = { type: this._inferType(key, value) };
        }
        return defs;
    }

    /**
     * Infer parameter type from its key name and current value.
     */
    _inferType(key, value) {
        // Key name hints
        if (key === "key")  return "key";
        if (key === "mods") return "mods";
        if (key === "condition" || key === "expr") return "condition";

        // Value type
        if (Array.isArray(value)) return "array";
        if (typeof value === "number") return "number";
        return "string";
    }

    // ── Build Parameter Row ────────────────────────────────────────────

    _buildParamRow(key, def, value, sid) {
        const row = document.createElement("div");
        row.className = "step-editor-row";

        const label = document.createElement("div");
        label.className = "step-editor-label";
        label.textContent = key;
        row.appendChild(label);

        const control = document.createElement("div");
        control.className = "step-editor-control";

        switch (def.type) {
            case "string":
                control.appendChild(this._createStringInput(key, value, sid));
                break;
            case "number":
                control.appendChild(this._createNumberInput(key, value, sid));
                break;
            case "key":
                control.appendChild(this._createKeyCapture(key, value, sid));
                break;
            case "mods":
                control.appendChild(this._createModChips(key, value, sid));
                break;
            case "select":
                control.appendChild(this._createSelectInput(key, value, def.options, sid));
                break;
            case "condition":
                control.appendChild(this._createConditionInput(key, value, sid));
                break;
            case "array":
                control.appendChild(this._createArrayEditor(key, value, sid));
                break;
            default:
                control.appendChild(this._createStringInput(key, value, sid));
        }

        row.appendChild(control);
        return row;
    }

    // ── Input Widgets ──────────────────────────────────────────────────

    /**
     * String text input.
     */
    _createStringInput(key, value, sid) {
        const inp = document.createElement("input");
        inp.type = "text";
        inp.className = "step-ed-text";
        inp.value = (value !== undefined && value !== null) ? String(value) : "";
        inp.placeholder = key + "…";
        inp.setAttribute("spellcheck", "false");
        inp.setAttribute("autocomplete", "off");
        inp.setAttribute("autocorrect", "off");
        inp.setAttribute("autocapitalize", "off");

        inp.addEventListener("input", () => {
            this._updateParam(sid, key, inp.value);
        });
        inp.addEventListener("keydown", (e) => e.stopPropagation());

        return inp;
    }

    /**
     * Number input with +/- step controls.
     */
    _createNumberInput(key, value, sid) {
        const wrap = document.createElement("div");
        wrap.className = "step-ed-number-wrap";

        const btnMinus = document.createElement("button");
        btnMinus.className = "step-ed-num-btn";
        btnMinus.textContent = "−";
        wrap.appendChild(btnMinus);

        const inp = document.createElement("input");
        inp.type = "number";
        inp.className = "step-ed-number";
        inp.value = (value !== undefined && value !== null) ? String(value) : "0";
        inp.step = "1";
        wrap.appendChild(inp);

        const btnPlus = document.createElement("button");
        btnPlus.className = "step-ed-num-btn";
        btnPlus.textContent = "+";
        wrap.appendChild(btnPlus);

        const emit = () => {
            const v = parseFloat(inp.value) || 0;
            this._updateParam(sid, key, v);
        };

        inp.addEventListener("input", emit);
        inp.addEventListener("keydown", (e) => {
            e.stopPropagation();
            if (e.key === "ArrowUp")   { inp.value = String((parseFloat(inp.value)||0) + (e.shiftKey ? 10 : 1)); emit(); e.preventDefault(); }
            if (e.key === "ArrowDown") { inp.value = String((parseFloat(inp.value)||0) - (e.shiftKey ? 10 : 1)); emit(); e.preventDefault(); }
        });

        const step = (delta) => {
            inp.value = String((parseFloat(inp.value)||0) + delta);
            emit();
        };
        btnMinus.addEventListener("click", (e) => { e.stopPropagation(); step(e.shiftKey ? -10 : -1); });
        btnPlus.addEventListener("click",  (e) => { e.stopPropagation(); step(e.shiftKey ? 10 : 1); });

        return wrap;
    }

    /**
     * Key capture button — press any key to set.
     */
    _createKeyCapture(key, value, sid) {
        const wrap = document.createElement("div");
        wrap.style.cssText = "display:flex;align-items:center;gap:8px";

        const btn = document.createElement("button");
        btn.className = "step-ed-key-btn";
        btn.textContent = (value != null && value !== "") ? String(value) : "Click to set";
        wrap.appendChild(btn);

        const hint = document.createElement("span");
        hint.className = "step-ed-key-hint";
        hint.textContent = "press a key…";
        wrap.appendChild(hint);

        btn.addEventListener("click", (e) => {
            e.stopPropagation();
            this._startCapture(key, btn, sid);
        });

        return wrap;
    }

    /**
     * Start key capture mode on a button.
     */
    _startCapture(key, btn, sid) {
        this._cancelCapture();

        btn.classList.add("capturing");
        btn.textContent = "…";

        const handler = (e) => {
            e.preventDefault();
            e.stopPropagation();

            const normalized = normalizeKey(e);
            this._updateParam(sid, key, normalized);

            btn.classList.remove("capturing");
            btn.textContent = normalized || "???";

            document.removeEventListener("keydown", handler, true);
            this._capturingKey = null;
            this._keyHandler = null;
        };

        this._capturingKey = key;
        this._keyHandler = handler;
        document.addEventListener("keydown", handler, true);
    }

    /**
     * Cancel any active key capture.
     */
    _cancelCapture() {
        if (this._keyHandler) {
            document.removeEventListener("keydown", this._keyHandler, true);
            this._keyHandler = null;
            this._capturingKey = null;
        }
    }

    /**
     * Modifier toggle chips (ctrl/alt/shift/cmd).
     */
    _createModChips(key, value, sid) {
        const MOD_LIST = ["ctrl", "alt", "shift", "cmd"];
        const currentMods = Array.isArray(value) ? value : [];

        const wrap = document.createElement("div");
        wrap.className = "step-ed-mods";

        for (const mod of MOD_LIST) {
            const chip = document.createElement("button");
            chip.className = "step-ed-mod-chip" + (currentMods.includes(mod) ? " on" : "");
            chip.textContent = mod;
            chip.addEventListener("click", (e) => {
                e.stopPropagation();
                chip.classList.toggle("on");
                // Gather active mods
                const active = [];
                wrap.querySelectorAll(".step-ed-mod-chip.on").forEach(c => active.push(c.textContent));
                this._updateParam(sid, key, active);
            });
            wrap.appendChild(chip);
        }

        return wrap;
    }

    /**
     * Dropdown select for enum values.
     */
    _createSelectInput(key, value, options, sid) {
        const sel = document.createElement("select");
        sel.className = "step-ed-select";

        if (!options || options.length === 0) {
            options = [String(value || "")];
        }

        for (const opt of options) {
            const o = document.createElement("option");
            o.value = opt;
            o.textContent = opt;
            sel.appendChild(o);
        }

        // Set current value
        if (value !== undefined && value !== null) {
            sel.value = String(value);
        }

        sel.addEventListener("change", () => {
            this._updateParam(sid, key, sel.value);
        });
        sel.addEventListener("keydown", (e) => e.stopPropagation());

        return sel;
    }

    /**
     * Condition / Lua expression editor — monospace textarea.
     */
    _createConditionInput(key, value, sid) {
        const ta = document.createElement("textarea");
        ta.className = "step-ed-condition";
        ta.rows = 1;
        ta.value = (value !== undefined && value !== null) ? String(value) : "";
        ta.placeholder = "Lua expression…";
        ta.setAttribute("spellcheck", "false");
        ta.setAttribute("autocomplete", "off");
        ta.setAttribute("autocorrect", "off");
        ta.setAttribute("autocapitalize", "off");

        // Auto-resize
        const autoResize = () => {
            ta.style.height = "auto";
            ta.style.height = Math.min(ta.scrollHeight, 100) + "px";
        };

        ta.addEventListener("input", () => {
            this._updateParam(sid, key, ta.value);
            autoResize();
        });
        ta.addEventListener("keydown", (e) => e.stopPropagation());

        // Initial resize
        requestAnimationFrame(autoResize);

        return ta;
    }

    /**
     * Array editor — add/remove items.
     */
    _createArrayEditor(key, value, sid) {
        const items = Array.isArray(value) ? [...value] : [];
        const wrap = document.createElement("div");
        wrap.className = "step-ed-array";

        const renderItems = () => {
            // Clear existing items (keep the add button if present)
            wrap.querySelectorAll(".step-ed-array-item").forEach(el => el.remove());

            for (let i = 0; i < items.length; i++) {
                const itemRow = document.createElement("div");
                itemRow.className = "step-ed-array-item";

                const inp = document.createElement("input");
                inp.type = "text";
                inp.className = "step-ed-text";
                inp.value = String(items[i]);
                inp.setAttribute("spellcheck", "false");
                inp.setAttribute("autocomplete", "off");
                inp.setAttribute("autocorrect", "off");
                inp.setAttribute("autocapitalize", "off");
                inp.addEventListener("input", () => {
                    items[i] = inp.value;
                    this._updateParam(sid, key, [...items]);
                });
                inp.addEventListener("keydown", (e) => e.stopPropagation());
                itemRow.appendChild(inp);

                const removeBtn = document.createElement("div");
                removeBtn.className = "step-ed-array-remove";
                removeBtn.textContent = "×";
                removeBtn.addEventListener("click", (e) => {
                    e.stopPropagation();
                    items.splice(i, 1);
                    this._updateParam(sid, key, [...items]);
                    renderItems();
                });
                itemRow.appendChild(removeBtn);

                wrap.appendChild(itemRow);
            }
        };

        renderItems();

        const addBtn = document.createElement("button");
        addBtn.className = "step-ed-array-add";
        addBtn.textContent = "+ add item";
        addBtn.addEventListener("click", (e) => {
            e.stopPropagation();
            items.push("");
            this._updateParam(sid, key, [...items]);
            renderItems();
        });
        wrap.appendChild(addBtn);

        return wrap;
    }

    // ── Update Parameter ───────────────────────────────────────────────

    /**
     * Update a single parameter on the step and notify the canvas.
     */
    _updateParam(sid, key, value) {
        if (!this._canvas) return;
        this._canvas.updateStep(sid, { [key]: value });
        this._onUpdate(sid, { [key]: value });
    }

    // ── Destroy ────────────────────────────────────────────────────────

    destroy() {
        this.close();
        this._canvas = null;
    }
}

// ── Expose for IIFE contexts ───────────────────────────────────────────
if (typeof window !== "undefined") {
    window.StepEditor = StepEditor;
}
