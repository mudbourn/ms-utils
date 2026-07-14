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
            }
        ];

        var MOD_LIST = ["ctrl", "alt", "shift", "cmd"];

        /* ── State ─────────────────────────────────────────────────── */
        var _selectedId  = null;
        var _paramValues = {};   // { paramName: value }
        var _modState    = {};   // { ctrl: false, alt: false, ... }
        var _keyCapture  = null; // param name currently capturing
        var _toastTimer  = null;

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
        searchInput.placeholder = "Search ms.* functions\u2026";
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
        detailPane.innerHTML = '<div class="fn-detail-empty"><svg class="icon" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M16.6582 9.28638C18.098 10.1862 18.8178 10.6361 19.0647 11.2122C19.2803 11.7152 19.2803 12.2847 19.0647 12.7878C18.8178 13.3638 18.098 13.8137 16.6582 14.7136L9.896 18.94C8.29805 19.9387 7.49907 20.4381 6.83973 20.385C6.26501 20.3388 5.73818 20.0469 5.3944 19.584C5 19.053 5 18.1108 5 16.2264V7.77357C5 5.88919 5 4.94701 5.3944 4.41598C5.73818 3.9531 6.26501 3.66111 6.83973 3.6149C7.49907 3.5619 8.29805 4.06126 9.896 5.05998L16.6582 9.28638Z" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/></svg>Select a function from the list</div>';

        root.appendChild(listPane);
        root.appendChild(detailPane);
        slot.appendChild(root);

        // Toast
        var toast = document.createElement("div");
        toast.className = "fn-toast";
        document.body.appendChild(toast);

        /* ── Render Function List ──────────────────────────────────── */
        function renderList(filter) {
            entriesDiv.innerHTML = "";
            var q = (filter || "").toLowerCase();
            var visible = [];
            for (var i = 0; i < REGISTRY.length; i++) {
                var fn = REGISTRY[i];
                if (q && fn.name.toLowerCase().indexOf(q) === -1
                       && fn.desc.toLowerCase().indexOf(q) === -1
                       && fn.category.toLowerCase().indexOf(q) === -1) {
                    continue;
                }
                visible.push(fn);
            }
            for (var j = 0; j < visible.length; j++) {
                (function(fn) {
                    var row = document.createElement("div");
                    row.className = "fn-entry" + (_selectedId === fn.id ? " active" : "");
                    row.setAttribute("data-fn-id", fn.id);

                    var sigSpan = document.createElement("span");
                    sigSpan.className = "fn-entry-sig";
                    sigSpan.textContent = fn.name;
                    row.appendChild(sigSpan);

                    var catSpan = document.createElement("span");
                    catSpan.className = "fn-entry-label";
                    catSpan.textContent = fn.category;
                    row.appendChild(catSpan);

                    row.addEventListener("click", function() {
                        selectFunction(fn.id);
                    });

                    entriesDiv.appendChild(row);
                })(visible[j]);
            }
        }

        /* ── Select Function ───────────────────────────────────────── */
        function selectFunction(id) {
            _selectedId = id;
            _paramValues = {};
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
            html += '<button class="fn-add-btn" id="fn-add-btn">Add Tool</button>';
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
        function renderParamField(p) {
            var html = '<div class="fn-param-group fn-param">';
            html += '<div class="fn-param-label">' + esc(p.label);
            html += ' <span class="fn-param-type">' + esc(p.type) + '</span>';
            if (p.required) html += ' <span style="color:var(--danger)">*</span>';
            html += '</div>';

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
            }

            html += '</div>';
            return html;
        }

        /* ── Wire up input events ──────────────────────────────────── */
        function wireParamInputs(fn) {
            // Text and number inputs
            var inputs = detailPane.querySelectorAll("input[data-param]");
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
                if (p.type === "mods") {
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

        /* ── External API: allow ms.shell.eval to call in ──────────── */
        window.fnPicker = {
            select: selectFunction,
            registry: REGISTRY,
            showToast: showToast,
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
        "if":"branch","for":"loop","while":"repeat","else":"branch"
    };

    function iconFor(action) { return ACTION_ICON[action] || "macros"; }

    /* ── Param summary ───────────────────────────────────────────── */
    function paramSummary(action, params) {
        if (!params) return "";
        var keys = Object.keys(params);
        if (keys.length === 0) return "";
        if (action === "if" || action === "while") return params.condition || "";
        if (action === "for") return (params.var||"i") + " = " + (params.from||1) + " → " + (params.to||1);
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
        var needed = ["drag","close","chevdown","macros"];
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

    ToolCanvas.prototype.addTool = function(def, afterId) {
        var step = deepClone(def);
        step._sid = nextToolId();
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
        d.innerHTML = '<span class="tool-canvas-empty-icon"><svg class="icon" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M16.6582 9.28638C18.098 10.1862 18.8178 10.6361 19.0647 11.2122C19.2803 11.7152 19.2803 12.2847 19.0647 12.7878C18.8178 13.3638 18.098 13.8137 16.6582 14.7136L9.896 18.94C8.29805 19.9387 7.49907 20.4381 6.83973 20.385C6.26501 20.3388 5.73818 20.0469 5.3944 19.584C5 19.053 5 18.1108 5 16.2264V7.77357C5 5.88919 5 4.94701 5.3944 4.41598C5.73818 3.9531 6.26501 3.66111 6.83973 3.6149C7.49907 3.5619 8.29805 4.06126 9.896 5.05998L16.6582 9.28638Z" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/></svg></span>No tools yet<br><span style="font-size:10px">Click <b>+ Add Tool</b> to begin</span>';
        this._root.appendChild(d);
    };

    ToolCanvas.prototype._isContainer = function(s) {
        return s.action==="if" || s.action==="for" || s.action==="while";
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

        var acts = document.createElement("div");
        acts.className = "tool-actions";
        var db = document.createElement("div");
        db.className = "tool-action-btn del";
        db.innerHTML = _svgCache["close"] || '<svg class="icon" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><g id="Edit / Close_Circle"><path id="Vector" d="M9 9L11.9999 11.9999M11.9999 11.9999L14.9999 14.9999M11.9999 11.9999L9 14.9999M11.9999 11.9999L14.9999 9M12 21C7.02944 21 3 16.9706 3 12C3 7.02944 7.02944 3 12 3C16.9706 3 21 7.02944 21 12C21 16.9706 16.9706 21 12 21Z" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></g></svg>';
        db.addEventListener("click", function(e) { e.stopPropagation(); self.removeTool(step._sid); });
        acts.appendChild(db);
        el.appendChild(acts);

        el.addEventListener("click", function(e) {
            if (e.target.closest(".tool-action-btn") || e.target.closest(".tool-drag-handle")) return;
            self._selectTool(step._sid);
        });

        this._wireDrag(el, step);
        return el;
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

        var acts = document.createElement("div");
        acts.className = "tool-actions";
        var db = document.createElement("div");
        db.className = "tool-action-btn del";
        db.innerHTML = _svgCache["close"] || '<svg class="icon" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><g id="Edit / Close_Circle"><path id="Vector" d="M9 9L11.9999 11.9999M11.9999 11.9999L14.9999 14.9999M11.9999 11.9999L9 14.9999M11.9999 11.9999L14.9999 9M12 21C7.02944 21 3 16.9706 3 12C3 7.02944 7.02944 3 12 3C16.9706 3 21 7.02944 21 12C21 16.9706 16.9706 21 12 21Z" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></g></svg>';
        db.addEventListener("click", function(e) { e.stopPropagation(); self.removeTool(step._sid); });
        acts.appendChild(db);
        header.appendChild(acts);

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
    ToolCanvas.prototype.copySelected = function() {
        var step = this.getSelectedTool();
        if (!step) return false;
        var clone = deepClone(step);
        this._strip([clone]);
        try { navigator.clipboard.writeText(JSON.stringify(clone)); } catch(e) {}
        this._clipboard = clone;
        return true;
    };
    ToolCanvas.prototype.cutSelected = function() {
        var sid = this._selId;
        if (!sid || !this._map[sid]) return false;
        this.copySelected();
        this.removeTool(sid);
        return true;
    };
    ToolCanvas.prototype.pasteAfter = function() {
        if (!this._clipboard) return false;
        var clone = deepClone(this._clipboard);
        clone._sid = nextToolId();
        this._map[clone._sid] = clone;
        if (clone.then) this._assignIds(clone.then);
        if (clone.else) this._assignIds(clone.else);
        if (clone.body) this._assignIds(clone.body);
        var afterId = this._selId;
        if (afterId) {
            var idx = this._findIdx(this._tools, afterId);
            if (idx !== -1) this._tools.splice(idx + 1, 0, clone);
            else this._tools.push(clone);
        } else {
            this._tools.push(clone);
        }
        this._selId = clone._sid;
        this._render();
        this._fireChange();
        return true;
    };

    /* ── Macro Management State ──────────────────────────────────── */
    var _currentMacroId = null;
    var _currentMacroDef = null;
    var _macroDirty = false;
    var _canvas = null;

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

    var macroSelect = document.createElement("select");
    macroSelect.className = "macro-select";
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

    // Test Run button
    var testBtn = document.createElement("button");
    testBtn.className = "macro-toolbar-btn";
    testBtn.textContent = "\u25b6 Test";
    testBtn.title = "Test Run current macro";
    toolbar.appendChild(testBtn);

    // Record button
    var recordBtn = document.createElement("button");
    recordBtn.className = "macro-toolbar-btn";
    recordBtn.innerHTML = '<span class="macro-rec-dot" style="display:none"></span> Record';
    recordBtn.title = "Record user actions into tools";
    toolbar.appendChild(recordBtn);

    // Delete button
    var delMacroBtn = document.createElement("button");
    delMacroBtn.className = "macro-toolbar-btn danger";
    delMacroBtn.innerHTML = '<svg class="icon" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M10 12L14 16M14 12L10 16M4 6H20M16 6L15.7294 5.18807C15.4671 4.40125 15.3359 4.00784 15.0927 3.71698C14.8779 3.46013 14.6021 3.26132 14.2905 3.13878C13.9376 3 13.523 3 12.6936 3H11.3064C10.477 3 10.0624 3 9.70951 3.13878C9.39792 3.26132 9.12208 3.46013 8.90729 3.71698C8.66405 4.00784 8.53292 4.40125 8.27064 5.18807L8 6M18 6V16.2C18 17.8802 18 18.7202 17.673 19.362C17.3854 19.9265 16.9265 20.3854 16.362 20.673C15.7202 21 14.8802 21 13.2 21H10.8C9.11984 21 8.27976 21 7.63803 20.673C7.07354 20.3854 6.6146 19.9265 6.32698 19.362C6 18.7202 6 17.8802 6 16.2V6" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>';
    delMacroBtn.title = "Delete macro";
    toolbar.appendChild(delMacroBtn);

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
    addToolBtn.innerHTML = (_svgCache["add"] || "+") + " Add Tool";
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
    overlayTitle.textContent = "Add Tool";
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

    // Assemble layout
    layout.appendChild(toolbar);
    layout.appendChild(mainArea);
    slot.appendChild(layout);

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
        if (svg) addToolBtn.innerHTML = svg + " Add Tool";
    });
    _fetchSVG("close").then(function(svg) {
        if (svg) overlayClose.innerHTML = svg;
    });

    /* ── Fn-picker overlay toggle ────────────────────────────────── */
    function openFnOverlay() {
        overlay.classList.add("open");
    }
    function closeFnOverlay() {
        overlay.classList.remove("open");
    }
    addToolBtn.addEventListener("click", function() {
        openFnOverlay();
    });

    /* ── Macro select / management ───────────────────────────────── */
    function refreshMacroList() {
        // Ask Lua for the list of macros
        if (window.shellPost) {
            shellPost("macros", "listMacros", {});
        }
    }

    function setMacroList(ids) {
        macroSelect.innerHTML = "";
        var none = document.createElement("option");
        none.value = "";
        none.textContent = "— Select —";
        macroSelect.appendChild(none);

        for (var i = 0; i < ids.length; i++) {
            var opt = document.createElement("option");
            opt.value = ids[i];
            opt.textContent = ids[i];
            macroSelect.appendChild(opt);
        }

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
    }

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
    });

    saveBtn.addEventListener("click", function() { saveMacro(); });

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
        testBtn.textContent = "\u25b6 Test";
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
        testBtn.textContent = "Running\u2026";
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
        var dot = recordBtn.querySelector(".macro-rec-dot");
        if (on) {
            recordBtn.className = "macro-toolbar-btn recording";
            recordBtn.innerHTML = '<span class="macro-rec-dot"></span> Stop';
            recordBtn.title = "Stop recording";
            showTestToast("\u23fa Recording — perform actions, then click Stop\u2026");
        } else {
            recordBtn.className = "macro-toolbar-btn";
            recordBtn.innerHTML = '<span class="macro-rec-dot" style="display:none"></span> Record';
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
        addTool: function(def) { _canvas.addTool(def); closeFnOverlay(); },
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
