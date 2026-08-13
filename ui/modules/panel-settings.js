    /* panel: settings */
    (function() {
    "use strict";
// ── State ──────────────────────────────────────────────────────────
            let S = {};
            let _modalResolve = null;
            let _toastTimer = null;
            let _ctxTarget = null; // { macro: m } — what was right-clicked

            // ── Context menu ───────────────────────────────────────────────────
            function closeCtxMenu() {
                const el = document.getElementById("ctx-menu-settings");
                if (el) el.classList.remove("open");
                _ctxTarget = null;
            }

            function showCtxMenu(x, y, items, title) {
                const el = document.getElementById("ctx-menu-settings");
                if (!el) return;
                el.innerHTML = "";
                if (title) {
                    const hdr = document.createElement("div");
                    hdr.className = "ctx-header";
                    hdr.textContent = title;
                    el.appendChild(hdr);
                }
                for (const item of items) {
                    if (item === "divider") {
                        const d = document.createElement("div");
                        d.className = "ctx-divider";
                        el.appendChild(d);
                        continue;
                    }
                    const row = document.createElement("div");
                    row.className = "ctx-item" + (item.danger ? " danger" : "");
                    if (item.icon) {
                        const ico = document.createElement("span");
                        ico.className = "ctx-icon";
                        ico.textContent = item.icon;
                        row.appendChild(ico);
                    }
                    const lbl = document.createElement("span");
                    lbl.textContent = item.label;
                    row.appendChild(lbl);
                    row.addEventListener("mouseenter", () => playSlot("hover"));
                    row.addEventListener("click", (e) => {
                        e.stopPropagation();
                        playSlot("interact");
                        closeCtxMenu();
                        item.action();
                    });
                    el.appendChild(row);
                }

                // Keep the menu fully visible: clamp horizontally, flip up when
                // there's more room above, and cap the height so a tall menu scrolls
                // internally rather than spilling past the window border.
                el.classList.add("open");
                el.style.maxHeight = "";
                const MARGIN = 6;
                const vw = window.innerWidth, vh = window.innerHeight;
                const mw = el.offsetWidth || 160;
                const naturalH = el.scrollHeight;
                const left = Math.max(MARGIN, Math.min(x, vw - mw - MARGIN));
                const spaceBelow = vh - y - MARGIN, spaceAbove = y - MARGIN;
                let top, maxH;
                if (naturalH <= spaceBelow)      { top = y;            maxH = spaceBelow; }
                else if (naturalH <= spaceAbove) { top = y - naturalH; maxH = spaceAbove; }
                else if (spaceBelow >= spaceAbove) { top = y;          maxH = spaceBelow; }
                else                             { top = MARGIN;        maxH = spaceAbove; }
                top = Math.max(MARGIN, top);
                el.style.left = left + "px";
                el.style.top = top + "px";
                el.style.maxHeight = maxH + "px";
            }

            // Close ctx menu on any left-click or Escape. preventDefault on
            // contextmenu suppresses the native WebKit menu everywhere.
            document.addEventListener("click", () => closeCtxMenu());
            const _settingsPanel = document.querySelector('.panel-settings');
            document.addEventListener("contextmenu", (e) => {
                if (!_settingsPanel || getComputedStyle(_settingsPanel).display === "none") return;
                e.preventDefault();
                closeCtxMenu();
            });
            document.addEventListener("keydown", (e) => {
                if (!_settingsPanel || getComputedStyle(_settingsPanel).display === "none") return;
                if (e.key === "Escape") closeCtxMenu();
            });

            // ── Bridge ─────────────────────────────────────────────────────────
            function sendToHost(msg) {
                const s = typeof msg === "string" ? msg : JSON.stringify(msg);
                if (window.shellPost) {
                    // Running inside the Macro Lab shell — route through msShell channel
                    const data = typeof msg === "string" ? JSON.parse(msg) : msg;
                    window.shellPost("settings", data.action || "unknown", data);
                } else if (window.chrome?.webview) {
                    window.chrome.webview.postMessage(s);
                } else {
                    window.webkit.messageHandlers.ms.postMessage(s);
                }
            }

            // ── Shell integration ─────────────────────────────────────────────
            // When loaded inside the shell, register as a panel so shellDispatch
            // can route incoming Lua pushes (state, theme) to receiveState().
            if (window.registerPanel) {
                window.registerPanel("settings", function(action, body) {
                    if (action === "state" && body) {
                        receiveState(body);
                    } else if (action === "theme" && body) {
                        applyTheme(body);
                    }
                });
            }

            // ── Window drag ────────────────────────────────────────────────────
            // borderless windows ignore -webkit-app-region (isMovable=false by default)
            // so we implement drag manually via the Lua moveWindow action.
            let _dragging = false; // script-level so playSlot can read it
            (function () {
                let _drag = null;
                document
                    .getElementById("header")
                    .addEventListener("mousedown", (e) => {
                        if (
                            e.target.closest(
                                ".header-btns, button, input, select",
                            )
                        )
                            return;
                        _drag = { ox: e.screenX, oy: e.screenY };
                        _dragging = true;
                        const onMove = (ev) => {
                            if (!_drag) return;
                            sendToHost({
                                action: "moveWindow",
                                dx: ev.screenX - _drag.ox,
                                dy: ev.screenY - _drag.oy,
                            });
                            _drag.ox = ev.screenX;
                            _drag.oy = ev.screenY;
                        };
                        const onUp = () => {
                            _drag = null;
                            _dragging = false;
                            window.removeEventListener("mousemove", onMove);
                            window.removeEventListener("mouseup", onUp);
                        };
                        window.addEventListener("mousemove", onMove);
                        window.addEventListener("mouseup", onUp);
                    });
            })();

            // ── Sound ──────────────────────────────────────────────────────────
            const _lastSlot = {};
            function playSlot(slot) {
                if (_dragging) return; // window is being dragged; skip hover sounds
                if (slot === "hover" && !document.hasFocus()) return;
                const now = Date.now();
                if (now - (_lastSlot[slot] || 0) < 50) return;
                _lastSlot[slot] = now;
                sendToHost({ action: "playSlot", slot });
            }

            // ── Toast ──────────────────────────────────────────────────────────
            function showAlert(msg, duration) {
                const el = document.getElementById("toast");
                el.textContent = msg;
                el.classList.add("visible");
                clearTimeout(_toastTimer);
                _toastTimer = setTimeout(
                    () => el.classList.remove("visible"),
                    duration || 3000,
                );
            }

            function hideToast() {
                const el = document.getElementById("toast");
                el.classList.remove("visible");
                clearTimeout(_toastTimer);
                _toastTimer = null;
            }

            // ── Modal ──────────────────────────────────────────────────────────
            function openModal(
                title,
                msg,
                confirmLabel = "OK",
                cancelLabel = "Cancel",
                withInput = false,
                defaultVal = "",
            ) {
                return new Promise((resolve) => {
                    _modalResolve = resolve;
                    document.getElementById("modal-title").textContent = title;
                    document.getElementById("modal-msg").textContent = msg;
                    const inp = document.getElementById("modal-input");
                    if (withInput) {
                        inp.classList.add("show");
                        inp.value = defaultVal;
                        setTimeout(() => inp.focus(), 100);
                    } else {
                        inp.classList.remove("show");
                    }
                    // A previous live-capture modal may have hidden a button
                    // (see updateLuaModal). Restore both to visible on every
                    // fresh open so a plain confirm modal isn't missing a button.
                    document.getElementById("modal-confirm").style.display = "";
                    document.getElementById("modal-cancel").style.display = "";
                    // The detected-key strip is rebind-only; keep it out of
                    // plain modals until a keys[] payload turns it on.
                    const keysBox = document.getElementById("modal-keys");
                    keysBox.innerHTML = "";
                    keysBox.style.display = "none";
                    document.getElementById("modal-confirm").textContent =
                        confirmLabel;
                    document.getElementById("modal-cancel").textContent =
                        cancelLabel;
                    document
                        .getElementById("modal-overlay")
                        .classList.add("open");
                });
            }
            function closeModal(confirmed) {
                const val = document.getElementById("modal-input").value;
                document
                    .getElementById("modal-overlay")
                    .classList.remove("open");
                if (_modalResolve) {
                    _modalResolve({ confirmed, value: val });
                    _modalResolve = null;
                }
            }
            window.openModal = openModal;
            window.closeModal = closeModal;

            // Called by Lua via evaluateJavaScript to show a modal and report the
            // result back through the 'modalResult' action. Always displayed above
            // all panel content via the existing z-index: 400 modal overlay.
            function openLuaModal(d) {
                openModal(
                    d.title || "",
                    d.msg || "",
                    d.confirm || "OK",
                    d.cancel || "Cancel",
                    !!d.hasInput,
                    d.inputDefault || "",
                ).then((r) => {
                    sendToHost({
                        action: "modalResult",
                        confirmed: r.confirmed,
                        value: r.value || "",
                    });
                });
            }
            // Lua calls this via ms.shell.eval, which runs at global scope, so
            // the IIFE-local declaration has to be published to window — same as
            // openModal/closeModal above. Without it the confirm modal never
            // opens (ReferenceError), so rebinds capture but never save.
            window.openLuaModal = openLuaModal;

            // Mutate the already-open modal in place without opening a new one
            // or resolving the pending promise. The rebind flow uses this to
            // drive a single modal through two phases — a live "capturing" phase
            // that streams the keys being held, then a "confirm" phase — so the
            // one prompt both informs the user and shows the detected bind,
            // replacing the old floating alert toast. Any field may be omitted
            // to leave it untouched; showConfirm/showCancel toggle each button
            // (the confirm button is hidden while capturing, since a click in
            // that phase would itself register as a mouse bind).
            function updateLuaModal(d) {
                if (d.title !== undefined)
                    document.getElementById("modal-title").textContent = d.title;
                if (d.msg !== undefined)
                    document.getElementById("modal-msg").textContent = d.msg;
                if (d.confirm !== undefined)
                    document.getElementById("modal-confirm").textContent =
                        d.confirm;
                if (d.cancel !== undefined)
                    document.getElementById("modal-cancel").textContent =
                        d.cancel;
                if (d.showConfirm !== undefined)
                    document.getElementById("modal-confirm").style.display =
                        d.showConfirm ? "" : "none";
                if (d.showCancel !== undefined)
                    document.getElementById("modal-cancel").style.display =
                        d.showCancel ? "" : "none";
                // keys: render the detected combo as spotlighted key caps. An
                // array (even empty) shows the strip — empty renders a dim "…"
                // placeholder so the user can see where their keys will land
                // before pressing anything. Omit the field to leave it as is;
                // openModal hides the strip for ordinary (non-rebind) modals.
                // hs.json encodes an empty Lua table as {}, not [], so anything
                // that isn't a real array is treated as the empty/placeholder case.
                if (d.keys !== undefined) {
                    const box = document.getElementById("modal-keys");
                    box.innerHTML = "";
                    box.style.display = "flex";
                    const arr = Array.isArray(d.keys) ? d.keys : [];
                    if (arr.length === 0) {
                        const ph = document.createElement("kbd");
                        ph.className = "modal-key placeholder";
                        ph.textContent = "…";
                        box.appendChild(ph);
                    } else {
                        arr.forEach((k, i) => {
                            if (i > 0) {
                                const plus = document.createElement("span");
                                plus.className = "modal-key-plus";
                                plus.textContent = "+";
                                box.appendChild(plus);
                            }
                            const cap = document.createElement("kbd");
                            cap.className = "modal-key";
                            cap.textContent = k;
                            box.appendChild(cap);
                        });
                    }
                }
            }
            window.updateLuaModal = updateLuaModal;

            document
                .getElementById("modal-overlay")
                .addEventListener("click", (e) => {
                    if (e.target === e.currentTarget) closeModal(false);
                });
            // Global Enter/Escape for all modals (including confirm-only where
            // the input field is hidden and its own keydown handler won't fire).
            document.addEventListener("keydown", (e) => {
                const overlay = document.getElementById("modal-overlay");
                if (!overlay || !overlay.classList.contains("open")) return;
                if (e.key === "Enter") {
                    // Don't double-fire if focus is on the input (its own handler runs).
                    if (document.activeElement === document.getElementById("modal-input")) return;
                    e.preventDefault();
                    playSlot("interact");
                    closeModal(true);
                }
                if (e.key === "Escape") {
                    e.preventDefault();
                    playSlot("back");
                    closeModal(false);
                }
            });
            document
                .getElementById("modal-input")
                .addEventListener("keydown", (e) => {
                    if (e.key === "Enter") {
                        playSlot("interact");
                        closeModal(true);
                    }
                    if (e.key === "Escape") {
                        playSlot("back");
                        closeModal(false);
                    }
                });

            // ── Shutdown ───────────────────────────────────────────────────────
            // The power button is the only destructive control in the title
            // bar, so it confirms first. Once confirmed the panel's job is
            // over: it hands off to the host and goes quiet.
            //
            // Deliberately no curtain and no send-off sound here. Both used to
            // live in this page, and both were wrong for the same reason —
            // this window is what the host's teardown closes, so the curtain
            // went dark while the sample was still playing, leaving the
            // desktop on screen for the rest of the send-off. The host puts up
            // a full-screen curtain that outlives this window, and starts the
            // sound itself so the legacy UI's power button gets one too.
            let _shuttingDown = false;

            async function requestShutdown() {
                if (_shuttingDown) return;
                playSlot("interact");
                const r = await openModal(
                    "Quit mudscript",
                    "Stop all macros and quit mudscript?\n\nThis quits Hammerspoon — mudscript runs inside it, so there is no way to leave one without the other.",
                    "Quit",
                );
                if (!r.confirmed) return;
                beginShutdown();
            }
            window.requestShutdown = requestShutdown;

            function beginShutdown() {
                _shuttingDown = true;
                sendToHost({ action: "shutdown" });
            }

            // ── Helpers ────────────────────────────────────────────────────────
            function h(tag, attrs = {}, ...children) {
                const el = document.createElement(tag);
                for (const [k, v] of Object.entries(attrs)) {
                    if (k === "cls") el.className = v;
                    else if (k.startsWith("on"))
                        el.addEventListener(k.slice(2), v);
                    else el.setAttribute(k, v);
                }
                for (const c of children) {
                    if (c == null) continue;
                    el.appendChild(
                        typeof c === "string" ? document.createTextNode(c) : c,
                    );
                }
                return el;
            }

            function toggle(checked, onchange) {
                const label = h(
                    "label",
                    { cls: "toggle", onmouseenter: () => playSlot("hover") },
                    h("input", {
                        type: "checkbox",
                        // The shell owns the toggle sound for every toggle; host
                        // handlers must not play one or they double up. Sounding
                        // after onchange keeps the mute toggles honest — the host
                        // processes messages in order, so muting silences its own
                        // click and unmuting is audible.
                        onchange: (e) => {
                            const on = e.target.checked;
                            try { if (onchange) onchange(e); }
                            finally { playSlot(on ? "toggleOn" : "toggleOff"); }
                        },
                    }),
                    h("div", { cls: "toggle-track" }),
                    h("div", { cls: "toggle-thumb" }),
                );
                label.querySelector("input").checked = checked;
                return label;
            }

            function seg(options, active, onselect) {
                const wrap = h("div", { cls: "seg" });
                for (const o of options) {
                    const btn = h(
                        "button",
                        {
                            cls:
                                "seg-btn" +
                                (o.value === active ? " active" : ""),
                            onmouseenter: () => playSlot("hover"),
                            onclick: () => {
                                playSlot("interact");
                                // Move the highlight ourselves: some callers
                                // (the Type picker) never rebuild this control,
                                // so relying on a re-render to reflect the
                                // selection left the active class stuck on the
                                // initial option.
                                for (const b of wrap.children)
                                    b.classList.remove("active");
                                btn.classList.add("active");
                                onselect(o.value);
                            },
                        },
                        o.label,
                    );
                    wrap.appendChild(btn);
                }
                return wrap;
            }

            // A settings group: a sticky heading and its rows, always open.
            // Groups used to collapse because settings was one narrow panel
            // sharing space with everything else; it has its own window and a
            // nav rail now, so a chevron only hides content for no gain.
            // `desc` is an optional one-line explanation of the group.
            function section(id, title, buildFn, desc) {
                const head = h(
                    "div",
                    { cls: "section-head" },
                    h("span", { cls: "section-title" }, title),
                    desc ? h("span", { cls: "section-desc" }, desc) : null,
                );
                const body = h("div", { cls: "section-body" });
                buildFn(body);
                const wrap = h("div", { cls: "section" });
                wrap.setAttribute("data-section", id);
                wrap.appendChild(head);
                wrap.appendChild(body);
                return wrap;
            }

            function row(
                label,
                sublabel,
                control,
                extra = "",
                ctxItems = null,
            ) {
                const r = h("div", {
                    cls: "row " + extra,
                    onmouseenter: () => playSlot("hover"),
                });
                const lbl = h("div", { cls: "row-label" }, label);
                if (sublabel) lbl.appendChild(h("small", {}, sublabel));
                r.appendChild(lbl);
                if (control) r.appendChild(control);
                r.addEventListener("contextmenu", (e) => {
                    e.preventDefault();
                    e.stopImmediatePropagation();
                    if (ctxItems && ctxItems.length > 0) {
                        playSlot("interact");
                        showCtxMenu(e.clientX, e.clientY, ctxItems, label);
                    }
                });
                return r;
            }

            function btnRow(...buttons) {
                const wrap = h("div", { cls: "btn-row" });
                for (const b of buttons) wrap.appendChild(b);
                return wrap;
            }

            function actionBtn(label, cls, action) {
                return h(
                    "button",
                    {
                        cls: "btn-action " + (cls || ""),
                        onmouseenter: () => playSlot("hover"),
                        onclick: () => {
                            playSlot("interact");
                            action();
                        },
                    },
                    label,
                );
            }

            function divider() {
                return h("div", { cls: "divider" });
            }
            function groupLabel(txt) {
                return h("div", { cls: "group-label" }, txt);
            }

            // The row/toggle/section vocabulary is the settings panel's, but it
            // is what every settings-shaped surface in the shell is built from.
            // Panels split out of here (panel-theme.js, and the library and
            // trust tabs to come) build with the same kit rather than growing a
            // second, drifting copy of it.
            window.msUI = {
                h, toggle, seg, section, row, btnRow, actionBtn, divider,
                groupLabel, showCtxMenu,
            };

            // ── Sections ───────────────────────────────────────────────────────


            // ── Reusable slider row builder ────────────────────────────────────────
            // Builds a complete slider row element and returns it.
            // label (string), hint (string|null), min/max/step (number),
            // unit (string|null), val (number), onChange(v), ctxItems (array|null)
            function buildSlider(
                label,
                hint,
                min,
                max,
                step,
                unit,
                val,
                onChange,
                ctxItems,
            ) {
                const wrap = h("div", {
                    cls: "row slider-row",
                    onmouseenter: () => playSlot("hover"),
                });
                if (ctxItems && ctxItems.length) {
                    wrap.addEventListener("contextmenu", (e) => {
                        e.preventDefault();
                        e.stopImmediatePropagation();
                        playSlot("interact");
                        showCtxMenu(e.clientX, e.clientY, ctxItems, label);
                    });
                }
                const top = h("div", { cls: "slider-top" });
                const lbl = h("div", { cls: "row-label" }, label);
                if (hint) lbl.appendChild(h("small", {}, hint));
                top.appendChild(lbl);
                const numInput = h("input", {
                    type: "number",
                    step: String(step || 1),
                    min: String(min),
                    max: String(max),
                });
                numInput.value = val;
                const valDiv = h("div", { cls: "slider-val" });
                valDiv.appendChild(numInput);
                if (unit) {
                    const uSpan = document.createElement("span");
                    uSpan.textContent = unit;
                    uSpan.style.cssText =
                        "font-size:11px;opacity:0.55;margin-left:3px;";
                    valDiv.appendChild(uSpan);
                }
                top.appendChild(valDiv);
                wrap.appendChild(top);
                const slider = h("input", {
                    type: "range",
                    min: String(min),
                    max: String(max),
                    step: String(step || 1),
                });
                slider.value = val;
                const decimals = step && step < 1 ? 2 : 0;
                slider.addEventListener("input", () => {
                    numInput.value = parseFloat(slider.value).toFixed(decimals);
                });
                slider.addEventListener("change", () =>
                    onChange(parseFloat(slider.value)),
                );
                numInput.addEventListener("change", () => {
                    const v = Math.max(
                        min,
                        Math.min(max, parseFloat(numInput.value) || min),
                    );
                    slider.value = v;
                    onChange(v);
                });
                wrap.appendChild(slider);
                return wrap;
            }

            // ── buildRuntime — macro engine + reload ───────────────────────────
            // The macros switch and the reload menu used to live in the title
            // bar as compact ghost buttons, back when the title bar was the
            // only chrome settings had. They are settings, so they read as
            // settings rows now; the title bar keeps only window controls.
            function buildRuntime(body) {
                body.appendChild(
                    row(
                        "Macros",
                        "Master switch for the macro engine",
                        toggle(S.macrosEnabled ?? false, (e) =>
                            sendToHost({
                                action: "setMacros",
                                value: e.target.checked ? 1 : 0,
                            }),
                        ),
                    ),
                );

                body.appendChild(divider());
                body.appendChild(groupLabel("Reload"));
                body.appendChild(
                    h("div", { cls: "group-hint" },
                        "Pick what a reload rebuilds. Anything left off keeps "
                        + "its current state."),
                );

                // Which subsystems the Reload button rebuilds. Same qrOptions
                // the old dropdown's checkboxes wrote to. Four short labels
                // sharing one explanation, rather than four rows each
                // restating what its own name already says.
                const qr = S.qrOptions || {};
                const targets = [
                    ["macros", "Macro pack"],
                    ["theme", "Theme and sounds"],
                    ["settings", "Settings file"],
                    ["ui", "Shell windows"],
                ];
                for (const [key, label] of targets) {
                    body.appendChild(
                        row(
                            label,
                            null,
                            toggle(qr[key] !== false, (e) =>
                                sendToHost({
                                    action: "setQROption",
                                    key: key,
                                    value: e.target.checked,
                                }),
                            ),
                            "row-sub row-compact",
                        ),
                    );
                }

                body.appendChild(
                    btnRow(
                        actionBtn("Reload Selected", "accent", () => {
                            const q = S.qrOptions || {};
                            const acts = {
                                macros: "reloadMacros",
                                theme: "reloadTheme",
                                settings: "reloadSettings",
                                ui: "reloadUI",
                            };
                            let sent = false;
                            for (const [key, action] of Object.entries(acts)) {
                                if (q[key] !== false) {
                                    sendToHost({ action: action });
                                    sent = true;
                                }
                            }
                            if (!sent) showAlert("Nothing selected to reload.");
                        }),
                        actionBtn("Reload All", "", async () => {
                            const r = await openModal(
                                "Reload All",
                                "Restart Hammerspoon and reload mudscript from disk?",
                                "Reload",
                            );
                            if (r.confirmed) sendToHost({ action: "reloadAll" });
                        }),
                    ),
                );
            }

            // ── buildAccessibility — input and motion settings ─────────────────────
            function buildAccessibility(body) {
                const hidden = S.hiddenFeatures || {};
                const hasTrackpad = !hidden.trackpad;
                const hasSocd = !hidden.socd;

                // Trackpad Mode
                if (hasTrackpad) {
                    body.appendChild(
                        row(
                            "Trackpad / Pen Mode",
                            null,
                            toggle(S.trackpadMode ?? false, (e) =>
                                sendToHost({
                                    action: "setTrackpadMode",
                                    value: e.target.checked,
                                }),
                            ),
                            "",
                            [
                                {
                                    icon: "",
                                    label: "Reset to default",
                                    action: () =>
                                        sendToHost({
                                            action: "resetSetting",
                                            key: "trackpadMode",
                                        }),
                                },
                            ],
                        ),
                    );
                }

                // SOCD
                if (hasSocd) {
                    if (hasTrackpad) body.appendChild(divider());
                    body.appendChild(
                        row(
                            "SOCD Cleaning",
                            null,
                            toggle(S.socdEnabled ?? false, (e) =>
                                sendToHost({
                                    action: "setSocdEnabled",
                                    value: e.target.checked,
                                }),
                            ),
                            "",
                            [
                                {
                                    icon: "",
                                    label: "Reset to default",
                                    action: () =>
                                        sendToHost({
                                            action: "resetSetting",
                                            key: "socdEnabled",
                                        }),
                                },
                            ],
                        ),
                    );
                    if (S.socdEnabled) {
                        body.appendChild(
                            row(
                                "SOCD Mode",
                                null,
                                seg(
                                    [
                                        {
                                            label: "Last Wins",
                                            value: "lastWins",
                                        },
                                        { label: "Neutral", value: "neutral" },
                                        {
                                            label: "First Wins",
                                            value: "firstWins",
                                        },
                                    ],
                                    S.socdMode ?? "lastWins",
                                    (v) =>
                                        sendToHost({
                                            action: "setSocdMode",
                                            value: v,
                                        }),
                                ),
                                "row-sub",
                                [
                                    {
                                        icon: "",
                                        label: "Reset to default",
                                        action: () =>
                                            sendToHost({
                                                action: "resetSetting",
                                                key: "socdMode",
                                            }),
                                    },
                                ],
                            ),
                        );
                    }
                }

                // Octane Mode
                if (hasTrackpad || hasSocd) body.appendChild(divider());
                const octane = S.octaneMode === true;
                body.appendChild(
                    row(
                        "Octane Mode",
                        "Low-overhead mode: disables logging, animations, pollers, and sounds while macros run as normal",
                        toggle(octane, (e) => {
                            sendToHost({
                                action: "setOctaneMode",
                                value: e.target.checked,
                            });
                        }),
                    ),
                );

                // Octane sound mute sub-toggle
                const octaneMute = S.octaneMuteSounds === true;
                body.appendChild(
                    row(
                        "Octane: mute sounds",
                        "Silence all UI sounds when Octane Mode is active",
                        toggle(octaneMute, (e) => {
                            sendToHost({
                                action: "setOctaneMuteSounds",
                                value: e.target.checked,
                            });
                        }),
                    ),
                );
            }

            // ── renderUserItem — shared renderer for user-defined items ─────────────
            // Used by both buildSettings (Settings section) and buildUserSection.
            function renderUserItem(body, item) {
                if (item.type === "divider") {
                    body.appendChild(divider());
                } else if (item.type === "groupLabel") {
                    body.appendChild(groupLabel(item.label || ""));
                } else if (item.type === "toggle") {
                    const ctxItems =
                        item.default !== undefined
                            ? [
                                  {
                                      icon: "",
                                      label: "Reset to default",
                                      action: () =>
                                          sendToHost({
                                              action: "resetUserSetting",
                                              key: item.key,
                                          }),
                                  },
                              ]
                            : null;
                    body.appendChild(
                        row(
                            item.label || item.key,
                            item.hint || null,
                            toggle(item.value ?? false, (e) =>
                                sendToHost({
                                    action: "userSettingChange",
                                    key: item.key,
                                    value: e.target.checked,
                                }),
                            ),
                            "",
                            ctxItems,
                        ),
                    );
                } else if (item.type === "slider") {
                    const ctxItems =
                        item.default !== undefined
                            ? [
                                  {
                                      icon: "",
                                      label: "Reset to default",
                                      action: () =>
                                          sendToHost({
                                              action: "resetUserSetting",
                                              key: item.key,
                                          }),
                                  },
                              ]
                            : null;
                    body.appendChild(
                        buildSlider(
                            item.label || item.key,
                            item.hint || null,
                            item.min ?? 0,
                            item.max ?? 100,
                            item.step ?? 1,
                            item.unit || null,
                            item.value ?? item.default ?? 0,
                            (v) =>
                                sendToHost({
                                    action: "userSettingChange",
                                    key: item.key,
                                    value: v,
                                }),
                            ctxItems,
                        ),
                    );
                } else if (item.type === "seg") {
                    const ctxItems =
                        item.default !== undefined
                            ? [
                                  {
                                      icon: "",
                                      label: "Reset to default",
                                      action: () =>
                                          sendToHost({
                                              action: "resetUserSetting",
                                              key: item.key,
                                          }),
                                  },
                              ]
                            : null;
                    body.appendChild(
                        row(
                            item.label || item.key,
                            item.hint || null,
                            seg(
                                item.options || [],
                                item.value ?? item.default,
                                (v) =>
                                    sendToHost({
                                        action: "userSettingChange",
                                        key: item.key,
                                        value: v,
                                    }),
                            ),
                            "",
                            ctxItems,
                        ),
                    );
                } else if (item.type === "action") {
                    const btn = actionBtn(
                        item.btnLabel || "Run",
                        item.danger ? "danger" : "",
                        () =>
                            sendToHost({
                                action: "userSettingAction",
                                key: item.key,
                            }),
                    );
                    if (item.label) {
                        body.appendChild(
                            row(item.label, item.hint || null, btn, "", null),
                        );
                    } else {
                        body.appendChild(btnRow(btn));
                    }
                } else if (item.type === "group") {
                    // Collapsible group containing nested settings items.
                    const det = document.createElement("details");
                    det.className = "user-group";
                    det.open = item.open !== false;
                    const sum = document.createElement("summary");
                    sum.className = "user-group-summary";
                    const arrow = document.createElement("span");
                    arrow.className = "user-group-arrow";
                    arrow.textContent = "\u25b8";
                    sum.appendChild(arrow);
                    sum.appendChild(
                        document.createTextNode(
                            "\u00a0" + (item.label || "Group"),
                        ),
                    );
                    det.appendChild(sum);
                    for (const child of item.items || []) {
                        renderUserItem(det, child);
                    }
                    body.appendChild(det);
                }
            }

            // ── buildDefaults — save / restore the whole settings file ─────────
            // These act on every setting, app-level and pack-defined alike —
            // not just the user-defined ones — so they live in the Settings
            // panel, not in Tools with the pack's own controls.
            function buildDefaults(body) {
                body.appendChild(
                    btnRow(
                        actionBtn("Save as Default", "", async () => {
                            const r = await openModal(
                                "Save as Default",
                                "Save current settings as the new default?\nThe existing default will be archived.",
                                "Save",
                            );
                            if (r.confirmed)
                                sendToHost({ action: "saveDefault" });
                        }),
                        actionBtn("Reset to Default", "danger", async () => {
                            const r = await openModal(
                                "Reset to Default",
                                "Reset all settings to the saved default?\nCurrent settings will be overwritten.",
                                "Reset",
                            );
                            if (r.confirmed)
                                sendToHost({ action: "resetToDefault" });
                        }),
                    ),
                );
            }

            // ── buildSettings — the pack's own user-defined settings ───────────
            function buildSettings(body) {
                // User-defined settings targeting the Settings section
                const items = S.userSettings || [];
                if (items.length > 0) {
                    for (const item of items) {
                        renderUserItem(body, item);
                    }
                } else {
                    body.appendChild(groupLabel("No settings defined."));
                    const r = h("div", { cls: "row" });
                    const lbl = h("div", { cls: "row-label" });
                    lbl.appendChild(
                        h(
                            "small",
                            {},
                            "Use ms.settings.define() in ms_macros.lua, or build settings with the builder.",
                        ),
                    );
                    r.appendChild(lbl);
                    body.appendChild(r);
                }
            }

            // ── buildUserSection — custom user-defined sections ────────────────────
            function buildUserSection(body, menu) {
                for (const item of menu.items || []) {
                    renderUserItem(body, item);
                }
            }

            // The profiles tab is laid out the way the settings list is: the
            // saved profiles, what you can do to them, and what travels off
            // the machine, each in its own named section. It used to be one
            // undifferentiated run of rows and button pairs.
            function buildProfiles(root) {
                const current = S.currentProfile || "";
                const profiles = S.profiles || [];
                const hasOthers = profiles.some((n) => n !== current);

                root.appendChild(section("profiles-list", "Profiles",
                    (body) => buildProfileList(body, current, profiles),
                    current ? "Active: " + current : "None active"));

                root.appendChild(section("profiles-manage", "Manage",
                    (body) => buildProfileManage(body, current, profiles, hasOthers),
                    "Creating, saving and clearing profiles"));

                root.appendChild(section("profiles-packages", "Packages",
                    buildProfilePackages,
                    "Moving a profile between machines"));
            }

            // The row menu (also opened by right-click). Switch/Delete only make
            // sense for a saved, non-active profile; Export works for either —
            // the active one exports live, a saved one exports its snapshot plus
            // the live assets (see exportPackage/collect in the host).
            function profileMenuItems(name, isCurrent) {
                const items = [];
                if (!isCurrent) {
                    items.push({
                        icon: "",
                        label: "Switch to this profile",
                        action: async () => {
                            const res = await openModal(
                                "Switch Profile",
                                `Switch to "${name}"?\n\nThe current profile will be archived and settings reloaded.`,
                                "Switch",
                            );
                            if (res.confirmed)
                                sendToHost({ action: "switchProfile", name });
                        },
                    });
                }
                items.push({
                    icon: "",
                    label: "Export this profile…",
                    action: () =>
                        sendToHost(
                            isCurrent
                                ? { action: "exportPackage", type: "profile" }
                                : { action: "exportPackage", type: "profile", profileName: name },
                        ),
                });
                if (!isCurrent) {
                    items.push("divider");
                    items.push({
                        icon: "",
                        label: "Delete profile",
                        danger: true,
                        action: async () => {
                            const res = await openModal(
                                "Delete Profile",
                                `Delete "${name}"?\n\nThis cannot be undone.`,
                                "Delete",
                            );
                            if (res.confirmed)
                                sendToHost({ action: "deleteProfile", name });
                        },
                    });
                }
                return items;
            }

            function buildProfileList(body, current, profiles) {
                const otherProfiles = profiles.filter((n) => n !== current);
                if (otherProfiles.length === 0 && !current) {
                    body.appendChild(
                        h(
                            "div",
                            { cls: "row disabled" },
                            h(
                                "div",
                                { cls: "row-label" },
                                "No saved profiles yet.",
                            ),
                        ),
                    );
                }

                for (const name of profiles) {
                    const isCurrent = name === current;
                    // No "disabled" on the active row — it must stay interactive
                    // so its actions button (Export) is clickable.
                    const r = h("div", {
                        cls: "row",
                        onmouseenter: () => playSlot("hover"),
                    });
                    r.appendChild(h("div", { cls: "row-label" }, name));
                    if (isCurrent)
                        r.appendChild(
                            h("span", { cls: "pill success" }, "Active"),
                        );

                    // Visible actions affordance — right-click is not reliable in
                    // the host webview, so every action is reachable from here.
                    const menuBtn = h(
                        "button",
                        {
                            cls: "row-menu-btn",
                            title: "Profile actions",
                            onmouseenter: () => playSlot("hover"),
                        },
                        "⋯",
                    );
                    menuBtn.addEventListener("click", (e) => {
                        e.preventDefault();
                        e.stopPropagation();
                        playSlot("interact");
                        const rect = menuBtn.getBoundingClientRect();
                        showCtxMenu(
                            rect.right,
                            rect.bottom,
                            profileMenuItems(name, isCurrent),
                            name,
                        );
                    });
                    r.appendChild(menuBtn);

                    if (!isCurrent)
                        r.addEventListener("click", async () => {
                            playSlot("interact");
                            const res = await openModal(
                                "Switch Profile",
                                `Switch to "${name}"?\n\nThe current profile will be archived and settings reloaded.`,
                                "Switch",
                            );
                            if (res.confirmed)
                                sendToHost({ action: "switchProfile", name });
                        });

                    r.addEventListener("contextmenu", (e) => {
                        e.preventDefault();
                        e.stopImmediatePropagation();
                        playSlot("interact");
                        showCtxMenu(
                            e.clientX,
                            e.clientY,
                            profileMenuItems(name, isCurrent),
                            name,
                        );
                    });
                    body.appendChild(r);
                }
            }

            function buildProfileManage(body, current, profiles, hasOthers) {
                const nameExists = current && profiles.some((n) => n === current);
                body.appendChild(
                    btnRow(
                        (() => {
                            const b = h(
                                "button",
                                {
                                    cls: "btn-action",
                                    onmouseenter: () => playSlot("hover"),
                                    onclick: () => {
                                        playSlot("interact");
                                        sendToHost({ action: "createNewProfile" });
                                    },
                                },
                                "Create New Profile",
                            );
                            return b;
                        })(),
                        (() => {
                            const b = h(
                                "button",
                                {
                                    cls: "btn-action" + (!nameExists ? " disabled" : ""),
                                    onmouseenter: () => playSlot("hover"),
                                    onclick: () => {
                                        if (!nameExists) return;
                                        playSlot("interact");
                                        sendToHost({ action: "saveCurrentProfile" });
                                    },
                                },
                                "Save Current Profile",
                            );
                            return b;
                        })(),
                    ),
                );
                if (hasOthers) {
                    body.appendChild(divider());
                    body.appendChild(
                        btnRow(
                            actionBtn(
                                "Clear Saved Profiles",
                                "danger",
                                async () => {
                                    const res = await openModal(
                                        "Clear Saved Profiles",
                                        "Delete all saved profiles except the active one?\n\nThis cannot be undone.",
                                        "Delete All",
                                    );
                                    if (res.confirmed)
                                        sendToHost({ action: "clearProfiles" });
                                },
                            ),
                        ),
                    );
                }
            }

            function buildProfilePackages(body) {
                body.appendChild(
                    btnRow(
                        actionBtn("Import Profile", "", () =>
                            sendToHost({ action: "importPackage" }),
                        ),
                        actionBtn("Export Profile", "", () =>
                            sendToHost({ action: "exportPackage", type: "profile" }),
                        ),
                        actionBtn("Split Profile…", "", () =>
                            sendToHost({ action: "splitProfile" }),
                        ),
                    ),
                );
                // A profile carries everything; this is the narrow one — just
                // ms_macros.lua / ms_macros_visual.json and sounds/macro/. Both
                // macro formats travel if both are present; the manifest's
                // macroFormat records which.
                body.appendChild(
                    btnRow(
                        actionBtn("Export Macros…", "", () =>
                            sendToHost({ action: "exportPackage", type: "macro" }),
                        ),
                    ),
                );
            }

            function buildDeveloper(body) {
                // Edit Macros lives in the Macros panel toolbar and Edit Theme
                // in the Theme panel's Theme File section — each raw-file escape
                // hatch sits with the builder that owns that file.
                body.appendChild(
                    btnRow(
                        actionBtn("Open Log Folder", "", () =>
                            sendToHost({ action: "openDevLogs" }),
                        ),
                    ),
                );

                body.appendChild(divider());

                // Log archive limit
                body.appendChild(
                    buildSlider(
                        "Log archive limit",
                        "Max archived log files kept per category in backups/",
                        0,
                        50,
                        1,
                        null,
                        S.devArchiveLimit ?? 15,
                        (v) =>
                            sendToHost({
                                action: "setDevArchiveLimit",
                                value: v,
                            }),
                        [
                            {
                                icon: "",
                                label: "Reset to default",
                                action: () =>
                                    sendToHost({
                                        action: "setDevArchiveLimit",
                                        value: 15,
                                    }),
                            },
                        ],
                    ),
                );

                // Update channel selector
                const chan = S.updateChannel || "stable";
                body.appendChild(divider());
                body.appendChild(
                    row(
                        "Update Channel",
                        chan === "testing"
                            ? "Checks GitHub Actions for latest testing build"
                            : "Checks MANIFEST.json for stable releases",
                        h(
                            "button",
                            {
                                cls: "btn-macro " + (chan === "testing" ? "btn-enable" : ""),
                                onmouseenter: () => playSlot("hover"),
                                onclick: () => {
                                    const next = chan === "testing" ? "stable" : "testing";
                                    sendToHost({
                                        action: "setUpdateChannel",
                                        value: next,
                                    });
                                },
                            },
                            chan === "testing" ? "Testing" : "Stable",
                        ),
                    ),
                );

                body.appendChild(divider());

                // Testing source selector (only shown when channel is testing)
                if (chan === "testing") {
                    const src = S.testingSource || "release";
                    body.appendChild(
                        row(
                            "Testing Source",
                            src === "artifact"
                                ? "Downloads from GitHub Actions artifacts (zip only)"
                                : "Downloads from GitHub Releases (signed manifests)",
                            h(
                                "button",
                                {
                                    cls: "btn-macro " + (src === "artifact" ? "btn-enable" : ""),
                                    onmouseenter: () => playSlot("hover"),
                                    onclick: () => {
                                        const next = src === "artifact" ? "release" : "artifact";
                                        sendToHost({
                                            action: "setTestingSource",
                                            value: next,
                                        });
                                    },
                                },
                                src === "artifact" ? "Artifacts" : "Releases",
                            ),
                        ),
                    );

                    // GitHub token (only needed for artifacts)
                    if (src === "artifact") {
                        const token = S.githubToken || "";
                        body.appendChild(
                            row(
                                "GitHub Token",
                                token ? "••••••••" + token.slice(-4) : "Required for artifact downloads",
                                h("input", {
                                    type: "password",
                                    cls: "input-sm",
                                    placeholder: "ghp_...",
                                    value: token,
                                    onchange: (e) => {
                                        sendToHost({
                                            action: "setGithubToken",
                                            value: e.target.value,
                                        });
                                    },
                                }),
                            ),
                        );
                    }
                }

                body.appendChild(divider());

                // System Integrity
                const status = S.integrityStatus || "uninitialized";
                const hash = S.integrityHash
                    ? S.integrityHash.slice(0, 16) + "…"
                    : "—";
                const trusted = status === "trusted";

                let statusPill;
                if (status === "trusted")
                    statusPill = h(
                        "span",
                        { cls: "pill success", style: "font-weight:600" },
                        "Trusted",
                    );
                else if (status === "mismatch")
                    statusPill = h(
                        "span",
                        { cls: "pill danger", style: "font-weight:600" },
                        "⚠ Mismatch",
                    );
                else statusPill = h("span", { cls: "pill", style: "font-weight:600" }, "Not set");
                body.appendChild(row("System Integrity", hash, statusPill));

                // Trust row — greyed when trusted
                const trustRow = h("div", {
                    cls: "row" + (trusted ? " disabled" : ""),
                    onmouseenter: () => {
                        if (!trusted) playSlot("hover");
                    },
                });
                trustRow.appendChild(
                    h(
                        "div",
                        { cls: "row-label" },
                        trusted
                            ? "Trust Current Version"
                            : "Trust Current Version…",
                    ),
                );
                if (!trusted) {
                    trustRow.addEventListener("click", async () => {
                        playSlot("interact");
                        const prompt =
                            status === "uninitialized"
                                ? `Seal this ms_core.lua as the trusted baseline?\nHash: ${hash}`
                                : `Hash mismatch — trust the CURRENT (possibly modified) version?\nHash: ${hash}`;
                        const r = await openModal(
                            "Trust Current Version",
                            prompt,
                            "Trust",
                        );
                        if (r.confirmed)
                            sendToHost({ action: "trustCurrentVersion" });
                    });
                }
                body.appendChild(trustRow);

                body.appendChild(
                    btnRow(
                        actionBtn("Check Integrity", "", () =>
                            sendToHost({ action: "checkIntegrity" }),
                        ),
                    ),
                );

                // Delete hash — only shown when a hash is actually on record
                if (status !== "uninitialized") {
                    body.appendChild(divider());
                    body.appendChild(
                        btnRow(
                            actionBtn(
                                "Delete Trusted Hash",
                                "danger",
                                async () => {
                                    const r = await openModal(
                                        "Delete Trusted Hash",
                                        "This removes integrity protection entirely.\n\n" +
                                            "From this point on mudscript will load ANY version of its code " +
                                            "without warning — including maliciously modified files.\n\n" +
                                            "You are on your own. Proceed only if you know what you are doing.",
                                        "Delete — I understand the risk",
                                    );
                                    if (r.confirmed)
                                        sendToHost({
                                            action: "deleteTrustedHash",
                                        });
                                },
                            ),
                        ),
                    );
                }
            }

            function buildHelp(body) {
                const meta = S.macroMeta || {};
                const ver = S.msVersion || "dev";
                body.appendChild(
                    h(
                        "div",
                        { cls: "group-label" },
                        "mudscript HS Utilities \u2013 Version: ",
                        h("span", { style: "text-transform: none" }, ver),
                    ),
                );

                const aboutBtn = actionBtn("About", "", () => {
                    sendToHost({
                        action: "alert",
                        msg: "mudscript Utility Library\nBy: mudbourn \u2014 mudbourn.info",
                        duration: 5,
                    });
                    if (meta.name) {
                        const line2 =
                            meta.name +
                            (meta.author ? `\nBy: ${meta.author}` : "") +
                            (meta.website ? `\n${meta.website}` : "");
                        sendToHost({
                            action: "alert",
                            msg: line2,
                            duration: 5,
                            noSound: true,
                        });
                    }
                });

                const docBtn = actionBtn("Documentation", "", () =>
                    sendToHost({
                        action: "openURL",
                        url: (S.docsURL || "") + "?platform=mac",
                    }),
                );
                docBtn.style.flex = "1";

                const githubBtn = actionBtn("GitHub", "", () =>
                    sendToHost({
                        action: "openURL",
                        url: "https://github.com/mudbourn/mudscript",
                    }),
                );
                githubBtn.style.flex = "1";

                if (S.updateManifestURL || S.updateChannel === "testing") {
                    const _chan = S.updateChannel || "stable";
                    const updateBtn = actionBtn(
                        "Check for Update",
                        "",
                        async () => {
                            const r = await openModal(
                                "Check for Update",
                                "Channel: " + _chan + "\nDownload and apply the latest ms_core.lua from GitHub?\n\nThe current file will be backed up to backups/ and Hammerspoon will reload.",
                                "Update",
                            );
                            if (r.confirmed)
                                sendToHost({ action: "checkForUpdate" });
                        },
                    );
                    body.appendChild(btnRow(aboutBtn, updateBtn));
                } else {
                    body.appendChild(btnRow(aboutBtn));
                }
                body.appendChild(btnRow(docBtn, githubBtn));
            }

            // ── Render ─────────────────────────────────────────────────────────
            function render() {
                const scroll = document.getElementById("scroll");
                const scrollTop = scroll.scrollTop;
                scroll.innerHTML = "";

                // Everything user-defined — the pack's own Settings section,
                // its Calibration group, and any custom menus — lives in the
                // Tools panel now (renderToolsPanel, below). Macros moved to
                // the macros panel, which owns rebinding. Settings keeps only
                // the app-level surfaces that have no panel of their own.
                scroll.appendChild(
                    section("runtime", "Runtime", buildRuntime,
                        "Macro engine and what a reload touches"),
                );
                scroll.appendChild(
                    section("accessibility", "Accessibility", buildAccessibility,
                        "Input handling and performance"),
                );
                scroll.appendChild(
                    section("defaults", "Defaults", buildDefaults,
                        "Save or restore every setting at once"),
                );
                scroll.appendChild(
                    section("developer", "Developer", buildDeveloper,
                        "Editing, logs, updates, and integrity"),
                );
                scroll.appendChild(
                    section("help", "Help", buildHelp, "Version and documentation"),
                );

                scroll.scrollTop = scrollTop;
            }

            // ── buildSettingBuilder — author a setting from the Tools panel ────
            // A live form for composing a setting definition without hand-
            // editing ms_macros.lua: pick a type, fill the fields, watch it
            // render in the preview using the very same renderUserItem the real
            // rows use, then Add it. The Add posts the finished def to the host
            // on the tools channel (ui:tools:addUserSetting) — the Lua side that
            // persists it into the pack is the next step; until then this
            // models the authoring flow end to end and previews the result.
            function buildSettingBuilder(body) {
                // The one field of type shape shared by every kind of setting.
                const draft = {
                    type: "toggle",
                    key: "",
                    label: "",
                    hint: "",
                    default: false,
                    min: 0,
                    max: 100,
                    step: 1,
                    unit: "",
                    options: [
                        { label: "One", value: "one" },
                        { label: "Two", value: "two" },
                    ],
                    btnLabel: "Run",
                    danger: false,
                    target: "settings",
                };

                const typeLabels = [
                    { label: "Toggle", value: "toggle" },
                    { label: "Slider", value: "slider" },
                    { label: "Segmented", value: "seg" },
                    { label: "Action", value: "action" },
                    { label: "Label", value: "groupLabel" },
                    { label: "Divider", value: "divider" },
                ];
                // Types that carry a key/value; label and divider are cosmetic.
                const keyed = (t) =>
                    t !== "divider" && t !== "groupLabel";

                // A labelled text field on its own row, matching the input-sm
                // house style. Re-renders nothing on input beyond the preview,
                // so focus stays put while typing. The input elements are kept
                // in `identityInputs` so Add/Reset can push cleared draft values
                // back into the DOM — the builder no longer rebuilds itself, so
                // clearing `draft` alone would leave stale text on screen.
                const identityInputs = {};
                const textField = (labelText, sub, key, placeholder) => {
                    const input = h("input", {
                        type: "text",
                        cls: "input-sm",
                        placeholder: placeholder || "",
                        value: draft[key] || "",
                        oninput: (e) => {
                            draft[key] = e.target.value;
                            updatePreview();
                        },
                    });
                    identityInputs[key] = input;
                    return row(labelText, sub, input);
                };
                // Sync the identity inputs' visible text from `draft` — used
                // after Add/Reset clears the draft.
                const syncIdentityInputs = () => {
                    for (const k in identityInputs)
                        identityInputs[k].value = draft[k] || "";
                };

                const numField = (labelText, key, step) =>
                    row(
                        labelText,
                        null,
                        h("input", {
                            type: "number",
                            cls: "input-sm",
                            step: String(step || 1),
                            value: String(draft[key]),
                            oninput: (e) => {
                                const v = parseFloat(e.target.value);
                                draft[key] = isNaN(v) ? 0 : v;
                                updatePreview();
                            },
                        }),
                        "row-sub row-compact",
                    );

                // ── Stable containers ────────────────────────────────────────
                // Type picker never rebuilds; the type-specific block (dyn) and
                // the preview do. Keeping the picker and the common text fields
                // out of the rebuilt region is what preserves input focus.
                body.appendChild(
                    row(
                        "Type",
                        "What kind of control to add",
                        seg(typeLabels, draft.type, (v) => {
                            draft.type = v;
                            renderDynamic();
                            updatePreview();
                        }),
                    ),
                );

                body.appendChild(divider());
                const dyn = h("div", { cls: "setting-builder-dyn" });
                body.appendChild(dyn);

                // ── Preview ──────────────────────────────────────────────────
                body.appendChild(divider());
                body.appendChild(groupLabel("Preview"));
                const preview = h("div", { cls: "setting-builder-preview" });
                body.appendChild(preview);

                // ── Add / Reset ──────────────────────────────────────────────
                body.appendChild(
                    btnRow(
                        actionBtn("Add Setting", "accent", () => {
                            const def = buildDef();
                            const err = validate(def);
                            if (err) {
                                showAlert(err);
                                return;
                            }
                            // The host validates (duplicate keys, etc.) and is
                            // the source of truth for the success/failure
                            // notice. Clear the identity fields so the next
                            // setting starts fresh — the builder no longer
                            // rebuilds on the host's state push, so push the
                            // cleared values into the inputs directly.
                            sendToHost({ action: "addUserSetting", def: def });
                            draft.key = "";
                            draft.label = "";
                            draft.hint = "";
                            syncIdentityInputs();
                            renderDynamic();
                            updatePreview();
                        }),
                        actionBtn("Reset", "", () => {
                            draft.key = "";
                            draft.label = "";
                            draft.hint = "";
                            syncIdentityInputs();
                            renderDynamic();
                            updatePreview();
                        }),
                    ),
                );

                // ── Builders ─────────────────────────────────────────────────
                // Assemble the serialized item the preview and the host both
                // consume — same shape ms_ui.lua emits for a defined setting.
                function buildDef() {
                    const d = { type: draft.type, target: draft.target };
                    if (keyed(draft.type)) {
                        d.key = draft.key.trim();
                        d.hint = draft.hint.trim() || undefined;
                    }
                    if (draft.type === "groupLabel") {
                        d.label = draft.label.trim();
                    } else if (draft.type !== "divider") {
                        d.label = draft.label.trim();
                    }
                    if (draft.type === "toggle") {
                        d.default = draft.default;
                        d.value = draft.default;
                    } else if (draft.type === "slider") {
                        d.min = draft.min;
                        d.max = draft.max;
                        d.step = draft.step;
                        d.unit = draft.unit.trim() || undefined;
                        d.default = draft.default || draft.min;
                        d.value = d.default;
                    } else if (draft.type === "seg") {
                        d.options = draft.options.filter(
                            (o) => o.label.trim() !== "",
                        );
                        d.default =
                            d.options.length > 0 ? d.options[0].value : undefined;
                        d.value = d.default;
                    } else if (draft.type === "action") {
                        d.btnLabel = draft.btnLabel.trim() || "Run";
                        d.danger = draft.danger;
                    }
                    return d;
                }

                function validate(def) {
                    if (keyed(def.type) && !def.key)
                        return "A key is required for this setting type.";
                    if (def.type === "groupLabel" && !def.label)
                        return "A label is required.";
                    if (def.type === "seg" && (!def.options || !def.options.length))
                        return "Add at least one option.";
                    return null;
                }

                // ── Type-specific fields ─────────────────────────────────────
                function renderDynamic() {
                    dyn.innerHTML = "";
                    const t = draft.type;

                    if (keyed(t)) {
                        dyn.appendChild(
                            textField(
                                "Key",
                                "Unique id used to read the value",
                                "key",
                                "mySetting",
                            ),
                        );
                    }
                    if (t !== "divider") {
                        dyn.appendChild(
                            textField("Label", null, "label", "My Setting"),
                        );
                    }
                    if (keyed(t)) {
                        dyn.appendChild(
                            textField("Hint", "Optional one-line help", "hint", ""),
                        );
                    }

                    if (t === "toggle") {
                        dyn.appendChild(
                            row(
                                "Default",
                                "State when reset",
                                toggle(draft.default, (e) => {
                                    draft.default = e.target.checked;
                                    updatePreview();
                                }),
                                "row-sub",
                            ),
                        );
                    } else if (t === "slider") {
                        dyn.appendChild(numField("Min", "min", draft.step));
                        dyn.appendChild(numField("Max", "max", draft.step));
                        dyn.appendChild(numField("Step", "step", 0.1));
                        dyn.appendChild(numField("Default", "default", draft.step));
                        dyn.appendChild(
                            textField("Unit", "Optional suffix, e.g. px", "unit", ""),
                        );
                    } else if (t === "seg") {
                        dyn.appendChild(groupLabel("Options"));
                        renderOptions(dyn);
                    } else if (t === "action") {
                        dyn.appendChild(
                            textField(
                                "Button text",
                                null,
                                "btnLabel",
                                "Run",
                            ),
                        );
                        dyn.appendChild(
                            row(
                                "Destructive",
                                "Style the button as a danger action",
                                toggle(draft.danger, (e) => {
                                    draft.danger = e.target.checked;
                                    updatePreview();
                                }),
                                "row-sub",
                            ),
                        );
                    }

                    if (keyed(t) || t === "groupLabel") {
                        dyn.appendChild(divider());
                        dyn.appendChild(
                            row(
                                "Destination",
                                "Which Tools section it lands in",
                                seg(
                                    [
                                        { label: "Settings", value: "settings" },
                                        {
                                            label: "Calibration",
                                            value: "calibration",
                                        },
                                    ],
                                    draft.target,
                                    (v) => {
                                        draft.target = v;
                                    },
                                ),
                                "row-sub",
                            ),
                        );
                    }
                }

                // The segmented-control options editor: a stack of label/value
                // pairs with add and remove. Structural changes rebuild the
                // list; typing only touches the draft and the preview.
                function renderOptions(host) {
                    const list = h("div", { cls: "setting-builder-opts" });
                    draft.options.forEach((opt, i) => {
                        const rowEl = h("div", { cls: "sb-opt-row" });
                        rowEl.appendChild(
                            h("input", {
                                type: "text",
                                cls: "input-sm",
                                placeholder: "Label",
                                value: opt.label,
                                oninput: (e) => {
                                    opt.label = e.target.value;
                                    updatePreview();
                                },
                            }),
                        );
                        rowEl.appendChild(
                            h("input", {
                                type: "text",
                                cls: "input-sm",
                                placeholder: "value",
                                value: opt.value,
                                oninput: (e) => {
                                    opt.value = e.target.value;
                                    updatePreview();
                                },
                            }),
                        );
                        const rm = actionBtn("✕", "", () => {
                            draft.options.splice(i, 1);
                            host.innerHTML = "";
                            renderOptions(host);
                            updatePreview();
                        });
                        rm.classList.add("sb-opt-rm");
                        rowEl.appendChild(rm);
                        list.appendChild(rowEl);
                    });
                    host.appendChild(list);
                    host.appendChild(
                        btnRow(
                            actionBtn("Add Option", "", () => {
                                draft.options.push({ label: "", value: "" });
                                host.innerHTML = "";
                                renderOptions(host);
                                updatePreview();
                            }),
                        ),
                    );
                }

                // The payoff: the exact renderUserItem the live rows use, so the
                // preview can never drift from the real thing.
                function updatePreview() {
                    preview.innerHTML = "";
                    const def = buildDef();
                    try {
                        renderUserItem(preview, def);
                    } catch (e) {
                        preview.appendChild(
                            groupLabel("Preview unavailable."),
                        );
                    }
                }

                renderDynamic();
                updatePreview();
            }

            // ── Tools panel (rendered into #tools-scroll) ────────────────────
            // Home for everything the macro pack defines: the generic Settings
            // section (with Save/Reset as Default), the Calibration group, and
            // any custom menus. Built from the same section()/renderUserItem
            // kit as the Settings panel — same document, so it renders straight
            // into the Tools panel's scroll container. Rendered from
            // panel-settings.js exactly as the Profiles panel is.
            function renderToolsPanel() {
                const scroll = document.getElementById("tools-scroll");
                if (!scroll) return;
                const scrollTop = scroll.scrollTop;
                scroll.innerHTML = "";

                scroll.appendChild(
                    section("settings", "Settings", buildSettings,
                        "Defined by your macro pack"),
                );

                const calib = S.userCalibrationSettings || [];
                if (calib.length > 0) {
                    scroll.appendChild(
                        section("calibration", "Calibration", (body) => {
                            for (const item of calib) renderUserItem(body, item);
                        }, "Tune the pack to your setup"),
                    );
                }

                for (const menu of S.userMenus || []) {
                    const title = menu.icon
                        ? menu.icon + " " + menu.title
                        : menu.title;
                    scroll.appendChild(
                        section("user_" + menu.id, title, (body) =>
                            buildUserSection(body, menu),
                        ),
                    );
                }

                scroll.scrollTop = scrollTop;

                // Setting Builder lives in its own tab. Build it ONCE: it is a
                // self-contained compose form backed by local `draft` state and
                // reads nothing from host state, so there is no reason to rebuild
                // it on a state push — and doing so destroyed the focused input
                // mid-keystroke. With the shell being a non-activating panel,
                // the lost focus meant the next keys fell through to whatever app
                // was actually active instead of the field.
                const bscroll = document.getElementById("tools-builder-scroll");
                if (bscroll && !bscroll.firstChild) {
                    bscroll.appendChild(
                        section("builder", "Setting Builder", buildSettingBuilder,
                            "Compose a new setting and preview it live"),
                    );
                }
            }
            window.renderToolsPanel = renderToolsPanel;

            // ── Tools tab strip ──────────────────────────────────────────────
            let _otabs = null;
            function toolsTabs() {
                if (_otabs) return _otabs;
                const panel = document.querySelector(".panel-tools");
                if (!panel || !window.createTabs) return null;
                _otabs = window.createTabs({
                    root: panel,
                    tabSelector: ".otab",
                    sectionSelector: ".otab-section",
                    tabKey: (el) => el.dataset.otab,
                    sectionKey: (el) => el.dataset.osection,
                    onSame: () => playSlot("back"),
                    onSwitch: () => playSlot("interact"),
                });
                return _otabs;
            }

            function switchToolsTab(tab) {
                const t = toolsTabs();
                if (t) t.switch(tab);
            }
            window.switchToolsTab = switchToolsTab;

            // ── Profiles panel (rendered into #profiles-scroll) ──────────────
            function renderProfilesPanel() {
                const el = document.getElementById("profiles-scroll");
                if (!el) return;
                el.innerHTML = "";
                buildProfiles(el);
                // Coming soon note
                const note = h("div", {
                    style: "padding:16px 14px 8px;font-size:11px;color:var(--text3);opacity:0.6;font-style:italic;",
                }, "More profile features coming soon.");
                el.appendChild(note);
                // The Profiles panel no longer has a Browse tab — discovery and
                // install moved to the universal Browse stage (panel-browse.js).
            }
            window.renderProfilesPanel = renderProfilesPanel;
            // The Profiles panel is a single view now — its old Profiles/Browse
            // tab strip was removed once Browse moved to its own stage.

            // ── Theme application ──────────────────────────────────────────────

            window.settingsApplyTheme = settingsApplyTheme;

            function applyFont(font, fontURL) {
                if (!font) return;
                if (fontURL) {
                    // Inject or replace a @font-face rule for a local font file.
                    let el = document.getElementById("_ms-custom-font");
                    if (!el) {
                        el = document.createElement("style");
                        el.id = "_ms-custom-font";
                        document.head.appendChild(el);
                    }
                    el.textContent = `@font-face { font-family: "${font}"; src: url("${fontURL}"); }`;
                }
                document.body.style.fontFamily = `"${font}", Almendra, Palatino, Georgia, serif`;
            }

            // Parse #rrggbb or #rgb → { r, g, b }
            function hexToRgb(hex) {
                hex = hex.replace(/^#/, "");
                if (hex.length === 3) hex = hex[0]+hex[0]+hex[1]+hex[1]+hex[2]+hex[2];
                const n = parseInt(hex, 16);
                return { r: (n >> 16) & 255, g: (n >> 8) & 255, b: n & 255 };
            }

            function settingsApplyTheme(t) {
                if (!t) return;
                const r = document.documentElement.style;
                // ── Base colors ──────────────────────────────────────────
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

                // ── Derived: text2/text3 from text ───────────────────────
                if (t.text && !t.text2) {
                    const c = hexToRgb(t.text);
                    if (c) r.setProperty("--text2", `rgba(${c.r},${c.g},${c.b},0.85)`);
                }
                if (t.text && !t.text3) {
                    const c = hexToRgb(t.text);
                    if (c) r.setProperty("--text3", `rgba(${c.r},${c.g},${c.b},0.55)`);
                }

                // ── Derived: border from accent + hover mix ──────────────
                if (t.accent && t.hover && !t.border) {
                    const a = hexToRgb(t.accent);
                    const h = hexToRgb(t.hover);
                    if (a && h) {
                        const mr = Math.round(a.r * 0.5 + h.r * 0.5);
                        const mg = Math.round(a.g * 0.5 + h.g * 0.5);
                        const mb = Math.round(a.b * 0.5 + h.b * 0.5);
                        r.setProperty("--border", `rgba(${mr},${mg},${mb},0.55)`);
                    }
                }

                // ── Derived: accent glow ─────────────────────────────────
                if (t.accent && !t.accentGlow) {
                    const a = hexToRgb(t.accent);
                    if (a) r.setProperty("--accent-glow", `rgba(${a.r},${a.g},${a.b},0.4)`);
                }
                if (t.accent && !t.accentGlowFaint) {
                    const a = hexToRgb(t.accent);
                    if (a) r.setProperty("--accent-glow-faint", `rgba(${a.r},${a.g},${a.b},0.12)`);
                }

                // ── Derived: danger glow/border ──────────────────────────
                if (t.danger && !t.dangerGlow) {
                    const d = hexToRgb(t.danger);
                    if (d) r.setProperty("--danger-glow", `rgba(${d.r},${d.g},${d.b},0.6)`);
                }
                if (t.danger && !t.dangerBorder) {
                    const d = hexToRgb(t.danger);
                    if (d) r.setProperty("--danger-border", `rgba(${d.r},${d.g},${d.b},0.3)`);
                }

                // ── Explicit overrides always win ────────────────────────
                if (t.text2) r.setProperty("--text2", t.text2);
                if (t.text3) r.setProperty("--text3", t.text3);
                if (t.border) r.setProperty("--border", t.border);
                if (t.accentGlow) r.setProperty("--accent-glow", t.accentGlow);
                if (t.accentGlowFaint) r.setProperty("--accent-glow-faint", t.accentGlowFaint);
                if (t.dangerGlow) r.setProperty("--danger-glow", t.dangerGlow);
                if (t.dangerBorder) r.setProperty("--danger-border", t.dangerBorder);

                // ── Radius, font ────────────────────────────────────────
                if (t.radius !== undefined) {
                    r.setProperty("--radius", t.radius + "px");
                    r.setProperty(
                        "--radius-s",
                        Math.max(0, t.radius - 1) + "px",
                    );
                }
                applyFont(t.font, t.fontURL);
            }

            // ── receiveState ───────────────────────────────────────────────────
            function receiveState(state) {
                S = state;
                applyTheme(S.theme);
                const verEl = document.getElementById("rail-version");
                if (verEl && S.msVersion) verEl.textContent = "v" + S.msVersion;
                render();
                renderToolsPanel();
                renderProfilesPanel();
                // Theme & sound live in panel-theme.js — it gets the state it
                // needs handed to it rather than reaching back for S.
                if (window.renderThemePanel) window.renderThemePanel(state);
                if (window.renderPluginsPanel) window.renderPluginsPanel(state);
            }

            // ── Init ───────────────────────────────────────────────────────────
            document.addEventListener("DOMContentLoaded", () => {
                // When embedded in the shell iframe, strip window-chrome styling
                if (window.shellPost) {
                    var p = document.getElementById("panel");
                    if (p) {
                        p.style.borderRadius = "0";
                        p.style.clipPath = "none";
                    }
                }
                // Header drag (settings panel is outside log-panel.js scope)
                (function() {
                    // Drag is handled by the main header drag handler (event delegation)
                })();
                sendToHost({ action: "ready" });
            });

            // Expose for inline onclick handlers in the HTML
            window.sendToHost = sendToHost;
            window.playSlot = playSlot;
            window.closePanel = function() { sendToHost({ action: 'close' }); };
    })();
