    /* panel: theme & sound */
    (function() {
    "use strict";

    /* -- panel-theme.js --
     *
     * The Theme & Sound panel. This was a forty-line renderThemePanel() at the
     * bottom of panel-settings.js, a custom-theme toggle, an "Edit Theme File"
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
     * Backgrounds and gradients are deliberately absent, that model is still
     * undecided, and it is not going to be UIFC's.
     *
     * Building blocks come from window.msUI (panel-settings.js). This panel
     * owns no widget vocabulary of its own beyond the colour field.
     */

    // -- State --
    let S = {};
    // Local edits not yet reflected back in S, the theme repaints from
    // S.theme + this, so a second colour tweak doesn't undo the first.
    let _pending = {};
    let _openSoundPicker = null;
    let _tabs = null;

    function ui() { return window.msUI || null; }
    function playSlot(slot) { if (window.playSlot) window.playSlot(slot); }
    function sendToHost(msg) { if (window.sendToHost) window.sendToHost(msg); }

    // -- Theme keys --
    // The eleven colours loadTheme() accepts. Everything else the theme can
    // carry (text2, border, the glows) is derived from these unless the user
    // has hand-written an override into ms_theme.json, the editor doesn't
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

    // -- Live preview --
    // The merged theme as it would look with the pending edits applied.
    function previewTheme() {
        const t = Object.assign({}, S.theme || {}, _pending);
        // _shellApplyTheme paints the chrome the settings panel doesn't own
        // (console, watcher, keys, window); settingsApplyTheme adds the
        // derived text/border/glow values on top. Same order Lua uses.
        if (window._shellApplyTheme) window._shellApplyTheme(t);
        else if (window.settingsApplyTheme) window.settingsApplyTheme(t);
    }

    // -- Committing --
    // macOS keeps the system colour panel open and fires `change` alongside
    // `input` the whole time you drag in it, so a naive commit-on-change would
    // be one Lua write and one full re-render per frame, with the swatch you
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

    // #rgb -> #rrggbb, because <input type="color"> only accepts the long form.
    function longHex(s) {
        if (!isHex(s)) return null;
        const b = s.slice(1);
        return b.length === 3 ? "#" + b[0]+b[0]+b[1]+b[1]+b[2]+b[2] : "#" + b.toLowerCase();
    }

    // -- Colour field --
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

    // -- Sections --
    // Every tab in this panel is laid out the way the settings panel is: a
    // sticky heading naming the group, and its controls in a card. The tabs
    // used to be one flat run of rows with uppercase labels floating in it,
    // which read as a list rather than as settings.
    function sec(root, id, title, desc, buildFn) {
        root.appendChild(ui().section(id, title, buildFn, desc));
    }

    // -- Installed library --
    // The shelf of hotswappable slices the host keeps under data/library. Each
    // panel that owns a kind (theme and sound here, macro in panel-macros.js)
    // renders a manager section: the list plus a "save current" button. The
    // list repaints out-of-band whenever the host pushes it, so it is held in
    // module state keyed by kind and re-filled into a stable container.
    const LIB_STATE = { theme: [], sound: [] };
    const LIB_NOUN  = { theme: "theme", sound: "sound pack" };

    function fillLibList(kind, wrap) {
        const { h, row, btnRow, actionBtn } = ui();
        wrap.innerHTML = "";

        const entries = LIB_STATE[kind] || [];
        if (!entries.length) {
            wrap.appendChild(h("div", { cls: "theme-note" },
                "Nothing here yet. Install a " + LIB_NOUN[kind] + " from Browse, "
                + "or save your current one below."));
            return;
        }

        for (const e of entries) {
            const meta = [e.origin, e.version].filter(Boolean).join(" · ");
            wrap.appendChild(row(e.name, meta || null, btnRow(
                actionBtn("Activate", "accent", () =>
                    window.msLibraryClient.activate(kind, e.slug, e.name)),
                actionBtn("Delete", "danger", async () => {
                    const r = await window.openModal(
                        "Delete " + e.name + "?",
                        "Removes it from your library. Anything already applied stays in place.",
                        "Delete", "Cancel");
                    if (r.confirmed) window.msLibraryClient.remove(kind, e.slug);
                }),
            )));
        }
    }

    function repaintLib(kind) {
        const wrap = document.getElementById("library-list-" + kind);
        if (wrap) fillLibList(kind, wrap);
    }

    function librarySection(root, kind, title, desc, captureLabel) {
        const { h, btnRow, actionBtn } = ui();

        sec(root, "installed-" + kind, title, desc, (body) => {
            const list = h("div", { id: "library-list-" + kind, cls: "library-list" });
            fillLibList(kind, list);
            body.appendChild(list);

            body.appendChild(btnRow(
                actionBtn(captureLabel, "", async () => {
                    const r = await window.openModal(
                        "Save current " + LIB_NOUN[kind],
                        "Name it so you can hotswap back to it later.",
                        "Save", "Cancel", true, "");
                    if (r.confirmed) {
                        window.msLibraryClient.capture(kind, (r.value || "").trim());
                    }
                }),
            ));
        });

        if (window.msLibraryClient) window.msLibraryClient.request(kind);
    }

    if (window.msLibraryClient) {
        window.msLibraryClient.on("theme", (entries) => {
            LIB_STATE.theme = entries;
            repaintLib("theme");
        });

        window.msLibraryClient.on("sound", (entries) => {
            LIB_STATE.sound = entries;
            repaintLib("sound");
        });
    }

    // -- Theme tab --
    function buildTheme(root) {
        const { h, row, toggle, btnRow, actionBtn } = ui();
        const theme = Object.assign({}, S.theme || {}, _pending);
        const set   = S.themeSet || {};

        const customTheme = S.customThemeEnabled !== false;
        sec(root, "custom", "Theme", "Whether this pack's look is used at all", (body) => {
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
            }
        });

        if (!customTheme) return;

        sec(root, "colours", "Colours", "Everything dimmer is derived from these", (body) => {
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
        });

        // -- Radius --
        sec(root, "shape", "Shape", "Corner rounding across every panel", (body) => {
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
        });

        // -- Font --
        // Values are what ms_theme.json stores: a path under ui/fonts/ for a
        // font file (Lua turns it into an @font-face), or a bare family name.
        sec(root, "type", "Type", "The face the whole shell is set in", (body) => {
            const fonts   = S.themeFonts || [];
            const current = S.themeFontValue || "";

            // createSelect, not <select>: the closed control takes CSS but the
            // *open* native popup is drawn by macOS and no stylesheet reaches it,
            // so it broke out of the shell's look mid-interaction, on the one
            // panel whose whole subject is how the shell looks.
            const options = [];
            // A font set by hand in ms_theme.json that is not in the folder listing
            // still has to be selectable, and has to say why it looks different.
            if (!fonts.some((f) => f.value === current) && current) {
                options.push({ value: current, label: current + " (from file)" });
            }
            for (const f of fonts) {
                options.push({ value: f.value, label: f.label });
            }

            const select = createSelect({
                options: options,
                value: current,
                className: "theme-select",
                onChange: (v) =>
                    sendToHost({ action: "setThemeKey", key: "font", value: v }),
            });
            select.addEventListener("mouseenter", () => playSlot("hover"));
            body.appendChild(
                row("Font", "Files in ui/fonts/ travel with a theme package", select),
            );
        });

        // -- Escape hatches --
        sec(root, "themefile", "Theme File", "Editing ms_theme.json by hand", (body) => {
            body.appendChild(
                btnRow(
                    actionBtn("Edit Theme File...", "", () =>
                        sendToHost({ action: "editTheme" })),
                    actionBtn("Reset Theme", "danger", () =>
                        sendToHost({ action: "resetTheme" })),
                ),
            );
            body.appendChild(h("div", { cls: "theme-note" },
                "Overrides the editor doesn't offer, text2, border, the glow "
                + "colours, can be hand-written into ms_theme.json and win over "
                + "the values derived here."));
        });

        librarySection(root, "theme", "Installed Themes",
            "Hotswap a saved look", "Save current theme...");
    }

    // -- Sound picker --
    // Moved verbatim from panel-settings.js, with one fix: the reposition
    // handler now attaches to whichever scroll container the picker was
    // rendered into, rather than to the settings panel's #scroll, which is
    // not the element these rows have scrolled inside since the sound section
    // moved out of the settings list.
    // Custom theme off means the sound set is stock, same as the colours ,
    // so everything that could move a slot off its default is inert, not just
    // ignored. Read through a function: S is replaced on every render.
    const themeLocked = () => S.customThemeEnabled === false;
    const LOCK_HINT = "Turn custom theme on to change sounds";

    function soundPicker(slotId, assigned, soundNames, scrollEl) {
        const { h } = ui();
        const display = assigned || "off";
        const locked = themeLocked();
        const wrap = h("div", { cls: "sound-picker-wrap" });
        const btn = h(
            "div",
            {
                cls: "sound-picker-btn" + (locked ? " locked" : ""),
                title: locked ? LOCK_HINT : "",
                onmouseenter: () => { if (!locked) playSlot("hover"); },
            },
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
            if (locked) return;
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

    // -- Sound tab --
    // The slots, their labels, their grouping and the samples the "Default"
    // preset restores all arrive in the state payload from ms.soundSlots.
    // This panel keeps no list of its own: it used to, and it was one of four
    // hand-written copies that had to agree.
    //
    // Read through functions rather than consts, S is replaced on every
    // render, so a const captured at module load would freeze the first one.
    const slotsIn = (group) => (S.soundSlots || []).filter((s) => s.group === group);

    // A slot with no `d` ships unassigned (restart), so the Default preset has
    // nothing to say about it and leaves it empty, which is what makes it
    // fall through to the sound its registry entry points at.
    function defaultAssignsFor(slots) {
        const out = {};
        for (const s of slots) if (s.d) out[s.id] = s.d;
        return out;
    }

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
        const can = removable(name) && !themeLocked();
        const b = h("button", {
            cls: "slot-btn slot-btn-danger",
            title: themeLocked() ? LOCK_HINT
                 : can ? "Remove “" + name + "”"
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
        const mk = (iconName, glyph, title, action, locked) => {
            const b = h("button", {
                cls: "slot-btn",
                title: locked ? LOCK_HINT : title,
                onmouseenter: () => { if (!locked) playSlot("hover"); },
                onclick: (e) => { e.stopPropagation(); if (locked) return; action(); },
            });
            b.disabled = !!locked;
            const svg = typeof window.icon === "function" ? window.icon(iconName) : "";
            if (svg && svg.indexOf("<path") !== -1) b.innerHTML = svg;
            else b.textContent = glyph;
            return b;
        };
        // Preview stays live while locked: hearing the stock set is not
        // changing it.
        wrap.appendChild(mk("play", "▶", "Preview",
            () => sendToHost({ action: "playSlot", slot: slotId })));
        wrap.appendChild(mk("download", "⤓", "Import a file for this slot",
            () => sendToHost({ action: "importSoundForSlot", slot: slotId, label: label }),
            themeLocked()));
        // Removes the file this slot points at, not the slot itself, the
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
        // The context menu is the same set of actions as the buttons, so it
        // locks with them, otherwise right-click is a way around the lock.
        return row(label, null, ctl, "", [
            { icon: "", label: "Play",
              action: () => sendToHost({ action: "playSlot", slot: slotId }) },
            ...(themeLocked() ? [] : [
                { icon: "", label: "Import",
                  action: () => sendToHost({ action: "importSoundForSlot", slot: slotId, label: label }) },
                ...(assigned ? [{
                    icon: "", label: "Clear",
                    action: () => sendToHost({ action: "setSoundAssign", slot: slotId, name: "" }),
                }] : []),
            ]),
        ]);
    }

    function buildSound(root, scrollEl) {
        const { h, row, toggle, seg, divider, groupLabel, btnRow, actionBtn, showCtxMenu } = ui();

        sec(root, "output", "Output", "Whether the shell makes sound, and how loud", (body) => {
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

            // -- Volume --
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
        });

        // -- Presets --
        const presets   = S.soundPresets || [];
        const ALL_SLOTS = S.soundSlots || [];

        // Only the slots a preset actually speaks about, the same test
        // buildSoundPresets() applies on the Lua side. A slot with no series
        // of its own borrows from another slot, and a preset has nothing to
        // say about a borrower: it cannot match the Default map (which has no
        // entry to match against), and clearing it just drops it back to
        // borrowing. This was every slot id, which put any such slot into
        // both preset operations wrongly. No slot in the registry is
        // borrow-only today, so this changes nothing now; it is the invariant
        // that keeps the next one from re-breaking the segment.
        const presetSlotIds = ALL_SLOTS.filter(s => s.d || s.a).map(s => s.id);

        const defaultAssigns = defaultAssignsFor(ALL_SLOTS);

        // Which preset is live is inferred from the assignments themselves ,
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

        // Custom theme off reverts the sound set to stock, so the segment is
        // pinned to Default and reads as fixed rather than as a live choice
        // that happens to agree with the setting.
        const soundLocked = themeLocked();
        const shown = soundLocked ? "default" : activePreset;

        const segBtn = (key, labelText, action) => {
            const b = h("button", {
                cls: "seg-btn" + (shown === key ? " active" : ""),
                title: soundLocked ? LOCK_HINT : "",
                onmouseenter: () => { if (!soundLocked) playSlot("hover"); },
                onclick: () => { if (soundLocked) return; action(); },
            }, labelText);
            b.disabled = soundLocked;
            return b;
        };

        sec(root, "presets", "Presets", "A whole slot map in one click", (body) => {
            const presetWrap = h("div", { cls: "seg" + (soundLocked ? " locked" : "") });
            presetWrap.appendChild(segBtn(null, "Custom", () =>
                sendToHost({ action: "clearSoundPreset", slots: presetSlotIds })));
            presetWrap.appendChild(segBtn("default", "Default", () =>
                sendToHost({ action: "setSoundPreset", assigns: defaultAssigns, preset: "default" })));
            for (const p of presets) {
                presetWrap.appendChild(segBtn(String(p.num), String(p.num), () =>
                    sendToHost({ action: "setSoundPreset", assigns: p.assigns, preset: String(p.num) })));
            }
            body.appendChild(row(
                "Preset",
                soundLocked
                    ? "Fixed at Default while custom theme is off"
                    : "Select a numbered sound set, or Custom for individual control",
                presetWrap,
            ));
        });

        // -- Slots --
        // Each group of slots is its own section, so the heading naming it
        // stays on screen while a long list of slots scrolls under it.
        const names = S.soundNames || [];

        const loadSlots = slotsIn("load");
        if (loadSlots.length > 0) {
            sec(root, "loadslots", "Startup", "Played while mudscript starts up", (body) => {
                for (const slot of loadSlots) {
                    body.appendChild(slotRow(slot.id, slot.label, names, scrollEl));
                }
            });
        }

        sec(root, "eventslots", "Event Slots", "One sound per shell interaction", (body) => {
            for (const slot of slotsIn("event")) {
                body.appendChild(slotRow(slot.id, slot.label, names, scrollEl));
            }
        });

        // Slots declared by the pack via ms.settings.define({ type = "soundSlot" }).
        const userSlots = S.userSoundSlots || [];
        if (userSlots.length > 0) {
            sec(root, "packslots", "Pack Slots", "Declared by your macro pack", (body) => {
                for (const slot of userSlots) {
                    body.appendChild(slotRow(slot.key, slot.label, names, scrollEl));
                }
            });
        }

        // -- Sound library --
        // The sections above list *slots*, a fixed set of events, each
        // pointing at a file. This lists the files themselves, one row per
        // sound, so a sound that no slot uses is still visible and still
        // removable. Adding a sound adds a row here; removing one takes its
        // row with it. Nothing is enumerated by hand.
        const entries = S.soundEntries || [];
        const byKind = (k) => entries.filter((e) => e.kind === k);

        const soundEntryRow = (e) => {
            const ctl = h("div", { cls: "slot-ctl" });
            // Every sound you own gets to say what it is; only defaults are
            // fixed, because they are the fallback floor. An import has no
            // type yet, so neither option reads as selected, picking one is
            // what moves it out of Imported and into that group.
            const selected = e.imported ? null : e.role;
            if (e.role === "default") {
                ctl.appendChild(h("span", { cls: "snd-entry-kind" }, e.kind));
            } else {
                ctl.appendChild(seg(
                    [{ value: "active", label: "Active" },
                     { value: "macro",  label: "Macro"  }],
                    selected,
                    (v) => {
                        if (v === selected) return;
                        sendToHost({ action: "setSoundKind", name: e.name, kind: v });
                    },
                ));
            }
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

        // Active sounds had no group of their own, they were only reachable
        // through the slot pickers above. That was survivable while nothing
        // could become one, but assigning a sound "active" has to put it
        // somewhere visible or the click looks like it deleted it.
        // Active, macro and imported are groups *within* the library, not
        // peers of the slot sections above. Every slot ships both a d_ default
        // and an a_ active sample, so an "Active Sounds" section standing
        // alongside "Event Slots" read as a second kind of sound when it is
        // the pool those same slots draw from. They are sub-groups of one
        // Sound Library section instead, which also retires a section that
        // was called "Library" while sitting next to the actual library.
        sec(root, "library", "Sound Library",
            "The files themselves, whether or not a slot uses them", (body) => {
            const activeEntries = byKind("active");
            body.appendChild(groupLabel("Active"));
            if (activeEntries.length === 0) {
                body.appendChild(h("div", { cls: "theme-note" },
                    "Sounds in sounds/active/ appear here. These are the ones the "
                    + "slots above can be assigned to."));
            } else {
                for (const e of activeEntries) body.appendChild(soundEntryRow(e));
            }

            const macroEntries = byKind("macro");
            body.appendChild(divider());
            body.appendChild(groupLabel("Macro"));
            if (macroEntries.length === 0) {
                body.appendChild(h("div", { cls: "theme-note" },
                    "Sounds in sounds/macro/ appear here, one row each. Macros play "
                    + "them by name with ms.sound(\"m_Name\"), they have no slot, "
                    + "because a macro chooses its own sound at the call."));
            } else {
                for (const e of macroEntries) body.appendChild(soundEntryRow(e));
            }

            const importedEntries = byKind("imported");
            if (importedEntries.length > 0) {
                body.appendChild(divider());
                body.appendChild(groupLabel("Imported"));
                for (const e of importedEntries) body.appendChild(soundEntryRow(e));
            }

            body.appendChild(divider());
            body.appendChild(
                btnRow(actionBtn("Import Sound Files...", "", () =>
                    sendToHost({ action: "importSounds" }))),
            );
        });

        sec(root, "bundling", "Sharing", "What travels with a theme package", (body) => {
            body.appendChild(row(
                "Bundle Sounds With Theme",
                "Include your sounds and their slot assignments in theme exports",
                toggle(S.bundleSoundsWithTheme ?? true, (e) =>
                    sendToHost({ action: "setBundleSoundsWithTheme", value: e.target.checked })),
                "",
                [{ icon: "", label: "Reset to default",
                   action: () => sendToHost({ action: "setBundleSoundsWithTheme", value: true }) }],
            ));
        });

        librarySection(root, "sound", "Installed Sound Packs",
            "Hotswap a saved set", "Save current sounds...");
    }

    // -- Share tab --
    // Sound is a theme aspect: a theme is the whole sensory surface, so a
    // theme package carries its audio and the slot map that gives that audio
    // meaning. The sound package still exists for sharing a set on its own,
    // but it is the narrower thing, not the co-equal one.
    function buildShare(root) {
        const { h, btnRow, actionBtn } = ui();

        sec(root, "export", "Export", "Package what you have made", (body) => {
            body.appendChild(h("div", { cls: "theme-note" },
                "A theme package carries ms_theme.json, any font files in "
                + "ui/fonts/, and, unless you turn it off under Sounds, your "
                + "sounds and their slot assignments. Export Sounds is for "
                + "sharing a sound set on its own, without the colours."));

            body.appendChild(btnRow(
                actionBtn("Export Theme...", "", () =>
                    sendToHost({ action: "exportPackage", type: "theme" })),
                actionBtn("Export Sounds...", "", () =>
                    sendToHost({ action: "exportPackage", type: "sound" })),
            ));
        });

        sec(root, "import", "Import", "Install a package someone shared", (body) => {
            body.appendChild(h("div", { cls: "theme-note" },
                "Importing a package replaces the files it carries, keeping a .bak "
                + "of anything it overwrites. A package outside the validated "
                + "library asks before it installs."));
            body.appendChild(btnRow(
                actionBtn("Import Package...", "", () =>
                    sendToHost({ action: "importPackage" })),
            ));
        });
    }

    // -- Tabs --
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

    // -- Render --
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
        // is deferred until the edit settles, the panel is already showing the
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
