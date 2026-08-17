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

            /* ── window ─────────────────────────────────────────── */
            {
                id: "ms.window",
                name: "ms.window",
                sig: "ms.window(operation, x, y, w, h)",
                desc: "Move or resize the focused window. Move uses (x,y); Resize uses (x=width, y=height); Frame uses all four.",
                category: "window",
                params: [
                    { name: "operation", type: "string", label: "Operation (Move/Resize/Frame)", required: true },
                    { name: "x", type: "number", label: "X / Width",  required: true },
                    { name: "y", type: "number", label: "Y / Height", required: true },
                    { name: "w", type: "number", label: "Width (Frame)",  required: false },
                    { name: "h", type: "number", label: "Height (Frame)", required: false }
                ]
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
        var _view        = "module"; // "module" | "tool"

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

            // Draggable straight onto the canvas as a new module (with default
            // params), as an alternative to selecting it and clicking Add Module.
            // The canvas reads this MIME type; see the drop wiring on the canvas.
            row.setAttribute("draggable", "true");
            row.addEventListener("dragstart", function(e) {
                e.dataTransfer.effectAllowed = "copy";
                e.dataTransfer.setData("application/x-ms-fn", fn.id);
                // A plain-text fallback keeps the drag valid where the custom
                // type is filtered; the canvas prefers the typed payload.
                e.dataTransfer.setData("text/plain", fn.name);
            });

            row.addEventListener("click", function() {
                if (window.playSlot) playSlot("interact");
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
        // Build one draggable tool row (a shared-setting reference).
        function makeToolRow(t) {
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

            // Draggable onto the canvas as a shared-setting reference block,
            // mirroring the module rows. The canvas drop wiring reads this MIME
            // type and inserts a { action:"setting" } step.
            row.setAttribute("draggable", "true");
            row.addEventListener("dragstart", function(e) {
                e.dataTransfer.effectAllowed = "copy";
                e.dataTransfer.setData("application/x-ms-tool", t.key);
                e.dataTransfer.setData("text/plain", t.label || t.key);
            });
            row.addEventListener("mouseenter", function() {
                if (window.playSlot) playSlot("hover");
            });
            row.addEventListener("click", function() {
                if (window.playSlot) playSlot("interact");
                selectTool(t.key);
            });
            return row;
        }

        // The Tools live above the module categories (they are settings, not
        // code the compiler emits). Each tool's `section` becomes its own
        // collapsible heading here — so a plugin that tags its settings with a
        // section (e.g. the Roblox plugin's section="roblox") gets its own named
        // group alongside the module categories, exactly like LUA / FLOW /
        // UTILITIES. Tools with no section fall under a default "tools" group.
        function renderToolsGroup(filter, searching) {
            var q = (filter || "").toLowerCase();
            var matches = _tools.filter(function(t) {
                if (!q) return true;
                return (t.label || "").toLowerCase().indexOf(q) !== -1
                    || (t.key || "").toLowerCase().indexOf(q) !== -1
                    || (t.section || "").toLowerCase().indexOf(q) !== -1
                    || "tool".indexOf(q) !== -1;
            });
            var searchingTools = q && "tool".indexOf(q) === -1;

            // With no tools at all, keep the single default header + a hint so
            // tools stay discoverable; a no-match search just hides the group.
            if (matches.length === 0) {
                if (searchingTools) return;
                renderToolSection("tools", [], filter, searching, true);
                return;
            }

            // Group by section, preserving first-seen order. The default "tools"
            // group, when present, is emitted first so ungrouped tools lead.
            var order = [];
            var groups = {};
            matches.forEach(function(t) {
                var s = (t.section && String(t.section)) || "tools";
                if (!groups[s]) { groups[s] = []; order.push(s); }
                groups[s].push(t);
            });
            if (groups["tools"]) {
                order = ["tools"].concat(order.filter(function(s) { return s !== "tools"; }));
            }
            order.forEach(function(s) {
                renderToolSection(s, groups[s], filter, searching, false);
            });
        }

        // Render one Tools sub-section: a category-style header keyed by section
        // name, with its own independent collapse state, then its tool rows.
        function renderToolSection(section, rows, filter, searching, emptyHint) {
            var key = "__tools:" + section;
            var collapsed = searching ? false : (_catCollapsed[key] !== false);

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
            name.textContent = section;
            head.appendChild(name);

            var count = document.createElement("span");
            count.className = "fn-cat-count";
            count.textContent = String(rows.length);
            head.appendChild(count);

            head.addEventListener("mouseenter", function() {
                if (window.playSlot) playSlot("hover");
            });
            if (!searching) {
                head.addEventListener("click", function() {
                    if (window.playSlot) playSlot("interact");
                    _catCollapsed[key] = !(_catCollapsed[key] !== false);
                    renderList(filter);
                });
            }
            entriesDiv.appendChild(head);

            if (collapsed) return;

            rows.forEach(function(t) { entriesDiv.appendChild(makeToolRow(t)); });

            // Tools are authored in the dedicated Tools panel (Setting Builder),
            // not here. When none exist yet, a hint points at where to make one.
            if (emptyHint && rows.length === 0) {
                var hint = document.createElement("div");
                hint.className = "fn-entry fn-tool-hint";
                hint.innerHTML = '<span class="fn-entry-sig">No tools — add one in the Tools panel</span>';
                entriesDiv.appendChild(hint);
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
                var collapsed = searching ? false : (_catCollapsed[cat] !== false);

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
                        _catCollapsed[cat] = !(_catCollapsed[cat] !== false);
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
           number baked into the source. selectTool shows one read-only; tools
           are authored in the dedicated Tools panel, not here. */
        function findTool(key) {
            for (var i = 0; i < _tools.length; i++) {
                if (_tools[i].key === key) return _tools[i];
            }
            return null;
        }

        // Canvas step for a tool reference. Only the key/label/type are kept —
        // the setting itself lives globally (authored in the Tools panel), so
        // the block just points at it. The compiler emits an inert, documented
        // marker; the live value is read via ms.settings.get(key) wherever a
        // parameter is wired to this tool.
        function settingDefFor(t) {
            return {
                action: "setting",
                params: { key: t.key, label: t.label || t.key, type: t.type },
            };
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
            // Add the tool to the macro as a shared-setting reference block.
            // Tools are independent of macros — this places an anchor that says
            // "this macro uses this setting"; it never redefines the setting,
            // so several macros can reference the same one.
            html += '<button class="fn-add-btn" id="fn-tool-add">Add to Macro</button>';
            if (t.source === "builder") {
                html += '<button class="fn-add-btn fn-tool-delete" id="fn-tool-delete">Delete Tool</button>';
            }
            html += '</div>';

            detailPane.innerHTML = html;

            var add = document.getElementById("fn-tool-add");
            if (add) {
                add.addEventListener("mouseenter", function() {
                    if (window.playSlot) playSlot("hover");
                });
                add.addEventListener("click", function() {
                    if (window.playSlot) playSlot("interact");
                    if (window.macroLab && window.macroLab.addTool) {
                        window.macroLab.addTool(settingDefFor(t));
                    }
                });
            }

            var del = document.getElementById("fn-tool-delete");
            if (del) {
                del.addEventListener("mouseenter", function() {
                    if (window.playSlot) playSlot("hover");
                });
                del.addEventListener("click", function() {
                    if (window.playSlot) playSlot("back");
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

        // The tool CREATOR was removed: tools are authored in the dedicated
        // Tools panel (Setting Builder) and only referenced here. selectTool /
        // renderToolDetail below still show a tool read-only for wiring.

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
                addBtn.addEventListener("mouseenter", function() {
                    if (window.playSlot) playSlot("hover");
                });
                addBtn.addEventListener("click", function() {
                    if (window.playSlot) playSlot("interact");
                    addToMacro(fn);
                });
            }

            updatePreview(fn);
        }

        /* ── Render a single parameter field ───────────────────────── */
        // Option list for a createSelect tool picker, as the {value,label}
        // array the themed dropdown consumes. The empty "" row is the
        // placeholder / "no tool chosen" state.
        function toolSelectOptions() {
            if (_tools.length === 0) {
                return [{ value: "", label: "No tools — create one first" }];
            }
            var opts = [{ value: "", label: "Pick a tool…" }];
            _tools.forEach(function(t) {
                opts.push({ value: t.key, label: (t.label || t.key) + "  ·  " + t.type });
            });
            return opts;
        }

        // Live createSelect nodes for the currently rendered param fields, keyed
        // by param name, so setToolList can refresh their options in place.
        var _toolSelects = {};

        // Replace each tool-select mount point with a themed createSelect. Falls
        // back to a native <select> only if createSelect isn't loaded.
        function mountToolSelects(fn) {
            _toolSelects = {};
            if (typeof window.createSelect !== "function") return;
            var mounts = detailPane.querySelectorAll(".fn-tool-select-mount");
            for (var i = 0; i < mounts.length; i++) {
                (function(mount) {
                    var name = mount.getAttribute("data-toolmount");
                    var sel = window.createSelect({
                        options: toolSelectOptions(),
                        value: _paramBind[name] || "",
                        className: "fn-tool-select",
                        onChange: function(v) {
                            if (window.playSlot) playSlot("interact");
                            _paramBind[name] = v;
                            _paramValues[name] = { __toolRef: v };
                            updatePreview(fn);
                        },
                    });
                    // The Value/Tool switch reads the current pick via this attr.
                    sel.setAttribute("data-toolsel", name);
                    mount.appendChild(sel);
                    _toolSelects[name] = sel;
                })(mounts[i]);
            }
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
                html += '<div class="fn-param-tool" data-toolwrap="' + esc(p.name) + '"'
                    + (bound ? '' : ' style="display:none"') + '>';
                // A themed createSelect is mounted here after the HTML lands — a
                // native <select> can style its closed control but not its open
                // popup (macOS draws that), so the tool picker broke the shell's
                // look mid-interaction. See mountToolSelects().
                html += '<div class="fn-tool-select-mount" data-toolmount="' + esc(p.name) + '"></div>';
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
                    btn.addEventListener("mouseenter", function() {
                        if (window.playSlot) playSlot("hover");
                    });
                    btn.addEventListener("click", function(e) {
                        e.stopPropagation();
                        if (window.playSlot) playSlot("interact");
                        startKeyCapture(name, btn, fn);
                    });
                })(keyBtns[j]);
            }

            // Modifier chips
            var modChips = detailPane.querySelectorAll("[data-mod]");
            for (var k = 0; k < modChips.length; k++) {
                (function(chip) {
                    var mod = chip.getAttribute("data-mod");
                    chip.addEventListener("mouseenter", function() {
                        if (window.playSlot) playSlot("hover");
                    });
                    chip.addEventListener("click", function() {
                        _modState[mod] = !_modState[mod];
                        if (window.playSlot) playSlot(_modState[mod] ? "toggleOn" : "toggleOff");
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
            // Mounted as themed createSelect nodes (each wires its own onChange).
            mountToolSelects(fn);
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
            if (_view === "tool" && _selectedId) {
                var t = findTool(_selectedId);
                if (t) renderToolDetail(t); else { detailPane.innerHTML = ''; _view = "module"; }
            } else {
                // A module detail may be open and mid-edit — re-rendering it
                // would wipe half-typed fields — so only the tool picker option
                // lists are refreshed in place, keeping each current selection.
                for (var name in _toolSelects) {
                    if (!_toolSelects.hasOwnProperty(name)) continue;
                    var picked = _paramBind[name] || "";
                    _toolSelects[name].setOptions(toolSelectOptions());
                    _toolSelects[name].value = picked;
                }
            }
        }

        /* ── External API: allow ms.shell.eval to call in ──────────── */
        window.fnPicker = {
            select: selectFunction,
            registry: REGISTRY,
            showToast: showToast,
            setToolList: setToolList,
            settingDef: settingDefFor,
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
        "comment":"inputs","code":"macros","setting":"settings"
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
        if (action === "setting") return 'ms.settings.get("' + (params.key || "") + '")';
        if (action === "ms.dragPath") {
            var pts = (typeof params.points === "string" && params.points.trim())
                ? params.points.split(";").filter(function(s){ return s.trim(); }).length : 0;
            return (params.button || "Left") + " drag · " + pts + " pts";
        }
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
        // Opening the parameter editor is its own gesture (right-click a
        // module) rather than a side effect of selecting one — selection alone
        // no longer forces the params panel open, which read as persistent.
        this._onContext = (opts && opts.onContext) || function(){};
        this._tools = [];
        this._map = {};
        // Selection model (Keyboard-Maestro style, text-like):
        //   _selSet   — every currently selected sid (map sid → true)
        //   _anchorId — the pivot for shift-range selection
        // _selId is kept as the "primary" single selection: it is non-null
        // ONLY when exactly one block is selected, and it is what drives the
        // inline parameter editor. Multi-selection ⇒ _selId null ⇒ no params.
        this._selSet   = {};
        this._anchorId = null;
        this._selId    = null;
        this._dragId = null;
        this._dragGroup = null;  // sids being dragged together (doc order)
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
        this._clearSelection();
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

    // Insert a new top-level module before `beforeSid` (or at the end when
    // null), selecting it. Used by the picker→canvas drag; keeps insertion at
    // the top level so an external drop can never land inside a container it
    // has no context for.
    ToolCanvas.prototype.insertDefAt = function(def, beforeSid) {
        var step = deepClone(def);
        step._sid = nextToolId();
        seedContainer(step);
        this._map[step._sid] = step;
        var idx = beforeSid ? this._findIdx(this._tools, beforeSid) : -1;
        if (idx !== -1) this._tools.splice(idx, 0, step);
        else this._tools.push(step);
        this._setSelection([step._sid]);
        this._render();
        this._fireChange();
        return step._sid;
    };

    ToolCanvas.prototype.removeTool = function(sid) {
        if (this._removeFrom(this._tools, sid)) {
            delete this._map[sid];
            this._deselectOne(sid);
            this._render();
            this._emitSelection();
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

    // Locate the list a sid lives in and its index within that list.
    ToolCanvas.prototype._locate = function(sid, list) {
        list = list || this._tools;
        for (var i = 0; i < list.length; i++) {
            if (list[i]._sid === sid) return { list: list, idx: i };
            var s = list[i];
            var r = (s.then && this._locate(sid, s.then))
                 || (s.else && this._locate(sid, s.else))
                 || (s.body && this._locate(sid, s.body));
            if (r) return r;
        }
        return null;
    };

    // Move a group of blocks (given in document order) to a target, keeping
    // their relative order. A single-element group behaves exactly like
    // moveTool, so both drag paths share this code.
    ToolCanvas.prototype.moveTools = function(dragIds, targetId, pos) {
        if (!dragIds || !dragIds.length) return;
        if (dragIds.indexOf(targetId) !== -1) return;   // never drop onto self
        // Collect the step objects, then detach them all from the tree.
        var steps = [];
        for (var i = 0; i < dragIds.length; i++) {
            var s = this._map[dragIds[i]];
            if (s) { steps.push(s); this._removeFrom(this._tools, dragIds[i]); }
        }
        if (!steps.length) return;

        if (pos === "nest") {
            var tgt = this._map[targetId];
            if (tgt) {
                var branch = tgt.action === "if"
                    ? (tgt.then || (tgt.then = []))
                    : (tgt.body || (tgt.body = []));
                for (var j = 0; j < steps.length; j++) branch.push(steps[j]);
            }
        } else {
            // Re-locate the target AFTER detaching, since indices shifted.
            var loc = this._locate(targetId);
            if (loc) {
                var at = pos === "above" ? loc.idx : loc.idx + 1;
                Array.prototype.splice.apply(loc.list, [at, 0].concat(steps));
            } else {
                for (var k = 0; k < steps.length; k++) this._tools.push(steps[k]);
            }
        }
        // The moved blocks stay selected so the group can be nudged again.
        this._setSelection(dragIds);
        this._render();
        this._applySelectionClasses();
        this._emitSelection();
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
        var isSetting = step.action === "setting";
        var el = document.createElement("div");
        el.className = "tool-block" + (this._isSelected(step._sid)?" selected":"")
            + (isSetting ? " tool-block-setting" : "");
        el.setAttribute("data-sid", step._sid);
        // No draggable="true": reordering is pointer-based (see _wireDrag). The
        // HTML5 DnD API dropped drops in this WKWebView, so blocks are dragged
        // with plain mouse events instead.

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
        // A setting block is a reference to a shared tool, not a code action, so
        // it reads "Setting · <label>" rather than the bare "setting" action.
        nm.textContent = isSetting
            ? ("Setting · " + ((step.params && (step.params.label || step.params.key)) || "?"))
            : step.action;
        el.appendChild(nm);

        var pm = document.createElement("span");
        pm.className = "tool-params";
        pm.textContent = paramSummary(step.action, step.params);
        el.appendChild(pm);

        el.appendChild(this._buildToolActions(step));

        el.addEventListener("mouseenter", function() {
            if (window.playSlot) playSlot("hover");
        });
        el.addEventListener("click", function(e) {
            if (e.target.closest(".tool-action-btn") || e.target.closest(".tool-drag-handle")) return;
            if (window.playSlot) playSlot("interact");
            self._clickSelect(step._sid, e);
        });
        // Right-click opens the parameter editor for just this module. Select
        // it first so the editor and the highlight agree.
        el.addEventListener("contextmenu", function(e) {
            e.preventDefault();
            if (window.playSlot) playSlot("interact");
            self.select([step._sid]);
            self._onContext(step._sid);
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
        cp.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
        cp.addEventListener("click", function(e) {
            e.stopPropagation();
            if (window.playSlot) playSlot("interact");
            self.copyStep(step._sid);
        });
        acts.appendChild(cp);

        var pt = document.createElement("div");
        pt.className = "tool-action-btn paste";
        pt.title = "Paste module after this one";
        pt.innerHTML = _svgCache["paste"] || (window.icon ? window.icon("paste") : "");
        pt.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
        pt.addEventListener("click", function(e) {
            e.stopPropagation();
            if (window.playSlot) playSlot("interact");
            self.pasteAfterId(step._sid);
        });
        acts.appendChild(pt);

        var db = document.createElement("div");
        db.className = "tool-action-btn del";
        db.title = "Delete module";
        db.innerHTML = _svgCache["close"] || '<svg class="icon" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><g id="Edit / Close_Circle"><path id="Vector" d="M9 9L11.9999 11.9999M11.9999 11.9999L14.9999 14.9999M11.9999 11.9999L9 14.9999M11.9999 11.9999L14.9999 9M12 21C7.02944 21 3 16.9706 3 12C3 7.02944 7.02944 3 12 3C16.9706 3 21 7.02944 21 12C21 16.9706 16.9706 21 12 21Z" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></g></svg>';
        db.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
        db.addEventListener("click", function(e) {
            e.stopPropagation();
            if (window.playSlot) playSlot("back");
            self.removeTool(step._sid);
        });
        acts.appendChild(db);

        return acts;
    };

    ToolCanvas.prototype._renderContainer = function(step) {
        var self = this;
        var wrap = document.createElement("div");
        wrap.className = "tool-block-container";
        wrap.setAttribute("data-sid", step._sid);

        var header = document.createElement("div");
        header.className = "tool-block" + (this._isSelected(step._sid)?" selected":"");
        header.setAttribute("data-sid", step._sid);
        // Pointer-based drag; no native draggable (see _wireDrag / _renderLeaf).

        var h = document.createElement("div");
        h.className = "tool-drag-handle";
        h.innerHTML = _svgCache["drag"] || '<svg class="icon" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M12 3V9M12 3L9 6M12 3L15 6M12 15V21M12 21L15 18M12 21L9 18M3 12H9M3 12L6 15M3 12L6 9M15 12H21M21 12L18 9M21 12L18 15" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>';
        header.appendChild(h);

        var tg = document.createElement("div");
        tg.className = "tool-nest-toggle";
        tg.innerHTML = _svgCache["chevdown"] || '<svg class="icon" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M7 13L12 18L17 13M7 6L12 11L17 6" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>';
        tg.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
        tg.addEventListener("click", function(e) {
            e.stopPropagation();
            if (window.playSlot) playSlot("interact");
            var collapsed = tg.classList.toggle("collapsed");
            // Collapse every branch of THIS container — an `if` has both a
            // "then" and an "else" nest, each with its own label. A plain
            // querySelector(".tool-nest-body") stopped at "then" and left the
            // "else" nest (and both labels) showing. Only direct children are
            // touched, so a nested block keeps its own collapse state.
            for (var ci = 0; ci < wrap.children.length; ci++) {
                var child = wrap.children[ci];
                if (child.classList.contains("tool-nest-body")
                    || child.classList.contains("tool-nest-label")) {
                    child.classList.toggle("collapsed", collapsed);
                }
            }
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

        header.addEventListener("mouseenter", function() {
            if (window.playSlot) playSlot("hover");
        });
        header.addEventListener("click", function(e) {
            if (e.target.closest(".tool-action-btn")||e.target.closest(".tool-drag-handle")||e.target.closest(".tool-nest-toggle")) return;
            if (window.playSlot) playSlot("interact");
            self._clickSelect(step._sid, e);
        });
        // Right-click opens the parameter editor for this container.
        header.addEventListener("contextmenu", function(e) {
            e.preventDefault();
            if (window.playSlot) playSlot("interact");
            self.select([step._sid]);
            self._onContext(step._sid);
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

        // Dropping a block INTO this branch is handled by the pointer-drag
        // hit-test (see _beginPointerDrag / _commitNest), which targets this
        // element via its data-nest-parent / data-nest-branch attributes. No
        // HTML5 drop wiring here — that API is unreliable in this WKWebView.
        return body;
    };

    /* ── Selection engine ────────────────────────────────────────────
     * The set of selected blocks is _selSet. _selId mirrors it only when the
     * selection is a single block — that is the signal the parameter editor
     * uses, so a multi-selection (or empty selection) shows no params. */

    ToolCanvas.prototype._isSelected = function(sid) {
        return !!this._selSet[sid];
    };
    ToolCanvas.prototype._selCount = function() {
        return Object.keys(this._selSet).length;
    };
    // Selected sids in document (visual) order — the order the user sees, and
    // the order a group keeps when dragged or copied.
    ToolCanvas.prototype._selList = function() {
        var self = this, out = [];
        if (this._root) {
            this._root.querySelectorAll(".tool-block[data-sid]").forEach(function(el) {
                var sid = el.getAttribute("data-sid");
                if (self._selSet[sid] && out.indexOf(sid) === -1) out.push(sid);
            });
        }
        // Fall back to insertion order for any selected id not currently in the
        // DOM (shouldn't happen, but keeps the set from silently dropping ids).
        for (var sid in this._selSet) { if (out.indexOf(sid) === -1) out.push(sid); }
        return out;
    };
    // All sids in document order — the flat visual sequence shift-range walks.
    ToolCanvas.prototype._docOrder = function() {
        var out = [];
        if (this._root) {
            this._root.querySelectorAll(".tool-block[data-sid]").forEach(function(el) {
                var sid = el.getAttribute("data-sid");
                if (out.indexOf(sid) === -1) out.push(sid);
            });
        }
        return out;
    };

    // Update state only (no DOM, no emit). Primary/_selId is set iff exactly
    // one block is selected.
    ToolCanvas.prototype._setSelection = function(ids) {
        this._selSet = {};
        for (var i = 0; i < ids.length; i++) { if (ids[i]) this._selSet[ids[i]] = true; }
        var keys = Object.keys(this._selSet);
        this._selId = keys.length === 1 ? keys[0] : null;
        if (ids.length) this._anchorId = ids[ids.length - 1];
    };
    ToolCanvas.prototype._clearSelection = function() {
        this._selSet = {};
        this._selId = null;
        this._anchorId = null;
    };
    ToolCanvas.prototype._deselectOne = function(sid) {
        delete this._selSet[sid];
        if (this._anchorId === sid) this._anchorId = null;
        var keys = Object.keys(this._selSet);
        this._selId = keys.length === 1 ? keys[0] : null;
    };

    // Repaint .selected on every block from _selSet without a full re-render.
    ToolCanvas.prototype._applySelectionClasses = function() {
        var self = this;
        if (!this._root) return;
        this._root.querySelectorAll(".tool-block[data-sid]").forEach(function(el) {
            var sid = el.getAttribute("data-sid");
            el.classList.toggle("selected", !!self._selSet[sid]);
        });
    };

    // Tell the host what the primary (single) selection is. null ⇒ hide params
    // (nothing selected, or a multi-selection).
    ToolCanvas.prototype._emitSelection = function() {
        this._onSelect(this._selId, this._selId ? this._map[this._selId] : null);
    };

    // Click routing: plain / ⌘(⌃)-toggle / ⇧-range, text-editor semantics.
    ToolCanvas.prototype._clickSelect = function(sid, e) {
        var meta  = e && (e.metaKey || e.ctrlKey);
        var shift = e && e.shiftKey;

        if (meta) {
            // Toggle this block in/out of the selection.
            if (this._selSet[sid]) this._deselectOne(sid);
            else { this._selSet[sid] = true; this._anchorId = sid;
                   var k = Object.keys(this._selSet); this._selId = k.length === 1 ? k[0] : null; }
        } else if (shift && this._anchorId && this._anchorId !== sid) {
            // Select the contiguous visual range between the anchor and here.
            var order = this._docOrder();
            var a = order.indexOf(this._anchorId), b = order.indexOf(sid);
            if (a === -1 || b === -1) { this._setSelection([sid]); }
            else {
                var lo = Math.min(a, b), hi = Math.max(a, b);
                this._selSet = {};
                for (var i = lo; i <= hi; i++) this._selSet[order[i]] = true;
                this._selId = (hi - lo === 0) ? order[lo] : null;
                // keep _anchorId where it was so the range can be re-dragged
            }
        } else {
            // Plain click: if this block is already the sole selection, toggle
            // it off (clears the params); otherwise select just this one.
            if (this._selId === sid && this._selCount() === 1) this._clearSelection();
            else this._setSelection([sid]);
        }

        this._applySelectionClasses();
        this._emitSelection();
    };

    // Public: select exactly these ids and refresh the view + editor.
    ToolCanvas.prototype.select = function(ids) {
        this._setSelection(ids || []);
        this._applySelectionClasses();
        this._emitSelection();
    };
    ToolCanvas.prototype.clearSelection = function() {
        this._clearSelection();
        this._applySelectionClasses();
        this._emitSelection();
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

    // Pointer-based reorder (mousedown → mousemove → mouseup).
    //
    // The HTML5 Drag-and-Drop API does NOT reliably deliver `drop` inside this
    // WKWebView: dragstart/dragover fired but the drop was swallowed, so a
    // dragged block silently bounced back to its origin. Reordering is a pure
    // in-webview interaction, so it can only ever be JavaScript — Lua/Hammerspoon
    // lives outside the webview and never sees the drag (the macro reaches the
    // host only on Save). The fix is to abandon the flaky native API and drive
    // the drag with plain mouse events plus a hand-drawn ghost — the same move
    // the shell already made when the native <select> misbehaved here.
    ToolCanvas.prototype._wireDrag = function(el, step) {
        var self = this;
        el.addEventListener("mousedown", function(e) {
            if (e.button !== 0) return;                          // left button only
            if (e.target.closest(".tool-action-btn")) return;    // copy/paste/delete
            if (e.target.closest(".tool-nest-toggle")) return;   // collapse arrow
            // Suppress the native text-selection drag. Without this, WKWebView
            // treats a held-button move as a selection gesture and swallows every
            // mousemove until release — so begin() (gated on the move threshold)
            // never fires during the hold, and the ghost only latches to the
            // cursor after mouseup, dropping on the next click ("sticky tape").
            // preventDefault on mousedown blocks selection/focus but still lets
            // the synthesised click through, so plain click-select is untouched.
            e.preventDefault();
            self._beginPointerDrag(el, step, e);
        });
    };

    // Runs a single reorder gesture. A drag only actually begins once the
    // pointer crosses a small threshold, so a plain click still falls through
    // to the click-select handler untouched.
    ToolCanvas.prototype._beginPointerDrag = function(el, step, downEvt) {
        var self = this;
        var startX = downEvt.clientX, startY = downEvt.clientY;
        var THRESH = 4;
        var started = false;
        var ghost = null, offX = 0, offY = 0;
        var group = null;
        var target = null;   // { kind:"block", sid, pos } | { kind:"nest", parent, branch }
        var scroller = self._el;

        function begin() {
            started = true;
            // Single block, or the whole multi-selection when the grabbed block
            // is part of one — matching the old drag-group behaviour.
            if (self._isSelected(step._sid) && self._selCount() > 1) {
                group = self._selList();
            } else {
                group = [step._sid];
                if (!self._isSelected(step._sid)) self.select([step._sid]);
            }
            self._dragId = step._sid;
            self._dragGroup = group;
            group.forEach(function(sid) {
                var d = self._root.querySelector('.tool-block[data-sid="'+sid+'"]');
                if (d) d.classList.add("dragging");
            });
            ghost = el.cloneNode(true);
            ghost.classList.add("tool-drag-ghost");
            ghost.style.width = el.offsetWidth + "px";
            var r = el.getBoundingClientRect();
            offX = startX - r.left; offY = startY - r.top;
            if (group.length > 1) {
                var badge = document.createElement("div");
                badge.className = "tool-drag-badge";
                badge.textContent = group.length;
                ghost.appendChild(badge);
            }
            document.body.appendChild(ghost);
            document.body.classList.add("tool-dragging-active");
            moveGhost(startX, startY);
            if (window.playSlot) playSlot("interact");
        }

        function moveGhost(x, y) {
            if (ghost) { ghost.style.left = (x - offX) + "px"; ghost.style.top = (y - offY) + "px"; }
        }

        // Figure out where a drop at (x,y) would land and paint the marker.
        // The ghost is pointer-events:none, so elementFromPoint sees through it.
        function hitTest(x, y) {
            self._clearDrops();
            target = null;
            var under = document.elementFromPoint(x, y);
            if (!under || !under.closest) return;

            var blockEl = under.closest(".tool-block[data-sid]");
            if (blockEl && group.indexOf(blockEl.getAttribute("data-sid")) !== -1) {
                blockEl = null;   // a block in the drag group is not a target
            }
            if (blockEl) {
                var tid = blockEl.getAttribute("data-sid");
                var tstep = self._map[tid];
                var rect = blockEl.getBoundingClientRect();
                var ry = y - rect.top, h = rect.height;
                var pos;
                if (tstep && self._isContainer(tstep) && ry > h*0.3 && ry < h*0.7) pos = "nest";
                else if (ry < h/2) pos = "above";
                else pos = "below";
                if (pos === "nest") {
                    for (var i = 0; i < group.length; i++) {
                        if (group[i] === tid || self._isDesc(group[i], tid)) return;
                    }
                }
                blockEl.classList.add(pos === "nest" ? "drag-over-nest"
                    : pos === "above" ? "drag-over-above" : "drag-over-below");
                target = { kind: "block", sid: tid, pos: pos };
                return;
            }

            // Not over any block — maybe over an (empty) container branch.
            var nestEl = under.closest(".tool-nest-body");
            if (nestEl) {
                var psid = nestEl.getAttribute("data-nest-parent");
                for (var j = 0; j < group.length; j++) {
                    if (group[j] === psid || self._isDesc(group[j], psid)) return;
                }
                nestEl.classList.add("drag-target");
                target = { kind: "nest", parent: psid, branch: nestEl.getAttribute("data-nest-branch") };
            }
        }

        function autoscroll(y) {
            if (!scroller) return;
            var r = scroller.getBoundingClientRect(), M = 28;
            if (y < r.top + M) scroller.scrollTop -= 10;
            else if (y > r.bottom - M) scroller.scrollTop += 10;
        }

        function onMove(e) {
            if (!started) {
                if (Math.abs(e.clientX - startX) < THRESH && Math.abs(e.clientY - startY) < THRESH) return;
                begin();
            }
            e.preventDefault();
            moveGhost(e.clientX, e.clientY);
            autoscroll(e.clientY);
            hitTest(e.clientX, e.clientY);
        }

        function commit() {
            if (!target) return;
            if (target.kind === "block") self.moveTools(group, target.sid, target.pos);
            else self._commitNest(group, target.parent, target.branch);
        }

        function cleanup() {
            document.removeEventListener("mousemove", onMove, true);
            document.removeEventListener("mouseup", onUp, true);
            document.removeEventListener("keydown", onKey, true);
            if (ghost) ghost.remove();
            ghost = null;
            document.body.classList.remove("tool-dragging-active");
            self._root.querySelectorAll(".tool-block.dragging").forEach(function(d) {
                d.classList.remove("dragging");
            });
            self._clearDrops();
            self._dragId = null; self._dragGroup = null;
        }

        function onUp(e) {
            if (started) {
                e.preventDefault(); e.stopPropagation();
                commit();
                // Swallow the click that a mouseup would otherwise synthesise,
                // so a drag never doubles as a select.
                var swallow = function(ev) {
                    ev.stopPropagation(); ev.preventDefault();
                    document.removeEventListener("click", swallow, true);
                };
                document.addEventListener("click", swallow, true);
            }
            cleanup();
        }
        function onKey(e) { if (e.key === "Escape") { target = null; cleanup(); } }

        document.addEventListener("mousemove", onMove, true);
        document.addEventListener("mouseup", onUp, true);
        document.addEventListener("keydown", onKey, true);
    };

    // Drop a group into a container branch (then/else/body). Mirrors moveTools
    // for the nest case, but keeps the explicit branch — moveTools' "nest" can
    // only reach a container's default branch, not an if-block's else.
    ToolCanvas.prototype._commitNest = function(group, parentSid, branch) {
        var parent = this._map[parentSid];
        if (!parent) return;
        for (var i = 0; i < group.length; i++) {
            if (group[i] === parentSid || this._isDesc(group[i], parentSid)) return;
        }
        var steps = [];
        for (var g = 0; g < group.length; g++) {
            var st = this._map[group[g]];
            if (st) { steps.push(st); this._removeFrom(this._tools, group[g]); }
        }
        if (!steps.length) return;
        var dst = branch === "then" ? (parent.then || (parent.then = []))
                : branch === "else" ? (parent.else || (parent.else = []))
                : (parent.body || (parent.body = []));
        for (var k = 0; k < steps.length; k++) dst.push(steps[k]);
        this._setSelection(group);
        this._render(); this._applySelectionClasses(); this._emitSelection(); this._fireChange();
    };

    ToolCanvas.prototype._clearDrops = function() {
        this._root.querySelectorAll(".drag-over-above,.drag-over-below,.drag-over-nest").forEach(function(el) {
            el.classList.remove("drag-over-above","drag-over-below","drag-over-nest");
        });
        this._root.querySelectorAll(".drag-target").forEach(function(el) { el.classList.remove("drag-target"); });
    };

    ToolCanvas.prototype.updateTool = function(sid, params, opts) {
        var s = this._map[sid]; if (!s) return;
        for (var k in params) { if (params.hasOwnProperty(k)) s.params[k] = params[k]; }
        // Live typing passes { quiet:true }. A full _render() here rebuilds the
        // canvas and (via the editor's render hook) the parameter form, tearing
        // down the very input being typed into — so each keystroke kicked focus
        // out of the field. Quiet updates patch only the block's on-canvas
        // summary and leave the DOM (and focus) intact.
        if (opts && opts.quiet) {
            this._patchSummary(sid);
            this._fireChange();
            return;
        }
        this._render(); this._fireChange();
    };

    // Update just the on-canvas parameter summary for one block, without
    // re-rendering. Direct-child selector so a container's summary isn't
    // confused with a nested child's.
    ToolCanvas.prototype._patchSummary = function(sid) {
        var s = this._map[sid]; if (!s || !this._root) return;
        var block = this._root.querySelector('.tool-block[data-sid="' + sid + '"]');
        if (!block) return;
        var el = block.querySelector(":scope > .tool-params");
        if (el) el.textContent = paramSummary(s.action, s.params);
    };

    ToolCanvas.prototype.getSelectedId = function() { return this._selId; };
    ToolCanvas.prototype.getSelectedTool = function() { return this._selId ? this._map[this._selId] : null; };
    ToolCanvas.prototype.hasSelection = function() { return this._selCount() > 0; };
    ToolCanvas.prototype.getSelectedIds = function() { return this._selList(); };
    // Select every top-level block (⌘A). Nested blocks come along visually via
    // their containers, so a select-all of the top level is the useful default.
    ToolCanvas.prototype.selectAll = function() {
        var ids = this._tools.map(function(s) { return s._sid; });
        this.select(ids);
    };

    /* ── Clipboard (copy / cut / paste) ─────────────────────────────── */
    // Copy a specific module (by id) onto the module clipboard. Adding the
    // .has-clip class to the canvas root is what reveals every module's paste
    // button — see the CSS rule that gates .tool-action-btn.paste.
    // The clipboard holds an array of stripped module defs (one entry for a
    // single copy, several for a multi-selection). The .has-clip class on the
    // root reveals every block's paste button.
    ToolCanvas.prototype._setClipboard = function(steps) {
        var clones = deepClone(steps);
        this._strip(clones);
        try { navigator.clipboard.writeText(JSON.stringify(clones.length === 1 ? clones[0] : clones)); } catch(e) {}
        this._clipboard = clones;
        if (this._root) this._root.classList.add("has-clip");
        return true;
    };
    ToolCanvas.prototype.copyStep = function(sid) {
        var step = sid ? this._map[sid] : null;
        if (!step) return false;
        return this._setClipboard([step]);
    };
    ToolCanvas.prototype.copySelected = function() {
        var ids = this._selList();
        if (!ids.length) return false;
        var steps = [];
        for (var i = 0; i < ids.length; i++) { if (this._map[ids[i]]) steps.push(this._map[ids[i]]); }
        if (!steps.length) return false;
        return this._setClipboard(steps);
    };
    ToolCanvas.prototype.cutSelected = function() {
        if (!this.copySelected()) return false;
        this.removeSelected();
        return true;
    };
    // Remove every selected block (a grouped delete). Detaches all, then
    // clears the selection and repaints once.
    ToolCanvas.prototype.removeSelected = function() {
        var ids = this._selList();
        if (!ids.length) return false;
        for (var i = 0; i < ids.length; i++) {
            if (this._removeFrom(this._tools, ids[i])) delete this._map[ids[i]];
        }
        this._clearSelection();
        this._render();
        this._emitSelection();
        this._fireChange();
        return true;
    };
    // Paste the clipboard modules after `afterId` (or at the end when null),
    // preserving their order and selecting the pasted block(s).
    ToolCanvas.prototype.pasteAfterId = function(afterId) {
        if (!this._clipboard) return false;
        var entries = Array.isArray(this._clipboard) ? this._clipboard : [this._clipboard];
        if (!entries.length) return false;
        var newIds = [];
        var insertAt = afterId ? this._findIdx(this._tools, afterId) : -1;
        // No anchor (nothing selected) → paste at the TOP of the macro, the only
        // way to insert above every existing module. With an anchor we insert
        // directly after it, preserving group order.
        var atTop = (insertAt === -1);
        for (var i = 0; i < entries.length; i++) {
            var clone = deepClone(entries[i]);
            clone._sid = nextToolId();
            this._map[clone._sid] = clone;
            if (clone.then) this._assignIds(clone.then);
            if (clone.else) this._assignIds(clone.else);
            if (clone.body) this._assignIds(clone.body);
            if (atTop) this._tools.splice(i, 0, clone);
            else this._tools.splice(insertAt + 1 + i, 0, clone);
            newIds.push(clone._sid);
        }
        this._setSelection(newIds);
        this._render();
        this._applySelectionClasses();
        this._emitSelection();
        if (this._root) this._root.classList.add("has-clip");
        this._fireChange();
        return true;
    };
    ToolCanvas.prototype.pasteAfter = function() {
        // Paste after the last selected block so a group paste lands in order.
        var ids = this._selList();
        return this.pasteAfterId(ids.length ? ids[ids.length - 1] : null);
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
        // Shown on the closed button when nothing is selected — never a menu row.
        var PLACEHOLDER = "Select";

        function labelFor(v) {
            for (var i = 0; i < _opts.length; i++) {
                if (_opts[i].value === v) return _opts[i].label;
            }
            return "";
        }
        function close() { root.classList.remove("open"); }
        function render() {
            // Empty value → the button reads "Select"; the menu never carries a
            // "Select" row (it's a placeholder, not a real choice).
            var lbl = _value ? labelFor(_value) : "";
            label.textContent = lbl || PLACEHOLDER;
            menu.innerHTML = "";
            // Real, selectable options only — anything with an empty value is a
            // placeholder and is dropped from the list.
            var choices = _opts.filter(function(o) { return o.value !== ""; });
            if (choices.length === 0) {
                // Nothing created yet: a single, non-selecting "None" row so the
                // open menu isn't blank. It's replaced by the first real entry
                // as soon as one exists.
                var none = document.createElement("div");
                none.className = "macro-select-item macro-select-empty";
                none.textContent = "None";
                menu.appendChild(none);
                return;
            }
            choices.forEach(function(o) {
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

        // No options until the macro list arrives from Lua. The button reads
        // "Select" on its own, and the open menu shows "None".
        root.setOptions([]);
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
    // Shell sounds: hover on enter, interact on focus (a click into the field).
    // Guarded on playSlot so it no-ops in a bus-less context.
    nameInput.addEventListener("mouseenter", function() {
        if (window.playSlot) playSlot("hover");
    });
    nameInput.addEventListener("focus", function() {
        if (window.playSlot) playSlot("interact");
    });
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

    // Class field — whether this visual macro is a MAIN or OPTIONAL one. It
    // drives the compiled ms.bind.define group ("visual - main" / "visual -
    // optional"), which is what the Binds tab groups under. Purely a grouping
    // convention (only "system" is functionally special), so this needs no
    // host change — the compiler already emits macroDef.group verbatim.
    var _currentMacroClass = "main";   // "main" | "optional"

    var classLabel = document.createElement("span");
    classLabel.style.cssText = "font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.6px;color:var(--text3);margin-left:8px;margin-right:4px";
    classLabel.textContent = "Class";
    toolbar.appendChild(classLabel);

    // Two-button segmented control, reusing the param Value/Tool switch styling.
    var classSeg = document.createElement("span");
    classSeg.className = "fn-bind-switch macro-class-seg";
    function buildClassOpt(value, text) {
        var b = document.createElement("button");
        b.className = "fn-bind-opt" + (_currentMacroClass === value ? " on" : "");
        b.setAttribute("data-class", value);
        b.textContent = text;
        b.title = value === "main"
            ? "Main macro — grouped under VISUAL - MAIN"
            : "Optional macro — grouped under VISUAL - OPTIONAL";
        b.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
        b.addEventListener("click", function() {
            if (_currentMacroClass === value) return;
            if (window.playSlot) playSlot("interact");
            setMacroClass(value);
            _macroDirty = true;
            updateSaveBtnState();
        });
        return b;
    }
    classSeg.appendChild(buildClassOpt("main", "Main"));
    classSeg.appendChild(buildClassOpt("optional", "Optional"));
    toolbar.appendChild(classSeg);

    // Reflect the current class onto the segmented control.
    function setMacroClass(value) {
        _currentMacroClass = (value === "optional") ? "optional" : "main";
        var opts = classSeg.querySelectorAll(".fn-bind-opt");
        opts.forEach(function(o) {
            o.classList.toggle("on", o.getAttribute("data-class") === _currentMacroClass);
        });
    }
    // Derive the class from a stored macro group string ("visual - optional").
    function classFromGroup(group) {
        return (typeof group === "string" && /optional/i.test(group)) ? "optional" : "main";
    }

    // Right-side action cluster. `margin-left:auto` pins it to the right edge,
    // and because it's a single flex child it drops down as one right-aligned
    // unit when the toolbar wraps — rather than the buttons scattering to the
    // left of a new row (which is what a bare flex spacer + loose buttons did).
    var actions = document.createElement("div");
    actions.className = "macro-toolbar-actions";

    // New macro button
    var newBtn = document.createElement("button");
    newBtn.className = "macro-toolbar-btn";
    newBtn.textContent = "New";
    actions.appendChild(newBtn);

    // Save button
    var saveBtn = document.createElement("button");
    saveBtn.className = "macro-toolbar-btn primary";
    saveBtn.textContent = "Save";
    actions.appendChild(saveBtn);

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

    // Record button — with a paired "⋯" that opens the recording-settings
    // menu. The two sit in one row so the options live right next to the
    // action they configure.
    var recordRow = document.createElement("div");
    recordRow.className = "macro-record-row";
    var recordBtn = document.createElement("button");
    recordBtn.className = "macro-toolbar-btn";
    recordBtn.innerHTML = menuLabel("record", "Record");
    recordBtn.title = "Record user actions into modules";
    recordRow.appendChild(recordBtn);

    var recSettingsBtn = document.createElement("button");
    recSettingsBtn.className = "macro-toolbar-btn macro-record-settings-btn";
    recSettingsBtn.textContent = "⋯"; // ⋯
    recSettingsBtn.title = "Recording settings";
    recSettingsBtn.setAttribute("aria-label", "Recording settings");
    recordRow.appendChild(recSettingsBtn);

    overflowMenu.appendChild(recordRow);

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

    // Change the app "Edit File" opens in. The editMacros confirm only offers a
    // picker when no editor is set yet, so this is how a wrong/stale choice is
    // switched.
    var editorBtn = document.createElement("button");
    editorBtn.className = "macro-toolbar-btn";
    editorBtn.innerHTML = menuLabel("settings", "Change Editor");
    editorBtn.title = "Pick which app opens ms_macros.lua";
    overflowMenu.appendChild(editorBtn);

    actions.appendChild(overflowWrap);
    toolbar.appendChild(actions);

    // ── Main area ──
    var mainArea = document.createElement("div");
    mainArea.className = "macros-main";

    // Tool canvas area
    var toolArea = document.createElement("div");
    toolArea.className = "macros-tool-area";
    // Canvas container (ToolCanvas will be mounted here)
    var canvasContainer = document.createElement("div");
    // overflow-y:auto (not hidden) so the module list scrolls: the inner
    // .tool-canvas grows to its content height, and this bounded flex child is
    // the scroller. The inline editor panel lives inside that flow, so it
    // scrolls into view instead of being clipped.
    canvasContainer.className = "macros-canvas-scroll";
    canvasContainer.style.cssText = "flex:1;overflow-y:auto;overflow-x:hidden;position:relative";
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
    overlayClose.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
    overlayClose.addEventListener("click", function() {
        if (window.playSlot) playSlot("back");
        closeFnOverlay();
    });
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

    /* ── Pack Info (ms.macroMeta) editor ─────────────────────────────
       The visual macro pack carries an ms.macroMeta credit block (name /
       author / website) that the compiler bakes into the generated file and
       the loading screen shows. It lives at the top of the Binds tab so the
       pack's identity is edited alongside its binds. Saving round-trips
       through the host, which rewrites the JSON, recompiles, and reloads so
       ms.macroMeta updates live. */
    var _metaLoaded  = false;   // suppress dirty-marking during programmatic fill
    var _metaDirty   = false;
    var _metaOwned   = false;   // true when handwritten ms_macros.lua owns the meta

    function metaField(labelText, placeholder) {
        var wrap = document.createElement("label");
        wrap.className = "meta-field";
        var lb = document.createElement("span");
        lb.className = "meta-field-label";
        lb.textContent = labelText;
        var inp = document.createElement("input");
        inp.type = "text";
        inp.className = "meta-input";
        inp.placeholder = placeholder || "";
        // Keydown must not bubble to the canvas shortcut handler (⌘A/Delete etc.)
        inp.addEventListener("keydown", function(e) { e.stopPropagation(); });
        inp.addEventListener("input", function() {
            if (_metaLoaded) { _metaDirty = true; updateMetaSaveBtn(); }
        });
        wrap.appendChild(lb);
        wrap.appendChild(inp);
        return { wrap: wrap, input: inp };
    }

    // Collapsed by default: the editor is set-once, but it sits above the
    // bind list and expanded it ate a third of the tab. Collapsed it is a
    // single header row, and the chevron says there is more.
    var metaCard = document.createElement("div");
    metaCard.className = "section macro-meta-section collapsed";
    var metaHead = document.createElement("div");
    metaHead.className = "section-head macro-meta-head";
    var metaChev = document.createElement("span");
    metaChev.className = "macro-meta-chev";
    metaChev.innerHTML = (typeof window.icon === "function"
        && window.ICONS && window.ICONS.chevdown)
        ? window.icon("chevdown") : "";
    var metaTitle = document.createElement("span");
    metaTitle.className = "section-title";
    metaTitle.textContent = "Pack Info";
    var metaDesc = document.createElement("span");
    metaDesc.className = "section-desc";
    metaDesc.textContent = "Credits baked into your visual macros (ms.macroMeta)";
    metaHead.appendChild(metaChev);
    metaHead.appendChild(metaTitle);
    metaHead.appendChild(metaDesc);
    metaHead.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
    metaHead.addEventListener("click", function() {
        if (window.playSlot) playSlot("interact");
        metaCard.classList.toggle("collapsed");
    });
    metaCard.appendChild(metaHead);

    var metaBody = document.createElement("div");
    metaBody.className = "section-body macro-meta-body";
    var _metaName    = metaField("Name",    "My Macros");
    var _metaVersion = metaField("Version", "1.0.0");
    var _metaAuthor  = metaField("Author",  "You");
    var _metaWebsite = metaField("Website", "https://…");
    metaBody.appendChild(_metaName.wrap);
    metaBody.appendChild(_metaVersion.wrap);
    metaBody.appendChild(_metaAuthor.wrap);
    metaBody.appendChild(_metaWebsite.wrap);

    var metaSaveRow = document.createElement("div");
    metaSaveRow.className = "macro-meta-save-row";
    var metaSaveBtn = document.createElement("button");
    metaSaveBtn.className = "macro-toolbar-btn meta-save-btn";
    metaSaveBtn.textContent = "Save Pack Info";
    metaSaveBtn.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
    metaSaveBtn.addEventListener("click", function() {
        if (!_metaDirty) return;
        if (window.playSlot) playSlot("interact");
        if (window.shellPost) {
            shellPost("macros", "setMeta", {
                name:    _metaName.input.value.trim(),
                version: _metaVersion.input.value.trim(),
                author:  _metaAuthor.input.value.trim(),
                website: _metaWebsite.input.value.trim(),
            });
        }
        _metaDirty = false;
        updateMetaSaveBtn();
    });
    metaSaveRow.appendChild(metaSaveBtn);
    metaBody.appendChild(metaSaveRow);
    metaCard.appendChild(metaBody);
    bindsSection.insertBefore(metaCard, bindsScroll);

    function updateMetaSaveBtn() {
        var on = _metaDirty && !_metaOwned;
        metaSaveBtn.disabled = !on;
        metaSaveBtn.style.opacity = on ? "1" : "0.5";
    }
    updateMetaSaveBtn();

    function refreshMeta() {
        if (window.shellPost) shellPost("macros", "getMeta", {});
    }

    function setMeta(meta) {
        meta = meta || {};
        _metaLoaded = false;
        _metaName.input.value    = meta.name    || "";
        _metaVersion.input.value = meta.version || "";
        _metaAuthor.input.value  = meta.author  || "";
        _metaWebsite.input.value = meta.website || "";
        _metaLoaded = true;
        _metaDirty  = false;

        // When a handwritten ms_macros.lua supplies credits it owns them: the
        // visual copy is inert, so present these as read-only, sourced from the
        // handwritten file rather than a second set the runtime ignores.
        _metaOwned = meta.owned === true;
        [_metaName, _metaVersion, _metaAuthor, _metaWebsite].forEach(function(f) {
            f.input.readOnly = _metaOwned;
            f.input.classList.toggle("meta-input-locked", _metaOwned);
        });
        metaDesc.textContent = _metaOwned
            ? "Sourced from your handwritten ms_macros.lua (read-only)"
            : "Credits baked into your visual macros (ms.macroMeta)";
        metaSaveRow.style.display = _metaOwned ? "none" : "";
        updateMetaSaveBtn();
    }

    ["builder", "binds"].forEach(function(id) {
        var b = document.createElement("button");
        b.className = "mtab" + (id === "binds" ? " active" : "");
        b.setAttribute("data-mtab", id);
        b.textContent = id === "builder" ? "Builder" : "Manager";
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
            if (tab === "binds") { refreshBindList(); refreshMeta(); }
        },
    });

    // ── Tool Canvas instance ──
    _canvas = new ToolCanvas(canvasContainer, {
        onChange: function(steps) {
            _macroDirty = true;
            updateSaveBtnState();
        },
        onSelect: function(sid, step) {
            if (!_toolEditor) return;
            // Selecting a block no longer opens its params — that panel stayed
            // up persistently and got in the way. Selection only *closes* a
            // stale editor: if the open block is no longer the sole selection,
            // drop the panel. Opening is now the right-click gesture (onContext).
            if (_toolEditor._open && (!sid || _toolEditor._toolSid !== sid)) {
                _toolEditor.close();
            }
        },
        onContext: function(sid) {
            if (!_toolEditor || !sid) return;
            // Right-click toggles the parameter editor: if this module's panel is
            // already the open one, close it; otherwise open it. Without the
            // toggle a second right-click just re-opened the same panel, so the
            // menu felt impossible to dismiss by the gesture that summoned it.
            if (_toolEditor._open && _toolEditor._toolSid === sid) {
                _toolEditor.close();
            } else {
                _toolEditor.open(sid);
            }
        }
    });

    // ── Picker → canvas drag-drop ───────────────────────────────────
    // Dropping a module from the Add-Module picker onto the canvas inserts it
    // as a new top-level module. Listeners are bound on the container in the
    // CAPTURE phase and only act on our custom MIME type: this lets them
    // intercept the external drag before the per-block reorder handlers (which
    // stopPropagation on drop) can swallow it, while internal reorder drags —
    // which carry no such type — fall straight through untouched.
    (function() {
        var FN_MIME   = "application/x-ms-fn";
        var TOOL_MIME = "application/x-ms-tool";
        function hasType(e, mime) {
            var types = e.dataTransfer && e.dataTransfer.types;
            if (!types) return false;
            return Array.prototype.indexOf.call(types, mime) !== -1;
        }
        function hasFn(e)   { return hasType(e, FN_MIME) || hasType(e, TOOL_MIME); }
        // Build a shared-setting reference step for a dragged tool key.
        function buildToolDef(key) {
            var tools = window.msMacroTools || [];
            for (var i = 0; i < tools.length; i++) {
                if (tools[i].key === key) {
                    return (window.fnPicker && window.fnPicker.settingDef)
                        ? window.fnPicker.settingDef(tools[i])
                        : { action: "setting", params: { key: tools[i].key, label: tools[i].label || tools[i].key, type: tools[i].type } };
                }
            }
            return null;
        }
        // Build a module def with default params from the shared registry.
        function buildDefaultDef(fnId) {
            var reg = window.fnPicker && window.fnPicker.registry;
            if (!reg) return null;
            var fn = null;
            for (var i = 0; i < reg.length; i++) {
                if (reg[i].id === fnId) { fn = reg[i]; break; }
            }
            if (!fn) return null;
            var params = {};
            (fn.params || []).forEach(function(p) {
                if (p.type === "mods") params[p.name] = [];
                else if (p.type === "number") params[p.name] = 0;
                else params[p.name] = "";
            });
            return { action: fn.name, params: params };
        }
        // Which existing top-level block should the new one land before? The
        // first whose vertical midpoint is below the cursor; else append.
        function beforeSidAt(clientY) {
            var root = _canvas._root;
            var blocks = root.children;
            for (var i = 0; i < blocks.length; i++) {
                var b = blocks[i];
                if (!b.getAttribute) continue;
                var sid = b.getAttribute("data-sid");
                if (!sid) continue;
                var r = b.getBoundingClientRect();
                if (clientY < r.top + r.height / 2) return sid;
            }
            return null;
        }
        canvasContainer.addEventListener("dragenter", function(e) {
            if (!hasFn(e)) return;
            e.preventDefault();
            e.stopPropagation();
        }, true);
        canvasContainer.addEventListener("dragover", function(e) {
            if (!hasFn(e)) return;
            e.preventDefault();
            e.stopPropagation();
            e.dataTransfer.dropEffect = "copy";
            _canvas._root.classList.add("fn-drop-target");
        }, true);
        canvasContainer.addEventListener("dragleave", function(e) {
            if (!hasFn(e)) return;
            // Only clear when the pointer actually leaves the container, not on
            // every crossing between child blocks.
            if (e.target === canvasContainer || !canvasContainer.contains(e.relatedTarget)) {
                _canvas._root.classList.remove("fn-drop-target");
            }
        }, true);
        canvasContainer.addEventListener("drop", function(e) {
            if (!hasFn(e)) return;
            e.preventDefault();
            e.stopPropagation();
            _canvas._root.classList.remove("fn-drop-target");
            var def = null;
            if (hasType(e, TOOL_MIME)) {
                def = buildToolDef(e.dataTransfer.getData(TOOL_MIME));
            } else {
                def = buildDefaultDef(e.dataTransfer.getData(FN_MIME));
            }
            if (!def) return;
            _canvas.insertDefAt(def, beforeSidAt(e.clientY));
            _macroDirty = true;
            updateSaveBtnState();
            if (window.playSlot) playSlot("interact");
            closeFnOverlay();
        }, true);
    })();

    // ── Tool keyboard shortcuts (copy/cut/paste/delete) ─────────────
    // Bound on document, not toolArea: the tool blocks and their area are not
    // focusable, so a keydown never landed on toolArea and every shortcut was
    // dead. Gate on the builder being the visible section and a module being
    // selected, and bail while typing into a field so editing text is normal.
    document.addEventListener("keydown", function(e) {
        if (!builderSection.classList.contains("active")) return;
        var t = e.target;
        if (t && t.closest && t.closest("input, textarea, [contenteditable='true']")) return;
        var mod = e.metaKey || e.ctrlKey;
        // ⌘A selects every top-level block; paste works even with nothing
        // selected (lands at the end). Everything else needs a selection.
        if (mod && (e.key === "a" || e.key === "A")) {
            e.preventDefault();
            _canvas.selectAll();
            return;
        }
        if (mod && (e.key === "v" || e.key === "V")) {
            e.preventDefault();
            _canvas.pasteAfter();
            _macroDirty = true;
            updateSaveBtnState();
            return;
        }
        if (e.key === "Escape" && _canvas.hasSelection()) {
            e.preventDefault();
            _canvas.clearSelection();
            return;
        }
        if (!_canvas.hasSelection()) return;
        if (mod && (e.key === "c" || e.key === "C")) {
            e.preventDefault();
            _canvas.copySelected();
        } else if (mod && (e.key === "x" || e.key === "X")) {
            e.preventDefault();
            _canvas.cutSelected();
            _macroDirty = true;
            updateSaveBtnState();
        } else if (e.key === "Delete" || e.key === "Backspace") {
            e.preventDefault();
            _canvas.removeSelected();
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
    // Closed by default. The overlay is only slid off-screen (transform), not
    // removed from the DOM, so without `inert` its buttons/inputs stayed in the
    // tab order — Tab would move focus into the invisible, off-screen panel and
    // break the illusion that it is closed. `inert` takes its contents out of
    // the tab order (and pointer/a11y) without touching the slide animation.
    overlay.inert = true;
    function openFnOverlay() {
        overlay.classList.add("open");
        overlay.inert = false;
        // Pull the current tool list every time — a tool may have been added
        // or removed from the Settings panel since the overlay last opened.
        refreshToolList();
    }
    function closeFnOverlay() {
        overlay.classList.remove("open");
        overlay.inert = true;
    }
    addToolBtn.addEventListener("mouseenter", function() {
        if (window.playSlot) playSlot("hover");
    });
    addToolBtn.addEventListener("click", function() {
        if (window.playSlot) playSlot("interact");
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

    // Themed delete confirmation → Promise<boolean>. Uses the shell's own modal
    // (window.openModal, from panel-settings.js) rather than a native confirm(),
    // which macOS draws in its own chrome and which can softlock behind the
    // always-on-top shell. Falls back to a native confirm only if the shell
    // modal isn't available (e.g. a popout that never loaded panel-settings).
    function confirmDelete(name) {
        var msg = 'Delete "' + name + '"? This cannot be undone.';
        if (typeof window.openModal === "function") {
            return window.openModal("Delete macro", msg, "Delete", "Cancel")
                .then(function(r) { return !!(r && r.confirmed); });
        }
        // ui-lint-allow-native: last-resort fallback if the shell modal is absent.
        var ok = (typeof window.confirm !== "function") || window.confirm(msg);
        return Promise.resolve(ok);
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

            // Delete — a peer/sub macro is a real macro of its own (it just
            // borrows another's trigger), so it deserves the same delete the
            // main rows have. Guarded by a confirm like the main path.
            if (m.group !== "system" && !m.systemBind) {
                acts.appendChild(iconBtn("trash", "Delete macro", function() {
                    confirmDelete(m.label || m.id).then(function(ok) {
                        if (!ok) return;
                        if (window.playSlot) playSlot("back");
                        shellPost("macros", "deleteMacro", { id: m.id });
                    });
                }));
            }
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

            // Delete — only user-authored macros can be removed; system macros
            // and the built-in system binds have no delete affordance. A single
            // confirm guards against a misclick since the Manager list has no
            // "currently editing" context to fall back on.
            if (m.group !== "system" && !m.systemBind) {
                acts.appendChild(iconBtn("trash", "Delete macro", function() {
                    confirmDelete(m.label || m.id).then(function(ok) {
                        if (!ok) return;
                        if (window.playSlot) playSlot("back");
                        shellPost("macros", "deleteMacro", { id: m.id });
                        // Optimistic: drop it locally and repaint so the row leaves
                        // immediately; the host refresh reconciles on its next push.
                        _bindList = _bindList.filter(function(x) { return x.id !== m.id; });
                        renderBindList();
                    });
                }));
            }
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
                titleCaseGroup(g),
                g === "system" ? "Always live — these cannot be disabled" : null,
                rows,
            ));
        });
    }

    // Title-case each word of a group key so compound groups read cleanly:
    // "visual - main" → "Visual - Main", "system" → "System".
    function titleCaseGroup(g) {
        return String(g).replace(/[A-Za-z]+/g, function(w) {
            return w.charAt(0).toUpperCase() + w.slice(1).toLowerCase();
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
        // Real macro ids only — the "Select" placeholder lives on the button,
        // not as a menu row, and an empty list renders as "None".
        var opts = [];
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
            setMacroClass("main");
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
        setMacroClass(classFromGroup(def.group));
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
            // Group the compiled bind under VISUAL - MAIN / VISUAL - OPTIONAL
            // per the toolbar Class control.
            group: "visual - " + _currentMacroClass,
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
        setMacroClass("main");
        _macroDirty = false;
        updateSaveBtnState();
        refreshMacroList();
    }

    function updateSaveBtnState() {
        saveBtn.style.opacity = _macroDirty ? "1" : "0.5";
    }

    /* ── Wire toolbar buttons ────────────────────────────────────── */
    newBtn.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
    newBtn.addEventListener("click", function() {
        if (window.playSlot) playSlot("interact");
        _currentMacroId = null;
        _currentMacroDef = null;
        _canvas.load([]);
        nameInput.value = "";
        nameInput.focus();
        setMacroClass("main");
        _macroDirty = false;
        updateSaveBtnState();
        macroSelect.value = "";
        updateBindBtn();
    });

    saveBtn.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
    saveBtn.addEventListener("click", function() {
        if (window.playSlot) playSlot("interact");
        saveMacro();
    });

    editFileBtn.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
    editFileBtn.addEventListener("click", function() {
        if (window.playSlot) playSlot("interact");
        // The action router keys on body.action (ms_ui _routeAction), so an
        // empty body silently no-ops — every other macros action includes it.
        if (window.shellPost) shellPost("macros", "editMacros", { action: "editMacros" });
    });

    editorBtn.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
    editorBtn.addEventListener("click", function() {
        if (window.playSlot) playSlot("interact");
        if (window.shellPost) shellPost("macros", "chooseMacroEditor", { action: "chooseMacroEditor" });
    });

    /* ── Test Run ────────────────────────────────────────────────── */
    var _testRunning = false;
    var _testToastTimer = null;

    function showTestToast(msg, type, iconName) {
        // Icon path builds via DOM so msg stays inert text (some callers pass
        // interpolated error strings) while the leading glyph becomes real SVG.
        if (iconName && window.icon) {
            testToast.innerHTML = window.icon(iconName);
            testToast.appendChild(document.createTextNode(" " + msg));
        } else {
            testToast.textContent = msg;
        }
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

    testBtn.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
    testBtn.addEventListener("click", function() {
        if (_testRunning) return;
        var steps = _canvas.serialize();
        if (!steps || steps.length === 0) {
            if (window.playSlot) playSlot("back");
            showTestToast("No steps to run", "error");
            return;
        }
        if (window.playSlot) playSlot("interact");

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

    // Recording options, tweaked through the "⋯" menu next to Record and
    // persisted so a chosen recording style survives a reload. The Lua
    // recorder reads the same shape (see ms_core startRecording handler).
    var _REC_OPTS_KEY = "ms.macroRecordOpts";
    var _recOptDefaults = {
        recordDelays:       true,   // emit ms.wait for idle gaps
        pressMode:          "type", // "type" | "press" | "pressRelease"
        recordDrags:        true,   // capture mouse drags as Drag ops
        dragGranularity:    5,      // 1 (coarse) … 10 (near 1:1) path fidelity
        recordMouseButtons: true,   // capture mouse-button clicks
        recordWindowMove:   false,  // capture focused-window moves
        recordWindowResize: false,  // capture focused-window resizes
        waitThreshold:      50      // ms — gaps shorter than this are noise
    };
    var _recOpts = (function() {
        var o = {};
        for (var k in _recOptDefaults) o[k] = _recOptDefaults[k];
        try {
            var saved = JSON.parse(localStorage.getItem(_REC_OPTS_KEY) || "{}");
            for (var k2 in saved) if (k2 in o) o[k2] = saved[k2];
            // The key-down-only "press" mode was removed; fold any stored value
            // into the press+release mode so recording never stays down-only.
            if (o.pressMode === "press") o.pressMode = "pressRelease";
        } catch (e) { /* corrupt/absent — fall back to defaults */ }
        return o;
    })();
    function _saveRecOpts() {
        try { localStorage.setItem(_REC_OPTS_KEY, JSON.stringify(_recOpts)); }
        catch (e) { /* private mode / quota — options just won't persist */ }
    }

    function _setRecordingState(on) {
        _isRecording = on;
        if (on) {
            recordBtn.className = "macro-toolbar-btn recording";
            recordBtn.innerHTML = menuLabel("stop", "Stop");
            recordBtn.title = "Stop recording";
            showTestToast("Recording — perform actions, then click Stop\u2026", null, "record");
        } else {
            recordBtn.className = "macro-toolbar-btn";
            recordBtn.innerHTML = menuLabel("record", "Record");
            recordBtn.title = "Record user actions into tools";
        }
    }

    recordBtn.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
    recordBtn.addEventListener("click", function() {
        if (window.playSlot) playSlot("interact");
        if (!_isRecording) {
            // Start recording — carry the current options through so the Lua
            // recorder captures exactly what the user asked for.
            if (window.shellPost) {
                shellPost("macros", "startRecording", {
                    waitThreshold: _recOpts.waitThreshold,
                    options: _recOpts
                });
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

    /* ── Recording settings menu ─────────────────────────────────
       A small modal in the same visual language as the rebind / warning
       prompts: an accent-topped card over a dimmed backdrop. Built lazily
       on first open, then reused. */
    var _recModal = null;

    function _buildRecModal() {
        var overlayEl = document.createElement("div");
        overlayEl.className = "rec-settings-overlay";
        overlayEl.style.cssText =
            "position:fixed;inset:0;background:rgba(0,0,0,0.6);display:flex;" +
            "align-items:center;justify-content:center;z-index:320;opacity:0;" +
            "pointer-events:none;transition:opacity 0.2s;";

        var card = document.createElement("div");
        card.style.cssText =
            "background:var(--surface);border-top:2px solid var(--accent);" +
            "border-radius:var(--radius);padding:18px 20px;width:340px;" +
            "max-height:82vh;overflow-y:auto;box-shadow:0 16px 48px rgba(0,0,0,0.7)," +
            "0 0 0 1px var(--border);transform:scale(0.96);transition:transform 0.2s;";
        overlayEl.appendChild(card);

        var title = document.createElement("div");
        title.style.cssText = "font-size:14px;font-weight:700;margin-bottom:2px;";
        title.textContent = "Recording Settings";
        card.appendChild(title);

        var sub = document.createElement("div");
        sub.style.cssText = "font-size:11px;color:var(--text2);margin-bottom:14px;line-height:1.5;";
        sub.textContent = "Choose what a recording captures. Applied to the next recording you start.";
        card.appendChild(sub);

        // Row scaffold shared by toggle + segmented rows.
        function row(label, hint, control) {
            var r = document.createElement("div");
            r.style.cssText =
                "display:flex;align-items:center;justify-content:space-between;" +
                "gap:12px;padding:9px 0;border-bottom:1px solid var(--border-dim,var(--border));";
            var lwrap = document.createElement("div");
            lwrap.style.cssText = "min-width:0;flex:1;";
            var l = document.createElement("div");
            l.style.cssText = "font-size:12px;color:var(--text);";
            l.textContent = label;
            lwrap.appendChild(l);
            if (hint) {
                var h = document.createElement("div");
                h.style.cssText = "font-size:10px;color:var(--text3);margin-top:2px;line-height:1.4;";
                h.textContent = hint;
                lwrap.appendChild(h);
            }
            r.appendChild(lwrap);
            r.appendChild(control);
            card.appendChild(r);
            return r;
        }

        function toggle(key) {
            var wrap = document.createElement("label");
            wrap.className = "toggle";
            var input = document.createElement("input");
            input.type = "checkbox";
            input.checked = !!_recOpts[key];
            var track = document.createElement("span"); track.className = "toggle-track";
            var thumb = document.createElement("span"); thumb.className = "toggle-thumb";
            wrap.appendChild(input); wrap.appendChild(track); wrap.appendChild(thumb);
            input.addEventListener("change", function() {
                _recOpts[key] = input.checked;
                _saveRecOpts();
                if (window.playSlot) playSlot("interact");
            });
            return wrap;
        }

        // Integer slider with a live value read-out. Used for drag fidelity:
        // the value is the number of RDP retention steps the Lua recorder uses
        // (higher = more points kept = closer to a 1:1 path). One dragPath step
        // still results regardless, so a high value never floods the canvas.
        function slider(key, min, max) {
            var wrap = document.createElement("div");
            wrap.style.cssText = "display:flex;align-items:center;gap:10px;";
            var input = document.createElement("input");
            input.type = "range";
            input.min = String(min); input.max = String(max); input.step = "1";
            input.value = String(_recOpts[key] != null ? _recOpts[key] : min);
            input.style.cssText = "flex:1;min-width:110px;accent-color:var(--accent);";
            var val = document.createElement("span");
            val.style.cssText = "font-size:12px;color:var(--text2);min-width:20px;text-align:right;font-variant-numeric:tabular-nums;";
            val.textContent = input.value;
            input.addEventListener("input", function() {
                val.textContent = input.value;
            });
            input.addEventListener("change", function() {
                _recOpts[key] = parseInt(input.value, 10);
                _saveRecOpts();
                if (window.playSlot) playSlot("interact");
            });
            wrap.appendChild(input);
            wrap.appendChild(val);
            return wrap;
        }

        function seg(key, opts) {
            var s = document.createElement("div");
            s.className = "seg";
            opts.forEach(function(o) {
                var b = document.createElement("button");
                b.className = "seg-btn" + (_recOpts[key] === o.value ? " active" : "");
                b.textContent = o.label;
                b.title = o.hint || "";
                b.addEventListener("click", function() {
                    _recOpts[key] = o.value;
                    _saveRecOpts();
                    if (window.playSlot) playSlot("interact");
                    Array.prototype.forEach.call(s.children, function(c) {
                        c.classList.remove("active");
                    });
                    b.classList.add("active");
                });
                b.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
                s.appendChild(b);
            });
            return s;
        }

        row("Record delays", "Insert wait modules for idle gaps between actions.", toggle("recordDelays"));
        row("Key presses", "How keystrokes are captured.",
            seg("pressMode", [
                { value: "type",         label: "Type",    hint: "Full press+release keystroke (ms.type)" },
                { value: "pressRelease", label: "Press",   hint: "Separate press and release with real hold timing" }
            ]));
        row("Record mouse buttons", "Capture left/right/middle clicks.", toggle("recordMouseButtons"));
        row("Record mouse drags", "Capture press-move-release as a drag gesture.", toggle("recordDrags"));
        row("Drag fidelity", "How closely a recorded drag follows your real path. Lower is coarser; higher tracks curves near 1:1. The whole gesture stays one module either way.", slider("dragGranularity", 1, 10));
        row("Record window moves", "Capture moving the focused window.", toggle("recordWindowMove"));
        var lastRow =
        row("Record window resizes", "Capture resizing the focused window.", toggle("recordWindowResize"));
        lastRow.style.borderBottom = "none";

        // Buttons
        var btns = document.createElement("div");
        btns.className = "modal-btns";
        btns.style.cssText = "display:flex;gap:8px;margin-top:16px;";
        var resetBtn = document.createElement("button");
        resetBtn.textContent = "Reset";
        resetBtn.style.cssText = "flex:0 0 auto;padding:8px 12px;border-radius:var(--radius-s);" +
            "font-size:13px;font-weight:600;background:var(--surface2);color:var(--text2);";
        var doneBtn = document.createElement("button");
        doneBtn.className = "primary";
        doneBtn.textContent = "Done";
        doneBtn.style.cssText = "flex:1;padding:8px;border-radius:var(--radius-s);" +
            "font-size:13px;font-weight:600;background:var(--accent);color:var(--bg);";
        btns.appendChild(resetBtn);
        btns.appendChild(doneBtn);
        card.appendChild(btns);

        function close() {
            overlayEl.style.opacity = "0";
            overlayEl.style.pointerEvents = "none";
            card.style.transform = "scale(0.96)";
        }
        resetBtn.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
        resetBtn.addEventListener("click", function() {
            for (var k in _recOptDefaults) _recOpts[k] = _recOptDefaults[k];
            _saveRecOpts();
            if (window.playSlot) playSlot("back");
            // Rebuild reflects the reset values cleanly.
            _recModal = null;
            card.remove(); overlayEl.remove();
            _openRecModal();
        });
        doneBtn.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
        doneBtn.addEventListener("click", function() { if (window.playSlot) playSlot("interact"); close(); });
        overlayEl.addEventListener("click", function(e) {
            if (e.target === overlayEl) { if (window.playSlot) playSlot("back"); close(); }
        });

        document.body.appendChild(overlayEl);
        _recModal = { overlay: overlayEl, card: card };
        return _recModal;
    }

    function _openRecModal() {
        var m = _recModal || _buildRecModal();
        // Force reflow so the opening transition runs from the closed state.
        m.overlay.getBoundingClientRect();
        m.overlay.style.opacity = "1";
        m.overlay.style.pointerEvents = "all";
        m.card.style.transform = "scale(1)";
    }

    recSettingsBtn.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
    recSettingsBtn.addEventListener("click", function() {
        // Let the click bubble so the overflow menu closes behind the modal.
        if (window.playSlot) playSlot("interact");
        _openRecModal();
    });

    delMacroBtn.addEventListener("mouseenter", function() { if (window.playSlot) playSlot("hover"); });
    delMacroBtn.addEventListener("click", function() {
        if (_currentMacroId) {
            if (window.playSlot) playSlot("back");
            deleteMacro();
        }
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
        if (action === "packMeta" && body) {
            setMeta(body);
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
        setMeta: setMeta,
        refreshMeta: refreshMeta,
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
    refreshMeta();

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
