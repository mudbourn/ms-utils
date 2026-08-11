    /* panel: macros — Function Picker + Step Canvas + Macro Management */
    (function() {
    "use strict";
(function() {
        "use strict";

        /* ── Function Registry ─────────────────────────────────────── */
        var REGISTRY = [
            /* ── input ──────────────────────────────────────────── */
            {
                id: "ms.type",
                name: "ms.type",
                sig: "ms.type(key, mods)",
                desc: "Type a key with optional modifiers. Full keypress cycle (down+up).",
                category: "input",
                params: [
                    { name: "key",  type: "key",   label: "Key",        required: true },
                    { name: "mods", type: "mods",   label: "Modifiers",  required: false }
                ]
            },
            {
                id: "ms.press",
                name: "ms.press",
                sig: "ms.press(key, mods)",
                desc: "Send key-down only.",
                category: "input",
                params: [
                    { name: "key",  type: "key",   label: "Key",        required: true },
                    { name: "mods", type: "mods",   label: "Modifiers",  required: false }
                ]
            },
            {
                id: "ms.release",
                name: "ms.release",
                sig: "ms.release(key)",
                desc: "Send key-up only.",
                category: "input",
                params: [
                    { name: "key", type: "key", label: "Key", required: true }
                ]
            },
            {
                id: "ms.hold",
                name: "ms.hold",
                sig: "ms.hold(key)",
                desc: "Hold a key down without releasing.",
                category: "input",
                params: [
                    { name: "key", type: "key", label: "Key", required: true }
                ]
            },
            {
                id: "ms.toggle",
                name: "ms.toggle",
                sig: "ms.toggle(key, mods)",
                desc: "Toggle a key: if held, release; if not held, press.",
                category: "input",
                params: [
                    { name: "key",  type: "key",   label: "Key",        required: true },
                    { name: "mods", type: "mods",   label: "Modifiers",  required: false }
                ]
            },
            {
                id: "ms.multiPress",
                name: "ms.multiPress",
                sig: "ms.multiPress(keys, delayMs, mods)",
                desc: "Press a sequence of keys in order with optional delay.",
                category: "input",
                params: [
                    { name: "keys",    type: "string", label: "Keys (comma-separated)", required: true },
                    { name: "delayMs", type: "number", label: "Delay (ms)",             required: false },
                    { name: "mods",    type: "mods",   label: "Modifiers",              required: false }
                ]
            },

            /* ── clipboard ──────────────────────────────────────── */
            {
                id: "ms.copy",
                name: "ms.copy",
                sig: "ms.copy(text)",
                desc: "Copy text to system clipboard.",
                category: "clipboard",
                params: [
                    { name: "text", type: "string", label: "Text", required: true }
                ]
            },
            {
                id: "ms.paste",
                name: "ms.paste",
                sig: "ms.paste()",
                desc: "Paste current clipboard contents.",
                category: "clipboard",
                params: []
            },

            /* ── timing ─────────────────────────────────────────── */
            {
                id: "ms.wait",
                name: "ms.wait",
                sig: "ms.wait(ms)",
                desc: "Pause macro execution for N milliseconds.",
                category: "timing",
                params: [
                    { name: "ms", type: "number", label: "Milliseconds", required: true }
                ]
            },
            {
                id: "ms.randWait",
                name: "ms.randWait",
                sig: "ms.randWait(min, max)",
                desc: "Wait a random duration between min and max ms.",
                category: "timing",
                params: [
                    { name: "min", type: "number", label: "Min (ms)", required: true },
                    { name: "max", type: "number", label: "Max (ms)", required: true }
                ]
            },
            {
                id: "ms.jitter",
                name: "ms.jitter",
                sig: "ms.jitter(base, jitterMs)",
                desc: "Wait base ms plus/minus random jitter.",
                category: "timing",
                params: [
                    { name: "base",     type: "number", label: "Base (ms)",   required: true },
                    { name: "jitterMs", type: "number", label: "Jitter (ms)", required: true }
                ]
            },
            {
                id: "ms.waitApp",
                name: "ms.waitApp",
                sig: "ms.waitApp(appName, timeout)",
                desc: "Wait until an app is running.",
                category: "timing",
                params: [
                    { name: "appName", type: "string", label: "App Name",  required: true },
                    { name: "timeout", type: "number", label: "Timeout (ms)", required: false }
                ]
            },
            {
                id: "ms.waitNotApp",
                name: "ms.waitNotApp",
                sig: "ms.waitNotApp(appName, timeout)",
                desc: "Wait until an app stops running.",
                category: "timing",
                params: [
                    { name: "appName", type: "string", label: "App Name",  required: true },
                    { name: "timeout", type: "number", label: "Timeout (ms)", required: false }
                ]
            },

            /* ── mouse ──────────────────────────────────────────── */
            {
                id: "ms.Mouse",
                name: "ms.Mouse",
                sig: "ms.Mouse(operation, button, reference, x1, y1, x2, y2)",
                desc: "Unified mouse API (click, move, drag at coordinates).",
                category: "mouse",
                params: [
                    { name: "operation", type: "string", label: "Operation (click/move/drag)", required: true },
                    { name: "button",    type: "string", label: "Button (left/right/middle)",  required: true },
                    { name: "reference", type: "string", label: "Reference",                   required: true },
                    { name: "x1",        type: "number", label: "X1",                          required: true },
                    { name: "y1",        type: "number", label: "Y1",                          required: true },
                    { name: "x2",        type: "number", label: "X2",                          required: false },
                    { name: "y2",        type: "number", label: "Y2",                          required: false }
                ]
            },
            {
                id: "ms.scroll",
                name: "ms.scroll",
                sig: "ms.scroll(direction, clicks)",
                desc: "Post a scroll event.",
                category: "mouse",
                params: [
                    { name: "direction", type: "string", label: "Direction (up/down/left/right)", required: true },
                    { name: "clicks",    type: "number", label: "Clicks",                        required: true }
                ]
            },
            {
                id: "ms.moveMouse",
                name: "ms.moveMouse",
                sig: "ms.moveMouse(x, y, ref, durationMs)",
                desc: "Smooth mouse movement.",
                category: "mouse",
                params: [
                    { name: "x",          type: "number", label: "X",          required: true },
                    { name: "y",          type: "number", label: "Y",          required: true },
                    { name: "ref",        type: "string", label: "Reference",  required: false },
                    { name: "durationMs", type: "number", label: "Duration (ms)", required: false }
                ]
            },
            {
                id: "ms.dragPath",
                name: "ms.dragPath",
                sig: "ms.dragPath(points, button, ref, delayMs)",
                desc: "Drag through a sequence of points.",
                category: "mouse",
                params: [
                    { name: "points", type: "string", label: "Points (x,y;x,y)", required: true },
                    { name: "button", type: "string", label: "Button",           required: false },
                    { name: "ref",    type: "string", label: "Reference",        required: false },
                    { name: "delayMs",type: "number", label: "Delay (ms)",       required: false }
                ]
            },
            {
                id: "ms.saveCursor",
                name: "ms.saveCursor",
                sig: "ms.saveCursor()",
                desc: "Save current mouse position.",
                category: "mouse",
                params: []
            },
            {
                id: "ms.restoreCursor",
                name: "ms.restoreCursor",
                sig: "ms.restoreCursor()",
                desc: "Restore saved mouse position.",
                category: "mouse",
                params: []
            },

            /* ── camera ─────────────────────────────────────────── */
            {
                id: "ms.cam",
                name: "ms.cam",
                sig: "ms.cam(dy, dx)",
                desc: "Move camera by delta. Note: params are (dy, dx) — vertical first.",
                category: "camera",
                params: [
                    { name: "dy", type: "number", label: "Delta Y", required: true },
                    { name: "dx", type: "number", label: "Delta X", required: true }
                ]
            },
            {
                id: "ms.cam.rebalance",
                name: "ms.cam.rebalance",
                sig: "ms.cam.rebalance()",
                desc: "Rebalance camera to neutral.",
                category: "camera",
                params: []
            },
            {
                id: "ms.cam.reset",
                name: "ms.cam.reset",
                sig: "ms.cam.reset()",
                desc: "Reset camera to default.",
                category: "camera",
                params: []
            },

            /* ── pixel ──────────────────────────────────────────── */
            {
                id: "ms.pixelColor",
                name: "ms.pixelColor",
                sig: "ms.pixelColor(x, y, reference)",
                desc: "Get pixel color at position.",
                category: "pixel",
                params: [
                    { name: "x",         type: "number", label: "X",         required: true },
                    { name: "y",         type: "number", label: "Y",         required: true },
                    { name: "reference", type: "string", label: "Reference", required: false }
                ]
            },
            {
                id: "ms.pixelMatch",
                name: "ms.pixelMatch",
                sig: "ms.pixelMatch(x, y, reference, r, g, b, tolerance)",
                desc: "Check if pixel matches color.",
                category: "pixel",
                params: [
                    { name: "x",         type: "number", label: "X",         required: true },
                    { name: "y",         type: "number", label: "Y",         required: true },
                    { name: "reference", type: "string", label: "Reference", required: false },
                    { name: "r",         type: "number", label: "R",         required: true },
                    { name: "g",         type: "number", label: "G",         required: true },
                    { name: "b",         type: "number", label: "B",         required: true },
                    { name: "tolerance", type: "number", label: "Tolerance", required: false }
                ]
            },
            {
                id: "ms.waitPixel",
                name: "ms.waitPixel",
                sig: "ms.waitPixel(x, y, ref, r, g, b, tolerance, timeout)",
                desc: "Wait until pixel matches color.",
                category: "pixel",
                params: [
                    { name: "x",         type: "number", label: "X",         required: true },
                    { name: "y",         type: "number", label: "Y",         required: true },
                    { name: "ref",       type: "string", label: "Reference", required: false },
                    { name: "r",         type: "number", label: "R",         required: true },
                    { name: "g",         type: "number", label: "G",         required: true },
                    { name: "b",         type: "number", label: "B",         required: true },
                    { name: "tolerance", type: "number", label: "Tolerance", required: false },
                    { name: "timeout",   type: "number", label: "Timeout (ms)", required: false }
                ]
            },
            {
                id: "ms.waitNotPixel",
                name: "ms.waitNotPixel",
                sig: "ms.waitNotPixel(x, y, ref, r, g, b, tolerance, timeout)",
                desc: "Wait until pixel changes.",
                category: "pixel",
                params: [
                    { name: "x",         type: "number", label: "X",         required: true },
                    { name: "y",         type: "number", label: "Y",         required: true },
                    { name: "ref",       type: "string", label: "Reference", required: false },
                    { name: "r",         type: "number", label: "R",         required: true },
                    { name: "g",         type: "number", label: "G",         required: true },
                    { name: "b",         type: "number", label: "B",         required: true },
                    { name: "tolerance", type: "number", label: "Tolerance", required: false },
                    { name: "timeout",   type: "number", label: "Timeout (ms)", required: false }
                ]
            },

            /* ── state ──────────────────────────────────────────── */
            {
                id: "ms.app",
                name: "ms.app",
                sig: "ms.app()",
                desc: "Get frontmost app name.",
                category: "state",
                params: []
            },
            {
                id: "ms.appRunning",
                name: "ms.appRunning",
                sig: "ms.appRunning(appName)",
                desc: "Check if app is running.",
                category: "state",
                params: [
                    { name: "appName", type: "string", label: "App Name", required: true }
                ]
            },
            {
                id: "ms.appIsFront",
                name: "ms.appIsFront",
                sig: "ms.appIsFront(appName)",
                desc: "Check if app is frontmost.",
                category: "state",
                params: [
                    { name: "appName", type: "string", label: "App Name", required: true }
                ]
            },
            {
                id: "ms.focus",
                name: "ms.focus",
                sig: "ms.focus(appName)",
                desc: "Bring app to front.",
                category: "state",
                params: [
                    { name: "appName", type: "string", label: "App Name", required: true }
                ]
            },
            {
                id: "ms.keystate",
                name: "ms.keystate",
                sig: "ms.keystate(key)",
                desc: "Check if a key is currently held.",
                category: "state",
                params: [
                    { name: "key", type: "key", label: "Key", required: true }
                ]
            },
            {
                id: "ms.mousePos",
                name: "ms.mousePos",
                sig: "ms.mousePos()",
                desc: "Get cursor position in reference-space.",
                category: "state",
                params: []
            },

            /* ── audio ──────────────────────────────────────────── */
            {
                id: "ms.sound",
                name: "ms.sound",
                sig: "ms.sound(path, async)",
                desc: "Play a sound file.",
                category: "audio",
                params: [
                    { name: "path",  type: "string", label: "Path",  required: true },
                    { name: "async", type: "number", label: "Async", required: false }
                ]
            },
            {
                id: "ms.playSlot",
                name: "ms.playSlot",
                sig: "ms.playSlot(slotId)",
                desc: "Play a named sound slot.",
                category: "audio",
                params: [
                    { name: "slotId", type: "string", label: "Slot ID", required: true }
                ]
            },
            {
                id: "ms.setVolume",
                name: "ms.setVolume",
                sig: "ms.setVolume(level)",
                desc: "Set system volume (0-100).",
                category: "audio",
                params: [
                    { name: "level", type: "number", label: "Level (0-100)", required: true }
                ]
            },
            {
                id: "ms.mute",
                name: "ms.mute",
                sig: "ms.mute()",
                desc: "Mute system audio.",
                category: "audio",
                params: []
            },
            {
                id: "ms.unmute",
                name: "ms.unmute",
                sig: "ms.unmute()",
                desc: "Unmute system audio.",
                category: "audio",
                params: []
            },

            /* ── utility ────────────────────────────────────────── */
            {
                id: "ms.alert",
                name: "ms.alert",
                sig: "ms.alert(msg, duration)",
                desc: "Show a floating toast notification.",
                category: "utility",
                params: [
                    { name: "msg",      type: "string", label: "Message",       required: true },
                    { name: "duration", type: "number", label: "Duration (ms)", required: false }
                ]
            },
            {
                id: "ms.screenshot",
                name: "ms.screenshot",
                sig: "ms.screenshot(path)",
                desc: "Take a screenshot.",
                category: "utility",
                params: [
                    { name: "path", type: "string", label: "Path", required: false }
                ]
            },
            {
                id: "ms.notify",
                name: "ms.notify",
                sig: "ms.notify(title, subTitle, infoText)",
                desc: "Show native macOS notification.",
                category: "utility",
                params: [
                    { name: "title",    type: "string", label: "Title",    required: true },
                    { name: "subTitle", type: "string", label: "Subtitle", required: false },
                    { name: "infoText", type: "string", label: "Info",     required: false }
                ]
            },

            /* ── flow ───────────────────────────────────────────── */
            {
                id: "ms.setMacros",
                name: "ms.setMacros",
                sig: "ms.setMacros(state)",
                desc: "Enable (1) or disable (0) macros.",
                category: "flow",
                params: [
                    { name: "state", type: "number", label: "State (0/1)", required: true }
                ]
            },
            {
                id: "ms.cancelMacros",
                name: "ms.cancelMacros",
                sig: "ms.cancelMacros()",
                desc: "Cancel all active macro coroutines.",
                category: "flow",
                params: []
            },

            /* ── logic ──────────────────────────────────────────────
               Lua language constructs, not ms.* calls. `name` is the raw
               action the compiler emits an emitter for (see ms_compiler.lua):
               if / for / while / repeat are containers (they nest child
               modules); var_* / comment / code are leaves. */
            {
                id: "if",
                name: "if",
                sig: "if <condition> then … else … end",
                desc: "Branch: run the nested modules when a Lua condition is true, otherwise the else branch.",
                category: "logic",
                params: [
                    { name: "condition", type: "condition", label: "Condition", required: false }
                ]
            },
            {
                id: "for",
                name: "for",
                sig: "for i = from, to do … end",
                desc: "Numeric loop: run the nested modules once per step from `from` to `to`.",
                category: "logic",
                params: [
                    { name: "var",  type: "string", label: "Variable", required: false },
                    { name: "from", type: "number", label: "From",     required: false },
                    { name: "to",   type: "number", label: "To",       required: false },
                    { name: "step", type: "number", label: "Step",     required: false }
                ]
            },
            {
                id: "while",
                name: "while",
                sig: "while <condition> do … end",
                desc: "Loop the nested modules while a Lua condition holds true.",
                category: "logic",
                params: [
                    { name: "condition", type: "condition", label: "Condition", required: false }
                ]
            },
            {
                id: "repeat",
                name: "repeat",
                sig: "repeat … until <condition>",
                desc: "Loop the nested modules until a Lua condition becomes true (runs at least once).",
                category: "logic",
                params: [
                    { name: "condition", type: "condition", label: "Until", required: false }
                ]
            },
            {
                id: "var_set",
                name: "var_set",
                sig: "local name = value",
                desc: "Declare or set a local variable.",
                category: "logic",
                params: [
                    { name: "name",  type: "string", label: "Name",  required: true },
                    { name: "value", type: "string", label: "Value", required: false }
                ]
            },
            {
                id: "var_add",
                name: "var_add",
                sig: "name = name + amount",
                desc: "Increment a variable.",
                category: "logic",
                params: [
                    { name: "name",   type: "string", label: "Name",   required: true },
                    { name: "amount", type: "number", label: "Amount", required: false }
                ]
            },
            {
                id: "var_sub",
                name: "var_sub",
                sig: "name = name - amount",
                desc: "Decrement a variable.",
                category: "logic",
                params: [
                    { name: "name",   type: "string", label: "Name",   required: true },
                    { name: "amount", type: "number", label: "Amount", required: false }
                ]
            },
            {
                id: "var_mul",
                name: "var_mul",
                sig: "name = name * amount",
                desc: "Multiply a variable.",
                category: "logic",
                params: [
                    { name: "name",   type: "string", label: "Name",   required: true },
                    { name: "amount", type: "number", label: "Amount", required: false }
                ]
            },
            {
                id: "comment",
                name: "comment",
                sig: "-- text",
                desc: "A Lua comment. Documents the macro; emits nothing at runtime.",
                category: "logic",
                params: [
                    { name: "text", type: "string", label: "Text", required: false }
                ]
            },
            {
                id: "code",
                name: "code",
                sig: "<raw Lua>",
                desc: "Raw Lua escape hatch — emitted verbatim. Use for coroutines or anything the modules don't cover.",
                category: "logic",
                params: [
                    { name: "source", type: "code", label: "Lua source", required: false }
                ]
            }
        ];

        var MOD_LIST = ["ctrl", "alt", "shift", "cmd"];

        // Parameter types whose value can be wired to a tool (an authored
        // setting) instead of a literal. A bound param compiles to
        // ms.settings.get("key"), so it only makes sense where a plain value is
        // expected — not for key captures, modifier sets, or raw Lua blocks.
        var BINDABLE = { number: true, string: true };

        /* ── State ─────────────────────────────────────────────────── */
        var _selectedId  = null;
        var _paramValues = {};   // { paramName: value }
        var _paramBind   = {};   // { paramName: toolKey } — params wired to a tool
        var _modState    = {};   // { ctrl: false, alt: false, ... }
        var _keyCapture  = null; // param name currently capturing
        var _toastTimer  = null;
        var _tools       = [];   // current tools (authored settings + pack settings)
        var _view        = "module"; // "module" | "tool" | "toolCreator"
        var _toolDraft   = null; // in-progress new-tool definition (creator form)

        /* ── Build DOM ─────────────────────────────────────────────── */
        var slot = document.getElementById("slot-macros");
        if (!slot) return;

        var root = document.createElement("div");
        root.className = "fn-picker";

        // Left: list
        var listPane = document.createElement("div");
        listPane.className = "fn-picker-list";

        var searchBox = document.createElement("div");
        searchBox.className = "fn-picker-search";
        var searchInput = document.createElement("input");
        searchInput.type = "text";
        searchInput.placeholder = "Search modules\u2026";
        searchInput.setAttribute("spellcheck", "false");
        searchInput.setAttribute("autocomplete", "off");
        searchInput.setAttribute("autocorrect", "off");
        searchInput.setAttribute("autocapitalize", "off");
        searchBox.appendChild(searchInput);
        listPane.appendChild(searchBox);

        var entriesDiv = document.createElement("div");
        entriesDiv.className = "fn-picker-entries";
        listPane.appendChild(entriesDiv);

        // Right: detail
        var detailPane = document.createElement("div");
        detailPane.className = "fn-picker-detail";
        detailPane.innerHTML = '<div class="fn-detail-empty"><svg class="icon" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M16.6582 9.28638C18.098 10.1862 18.8178 10.6361 19.0647 11.2122C19.2803 11.7152 19.2803 12.2847 19.0647 12.7878C18.8178 13.3638 18.098 13.8137 16.6582 14.7136L9.896 18.94C8.29805 19.9387 7.49907 20.4381 6.83973 20.385C6.26501 20.3388 5.73818 20.0469 5.3944 19.584C5 19.053 5 18.1108 5 16.2264V7.77357C5 5.88919 5 4.94701 5.3944 4.41598C5.73818 3.9531 6.26501 3.66111 6.83973 3.6149C7.49907 3.5619 8.29805 4.06126 9.896 5.05998L16.6582 9.28638Z" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/></svg>Select a module from the list</div>';

        root.appendChild(listPane);
        root.appendChild(detailPane);
        slot.appendChild(root);

        // Toast
        var toast = document.createElement("div");
        toast.className = "fn-toast";
        document.body.appendChild(toast);

        /* ── Render Function List ──────────────────────────────────────
           Grouped by category into collapsible sections, in REGISTRY order.
           A search query flattens the collapse — every matching category is
           forced open so results are never hidden behind a folded header. */
        var _catCollapsed = {};   // category -> true when folded shut

        function makeEntryRow(fn) {
            var row = document.createElement("div");
            row.className = "fn-entry" + (_selectedId === fn.id ? " active" : "");
            row.setAttribute("data-fn-id", fn.id);

            var sigSpan = document.createElement("span");
            sigSpan.className = "fn-entry-sig";
            sigSpan.textContent = fn.name;
            row.appendChild(sigSpan);

            row.addEventListener("click", function() {
                selectFunction(fn.id);
            });
            row.addEventListener("mouseenter", function() {
                if (window.playSlot) playSlot("hover");
            });
            return row;
        }

        // The Tools group sits above the module categories: it is not part of
        // REGISTRY (tools are live settings, not code the compiler emits) so it
        // is rendered on its own. Every tool is a row you can inspect; a final
        // "New Tool…" row opens the creator. A module parameter is wired to a
        // tool from that parameter's own field, not from here.
        function renderToolsGroup(filter, searching) {
            var q = (filter || "").toLowerCase();
            var matches = _tools.filter(function(t) {
                if (!q) return true;
                return (t.label || "").toLowerCase().indexOf(q) !== -1
                    || (t.key || "").toLowerCase().indexOf(q) !== -1
                    || "tool".indexOf(q) !== -1;
            });
            // With an active query that matches no tool and not the word "tool",
            // hide the group entirely so search results stay tight.
            var showNew = !q || "new tool".indexOf(q) !== -1 || "tool".indexOf(q) !== -1;
            if (matches.length === 0 && !showNew) return;

            var collapsed = searching ? false : !!_catCollapsed["__tools"];

            var head = document.createElement("div");
            head.className = "fn-cat-head fn-cat-tools" + (collapsed ? " collapsed" : "");

            var chev = document.createElement("span");
            chev.className = "fn-cat-chev";
            chev.innerHTML = (typeof window.icon === "function"
                && window.ICONS && window.ICONS.chevdown)
                ? window.icon("chevdown") : "";
            head.appendChild(chev);

            var name = document.createElement("span");
            name.className = "fn-cat-name";
            name.textContent = "tools";
            head.appendChild(name);

            var count = document.createElement("span");
            count.className = "fn-cat-count";
            count.textContent = String(matches.length);
            head.appendChild(count);

            head.addEventListener("mouseenter", function() {
                if (window.playSlot) playSlot("hover");
            });
            if (!searching) {
                head.addEventListener("click", function() {
                    if (window.playSlot) playSlot("interact");
                    _catCollapsed["__tools"] = !_catCollapsed["__tools"];
                    renderList(filter);
                });
            }
            entriesDiv.appendChild(head);

            if (collapsed) return;

            matches.forEach(function(t) {
                var row = document.createElement("div");
                row.className = "fn-entry fn-tool-entry"
                    + (_view === "tool" && _selectedId === t.key ? " active" : "");
                row.setAttribute("data-tool-key", t.key);

                var sig = document.createElement("span");
                sig.className = "fn-entry-sig";
                sig.textContent = t.label || t.key;
                row.appendChild(sig);

                var tag = document.createElement("span");
                tag.className = "fn-tool-tag fn-tool-tag-" + (t.source || "pack");
                tag.textContent = t.type;
                row.appendChild(tag);

                row.addEventListener("mouseenter", function() {
                    if (window.playSlot) playSlot("hover");
                });
                row.addEventListener("click", function() { selectTool(t.key); });
                entriesDiv.appendChild(row);
            });

            if (showNew) {
                var newRow = document.createElement("div");
                newRow.className = "fn-entry fn-tool-new"
                    + (_view === "toolCreator" ? " active" : "");
                newRow.innerHTML = '<span class="fn-entry-sig">+ New Tool…</span>';
                newRow.addEventListener("mouseenter", function() {
                    if (window.playSlot) playSlot("hover");
                });
                newRow.addEventListener("click", function() { openToolCreator(); });
                entriesDiv.appendChild(newRow);
            }
        }

        function renderList(filter) {
            entriesDiv.innerHTML = "";
            var q = (filter || "").toLowerCase();
            var searching = q.length > 0;

            renderToolsGroup(filter, searching);

            // Group visible entries by category, preserving REGISTRY order.
            var order = [];
            var groups = {};
            for (var i = 0; i < REGISTRY.length; i++) {
                var fn = REGISTRY[i];
                if (q && fn.name.toLowerCase().indexOf(q) === -1
                       && fn.desc.toLowerCase().indexOf(q) === -1
                       && fn.category.toLowerCase().indexOf(q) === -1) {
                    continue;
                }
                var c = fn.category || "other";
                if (!groups[c]) { groups[c] = []; order.push(c); }
                groups[c].push(fn);
            }

            order.forEach(function(cat) {
                var collapsed = searching ? false : !!_catCollapsed[cat];

                var head = document.createElement("div");
                head.className = "fn-cat-head" + (collapsed ? " collapsed" : "");

                var chev = document.createElement("span");
                chev.className = "fn-cat-chev";
                chev.innerHTML = (typeof window.icon === "function"
                    && window.ICONS && window.ICONS.chevdown)
                    ? window.icon("chevdown") : "";
                head.appendChild(chev);

                var name = document.createElement("span");
                name.className = "fn-cat-name";
                name.textContent = cat;
                head.appendChild(name);

                var count = document.createElement("span");
                count.className = "fn-cat-count";
                count.textContent = String(groups[cat].length);
                head.appendChild(count);

                head.addEventListener("mouseenter", function() {
                    if (window.playSlot) playSlot("hover");
                });
                // While searching the sections are forced open, so the header
                // is inert — toggling collapse state would just be undone by
                // the next keystroke's re-render.
                if (!searching) {
                    head.addEventListener("click", function() {
                        if (window.playSlot) playSlot("interact");
                        _catCollapsed[cat] = !_catCollapsed[cat];
                        renderList(filter);
                    });
                }
                entriesDiv.appendChild(head);

                if (!collapsed) {
                    groups[cat].forEach(function(fn) {
                        entriesDiv.appendChild(makeEntryRow(fn));
                    });
                }
            });
        }

        /* ── Select Function ───────────────────────────────────────── */
        function selectFunction(id) {
            _selectedId = id;
            _view = "module";
            _paramValues = {};
            _paramBind = {};
            _modState = {};
            _keyCapture = null;

            // Update list highlight
            var items = entriesDiv.querySelectorAll(".fn-entry");
            for (var i = 0; i < items.length; i++) {
                items[i].classList.toggle("active", items[i].getAttribute("data-fn-id") === id);
            }

            // Find function definition
            var fn = null;
            for (var j = 0; j < REGISTRY.length; j++) {
                if (REGISTRY[j].id === id) { fn = REGISTRY[j]; break; }
            }
            if (!fn) return;

            // Initialize defaults
            for (var k = 0; k < fn.params.length; k++) {
                var p = fn.params[k];
                if (p.type === "mods") {
                    _paramValues[p.name] = [];
                    _modState = { ctrl: false, alt: false, shift: false, cmd: false };
                } else if (p.type === "number") {
                    _paramValues[p.name] = 0;
                } else {
                    _paramValues[p.name] = "";
                }
            }

            renderDetail(fn);
        }

        /* ── Tools ─────────────────────────────────────────────────────
           A tool is an authored setting: it defines a value the person running
           the pack can adjust from the Settings panel, and a module parameter
           can be wired to it so the macro reads that value live instead of a
           number baked into the source. selectTool shows one; openToolCreator
           makes a new one. */
        function findTool(key) {
            for (var i = 0; i < _tools.length; i++) {
                if (_tools[i].key === key) return _tools[i];
            }
            return null;
        }

        function selectTool(key) {
            _view = "tool";
            _selectedId = key;
            var items = entriesDiv.querySelectorAll(".fn-entry");
            for (var i = 0; i < items.length; i++) {
                items[i].classList.toggle("active",
                    items[i].getAttribute("data-tool-key") === key);
            }
            renderToolDetail(findTool(key));
        }

        function renderToolDetail(t) {
            if (!t) { detailPane.innerHTML = ''; return; }
            var html = '';
            html += '<div class="fn-detail-header">';
            html += '<div class="fn-detail-name">' + esc(t.label || t.key) + '</div>';
            html += '<div class="fn-detail-desc">'
                + esc(t.hint || 'A ' + t.type + ' tool. Wire it into a module parameter to read its value live.')
                + '</div>';
            html += '</div>';

            html += '<div class="fn-detail-body"><div class="fn-params">';
            html += toolMetaRow("Key", t.key);
            html += toolMetaRow("Type", t.type);
            html += toolMetaRow("Source",
                t.source === "builder" ? "Authored here" : "Declared in the pack");
            if (t.type === "slider") {
                html += toolMetaRow("Range", (t.min != null ? t.min : "?")
                    + " – " + (t.max != null ? t.max : "?")
                    + (t.step ? " (step " + t.step + ")" : ""));
            }
            if (t.type === "seg" && t.options) {
                var labels = t.options.map(function(o) { return o.label; }).join(", ");
                html += toolMetaRow("Options", labels);
            }
            if (t.default !== undefined && t.default !== null && t.default !== "") {
                html += toolMetaRow("Default", String(t.default));
            }
            html += '<div class="fn-tool-usehint">Reads as <code>ms.settings.get("'
                + esc(t.key) + '")</code>. To use it, add a module and switch any '
                + 'value field to <b>Tool</b>, then pick this.</div>';
            html += '</div></div>';

            html += '<div class="fn-detail-footer">';
            if (t.source === "builder") {
                html += '<button class="fn-add-btn fn-tool-delete" id="fn-tool-delete">Delete Tool</button>';
            }
            html += '</div>';

            detailPane.innerHTML = html;

            var del = document.getElementById("fn-tool-delete");
            if (del) {
                del.addEventListener("click", function() {
                    if (window.macroLab && window.macroLab.deleteTool) {
                        window.macroLab.deleteTool(t.key);
                    }
                });
            }
        }

        function toolMetaRow(label, value) {
            return '<div class="fn-param-group fn-tool-meta"><div class="fn-param-label">'
                + esc(label) + '</div><div class="fn-tool-meta-val">'
                + esc(String(value)) + '</div></div>';
        }

        // Tool types the creator can produce. "number" is a slider under the
        // hood (the settings engine has no free-number control), but presented
        // separately because a bounded counter reads differently from a
        // percentage-style slider.
        var TOOL_TYPES = [
            { id: "slider", label: "Slider" },
            { id: "number", label: "Number" },
            { id: "toggle", label: "Toggle" },
            { id: "seg",    label: "Segmented" }
        ];

        function openToolCreator() {
            _view = "toolCreator";
            _selectedId = null;
            _toolDraft = {
                type: "slider", key: "", label: "", hint: "",
                min: 0, max: 100, step: 1, unit: "",
                toggleDefault: false,
                options: [ { label: "One", value: "one" }, { label: "Two", value: "two" } ],
                segDefault: "one"
            };
            var items = entriesDiv.querySelectorAll(".fn-entry");
            for (var i = 0; i < items.length; i++) items[i].classList.remove("active");
            var nr = entriesDiv.querySelector(".fn-tool-new");
            if (nr) nr.classList.add("active");
            renderToolCreator();
        }

        function renderToolCreator() {
            var d = _toolDraft;
            var html = '';
            html += '<div class="fn-detail-header">';
            html += '<div class="fn-detail-name">New Tool</div>';
            html += '<div class="fn-detail-desc">Define a configurable value. It '
                + 'appears in the Settings panel and can be wired into any module '
                + 'parameter.</div>';
            html += '</div>';

            html += '<div class="fn-detail-body"><div class="fn-params">';

            // Type picker
            html += '<div class="fn-param-group"><div class="fn-param-label">Type</div>';
            html += '<div class="fn-mods-row" id="tc-types">';
            TOOL_TYPES.forEach(function(tt) {
                html += '<button class="fn-mod-chip' + (d.type === tt.id ? ' on' : '')
                    + '" data-tctype="' + tt.id + '">' + tt.label + '</button>';
            });
            html += '</div></div>';

            // Key + label + hint
            html += tcText("Key", "tc-key", d.key, "identifier, e.g. clickDelay", true);
            html += tcText("Label", "tc-label", d.label, "shown in Settings");
            html += tcText("Hint", "tc-hint", d.hint, "optional description");

            // Type-specific
            if (d.type === "slider" || d.type === "number") {
                html += tcNum("Min", "tc-min", d.min);
                html += tcNum("Max", "tc-max", d.max);
                html += tcNum("Step", "tc-step", d.step);
                html += tcNum("Default", "tc-default", d.numDefault != null ? d.numDefault : d.min);
                if (d.type === "slider") html += tcText("Unit", "tc-unit", d.unit, "optional, e.g. %");
            } else if (d.type === "toggle") {
                html += '<div class="fn-param-group"><div class="fn-param-label">Default</div>'
                    + '<div class="fn-mods-row"><button class="fn-mod-chip'
                    + (d.toggleDefault ? ' on' : '') + '" id="tc-toggle-def">'
                    + (d.toggleDefault ? 'On' : 'Off') + '</button></div></div>';
            } else if (d.type === "seg") {
                html += '<div class="fn-param-group"><div class="fn-param-label">Options'
                    + ' <span class="fn-param-type">label : value</span></div>'
                    + '<div id="tc-options">';
                d.options.forEach(function(o, i) {
                    html += '<div class="fn-seg-optrow">'
                        + '<input type="text" class="fn-seg-optlabel" data-oi="' + i + '" value="'
                        + esc(o.label) + '" placeholder="label" spellcheck="false">'
                        + '<input type="text" class="fn-seg-optval" data-oi="' + i + '" value="'
                        + esc(String(o.value)) + '" placeholder="value" spellcheck="false">'
                        + '<button class="fn-seg-optdel" data-oi="' + i + '" title="Remove">×</button>'
                        + '</div>';
                });
                html += '</div><button class="fn-seg-optadd" id="tc-optadd">+ Add option</button></div>';
            }

            html += '</div></div>';

            html += '<div class="fn-detail-footer">';
            html += '<button class="fn-add-btn" id="tc-create">Create Tool</button>';
            html += '</div>';

            detailPane.innerHTML = html;
            wireToolCreator();
        }

        function tcText(label, id, val, ph, required) {
            return '<div class="fn-param-group"><div class="fn-param-label">' + esc(label)
                + (required ? ' <span style="color:var(--danger)">*</span>' : '')
                + '</div><input type="text" id="' + id + '" value="' + esc(val || "")
                + '" placeholder="' + esc(ph || "") + '" spellcheck="false" autocomplete="off" '
                + 'autocorrect="off" autocapitalize="off"></div>';
        }

        function tcNum(label, id, val) {
            return '<div class="fn-param-group"><div class="fn-param-label">' + esc(label)
                + '</div><input type="number" id="' + id + '" value="'
                + (val != null ? val : 0) + '" step="any"></div>';
        }

        function wireToolCreator() {
            var d = _toolDraft;
            // Type chips
            var typeChips = detailPane.querySelectorAll("[data-tctype]");
            typeChips.forEach(function(c) {
                c.addEventListener("click", function() {
                    d.type = c.getAttribute("data-tctype");
                    renderToolCreator();
                });
            });
            function bindText(id, key) {
                var el = document.getElementById(id);
                if (el) el.addEventListener("input", function() { d[key] = el.value; });
                if (el) el.addEventListener("keydown", function(e) { e.stopPropagation(); });
            }
            function bindNum(id, key) {
                var el = document.getElementById(id);
                if (el) el.addEventListener("input", function() {
                    var v = parseFloat(el.value); d[key] = isNaN(v) ? 0 : v;
                });
                if (el) el.addEventListener("keydown", function(e) { e.stopPropagation(); });
            }
            bindText("tc-key", "key");
            bindText("tc-label", "label");
            bindText("tc-hint", "hint");
            bindText("tc-unit", "unit");
            bindNum("tc-min", "min");
            bindNum("tc-max", "max");
            bindNum("tc-step", "step");
            var defEl = document.getElementById("tc-default");
            if (defEl) defEl.addEventListener("input", function() {
                var v = parseFloat(defEl.value); d.numDefault = isNaN(v) ? undefined : v;
            });
            var tog = document.getElementById("tc-toggle-def");
            if (tog) tog.addEventListener("click", function() {
                d.toggleDefault = !d.toggleDefault; renderToolCreator();
            });
            // Seg options
            detailPane.querySelectorAll(".fn-seg-optlabel").forEach(function(el) {
                el.addEventListener("input", function() {
                    d.options[+el.getAttribute("data-oi")].label = el.value;
                });
                el.addEventListener("keydown", function(e) { e.stopPropagation(); });
            });
            detailPane.querySelectorAll(".fn-seg-optval").forEach(function(el) {
                el.addEventListener("input", function() {
                    d.options[+el.getAttribute("data-oi")].value = el.value;
                });
                el.addEventListener("keydown", function(e) { e.stopPropagation(); });
            });
            detailPane.querySelectorAll(".fn-seg-optdel").forEach(function(el) {
                el.addEventListener("click", function() {
                    if (d.options.length <= 1) return;
                    d.options.splice(+el.getAttribute("data-oi"), 1);
                    renderToolCreator();
                });
            });
            var add = document.getElementById("tc-optadd");
            if (add) add.addEventListener("click", function() {
                d.options.push({ label: "", value: "" });
                renderToolCreator();
            });
            var create = document.getElementById("tc-create");
            if (create) create.addEventListener("click", submitToolCreator);
        }

        function submitToolCreator() {
            var d = _toolDraft;
            var key = (d.key || "").trim();
            if (!key) { showToast("A key is required"); return; }
            if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(key)) {
                showToast("Key must be a valid identifier"); return;
            }
            if (findTool(key)) { showToast("A tool named '" + key + "' already exists"); return; }

            // The host's Setting Builder has no free "number" type; a number
            // tool is a slider whose range the creator supplied.
            var wireType = (d.type === "number") ? "slider" : d.type;
            var def = { type: wireType, target: "settings", key: key,
                        label: (d.label || "").trim() || key,
                        hint: (d.hint || "").trim() || undefined };

            if (wireType === "slider") {
                var mn = Number(d.min) || 0;
                var mx = Number(d.max);
                if (isNaN(mx) || mx <= mn) mx = mn + (d.type === "number" ? 999 : 100);
                var st = Number(d.step) || 1;
                var dv = (d.numDefault != null) ? d.numDefault : mn;
                if (dv < mn) dv = mn; if (dv > mx) dv = mx;
                def.min = mn; def.max = mx; def.step = st;
                def.default = dv; def.value = dv;
                if (d.type === "slider" && (d.unit || "").trim()) def.unit = d.unit.trim();
            } else if (wireType === "toggle") {
                def.default = !!d.toggleDefault; def.value = def.default;
            } else if (wireType === "seg") {
                var opts = [];
                d.options.forEach(function(o) {
                    var l = (o.label || "").trim();
                    if (l === "") return;
                    var v = (o.value === "" || o.value == null) ? l : o.value;
                    var nv = Number(v);
                    opts.push({ label: l, value: (!isNaN(nv) && String(nv) === String(v)) ? nv : v });
                });
                if (opts.length === 0) { showToast("At least one option is required"); return; }
                def.options = opts;
                def.default = opts[0].value; def.value = def.default;
            }

            if (window.macroLab && window.macroLab.createTool) {
                window.macroLab.createTool(def);
                showToast("Creating tool: " + key);
                // Clear identity fields so the next tool starts fresh; the
                // pushed list refresh re-renders the picker with the new row.
                _toolDraft.key = "";
                _toolDraft.label = "";
                _toolDraft.hint = "";
                renderToolCreator();
            }
        }

        /* ── Render Detail Panel ───────────────────────────────────── */
        function renderDetail(fn) {
            var html = '';

            // Header
            html += '<div class="fn-detail-header">';
            html += '<div class="fn-detail-name">' + esc(fn.name) + '</div>';
            html += '<div class="fn-detail-desc">' + esc(fn.desc) + '</div>';
            html += '</div>';

            // Body (params)
            html += '<div class="fn-detail-body">';
            if (fn.params.length === 0) {
                html += '<div class="fn-no-params">This function takes no parameters.</div>';
            } else {
                html += '<div class="fn-params">';
                for (var i = 0; i < fn.params.length; i++) {
                    var p = fn.params[i];
                    html += renderParamField(p);
                }
                html += '</div>';
            }
            html += '</div>';

            // Footer
            html += '<div class="fn-detail-footer">';
            html += '<button class="fn-add-btn" id="fn-add-btn">Add Module</button>';
            html += '<span class="fn-tool-preview" id="fn-tool-preview"></span>';
            html += '</div>';

            detailPane.innerHTML = html;

            // Wire up param inputs
            wireParamInputs(fn);

            // Wire add button
            var addBtn = document.getElementById("fn-add-btn");
            if (addBtn) {
                addBtn.addEventListener("click", function() {
                    addToMacro(fn);
                });
            }

            updatePreview(fn);
        }

        /* ── Render a single parameter field ───────────────────────── */
        // The <option> list for a tool picker. When there are no tools, the
        // sole disabled row tells the person what to do about it.
        function toolOptionsHtml(selectedKey) {
            if (_tools.length === 0) {
                return '<option value="" disabled selected>No tools — create one first</option>';
            }
            var html = '<option value="" disabled' + (selectedKey ? '' : ' selected') + '>Pick a tool…</option>';
            _tools.forEach(function(t) {
                html += '<option value="' + esc(t.key) + '"'
                    + (t.key === selectedKey ? ' selected' : '') + '>'
                    + esc((t.label || t.key) + '  ·  ' + t.type) + '</option>';
            });
            return html;
        }

        function renderParamField(p) {
            var bindable = !!BINDABLE[p.type];
            var bound = bindable && !!_paramBind[p.name];

            var html = '<div class="fn-param-group fn-param' + (bound ? ' bound' : '')
                + '" data-pname="' + esc(p.name) + '">';
            html += '<div class="fn-param-label">' + esc(p.label);
            html += ' <span class="fn-param-type">' + esc(p.type) + '</span>';
            if (p.required) html += ' <span style="color:var(--danger)">*</span>';
            if (bindable) {
                html += '<span class="fn-bind-switch">'
                    + '<button class="fn-bind-opt' + (bound ? '' : ' on') + '" data-bindmode="literal" data-param="'
                    + esc(p.name) + '">Value</button>'
                    + '<button class="fn-bind-opt' + (bound ? ' on' : '') + '" data-bindmode="tool" data-param="'
                    + esc(p.name) + '">Tool</button></span>';
            }
            html += '</div>';

            html += '<div class="fn-param-literal" data-lit="' + esc(p.name) + '"'
                + (bound ? ' style="display:none"' : '') + '>';
            switch (p.type) {
                case "string":
                    html += '<input type="text" data-param="' + esc(p.name) + '" placeholder="Enter text\u2026" autocomplete="off" autocorrect="off" autocapitalize="off" spellcheck="false">';
                    break;

                case "number":
                    html += '<input type="number" data-param="' + esc(p.name) + '" value="0" step="1">';
                    break;

                case "key":
                    html += '<div class="fn-key-capture">';
                    html += '<button class="fn-key-btn" data-param="' + esc(p.name) + '" data-key-capture>Click to set</button>';
                    html += '<span class="fn-key-hint">press a key\u2026</span>';
                    html += '</div>';
                    break;

                case "mods":
                    html += '<div class="fn-mods-row">';
                    for (var i = 0; i < MOD_LIST.length; i++) {
                        html += '<button class="fn-mod-chip" data-mod="' + MOD_LIST[i] + '">' + MOD_LIST[i] + '</button>';
                    }
                    html += '</div>';
                    break;

                case "condition":
                    html += '<textarea class="fn-code-input" data-param="' + esc(p.name) + '" rows="1" placeholder="Lua expression…" spellcheck="false" autocomplete="off" autocorrect="off" autocapitalize="off"></textarea>';
                    break;

                case "code":
                    html += '<textarea class="fn-code-input" data-param="' + esc(p.name) + '" rows="3" placeholder="Lua source…" spellcheck="false" autocomplete="off" autocorrect="off" autocapitalize="off"></textarea>';
                    break;
            }
            html += '</div>';

            if (bindable) {
                var sel = _paramBind[p.name] || "";
                html += '<div class="fn-param-tool" data-toolwrap="' + esc(p.name) + '"'
                    + (bound ? '' : ' style="display:none"') + '>';
                html += '<select class="fn-tool-select" data-toolsel="' + esc(p.name) + '">'
                    + toolOptionsHtml(sel) + '</select>';
                html += '</div>';
            }

            html += '</div>';
            return html;
        }

        /* ── Wire up input events ──────────────────────────────────── */
        function wireParamInputs(fn) {
            // Text and number inputs, plus condition/code textareas.
            var inputs = detailPane.querySelectorAll("input[data-param], textarea[data-param]");
            for (var i = 0; i < inputs.length; i++) {
                (function(inp) {
                    var name = inp.getAttribute("data-param");
                    inp.addEventListener("input", function() {
                        if (inp.type === "number") {
                            _paramValues[name] = parseFloat(inp.value) || 0;
                        } else {
                            _paramValues[name] = inp.value;
                        }
                        updatePreview(fn);
                    });
                    // Textareas capture typing that would otherwise reach the
                    // canvas/key-capture handlers.
                    if (inp.tagName === "TEXTAREA") {
                        inp.addEventListener("keydown", function(e) { e.stopPropagation(); });
                    }
                })(inputs[i]);
            }

            // Key capture buttons
            var keyBtns = detailPane.querySelectorAll("[data-key-capture]");
            for (var j = 0; j < keyBtns.length; j++) {
                (function(btn) {
                    var name = btn.getAttribute("data-param");
                    btn.addEventListener("click", function(e) {
                        e.stopPropagation();
                        startKeyCapture(name, btn, fn);
                    });
                })(keyBtns[j]);
            }

            // Modifier chips
            var modChips = detailPane.querySelectorAll("[data-mod]");
            for (var k = 0; k < modChips.length; k++) {
                (function(chip) {
                    var mod = chip.getAttribute("data-mod");
                    chip.addEventListener("click", function() {
                        _modState[mod] = !_modState[mod];
                        chip.classList.toggle("on", _modState[mod]);
                        // Update mods param value
                        var mods = [];
                        for (var m = 0; m < MOD_LIST.length; m++) {
                            if (_modState[MOD_LIST[m]]) mods.push(MOD_LIST[m]);
                        }
                        // Find the mods param name
                        for (var n = 0; n < fn.params.length; n++) {
                            if (fn.params[n].type === "mods") {
                                _paramValues[fn.params[n].name] = mods;
                                break;
                            }
                        }
                        updatePreview(fn);
                    });
                })(modChips[k]);
            }

            // Value/Tool switch — flips a parameter between a literal and a
            // tool binding. Switching to Tool with no tool chosen yet leaves the
            // binding empty until the select fires; switching back to Value
            // clears the binding and restores the literal value in state.
            var switches = detailPane.querySelectorAll(".fn-bind-opt");
            for (var s = 0; s < switches.length; s++) {
                (function(btn) {
                    var name = btn.getAttribute("data-param");
                    var mode = btn.getAttribute("data-bindmode");
                    btn.addEventListener("click", function() {
                        if (window.playSlot) playSlot("interact");
                        var group = detailPane.querySelector('.fn-param[data-pname="' + name + '"]');
                        if (!group) return;
                        var lit  = group.querySelector('[data-lit="' + name + '"]');
                        var tool = group.querySelector('[data-toolwrap="' + name + '"]');
                        var opts = group.querySelectorAll('.fn-bind-opt');
                        opts.forEach(function(o) {
                            o.classList.toggle("on", o.getAttribute("data-bindmode") === mode);
                        });
                        if (mode === "tool") {
                            group.classList.add("bound");
                            if (lit)  lit.style.display  = "none";
                            if (tool) tool.style.display = "";
                            var selEl = group.querySelector('[data-toolsel="' + name + '"]');
                            _paramBind[name] = (selEl && selEl.value) ? selEl.value : "";
                            if (_paramBind[name]) {
                                _paramValues[name] = { __toolRef: _paramBind[name] };
                            }
                        } else {
                            group.classList.remove("bound");
                            if (lit)  lit.style.display  = "";
                            if (tool) tool.style.display = "none";
                            delete _paramBind[name];
                            var litInput = group.querySelector('[data-param="' + name + '"]');
                            if (litInput) {
                                _paramValues[name] = (litInput.type === "number")
                                    ? (parseFloat(litInput.value) || 0) : litInput.value;
                            } else {
                                _paramValues[name] = "";
                            }
                        }
                        updatePreview(fn);
                    });
                })(switches[s]);
            }

            // Tool selects — pick which tool a bound parameter reads from.
            var toolSels = detailPane.querySelectorAll(".fn-tool-select");
            for (var ts = 0; ts < toolSels.length; ts++) {
                (function(sel) {
                    var name = sel.getAttribute("data-toolsel");
                    sel.addEventListener("change", function() {
                        _paramBind[name] = sel.value;
                        _paramValues[name] = { __toolRef: sel.value };
                        updatePreview(fn);
                    });
                })(toolSels[ts]);
            }
        }

        /* ── Key Capture ───────────────────────────────────────────── */
        function startKeyCapture(paramName, btn, fn) {
            // Cancel any existing capture
            if (_keyCapture) {
                var prevBtn = detailPane.querySelector(".fn-key-btn.capturing");
                if (prevBtn) prevBtn.classList.remove("capturing");
                document.removeEventListener("keydown", _keyCaptureHandler, true);
            }

            _keyCapture = paramName;
            btn.classList.add("capturing");
            btn.textContent = "\u2026";

            function handler(e) {
                e.preventDefault();
                e.stopPropagation();

                // Build key name
                var key = normalizeKey(e);
                _paramValues[paramName] = key;

                btn.classList.remove("capturing");
                btn.textContent = key || "???";
                btn.classList.remove("fn-key-btn");
                btn.classList.add("fn-key-btn");

                document.removeEventListener("keydown", handler, true);
                _keyCapture = null;
                _keyCaptureHandler = null;
                updatePreview(fn);
            }

            _keyCaptureHandler = handler;
            document.addEventListener("keydown", handler, true);
        }

        var _keyCaptureHandler = null;

        function normalizeKey(e) {
            // Map common keys to ms naming
            var map = {
                " ": "space",
                "ArrowUp": "up",
                "ArrowDown": "down",
                "ArrowLeft": "left",
                "ArrowRight": "right",
                "Backspace": "delete",
                "Escape": "escape",
                "Enter": "return",
                "Tab": "tab"
            };
            if (map[e.key]) return map[e.key];
            if (e.key.length === 1) return e.key.toLowerCase();
            return e.key.toLowerCase();
        }

        /* ── Step Preview ──────────────────────────────────────────── */
        function updatePreview(fn) {
            var el = document.getElementById("fn-tool-preview");
            if (!el) return;

            var parts = [];
            for (var i = 0; i < fn.params.length; i++) {
                var p = fn.params[i];
                var val = _paramValues[p.name];
                if (val && typeof val === "object" && val.__toolRef) {
                    // A bound parameter previews as the call it compiles to.
                    parts.push(p.name + ':ms.settings.get("' + val.__toolRef + '")');
                } else if (p.type === "mods") {
                    parts.push(p.name + ":[" + (val || []).join(",") + "]");
                } else if (p.type === "string") {
                    parts.push(p.name + ':"' + (val || "") + '"');
                } else {
                    parts.push(p.name + ":" + (val !== undefined ? val : ""));
                }
            }
            el.textContent = fn.name + "(" + parts.join(", ") + ")";
        }

        /* ── Add to Macro ──────────────────────────────────────────── */
        function addToMacro(fn) {
            var params = {};
            for (var i = 0; i < fn.params.length; i++) {
                var p = fn.params[i];
                var val = _paramValues[p.name];
                // A parameter switched to Tool but never given one is unfinished.
                if (_paramBind[p.name] !== undefined && !_paramBind[p.name]) {
                    showToast("Pick a tool for: " + p.label);
                    return;
                }
                if (val && typeof val === "object" && val.__toolRef) {
                    params[p.name] = { __toolRef: val.__toolRef };
                    continue;
                }
                if (p.required && p.type === "string" && (!val || val === "")) {
                    showToast("Missing required field: " + p.label);
                    return;
                }
                if (p.required && p.type === "key" && (!val || val === "")) {
                    showToast("Missing required field: " + p.label);
                    return;
                }
                if (p.type === "mods") {
                    params[p.name] = val || [];
                } else {
                    params[p.name] = val;
                }
            }

            // Add step directly to canvas via macroLab API
            if (window.macroLab && window.macroLab.addTool) {
                window.macroLab.addTool({ action: fn.name, params: params });
            }
            // Also send to Lua for bus event
            window.shellPost("macros", "addTool", {
                action: fn.name,
                params: params
            });

            showToast("Added: " + fn.name);
        }

        /* ── Toast ─────────────────────────────────────────────────── */
        function showToast(msg) {
            toast.textContent = msg;
            toast.classList.add("show");
            if (_toastTimer) clearTimeout(_toastTimer);
            _toastTimer = setTimeout(function() {
                toast.classList.remove("show");
                _toastTimer = null;
            }, 1800);
        }

        /* ── Escape HTML ───────────────────────────────────────────── */
        function esc(s) {
            var d = document.createElement("div");
            d.appendChild(document.createTextNode(s));
            return d.innerHTML;
        }

        /* ── Search Input Handler ──────────────────────────────────── */
        searchInput.addEventListener("input", function() {
            renderList(searchInput.value);
        });

        // Prevent key capture from swallowing search input keystrokes
        searchInput.addEventListener("keydown", function(e) {
            e.stopPropagation();
        });

        /* ── Panel handler (called by consolidated registerPanel below) ── */
        function _fnPickerHandler(action, body) {
            if (action === "functions" && Array.isArray(body)) {
                // Future: merge dynamically-loaded functions from Lua
            }
            if (action === "selectFunction" && body && body.name) {
                selectFunction(body.name);
            }
        }

        // Refresh the tool list (pushed from Lua). Keeps the shared global in
        // sync so the inline step editor can read the same set, re-renders the
        // list, and — if a tool detail or a param's tool picker is open —
        // refreshes what is on screen so a just-created tool shows up at once.
        function setToolList(list) {
            _tools = Array.isArray(list) ? list : [];
            window.msMacroTools = _tools;
            renderList(searchInput.value);
            if (_view === "toolCreator") {
                // Leave the creator as-is unless the new tool is now present.
                if (_selectedId && findTool(_selectedId)) selectTool(_selectedId);
            } else if (_view === "tool" && _selectedId) {
                var t = findTool(_selectedId);
                if (t) renderToolDetail(t); else { detailPane.innerHTML = ''; _view = "module"; }
            } else {
                // A module detail may be open and mid-edit — re-rendering it
                // would wipe half-typed fields — so only the tool <select>
                // option lists are refreshed in place, keeping each current
                // selection.
                var sels = detailPane.querySelectorAll(".fn-tool-select");
                for (var s = 0; s < sels.length; s++) {
                    var name = sels[s].getAttribute("data-toolsel");
                    sels[s].innerHTML = toolOptionsHtml(_paramBind[name] || "");
                }
            }
        }

        /* ── External API: allow ms.shell.eval to call in ──────────── */
        window.fnPicker = {
            select: selectFunction,
            registry: REGISTRY,
            showToast: showToast,
            setToolList: setToolList,
            handler: _fnPickerHandler
        };

        /* ── Initial Render ────────────────────────────────────────── */
        renderList("");

    })();

(function() {
    "use strict";

    var _svgCache = {};

    /* ── SVG loader — uses inline ICONS from shell, falls back to XHR ── */
    function _fetchSVG(name) {
        if (_svgCache[name]) return Promise.resolve(_svgCache[name]);
        // Use inline ICONS from the shell's shared script block
        if (window.ICONS && window.ICONS[name]) {
            _svgCache[name] = '<svg class="icon" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">' + window.ICONS[name] + '</svg>';
            return Promise.resolve(_svgCache[name]);
        }
        return Promise.resolve("");
    }

    /* ── Action → icon mapping ───────────────────────────────────── */
    var ACTION_ICON = {
        "ms.type":"keyboard","ms.press":"keyboard","ms.hold":"keyboard","ms.release":"keyboard",
        "ms.wait":"timer","ms.copy":"clipboard","ms.paste":"clipboard",
        "ms.cam":"camera","ms.cam.rebalance":"camera","ms.cam.reset":"camera",
        "ms.Mouse":"click","ms.click":"click","ms.scroll":"scroll","ms.move":"move","ms.select":"select",
        "ms.search":"search","ms.record":"record","ms.stop":"stop","ms.pause":"pause",
        "ms.play":"play","ms.save":"save","ms.load":"upload","ms.alert":"alert",
        "ms.refresh":"refresh","ms.pixelScan":"pixelscan","ms.window":"window",
        "ms.input":"inputs","ms.variable":"variable","ms.watch":"watcher",
        "ms.sound":"sound","ms.gamepad":"controller","ms.gamepadStart":"controller","ms.gamepadBind":"controller",
        "ms.setMacros":"power","ms.enable":"power","ms.disable":"power",
        "ms.screenshot":"camera","ms.clipChanged":"clipboard",
        "ms.randWait":"timer","ms.jitter":"timer","ms.waitPixel":"pixelscan","ms.waitNotPixel":"pixelscan",
        "ms.waitApp":"search","ms.waitNotApp":"search",
        "ms.focus":"window","ms.appRunning":"window","ms.appIsFront":"window",
        "ms.toggle":"keyboard","ms.multiPress":"keyboard",
        "ms.saveCursor":"select","ms.restoreCursor":"select",
        "ms.setVolume":"sound","ms.mute":"sound","ms.unmute":"sound",
        "ms.drag":"drag",
        "if":"branch","for":"loop","while":"repeat","repeat":"repeat","else":"branch",
        "var_set":"variable","var_add":"variable","var_sub":"variable","var_mul":"variable",
        "comment":"inputs","code":"macros"
    };

    function iconFor(action) { return ACTION_ICON[action] || "macros"; }

    /* ── Param summary ───────────────────────────────────────────── */
    function paramSummary(action, params) {
        if (!params) return "";
        var keys = Object.keys(params);
        if (keys.length === 0) return "";
        if (action === "if" || action === "while" || action === "repeat") return params.condition || "";
        if (action === "for") return (params.var||"i") + " = " + (params.from||1) + " → " + (params.to||1);
        if (action === "comment") return params.text || "";
        if (action === "code") return (params.source||"").split("\n")[0] || "";
        if (action === "var_set") return (params.name||"v") + " = " + (params.value!==undefined?params.value:"");
        if (action === "var_add" || action === "var_sub" || action === "var_mul") {
            var op = action==="var_add"?"+":action==="var_sub"?"-":"*";
            return (params.name||"v") + " " + op + "= " + (params.amount!==undefined?params.amount:1);
        }
        var parts = [];
        for (var i = 0; i < Math.min(keys.length, 2); i++) {
            var k = keys[i], v = params[k];
            if (Array.isArray(v)) { if (v.length === 0) continue; v = v.join("+"); }
            if (typeof v === "string" && v.length > 16) v = v.slice(0,14) + "…";
            parts.push(k + ": " + v);
        }
        return parts.join(", ");
    }

    /* ── Step ID generator ───────────────────────────────────────── */
    var _toolIdCounter = 0;
    function nextToolId() { return "_s" + (++_toolIdCounter) + "_" + Date.now().toString(36); }

    function deepClone(o) { return JSON.parse(JSON.stringify(o)); }

    /* ── ToolCanvas class (IIFE version) ─────────────────────────── */
    function ToolCanvas(container, opts) {
        this._el = container;
        this._onChange = (opts && opts.onChange) || function(){};
        this._onSelect = (opts && opts.onSelect) || function(){};
        this._tools = [];
        this._map = {};
        this._selId = null;
        this._dragId = null;
        this._root = document.createElement("div");
        this._root.className = "tool-canvas";
        this._el.appendChild(this._root);
        this._renderEmpty();
        this._preloadIcons();
    }

    ToolCanvas.prototype._preloadIcons = function() {
        var needed = ["drag","close","chevdown","macros","copy","paste"];
        for (var a in ACTION_ICON) { if (needed.indexOf(ACTION_ICON[a]) === -1) needed.push(ACTION_ICON[a]); }
        var self = this;
        var chain = Promise.resolve();
        needed.forEach(function(n) { chain = chain.then(function(){ return _fetchSVG(n); }); });
    };

    ToolCanvas.prototype._assignIds = function(steps) {
        for (var i = 0; i < steps.length; i++) {
            var s = steps[i];
            if (!s._sid) s._sid = nextToolId();
            this._map[s._sid] = s;
            if (s.then) this._assignIds(s.then);
            if (s.else) this._assignIds(s.else);
            if (s.body) this._assignIds(s.body);
        }
    };

    ToolCanvas.prototype.load = function(steps) {
        this._tools = steps || [];
        this._map = {};
        this._assignIds(this._tools);
        this._selId = null;
        this._render();
    };

    // Container actions carry nested child lists. Seed them on insert so the
    // block renders its droppable "then/else/body" nests immediately, even
    // before anything is dropped in.
    function seedContainer(step) {
        if (step.action === "if") {
            if (!step.then) step.then = [];
            if (!step.else) step.else = [];
        } else if (step.action === "for" || step.action === "while" || step.action === "repeat") {
            if (!step.body) step.body = [];
        }
    }

    ToolCanvas.prototype.addTool = function(def, afterId) {
        var step = deepClone(def);
        step._sid = nextToolId();
        seedContainer(step);
        this._map[step._sid] = step;
        if (afterId) {
            var idx = this._findIdx(this._tools, afterId);
            if (idx !== -1) this._tools.splice(idx+1, 0, step);
            else this._tools.push(step);
        } else {
            this._tools.push(step);
        }
        this._render();
        this._fireChange();
    };

    ToolCanvas.prototype.removeTool = function(sid) {
        if (this._removeFrom(this._tools, sid)) {
            delete this._map[sid];
            if (this._selId === sid) this._selId = null;
            this._render();
            this._fireChange();
        }
    };

    ToolCanvas.prototype._removeFrom = function(list, sid) {
        for (var i = 0; i < list.length; i++) {
            if (list[i]._sid === sid) { list.splice(i,1); return true; }
            var s = list[i];
            if (s.then && this._removeFrom(s.then, sid)) return true;
            if (s.else && this._removeFrom(s.else, sid)) return true;
            if (s.body && this._removeFrom(s.body, sid)) return true;
        }
        return false;
    };

    ToolCanvas.prototype._findIdx = function(list, sid) {
        for (var i = 0; i < list.length; i++) { if (list[i]._sid === sid) return i; }
        return -1;
    };

    ToolCanvas.prototype.moveTool = function(dragId, targetId, pos) {
        var step = this._map[dragId];
        if (!step) return;
        this._removeFrom(this._tools, dragId);
        if (pos === "nest") {
            var tgt = this._map[targetId];
            if (tgt) {
                if (tgt.action === "if") { if(!tgt.then) tgt.then=[]; tgt.then.push(step); }
                else { if(!tgt.body) tgt.body=[]; tgt.body.push(step); }
            }
        } else {
            var ti = this._findIdx(this._tools, targetId);
            if (ti !== -1) this._tools.splice(pos==="above"?ti:ti+1, 0, step);
            else this._tools.push(step);
        }
        this._render();
        this._fireChange();
    };

    ToolCanvas.prototype.serialize = function() {
        return this._strip(deepClone(this._tools));
    };

    ToolCanvas.prototype._strip = function(steps) {
        for (var i=0;i<steps.length;i++) {
            delete steps[i]._sid;
            if (steps[i].then) this._strip(steps[i].then);
            if (steps[i].else) this._strip(steps[i].else);
            if (steps[i].body) this._strip(steps[i].body);
        }
        return steps;
    };

    ToolCanvas.prototype._fireChange = function() { this._onChange(this.serialize()); };

    ToolCanvas.prototype._render = function() {
        this._root.innerHTML = "";
        if (this._tools.length === 0) { this._renderEmpty(); return; }
        for (var i=0;i<this._tools.length;i++) {
            this._root.appendChild(this._renderTool(this._tools[i]));
        }
    };

    ToolCanvas.prototype._renderEmpty = function() {
        this._root.innerHTML = "";
        var d = document.createElement("div");
        d.className = "tool-canvas-empty";
        d.innerHTML = '<span class="tool-canvas-empty-icon"><svg class="icon" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M16.6582 9.28638C18.098 10.1862 18.8178 10.6361 19.0647 11.2122C19.2803 11.7152 19.2803 12.2847 19.0647 12.7878C18.8178 13.3638 18.098 13.8137 16.6582 14.7136L9.896 18.94C8.29805 19.9387 7.49907 20.4381 6.83973 20.385C6.26501 20.3388 5.73818 20.0469 5.3944 19.584C5 19.053 5 18.1108 5 16.2264V7.77357C5 5.88919 5 4.94701 5.3944 4.41598C5.73818 3.9531 6.26501 3.66111 6.83973 3.6149C7.49907 3.5619 8.29805 4.06126 9.896 5.05998L16.6582 9.28638Z" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/></svg></span>No modules yet<br><span style="font-size:10px">Click <b>+ Add Module</b> to begin</span>';
        this._root.appendChild(d);
    };

    ToolCanvas.prototype._isContainer = function(s) {
        return s.action==="if" || s.action==="for" || s.action==="while" || s.action==="repeat";
    };

    ToolCanvas.prototype._renderTool = function(step) {
        return this._isContainer(step) ? this._renderContainer(step) : this._renderLeaf(step);
    };

    ToolCanvas.prototype._renderLeaf = function(step) {
        var self = this;
        var el = document.createElement("div");
        el.className = "tool-block" + (step._sid===this._selId?" selected":"");
        el.setAttribute("data-sid", step._sid);
        el.setAttribute("draggable","true");

        var h = document.createElement("div");
        h.className = "tool-drag-handle";
        h.innerHTML = _svgCache["drag"] || '<svg class="icon" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M12 3V9M12 3L9 6M12 3L15 6M12 15V21M12 21L15 18M12 21L9 18M3 12H9M3 12L6 15M3 12L6 9M15 12H21M21 12L18 9M21 12L18 15" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>';
        el.appendChild(h);

        var ic = document.createElement("div");
        ic.className = "tool-icon";
        ic.innerHTML = _svgCache[iconFor(step.action)] || "";
        el.appendChild(ic);

        var nm = document.createElement("span");
        nm.className = "tool-action-name";
        nm.textContent = step.action;
        el.appendChild(nm);

        var pm = document.createElement("span");
        pm.className = "tool-params";
        pm.textContent = paramSummary(step.action, step.params);
        el.appendChild(pm);

        el.appendChild(this._buildToolActions(step));

        el.addEventListener("click", function(e) {
            if (e.target.closest(".tool-action-btn") || e.target.closest(".tool-drag-handle")) return;
            self._selectTool(step._sid);
        });

        this._wireDrag(el, step);
        return el;
    };

    // Copy / paste / delete controls shared by leaf and container blocks.
    // Copy loads this module onto the clipboard; Paste (revealed only once
    // the clipboard holds a module) drops a copy directly after this one.
    ToolCanvas.prototype._buildToolActions = function(step) {
        var self = this;
        var acts = document.createElement("div");
        acts.className = "tool-actions";

        var cp = document.createElement("div");
        cp.className = "tool-action-btn copy";
        cp.title = "Copy module";
        cp.innerHTML = _svgCache["copy"] || (window.icon ? window.icon("copy") : "");
        cp.addEventListener("click", function(e) { e.stopPropagation(); self.copyStep(step._sid); });
        acts.appendChild(cp);

        var pt = document.createElement("div");
        pt.className = "tool-action-btn paste";
        pt.title = "Paste module after this one";
        pt.innerHTML = _svgCache["paste"] || (window.icon ? window.icon("paste") : "");
        pt.addEventListener("click", function(e) {
            e.stopPropagation();
            self.pasteAfterId(step._sid);
        });
        acts.appendChild(pt);

        var db = document.createElement("div");
        db.className = "tool-action-btn del";
        db.title = "Delete module";
        db.innerHTML = _svgCache["close"] || '<svg class="icon" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><g id="Edit / Close_Circle"><path id="Vector" d="M9 9L11.9999 11.9999M11.9999 11.9999L14.9999 14.9999M11.9999 11.9999L9 14.9999M11.9999 11.9999L14.9999 9M12 21C7.02944 21 3 16.9706 3 12C3 7.02944 7.02944 3 12 3C16.9706 3 21 7.02944 21 12C21 16.9706 16.9706 21 12 21Z" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></g></svg>';
        db.addEventListener("click", function(e) { e.stopPropagation(); self.removeTool(step._sid); });
        acts.appendChild(db);

        return acts;
    };

    ToolCanvas.prototype._renderContainer = function(step) {
        var self = this;
        var wrap = document.createElement("div");
        wrap.className = "tool-block-container";
        wrap.setAttribute("data-sid", step._sid);

        var header = document.createElement("div");
        header.className = "tool-block" + (step._sid===this._selId?" selected":"");
        header.setAttribute("data-sid", step._sid);
        header.setAttribute("draggable","true");

        var h = document.createElement("div");
        h.className = "tool-drag-handle";
        h.innerHTML = _svgCache["drag"] || '<svg class="icon" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M12 3V9M12 3L9 6M12 3L15 6M12 15V21M12 21L15 18M12 21L9 18M3 12H9M3 12L6 15M3 12L6 9M15 12H21M21 12L18 9M21 12L18 15" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>';
        header.appendChild(h);

        var tg = document.createElement("div");
        tg.className = "tool-nest-toggle";
        tg.innerHTML = _svgCache["chevdown"] || '<svg class="icon" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M7 13L12 18L17 13M7 6L12 11L17 6" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>';
        tg.addEventListener("click", function(e) {
            e.stopPropagation();
            tg.classList.toggle("collapsed");
            var b = wrap.querySelector(".tool-nest-body");
            if (b) b.classList.toggle("collapsed");
        });
        header.appendChild(tg);

        var ic = document.createElement("div");
        ic.className = "tool-icon";
        ic.innerHTML = _svgCache[iconFor(step.action)] || "";
        header.appendChild(ic);

        var nm = document.createElement("span");
        nm.className = "tool-action-name";
        nm.textContent = step.action;
        header.appendChild(nm);

        var pm = document.createElement("span");
        pm.className = "tool-params";
        pm.textContent = paramSummary(step.action, step.params);
        header.appendChild(pm);

        header.appendChild(this._buildToolActions(step));

        header.addEventListener("click", function(e) {
            if (e.target.closest(".tool-action-btn")||e.target.closest(".tool-drag-handle")||e.target.closest(".tool-nest-toggle")) return;
            self._selectTool(step._sid);
        });
        this._wireDrag(header, step);

        wrap.appendChild(header);

        if (step.action === "if") {
            var tl = document.createElement("div"); tl.className="tool-nest-label"; tl.textContent="then"; wrap.appendChild(tl);
            wrap.appendChild(this._renderNest(step.then||[], "then", step));
            var el2 = document.createElement("div"); el2.className="tool-nest-label"; el2.textContent="else"; wrap.appendChild(el2);
            wrap.appendChild(this._renderNest(step.else||[], "else", step));
        } else {
            wrap.appendChild(this._renderNest(step.body||[], "body", step));
        }
        return wrap;
    };

    ToolCanvas.prototype._renderNest = function(steps, branch, parent) {
        var self = this;
        var body = document.createElement("div");
        body.className = "tool-nest-body";
        body.setAttribute("data-nest-parent", parent._sid);
        body.setAttribute("data-nest-branch", branch);

        if (steps.length === 0) {
            var emp = document.createElement("div");
            emp.className = "tool-nest-body-empty";
            emp.textContent = "empty";
            body.appendChild(emp);
        } else {
            for (var i=0;i<steps.length;i++) body.appendChild(this._renderTool(steps[i]));
        }

        body.addEventListener("dragover", function(e) {
            if (!self._dragId) return; e.preventDefault(); e.stopPropagation();
            e.dataTransfer.dropEffect = "move"; body.classList.add("drag-target");
        });
        body.addEventListener("dragleave", function() { body.classList.remove("drag-target"); });
        body.addEventListener("drop", function(e) {
            e.preventDefault(); e.stopPropagation();
            if (!self._dragId) return;
            var step = self._map[self._dragId]; if (!step) return;
            self._removeFrom(self._tools, self._dragId);
            if (branch==="then") { if(!parent.then)parent.then=[]; parent.then.push(step); }
            else if (branch==="else") { if(!parent.else)parent.else=[]; parent.else.push(step); }
            else { if(!parent.body)parent.body=[]; parent.body.push(step); }
            body.classList.remove("drag-target");
            self._dragId = null;
            self._render(); self._fireChange();
        });
        return body;
    };

    ToolCanvas.prototype._selectTool = function(sid) {
        this._selId = sid;
        var prev = this._root.querySelector(".tool-block.selected");
        if (prev) prev.classList.remove("selected");
        var el = this._root.querySelector('[data-sid="'+sid+'"] > .tool-block[data-sid="'+sid+'"], .tool-block[data-sid="'+sid+'"]');
        if (el) el.classList.add("selected");
        this._onSelect(sid, this._map[sid]);
    };

    ToolCanvas.prototype._isDesc = function(pid, cid) {
        var p = this._map[pid]; if (!p) return false;
        var ch = [].concat(p.then||[], p.else||[], p.body||[]);
        for (var i=0;i<ch.length;i++) {
            if (ch[i]._sid===cid) return true;
            if (this._isDesc(ch[i]._sid, cid)) return true;
        }
        return false;
    };

    ToolCanvas.prototype._wireDrag = function(el, step) {
        var self = this;
        el.addEventListener("dragstart", function(e) {
            self._dragId = step._sid;
            el.classList.add("dragging");
            e.dataTransfer.effectAllowed = "move";
            e.dataTransfer.setData("text/plain", step._sid);
            var ghost = el.cloneNode(true);
            ghost.style.width = el.offsetWidth + "px"; ghost.style.opacity = "0.7";
            ghost.style.position = "absolute"; ghost.style.top = "-1000px";
            document.body.appendChild(ghost);
            e.dataTransfer.setDragImage(ghost, 10, 10);
            requestAnimationFrame(function() { ghost.remove(); });
        });
        el.addEventListener("dragend", function() {
            self._dragId = null; el.classList.remove("dragging");
            self._clearDrops();
        });
        el.addEventListener("dragover", function(e) {
            if (!self._dragId || self._dragId === step._sid) return;
            e.preventDefault(); e.dataTransfer.dropEffect = "move";
            var rect = el.getBoundingClientRect();
            var y = e.clientY - rect.top, h = rect.height;
            var isC = self._isContainer(step);
            el.classList.remove("drag-over-above","drag-over-below","drag-over-nest");
            if (isC && y > h*0.3 && y < h*0.7) el.classList.add("drag-over-nest");
            else if (y < h/2) el.classList.add("drag-over-above");
            else el.classList.add("drag-over-below");
        });
        el.addEventListener("dragleave", function() {
            el.classList.remove("drag-over-above","drag-over-below","drag-over-nest");
        });
        el.addEventListener("drop", function(e) {
            e.preventDefault(); e.stopPropagation();
            if (!self._dragId || self._dragId === step._sid) return;
            var rect = el.getBoundingClientRect();
            var y = e.clientY - rect.top, h = rect.height;
            var isC = self._isContainer(step);
            var pos;
            if (isC && y > h*0.3 && y < h*0.7) pos = "nest";
            else if (y < h/2) pos = "above";
            else pos = "below";
            if (pos === "nest" && self._isDesc(step._sid, self._dragId)) { self._clearDrops(); return; }
            self.moveTool(self._dragId, step._sid, pos);
            self._clearDrops();
        });
    };

    ToolCanvas.prototype._clearDrops = function() {
        this._root.querySelectorAll(".drag-over-above,.drag-over-below,.drag-over-nest").forEach(function(el) {
            el.classList.remove("drag-over-above","drag-over-below","drag-over-nest");
        });
        this._root.querySelectorAll(".drag-target").forEach(function(el) { el.classList.remove("drag-target"); });
    };

    ToolCanvas.prototype.updateTool = function(sid, params) {
        var s = this._map[sid]; if (!s) return;
        for (var k in params) { if (params.hasOwnProperty(k)) s.params[k] = params[k]; }
        this._render(); this._fireChange();
    };

    ToolCanvas.prototype.getSelectedId = function() { return this._selId; };
    ToolCanvas.prototype.getSelectedTool = function() { return this._selId ? this._map[this._selId] : null; };

    /* ── Clipboard (copy / cut / paste) ─────────────────────────────── */
    // Copy a specific module (by id) onto the module clipboard. Adding the
    // .has-clip class to the canvas root is what reveals every module's paste
    // button — see the CSS rule that gates .tool-action-btn.paste.
    ToolCanvas.prototype.copyStep = function(sid) {
        var step = sid ? this._map[sid] : null;
        if (!step) return false;
        var clone = deepClone(step);
        this._strip([clone]);
        try { navigator.clipboard.writeText(JSON.stringify(clone)); } catch(e) {}
        this._clipboard = clone;
        if (this._root) this._root.classList.add("has-clip");
        return true;
    };
    ToolCanvas.prototype.copySelected = function() {
        return this.copyStep(this._selId);
    };
    ToolCanvas.prototype.cutSelected = function() {
        var sid = this._selId;
        if (!sid || !this._map[sid]) return false;
        this.copyStep(sid);
        this.removeTool(sid);
        return true;
    };
    // Paste the clipboard module after `afterId` (or at the end when null).
    ToolCanvas.prototype.pasteAfterId = function(afterId) {
        if (!this._clipboard) return false;
        var clone = deepClone(this._clipboard);
        clone._sid = nextToolId();
        this._map[clone._sid] = clone;
        if (clone.then) this._assignIds(clone.then);
        if (clone.else) this._assignIds(clone.else);
        if (clone.body) this._assignIds(clone.body);
        if (afterId) {
            var idx = this._findIdx(this._tools, afterId);
            if (idx !== -1) this._tools.splice(idx + 1, 0, clone);
            else this._tools.push(clone);
        } else {
            this._tools.push(clone);
        }
        this._selId = clone._sid;
        this._render();
        if (this._root) this._root.classList.add("has-clip");
        this._fireChange();
        return true;
    };
    ToolCanvas.prototype.pasteAfter = function() {
        return this.pasteAfterId(this._selId);
    };

    /* ── Macro Management State ──────────────────────────────────── */
    var _currentMacroId = null;
    var _currentMacroDef = null;
    var _macroDirty = false;
    var _canvas = null;
    var _mtabs = null;

    /* ── Layout Setup ────────────────────────────────────────────── */
    var slot = document.getElementById("slot-macros");
    if (!slot) return;

    // The existing function picker is already in slot-macros as a .fn-picker child.
    // We restructure: wrap it in a layout with toolbar + step canvas + overlay.

    var existingPicker = slot.querySelector(".fn-picker");

    // Create the macros layout wrapper
    var layout = document.createElement("div");
    layout.className = "macros-layout";

    // ── Toolbar ──
    var toolbar = document.createElement("div");
    toolbar.className = "macro-toolbar";

    var macroLabel = document.createElement("span");
    macroLabel.style.cssText = "font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.6px;color:var(--text3);margin-right:4px";
    macroLabel.textContent = "Macro";
    toolbar.appendChild(macroLabel);

    // Custom dropdown rather than <select>: the closed control can be themed,
    // but an open native <select> renders as a macOS popup menu that no CSS
    // reaches, so it broke out of the shell's look. Exposes .value + "change"
    // so the rest of this panel treats it like the select it replaced.
    var macroSelect = (function() {
        var root = document.createElement("div");
        root.className = "macro-select";
        root.tabIndex = 0;

        var label = document.createElement("span");
        label.className = "macro-select-label";
        root.appendChild(label);

        var arrow = document.createElement("span");
        arrow.className = "macro-select-arrow";
        // chevdown from the shell's ICONS rather than a "▾" glyph: the
        // custom dropdown exists so this control can be themed, and a
        // typographic arrow is the one part of it that never was.
        arrow.innerHTML = (typeof window.icon === "function" && window.ICONS
            && window.ICONS.chevdown)
            ? window.icon("chevdown")
            : "";
        root.appendChild(arrow);

        var menu = document.createElement("div");
        menu.className = "macro-select-menu";
        root.appendChild(menu);

        var _opts = [];
        var _value = "";

        function labelFor(v) {
            for (var i = 0; i < _opts.length; i++) {
                if (_opts[i].value === v) return _opts[i].label;
            }
            return _opts.length ? _opts[0].label : "";
        }
        function close() { root.classList.remove("open"); }
        function render() {
            label.textContent = labelFor(_value);
            menu.innerHTML = "";
            _opts.forEach(function(o) {
                var item = document.createElement("div");
                item.className = "macro-select-item" + (o.value === _value ? " active" : "");
                item.textContent = o.label;
                item.addEventListener("mouseenter", function() {
                    if (window.playSlot) playSlot("hover");
                });
                item.addEventListener("click", function(e) {
                    e.stopPropagation();
                    if (window.playSlot) playSlot("interact");
                    close();
                    if (o.value === _value) return;
                    _value = o.value;
                    render();
                    root.dispatchEvent(new Event("change"));
                });
                menu.appendChild(item);
            });
        }

        root.setOptions = function(list) { _opts = list; render(); };
        Object.defineProperty(root, "value", {
            get: function() { return _value; },
            set: function(v) { _value = v == null ? "" : String(v); render(); },
        });

        root.addEventListener("mouseenter", function() {
            if (window.playSlot) playSlot("hover");
        });
        root.addEventListener("click", function(e) {
            e.stopPropagation();
            if (!root.classList.contains("open") && window.playSlot) playSlot("interact");
            root.classList.toggle("open");
        });
        root.addEventListener("keydown", function(e) {
            if (e.key === "Escape") close();
        });
        document.addEventListener("click", close);

        // Seed the placeholder so the control reads correctly before the macro
        // list arrives from Lua.
        root.setOptions([{ value: "", label: "Select" }]);
        return root;
    })();
    toolbar.appendChild(macroSelect);

    var nameInput = document.createElement("input");
    nameInput.className = "macro-name-input";
    nameInput.type = "text";
    nameInput.placeholder = "Macro name";
    nameInput.setAttribute("spellcheck", "false");
    nameInput.setAttribute("autocomplete", "off");
    nameInput.setAttribute("autocorrect", "off");
    nameInput.setAttribute("autocapitalize", "off");
    toolbar.appendChild(nameInput);

    // Bind field — the compiler already emits a ms.bind.define default block
    // from macroDef.bind; without this control the builder never supplied one,
    // so builder-authored macros were never bindable.
    var bindLabel = document.createElement("span");
    bindLabel.style.cssText = "font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.6px;color:var(--text3);margin-left:8px;margin-right:4px";
    bindLabel.textContent = "Bind";
    toolbar.appendChild(bindLabel);

    var bindBtn = document.createElement("button");
    bindBtn.className = "bind-pill unset";
    bindBtn.textContent = "unset";
    bindBtn.title = "Click to capture a bind for this macro";
    toolbar.appendChild(bindBtn);

    var spacer = document.createElement("div");
    spacer.className = "macro-toolbar-spacer";
    toolbar.appendChild(spacer);

    // New macro button
    var newBtn = document.createElement("button");
    newBtn.className = "macro-toolbar-btn";
    newBtn.textContent = "New";
    toolbar.appendChild(newBtn);

    // Save button
    var saveBtn = document.createElement("button");
    saveBtn.className = "macro-toolbar-btn primary";
    saveBtn.textContent = "Save";
    toolbar.appendChild(saveBtn);

    // Secondary actions live under an overflow "⋯" menu so the toolbar never
    // clips them when the shell is shrunk to its smallest width (Test/Record/
    // Delete/Edit File used to run off the edge). New/Save/Bind stay inline.
    var overflowWrap = document.createElement("div");
    overflowWrap.className = "macro-overflow";
    var overflowBtn = document.createElement("button");
    overflowBtn.className = "macro-toolbar-btn macro-overflow-btn";
    overflowBtn.textContent = "⋯"; // ⋯
    overflowBtn.title = "More actions";
    var overflowMenu = document.createElement("div");
    overflowMenu.className = "macro-overflow-menu";
    overflowWrap.appendChild(overflowBtn);
    overflowWrap.appendChild(overflowMenu);

    function closeOverflow() { overflowWrap.classList.remove("open"); }
    overflowBtn.addEventListener("mouseenter", function() {
        if (window.playSlot) playSlot("hover");
    });
    overflowBtn.addEventListener("click", function(e) {
        e.stopPropagation();
        if (!overflowWrap.classList.contains("open") && window.playSlot) playSlot("interact");
        overflowWrap.classList.toggle("open");
    });
    // A menu item's own handler still runs; close the menu after any click in it.
    overflowMenu.addEventListener("click", function() { closeOverflow(); });
    document.addEventListener("click", closeOverflow);

    // Every overflow item is icon + label, in that order, so the menu reads as
    // one consistent list rather than the old mix of symbol+label / label-only
    // / icon-only entries. `menuLabel()` renders one via the shell's icon().
    function menuLabel(name, text) {
        return (window.icon ? window.icon(name) : "") + '<span>' + text + '</span>';
    }

    // Test Run button
    var testBtn = document.createElement("button");
    testBtn.className = "macro-toolbar-btn";
    testBtn.innerHTML = menuLabel("play", "Test");
    testBtn.title = "Test Run current macro";
    overflowMenu.appendChild(testBtn);

    // Record button
    var recordBtn = document.createElement("button");
    recordBtn.className = "macro-toolbar-btn";
    recordBtn.innerHTML = menuLabel("record", "Record");
    recordBtn.title = "Record user actions into modules";
    overflowMenu.appendChild(recordBtn);

    // Delete button
    var delMacroBtn = document.createElement("button");
    delMacroBtn.className = "macro-toolbar-btn danger";
    delMacroBtn.innerHTML = menuLabel("trash", "Delete");
    delMacroBtn.title = "Delete macro";
    overflowMenu.appendChild(delMacroBtn);

    // Edit raw macro file — the escape hatch for anything the visual builder
    // doesn't cover. Lives here, with the builder that owns ms_macros.lua,
    // rather than in the Settings > Developer section it used to share.
    var editFileBtn = document.createElement("button");
    editFileBtn.className = "macro-toolbar-btn";
    editFileBtn.innerHTML = menuLabel("edit", "Edit File");
    editFileBtn.title = "Open ms_macros.lua in your editor";
    overflowMenu.appendChild(editFileBtn);

    toolbar.appendChild(overflowWrap);

    // ── Main area ──
    var mainArea = document.createElement("div");
    mainArea.className = "macros-main";

    // Tool canvas area
    var toolArea = document.createElement("div");
    toolArea.className = "macros-tool-area";
    // Canvas container (ToolCanvas will be mounted here)
    var canvasContainer = document.createElement("div");
    canvasContainer.style.cssText = "flex:1;overflow:hidden;position:relative";
    toolArea.appendChild(canvasContainer);

    mainArea.appendChild(toolArea);

    // Floating add-tool button
    var addToolBtn = document.createElement("button");
    addToolBtn.className = "macros-add-tool-btn";
    addToolBtn.innerHTML = (_svgCache["add"] || "+") + " Add Module";
    toolArea.appendChild(addToolBtn);

    // Test run / recording toast
    var testToast = document.createElement("div");
    testToast.className = "macro-test-toast";
    toolArea.appendChild(testToast);

    // Fn-picker overlay (the existing picker, restructured)
    var overlay = document.createElement("div");
    overlay.className = "fn-picker-overlay";

    var overlayHeader = document.createElement("div");
    overlayHeader.className = "fn-picker-overlay-header";
    var overlayTitle = document.createElement("span");
    overlayTitle.className = "fn-picker-overlay-title";
    overlayTitle.textContent = "Add Module";
    overlayHeader.appendChild(overlayTitle);
    var overlayClose = document.createElement("div");
    overlayClose.className = "fn-picker-overlay-close";
    overlayClose.innerHTML = (_svgCache["close"] || '<svg class="icon" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><g id="Edit / Close_Circle"><path id="Vector" d="M9 9L11.9999 11.9999M11.9999 11.9999L14.9999 14.9999M11.9999 11.9999L9 14.9999M11.9999 11.9999L14.9999 9M12 21C7.02944 21 3 16.9706 3 12C3 7.02944 7.02944 3 12 3C16.9706 3 21 7.02944 21 12C21 16.9706 16.9706 21 12 21Z" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></g></svg>');
    overlayClose.addEventListener("click", function() { closeFnOverlay(); });
    overlayHeader.appendChild(overlayClose);
    overlay.appendChild(overlayHeader);

    // Move existing picker into overlay
    if (existingPicker) {
        existingPicker.style.width = "100%";
        existingPicker.style.height = "100%";
        existingPicker.style.flex = "1";
        overlay.appendChild(existingPicker);
    }
    mainArea.appendChild(overlay);

    // ── Tab strip: Builder | Binds ───────────────────────────────────
    // Rebinding lives here rather than in Settings: the macros panel owns
    // every macro, whether it was authored in the builder or declared in
    // ms_macros.lua.
    var mtabs = document.createElement("div");
    mtabs.className = "mtabs";

    // Binds is the landing tab: it is the panel people open the shell to
    // read, where Builder is a thing you go to deliberately.
    var builderSection = document.createElement("div");
    builderSection.className = "mtab-section";
    builderSection.setAttribute("data-msec", "builder");

    var bindsSection = document.createElement("div");
    bindsSection.className = "mtab-section active";
    bindsSection.setAttribute("data-msec", "binds");

    var bindsScroll = document.createElement("div");
    bindsScroll.className = "binds-scroll";
    bindsSection.appendChild(bindsScroll);

    ["builder", "binds"].forEach(function(id) {
        var b = document.createElement("button");
        b.className = "mtab" + (id === "binds" ? " active" : "");
        b.setAttribute("data-mtab", id);
        b.textContent = id === "builder" ? "Builder" : "Binds";
        b.addEventListener("mouseenter", function() {
            if (window.playSlot) playSlot("hover");
        });
        b.addEventListener("click", function() {
            if (_mtabs) _mtabs.switch(id);
        });
        mtabs.appendChild(b);
    });

    // Assemble layout
    builderSection.appendChild(toolbar);
    builderSection.appendChild(mainArea);
    layout.appendChild(mtabs);
    layout.appendChild(builderSection);
    layout.appendChild(bindsSection);
    slot.appendChild(layout);

    // Shared tab model — same switch/sound behaviour as every other panel.
    _mtabs = window.createTabs && window.createTabs({
        root: layout,
        tabSelector: ".mtab",
        sectionSelector: ".mtab-section",
        tabKey: function(el) { return el.getAttribute("data-mtab"); },
        sectionKey: function(el) { return el.getAttribute("data-msec"); },
        onSame: function() { if (window.playSlot) playSlot("back"); },
        onSwitch: function(tab) {
            if (window.playSlot) playSlot("interact");
            if (tab === "binds") refreshBindList();
        },
    });

    // ── Tool Canvas instance ──
    _canvas = new ToolCanvas(canvasContainer, {
        onChange: function(steps) {
            _macroDirty = true;
            updateSaveBtnState();
        },
        onSelect: function(sid, step) {
            if (_toolEditor) _toolEditor.open(sid);
        }
    });

    // ── Tool keyboard shortcuts (copy/cut/paste/delete) ─────────────
    toolArea.addEventListener("keydown", function(e) {
        var mod = e.metaKey || e.ctrlKey;
        if (mod && e.key === "c") {
            e.preventDefault();
            _canvas.copySelected();
        } else if (mod && e.key === "x") {
            e.preventDefault();
            _canvas.cutSelected();
            _macroDirty = true;
            updateSaveBtnState();
        } else if (mod && e.key === "v") {
            e.preventDefault();
            _canvas.pasteAfter();
            _macroDirty = true;
            updateSaveBtnState();
        } else if ((e.key === "Delete" || e.key === "Backspace") && _canvas.getSelectedId()) {
            e.preventDefault();
            _canvas.removeTool(_canvas.getSelectedId());
            _macroDirty = true;
            updateSaveBtnState();
        }
    });

    // Inline tool parameter editor
    var _toolEditor = null;
    if (window.ToolEditor) {
        _toolEditor = new ToolEditor({ canvas: _canvas });
    } else {
        console.warn("[macros] ToolEditor not loaded — inline editing disabled");
    }

    /* ── Preload add icon ────────────────────────────────────────── */
    _fetchSVG("add").then(function(svg) {
        if (svg) addToolBtn.innerHTML = svg + " Add Module";
    });
    _fetchSVG("close").then(function(svg) {
        if (svg) overlayClose.innerHTML = svg;
    });

    /* ── Fn-picker overlay toggle ────────────────────────────────── */
    function openFnOverlay() {
        overlay.classList.add("open");
        // Pull the current tool list every time — a tool may have been added
        // or removed from the Settings panel since the overlay last opened.
        refreshToolList();
    }
    function closeFnOverlay() {
        overlay.classList.remove("open");
    }
    addToolBtn.addEventListener("click", function() {
        openFnOverlay();
    });

    function refreshToolList() {
        if (window.shellPost) shellPost("macros", "listTools", {});
    }

    /* ── Macro select / management ───────────────────────────────── */
    function refreshMacroList() {
        // Ask Lua for the list of macros
        if (window.shellPost) {
            shellPost("macros", "listMacros", {});
        }
    }

    /* ── Binds tab ───────────────────────────────────────────────────
       Lists every registered macro (builder-authored and ms_macros.lua
       alike) with its effective bind, its derived sub-binds, and controls
       to rebind, reset, or disable it. The actions are the same ones the
       settings panel used — they are routed to ms.ui._actions by the
       ui:macros:* bus subscription.                                     */
    var _bindList = [];

    function refreshBindList() {
        if (window.shellPost) shellPost("macros", "listBinds", {});
    }

    function bindPill(text, onClick, title) {
        var b = document.createElement("button");
        b.className = "bind-pill" + (text ? "" : " unset");
        b.textContent = text || "unset";
        if (title) b.title = title;
        b.addEventListener("mouseenter", function() {
            if (window.playSlot) playSlot("hover");
        });
        b.addEventListener("click", function(e) {
            e.stopPropagation();
            if (window.playSlot) playSlot("interact");
            onClick();
        });
        return b;
    }

    // Takes an ICONS name, not a glyph. It used to take the character itself,
    // which is how a lone "↺" ended up standing in for the refresh icon the
    // shell already ships — a text arrow next to real SVGs reads as a
    // different weight and does not follow --accent on hover.
    function iconBtn(iconName, title, onClick) {
        var b = document.createElement("button");
        b.className = "bind-act";
        // Falls back to the name rather than rendering nothing, so a typo in
        // an icon name is visible instead of an empty button.
        b.innerHTML = (typeof window.icon === "function" && window.ICONS
            && window.ICONS[iconName])
            ? window.icon(iconName)
            : "";
        if (!b.innerHTML) b.textContent = iconName;
        b.title = title;
        b.addEventListener("mouseenter", function() {
            if (window.playSlot) playSlot("hover");
        });
        b.addEventListener("click", function(e) {
            e.stopPropagation();
            if (window.playSlot) playSlot("interact");
            onClick();
        });
        return b;
    }

    function bindRow(m, isSub) {
        var r = document.createElement("div");
        r.className = "bind-row" + (isSub ? " bind-row-sub" : "");
        // Row-level hover, matching the log-panel list rows. mouseenter does not
        // bubble, so moving onto a pill/toggle inside the row fires only that
        // child's hover — no double-trigger.
        r.addEventListener("mouseenter", function() {
            if (window.playSlot) playSlot("hover");
        });

        var lbl = document.createElement("div");
        lbl.className = "bind-label";
        lbl.textContent = m.label || m.id;
        r.appendChild(lbl);

        var acts = document.createElement("div");
        acts.className = "bind-acts";

        // A sub-bind's trigger is inherited from its parent — only its modifier
        // is its own. Rebinding it as a whole key would sever it from the parent
        // and turn it into a standalone bind, so its pill drives the modifier
        // flow (startModRebind), and its reset clears the modifier rather than
        // resetting a bind that doesn't independently exist.
        if (isSub) {
            // A sub-bind inherits its parent's trigger and owns only its
            // modifier. Two rebind modes: "Mod" changes just that modifier and
            // stays attached to the parent; "Full" captures a whole new trigger
            // and branches this bind off into its own adjacent top-level bind.
            // The mode toggle drives which flow the pill starts.
            var mode = { full: false };
            var modeBtn = document.createElement("button");
            modeBtn.className = "bind-act bind-mode-toggle";
            function syncMode() {
                modeBtn.textContent = mode.full ? "Full" : "Mod";
                modeBtn.title = mode.full
                    ? "Full rebind — branches this off into its own bind"
                    : "Modifier only — stays attached to the parent";
            }
            syncMode();
            modeBtn.addEventListener("mouseenter", function() {
                if (window.playSlot) playSlot("hover");
            });
            modeBtn.addEventListener("click", function(e) {
                e.stopPropagation();
                if (window.playSlot) playSlot("interact");
                mode.full = !mode.full;
                syncMode();
            });

            acts.appendChild(bindPill(m.bind, function() {
                if (mode.full) {
                    shellPost("macros", "startRebind", {
                        action:     "startRebind",
                        id:         m.id,
                        systemBind: false,
                    });
                } else {
                    shellPost("macros", "startModRebind", {
                        action: "startModRebind",
                        id:     m.id,
                    });
                }
            }, "Click to rebind — Mod/Full toggle selects the mode"));

            acts.appendChild(modeBtn);

            // Clearing writes the derived link back (re-nesting a severed
            // sub) and drops the modifier.
            acts.appendChild(iconBtn("refresh", "Clear modifier / re-attach to parent", function() {
                shellPost("macros", "clearModifier", {
                    action: "clearModifier",
                    id:     m.id,
                });
            }));
        } else {
            acts.appendChild(bindPill(m.bind, function() {
                shellPost("macros", "startRebind", {
                    action:     "startRebind",
                    id:         m.id,
                    systemBind: m.systemBind || false,
                });
            }, "Click to rebind"));

            acts.appendChild(iconBtn("refresh", "Reset to default bind", function() {
                shellPost("macros", "resetBind", {
                    action:     "resetBind",
                    id:         m.id,
                    systemBind: m.systemBind || false,
                });
            }));
        }

        // System binds are always live; only real macros can be disabled.
        if (!isSub && m.group !== "system" && !m.systemBind) {
            // Same markup as the settings panel's toggle() so it picks up the
            // shared .toggle track/thumb styling rather than a native checkbox.
            // A macro with no bind has no trigger, so it cannot be enabled. The
            // host refuses setMacroEnabled(true) for it too; locking the toggle
            // here just makes that unreachable state legible instead of a click
            // that silently snaps back.
            var bindable = (m.bindable !== false);
            var lbl = document.createElement("label");
            lbl.className = "toggle bind-toggle" + (bindable ? "" : " disabled");
            if (!bindable) lbl.title = "Set a bind before enabling this macro";
            lbl.addEventListener("mouseenter", function() {
                if (window.playSlot) playSlot("hover");
            });
            var t = document.createElement("input");
            t.type = "checkbox";
            t.checked = !!m.enabled;
            t.disabled = !bindable;
            t.addEventListener("change", function() {
                if (!bindable) { t.checked = false; return; }
                shellPost("macros", "setMacroEnabled", {
                    action: "setMacroEnabled",
                    id:     m.id,
                    value:  t.checked,
                });
                // Matches the settings panel's toggle(): the shell sounds the
                // toggle, the host handler does not.
                if (window.playSlot) playSlot(t.checked ? "toggleOn" : "toggleOff");
            });
            var track = document.createElement("div");
            track.className = "toggle-track";
            var thumb = document.createElement("div");
            thumb.className = "toggle-thumb";
            lbl.appendChild(t); lbl.appendChild(track); lbl.appendChild(thumb);
            acts.appendChild(lbl);
        }

        r.appendChild(acts);
        return r;
    }

    function renderBindList() {
        bindsScroll.innerHTML = "";

        if (!_bindList.length) {
            var empty = document.createElement("div");
            empty.className = "binds-empty";
            empty.textContent = "No macros registered.";
            bindsScroll.appendChild(empty);
            return;
        }

        // Group in registration order, same grouping the macro list uses.
        var order = [];
        var groups = {};
        _bindList.forEach(function(m) {
            var g = m.group || "ungrouped";
            if (!groups[g]) { groups[g] = []; order.push(g); }
            groups[g].push(m);
        });

        // A group is a settings section: a sticky heading naming it, and its
        // binds in a card. It used to be a bare uppercase label over a flat
        // run of rows, which left nothing to tell you where one group ended.
        order.forEach(function(g) {
            var rows = [];
            groups[g].forEach(function(m) {
                rows.push(bindRow(m, false));
                (m.subs || []).forEach(function(sub) {
                    rows.push(bindRow(sub, true));
                });
            });
            bindsScroll.appendChild(bindSection(
                g.charAt(0).toUpperCase() + g.slice(1),
                g === "system" ? "Always live — these cannot be disabled" : null,
                rows,
            ));
        });
    }

    // The settings panel publishes section() through window.msUI, but it
    // takes a build function and this list already has its rows. Same markup,
    // built from a row array instead.
    function bindSection(title, desc, rows) {
        var wrap = document.createElement("div");
        wrap.className = "section";
        var head = document.createElement("div");
        head.className = "section-head";
        var t = document.createElement("span");
        t.className = "section-title";
        t.textContent = title;
        head.appendChild(t);
        if (desc) {
            var d = document.createElement("span");
            d.className = "section-desc";
            d.textContent = desc;
            head.appendChild(d);
        }
        var body = document.createElement("div");
        body.className = "section-body";
        rows.forEach(function(r) { body.appendChild(r); });
        wrap.appendChild(head);
        wrap.appendChild(body);
        return wrap;
    }

    function setBindList(list) {
        _bindList = Array.isArray(list) ? list : [];
        renderBindList();
        updateBindBtn();
    }

    function setMacroList(ids) {
        var opts = [{ value: "", label: "Select" }];
        for (var i = 0; i < ids.length; i++) {
            opts.push({ value: ids[i], label: ids[i] });
        }
        macroSelect.setOptions(opts);

        if (_currentMacroId) {
            macroSelect.value = _currentMacroId;
        }
    }

    function loadMacro(macroId) {
        if (!macroId) {
            _currentMacroId = null;
            _currentMacroDef = null;
            _canvas.load([]);
            nameInput.value = "";
            _macroDirty = false;
            updateSaveBtnState();
            updateBindBtn();
            return;
        }
        // Ask Lua for the macro definition
        if (window.shellPost) {
            shellPost("macros", "getMacro", { id: macroId });
        }
    }

    function setMacroDef(def) {
        _currentMacroId = def.id;
        _currentMacroDef = def;
        nameInput.value = def.name || def.id || "";
        _canvas.load(def.steps || []);
        _macroDirty = false;
        updateSaveBtnState();
        macroSelect.value = def.id;
        updateBindBtn();
    }

    // Show the macro's effective bind, preferring the live value from the
    // binds tab (which reflects user overrides) over the compiled default.
    function updateBindBtn() {
        var text = "";
        for (var i = 0; i < _bindList.length; i++) {
            if (_bindList[i].id === _currentMacroId) { text = _bindList[i].bind || ""; break; }
        }
        if (!text && _currentMacroDef && _currentMacroDef.bind) {
            var b = _currentMacroDef.bind;
            if (b.type === "mouse") text = "Mouse " + b.button;
            else if (b.key) text = (b.mods || []).concat([b.key]).join("+");
        }
        bindBtn.textContent = text || "unset";
        bindBtn.className = "bind-pill" + (text ? "" : " unset");
    }

    bindBtn.addEventListener("mouseenter", function() {
        if (window.playSlot) playSlot("hover");
    });
    bindBtn.addEventListener("click", function() {
        if (window.playSlot) playSlot("interact");
        // Capture targets a registered bind id, which only exists once the
        // macro has been compiled — so it must be saved first.
        if (!_currentMacroId || _macroDirty) {
            showTestToast("Save the macro before binding it", "error");
            return;
        }
        shellPost("macros", "startRebind", {
            action: "startRebind",
            id:     _currentMacroId,
        });
    });

    function saveMacro() {
        if (!_currentMacroId) {
            // Create new
            var name = nameInput.value.trim();
            if (!name) {
                nameInput.focus();
                return;
            }
            _currentMacroId = name.replace(/[^a-zA-Z0-9_]/g, "_");
        }

        var name = nameInput.value.trim() || _currentMacroId;
        var def = {
            id: _currentMacroId,
            name: name,
            author: "User",
            steps: _canvas.serialize()
        };
        // Carry the compiled default bind through a save — the compiler reads
        // macroDef.bind, so dropping it here would silently unbind the macro.
        if (_currentMacroDef && _currentMacroDef.bind) {
            def.bind = _currentMacroDef.bind;
        }
        if (_currentMacroDef && _currentMacroDef.cooldown) {
            def.cooldown = _currentMacroDef.cooldown;
        }
        _currentMacroDef = def;

        if (window.shellPost) {
            shellPost("macros", "saveMacro", { id: _currentMacroId, def: def });
        }
        _macroDirty = false;
        updateSaveBtnState();
    }

    function deleteMacro() {
        if (!_currentMacroId) return;
        if (window.shellPost) {
            shellPost("macros", "deleteMacro", { id: _currentMacroId });
        }
        _currentMacroId = null;
        _currentMacroDef = null;
        _canvas.load([]);
        nameInput.value = "";
        _macroDirty = false;
        updateSaveBtnState();
        refreshMacroList();
    }

    function updateSaveBtnState() {
        saveBtn.style.opacity = _macroDirty ? "1" : "0.5";
    }

    /* ── Wire toolbar buttons ────────────────────────────────────── */
    newBtn.addEventListener("click", function() {
        _currentMacroId = null;
        _currentMacroDef = null;
        _canvas.load([]);
        nameInput.value = "";
        nameInput.focus();
        _macroDirty = false;
        updateSaveBtnState();
        macroSelect.value = "";
        updateBindBtn();
    });

    saveBtn.addEventListener("click", function() { saveMacro(); });

    editFileBtn.addEventListener("click", function() {
        if (window.playSlot) playSlot("interact");
        if (window.shellPost) shellPost("macros", "editMacros", {});
    });

    /* ── Test Run ────────────────────────────────────────────────── */
    var _testRunning = false;
    var _testToastTimer = null;

    function showTestToast(msg, type) {
        testToast.textContent = msg;
        testToast.className = "macro-test-toast show"
            + (type === "error" ? " error-toast" : "")
            + (type === "success" ? " success-toast" : "");
        if (_testToastTimer) clearTimeout(_testToastTimer);
        _testToastTimer = setTimeout(function() {
            testToast.className = "macro-test-toast";
            _testToastTimer = null;
        }, type === "error" ? 5000 : 2500);
    }

    function _resetTestBtn() {
        testBtn.className = "macro-toolbar-btn";
        testBtn.innerHTML = menuLabel("play", "Test");
        testBtn.disabled = false;
        _testRunning = false;
    }

    testBtn.addEventListener("click", function() {
        if (_testRunning) return;
        var steps = _canvas.serialize();
        if (!steps || steps.length === 0) {
            showTestToast("No steps to run", "error");
            return;
        }

        // Build macro def for test run
        var macroId = _currentMacroId || ("_test_" + Date.now().toString(36));
        var macroDef = {
            id: macroId,
            name: nameInput.value.trim() || macroId,
            steps: steps,
        };

        // Set running state
        _testRunning = true;
        testBtn.className = "macro-toolbar-btn running";
        testBtn.innerHTML = menuLabel("timer", "Running\u2026");
        testBtn.disabled = true;

        // Send to Lua
        if (window.shellPost) {
            shellPost("macros", "testRun", macroDef);
        }

        // Safety timeout — reset after 30s if no response
        setTimeout(function() {
            if (_testRunning) {
                _resetTestBtn();
                showTestToast("Test run timed out", "error");
            }
        }, 30000);
    });

    /* ── Record Mode ─────────────────────────────────────────────── */
    var _isRecording = false;

    function _setRecordingState(on) {
        _isRecording = on;
        if (on) {
            recordBtn.className = "macro-toolbar-btn recording";
            recordBtn.innerHTML = menuLabel("stop", "Stop");
            recordBtn.title = "Stop recording";
            showTestToast("\u23fa Recording — perform actions, then click Stop\u2026");
        } else {
            recordBtn.className = "macro-toolbar-btn";
            recordBtn.innerHTML = menuLabel("record", "Record");
            recordBtn.title = "Record user actions into tools";
        }
    }

    recordBtn.addEventListener("click", function() {
        if (!_isRecording) {
            // Start recording
            if (window.shellPost) {
                shellPost("macros", "startRecording", { waitThreshold: 50 });
            }
            _setRecordingState(true);
        } else {
            // Stop recording
            if (window.shellPost) {
                shellPost("macros", "stopRecording", {});
            }
            _setRecordingState(false);
            showTestToast("Recording stopped", "success");
        }
    });

    delMacroBtn.addEventListener("click", function() {
        if (_currentMacroId) deleteMacro();
    });

    macroSelect.addEventListener("change", function() {
        var id = macroSelect.value;
        loadMacro(id);
    });

    nameInput.addEventListener("keydown", function(e) { e.stopPropagation(); });
    nameInput.addEventListener("input", function() {
        _macroDirty = true;
        updateSaveBtnState();
    });

    /* ── Panel handler (consolidated Lua → JS dispatch) ──────────── */
    window.registerPanel("macros", function(action, body) {
        // Function picker messages
        if (window.fnPicker && window.fnPicker.handler) {
            window.fnPicker.handler(action, body);
        }
        // Tool-canvas messages
        if (action === "addTool" && body) {
            _canvas.addTool(body);
            _macroDirty = true;
            updateSaveBtnState();
            return;
        }
        if (action === "macroList" && Array.isArray(body)) {
            setMacroList(body);
            return;
        }
        if (action === "macroDef" && body) {
            setMacroDef(body);
            return;
        }
        if (action === "macroSaved") {
            _macroDirty = false;
            updateSaveBtnState();
            refreshMacroList();
            // A saved macro may have gained or changed its bind.
            refreshBindList();
            return;
        }
        if (action === "bindList" && Array.isArray(body)) {
            setBindList(body);
            return;
        }
        if (action === "setToolList" && Array.isArray(body)) {
            if (window.fnPicker && window.fnPicker.setToolList) {
                window.fnPicker.setToolList(body);
            }
            return;
        }
        if (action === "testRunResult" && body) {
            _resetTestBtn();
            if (body.ok) {
                testBtn.className = "macro-toolbar-btn success";
                showTestToast("\u2713 Macro ran successfully", "success");
                setTimeout(function() {
                    if (!_testRunning) testBtn.className = "macro-toolbar-btn";
                }, 2500);
            } else {
                testBtn.className = "macro-toolbar-btn error";
                showTestToast("\u2717 " + (body.err || "Unknown error"), "error");
                setTimeout(function() {
                    if (!_testRunning) testBtn.className = "macro-toolbar-btn";
                }, 5000);
            }
            return;
        }
        if (action === "recordStep" && body) {
            _canvas.addTool({ action: body.action, params: body.params });
            _macroDirty = true;
            updateSaveBtnState();
            return;
        }
    });

    /* ── External API ────────────────────────────────────────────── */
    window.macroLab = {
        canvas: _canvas,
        editor: _toolEditor,
        loadMacro: loadMacro,
        saveMacro: saveMacro,
        refreshList: refreshMacroList,
        setMacroList: setMacroList,
        setMacroDef: setMacroDef,
        setBindList: setBindList,
        refreshBinds: refreshBindList,
        addTool: function(def) { _canvas.addTool(def); closeFnOverlay(); },
        // Tools (authored settings) — list is pushed from Lua; create/delete
        // round-trip through the host, which re-pushes the updated list.
        setToolList: function(list) {
            if (window.fnPicker && window.fnPicker.setToolList) {
                window.fnPicker.setToolList(list);
            }
        },
        createTool: function(def) {
            if (!window.shellPost) return;
            shellPost("macros", "addUserSetting", { action: "addUserSetting", def: def });
            // The host has no create-ack, so re-pull the list shortly after so
            // the new tool appears in the picker.
            setTimeout(refreshToolList, 250);
        },
        deleteTool: function(key) {
            if (!window.shellPost) return;
            shellPost("macros", "removeUserSetting", { action: "removeUserSetting", key: key });
            setTimeout(refreshToolList, 250);
        },
        // Test Run & Record Mode
        testRun: function() { testBtn.click(); },
        startRecording: function() { if (!_isRecording) recordBtn.click(); },
        stopRecording: function() { if (_isRecording) recordBtn.click(); },
        isRecording: function() { return _isRecording; },
    };

    /* ── Close panel (called by header pop-out button) ────────── */
    window.closePanel = function() {
        if (window.shellPost) shellPost("macros", "close", {});
    };

    /* ── Initial state ───────────────────────────────────────────── */
    updateSaveBtnState();
    refreshMacroList();
    refreshBindList();

    /* ── Header drag ──────────────────────────────────────────── */
    (function() {
        let _drag = null;
        const panel = document.querySelector(".panel-macros");
        if (!panel) return;
        const header = panel.querySelector("#header");
        if (!header) return;
        header.style.cursor = "-webkit-grab";
        header.addEventListener("mousedown", (e) => {
            if (e.button !== 0) return;
            if (e.target.closest(".header-btns")) return;
            _drag = { ox: e.screenX, oy: e.screenY };
            const onMove = (ev) => {
                if (!_drag) return;
                if (window.shellPost) {
                    shellPost("macros", "move", {
                        dx: ev.screenX - _drag.ox,
                        dy: ev.screenY - _drag.oy,
                    });
                }
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

    })();


    })();
