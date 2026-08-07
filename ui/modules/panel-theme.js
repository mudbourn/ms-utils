    /* panel: theme & sound */
    (function() {
    "use strict";

    /* ── panel-theme.js ─────────────────────────────────────────────────────
     *
     * The Theme & Sound panel. This was a forty-line renderThemePanel() at the
     * bottom of panel-settings.js — a custom-theme toggle, an "Edit Theme File"
     * button that opened JSON in a text editor, and the sound section.
     *
     * It is now three tabs off the shared ui-tabs.js factory:
     *
     *   Theme    live colour pickers over the ms_theme.json keys, radius, font
     *   Sounds   per-slot assignment, preview and import
     *   Share    theme and sounds exported as SEPARATE typed packages
     *
     * Editing is optimistic: dragging a colour repaints the shell immediately
     * from a local merge, and only the committed value (on `change`) goes to
     * Lua. So a drag is never a round-trip per frame, but what you see during
     * the drag is exactly what settingsApplyTheme will render afterwards.
     *
     * Backgrounds and gradients are deliberately absent — that model is still
     * undecided, and it is not going to be UIFC's.
     *
     * Building blocks come from window.msUI (panel-settings.js). This panel
     * owns no widget vocabulary of its own beyond the colour field.
     */

    // ── State ────────────────────────────────────────────────────────────
    let S = {};
    // Local edits not yet reflected back in S — the theme repaints from
    // S.theme + this, so a second colour tweak doesn't undo the first.
    let _pending = {};
    let _openSoundPicker = null;
    let _tabs = null;

    function ui() { return window.msUI || null; }
    function playSlot(slot) { if (window.playSlot) window.playSlot(slot); }
    function sendToHost(msg) { if (window.sendToHost) window.sendToHost(msg); }

    // ── Theme keys ───────────────────────────────────────────────────────
    // The eleven colours loadTheme() accepts. Everything else the theme can
    // carry (text2, border, the glows) is derived from these unless the user
    // has hand-written an override into ms_theme.json — the editor doesn't
    // offer those, because deriving them is what makes a theme cohere.
    const COLOR_KEYS = [
        { key: "bg",       label: "Background",    hint: "Panel backdrop" },
        { key: "surface",  label: "Surface",       hint: "Headers, rails, cards" },
        { key: "surface2", label: "Surface (alt)", hint: "Raised and inset areas" },
        { key: "hover",    label: "Hover",         hint: "Row and button hover" },
        { key: "accent",   label: "Accent",        hint: "Active tabs, focus, links" },
        { key: "accentHi", label: "Accent (hi)",   hint: "Accent hover state" },
        { key: "text",     label: "Text",          hint: "Dimmer text is derived from this" },
        { key: "success",  label: "Success",       hint: "Macros on, healthy status" },
        { key: "warning",  label: "Warning",       hint: "Cautions" },
        { key: "danger",   label: "Danger",        hint: "Errors, destructive actions" },
        { key: "dangerBg", label: "Danger (bg)",   hint: "Backdrop behind danger text" },
    ];

    // ── Live preview ─────────────────────────────────────────────────────
    // The merged theme as it would look with the pending edits applied.
    function previewTheme() {
        const t = Object.assign({}, S.theme || {}, _pending);
        // _shellApplyTheme paints the chrome the settings panel doesn't own
        // (console, watcher, keys, window); settingsApplyTheme adds the
        // derived text/border/glow values on top. Same order Lua uses.
        if (window._shellApplyTheme) window._shellApplyTheme(t);
        else if (window.settingsApplyTheme) window.settingsApplyTheme(t);
    }

    // ── Committing ───────────────────────────────────────────────────────
    // macOS keeps the system colour panel open and fires `change` alongside
    // `input` the whole time you drag in it, so a naive commit-on-change would
    // be one Lua write and one full re-render per frame — with the swatch you
    // are dragging replaced out from under you. Writes are therefore debounced,
    // and the incoming state push is ignored while an edit is in flight.
    const SETTLE_MS = 350;
    let _commitTimers = {};
    let _editingUntil = 0;
    let _rerenderTimer = null;

    function touchEditing() { _editingUntil = Date.now() + SETTLE_MS * 2; }

    function commit(key, value) {
        _pending[key] = value;
        previewTheme();
        touchEditing();
        clearTimeout(_commitTimers[key]);
        _commitTimers[key] = setTimeout(() => {
            delete _commitTimers[key];
            sendToHost({ action: "setThemeKey", key: key, value: value });
        }, SETTLE_MS);
    }

    // True while the user is mid-edit, so a state push shouldn't rebuild the
    // controls they are still holding.
    function editing() {
        return Date.now() < _editingUntil || Object.keys(_commitTimers).length > 0;
    }

    function isHex(s) { return /^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/.test(s); }

    // #rgb → #rrggbb, because <input type="color"> only accepts the long form.
    function longHex(s) {
        if (!isHex(s)) return null;
        const b = s.slice(1);
        return b.length === 3 ? "#" + b[0]+b[0]+b[1]+b[1]+b[2]+b[2] : "#" + b.toLowerCase();
    }

    // ── Colour field ─────────────────────────────────────────────────────
    // A swatch and a hex box over the same value. The swatch previews as it
    // drags and commits when released; the box commits on change.
    function colorField(key, current) {
        const { h } = ui();
        const wrap = h("div", { cls: "color-field" });

        const swatch = h("input", { type: "color", cls: "color-swatch" });
        const hex    = h("input", { type: "text", cls: "color-hex", spellcheck: "false", maxlength: "7" });

        const long = longHex(current) || "#000000";
        swatch.value = long;
        hex.value    = current || "";

        swatch.addEventListener("input", () => {
            hex.value = swatch.value;
            _pending[key] = swatch.value;
            previewTheme();
            touchEditing();
        });
        swatch.addEventListener("change", () => commit(key, swatch.value));

        hex.addEventListener("change", () => {
            const v = hex.value.trim();
            if (v === "") { swatch.value = "#000000"; commit(key, ""); return; }
            const l = longHex(v);
            if (!l) { hex.value = current || ""; playSlot("back"); return; }
            swatch.value = l;
            commit(key, v);
        });

        wrap.appendChild(swatch);
        wrap.appendChild(hex);
        return wrap;
    }

    // ── Theme tab ────────────────────────────────────────────────────────
    function buildTheme(body) {
        const { h, row, toggle, divider, groupLabel, btnRow, actionBtn } = ui();
        const theme = Object.assign({}, S.theme || {}, _pending);
        const set   = S.themeSet || {};

        const customTheme = S.customThemeEnabled !== false;
        body.appendChild(
            row(
                "Custom theme",
                "Off reverts every colour, the font and the sound set to stock",
                toggle(customTheme, (e) =>
                    sendToHost({ action: "setCustomTheme", value: e.target.checked }),
                ),
            ),
        );

        if (!customTheme) {
            body.appendChild(h("div", { cls: "theme-note" },
                "Turn custom theme on to edit colours."));
            return;
        }

        body.appendChild(divider());
        body.appendChild(groupLabel("Colours"));

        for (const c of COLOR_KEYS) {
            const value = theme[c.key] || "";
            body.appendChild(
                row(
                    c.label,
                    set[c.key] ? c.hint : c.hint + " · default",
                    colorField(c.key, value),
                    "",
                    [{
                        icon: "",
                        label: "Reset to default",
                        action: () => { delete _pending[c.key]; commit(c.key, ""); },
                    }],
                ),
            );
        }

        // ── Radius ───────────────────────────────────────────────────────
        body.appendChild(divider());
        body.appendChild(groupLabel("Shape"));

        const radius = theme.radius ?? 8;
        const radWrap = h("div", { cls: "row slider-row", onmouseenter: () => playSlot("hover") });
        const radTop  = h("div", { cls: "slider-top" });
        radTop.appendChild(h("div", { cls: "row-label" }, "Corner radius"));
        const radNum = h("input", { type: "number", min: "0", max: "40", step: "1" });
        radNum.value = radius;
        const radVal = h("div", { cls: "slider-val" });
        radVal.appendChild(radNum);
        radTop.appendChild(radVal);
        radWrap.appendChild(radTop);

        const radSlider = h("input", { type: "range", min: "0", max: "40", step: "1" });
        radSlider.value = radius;
        radSlider.addEventListener("input", () => {
            radNum.value = radSlider.value;
            _pending.radius = parseInt(radSlider.value, 10);
            previewTheme();
            touchEditing();
        });
        radSlider.addEventListener("change", () =>
            commit("radius", parseInt(radSlider.value, 10)));
        radNum.addEventListener("change", () => {
            const v = Math.max(0, Math.min(40, parseInt(radNum.value, 10) || 0));
            radNum.value = v;
            radSlider.value = v;
            commit("radius", v);
        });
        radWrap.appendChild(radSlider);
        body.appendChild(radWrap);

        // ── Font ─────────────────────────────────────────────────────────
        // Values are what ms_theme.json stores: a path under ui/fonts/ for a
        // font file (Lua turns it into an @font-face), or a bare family name.
        body.appendChild(divider());
        body.appendChild(groupLabel("Type"));

        const fonts   = S.themeFonts || [];
        const current = S.themeFontValue || "";
        const select  = h("select", { cls: "theme-select" });
        if (!fonts.some((f) => f.value === current) && current) {
            select.appendChild(h("option", { value: current }, current + " (from file)"));
        }
        for (const f of fonts) {
            select.appendChild(h("option", { value: f.value }, f.label));
        }
        select.value = current;
        select.addEventListener("mouseenter", () => playSlot("hover"));
        select.addEventListener("change", () =>
            sendToHost({ action: "setThemeKey", key: "font", value: select.value }));
        body.appendChild(
            row("Font", "Files in ui/fonts/ travel with a theme package", select),
        );

        // ── Escape hatches ───────────────────────────────────────────────
        body.appendChild(divider());
        body.appendChild(
            btnRow(
                actionBtn("Edit Theme File…", "", () =>
                    sendToHost({ action: "editTheme" })),
                actionBtn("Reset Theme", "danger", () =>
                    sendToHost({ action: "resetTheme" })),
            ),
        );
        body.appendChild(h("div", { cls: "theme-note" },
            "Overrides the editor doesn't offer — text2, border, the glow "
            + "colours — can be hand-written into ms_theme.json and win over "
            + "the values derived here."));
    }

    // ── Sound picker ─────────────────────────────────────────────────────
    // Moved verbatim from panel-settings.js, with one fix: the reposition
    // handler now attaches to whichever scroll container the picker was
    // rendered into, rather than to the settings panel's #scroll — which is
    // not the element these rows have scrolled inside since the sound section
    // moved out of the settings list.
    function soundPicker(slotId, assigned, soundNames, scrollEl) {
        const { h } = ui();
        const display = assigned || "off";
        const wrap = h("div", { cls: "sound-picker-wrap" });
        const btn = h(
            "div",
            { cls: "sound-picker-btn", onmouseenter: () => playSlot("hover") },
            display,
            h("span", { cls: "arrow" }, "▾"),
        );
        const list = h("div", { cls: "sound-list" });
        // The outside-click handler closes whatever is open without knowing
        // which container it was rendered into, so it carries its own teardown.
        list._detach = () => detach();

        let _filter = "all"; // "all" | "default" | "active" | "macro"
        function categoryOf(name) {
            if (name.startsWith("d_")) return "default";
            if (name.startsWith("m_")) return "macro";
            if (name.startsWith("a_")) return "active";
            return "other";
        }

        function detach() {
            if (list._scrollHandler && scrollEl) {
                scrollEl.removeEventListener("scroll", list._scrollHandler);
                list._scrollHandler = null;
            }
        }

        const filterBar = h("div", { cls: "sound-filter-bar" });
        const filters = [
            { key: "all", label: "All" },
            { key: "default", label: "Default" },
            { key: "active", label: "Active" },
            { key: "macro", label: "Macro" },
        ];
        function rebuildList() {
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
                    detach();
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
                // Position after toggling open so offsetWidth is valid.
                const positionList = () => {
                    const rect = btn.getBoundingClientRect();
                    const MARGIN = 6;
                    const vw = window.innerWidth, vh = window.innerHeight;
                    const w = list.offsetWidth || 140;
                    const spaceBelow = vh - rect.bottom - MARGIN;
                    const spaceAbove = rect.top - MARGIN;
                    // Cap height to the roomier side (never past the CSS 200
                    // default) so the list scrolls internally instead of
                    // spilling off-window.
                    list.style.maxHeight =
                        Math.min(200, Math.max(spaceBelow, spaceAbove)) + "px";
                    const menuH = list.offsetHeight;
                    let top;
                    if (menuH <= spaceBelow)           top = rect.bottom + 4;
                    else if (menuH <= spaceAbove)      top = rect.top - menuH - 4;
                    else if (spaceBelow >= spaceAbove) top = rect.bottom + 4;
                    else                               top = rect.top - menuH - 4;
                    top = Math.max(MARGIN, Math.min(top, vh - menuH - MARGIN));
                    list.style.top = top + "px";
                    list.style.left =
                        Math.max(MARGIN, Math.min(rect.right - w, vw - w - MARGIN)) + "px";
                };
                positionList();
                if (scrollEl) {
                    list._scrollHandler = positionList;
                    scrollEl.addEventListener("scroll", list._scrollHandler);
                }
            } else {
                detach();
            }
            _openSoundPicker = open ? list : null;
        });

        wrap.appendChild(btn);
        wrap.appendChild(list);
        return wrap;
    }

    document.addEventListener("click", () => {
        if (_openSoundPicker) {
            if (_openSoundPicker._detach) _openSoundPicker._detach();
            _openSoundPicker.classList.remove("open");
            _openSoundPicker = null;
        }
    });

    // ── Sound tab ────────────────────────────────────────────────────────
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
        { id: "shutdown", label: "Shutdown" },
        // Ships unassigned and has no d_*/a_* sample, so it is deliberately
        // absent from D_MAP and the preset lists — leaving it empty falls the
        // restart back to the shutdown sound rather than to silence.
        { id: "restart", label: "Restart" },
    ];

    const LOAD_SLOTS = [
        { id: "themeLoaded", label: "Theme Applied" },
        { id: "load", label: "Loading Screen End" },
        { id: "launch", label: "Launch Announcement" },
    ];

    // The d_* mapping the "Default" preset restores.
    const D_MAP = {
        themeLoaded: "d_ThemeLoaded", load: "d_LoadEnd", launch: "d_Launch",
        alert: "d_Alert", enabled: "d_MacrosOn", disabled: "d_MacrosOff",
        toggleOn: "d_ToggleOn", toggleOff: "d_ToggleOff",
        update: "d_Update", updateAvailable: "d_UpdateAvailable",
        reset: "d_Reset", interact: "d_Interact", hover: "d_Hover",
        back: "d_Back", settingsOpen: "d_SettingsOpen", settingsClose: "d_SettingsClose",
        shutdown: "d_Shutdown",
    };

    // Preview and import used to be right-click-only. They are the two things
    // you do most while assigning sounds, so they get their own controls.
    // Sound files, indexed by name. Slots point at these; several slots can
    // point at one file, which is why removal is keyed on the name and not
    // on the slot that happens to be showing it.
    function entryFor(name) {
        if (!name) return null;
        const entries = S.soundEntries || [];
        for (const e of entries) if (e.name === name) return e;
        return null;
    }

    // The one rule behind every X in this tab: a default is the floor a slot
    // falls back to, so it can never be removed. Clearing a non-default drops
    // the slot back to its default, which is how the control ends up greyed.
    function removable(name) {
        const e = entryFor(name);
        return !!(e && e.removable);
    }

    function removeBtn(name, onRemoved) {
        const { h } = ui();
        const can = removable(name);
        const b = h("button", {
            cls: "slot-btn slot-btn-danger",
            title: can ? "Remove “" + name + "”"
                       : (name ? "Default sounds cannot be removed"
                               : "Nothing assigned to remove"),
            onmouseenter: () => { if (can) playSlot("hover"); },
            onclick: (e) => {
                e.stopPropagation();
                if (!can) return;
                sendToHost({ action: "removeSound", name: name });
                if (onRemoved) onRemoved();
            },
        });
        b.disabled = !can;
        const svg = typeof window.icon === "function" ? window.icon("close") : "";
        if (svg && svg.indexOf("<path") !== -1) b.innerHTML = svg;
        else b.textContent = "✕";
        return b;
    }

    function slotButtons(slotId, label) {
        const { h } = ui();
        const wrap = h("div", { cls: "slot-btns" });
        // h() turns a string child into a text node, so an icon has to go in
        // as markup. The glyph is kept as the fallback for the case where the
        // shell's icon map has no such name.
        const mk = (iconName, glyph, title, action) => {
            const b = h("button", {
                cls: "slot-btn",
                title: title,
                onmouseenter: () => playSlot("hover"),
                onclick: (e) => { e.stopPropagation(); action(); },
            });
            const svg = typeof window.icon === "function" ? window.icon(iconName) : "";
            if (svg && svg.indexOf("<path") !== -1) b.innerHTML = svg;
            else b.textContent = glyph;
            return b;
        };
        wrap.appendChild(mk("play", "▶", "Preview",
            () => sendToHost({ action: "playSlot", slot: slotId })));
        wrap.appendChild(mk("download", "⤓", "Import a file for this slot",
            () => sendToHost({ action: "importSoundForSlot", slot: slotId, label: label })));
        // Removes the file this slot points at, not the slot itself — the
        // slot is fixed, and afterwards it shows its default.
        wrap.appendChild(removeBtn((S.soundAssign || {})[slotId] || ""));
        return wrap;
    }

    function slotRow(slotId, label, names, scrollEl) {
        const { h, row } = ui();
        const assigned = (S.soundAssign || {})[slotId] || "";
        const ctl = h("div", { cls: "slot-ctl" });
        ctl.appendChild(soundPicker(slotId, assigned, names, scrollEl));
        ctl.appendChild(slotButtons(slotId, label));
        return row(label, null, ctl, "", [
            { icon: "", label: "Play",
              action: () => sendToHost({ action: "playSlot", slot: slotId }) },
            { icon: "", label: "Import",
              action: () => sendToHost({ action: "importSoundForSlot", slot: slotId, label: label }) },
            ...(assigned ? [{
                icon: "", label: "Clear",
                action: () => sendToHost({ action: "setSoundAssign", slot: slotId, name: "" }),
            }] : []),
        ]);
    }

    function buildSound(body, scrollEl) {
        const { h, row, toggle, divider, groupLabel, btnRow, actionBtn, showCtxMenu } = ui();

        body.appendChild(
            row(
                "Sound Effects",
                null,
                toggle(S.soundEnabled ?? true, (e) =>
                    sendToHost({ action: "setSoundEnabled", value: e.target.checked })),
                "",
                [{ icon: "", label: "Reset to default",
                   action: () => sendToHost({ action: "resetSetting", key: "soundEnabled" }) }],
            ),
        );

        // ── Volume ───────────────────────────────────────────────────────
        const volWrap = h("div", { cls: "row slider-row", onmouseenter: () => playSlot("hover") });
        volWrap.addEventListener("contextmenu", (e) => {
            e.preventDefault();
            e.stopImmediatePropagation();
            playSlot("interact");
            showCtxMenu(e.clientX, e.clientY, [{
                icon: "", label: "Reset to 100",
                action: () => sendToHost({ action: "resetSetting", key: "soundVolume" }),
            }], "Volume");
        });
        const volTop = h("div", { cls: "slider-top" });
        volTop.appendChild(h("div", { cls: "row-label" }, "Volume"));
        const volNum = h("input", { type: "number", min: "0", max: "100", step: "1" });
        volNum.value = S.soundVolume ?? 100;
        const volDiv = h("div", { cls: "slider-val" });
        volDiv.appendChild(volNum);
        volTop.appendChild(volDiv);
        volWrap.appendChild(volTop);
        const volSlider = h("input", { type: "range", min: "0", max: "100", step: "1" });
        volSlider.value = S.soundVolume ?? 100;
        volSlider.addEventListener("input", () => { volNum.value = volSlider.value; });
        volSlider.addEventListener("change", () =>
            sendToHost({ action: "setSoundVolume", value: parseInt(volSlider.value, 10) }));
        volNum.addEventListener("change", () => {
            const v = Math.max(0, Math.min(100, parseInt(volNum.value, 10) || 0));
            volSlider.value = v;
            sendToHost({ action: "setSoundVolume", value: v });
        });
        volWrap.appendChild(volSlider);
        body.appendChild(volWrap);

        body.appendChild(divider());

        // ── Presets ──────────────────────────────────────────────────────
        const presets   = S.soundPresets || [];
        const ALL_SLOTS = [...LOAD_SLOTS, ...SLOTS];
        const presetSlotIds = ALL_SLOTS.map(s => s.id);

        const defaultAssigns = {};
        for (const sid of presetSlotIds) {
            if (D_MAP[sid]) defaultAssigns[sid] = D_MAP[sid];
        }

        // Which preset is live is inferred from the assignments themselves —
        // any hand-edit away from a preset lands you back on "Custom".
        const sa = S.soundAssign || {};
        let activePreset = null;
        let isDefault = presetSlotIds.length > 0;
        for (const sid of presetSlotIds) {
            if ((sa[sid] || "") !== (defaultAssigns[sid] || "")) { isDefault = false; break; }
        }
        if (isDefault) activePreset = "default";
        if (!activePreset) {
            for (const p of presets) {
                const pSlots = Object.keys(p.assigns || {});
                if (pSlots.length === 0) continue;
                let match = true;
                for (const sid of pSlots) {
                    if ((p.assigns[sid] || null) !== (sa[sid] || null)) { match = false; break; }
                }
                if (match) { activePreset = String(p.num); break; }
            }
        }

        body.appendChild(groupLabel("Sound Presets"));
        const presetWrap = h("div", { cls: "seg" });
        presetWrap.appendChild(h("button", {
            cls: "seg-btn" + (activePreset === null ? " active" : ""),
            onmouseenter: () => playSlot("hover"),
            onclick: () => sendToHost({ action: "clearSoundPreset", slots: presetSlotIds }),
        }, "Custom"));
        presetWrap.appendChild(h("button", {
            cls: "seg-btn" + (activePreset === "default" ? " active" : ""),
            onmouseenter: () => playSlot("hover"),
            onclick: () => sendToHost({
                action: "setSoundPreset", assigns: defaultAssigns, preset: "default" }),
        }, "Default"));
        for (const p of presets) {
            presetWrap.appendChild(h("button", {
                cls: "seg-btn" + (activePreset === String(p.num) ? " active" : ""),
                onmouseenter: () => playSlot("hover"),
                onclick: () => sendToHost({
                    action: "setSoundPreset", assigns: p.assigns, preset: String(p.num) }),
            }, String(p.num)));
        }
        body.appendChild(row(
            "Preset",
            "Select a numbered sound set, or Custom for individual control",
            presetWrap,
        ));

        // ── Slots ────────────────────────────────────────────────────────
        const names = S.soundNames || [];

        for (const slot of LOAD_SLOTS) {
            body.appendChild(slotRow(slot.id, slot.label, names, scrollEl));
        }

        body.appendChild(divider());
        body.appendChild(groupLabel("Event Slots"));
        for (const slot of SLOTS) {
            body.appendChild(slotRow(slot.id, slot.label, names, scrollEl));
        }

        // Slots declared by the pack via ms.settings.define({ type = "soundSlot" }).
        const userSlots = S.userSoundSlots || [];
        if (userSlots.length > 0) {
            body.appendChild(divider());
            body.appendChild(groupLabel("Pack Slots"));
            for (const slot of userSlots) {
                body.appendChild(slotRow(slot.key, slot.label, names, scrollEl));
            }
        }

        // ── Sound library ────────────────────────────────────────────────
        // The sections above list *slots* — a fixed set of events, each
        // pointing at a file. This lists the files themselves, one row per
        // sound, so a sound that no slot uses is still visible and still
        // removable. Adding a sound adds a row here; removing one takes its
        // row with it. Nothing is enumerated by hand.
        const entries = S.soundEntries || [];
        const byKind = (k) => entries.filter((e) => e.kind === k);

        const soundEntryRow = (e) => {
            const ctl = h("div", { cls: "slot-ctl" });
            ctl.appendChild(h("span", { cls: "snd-entry-kind" }, e.kind));
            const btns = h("div", { cls: "slot-btns" });
            const play = h("button", {
                cls: "slot-btn",
                title: "Preview “" + e.name + "”",
                onmouseenter: () => playSlot("hover"),
                onclick: (ev) => {
                    ev.stopPropagation();
                    sendToHost({ action: "previewSound", name: e.name });
                },
            });
            const psvg = typeof window.icon === "function" ? window.icon("play") : "";
            if (psvg && psvg.indexOf("<path") !== -1) play.innerHTML = psvg;
            else play.textContent = "▶";
            btns.appendChild(play);
            btns.appendChild(removeBtn(e.name));
            ctl.appendChild(btns);
            return row(e.name, null, ctl, "", [
                { icon: "", label: "Play",
                  action: () => sendToHost({ action: "previewSound", name: e.name }) },
                ...(e.removable ? [{
                    icon: "", label: "Remove",
                    action: () => sendToHost({ action: "removeSound", name: e.name }),
                }] : []),
            ]);
        };

        const macroEntries = byKind("macro");
        body.appendChild(divider());
        body.appendChild(groupLabel("Macro Sounds"));
        if (macroEntries.length === 0) {
            body.appendChild(h("div", { cls: "theme-note" },
                "Sounds in sounds/macro/ appear here, one row each. Macros play "
                + "them by name with ms.sound(\"m_Name\") — they have no slot, "
                + "because a macro chooses its own sound at the call."));
        } else {
            for (const e of macroEntries) body.appendChild(soundEntryRow(e));
        }

        const importedEntries = byKind("imported");
        if (importedEntries.length > 0) {
            body.appendChild(divider());
            body.appendChild(groupLabel("Imported Sounds"));
            for (const e of importedEntries) body.appendChild(soundEntryRow(e));
        }

        body.appendChild(divider());
        body.appendChild(
            btnRow(actionBtn("Import Sound Files…", "", () =>
                sendToHost({ action: "importSounds" }))),
        );

        // ── Export bundling ──────────────────────────────────────────────
        body.appendChild(divider());
        body.appendChild(row(
            "Bundle Sounds With Theme",
            "Include your sounds and their slot assignments in theme exports",
            toggle(S.bundleSoundsWithTheme ?? true, (e) =>
                sendToHost({ action: "setBundleSoundsWithTheme", value: e.target.checked })),
            "",
            [{ icon: "", label: "Reset to default",
               action: () => sendToHost({ action: "setBundleSoundsWithTheme", value: true }) }],
        ));
    }

    // ── Share tab ────────────────────────────────────────────────────────
    // Sound is a theme aspect: a theme is the whole sensory surface, so a
    // theme package carries its audio and the slot map that gives that audio
    // meaning. The sound package still exists for sharing a set on its own,
    // but it is the narrower thing, not the co-equal one.
    function buildShare(body) {
        const { h, divider, groupLabel, btnRow, actionBtn } = ui();

        body.appendChild(groupLabel("Export"));

        body.appendChild(h("div", { cls: "theme-note" },
            "A theme package carries ms_theme.json, any font files in "
            + "ui/fonts/, and — unless you turn it off under Sounds — your "
            + "sounds and their slot assignments. Export Sounds is for "
            + "sharing a sound set on its own, without the colours."));

        body.appendChild(btnRow(
            actionBtn("Export Theme…", "", () =>
                sendToHost({ action: "exportPackage", type: "theme" })),
            actionBtn("Export Sounds…", "", () =>
                sendToHost({ action: "exportPackage", type: "sound" })),
        ));

        body.appendChild(divider());
        body.appendChild(groupLabel("Import"));
        body.appendChild(h("div", { cls: "theme-note" },
            "Importing a package replaces the files it carries, keeping a .bak "
            + "of anything it overwrites. A package outside the validated "
            + "library asks before it installs."));
        body.appendChild(btnRow(
            actionBtn("Import Package…", "", () =>
                sendToHost({ action: "importPackage" })),
        ));
    }

    // ── Tabs ─────────────────────────────────────────────────────────────
    function tabs() {
        if (_tabs) return _tabs;
        const panel = document.querySelector(".panel-theme");
        if (!panel || !window.createTabs) return null;
        _tabs = window.createTabs({
            root: panel,
            tabSelector: ".ttab",
            sectionSelector: ".ttab-section",
            tabKey: (el) => el.dataset.ttab,
            sectionKey: (el) => el.dataset.tsection,
            onSame: () => playSlot("back"),
            onSwitch: () => playSlot("interact"),
        });
        return _tabs;
    }

    function switchThemeTab(tab) {
        const t = tabs();
        if (t) t.switch(tab);
    }
    window.switchThemeTab = switchThemeTab;

    // ── Render ───────────────────────────────────────────────────────────
    function renderInto(id, buildFn) {
        const el = document.getElementById(id);
        if (!el) return;
        const scrollTop = el.scrollTop;
        el.innerHTML = "";
        buildFn(el, el);
        el.scrollTop = scrollTop;
    }

    function renderThemePanel(state) {
        if (state) S = state;
        if (!ui()) return; // panel-settings.js hasn't published the kit yet

        // Sounds and Share are never mid-drag, so they always take the push.
        renderInto("sound-scroll", buildSound);
        renderInto("share-scroll", buildShare);

        // The theme tab holds live controls. Rebuilding it during a drag would
        // swap out the swatch or slider the user is still holding, so the push
        // is deferred until the edit settles — the panel is already showing the
        // right thing locally in the meantime.
        if (editing()) {
            clearTimeout(_rerenderTimer);
            _rerenderTimer = setTimeout(() => renderThemePanel(), SETTLE_MS);
            return;
        }
        _pending = {};
        renderInto("theme-scroll", buildTheme);
        const t = tabs();
        if (t) t.refresh();
    }
    window.renderThemePanel = renderThemePanel;

    })();
