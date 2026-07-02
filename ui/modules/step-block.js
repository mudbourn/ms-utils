/**
 * StepBlock — visual macro step block renderer and drag-and-drop manager.
 *
 * Renders macro steps as draggable blocks with nesting support (if/for/while).
 * Each block shows an icon, action name, parameter summary, drag handle, and
 * delete button. Blocks can be reordered via drag-and-drop and nested inside
 * control-flow containers.
 *
 * Usage (ES module):
 *
 *   import { StepCanvas } from "./modules/step-block.js";
 *   const canvas = new StepCanvas(containerEl, { onChange, svgBase });
 *   canvas.load(macroDef.steps);
 *   canvas.addStep({ action: "ms.type", params: { key: "/", mods: [] } });
 *   const steps = canvas.serialize();
 *
 * Usage (IIFE — in ms_shell.html or other non-module contexts):
 *
 *   // Already available as window.StepCanvas after this script loads.
 *   const canvas = new window.StepCanvas(containerEl, { onChange, svgBase });
 *   ...
 */

// ── SVG icon cache ──────────────────────────────────────────────────────
const _svgCache = {};

/**
 * Fetch an SVG file and return its innerHTML (cached).
 * @param {string} base  — base URL for svg/ directory
 * @param {string} name  — icon name (without .svg)
 * @returns {Promise<string>}
 */
async function fetchSVG(base, name) {
    if (_svgCache[name]) return _svgCache[name];
    const url = base + name + ".svg";
    try {
        const resp = await fetch(url);
        if (!resp.ok) return "";
        const raw = await resp.text();
        const inner = raw
            .replace(/<\?xml[^>]*\?>/g, "")
            .replace(/<!--[\s\S]*?-->/g, "")
            .trim();
        _svgCache[name] = inner;
        return inner;
    } catch (_) {
        return "";
    }
}

// ── Action → icon mapping ───────────────────────────────────────────────
const ACTION_ICON_MAP = {
    "ms.type":          "keyboard",
    "ms.press":         "keyboard",
    "ms.hold":          "keyboard",
    "ms.release":       "keyboard",
    "ms.wait":          "timer",
    "ms.copy":          "clipboard",
    "ms.paste":         "clipboard",
    "ms.cam":           "camera",
    "ms.cam.rebalance": "camera",
    "ms.cam.reset":     "camera",
    "ms.click":         "click",
    "ms.scroll":        "scroll",
    "ms.move":          "move",
    "ms.select":        "select",
    "ms.search":        "search",
    "ms.record":        "record",
    "ms.stop":          "stop",
    "ms.pause":         "pause",
    "ms.play":          "play",
    "ms.save":          "save",
    "ms.load":          "upload",
    "ms.alert":         "alert",
    "ms.refresh":       "refresh",
    "ms.pixelScan":     "pixelscan",
    "ms.window":        "window",
    "ms.input":         "inputs",
    "ms.variable":      "variable",
    "ms.watch":         "watcher",
    "if":               "branch",
    "for":              "loop",
    "while":            "repeat",
    "else":             "branch",
};

function iconForAction(action) {
    return ACTION_ICON_MAP[action] || "macros";
}

// ── Parameter summary ───────────────────────────────────────────────────

function paramSummary(action, params) {
    if (!params) return "";
    const keys = Object.keys(params);
    if (keys.length === 0) return "";
    if (action === "if" || action === "while") return params.condition || "";
    if (action === "for") {
        return (params.var || "i") + " = " + (params.from ?? 1) + " → " + (params.to ?? 1);
    }
    const parts = [];
    for (let i = 0; i < Math.min(keys.length, 2); i++) {
        const k = keys[i];
        let v = params[k];
        if (Array.isArray(v)) {
            if (v.length === 0) continue;
            v = v.join("+");
        }
        if (typeof v === "string" && v.length > 16) v = v.slice(0, 14) + "…";
        parts.push(k + ": " + v);
    }
    return parts.join(", ");
}

// ── Step ID generator ───────────────────────────────────────────────────
let _stepIdCounter = 0;
function nextStepId() {
    return "_step_" + (++_stepIdCounter) + "_" + Date.now().toString(36);
}

function deepClone(obj) {
    return JSON.parse(JSON.stringify(obj));
}

// ── CSS (injected once) ─────────────────────────────────────────────────
let _cssInjected = false;

function injectCSS() {
    if (_cssInjected) return;
    _cssInjected = true;
    const style = document.createElement("style");
    style.textContent = `
/* ── Step Canvas (ES module) ─────────────────────────────────────── */
.step-canvas {
    display: flex;
    flex-direction: column;
    gap: 2px;
    padding: 8px;
    min-height: 100%;
    overflow-y: auto;
    position: relative;
}

.step-canvas::-webkit-scrollbar { width: 4px; }
.step-canvas::-webkit-scrollbar-track { background: transparent; }
.step-canvas::-webkit-scrollbar-thumb { background: var(--border-dim); border-radius: 2px; }
.step-canvas::-webkit-scrollbar-thumb:hover { background: var(--border); }

.step-canvas-empty {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    color: var(--text3);
    font-size: 11px;
    padding: 40px 20px;
    text-align: center;
    gap: 6px;
    user-select: none;
}
.step-canvas-empty .step-canvas-empty-icon { font-size: 28px; opacity: 0.25; }

.step-block {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 5px 8px;
    background: var(--surface);
    border: 1px solid var(--border-dim);
    border-radius: var(--radius);
    cursor: default;
    transition: background 0.1s, border-color 0.15s, box-shadow 0.15s;
    position: relative;
    user-select: none;
    -webkit-user-select: none;
    min-height: 32px;
}
.step-block:hover { background: var(--surface2); border-color: var(--border); }
.step-block.selected {
    border-color: var(--accent);
    box-shadow: 0 0 0 1px var(--accent-glow-faint, rgba(196,26,26,0.12));
}

.step-block.drag-over-above::before {
    content: "";
    position: absolute;
    top: -3px;
    left: 4px;
    right: 4px;
    height: 2px;
    background: var(--accent);
    border-radius: 1px;
    z-index: 10;
}
.step-block.drag-over-below::after {
    content: "";
    position: absolute;
    bottom: -3px;
    left: 4px;
    right: 4px;
    height: 2px;
    background: var(--accent);
    border-radius: 1px;
    z-index: 10;
}
.step-block.drag-over-nest {
    border-color: var(--accent);
    background: var(--accent-glow-faint, rgba(196,26,26,0.12));
}
.step-block.dragging { opacity: 0.4; }

.step-drag-handle {
    width: 14px; height: 14px; flex-shrink: 0;
    display: flex; align-items: center; justify-content: center;
    cursor: grab; opacity: 0.35; transition: opacity 0.15s;
}
.step-drag-handle:hover { opacity: 0.8; }
.step-drag-handle:active { cursor: grabbing; }
.step-drag-handle svg { width: 14px; height: 14px; }
.step-drag-handle svg path, .step-drag-handle svg g { stroke: var(--text); fill: none; }

.step-icon {
    width: 16px; height: 16px; flex-shrink: 0;
    display: flex; align-items: center; justify-content: center;
}
.step-icon svg { width: 14px; height: 14px; }
.step-icon svg path, .step-icon svg g,
.step-icon svg circle, .step-icon svg rect { stroke: var(--accent); fill: none; }

.step-action-name {
    font-family: "SF Mono", "Menlo", "Consolas", monospace;
    font-size: 11px; color: var(--text); font-weight: 600;
    white-space: nowrap; flex-shrink: 0;
}
.step-params {
    font-family: "SF Mono", "Menlo", "Consolas", monospace;
    font-size: 10px; color: var(--text3);
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
    flex: 1; min-width: 0;
}

.step-actions {
    display: flex; align-items: center; gap: 2px;
    flex-shrink: 0; opacity: 0; transition: opacity 0.15s;
}
.step-block:hover .step-actions { opacity: 1; }

.step-action-btn {
    width: 18px; height: 18px;
    display: flex; align-items: center; justify-content: center;
    border-radius: var(--radius-s); cursor: pointer;
    opacity: 0.5; transition: opacity 0.1s, background 0.1s;
}
.step-action-btn:hover { opacity: 1; background: var(--hover); }
.step-action-btn svg { width: 12px; height: 12px; }
.step-action-btn svg path, .step-action-btn svg g { stroke: var(--text); fill: none; }
.step-action-btn.del:hover { background: var(--danger-bg); }
.step-action-btn.del:hover svg path { stroke: var(--danger); }

.step-block-container { display: flex; flex-direction: column; }

.step-nest-body {
    margin-left: 20px;
    border-left: 2px solid var(--border-dim);
    padding-left: 8px; padding-top: 2px; padding-bottom: 2px;
    display: flex; flex-direction: column; gap: 2px;
    min-height: 28px; position: relative;
}
.step-nest-body.drag-target {
    border-left-color: var(--accent);
    background: var(--accent-glow-faint, rgba(196,26,26,0.06));
    border-radius: var(--radius);
}
.step-nest-label {
    font-size: 9px; font-weight: 700;
    text-transform: uppercase; letter-spacing: 0.6px;
    color: var(--text3); padding: 2px 0 0;
}
.step-nest-body-empty {
    font-size: 10px; color: var(--text3);
    font-style: italic; padding: 4px 0; opacity: 0.6;
}

.step-nest-toggle {
    width: 14px; height: 14px; flex-shrink: 0;
    display: flex; align-items: center; justify-content: center;
    cursor: pointer; opacity: 0.5;
    transition: opacity 0.15s, transform 0.15s;
    font-size: 10px; color: var(--text);
}
.step-nest-toggle:hover { opacity: 1; }
.step-nest-toggle.collapsed { transform: rotate(-90deg); }
.step-nest-toggle svg { width: 12px; height: 12px; }
.step-nest-toggle svg path { stroke: var(--text); fill: none; }
.step-nest-body.collapsed { display: none; }
`;
    document.head.appendChild(style);
}

// ── StepCanvas class ────────────────────────────────────────────────────

/**
 * @param {HTMLElement} container — DOM element to render into
 * @param {Object} opts
 * @param {function} [opts.onChange] — called when steps change (receives serialized steps)
 * @param {string}   [opts.svgBase] — base URL for svg/ directory
 * @param {function} [opts.onSelect] — called when a step is selected (stepId, stepData)
 */
export class StepCanvas {
    constructor(container, opts = {}) {
        injectCSS();

        this._el = container;
        this._onChange = opts.onChange || (() => {});
        this._onSelect = opts.onSelect || (() => {});
        this._svgBase = opts.svgBase || "./svg/";

        // Internal storage
        this._steps = [];
        this._map = {};
        this._selId = null;
        this._dragId = null;

        // Build root
        this._root = document.createElement("div");
        this._root.className = "step-canvas";
        this._el.appendChild(this._root);

        this._renderEmpty();
        this._preloadIcons();
    }

    // ── Icon preloading ────────────────────────────────────────────────

    async _preloadIcons() {
        const needed = new Set(["drag", "close", "chevdown", "chevup", "trash", "edit", "macros"]);
        for (const action in ACTION_ICON_MAP) needed.add(ACTION_ICON_MAP[action]);
        for (const name of needed) await fetchSVG(this._svgBase, name);
    }

    // ── Step ID management ─────────────────────────────────────────────

    _assignIds(steps) {
        for (const step of steps) {
            if (!step._sid) step._sid = nextStepId();
            this._map[step._sid] = step;
            if (step.then) this._assignIds(step.then);
            if (step.else) this._assignIds(step.else);
            if (step.body) this._assignIds(step.body);
        }
    }

    // ── Load steps ─────────────────────────────────────────────────────

    load(steps) {
        this._steps = steps || [];
        this._map = {};
        this._assignIds(this._steps);
        this._selId = null;
        this._render();
    }

    // ── Add a step ─────────────────────────────────────────────────────

    addStep(stepDef, afterId) {
        const step = deepClone(stepDef);
        step._sid = nextStepId();
        this._map[step._sid] = step;

        if (afterId) {
            const idx = this._findIdx(this._steps, afterId);
            if (idx !== -1) this._steps.splice(idx + 1, 0, step);
            else this._steps.push(step);
        } else {
            this._steps.push(step);
        }
        this._render();
        this._fireChange();
    }

    // ── Remove a step ──────────────────────────────────────────────────

    removeStep(sid) {
        if (this._removeFrom(this._steps, sid)) {
            delete this._map[sid];
            if (this._selId === sid) this._selId = null;
            this._render();
            this._fireChange();
        }
    }

    _removeFrom(list, sid) {
        for (let i = 0; i < list.length; i++) {
            if (list[i]._sid === sid) { list.splice(i, 1); return true; }
            const s = list[i];
            if (s.then && this._removeFrom(s.then, sid)) return true;
            if (s.else && this._removeFrom(s.else, sid)) return true;
            if (s.body && this._removeFrom(s.body, sid)) return true;
        }
        return false;
    }

    _findIdx(list, sid) {
        for (let i = 0; i < list.length; i++) {
            if (list[i]._sid === sid) return i;
        }
        return -1;
    }

    // ── Move step ──────────────────────────────────────────────────────

    moveStep(dragId, targetId, pos) {
        const step = this._map[dragId];
        if (!step) return;
        this._removeFrom(this._steps, dragId);

        if (pos === "nest") {
            const tgt = this._map[targetId];
            if (tgt) {
                if (tgt.action === "if") {
                    if (!tgt.then) tgt.then = [];
                    tgt.then.push(step);
                } else {
                    if (!tgt.body) tgt.body = [];
                    tgt.body.push(step);
                }
            }
        } else {
            const ti = this._findIdx(this._steps, targetId);
            if (ti !== -1) {
                this._steps.splice(pos === "above" ? ti : ti + 1, 0, step);
            } else {
                this._steps.push(step);
            }
        }
        this._render();
        this._fireChange();
    }

    // ── Serialize ──────────────────────────────────────────────────────

    serialize() {
        return this._strip(deepClone(this._steps));
    }

    _strip(steps) {
        for (const step of steps) {
            delete step._sid;
            if (step.then) this._strip(step.then);
            if (step.else) this._strip(step.else);
            if (step.body) this._strip(step.body);
        }
        return steps;
    }

    // ── Update params ──────────────────────────────────────────────────

    updateStep(sid, newParams) {
        const step = this._map[sid];
        if (!step) return;
        Object.assign(step.params, newParams);
        this._render();
        this._fireChange();
    }

    // ── Selection ──────────────────────────────────────────────────────

    getSelectedId() { return this._selId; }
    getSelectedStep() { return this._selId ? this._map[this._selId] : null; }

    _selectStep(sid) {
        this._selId = sid;
        this._root.querySelectorAll(".step-block.selected").forEach(el => el.classList.remove("selected"));
        const el = this._root.querySelector(
            `[data-sid="${sid}"] > .step-block[data-sid="${sid}"], .step-block[data-sid="${sid}"]`
        );
        if (el) el.classList.add("selected");
        this._onSelect(sid, this._map[sid]);
    }

    // ── Fire change ────────────────────────────────────────────────────

    _fireChange() { this._onChange(this.serialize()); }

    // ── Render ─────────────────────────────────────────────────────────

    _render() {
        this._root.innerHTML = "";
        if (this._steps.length === 0) { this._renderEmpty(); return; }
        for (const step of this._steps) {
            this._root.appendChild(this._renderStep(step));
        }
    }

    _renderEmpty() {
        this._root.innerHTML = "";
        const d = document.createElement("div");
        d.className = "step-canvas-empty";
        d.innerHTML = '<span class="step-canvas-empty-icon">▶</span>'
            + 'No steps yet<br><span style="font-size:10px">Click <b>+ Add Step</b> to begin</span>';
        this._root.appendChild(d);
    }

    _isContainer(s) {
        return s.action === "if" || s.action === "for" || s.action === "while";
    }

    _renderStep(step) {
        return this._isContainer(step) ? this._renderContainer(step) : this._renderLeaf(step);
    }

    _renderLeaf(step) {
        const el = document.createElement("div");
        el.className = "step-block" + (step._sid === this._selId ? " selected" : "");
        el.setAttribute("data-sid", step._sid);
        el.setAttribute("draggable", "true");

        const handle = document.createElement("div");
        handle.className = "step-drag-handle";
        handle.innerHTML = _svgCache["drag"] || "⠿";
        el.appendChild(handle);

        const icon = document.createElement("div");
        icon.className = "step-icon";
        icon.innerHTML = _svgCache[iconForAction(step.action)] || "";
        el.appendChild(icon);

        const name = document.createElement("span");
        name.className = "step-action-name";
        name.textContent = step.action;
        el.appendChild(name);

        const params = document.createElement("span");
        params.className = "step-params";
        params.textContent = paramSummary(step.action, step.params);
        el.appendChild(params);

        const acts = document.createElement("div");
        acts.className = "step-actions";
        const del = document.createElement("div");
        del.className = "step-action-btn del";
        del.innerHTML = _svgCache["trash"] || "×";
        del.addEventListener("click", e => { e.stopPropagation(); this.removeStep(step._sid); });
        acts.appendChild(del);
        const editBtn = document.createElement("div");
        editBtn.className = "step-action-btn edit";
        editBtn.innerHTML = _svgCache["edit"] || "✎";
        editBtn.addEventListener("click", e => { e.stopPropagation(); this._selectStep(step._sid); });
        acts.appendChild(editBtn);
        el.appendChild(acts);

        el.addEventListener("click", e => {
            if (e.target.closest(".step-action-btn") || e.target.closest(".step-drag-handle")) return;
            this._selectStep(step._sid);
        });
        this._wireDrag(el, step);
        return el;
    }

    _renderContainer(step) {
        const wrap = document.createElement("div");
        wrap.className = "step-block-container";
        wrap.setAttribute("data-sid", step._sid);

        const header = document.createElement("div");
        header.className = "step-block" + (step._sid === this._selId ? " selected" : "");
        header.setAttribute("data-sid", step._sid);
        header.setAttribute("draggable", "true");

        const handle = document.createElement("div");
        handle.className = "step-drag-handle";
        handle.innerHTML = _svgCache["drag"] || "⠿";
        header.appendChild(handle);

        const toggle = document.createElement("div");
        toggle.className = "step-nest-toggle";
        toggle.innerHTML = _svgCache["chevdown"] || "▾";
        toggle.addEventListener("click", e => {
            e.stopPropagation();
            toggle.classList.toggle("collapsed");
            const body = wrap.querySelector(".step-nest-body");
            if (body) body.classList.toggle("collapsed");
        });
        header.appendChild(toggle);

        const icon = document.createElement("div");
        icon.className = "step-icon";
        icon.innerHTML = _svgCache[iconForAction(step.action)] || "";
        header.appendChild(icon);

        const name = document.createElement("span");
        name.className = "step-action-name";
        name.textContent = step.action;
        header.appendChild(name);

        const params = document.createElement("span");
        params.className = "step-params";
        params.textContent = paramSummary(step.action, step.params);
        header.appendChild(params);

        const acts = document.createElement("div");
        acts.className = "step-actions";
        const del = document.createElement("div");
        del.className = "step-action-btn del";
        del.innerHTML = _svgCache["trash"] || "×";
        del.addEventListener("click", e => { e.stopPropagation(); this.removeStep(step._sid); });
        acts.appendChild(del);
        const editBtn = document.createElement("div");
        editBtn.className = "step-action-btn edit";
        editBtn.innerHTML = _svgCache["edit"] || "✎";
        editBtn.addEventListener("click", e => { e.stopPropagation(); this._selectStep(step._sid); });
        acts.appendChild(editBtn);
        header.appendChild(acts);

        header.addEventListener("click", e => {
            if (e.target.closest(".step-action-btn") || e.target.closest(".step-drag-handle") || e.target.closest(".step-nest-toggle")) return;
            this._selectStep(step._sid);
        });
        this._wireDrag(header, step);
        wrap.appendChild(header);

        if (step.action === "if") {
            const tl = document.createElement("div");
            tl.className = "step-nest-label"; tl.textContent = "then";
            wrap.appendChild(tl);
            wrap.appendChild(this._renderNest(step.then || [], "then", step));

            const el2 = document.createElement("div");
            el2.className = "step-nest-label"; el2.textContent = "else";
            wrap.appendChild(el2);
            wrap.appendChild(this._renderNest(step.else || [], "else", step));
        } else {
            wrap.appendChild(this._renderNest(step.body || [], "body", step));
        }
        return wrap;
    }

    _renderNest(steps, branch, parent) {
        const body = document.createElement("div");
        body.className = "step-nest-body";
        body.setAttribute("data-nest-parent", parent._sid);
        body.setAttribute("data-nest-branch", branch);

        if (steps.length === 0) {
            const empty = document.createElement("div");
            empty.className = "step-nest-body-empty";
            empty.textContent = "empty";
            body.appendChild(empty);
        } else {
            for (const child of steps) body.appendChild(this._renderStep(child));
        }

        body.addEventListener("dragover", e => {
            if (!this._dragId) return;
            e.preventDefault(); e.stopPropagation();
            e.dataTransfer.dropEffect = "move";
            body.classList.add("drag-target");
        });
        body.addEventListener("dragleave", () => body.classList.remove("drag-target"));
        body.addEventListener("drop", e => {
            e.preventDefault(); e.stopPropagation();
            if (!this._dragId) return;
            const step = this._map[this._dragId];
            if (!step) return;
            this._removeFrom(this._steps, this._dragId);
            if (branch === "then") { if (!parent.then) parent.then = []; parent.then.push(step); }
            else if (branch === "else") { if (!parent.else) parent.else = []; parent.else.push(step); }
            else { if (!parent.body) parent.body = []; parent.body.push(step); }
            body.classList.remove("drag-target");
            this._dragId = null;
            this._render();
            this._fireChange();
        });
        return body;
    }

    // ── Drag and drop ──────────────────────────────────────────────────

    _isDesc(pid, cid) {
        const p = this._map[pid];
        if (!p) return false;
        const ch = [].concat(p.then || [], p.else || [], p.body || []);
        for (const c of ch) {
            if (c._sid === cid) return true;
            if (this._isDesc(c._sid, cid)) return true;
        }
        return false;
    }

    _wireDrag(el, step) {
        el.addEventListener("dragstart", e => {
            this._dragId = step._sid;
            el.classList.add("dragging");
            e.dataTransfer.effectAllowed = "move";
            e.dataTransfer.setData("text/plain", step._sid);
            const ghost = el.cloneNode(true);
            ghost.style.width = el.offsetWidth + "px";
            ghost.style.opacity = "0.7";
            ghost.style.position = "absolute";
            ghost.style.top = "-1000px";
            document.body.appendChild(ghost);
            e.dataTransfer.setDragImage(ghost, 10, 10);
            requestAnimationFrame(() => ghost.remove());
        });

        el.addEventListener("dragend", () => {
            this._dragId = null;
            el.classList.remove("dragging");
            this._clearDrops();
        });

        el.addEventListener("dragover", e => {
            if (!this._dragId || this._dragId === step._sid) return;
            e.preventDefault();
            e.dataTransfer.dropEffect = "move";
            const rect = el.getBoundingClientRect();
            const y = e.clientY - rect.top;
            const h = rect.height;
            const isC = this._isContainer(step);
            el.classList.remove("drag-over-above", "drag-over-below", "drag-over-nest");
            if (isC && y > h * 0.3 && y < h * 0.7) el.classList.add("drag-over-nest");
            else if (y < h / 2) el.classList.add("drag-over-above");
            else el.classList.add("drag-over-below");
        });

        el.addEventListener("dragleave", () => {
            el.classList.remove("drag-over-above", "drag-over-below", "drag-over-nest");
        });

        el.addEventListener("drop", e => {
            e.preventDefault();
            e.stopPropagation();
            if (!this._dragId || this._dragId === step._sid) return;
            const rect = el.getBoundingClientRect();
            const y = e.clientY - rect.top;
            const h = rect.height;
            const isC = this._isContainer(step);
            let pos;
            if (isC && y > h * 0.3 && y < h * 0.7) pos = "nest";
            else if (y < h / 2) pos = "above";
            else pos = "below";
            if (pos === "nest" && this._isDesc(step._sid, this._dragId)) { this._clearDrops(); return; }
            this.moveStep(this._dragId, step._sid, pos);
            this._clearDrops();
        });
    }

    _clearDrops() {
        this._root.querySelectorAll(".drag-over-above,.drag-over-below,.drag-over-nest").forEach(el => {
            el.classList.remove("drag-over-above", "drag-over-below", "drag-over-nest");
        });
        this._root.querySelectorAll(".drag-target").forEach(el => el.classList.remove("drag-target"));
    }

    // ── Destroy ────────────────────────────────────────────────────────

    destroy() {
        this._root.innerHTML = "";
        this._steps = [];
        this._map = {};
    }
}

// ── Expose on window for IIFE contexts ──────────────────────────────────
if (typeof window !== "undefined") {
    window.StepCanvas = StepCanvas;
}
