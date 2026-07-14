    /* panel: settings */
    (function() {
    "use strict";
// ── State ──────────────────────────────────────────────────────────
            let S = {};
            let _openSections = new Set();
            let _openSoundPicker = null;
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

            // Close ctx menu and reload dropdown on any left-click or Escape.
            // preventDefault on contextmenu suppresses the native WebKit menu everywhere.
            function closeReloadDropdown() {
                const el = document.getElementById("reloadDropdown");
                if (el) el.classList.remove("open");
            }
            document.addEventListener("click", (e) => {
                closeCtxMenu();
                if (!e.target.closest(".reload-dropdown")) closeReloadDropdown();
            });
            const _settingsPanel = document.querySelector('.panel-settings');
            document.addEventListener("contextmenu", (e) => {
                if (!_settingsPanel || getComputedStyle(_settingsPanel).display === "none") return;
                e.preventDefault();
                closeCtxMenu();
                closeReloadDropdown();
            });
            document.addEventListener("keydown", (e) => {
                if (!_settingsPanel || getComputedStyle(_settingsPanel).display === "none") return;
                if (e.key === "Escape") { closeCtxMenu(); closeReloadDropdown(); }
            });

            // ── Quick-Reload option checkboxes ──────────────────────────────
            function toggleQR(el) {
                const key = el.dataset.qr;
                if (!key) return;
                const now = !el.classList.contains("checked");
                el.classList.toggle("checked", now);
                sendToHost({ action: "setQROption", key: key, value: now });
            }
            // Sync checkbox states from the Lua state object.
            function syncQRChecks(qr) {
                if (!qr) return;
                document.querySelectorAll(".qr-check[data-qr]").forEach(el => {
                    const key = el.dataset.qr;
                    const on = qr[key] !== false;
                    el.classList.toggle("checked", on);
                });
            }

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
                    { cls: "toggle" },
                    h("input", { type: "checkbox", onchange }),
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

            function section(id, title, buildFn, defaultOpen = false, collapsible = true) {
                const isOpen = !collapsible || _openSections.has(id);
                const head = h(
                    "div",
                    { cls: "section-head" + (isOpen ? " open" : "") + (collapsible ? "" : " always-open") },
                    h("span", { cls: "section-chevron" }, "▶"),
                    h("span", { cls: "section-title" }, title),
                );
                const body = h("div", {
                    cls: "section-body" + (isOpen ? " open" : ""),
                });
                buildFn(body);
                if (collapsible) {
                    head.addEventListener("mouseenter", () => playSlot("hover"));
                    head.addEventListener("click", () => {
                        playSlot("interact");
                        const open = !_openSections.has(id);
                        if (open) _openSections.add(id);
                        else _openSections.delete(id);
                        head.classList.toggle("open", open);
                        body.classList.toggle("open", open);
                        if (open) {
                            // Wait for the CSS max-height transition (250ms) then scroll
                            // the bottom of the newly-expanded section into view.
                            setTimeout(() => {
                                const wrap = head.parentElement;
                                wrap.scrollIntoView({
                                    block: "nearest",
                                    behavior: "smooth",
                                });
                            }, 260);
                        }
                    });
                }
                const wrap = h("div", { cls: "section" });
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

            // ── Sound picker ───────────────────────────────────────────────────
            function soundPicker(slotId, assigned, soundNames) {
                const display = assigned || "off";
                const wrap = h("div", { cls: "sound-picker-wrap" });
                const btn = h(
                    "div",
                    {
                        cls: "sound-picker-btn",
                        onmouseenter: () => playSlot("hover"),
                    },
                    display,
                    h("span", { cls: "arrow" }, "▾"),
                );
                const list = h("div", { cls: "sound-list" });

                // Filter state
                let _filter = "all"; // "all" | "default" | "active" | "macro"
                function categoryOf(name) {
                    if (name.startsWith("d_")) return "default";
                    if (name.startsWith("m_")) return "macro";
                    if (name.startsWith("a_")) return "active";
                    return "other";
                }

                // Filter bar
                const filterBar = h("div", { cls: "sound-filter-bar" });
                const filters = [
                    { key: "all", label: "All" },
                    { key: "default", label: "Default" },
                    { key: "active", label: "Active" },
                    { key: "macro", label: "Macro" },
                ];
                function rebuildList() {
                    // Remove existing items (keep filter bar)
                    while (list.children.length > 1) list.removeChild(list.lastChild);
                    const opts = [
                        { name: "None", value: "" },
                        ...soundNames
                            .filter(n => _filter === "all" || categoryOf(n) === _filter)
                            .map(n => ({ name: n, value: n })),
                    ];
                    for (const opt of opts) {
                        const isSelected = opt.value === (assigned || "");
                        const item = h(
                            "div",
                            { cls: "sound-opt" + (isSelected ? " selected" : "") },
                            h("span", { cls: "check" }, isSelected ? "✓" : ""),
                            opt.name,
                        );
                        item.addEventListener("mouseenter", () => playSlot("hover"));
                        item.addEventListener("click", () => {
                            sendToHost({ action: "setSoundAssign", slot: slotId, name: opt.value });
                            if (list._scrollHandler) {
                                document.getElementById("scroll").removeEventListener("scroll", list._scrollHandler);
                                list._scrollHandler = null;
                            }
                            list.classList.remove("open");
                            _openSoundPicker = null;
                        });
                        list.appendChild(item);
                    }
                }
                for (const f of filters) {
                    const fBtn = h("button", {
                        cls: "seg-btn sound-filter-btn" + (_filter === f.key ? " active" : ""),
                        onmouseenter: () => playSlot("hover"),
                        onclick: (e) => {
                            e.stopPropagation();
                            playSlot("interact");
                            _filter = f.key;
                            for (const child of filterBar.children) child.classList.remove("active");
                            fBtn.classList.add("active");
                            rebuildList();
                        },
                    }, f.label);
                    filterBar.appendChild(fBtn);
                }
                list.appendChild(filterBar);
                rebuildList();

                btn.addEventListener("click", (e) => {
                    e.stopPropagation();
                    playSlot("interact");
                    if (_openSoundPicker && _openSoundPicker !== list)
                        _openSoundPicker.classList.remove("open");
                    const open = !list.classList.contains("open");
                    list.classList.toggle("open", open);
                    if (open) {
                        // Position after toggling open so offsetWidth is valid
                        const positionList = () => {
                            const rect = btn.getBoundingClientRect();
                            const MARGIN = 6;
                            const vw = window.innerWidth, vh = window.innerHeight;
                            const w = list.offsetWidth || 140;
                            const spaceBelow = vh - rect.bottom - MARGIN;
                            const spaceAbove = rect.top - MARGIN;
                            // Cap height to the roomier side (never past the CSS 200 default)
                            // so the list scrolls internally instead of spilling off-window.
                            list.style.maxHeight =
                                Math.min(200, Math.max(spaceBelow, spaceAbove)) + "px";
                            const menuH = list.offsetHeight;
                            let top;
                            if (menuH <= spaceBelow)        top = rect.bottom + 4;      // room below
                            else if (menuH <= spaceAbove)   top = rect.top - menuH - 4; // flip up
                            else if (spaceBelow >= spaceAbove) top = rect.bottom + 4;   // scroll, down
                            else                            top = rect.top - menuH - 4; // scroll, up
                            top = Math.max(MARGIN, Math.min(top, vh - menuH - MARGIN));
                            list.style.top = top + "px";
                            list.style.left =
                                Math.max(MARGIN, Math.min(rect.right - w, vw - w - MARGIN)) + "px";
                        };
                        positionList();
                        // Reposition while the scroll container scrolls
                        const scrollEl = document.getElementById("scroll");
                        list._scrollHandler = positionList;
                        scrollEl.addEventListener(
                            "scroll",
                            list._scrollHandler,
                        );
                    }
                    _openSoundPicker = open ? list : null;
                });

                wrap.appendChild(btn);
                wrap.appendChild(list);
                return wrap;
            }

            document.addEventListener("click", () => {
                if (_openSoundPicker) {
                    if (_openSoundPicker._scrollHandler) {
                        document
                            .getElementById("scroll")
                            .removeEventListener(
                                "scroll",
                                _openSoundPicker._scrollHandler,
                            );
                        _openSoundPicker._scrollHandler = null;
                    }
                    _openSoundPicker.classList.remove("open");
                    _openSoundPicker = null;
                }
            });

            // ── Sections ───────────────────────────────────────────────────────

            function buildMacros(body) {
                // Dynamic grouping: collect macros by group, preserve order of first appearance
                const groupOrder = [];
                const groups = {};
                (S.macros || []).forEach((m) => {
                    const g = m.group || "ungrouped";
                    if (!groups[g]) { groups[g] = []; groupOrder.push(g); }
                    groups[g].push(m);
                });

                function subRow(sub) {
                    const r = h("div", {
                        cls: "row row-sub",
                        onmouseenter: () => playSlot("hover"),
                    });
                    r.appendChild(h("div", { cls: "row-label" }, sub.label));
                    if (sub.mod)
                        r.appendChild(h("span", { cls: "pill" }, sub.mod));
                    if (sub.bind)
                        r.appendChild(h("span", { cls: "pill" }, sub.bind));
                    // If this sub-item itself has sub-items, show them as nested pills.
                    if (sub.subsubs && sub.subsubs.length) {
                        const nest = h("div", { cls: "row-subsubs" });
                        sub.subsubs.forEach((ss) => {
                            const chip = h(
                                "span",
                                { cls: "pill pill-subsub" },
                                ss.label,
                            );
                            if (ss.mod) chip.title = "mod: " + ss.mod;
                            chip.style.cursor = "context-menu";
                            chip.addEventListener("contextmenu", (e) => {
                                e.preventDefault();
                                e.stopImmediatePropagation();
                                playSlot("interact");
                                const items = [
                                    {
                                        icon: "",
                                        label: "Change Modifier\u2026",
                                        action: () =>
                                            sendToHost({
                                                action: "startModRebind",
                                                id: ss.id,
                                            }),
                                    },
                                ];
                                if (ss.mod) {
                                    items.push("divider");
                                    items.push({
                                        icon: "",
                                        label: "Clear Modifier",
                                        danger: true,
                                        action: () =>
                                            sendToHost({
                                                action: "clearModifier",
                                                id: ss.id,
                                            }),
                                    });
                                }
                                showCtxMenu(
                                    e.clientX,
                                    e.clientY,
                                    items,
                                    ss.label,
                                );
                            });
                            nest.appendChild(chip);
                        });
                        r.appendChild(nest);
                    }
                    r.addEventListener("contextmenu", (e) => {
                        e.preventDefault();
                        e.stopImmediatePropagation();
                        playSlot("interact");
                        const items = [
                            {
                                icon: "",
                                label: "Change Modifier\u2026",
                                action: () =>
                                    sendToHost({
                                        action: "startModRebind",
                                        id: sub.id,
                                    }),
                            },
                        ];
                        if (sub.mod) {
                            items.push("divider");
                            items.push({
                                icon: "",
                                label: "Clear Modifier",
                                danger: true,
                                action: () =>
                                    sendToHost({
                                        action: "clearModifier",
                                        id: sub.id,
                                    }),
                            });
                        }
                        showCtxMenu(e.clientX, e.clientY, items, sub.label);
                    });
                    return r;
                }

                function macroRow(m) {
                    const r = h("div", {
                        cls: "row",
                        onmouseenter: () => playSlot("hover"),
                    });
                    r.appendChild(h("div", { cls: "row-label" }, m.label));
                    if (m.bind)
                        r.appendChild(h("span", { cls: "pill" }, m.bind));
                    if (m.group !== "system") {
                        r.appendChild(
                            toggle(m.enabled, (e) => {
                                sendToHost({
                                    action: "setMacroEnabled",
                                    id: m.id,
                                    value: e.target.checked,
                                });
                            }),
                        );
                    }

                    // Right-click context menu (skip for non-rebindable system macros)
                    if (!(m.group === "system" && !m.systemBind)) {
                        r.addEventListener("contextmenu", (e) => {
                            e.preventDefault();
                            e.stopImmediatePropagation();
                            playSlot("interact");
                            const items = [
                                {
                                    icon: "",
                                    label: "Rebind\u2026",
                                    action: () =>
                                        sendToHost({
                                            action: "startRebind",
                                            id: m.id,
                                            systemBind: m.systemBind || false,
                                        }),
                                },
                            ];
                            if (m.bind) {
                                items.push("divider");
                                items.push({
                                    icon: "",
                                    label: "Reset Bind",
                                    danger: true,
                                    action: () =>
                                        sendToHost({
                                            action: "resetBind",
                                            id: m.id,
                                            systemBind: m.systemBind || false,
                                        }),
                                });
                            }
                            showCtxMenu(e.clientX, e.clientY, items, m.label);
                        });
                    }

                    return r;
                }

                function appendMacro(m) {
                    body.appendChild(macroRow(m));
                    (m.subs || []).forEach((sub) =>
                        body.appendChild(subRow(sub)),
                    );
                }

                groupOrder.forEach((g) => {
                    if (groups[g].length) {
                        body.appendChild(
                            groupLabel(
                                g.charAt(0).toUpperCase() + g.slice(1),
                            ),
                        );
                        groups[g].forEach(appendMacro);
                    }
                });
            }

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

            // ── buildCalibration — user-injected calibration settings ──────────
            function buildCalibration(body) {
                const items = S.userCalibrationSettings || [];
                for (const item of items) {
                    renderUserItem(body, item);
                }
            }

            // ── buildUserSection — custom user-defined sections ────────────────────
            function buildUserSection(body, menu) {
                for (const item of menu.items || []) {
                    renderUserItem(body, item);
                }
            }

            function buildSound(body) {
                // Master toggle
                body.appendChild(
                    row(
                        "Sound Effects",
                        null,
                        toggle(S.soundEnabled ?? true, (e) =>
                            sendToHost({
                                action: "setSoundEnabled",
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
                                        key: "soundEnabled",
                                    }),
                            },
                        ],
                    ),
                );

                // Volume slider
                const volWrap = h("div", {
                    cls: "row slider-row",
                    onmouseenter: () => playSlot("hover"),
                });
                volWrap.addEventListener("contextmenu", (e) => {
                    e.preventDefault();
                    e.stopImmediatePropagation();
                    playSlot("interact");
                    showCtxMenu(
                        e.clientX,
                        e.clientY,
                        [
                            {
                                icon: "",
                                label: "Reset to 100",
                                action: () =>
                                    sendToHost({
                                        action: "resetSetting",
                                        key: "soundVolume",
                                    }),
                            },
                        ],
                        "Volume",
                    );
                });
                const volTop = h("div", { cls: "slider-top" });
                volTop.appendChild(h("div", { cls: "row-label" }, "Volume"));
                const volNum = h("input", {
                    type: "number",
                    min: "0",
                    max: "100",
                    step: "1",
                });
                volNum.value = S.soundVolume ?? 100;
                const volDiv = h("div", { cls: "slider-val" });
                volDiv.appendChild(volNum);
                volTop.appendChild(volDiv);
                volWrap.appendChild(volTop);
                const volSlider = h("input", {
                    type: "range",
                    min: "0",
                    max: "100",
                    step: "1",
                });
                volSlider.value = S.soundVolume ?? 100;
                volSlider.addEventListener("input", () => {
                    volNum.value = volSlider.value;
                });
                volSlider.addEventListener("change", () =>
                    sendToHost({
                        action: "setSoundVolume",
                        value: parseInt(volSlider.value),
                    }),
                );
                volNum.addEventListener("change", () => {
                    const v = Math.max(
                        0,
                        Math.min(100, parseInt(volNum.value) || 0),
                    );
                    volSlider.value = v;
                    sendToHost({ action: "setSoundVolume", value: v });
                });
                volWrap.appendChild(volSlider);
                body.appendChild(volWrap);

                body.appendChild(divider());

                // Slot pickers
                const SLOTS = [
                    { id: "updateAvailable", label: "Update Available" },
                    { id: "alert", label: "Alert / Notice" },
                    { id: "enabled", label: "Macros Enabled" },
                    { id: "disabled", label: "Macros Disabled" },
                    { id: "toggleOn", label: "Toggle On" },
                    { id: "toggleOff", label: "Toggle Off" },
                    { id: "update", label: "Setting Updated" },
                    { id: "reset", label: "Setting Reset" },
                    { id: "interact", label: "Menu Interact" },
                    { id: "hover", label: "Menu Hover" },
                    { id: "back", label: "Menu Back" },
                    { id: "settingsOpen", label: "Settings Open" },
                    { id: "settingsClose", label: "Settings Close" },
                ];

                // Loading sound slots
                const LOAD_SLOTS = [
                    { id: "themeLoaded", label: "Theme Applied" },
                    { id: "load", label: "Loading Screen End" },
                    { id: "launch", label: "Launch Announcement" },
                ];

                // ── Sound Presets (all system slots) ──────────────────────────
                const presets = S.soundPresets || [];
                const ALL_SLOTS = [...LOAD_SLOTS, ...SLOTS];

                // Slots managed by presets (all 14 system slots)
                const presetSlotIds = ALL_SLOTS.map(s => s.id);

                // d_* default mapping for "Default" preset
                const dMap = {
                    themeLoaded: "d_ThemeLoaded", load: "d_LoadEnd", launch: "d_Launch",
                    alert: "d_Alert", enabled: "d_MacrosOn", disabled: "d_MacrosOff",
                    toggleOn: "d_ToggleOn", toggleOff: "d_ToggleOff",
                    update: "d_Update", updateAvailable: "d_UpdateAvailable",
                    reset: "d_Reset", interact: "d_Interact", hover: "d_Hover",
                    back: "d_Back", settingsOpen: "d_SettingsOpen", settingsClose: "d_SettingsClose",
                };
                const defaultAssigns = {};
                for (const sid of presetSlotIds) {
                    if (dMap[sid]) defaultAssigns[sid] = dMap[sid];
                }

                // Detect which preset is currently active
                // Checks all slots the preset defines
                let activePreset = null;
                const sa = S.soundAssign || {};

                // Check if "Default" (all d_*)
                let isDefault = presetSlotIds.length > 0;
                for (const sid of presetSlotIds) {
                    if ((sa[sid] || "") !== (defaultAssigns[sid] || "")) { isDefault = false; break; }
                }
                if (isDefault) activePreset = "default";

                // Check numbered presets
                if (!activePreset) {
                    for (const p of presets) {
                        const pSlots = Object.keys(p.assigns || {});
                        if (pSlots.length === 0) continue;
                        let match = true;
                        for (const sid of pSlots) {
                            const expected = p.assigns[sid] || null;
                            const actual = sa[sid] || null;
                            if (expected !== actual) { match = false; break; }
                        }
                        if (match) { activePreset = String(p.num); break; }
                    }
                }

                body.appendChild(groupLabel("Sound Presets"));
                const presetWrap = h("div", { cls: "seg" });
                // "Custom" option — no preset applied
                const customBtn = h("button", {
                    cls: "seg-btn" + (activePreset === null ? " active" : ""),
                    onmouseenter: () => playSlot("hover"),
                    onclick: () => {
                        sendToHost({ action: "clearSoundPreset", slots: presetSlotIds });
                    },
                }, "Custom");
                presetWrap.appendChild(customBtn);
                // "Default" option — all d_* sounds
                const defaultBtn = h("button", {
                    cls: "seg-btn" + (activePreset === "default" ? " active" : ""),
                    onmouseenter: () => playSlot("hover"),
                    onclick: () => {
                        sendToHost({ action: "setSoundPreset", assigns: defaultAssigns, preset: "default" });
                    },
                }, "Default");
                presetWrap.appendChild(defaultBtn);
                // Numbered presets
                for (const p of presets) {
                    const pBtn = h("button", {
                        cls: "seg-btn" + (activePreset === String(p.num) ? " active" : ""),
                        onmouseenter: () => playSlot("hover"),
                        onclick: () => {
                            sendToHost({ action: "setSoundPreset", assigns: p.assigns, preset: String(p.num) });
                        },
                    }, String(p.num));
                    presetWrap.appendChild(pBtn);
                }
                body.appendChild(row("Preset", "Select a numbered sound set or Custom for individual control", presetWrap));

                // Individual loading slots (always visible)
                const names = S.soundNames || [];
                for (const slot of LOAD_SLOTS) {
                    const assigned = (S.soundAssign || {})[slot.id] || "";
                    body.appendChild(
                        row(
                            slot.label,
                            null,
                            soundPicker(slot.id, assigned, names),
                            "",
                            [
                                {
                                    icon: "",
                                    label: "Play",
                                    action: () =>
                                        sendToHost({
                                            action: "playSlot",
                                            slot: slot.id,
                                        }),
                                },
                                {
                                    icon: "",
                                    label: "Import",
                                    action: () =>
                                        sendToHost({
                                            action: "importSoundForSlot",
                                            slot: slot.id,
                                            label: slot.label,
                                        }),
                                },
                                ...(assigned
                                    ? [
                                          {
                                              icon: "",
                                              label: "Clear",
                                              action: () =>
                                                  sendToHost({
                                                      action: "setSoundAssign",
                                                      slot: slot.id,
                                                      name: "",
                                                  }),
                                          },
                                      ]
                                    : []),
                            ],
                        ),
                    );
                }

                body.appendChild(divider());
                body.appendChild(groupLabel("Event Slots"));
                for (const slot of SLOTS) {
                    const assigned = (S.soundAssign || {})[slot.id] || "";
                    body.appendChild(
                        row(
                            slot.label,
                            null,
                            soundPicker(slot.id, assigned, names),
                            "",
                            [
                                {
                                    icon: "",
                                    label: "Play",
                                    action: () =>
                                        sendToHost({
                                            action: "playSlot",
                                            slot: slot.id,
                                        }),
                                },
                                {
                                    icon: "",
                                    label: "Import",
                                    action: () =>
                                        sendToHost({
                                            action: "importSoundForSlot",
                                            slot: slot.id,
                                            label: slot.label,
                                        }),
                                },
                                ...(assigned
                                    ? [
                                          {
                                              icon: "",
                                              label: "Clear",
                                              action: () =>
                                                  sendToHost({
                                                      action: "setSoundAssign",
                                                      slot: slot.id,
                                                      name: "",
                                                  }),
                                          },
                                      ]
                                    : []),
                            ],
                        ),
                    );
                }

                // User-defined sound slots (from ms.settings.define({ type="soundSlot" }))
                const userSlots = S.userSoundSlots || [];
                if (userSlots.length > 0) {
                    body.appendChild(divider());
                    body.appendChild(groupLabel("Pack Slots"));
                    for (const slot of userSlots) {
                        const assigned = (S.soundAssign || {})[slot.key] || "";
                        body.appendChild(
                            row(
                                slot.label,
                                null,
                                soundPicker(slot.key, assigned, names),
                                "",
                                [
                                    {
                                        icon: "",
                                        label: "Play",
                                        action: () =>
                                            sendToHost({
                                                action: "playSlot",
                                                slot: slot.key,
                                            }),
                                    },
                                    {
                                        icon: "",
                                        label: "Import for this slot",
                                        action: () =>
                                            sendToHost({
                                                action: "importSoundForSlot",
                                                slot: slot.key,
                                                label: slot.label,
                                            }),
                                    },
                                    ...(assigned
                                        ? [
                                              {
                                                  icon: "",
                                                  label: "Clear",
                                                  action: () =>
                                                      sendToHost({
                                                          action: "setSoundAssign",
                                                          slot: slot.key,
                                                          name: "",
                                                      }),
                                              },
                                          ]
                                        : []),
                                ],
                            ),
                        );
                    }
                }

                body.appendChild(divider());
                body.appendChild(
                    btnRow(
                        actionBtn("Import Sound Files\u2026", "", () =>
                            sendToHost({ action: "importSounds" }),
                        ),
                    ),
                );
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

                scroll.appendChild(section("macros", "Macros", buildMacros));
                scroll.appendChild(
                    section("settings", "Settings", buildSettings),
                );
                // Calibration section is only rendered when at least one user
                // setting targets it (via ms.settings.define({ section: "calibration" })).
                if ((S.userCalibrationSettings || []).length > 0) {
                    scroll.appendChild(
                        section("calibration", "Calibration", buildCalibration),
                    );
                }
                scroll.appendChild(section("accessibility", "Accessibility", buildAccessibility));
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
                    section("developer", "Developer", buildDeveloper, false, false),
                );
                scroll.appendChild(section("help", "Help", buildHelp, false, false));

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
            }
            window.renderProfilesPanel = renderProfilesPanel;

            // ── Theme & Sound panel (rendered into #theme-scroll) ───────────
            function renderThemePanel() {
                const el = document.getElementById("theme-scroll");
                if (!el) return;
                el.innerHTML = "";

                // Custom theme toggle
                const customTheme = S.customThemeEnabled !== false;
                el.appendChild(
                    row(
                        "Custom theme",
                        "Load ms_theme.json colors and font",
                        toggle(customTheme, (e) => {
                            sendToHost({
                                action: "setCustomTheme",
                                value: e.target.checked,
                            });
                        }),
                    ),
                );

                // Edit Theme button
                el.appendChild(divider());
                const btnWrap = h("div", { cls: "btn-row" });
                btnWrap.appendChild(
                    actionBtn("Edit Theme File", "", () =>
                        sendToHost({ action: "editTheme" }),
                    ),
                );
                el.appendChild(btnWrap);
                el.appendChild(divider());

                // Sound settings
                buildSound(el);

                // Coming soon note
                const note = h("div", {
                    style: "padding:16px 14px 8px;font-size:11px;color:var(--text3);opacity:0.6;font-style:italic;",
                }, "More theme features coming soon.");
                el.appendChild(note);
            }
            window.renderThemePanel = renderThemePanel;

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

            function applyUIFC(uifcURL) {
                const panel = document.getElementById("panel");
                if (uifcURL) {
                    // Body becomes the full expanded canvas; #panel is centred within it.
                    document.body.style.backgroundImage = `url("${uifcURL}")`;
                    document.body.style.backgroundSize = "100% 100%";
                    document.body.style.backgroundRepeat = "no-repeat";
                    document.body.style.padding = "12.5%";
                    document.body.style.boxSizing = "border-box";
                    if (panel) panel.style.height = "100%";
                } else {
                    document.body.style.backgroundImage = "";
                    document.body.style.backgroundSize = "";
                    document.body.style.backgroundRepeat = "";
                    document.body.style.padding = "";
                    document.body.style.boxSizing = "";
                    if (panel) panel.style.height = "";
                }
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

                // ── Radius, font, UIFC ──────────────────────────────────
                if (t.radius !== undefined) {
                    r.setProperty("--radius", t.radius + "px");
                    r.setProperty(
                        "--radius-s",
                        Math.max(0, t.radius - 1) + "px",
                    );
                }
                applyFont(t.font, t.fontURL);
                applyUIFC(t.uifcURL);
            }

            // ── receiveState ───────────────────────────────────────────────────
            function receiveState(state) {
                S = state;
                applyTheme(S.theme);
                const btn = document.getElementById("btn-toggle-macros");
                const enabled = S.macrosEnabled ?? false;
                if (btn) {
                    btn.textContent = enabled ? "Macros: ON" : "Macros: OFF";
                    btn.dataset.on = enabled ? "1" : "0";
                    btn.style.color = enabled ? "var(--success)" : "var(--danger)";
                }
                const verEl = document.getElementById("rail-version");
                if (verEl && S.msVersion) verEl.textContent = "v" + S.msVersion;
                syncQRChecks(S.qrOptions);
                render();
                renderProfilesPanel();
                renderThemePanel();
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
            window.toggleQR = toggleQR;
    })();
