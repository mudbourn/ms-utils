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
            // bar, so it confirms first. Once confirmed the UI stops being
            // interactive: the overlay covers the panel, the shutdown slot
            // plays, and the host is told to quit only after the sound has had
            // time to start — quitting immediately cuts it off mid-sample.
            const SHUTDOWN_HOLD_MS = 900;
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

            // The curtain covers both exits. Restart gets its own wording and
            // mark because the two look identical otherwise, and "shutting
            // down" during a reload reads as a crash — the window vanishing a
            // moment later makes that worse, not better.
            const CURTAIN = {
                shutdown: {
                    text: "mudscript is shutting down",
                    icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2v10"/><path d="M18.4 6.6a9 9 0 1 1-12.77.04"/></svg>',
                },
                restart: {
                    text: "mudscript is restarting",
                    icon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12a9 9 0 0 1 15.5-6.2L21 8"/><path d="M21 3v5h-5"/><path d="M21 12a9 9 0 0 1-15.5 6.2L3 16"/><path d="M3 21v-5h5"/></svg>',
                },
            };

            // Called by the host for the restart path too, which has no UI in
            // front of it — hence the global.
            function showShutdownCurtain(mode) {
                const spec = CURTAIN[mode] || CURTAIN.shutdown;
                const ov = document.getElementById("shutdown-overlay");
                const mark = document.getElementById("shutdown-mark");
                const text = document.getElementById("shutdown-text");
                if (mark) mark.innerHTML = spec.icon;
                if (text) text.textContent = spec.text;
                if (ov) ov.classList.add("open");
            }
            window.showShutdownCurtain = showShutdownCurtain;

            function beginShutdown() {
                _shuttingDown = true;
                showShutdownCurtain("shutdown");
                playSlot("shutdown");
                setTimeout(
                    () => sendToHost({ action: "shutdown" }),
                    SHUTDOWN_HOLD_MS,
                );
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
                        actionBtn("Reload Everything", "", async () => {
                            const r = await openModal(
                                "Reload Everything",
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

            // ── buildSettings — system + user-defined settings ─────────────────
            function buildSettings(body) {
                // Save / Reset as Default — always first
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

                // User-defined settings targeting the Settings section
                const items = S.userSettings || [];
                if (items.length > 0) {
                    body.appendChild(divider());
                    for (const item of items) {
                        renderUserItem(body, item);
                    }
                } else {
                    body.appendChild(divider());
                    body.appendChild(groupLabel("No settings defined."));
                    const r = h("div", { cls: "row" });
                    const lbl = h("div", { cls: "row-label" });
                    lbl.appendChild(
                        h(
                            "small",
                            {},
                            "Use ms.settings.define() in your macro pack.",
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

            function buildProfiles(body) {
                const current = S.currentProfile || "";
                const profiles = S.profiles || [];
                if (current)
                    body.appendChild(
                        h("div", { cls: "group-label" }, "Active: " + current),
                    );

                const otherProfiles = profiles.filter((n) => n !== current);
                if (otherProfiles.length === 0) {
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
                    const r = h("div", {
                        cls: "row" + (isCurrent ? " disabled" : ""),
                        onmouseenter: () => playSlot("hover"),
                    });
                    r.appendChild(h("div", { cls: "row-label" }, name));
                    if (isCurrent)
                        r.appendChild(
                            h("span", { cls: "pill success" }, "Active"),
                        );
                    else
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
                        if (isCurrent) return;
                        playSlot("interact");
                        showCtxMenu(
                            e.clientX,
                            e.clientY,
                            [
                                {
                                    icon: "",
                                    label: "Switch to this profile",
                                    action: async () => {
                                        const res = await openModal(
                                            "Switch Profile",
                                            `Switch to "${name}"?\n\nThe current profile will be archived and settings reloaded.`,
                                            "Switch",
                                        );
                                        if (res.confirmed)
                                            sendToHost({
                                                action: "switchProfile",
                                                name,
                                            });
                                    },
                                },
                                "divider",
                                {
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
                                            sendToHost({
                                                action: "deleteProfile",
                                                name,
                                            });
                                    },
                                },
                            ],
                            name,
                        );
                    });
                    body.appendChild(r);
                }

                body.appendChild(divider());
                const hasOthers = profiles.some((n) => n !== current);
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
                body.appendChild(
                    btnRow(
                        actionBtn("Import Profile", "", () =>
                            sendToHost({ action: "importProfilePkg" }),
                        ),
                        actionBtn("Export Profile", "", () =>
                            sendToHost({ action: "exportProfilePkg" }),
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
                if (hasOthers)
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

            function buildDeveloper(body) {
                body.appendChild(
                    btnRow(
                        actionBtn("Edit Macros", "", () =>
                            sendToHost({ action: "editMacros" }),
                        ),
                        actionBtn("Edit Theme", "", () =>
                            sendToHost({ action: "editTheme" }),
                        ),
                        actionBtn("Open Log Folder", "", () =>
                            sendToHost({ action: "openDevLogs" }),
                        ),
                    ),
                );

                body.appendChild(divider());

                // Roblox cache cleaner toggle
                const cacheCleaner = S.cacheCleanerEnabled === true;
                body.appendChild(
                    row(
                        "Roblox cache cleaner",
                        "Auto-purge micro-profiler dumps & stale logs every 6 h",
                        toggle(cacheCleaner, (e) => {
                            sendToHost({
                                action: "setCacheCleanerEnabled",
                                value: e.target.checked,
                            });
                        }),
                    ),
                );

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
                        url: "https://github.com/mudbourn/ms-utils",
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

                // Macros moved to the macros panel (which owns rebinding) and
                // Calibration to the tools panel (its content is entirely
                // user-defined settings). Settings keeps only what has no
                // panel of its own.
                scroll.appendChild(
                    section("runtime", "Runtime", buildRuntime,
                        "Macro engine and what a reload touches"),
                );
                scroll.appendChild(
                    section("settings", "Settings", buildSettings,
                        "Defined by your macro pack"),
                );
                scroll.appendChild(
                    section("accessibility", "Accessibility", buildAccessibility,
                        "Input handling and performance"),
                );
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
                scroll.appendChild(
                    section("developer", "Developer", buildDeveloper,
                        "Editing, logs, updates, and integrity"),
                );
                scroll.appendChild(
                    section("help", "Help", buildHelp, "Version and documentation"),
                );

                scroll.scrollTop = scrollTop;
            }

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

                // Browse tab — stub until the profile browser lands.
                const browse = document.getElementById("profiles-browse-scroll");
                if (browse) {
                    browse.innerHTML = "";
                    browse.appendChild(h("div", {
                        style: "display:flex;align-items:center;justify-content:center;"
                            + "flex:1;padding:32px 14px;color:var(--text3);font-size:13px;",
                    }, "Profile Browser coming soon."));
                }
            }
            window.renderProfilesPanel = renderProfilesPanel;

            // ── Profiles tab strip ───────────────────────────────────────────
            let _ptabs = null;
            function profilesTabs() {
                if (_ptabs) return _ptabs;
                const panel = document.querySelector(".panel-profiles");
                if (!panel || !window.createTabs) return null;
                _ptabs = window.createTabs({
                    root: panel,
                    tabSelector: ".ptab",
                    sectionSelector: ".ptab-section",
                    tabKey: (el) => el.dataset.ptab,
                    sectionKey: (el) => el.dataset.psection,
                    onSame: () => playSlot("back"),
                    onSwitch: () => playSlot("interact"),
                });
                return _ptabs;
            }

            function switchProfilesTab(tab) {
                const t = profilesTabs();
                if (t) t.switch(tab);
            }
            window.switchProfilesTab = switchProfilesTab;

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
