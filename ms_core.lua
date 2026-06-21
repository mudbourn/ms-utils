-- Core System ---- PLEASE EDIT CAREFULLY --
    -- Hammerspoon mudscript Utility Library --
        -- 0. Pre-Load  --
            -- hs.reload() re-runs this whole file but never tears down old native
            -- objects (watchers, timers, hotkeys). Without this, every reload
            -- leaves the previous ms._appWatcher running forever, stacked on top
            -- of every watcher from every reload before it. Stop the prior
            -- generation before this load creates a new one.
            -- ── Watcher teardown (belt-and-suspenders; primary is in init.lua stub) ──────
            if _G.__ms_appWatcher then pcall(function() _G.__ms_appWatcher:stop() end) end

            -- ── Guardian tamper check moved to Spoons/MsGuardian.spoon/ ────────────────
            -- MsGuardian.spoon hashes this file (ms_core.lua) before dofile()-ing it.
            -- The check no longer lives here so it cannot be excised by editing this file.


            -- One-time migration: move settings/hash files from root into data/ ──────
            -- Safe to run on every reload; skips files that already exist at the new path.
            do
                local _h = os.getenv("HOME") .. "/.hammerspoon"
                os.execute("mkdir -p '" .. _h .. "/data'")
                local function _mvToData(name)
                    local src = _h .. "/" .. name
                    local dst = _h .. "/data/" .. name
                    if hs.fs.attributes(dst) then return end
                    if not hs.fs.attributes(src) then return end
                    local f = io.open(src, "rb"); if not f then return end
                    local c = f:read("*all"); f:close()
                    local g = io.open(dst, "wb"); if not g then return end
                    g:write(c); g:close(); os.remove(src)
                end
                _mvToData("ms_settings.json")
                _mvToData("ms_settings_default.json")
                _mvToData(".ms_trusted_hash")
            end

            -- Font installation ──────────────────────────────────────────────────────
            -- Copies bundled fonts from ui/fonts/ into ~/Library/Fonts/ so they are
            -- available as system fonts for hs.canvas (canvas cannot load .ttf files
            -- directly — only installed font names work).
            -- Runs on every reload but is a no-op once fonts are present.
            -- If any font is newly installed, reloads immediately so the macOS font
            -- daemon registers them before any canvas toast renders.
            do
                local _h       = os.getenv("HOME") .. "/.hammerspoon"
                local _srcDir  = _h .. "/ui/fonts/"
                local _dstDir  = os.getenv("HOME") .. "/Library/Fonts/"
                local _installed = false
                hs.fs.mkdir(_dstDir)
                if hs.fs.attributes(_srcDir) then
                    for _file in hs.fs.dir(_srcDir) do
                        if _file ~= "." and _file ~= ".." then
                            local _ext = _file:match("%.([^%.]+)$")
                            if _ext == "ttf" or _ext == "otf" or _ext == "woff" or _ext == "woff2" then
                                local _dst = _dstDir .. _file
                                if not hs.fs.attributes(_dst) then
                                    local _f = io.open(_srcDir .. _file, "rb")
                                    if _f then
                                        local _c = _f:read("*all"); _f:close()
                                        local _g = io.open(_dst, "wb")
                                        if _g then _g:write(_c); _g:close(); _installed = true end
                                    end
                                end
                            end
                        end
                    end
                end
                if _installed then
                    -- Reload so fonts are registered with the font daemon before
                    -- canvas renders anything. This extra load only happens once.
                    hs.reload(); return
                end
            end
        -- END --

        -- 1. Prefix Variables & State Tracking --
            ms = {}
            ms.vars = {}
            ms.keytrack = {}
            ms._keyBindings = {}
            ms.bindConfig = {}
            ms.bindHandles = {}
            ms._activeSub = nil
            ms.modConfig             = {}
            ms.subBinds              = {}
            ms.independentBindsEnabled = false
            ms.trackpadMode          = false
            ms.trackpadHoldKeys      = { left = "n", right = "j" }
            ms.socdMode              = "lastWins"
            ms.socdEnabled           = false
            ms.trackpadBindOverrides = {
                superJump     = {type="key", mods={}, key="k"},
            }
            ms.binds                 = {}
            ms.running   = {}  -- { [groupId] = timerHandle } — populated on fire, cleared on expiry
            ms.cooldowns = {}  -- user cooldown overrides: { [id] = N ms }
            ms._robloxActive = false  -- kept current by the app watcher; no OS call needed on keypress
            ms._menuOpen     = false  -- persistent-session flag: set on open, cleared by Alt+P close only
            ms._menuVisible  = false  -- true only while popupMenu is blocking; cleared on every return
            ms._menuFnFired  = false  -- true when an item fn ran during the current popupMenu session
            ms._menuHoverWatcher = nil   -- AX accessibility observer for mouse-hover sounds
            ms._playSlotTimes    = {}    -- per-slot last-play timestamps for duplicate suppression
            ms._slotHandles      = {}    -- per-slot last sound handle; stopped before each new play
            ms._currentFlags     = {}    -- modifier flags at last keyDown dispatch
            ms._pendingReopenToSound = false  -- set by Import Sound Files to reopen directly at the sound submenu
            ms._inputOpen    = false  -- true while a Hammerspoon dialog has focus (suppress state toasts)
            ms._macroHeldKeys    = {}  -- keyCode → {mods, hidinject}  keys held by macro presses
            ms._macroHeldButtons = {}  -- btn-number → {upT, pos, app}  buttons held by macro presses
            ms._coroContext      = {}  -- coroutine → cancel-context
            ms._activeContexts   = {}  -- cancel-context → true
            ms.registry              = { _defs = {}, _defList = {} }
            ms.bind                  = { _wires = {}, _autoCount = 0 }
            roblox = hs.application.get("Roblox")
            notice = 0
            loadfinish = 0
            REF_W = 1680
            REF_H = 1044
            REF_SENS = 1.5
            -- ms.Mouse named constants — operations, buttons, references.
            -- Plain string globals; accessible from ms_macros.lua via the sandbox fallback.
            -- Typos error immediately at ms.Mouse call time rather than silently misfiring.
            Move        = "Move";    Click       = "Click";    DoubleClick = "DoubleClick"
            TripleClick = "TripleClick";   Drag   = "Drag";    Press       = "Press";    Release     = "Release"
            Left        = "Left";    Right       = "Right";   Center      = "Center"
            Button4     = "Button4"; Button5     = "Button5"
            Unscaled    = true   -- pass between reference and x1 in ms.Mouse for raw pixel window offsets
            Absolute     = "Absolute";  Mouse        = "Mouse"
            WindowTL     = "WindowTL";  WindowTR     = "WindowTR"
            WindowBL     = "WindowBL";  WindowBR     = "WindowBR";  WindowCenter = "WindowCenter"
            ScreenTL     = "ScreenTL";  ScreenTR     = "ScreenTR"
            ScreenBL     = "ScreenBL";  ScreenBR     = "ScreenBR";  ScreenCenter = "ScreenCenter"
            BindValidity = 1
            SoundLib = os.getenv("HOME") .. "/.hammerspoon/sounds/"
            ms.sounds          = {}     -- name → path; populated by _discoverSounds
            ms.importedSounds  = {}     -- name → filename; persisted in settings — source of truth for the menu
            ms.soundEnabled    = true   -- master on/off
            ms.soundVolume     = 100    -- 0–100
            ms.soundAssign     = {}     -- per-slot overrides: { slotId = soundName }
            ms._docsURL           = "https://docs-ms.mudbourn.info"  -- opened by Settings › Documentation
            ms._updateManifestURL = "https://raw.githubusercontent.com/mudbourn/ms-utils/main/MANIFEST.json"

            -- RSA-2048 public key used to verify MANIFEST.json signatures.
            -- The matching private key lives in GitHub Secrets (MS_SIGNING_KEY) and
            -- is never stored in this repository.  GitHub Actions signs every
            -- MANIFEST.json automatically whenever ms_core.lua is pushed to main.
            -- Replace this placeholder after running the one-time key generation:
            --   openssl genrsa -out private.pem 2048
            --   openssl rsa -in private.pem -pubout -out public.pem
            --   → paste public.pem content here, add private.pem to GitHub Secrets
            ms._updatePublicKey = [[
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA3pyxWISHUScKsmK0fyqA
QWUU0nzYEVpRYD+kRkZsL5AGqpjfNqfOky5bacE1jPXgu9LGz+b1pq1tuyZotvK/
FrMeQDCmGWiu5RXAqsyg0iN1c1CHSvWAT40xi6g54u9ot9LMfzmBETlwWd4QoXOA
OnT3KW0aia1EoyUjjNIRk6iv6pxi+BjHnGKoID6pAl9de+WASt/DETgCuKhQ7o/Y
iGn43A9ZutKUfkV+Muu1RcTy62zbXcQrzK3cyLl0M7gfTm0YWPzaf+d3ATNnq/9j
/952QfmXjVSGhU3EBxlEM6NWstNSNuaTWSMCcbcH+va/AMOHK1rRKQ3IOdzjYcQm
YQIDAQAB
-----END PUBLIC KEY-----
]]

            -- User Settings & Menu API State ─────────────────────────────────────
            ms.settings          = {}  -- user settings API namespace
            ms.menu              = {}  -- custom section API namespace (ms.menu.define)
            ms._menubar          = nil  -- hs.menubar instance (menu-bar icon); set in Section 7
            ms.features          = {}  -- feature visibility API namespace
            ms._userSettingDefs  = {}  -- ordered list of all setting/item definitions
            ms._userSettingIndex = {}  -- key → def, for O(1) lookup
            ms._userSettingVals  = {}  -- key → current live value
            ms._userMenuDefs     = {}  -- ordered list of ms.menu.define() entries
            ms._hiddenFeatures   = {}  -- set: name → true (from ms.features.hide())
            -- Theme defaults — matches the shipped data/ms_theme.json baseline.
            -- ms.loadTheme() overrides these with the user's file at startup.
            ms._themeDefaults = {
                bg       = "#060402",
                surface  = "#100806",
                surface2 = "#1c100c",
                hover    = "#301610",
                accent   = "#c41a1a",
                accentHi = "#e52424",
                success  = "#4a7820",
                dangerBg = "#1e0608",
                danger   = "#d42020",
                warning  = "#c47820",
                text     = "#f0ddb0",
                radius   = 3,
                font     = "Almendra",
                uifc     = { settings = "", guardian = "" },
            }
            ms._theme = {}
            for k, v in pairs(ms._themeDefaults) do ms._theme[k] = v end
            ms._themeLoaded = false  -- set true by ms.loadTheme() when a file loads successfully

            require("hs.eventtap")
            require("hs.mouse")
            require("hs.uielement")
            require("hs.timer")
            require("hs.hotkey")
            require("hs.json")
            require("hs.keycodes")
            require("hs.canvas")
            require("hs.window")
            require("hs.screen")
            require("hs.menubar")
            require("hs.application")

            -- ── Developer Tools — ms.dev ───────────────────────────────────────────────────
            ms.dev = {
                _consolePanel    = nil,
                _watcherPanel    = nil,
                _keysPanel       = nil,
                _consolePanelPos = nil,
                _watcherPanelPos = nil,
                _keysPanelPos    = nil,
                _activeKeys      = {},
            }
            local _devLogPath = os.getenv("HOME") .. "/Documents/ms_dev.log"
            local _devBusy          = false
            local _devKeyNoticeSent = false  -- true after first key notice; reset on any non-key event

            local function _devWrite(entry)
                if _devBusy then return end
                _devBusy = true
                entry.ts = os.date("%H:%M:%S")
                pcall(function()
                    local f = io.open(_devLogPath, "a")
                    if f then f:write(hs.json.encode(entry) .. "\n"); f:close() end
                end)
                local ok, json = pcall(hs.json.encode, entry)
                if ok then
                    local t = entry.type
                    -- Key/mouse events go to the Key Monitor only.
                    -- The console gets one dim notice per burst of key activity;
                    -- the notice resets whenever any non-key event fires so the
                    -- next burst of keys shows a fresh line.
                    if t == "key" or t == "mouse" then
                        if ms.dev._consolePanel and not _devKeyNoticeSent then
                            _devKeyNoticeSent = true
                            local notice = { ts = entry.ts, type = "print",
                                             msg = "\xe2\x8c\xa8  input activity \xe2\x80\x94 see Input Monitor" }
                            local nok, njson = pcall(hs.json.encode, notice)
                            if nok then
                                pcall(function()
                                    ms.dev._consolePanel:evaluateJavaScript(
                                        "appendEntry(" .. njson .. ")")
                                end)
                            end
                        end
                    else
                        -- Only a macro (or REPL result) resets the key-notice gate.
                        -- Plain print/error output does not — keys and macros strictly
                        -- take turns: one key notice per macro execution, no more.
                        if t == "macro" or t == "result" or t == "input" then
                            _devKeyNoticeSent = false
                        end
                        if ms.dev._consolePanel then
                            pcall(function()
                                ms.dev._consolePanel:evaluateJavaScript("appendEntry(" .. json .. ")")
                            end)
                        end
                    end
                    if ms.dev._watcherPanel and (t=="macro" or t=="print" or t=="error") then
                        pcall(function()
                            ms.dev._watcherPanel:evaluateJavaScript("appendEntry(" .. json .. ")")
                        end)
                    end
                    if ms.dev._keysPanel
                        and (t=="key" or t=="mouse" or t=="scroll" or t=="mousemove") then
                        pcall(function()
                            ms.dev._keysPanel:evaluateJavaScript("appendEntry(" .. json .. ")")
                        end)
                    end
                end
                _devBusy = false
            end

            local _origPrint = print
            _G.print = function(...)
                _origPrint(...)
                local parts = {}
                for i = 1, select('#', ...) do parts[i] = tostring(select(i, ...)) end
                _devWrite({ type = "print", msg = table.concat(parts, "\t") })
            end

            ms.dev._onMacroFire = function(id, label, parentId, parentLabel, trigger)
                _devWrite({
                    type        = "macro",
                    id          = id,
                    label       = label or id,
                    parentLabel = parentLabel,
                    trigger     = trigger,
                })
            end

            ms.dev._onKeyEvent = function(keyCode, keyName, isDown)
                _devWrite({ type = "key", key = keyName or ("code:" .. tostring(keyCode)), down = isDown })
                if isDown then ms.dev._activeKeys[keyCode] = keyName or tostring(keyCode)
                else            ms.dev._activeKeys[keyCode] = nil end
                if ms.dev._keysPanel then
                    local active = {}
                    for _, name in pairs(ms.dev._activeKeys) do table.insert(active, name) end
                    local aok, aj = pcall(hs.json.encode, active)
                    if aok then
                        pcall(function()
                            ms.dev._keysPanel:evaluateJavaScript("updateActiveKeys(" .. aj .. ")")
                        end)
                    end
                end
            end

            ms.dev._onMouseEvent = function(button, isDown, x, y)
                _devWrite({ type = "mouse", button = button, down = isDown, x = x, y = y })
            end

            hs.timer.doAfter(0.3, function()
                local roblox = hs.application.get("Roblox")
                if roblox then
                    -- Seed _robloxActive now so the Hammerspoon step of the bounce
                    -- correctly triggers ms._inputOpen via the app watcher.
                    -- Without this the watcher sees _robloxActive=false and skips
                    -- setting _inputOpen, causing a spurious ENABLED toast on return.
                    ms._robloxActive = true

                    -- Bounce through Hammerspoon so macOS registers a genuine fresh
                    -- Roblox activation. A direct roblox:activate() is a no-op when
                    -- Roblox is already frontmost (common after a reload from the
                    -- Hammerspoon console) and never fires the app watcher, leaving
                    -- ms._inputOpen stuck true for the rest of the session.
                    local hs_app = hs.application.get("Hammerspoon")
                    if hs_app then hs_app:activate() end

                    hs.timer.doAfter(0.25, function()
                        -- Re-fetch the app handle; the captured reference can become
                        -- stale between the outer and inner timer callbacks.
                        local app = hs.application.get("Roblox") or roblox
                        local ok, win = pcall(function() return app:mainWindow() end)
                        if ok and win then pcall(function() win:focus() end) end
                        pcall(function() app:activate() end)
                    end)
                end
            end)
        -- END --

        -- 2. Conditions, States, and UI Elements--
            ms.app = function() return hs.application.frontmostApplication():name() end

            -- Alerts --
                ms.alert = (function()
                    local queue = {}              -- active toast entries
                    local maxAlerts = 4
                    local bottomY   = 150         -- px above the bottom of the usable area
                    local animDuration = 0.25
                    local animSteps    = 20

                    -- Recalculated on every render so display changes and
                    -- secondary-monitor setups always position correctly.
                    local function screenBounds()
                        local f = hs.screen.mainScreen():frame()
                        -- f.y is the top of the usable area in absolute coords.
                        -- f.y + f.h is the absolute bottom (above the dock).
                        return f.x, f.y, f.w, f.y + f.h
                    end

                    local function makeCanvas(msg, x, y, w, alpha)
                        local padding = 16
                        local lineH   = 20
                        local closeW  = 22  -- right-side area for the ✕ dismiss button

                        local lines = {}
                        for line in (msg .. "\n"):gmatch("([^\n]*)\n") do
                            table.insert(lines, line)
                        end

                        local longestLine = 0
                        for _, line in ipairs(lines) do
                            if #line > longestLine then longestLine = #line end
                        end

                        local charW  = 8
                        local cw     = math.max(200, math.min(600, longestLine * charW + padding * 2)) + closeW
                        local textH  = #lines * lineH
                        local ch     = textH + padding * 2
                        local cx     = x + (w - cw) / 2  -- centred within the screen

                        -- Read theme values at render time so every toast reflects the
                        -- current ms_theme.json without needing a reload.
                        local theme = ms._theme or {}

                        local function hexToColor(hex, default)
                            if type(hex) ~= "string" then return default end
                            local h = hex:match("^#?([0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F])")
                            if not h then return default end
                            return {
                                red   = tonumber(h:sub(1,2), 16) / 255,
                                green = tonumber(h:sub(3,4), 16) / 255,
                                blue  = tonumber(h:sub(5,6), 16) / 255,
                                alpha = 1,
                            }
                        end

                        local bgColor     = hexToColor(theme.surface2, { red=0.11, green=0.063, blue=0.047, alpha=1 })
                        local txtColor    = hexToColor(theme.text,     { red=0.94, green=0.87, blue=0.69, alpha=1 })
                        local accentColor = hexToColor(theme.accent,   { red=0.77, green=0.10, blue=0.10, alpha=1 })
                        local radius      = type(theme.radius) == "number" and math.max(0, theme.radius) or 3
                        -- Canvas uses system font names. Bundled fonts are installed into
                        -- ~/Library/Fonts/ at startup, so "Almendra" works directly.
                        -- File paths are still skipped as a safety net.
                        local font = "Helvetica"
                        if type(theme.font) == "string" and #theme.font > 0
                            and not theme.font:find("[/\\]") then
                            font = theme.font
                        end

                        -- Semi-transparent background so the game shows through.
                        bgColor.alpha = 0.88

                        local c = hs.canvas.new({ x = cx, y = y, w = cw, h = ch })
                        c:level(hs.canvas.windowLevels.popUpMenu or hs.canvas.windowLevels.status or 25)
                        c:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
                        c:alpha(alpha or 0)
                        c:appendElements(
                            -- 1: Background — also tracks mouse enter/exit for hover-to-hold.
                            {
                                type                 = "rectangle",
                                action               = "strokeAndFill",
                                fillColor            = bgColor,
                                strokeColor          = accentColor,
                                strokeWidth          = 1,
                                roundedRectRadii     = { xRadius = radius, yRadius = radius },
                                trackMouseEnterExit  = true,
                            },
                            -- 2: Message text (narrowed to leave room for the ✕ button).
                            {
                                type          = "text",
                                text          = msg,
                                textFont      = font,
                                textSize      = 13,
                                textColor     = txtColor,
                                textAlignment = "center",
                                frame         = { x = 0, y = padding + 4, w = cw, h = textH }
                            },
                            -- 3: Dismiss button (✕) — hidden until hover, click to close.
                            {
                                type          = "text",
                                text          = "\xe2\x9c\x95",
                                textFont      = "Helvetica",
                                textSize      = 10,
                                textColor     = { red = txtColor.red, green = txtColor.green, blue = txtColor.blue, alpha = 0 },
                                textAlignment = "center",
                                frame         = { x = cw - closeW, y = 5, w = closeW - 4, h = 14 },
                                trackMouseDown = true,
                            }
                        )
                        c:show()

                        local xShowColor = { red = txtColor.red, green = txtColor.green, blue = txtColor.blue, alpha = 0.45 }
                        local xHideColor = { red = txtColor.red, green = txtColor.green, blue = txtColor.blue, alpha = 0 }
                        local function showX() pcall(function() c:elementAttribute(3, "textColor", xShowColor) end) end
                        local function hideX() pcall(function() c:elementAttribute(3, "textColor", xHideColor) end) end

                        return c, ch, showX, hideX
                    end

                    local function animateEntry(entry, fromY, toY, fromAlpha, toAlpha, onDone)
                        local step = 0
                        if entry._animTimer then entry._animTimer:stop() end
                        entry._animTimer = hs.timer.doEvery(animDuration / animSteps, function()
                            step = step + 1
                            local t    = step / animSteps
                            local ease = 1 - (1 - t) ^ 3
                            local y     = fromY     + (toY     - fromY)     * ease
                            local alpha = fromAlpha + (toAlpha - fromAlpha) * ease
                            if entry.canvas then
                                local f = entry.canvas:frame()
                                entry.canvas:frame({ x = f.x, y = y, w = f.w, h = f.h })
                                entry.canvas:alpha(alpha)
                            end
                            if step >= animSteps then
                                entry._animTimer:stop()
                                entry._animTimer = nil
                                if onDone then onDone() end
                            end
                        end)
                    end

                    -- Forward-declared so redraw's mouseCallback closure can reference it.
                    local dismissEntry

                    local function redraw(newEntry)
                        local sx, sy, sw, sBottom = screenBounds()

                        -- Ensure every queued entry has a height measurement.
                        for _, entry in ipairs(queue) do
                            if not entry.h then
                                local lines = {}
                                for line in (entry.msg .. "\n"):gmatch("([^\n]*)\n") do
                                    table.insert(lines, line)
                                end
                                entry.h = #lines * 20 + 32
                            end
                        end

                        local currentY = sBottom - bottomY
                        for i = #queue, 1, -1 do
                            local entry   = queue[i]
                            local targetY = currentY - entry.h
                            currentY = targetY - 8

                            if entry == newEntry then
                                if not entry.canvas then
                                    local c, h, showX, hideX = makeCanvas(entry.msg, sx, sBottom - bottomY, sw, 0)
                                    entry.canvas = c
                                    entry.h      = h
                                    entry._showX = showX
                                    entry._hideX = hideX
                                    -- Hover-to-hold and click-to-dismiss callbacks.
                                    c:mouseCallback(function(cvs, msg, id, cx, cy)
                                        if msg == "mouseEnter" then
                                            entry._hovered = true
                                            if entry.timer then entry.timer:stop(); entry.timer = nil end
                                            if entry._showX then entry._showX() end
                                        elseif msg == "mouseExit" and id == 1 then
                                            entry._hovered = false
                                            if entry._hideX then entry._hideX() end
                                            if not entry.timer then
                                                entry.timer = hs.timer.doAfter(2, function()
                                                    dismissEntry(entry)
                                                end)
                                            end
                                        elseif msg == "mouseDown" and id == 3 then
                                            dismissEntry(entry)
                                        end
                                    end)
                                end
                                animateEntry(entry, sBottom - bottomY, targetY, 0, 1, nil)
                            else
                                if entry.canvas then
                                    local f = entry.canvas:frame()
                                    animateEntry(entry, f.y, targetY, 1, 1, nil)
                                end
                            end
                        end
                    end

                    local function fadeOut(entry, onDone)
                        if not entry.canvas then
                            if onDone then onDone() end
                            return
                        end
                        local f = entry.canvas:frame()
                        animateEntry(entry, f.y, f.y, 1, 0, onDone)
                    end

                    -- Removes an entry from the queue and fades it out.
                    dismissEntry = function(entry)
                        if entry.timer then entry.timer:stop(); entry.timer = nil end
                        for i, e in ipairs(queue) do
                            if e == entry then
                                table.remove(queue, i)
                                fadeOut(e, function()
                                    if e.canvas then e.canvas:delete() end
                                end)
                                redraw(nil)
                                break
                            end
                        end
                    end

                    -- dismissAll: instantly clears all active toasts without animation.
                    -- Used by _doNotify to cut off a previous state toast before
                    -- showing the new one.
                    local function dismissAll()
                        for i = #queue, 1, -1 do
                            local e = queue[i]
                            if e.timer      then e.timer:stop();      e.timer      = nil end
                            if e._animTimer then e._animTimer:stop(); e._animTimer = nil end
                            if e.canvas     then pcall(function() e.canvas:delete() end); e.canvas = nil end
                        end
                        queue = {}
                    end

                    -- Return a table callable via __call so ms.alert(...) works and
                    -- ms.alert.dismissAll() is a plain field — Lua functions can't be indexed.
                    return setmetatable({ dismissAll = dismissAll }, {
                        __call = function(_, msg, duration, noDefaultSound)
                            duration = duration or 5

                            -- Play alert sound if loaded, post-startup, and not suppressed.
                            if loadfinish == 1 and not noDefaultSound then
                                ms.playSlot("alert")
                            end

                            if #queue >= maxAlerts then
                                local oldest = queue[1]
                                if oldest._animTimer then oldest._animTimer:stop() end
                                if oldest.timer then oldest.timer:stop() end
                                fadeOut(oldest, function()
                                    if oldest.canvas then oldest.canvas:delete() end
                                end)
                                table.remove(queue, 1)
                            end

                            local entry = { msg = msg, canvas = nil, timer = nil, h = nil }
                            table.insert(queue, entry)
                            redraw(entry)

                            entry.timer = hs.timer.doAfter(duration, function()
                                dismissEntry(entry)
                            end)
                        end,
                    })
                end)()
            -- END Alerts --

            -- Settings Menu --
                local settingsPath    = os.getenv("HOME") .. "/.hammerspoon/ms_settings.txt"
                local jsonPath        = os.getenv("HOME") .. "/.hammerspoon/data/ms_settings.json"
                local defaultPath     = os.getenv("HOME") .. "/.hammerspoon/data/ms_settings_default.json"
                local archivePath     = os.getenv("HOME") .. "/.hammerspoon/backups/"
                local macrosPath      = os.getenv("HOME") .. "/.hammerspoon/ms_macros.lua"
                local profilesPath    = os.getenv("HOME") .. "/.hammerspoon/profiles/"
                local corePath        = os.getenv("HOME") .. "/.hammerspoon/ms_core.lua"
                local trustedHashPath = os.getenv("HOME") .. "/.hammerspoon/data/.ms_trusted_hash"
                local themePath       = os.getenv("HOME") .. "/.hammerspoon/data/ms_theme.json"

                ms.bindConfig = {}
                ms.bindHandles = {}

                ms.parseBind = function(str)
                    local btn = str:match("^mouse:(%d+)$")
                    if btn then return {type="mouse", button=tonumber(btn)} end
                    local mods = {}
                    local parts = {}
                    for part in str:gmatch("[^+]+") do
                        table.insert(parts, part:lower())
                    end
                    local modkeys = {cmd=true, alt=true, ctrl=true, shift=true}
                    local key = nil
                    for _, part in ipairs(parts) do
                        if modkeys[part] then
                            table.insert(mods, part)
                        else
                            key = part
                        end
                    end
                    if key then return {type="key", mods=mods, key=key} end
                    return nil
                end

                -- ── User Settings — validation helpers ──────────────────────────────────────
                local _SETTING_TYPES = {
                    toggle = true, slider    = true, seg       = true,
                    action = true, divider   = true, groupLabel = true,
                    soundSlot = true,  -- user-defined sound event slot
                }
                -- Feature names ms.features.hide() is permitted to suppress.
                -- "sound" and "profiles" are intentionally excluded.
                local _HIDEABLE_FEATURES = {
                    socd             = true,
                    trackpad         = true,
                    independentBinds = true,
                    sensitivity      = true,
                }
                -- Returns the validated (and possibly clamped) value, or nil on failure.
                local function _validateUserValue(def, value)
                    if def.type == "toggle" then
                        if value == true or value == false then return value end
                    elseif def.type == "slider" then
                        local n = tonumber(value)
                        if n then return math.max(def.min or 0, math.min(def.max or 100, n)) end
                    elseif def.type == "seg" then
                        if type(def.options) == "table" then
                            for _, opt in ipairs(def.options) do
                                if opt.value == value then return value end
                            end
                        end
                    end
                    return nil
                end

                -- Applies a decoded settings table to the live runtime state.
                ms._applySettings = function(data)
                    if not data then return end
                    if data.sensitivity ~= nil then
                        local num = tonumber(data.sensitivity)
                        if num and num >= 0.1 and num <= 4 then CUR_CAM_SENS = num end
                    end
                    if data.frameLevel ~= nil then
                        local num = tonumber(data.frameLevel)
                        if num and num >= 1 and num <= 4 then clickLevel = num end
                    end
                    if data.trackpadMode     ~= nil then ms.trackpadMode           = (data.trackpadMode     == true) end
                    if data.socdEnabled      ~= nil then ms.socdEnabled            = (data.socdEnabled      == true) end
                    if data.independentBinds ~= nil then ms.independentBindsEnabled = (data.independentBinds == true) end
                    if data.socdMode then
                        if data.socdMode == "lastWins" or data.socdMode == "neutral" or data.socdMode == "firstWins" then
                            ms.socdMode = data.socdMode
                        end
                    end
                    if data.trackpadHoldKeys and ms.trackpadHoldKeys then
                        if data.trackpadHoldKeys.left  then ms.trackpadHoldKeys.left  = data.trackpadHoldKeys.left  end
                        if data.trackpadHoldKeys.right then ms.trackpadHoldKeys.right = data.trackpadHoldKeys.right end
                    end
                    if data.soundEnabled ~= nil then ms.soundEnabled = (data.soundEnabled == true) end
                    if data.soundVolume  ~= nil then
                        local v = tonumber(data.soundVolume)
                        if v and v >= 0 and v <= 100 then ms.soundVolume = math.floor(v) end
                    end
                    if data.soundAssign      then ms.soundAssign     = data.soundAssign      end
                    if data.importedSounds   then ms.importedSounds  = data.importedSounds   end
                    if data.macros then
                        for id, entry in pairs(data.macros) do
                            if entry.enabled ~= nil then
                                ms.binds[id] = entry.enabled
                            end
                            if entry.bind then
                                local def = ms.registry._defs and ms.registry._defs[id]
                                if def and not def.sub then
                                    ms.bindConfig[id] = entry.bind
                                else
                                    ms.subBinds[id] = entry.bind
                                end
                            end
                            if entry.mod ~= nil then
                                                -- "" = explicitly cleared (no modifier); nil = use declared default.
                                                -- Both are stored as-is so the cleared state persists after reload.
                                                ms.modConfig[id] = entry.mod
                            end
                            if entry.cooldown ~= nil then
                                local n = tonumber(entry.cooldown)
                                if n and n >= 0 then ms.cooldowns[id] = math.floor(n) end
                            end
                        end
                    end
                    -- Apply user-defined settings from the "user" sub-table.
                    -- Runs last so user settings always take final effect.
                    -- Fires onChange callbacks, which sync system bridges (e.g. ms.setClickLevel).
                    if data.user and type(data.user) == "table" then
                        for key, value in pairs(data.user) do
                            local uDef = ms._userSettingIndex[key]
                            if uDef and uDef.type ~= "action" then
                                local validated = _validateUserValue(uDef, value)
                                if validated ~= nil then
                                    ms._userSettingVals[key] = validated
                                    if type(uDef.onChange) == "function" then
                                        pcall(uDef.onChange, validated)
                                    end
                                end
                            end
                        end
                    end
                end

                -- Parses the old flat settings file into a settings table.
                -- Unknown keys are silently skipped; returns (data, skippedKeys).
                ms._convertFlatSettings = function(file)
                    local data    = { macros = {} }
                    local skipped = {}
                    for line in file:lines() do
                        local key, val = line:match("^(.-)=(.+)$")
                        if not key then
                            -- blank or malformed line; skip
                        elseif key == "sensitivity" then
                            local num = tonumber(val)
                            if num and num >= 0.1 and num <= 4 then data.sensitivity = num end
                        elseif key == "clickLevel" or key == "frameLevel" then
                            local num = tonumber(val)
                            if num and num >= 1 and num <= 4 then data.frameLevel = num end
                        elseif key == "binds" then
                            local decoded = hs.json.decode(val)
                            if decoded then
                                for id, enabled in pairs(decoded) do
                                    data.macros[id] = data.macros[id] or {}
                                    data.macros[id].enabled = enabled
                                end
                            end
                        elseif key == "trackpadMode"     then data.trackpadMode     = (val == "true")
                        elseif key == "socdEnabled"      then data.socdEnabled      = (val == "true")
                        elseif key == "independentBinds" then data.independentBinds = (val == "true")
                        elseif key == "socdMode" then
                            if val == "lastWins" or val == "neutral" or val == "firstWins" then
                                data.socdMode = val
                            end
                        elseif key == "trackpadHoldLeft" then
                            data.trackpadHoldKeys = data.trackpadHoldKeys or {}
                            data.trackpadHoldKeys.left = val
                        elseif key == "trackpadHoldRight" then
                            data.trackpadHoldKeys = data.trackpadHoldKeys or {}
                            data.trackpadHoldKeys.right = val
                        elseif key:sub(1, 5) == "bind_" then
                            local id = key:sub(6)
                            local parsed = ms.parseBind(val)
                            if parsed then
                                data.macros[id] = data.macros[id] or {}
                                data.macros[id].bind = parsed
                            end
                        elseif key:sub(1, 4) == "mod_" then
                            local id = key:sub(5)
                            data.macros[id] = data.macros[id] or {}
                            data.macros[id].mod = (val == "") and nil or val
                        elseif key:sub(1, 8) == "subbind_" then
                            local id = key:sub(9)
                            local parsed = ms.parseBind(val)
                            if parsed then
                                data.macros[id] = data.macros[id] or {}
                                data.macros[id].bind = parsed
                            end
                        else
                            table.insert(skipped, key)
                        end
                    end
                    return data, skipped
                end

                ms.saveSettings = function()
                    local data = {
                        sensitivity      = CUR_CAM_SENS,
                        frameLevel       = clickLevel,
                        trackpadMode     = ms.trackpadMode,
                        socdEnabled      = ms.socdEnabled,
                        socdMode         = ms.socdMode or "lastWins",
                        independentBinds = ms.independentBindsEnabled,
                        trackpadHoldKeys = {
                            left  = ms.trackpadHoldKeys and ms.trackpadHoldKeys.left  or "n",
                            right = ms.trackpadHoldKeys and ms.trackpadHoldKeys.right or "j",
                        },
                        soundEnabled     = ms.soundEnabled,
                        soundVolume      = ms.soundVolume,
                        soundAssign      = ms.soundAssign,
                        importedSounds   = ms.importedSounds or {},
                        user             = ms._userSettingVals or {},
                        macros = {},
                    }
                    -- Enabled state per macro
                    for id, enabled in pairs(ms.binds or {}) do
                        data.macros[id] = data.macros[id] or {}
                        data.macros[id].enabled = enabled
                    end
                    -- Root bind overrides (only written when different from code default)
                    for id, cfg in pairs(ms.bindConfig or {}) do
                        local regEntry = ms.registry._defs and ms.registry._defs[id]
                        local def = regEntry and regEntry.default
                        if def then
                            local isDifferent = false
                            if cfg.type ~= def.type then
                                isDifferent = true
                            elseif cfg.type == "mouse" and cfg.button ~= def.button then
                                isDifferent = true
                            elseif cfg.type == "key" then
                                local cfgMods = table.concat(cfg.mods or {}, "+")
                                local defMods = table.concat(def.mods or {}, "+")
                                if cfg.key ~= def.key or cfgMods ~= defMods then isDifferent = true end
                            end
                            if isDifferent then
                                data.macros[id] = data.macros[id] or {}
                                data.macros[id].bind = cfg
                            end
                        end
                    end
                    -- Modifier key overrides
                    for id, key in pairs(ms.modConfig or {}) do
                        data.macros[id] = data.macros[id] or {}
                        data.macros[id].mod = key
                    end
                    -- Sub-item independent binds
                    for id, cfg in pairs(ms.subBinds or {}) do
                        data.macros[id] = data.macros[id] or {}
                        data.macros[id].bind = cfg
                    end
                    -- User cooldown overrides
                    for id, cooldown in pairs(ms.cooldowns or {}) do
                        data.macros[id] = data.macros[id] or {}
                        data.macros[id].cooldown = cooldown
                    end
                    local f = io.open(jsonPath, "w")
                    if f then
                        f:write(hs.json.encode(data, true))
                        f:close()
                    end
                end

                ms.loadSettings = function()
                    -- JSON file takes priority
                    local f = io.open(jsonPath, "r")
                    if f then
                        local content = f:read("*all")
                        f:close()
                        local data = hs.json.decode(content)
                        if data then
                            ms._applySettings(data)
                            return
                        end
                        -- JSON present but unreadable; fall through to flat-file check.
                    end
                    -- Auto-convert from old flat file if JSON is absent
                    local oldF = io.open(settingsPath, "r")
                    if oldF then
                        local data, skipped = ms._convertFlatSettings(oldF)
                        oldF:close()
                        ms._applySettings(data)
                        ms.saveSettings()
                        os.rename(settingsPath, archivePath .. "ms_settings_txt.bak")
                        hs.timer.doAfter(1, function()
                            if #skipped > 0 then
                                ms.alert("Settings converted to JSON.\nSkipped unknown keys: " .. table.concat(skipped, ", "), 8)
                            else
                                ms.alert("Settings converted to JSON format.\nOld file backed up to backups/ms_settings_txt.bak.", 6)
                            end
                        end)
                        return
                    end
                    -- Fall back to shipped default settings file
                    local df = io.open(defaultPath, "r")
                    if df then
                        local content = df:read("*all")
                        df:close()
                        local data = hs.json.decode(content)
                        if data then
                            ms._applySettings(data)
                            return
                        end
                    end
                    -- No settings file found — build default from macro declarations.
                    ms._buildDefaultSettings()
                    local df2 = io.open(defaultPath, "r")
                    if df2 then
                        local content2 = df2:read("*all"); df2:close()
                        local data2 = hs.json.decode(content2)
                        if data2 then ms._applySettings(data2) end
                    end
                end

                -- Archives the current default and saves the current settings in its place.
                ms.saveDefault = function()
                    ms.saveSettings()
                    local sf = io.open(jsonPath, "r")
                    if not sf then ms.alert("Could not read current settings.", 3); return end
                    local content = sf:read("*all")
                    sf:close()
                    -- Archive the existing default if one exists.
                    local existingDf = io.open(defaultPath, "r")
                    if existingDf then
                        local oldContent = existingDf:read("*all")
                        existingDf:close()
                        os.execute("mkdir -p '" .. archivePath .. "'")
                        local timestamp = os.date("%Y-%m-%d_%H%M")
                        local archiveFile = archivePath .. "ms_settings_default_" .. timestamp .. ".json"
                        local af = io.open(archiveFile, "w")
                        if af then af:write(oldContent); af:close() end
                    end
                    -- Write the new default.
                    local df = io.open(defaultPath, "w")
                    if df then
                        df:write(content)
                        df:close()
                        ms.alert("Default settings saved.", 3)
                    end
                end

                -- Applies the saved default settings and rebinds everything.
                -- Returns true on success, false if no default file is found.
                ms.resetToDefault = function()
                    local f = io.open(defaultPath, "r")
                    if not f then
                        ms.alert("No default settings file found.", 3)
                        return false
                    end
                    local content = f:read("*all")
                    f:close()
                    local data = hs.json.decode(content)
                    if not data then
                        ms.alert("Default settings file could not be decoded.", 3)
                        return false
                    end
                    -- Clear all per-macro customisations before applying so the default
                    -- is a full replacement, not a merge on top of the current state.
                    -- Without this, any bind/mod/subbind not present in the default file
                    -- would silently persist because _applySettings only sets what it sees.
                    ms.bindConfig = {}
                    ms.subBinds   = {}
                    ms.modConfig  = {}
                    ms.cooldowns  = {}
                    ms._applySettings(data)
                    -- Also reset user-defined settings to their declared defaults.
                    for key, def in pairs(ms._userSettingIndex) do
                        if def.type ~= "action" and def.default ~= nil then
                            ms._userSettingVals[key] = def.default
                            if type(def.onChange) == "function" then
                                pcall(def.onChange, def.default)
                            end
                        end
                    end
                    ms.saveSettings()
                    ms.bind.rebind()
                    ms.cam.updateAnchor()
                    ms.cam.updateMultiplier()
                    ms.socdApply()
                    return true
                end

                -- Reloads settings from disk and applies them fully.
                -- Single source of truth called by both the menu item and the Alt+] hotkey.
                ms.reloadSettings = function()
                    ms.loadSettings()
                    ms.bind.rebind()
                    ms.cam.updateAnchor()
                    ms.cam.updateMultiplier()
                    ms.socdApply()
                    ms.playSlot("update")
                    ms.alert("Settings reloaded.", 5, true)
                end

                -- ── User Settings & Menu API ─────────────────────────────────────────────────────────────────────
                --
                -- These functions are called from ms_macros.lua (after ms.macroMeta, before
                -- macro functions) to declare custom settings, panel sections, and to hide
                -- unused built-in features.
                --
                -- Callbacks (onChange, onAction) defined in ms_macros.lua run inside the
                -- macro sandbox — they have access to ms.* functions and safe Lua builtins,
                -- but cannot touch hs.*, io.*, os.*, or any filesystem / shell API.
                --
                -- Quick reference:
                --
                --   ms.settings.define({ key="k", type="toggle", default=false,
                --       label="My Toggle", onChange=function(v) end })
                --
                --   ms.settings.define({ key="k", type="slider", min=0, max=100,
                --       step=1, unit="ms", default=50, label="My Slider",
                --       onChange=function(v) end })
                --
                --   ms.settings.define({ key="k", type="seg",
                --       options={{label="A",value="a"},{label="B",value="b"}},
                --       default="a", label="My Seg", onChange=function(v) end })
                --
                --   ms.settings.define({ key="k", type="action",
                --       label="Row label", btnLabel="Run", danger=false,
                --       onAction=function() end })
                --
                --   ms.settings.define({ type="divider" })
                --   ms.settings.define({ type="groupLabel", label="My Group" })
                --
                --   ms.settings.get("k")          -- read current value
                --   ms.settings.set("k", value)   -- write + save + fire onChange
                --
                --   ms.menu.define({ id="sec", title="My Section", icon="⚔",
                --       items={ {type="toggle", key="k", ...}, ... } })
                --
                --   ms.features.hide("socd")          -- hide SOCD rows in Tools
                --   ms.features.hide("trackpad")      -- hide Trackpad row in Tools
                --   ms.features.hide("sensitivity")   -- hide Sensitivity slider in Tools
                --   ms.features.hide("independentBinds") -- hide Ind. Binds row in Tools
                --
                -- ── ms.settings.define(def) ────────────────────────────────────────────────────────────────────
                -- Registers one setting or visual item in the Settings section.
                -- Items appear in declaration order.
                --
                ms.settings.define = function(def)
                    assert(type(def) == "table",
                        "ms.settings.define: argument must be a table")
                    local t = def.type
                    assert(_SETTING_TYPES[t],
                        "ms.settings.define: unknown type '" .. tostring(t) .. "'")
                    -- Visual-only items need no key or value.
                    if t == "divider" or t == "groupLabel" then
                        table.insert(ms._userSettingDefs, def)
                        return
                    end
                    -- Sound slot: no stored value — assignment lives in ms.soundAssign[key].
                    if t == "soundSlot" then
                        local key = def.key
                        assert(type(key) == "string" and #key > 0,
                            "ms.settings.define: 'key' is required for type 'soundSlot'")
                        assert(not ms._userSettingIndex[key],
                            "ms.settings.define: duplicate key '" .. key .. "'")
                        ms._userSettingIndex[key] = def
                        table.insert(ms._userSettingDefs, def)
                        return
                    end
                    local key = def.key
                    assert(type(key) == "string" and #key > 0,
                        "ms.settings.define: 'key' is required for type '" .. t .. "'")
                    assert(not ms._userSettingIndex[key],
                        "ms.settings.define: duplicate key '" .. key .. "'")
                    if def.onChange then
                        assert(type(def.onChange) == "function",
                            "ms.settings.define: onChange must be a function")
                    end
                    if def.onAction then
                        assert(type(def.onAction) == "function",
                            "ms.settings.define: onAction must be a function")
                    end
                    ms._userSettingIndex[key] = def
                    table.insert(ms._userSettingDefs, def)
                    -- Action items carry no stored value.
                    if t == "action" then return end
                    -- Seed with declared default; _applySettings will override with the
                    -- saved value once settings load from disk (after ms_macros.lua runs).
                    ms._userSettingVals[key] = def.default
                    if def.default ~= nil and type(def.onChange) == "function" then
                        pcall(def.onChange, def.default)
                    end
                end

                -- ── ms.settings.get(key) ──────────────────────────────────────────────────────────────────────
                -- Returns the current value of a user setting, or its declared default.
                -- Safe to call inside ms.fn()-wrapped macro bodies at any time.
                --
                ms.settings.get = function(key)
                    assert(type(key) == "string", "ms.settings.get: key must be a string")
                    local def = ms._userSettingIndex[key]
                    if not def then return nil end
                    local v = ms._userSettingVals[key]
                    return v ~= nil and v or def.default
                end

                -- ── ms.settings.set(key, value) ────────────────────────────────────────────────────────────
                -- Programmatically updates a user setting.
                -- Validates the value, persists if save ~= false, and fires onChange.
                --
                ms.settings.set = function(key, value)
                    assert(type(key) == "string", "ms.settings.set: key must be a string")
                    local def = ms._userSettingIndex[key]
                    if not def then
                        print("ms.settings.set: unknown key '" .. tostring(key) .. "'")
                        return
                    end
                    if def.type == "action" then
                        print("ms.settings.set: action items have no value (key='" .. key .. "')")
                        return
                    end
                    local validated = _validateUserValue(def, value)
                    if validated == nil then
                        print("ms.settings.set: invalid value " .. tostring(value)
                            .. " for key '" .. key .. "'")
                        return
                    end
                    ms._userSettingVals[key] = validated
                    if def.save ~= false then ms.saveSettings() end
                    if type(def.onChange) == "function" then
                        pcall(def.onChange, validated)
                    end
                end

                -- ── ms.menu.define(def) ────────────────────────────────────────────────────────────────────────
                -- Registers a custom panel section that appears below the Tools section.
                -- Sections appear in the order ms.menu.define is called.
                --
                --   id    (required) Unique identifier string.
                --   title (required) Header text shown in the panel.
                --   icon  (optional) Emoji prepended to the title in the panel header.
                --   items (required) Array of item definitions (same fields as
                --                    ms.settings.define entries). Each item with a key
                --                    is automatically reachable via ms.settings.get/set.
                --
                ms.menu.define = function(def)
                    assert(type(def) == "table",
                        "ms.menu.define: argument must be a table")
                    assert(type(def.id) == "string" and #def.id > 0,
                        "ms.menu.define: 'id' is required")
                    assert(type(def.title) == "string" and #def.title > 0,
                        "ms.menu.define: 'title' is required")
                    assert(type(def.items) == "table",
                        "ms.menu.define: 'items' must be a table")
                    -- Register each keyed item so ms.settings.get/set works for them.
                    for _, item in ipairs(def.items) do
                        if type(item) == "table"
                            and type(item.key) == "string" and #item.key > 0
                            and not ms._userSettingIndex[item.key] then
                            if item.onChange then
                                assert(type(item.onChange) == "function",
                                    "ms.menu.define: item onChange must be a function")
                            end
                            ms._userSettingIndex[item.key] = item
                            if item.type ~= "action" then
                                ms._userSettingVals[item.key] = item.default
                                if item.default ~= nil and type(item.onChange) == "function" then
                                    pcall(item.onChange, item.default)
                                end
                            end
                        end
                    end
                    table.insert(ms._userMenuDefs, def)
                end

                -- ── ms.features.hide(name) ───────────────────────────────────────────────────────────────────
                -- Hides a built-in panel feature for this macro pack session.
                -- Purely cosmetic — the underlying feature remains functional.
                -- The item reappears when the call is removed and Hammerspoon reloads.
                --
                -- Accepted names:
                --   "sensitivity"        Camera Sensitivity slider in Tools
                --   "socd"               SOCD Cleaning + Mode rows in Tools
                --   "trackpad"           Trackpad / Pen Mode row in Tools
                --   "independentBinds"   Independent Binds row in Tools
                --
                -- Note: "sound" and "profiles" cannot be hidden.
                --
                ms.features.hide = function(name)
                    if not _HIDEABLE_FEATURES[name] then
                        print("ms.features.hide: '" .. tostring(name)
                            .. "' is not a hideable feature. "
                            .. "Accepted: sensitivity, socd, trackpad, independentBinds")
                        return
                    end
                    ms._hiddenFeatures[name] = true
                end

                -- ── ms.setClickLevel(n) ─────────────────────────────────────────────────────────────────────────
                -- Bridge function: updates the system clickLevel variable from a
                -- ms.settings.define onChange callback in ms_macros.lua.
                -- This is the correct way to sync click level when it is declared as a
                -- user setting. Valid values: 1, 2, 3, 4.
                --
                ms.setClickLevel = function(n)
                    n = tonumber(n)
                    if n and (n == 1 or n == 2 or n == 3 or n == 4) then
                        clickLevel = n
                    end
                end

                -- ── END User Settings & Menu API ─────────────────────────────────────────────────────────────────────

                -- ── Theme System ─────────────────────────────────────────────────────
                --
                -- Loads data/ms_theme.json and validates every value.
                -- Safe to call multiple times; always resets to _themeDefaults first.
                -- Called at startup after loadSettings(), and on demand via the
                -- "Reload Theme" panel action.
                --
                ms.loadTheme = function()
                    for k, v in pairs(ms._themeDefaults) do ms._theme[k] = v end
                    local f = io.open(themePath, "r")
                    if not f then return end
                    local content = f:read("*all"); f:close()
                    local data = hs.json.decode(content)
                    if not data then return end
                    ms._themeLoaded = true
                    -- Validate hex color fields.
                    local colorKeys = {
                        "bg","surface","surface2","hover",
                        "accent","accentHi","success","dangerBg",
                        "danger","warning","text",
                    }
                    for _, k in ipairs(colorKeys) do
                        if type(data[k]) == "string"
                            and data[k]:match("^#[0-9a-fA-F]+$")
                        then
                            ms._theme[k] = data[k]
                        end
                    end
                    -- Validate radius (0–40, integer).
                    if type(data.radius) == "number" then
                        ms._theme.radius = math.max(0, math.min(40, math.floor(data.radius)))
                    end
                    -- Validate font (strip dangerous CSS characters).
                    if type(data.font) == "string" and #data.font > 0 then
                        local clean = data.font:gsub("[;{}()<>\"']", "")
                        if #clean > 0 then ms._theme.font = clean end
                    end
                    -- Validate uifc — supports table (per-window) or legacy string.
                    local function _sanitizeUIFCPath(p)
                        if type(p) ~= "string" or p == "" then return "" end
                        -- Strip .. traversal sequences in all slash-context forms.
                        -- The old pattern "%%.%%.  was wrong: in a Lua pattern, %% matches
                        -- a literal %, so it never matched "..".  The correct escape is %.%.
                        p = p:gsub("%.%.[/\\]", ""):gsub("[/\\]%.%.", ""):gsub("^%.%.$", "")
                        -- Strip leading / or ~ to block absolute-path injection.
                        p = p:gsub("^[/~]+", "")
                        return p
                    end
                    if type(data.uifc) == "string" and data.uifc ~= "" then
                        -- Backward compat: old single-string → settings key.
                        ms._theme.uifc = {
                            settings = _sanitizeUIFCPath(data.uifc),
                            guardian = "",
                        }
                    elseif type(data.uifc) == "table" then
                        ms._theme.uifc = { settings = "", guardian = "" }
                        if type(data.uifc.settings) == "string" then
                            ms._theme.uifc.settings = _sanitizeUIFCPath(data.uifc.settings)
                        end
                        if type(data.uifc.guardian) == "string" then
                            ms._theme.uifc.guardian = _sanitizeUIFCPath(data.uifc.guardian)
                        end
                    end
                end

                -- ── END Theme System ─────────────────────────────────────────────────

                -- ── Capability Detection — ms.has(feature) ───────────────────────────────────
                --
                -- Returns true if the named feature is present and configured.
                -- Safe to call from ms_macros.lua at any point after ms.macroMeta.
                -- Use this to guard optional features so packs degrade gracefully
                -- when a user hasn't configured something or on an older install.
                --
                -- Flags:
                --   "theme"        data/ms_theme.json was loaded (custom values on disk)
                --   "uifc"         theme has a UI Frame Cosmetic path and the PNG file exists
                --   "sound"        sound is enabled and at least one file is indexed
                --   "socd"         SOCD engine is currently enabled
                --   "trackpad"     trackpad mode is currently enabled
                --   "profiles"     at least one valid profile exists in profiles/
                --   "userSettings" ms.settings.define API is present (version compat)
                --   "userMenu"     ms.menu.define API is present (version compat)
                --   "integrity"    ms_core.lua matches its trusted hash (system integrity check)
                --   "hidinject"    hidinject binary is present in bin/
                --
                ms.has = function(feature)
                    local home = os.getenv("HOME") .. "/.hammerspoon"

                    if feature == "theme" then
                        return ms._themeLoaded == true

                    elseif feature == "uifc" then
                        -- True if any per-window UIFC path is configured and the file exists.
                        local u = ms._theme and ms._theme.uifc
                        if type(u) ~= "table" then return false end
                        for _, v in pairs(u) do
                            if type(v) == "string" and v ~= ""
                                and hs.fs.attributes(home .. "/" .. v) then
                                return true
                            end
                        end
                        return false

                    elseif feature == "sound" then
                        return ms.soundEnabled == true
                            and next(ms.sounds or {}) ~= nil

                    elseif feature == "socd" then
                        return ms.socdEnabled == true

                    elseif feature == "trackpad" then
                        return ms.trackpadMode == true

                    elseif feature == "profiles" then
                        local pPath = home .. "/profiles/"
                        if not hs.fs.attributes(pPath) then return false end
                        for entry in hs.fs.dir(pPath) do
                            if entry ~= "." and entry ~= ".." then
                                if hs.fs.attributes(pPath .. entry .. "/ms_macros.lua") then
                                    return true
                                end
                            end
                        end
                        return false

                    elseif feature == "userSettings" then
                        return type(ms.settings) == "table"
                            and type(ms.settings.define) == "function"

                    elseif feature == "userMenu" then
                        return type(ms.menu) == "table"
                            and type(ms.menu.define) == "function"

                    elseif feature == "integrity" then
                        return ms.integrity ~= nil
                            and ms.integrity.check() == "trusted"

                    elseif feature == "hidinject" then
                        return hs.fs.attributes(home .. "/bin/hidinject") ~= nil

                    end
                    return false
                end

                -- ── END Capability Detection ──────────────────────────────────────────────────

                -- ── Profile Management ──────────────────────────────────────────────

                -- Builds ms_settings_default.json from registry declarations + ms.macroDefaults.
                -- Called automatically when no default file exists. macroDefaults values take
                -- precedence over library defaults; registry entries fill per-macro enabled state.
                ms._buildDefaultSettings = function()
                    local data = {
                        sensitivity      = 1.5,
                        frameLevel       = 3,
                        trackpadMode     = false,
                        socdEnabled      = false,
                        socdMode         = "lastWins",
                        independentBinds = false,
                        trackpadHoldKeys = { left = "n", right = "j" },
                        soundEnabled     = true,
                        soundVolume      = 100,
                        soundAssign      = {},
                        macros           = {},
                    }
                    if ms.macroDefaults then
                        for k, v in pairs(ms.macroDefaults) do
                            if k ~= "macros" then data[k] = v end
                        end
                        if ms.macroDefaults.macros then
                            for id, entry in pairs(ms.macroDefaults.macros) do
                                data.macros[id] = data.macros[id] or {}
                                for k, v in pairs(entry) do data.macros[id][k] = v end
                            end
                        end
                    end
                    for _, id in ipairs(ms.registry._defList or {}) do
                        local def = ms.registry._defs[id]
                        if def and not def.sub then
                            data.macros[id] = data.macros[id] or {}
                            if data.macros[id].enabled == nil then
                                data.macros[id].enabled = def.enabled
                            end
                        end
                    end
                    local f = io.open(defaultPath, "w")
                    if f then
                        f:write(hs.json.encode(data, true))
                        f:close()
                    end
                end

                -- Strip characters that are unsafe in macOS folder names.
                local function sanitizeName(name)
                    return (name:gsub('[/\\:*?"<>|%c]', "_"):gsub("^%s+", ""):gsub("%s+$", ""))
                end

                -- Moves a file by read-copy-delete (safe across mount points).
                local function moveFile(src, dst)
                    local f = io.open(src, "r")
                    if not f then return false, "cannot read " .. src end
                    local content = f:read("*all"); f:close()
                    local g = io.open(dst, "w")
                    if not g then return false, "cannot write " .. dst end
                    g:write(content); g:close()
                    os.remove(src)
                    return true
                end

                -- Loads an ms_macros.lua in a minimal sandbox just to read macroMeta.
                -- Returns the macroMeta table or nil on failure.
                local function readMacroMeta(filePath)
                    local captured = {}
                    local dummyFn  = function() end
                    local dummyTbl = setmetatable({}, {
                        __index    = function() return dummyFn end,
                        __newindex = function() end,
                        __call     = function() end,
                    })
                    local proxy = setmetatable({}, {
                        __index    = function(t, k)
                            if k == "macroMeta" then return captured.macroMeta end
                            return dummyTbl
                        end,
                        __newindex = function(t, k, v)
                            if k == "macroMeta" then captured.macroMeta = v end
                        end,
                    })
                    local env = setmetatable({ ms = proxy }, {
                        __index    = function() return nil end,
                        __newindex = function() end,
                    })
                    local chunk, err
                    if setfenv then
                        chunk, err = loadfile(filePath)
                        if chunk then setfenv(chunk, env) end
                    else
                        chunk, err = loadfile(filePath, "bt", env)
                    end
                    if not chunk then
                        print("readMacroMeta: parse error in " .. filePath .. ": " .. tostring(err))
                        return nil
                    end
                    pcall(chunk)  -- errors are expected and harmless here
                    return captured.macroMeta
                end

                -- Returns a sorted list of profile names that have a saved ms_macros.lua.
                local function getProfiles()
                    local list = {}
                    if not hs.fs.attributes(profilesPath) then return list end
                    for entry in hs.fs.dir(profilesPath) do
                        if entry ~= "." and entry ~= ".." then
                            local attr = hs.fs.attributes(profilesPath .. entry)
                            if attr and attr.mode == "directory" then
                                if hs.fs.attributes(profilesPath .. entry .. "/ms_macros.lua") then
                                    table.insert(list, entry)
                                end
                            end
                        end
                    end
                    table.sort(list)
                    return list
                end

                -- Forward declaration so switchProfile can call auditMacros,
                -- which is defined below in the same scope.
                local auditMacros

                -- Archives the active lua file and its settings files into profiles/<currentName>/,
                -- activates the target profile files, then reloads after 3 seconds.
                local function switchProfile(targetName)
                    -- Security: audit the target profile before touching any files.
                    -- A file manually dropped into profiles/ bypasses importProfile's audit,
                    -- so we check here as well.
                    local targetFile = profilesPath .. targetName .. "/ms_macros.lua"
                    local tf = io.open(targetFile, "r")
                    if not tf then
                        ms.alert("Profile switch failed: cannot read target profile.", 5)
                        return
                    end
                    local targetSrc = tf:read("*all"); tf:close()
                    local switchErrs = auditMacros(targetSrc)
                    if #switchErrs > 0 then
                        ms.alert("Profile switch rejected — security scan failed:\n  • "
                            .. table.concat(switchErrs, "\n  • "), 8)
                        return
                    end
                    local currentName = sanitizeName(
                        (ms.macroMeta and ms.macroMeta.name) or "unnamed"
                    )
                    hs.fs.mkdir(profilesPath)
                    hs.fs.mkdir(profilesPath .. currentName)

                    local ok, err = moveFile(macrosPath, profilesPath .. currentName .. "/ms_macros.lua")
                    if not ok then
                        ms.alert("Profile switch failed: could not archive current profile.\n" .. tostring(err), 5)
                        return
                    end
                    local hadSettings = hs.fs.attributes(jsonPath)   and moveFile(jsonPath,    profilesPath .. currentName .. "/ms_settings.json")
                    local hadDefaults = hs.fs.attributes(defaultPath) and moveFile(defaultPath, profilesPath .. currentName .. "/ms_settings_default.json")

                    ok, err = moveFile(profilesPath .. targetName .. "/ms_macros.lua", macrosPath)
                    if not ok then
                        moveFile(profilesPath .. currentName .. "/ms_macros.lua", macrosPath)
                        if hadSettings then moveFile(profilesPath .. currentName .. "/ms_settings.json",         jsonPath)    end
                        if hadDefaults then moveFile(profilesPath .. currentName .. "/ms_settings_default.json", defaultPath) end
                        ms.alert("Profile switch failed: could not activate \"" .. targetName .. "\".\n" .. tostring(err), 5)
                        return
                    end
                    if hs.fs.attributes(profilesPath .. targetName .. "/ms_settings.json") then
                        moveFile(profilesPath .. targetName .. "/ms_settings.json",         jsonPath)
                    end
                    if hs.fs.attributes(profilesPath .. targetName .. "/ms_settings_default.json") then
                        moveFile(profilesPath .. targetName .. "/ms_settings_default.json", defaultPath)
                    end

                    ms.alert("Switched to \"" .. targetName .. "\".\nReloading in 3 seconds...", 4)
                    hs.timer.doAfter(3, function() hs.reload() end)
                end

                -- Pre-execution security audit.
                -- Scans the raw Lua source for patterns that indicate tampering
                -- or attempts to escape the runtime sandbox.
                -- Comments are stripped in two passes before scanning:
                --   Pass 1: block comments --[=*[ ... ]=*] (handles multi-line)
                --   Pass 2: line comments  -- ...
                -- A leading space is prepended so [^%w%.]-anchored patterns also
                -- fire at position 1 of the cleaned source.
                -- Returns a (possibly empty) list of violation strings.
                auditMacros = function(src)
                    -- ── Lexer pass: neutralize string literals and comments ───────────────
                    -- Replaces their *contents* with spaces so deny patterns below only
                    -- fire on actual executable code tokens.  Newlines are preserved so
                    -- the global-function line check at the end has stable line numbers.
                    --
                    -- Handles all four Lua token kinds:
                    --   "..." / '...'          short strings (with \-escape sequences)
                    --   [=*[...]=*]            long strings of any bracket level
                    --   -- line comment
                    --   --[=*[...]=*]          block comments of any bracket level
                    --
                    -- Why this replaces the old two-pass regex approach:
                    -- The old stripper searched for "--" in raw source text without
                    -- understanding string literals.  A string like "--[[" would open a
                    -- fake block comment in the scanner, silently removing the deny-
                    -- pattern check for every line that followed until a "]]" appeared.
                    -- This is the Lua equivalent of the SQL-injection quote trick: use
                    -- a delimiter character inside a literal to escape the surrounding
                    -- context in the parser.  A proper lexer eliminates the ambiguity.

                    local function blank(s) return s:gsub("[^\n]", " ") end
                    local out = {}
                    local i, n = 1, #src

                    while i <= n do
                        local c = src:sub(i, i)

                        if c == '"' or c == "'" then
                            -- ── Short quoted string ─────────────────────────────────────
                            -- Walk until unescaped closing quote or bare newline.
                            -- A bare newline inside a short string is a Lua syntax error,
                            -- but we stop there anyway to avoid run-on blanking.
                            local j = i + 1
                            while j <= n do
                                local ch = src:sub(j, j)
                                if ch == "\\" then
                                    j = j + 2       -- skip escape + the escaped char
                                elseif ch == c then
                                    break           -- found unescaped closing quote
                                elseif ch == "\n" then
                                    break           -- unterminated string
                                else
                                    j = j + 1
                                end
                            end
                            out[#out + 1] = blank(src:sub(i, j))
                            i = j + 1

                        elseif c == "-" and src:sub(i + 1, i + 1) == "-" then
                            -- ── Comment ────────────────────────────────────────────────
                            local j      = i + 2   -- first char after --
                            local isLong = false
                            if src:sub(j, j) == "[" then
                                local eq = 0
                                while src:sub(j + 1 + eq, j + 1 + eq) == "=" do eq = eq + 1 end
                                if src:sub(j + 1 + eq, j + 1 + eq) == "[" then
                                    -- Block comment --[=*[...]=*]
                                    local closer = "]" .. string.rep("=", eq) .. "]"
                                    local _, ce  = src:find(closer, j + 2 + eq, true)
                                    out[#out + 1] = blank(src:sub(i, ce or n))
                                    i = ce and ce + 1 or n + 1
                                    isLong = true
                                end
                            end
                            if not isLong then
                                -- Line comment: blank to end of line, keep the newline.
                                local nl = src:find("\n", j)
                                if nl then
                                    out[#out + 1] = blank(src:sub(i, nl - 1)) .. "\n"
                                    i = nl + 1
                                else
                                    out[#out + 1] = blank(src:sub(i))
                                    i = n + 1
                                end
                            end

                        elseif c == "[" then
                            -- ── Long string [=*[...]=*] ──────────────────────────────────
                            local eq = 0
                            while src:sub(i + 1 + eq, i + 1 + eq) == "=" do eq = eq + 1 end
                            if src:sub(i + 1 + eq, i + 1 + eq) == "[" then
                                local closer = "]" .. string.rep("=", eq) .. "]"
                                local _, ce  = src:find(closer, i + 2 + eq, true)
                                out[#out + 1] = blank(src:sub(i, ce or n))
                                i = ce and ce + 1 or n + 1
                            else
                                out[#out + 1] = c
                                i = i + 1
                            end

                        else
                            out[#out + 1] = c
                            i = i + 1
                        end
                    end

                    local clean = " " .. table.concat(out)
                    local errs  = {}
                    local function deny(pat, label)
                        if clean:find(pat) then table.insert(errs, label) end
                    end

                    -- Direct Hammerspoon API
                    deny("[^%w%.]hs%.[%a_]",      "direct hs.* API access")

                    -- Dynamic code loading
                    deny("[^%w%.]load%s*%(",       "load()")
                    deny("loadfile%s*%(",           "loadfile()")
                    deny("loadstring%s*%(",         "loadstring()")
                    deny("[^%w%.]dofile%s*%(",      "dofile()")
                    deny("[^%w%.]require%s*%(",     "require()")

                    -- OS / filesystem / shell
                    deny("[^%w%.]os%.[%a_]",        "os.* access")
                    deny("[^%w%.]io%.[%a_]",        "io.* access")
                    deny("[^%w%.]popen%s*%(",       "popen()")

                    -- Dangerous stdlib
                    deny("[^%w%.]debug%.[%a_]",     "debug.* access")
                    deny("[^%w%.]package%.[%a_]",   "package.* access")
                    deny("collectgarbage%s*%(",     "collectgarbage()")

                    -- Sandbox / metatable / environment escape
                    deny("setmetatable%s*%(",       "setmetatable()")
                    deny("getmetatable%s*%(",       "getmetatable()")
                    deny("[^%w_]rawget%s*%(",       "rawget()")
                    deny("[^%w_]rawset%s*%(",       "rawset()")
                    deny("setfenv%s*%(",            "setfenv()")
                    deny("getfenv%s*%(",            "getfenv()")
                    deny("%f[%w_]_G%f[^%w_]",      "_G global-environment access")

                    -- App control / URL / process
                    deny(":launch%s*%(",            ":launch()")
                    deny(":activate%s*%(",          ":activate()")
                    deny("openURL%s*%(",            "openURL()")

                    -- Filesystem paths to OS directories.
                    -- Exception: context within ~120 chars contains a media extension.
                    local mediaExts = {
                        "%.mp3","%.wav","%.aiff","%.m4a","%.ogg","%.flac",
                        "%.caf","%.aac","%.mp4","%.mov","%.avi",
                        "%.jpg","%.jpeg","%.png","%.gif","%.webp","%.bmp","%.tiff",
                    }
                    local function nearMedia(pos)
                        local ctx = clean:sub(math.max(1, pos-10), math.min(#clean, pos+120))
                        for _, ext in ipairs(mediaExts) do
                            if ctx:find(ext) then return true end
                        end
                        return false
                    end
                    for _, sysPath in ipairs({
                        "/Users/","/home/","/Applications/",
                        "/usr/","/var/","/etc/","/bin/","/sbin/",
                        "/opt/","/tmp/","/System/","/Library/",
                        "~/","%.hammerspoon",
                    }) do
                        local pos = clean:find(sysPath)
                        if pos and not nearMedia(pos) then
                            local snip = clean:sub(pos, math.min(#clean, pos+35))
                                             :gsub("%s+", " ")
                            table.insert(errs, "disallowed path: " .. snip)
                        end
                    end

                    -- Non-local global function definitions.
                    -- All helpers in ms_macros.lua must be declared with 'local'.
                    -- A bare 'function name()' at the start of a line creates a global.
                    for line in clean:gmatch("[^\n]+") do
                        local name = line:match("^%s*function%s+([%a_][%w_]*)%s*%(")
                        if name then
                            table.insert(errs, "non-local global function definition: " .. name .. "()")
                        end
                    end

                    return errs
                end

                -- Opens a file picker and imports the selected ms_macros.lua into profiles/.
                local function importProfile()
                    ms.playSlot("alert")
                    hs.focus()
                    local result = hs.dialog.chooseFileOrFolder(
                        "Select an ms_macros.lua file to import",
                        os.getenv("HOME") .. "/Downloads/",
                        true, false, false
                    )
                    local roblox = hs.application.get("Roblox")
                    -- Normalize: chooseFileOrFolder may use string keys ("1") not integer keys (1).
                    local selectedPath
                    for _, v in pairs(result or {}) do
                        if type(v) == "string" then selectedPath = v; break end
                    end
                    if not selectedPath then
                        if roblox then pcall(function() roblox:activate() end) end
                        return
                    end
                    local meta = readMacroMeta(selectedPath)
                    if not meta or not meta.name or meta.name == "" then
                        if roblox then pcall(function() roblox:activate() end) end
                        ms.alert("Could not read profile name.\nMake sure the file has ms.macroMeta = { name = \"...\" }.", 6)
                        return
                    end
                    local folderName = sanitizeName(meta.name)
                    -- Ensure the profiles directory and target subfolder both exist.
                    local sq = function(s) return "'" .. s:gsub("'", "'\\''" ) .. "'" end
                    hs.execute("mkdir -p " .. sq(profilesPath .. folderName))
                    if not hs.fs.attributes(profilesPath .. folderName) then
                        if roblox then pcall(function() roblox:activate() end) end
                        ms.alert("Could not create profile folder.", 3)
                        return
                    end
                    -- Read source file in binary mode (same as sound import).
                    local f = io.open(selectedPath, "rb")
                    if not f then
                        if roblox then pcall(function() roblox:activate() end) end
                        ms.alert("Could not read the selected file.", 3)
                        return
                    end
                    local content = f:read("*all"); f:close()
                    -- Security audit before writing anything.
                    local auditErrs = auditMacros(content)
                    if #auditErrs > 0 then
                        if roblox then pcall(function() roblox:activate() end) end
                        ms.alert("Import rejected — security scan failed:\n  • "
                            .. table.concat(auditErrs, "\n  • "), 8)
                        return
                    end
                    -- Write to profiles folder in binary mode.
                    local dst    = profilesPath .. folderName .. "/ms_macros.lua"
                    local copied = false
                    local g = io.open(dst, "wb")
                    if g then
                        g:write(content); g:close()
                        copied = true
                    end
                    -- Fallback: shell cp (same pattern as sound import).
                    if not copied then
                        local _, st = hs.execute("/bin/cp " .. sq(selectedPath) .. " " .. sq(dst))
                        copied = (st == true) or (hs.fs.attributes(dst) ~= nil)
                    end
                    if not copied then
                        if roblox then pcall(function() roblox:activate() end) end
                        ms.alert("Could not write to profiles folder.\nGrant Hammerspoon Full Disk Access if importing from outside ~/.hammerspoon.", 5)
                        return
                    end
                    ms.playSlot("update")
                    if roblox then pcall(function() roblox:activate() end) end
                    hs.timer.doAfter(0.2, function()
                        ms.alert("Profile \"" .. meta.name .. "\" imported.\nSwitch to it from Settings > Profiles.", 5, true)
                    end)
                end

                -- Exports the current active profile as a .mspkg zip package.
                -- Bundles ms_macros.lua + optional defaults/theme/sounds into
                -- ~/Downloads/<name>.mspkg and reveals it in Finder.
                local function exportProfilePkg()
                    local sq = function(s) return "'" .. s:gsub("'", "'\\''" ) .. "'" end
                    local name = sanitizeName((ms.macroMeta and ms.macroMeta.name) or "unnamed")
                    local outName = name .. ".mspkg"
                    local outPath = os.getenv("HOME") .. "/Downloads/" .. outName
                    local tmpDir  = archivePath .. "mspkg_export/"
                    os.execute("mkdir -p " .. sq(archivePath))
                    os.execute("rm -rf " .. sq(tmpDir))
                    os.execute("mkdir -p " .. sq(tmpDir))
                    -- ms_macros.lua (required)
                    local _, cpOk = hs.execute("/bin/cp " .. sq(macrosPath) .. " " .. sq(tmpDir .. "ms_macros.lua"))
                    if not hs.fs.attributes(tmpDir .. "ms_macros.lua") then
                        ms.alert("Export failed: could not read ms_macros.lua.", 4)
                        os.execute("rm -rf " .. sq(tmpDir)); return
                    end
                    -- ms_settings_default.json (optional)
                    if hs.fs.attributes(defaultPath) then
                        hs.execute("/bin/cp " .. sq(defaultPath) .. " " .. sq(tmpDir .. "ms_settings_default.json"))
                    end
                    -- ms_theme.json (optional)
                    if hs.fs.attributes(themePath) then
                        hs.execute("/bin/cp " .. sq(themePath) .. " " .. sq(tmpDir .. "ms_theme.json"))
                    end
                    -- Sounds referenced in ms.soundAssign that are user-imported (optional)
                    local soundsDir = tmpDir .. "sounds/"
                    local soundsCopied = 0
                    for _, soundName in pairs(ms.soundAssign or {}) do
                        local filename = soundName and ms.importedSounds and ms.importedSounds[soundName]
                        if filename then
                            local srcSnd = SoundLib .. filename
                            if hs.fs.attributes(srcSnd) then
                                os.execute("mkdir -p " .. sq(soundsDir))
                                hs.execute("/bin/cp " .. sq(srcSnd) .. " " .. sq(soundsDir .. filename))
                                soundsCopied = soundsCopied + 1
                            end
                        end
                    end
                    -- Zip the staging dir with relative paths
                    hs.execute("cd " .. sq(tmpDir) .. " && zip -r " .. sq(outPath) .. " . 2>/dev/null")
                    os.execute("rm -rf " .. sq(tmpDir))
                    if hs.fs.attributes(outPath) then
                        ms.playSlot("alert")
                        local msg = "Exported " .. outName .. " to ~/Downloads/"
                        if soundsCopied > 0 then
                            msg = msg .. "\n" .. soundsCopied .. " sound" .. (soundsCopied > 1 and "s" or "") .. " bundled."
                        end
                        ms.alert(msg, 5, true)
                    else
                        ms.alert("Export failed: could not create " .. outName .. ".", 4)
                    end
                end

                -- Imports a .mspkg zip package into profiles/.
                -- Validates ms_macros.lua, copies optional assets, auto-adds bundled sounds.
                local function importProfilePkg()
                    hs.focus()
                    local result = hs.dialog.chooseFileOrFolder(
                        "Select a .mspkg profile package to import",
                        os.getenv("HOME") .. "/Downloads/",
                        true, false, false, { "mspkg", "zip" }
                    )
                    local roblox = hs.application.get("Roblox")
                    local selectedPath
                    for _, v in pairs(result or {}) do
                        if type(v) == "string" then selectedPath = v; break end
                    end
                    if not selectedPath then
                        if roblox then pcall(function() roblox:activate() end) end
                        return
                    end
                    local sq = function(s) return "'" .. s:gsub("'", "'\\''" ) .. "'" end
                    local tmpDir = archivePath .. "mspkg_import/"
                    os.execute("mkdir -p " .. sq(archivePath))
                    os.execute("rm -rf " .. sq(tmpDir))
                    os.execute("mkdir -p " .. sq(tmpDir))
                    hs.execute("unzip -o " .. sq(selectedPath) .. " -d " .. sq(tmpDir) .. " 2>/dev/null")
                    local macroSrc = tmpDir .. "ms_macros.lua"
                    if not hs.fs.attributes(macroSrc) then
                        if roblox then pcall(function() roblox:activate() end) end
                        ms.alert("Import failed: package does not contain ms_macros.lua.", 5)
                        os.execute("rm -rf " .. sq(tmpDir)); return
                    end
                    local mf = io.open(macroSrc, "rb")
                    if not mf then
                        if roblox then pcall(function() roblox:activate() end) end
                        ms.alert("Import failed: could not read ms_macros.lua from package.", 4)
                        os.execute("rm -rf " .. sq(tmpDir)); return
                    end
                    local content = mf:read("*all"); mf:close()
                    local auditErrs = auditMacros(content)
                    if #auditErrs > 0 then
                        if roblox then pcall(function() roblox:activate() end) end
                        ms.alert("Import rejected \xe2\x80\x94 security scan failed:\n  \xe2\x80\xa2 " .. table.concat(auditErrs, "\n  \xe2\x80\xa2 "), 8)
                        os.execute("rm -rf " .. sq(tmpDir)); return
                    end
                    local meta = readMacroMeta(macroSrc)
                    if not meta or not meta.name or meta.name == "" then
                        if roblox then pcall(function() roblox:activate() end) end
                        ms.alert("Import failed: could not read profile name from ms_macros.lua.", 5)
                        os.execute("rm -rf " .. sq(tmpDir)); return
                    end
                    local folderName = sanitizeName(meta.name)
                    hs.execute("mkdir -p " .. sq(profilesPath .. folderName))
                    -- ms_macros.lua
                    local dst = profilesPath .. folderName .. "/ms_macros.lua"
                    local copied = false
                    local gf = io.open(dst, "wb")
                    if gf then gf:write(content); gf:close(); copied = true end
                    if not copied then
                        local _, st = hs.execute("/bin/cp " .. sq(macroSrc) .. " " .. sq(dst))
                        copied = (st == true) or (hs.fs.attributes(dst) ~= nil)
                    end
                    if not copied then
                        if roblox then pcall(function() roblox:activate() end) end
                        ms.alert("Import failed: could not write to profiles folder.\nGrant Hammerspoon Full Disk Access if needed.", 5)
                        os.execute("rm -rf " .. sq(tmpDir)); return
                    end
                    -- ms_settings_default.json (optional)
                    local defSrc = tmpDir .. "ms_settings_default.json"
                    if hs.fs.attributes(defSrc) then
                        hs.execute("/bin/cp " .. sq(defSrc) .. " " .. sq(profilesPath .. folderName .. "/ms_settings_default.json"))
                    end
                    -- ms_theme.json (optional)
                    local themeSrc = tmpDir .. "ms_theme.json"
                    if hs.fs.attributes(themeSrc) then
                        hs.execute("/bin/cp " .. sq(themeSrc) .. " " .. sq(profilesPath .. folderName .. "/ms_theme.json"))
                    end
                    -- sounds/ (optional) — copy into SoundLib, skip existing, track in importedSounds
                    local soundsDir = tmpDir .. "sounds/"
                    local soundsAdded = {}
                    if hs.fs.attributes(soundsDir) then
                        local slibDir = SoundLib:match("^(.-)[/\\]*$") or SoundLib
                        if not hs.fs.attributes(slibDir) then
                            hs.execute("mkdir -p '" .. SoundLib .. "'")
                        end
                        for file in hs.fs.dir(soundsDir) do
                            if file ~= "." and file ~= ".." then
                                local importName = file:match("^(.+)%.[^%.]+$") or file
                                local srcSnd = soundsDir .. file
                                local dstSnd = SoundLib .. file
                                if not hs.fs.attributes(dstSnd) then
                                    local sf = io.open(srcSnd, "rb")
                                    if sf then
                                        local data = sf:read("*all"); sf:close()
                                        local out = io.open(dstSnd, "wb")
                                        if out then
                                            out:write(data); out:close()
                                            ms.importedSounds = ms.importedSounds or {}
                                            ms.importedSounds[importName] = file
                                            table.insert(soundsAdded, importName)
                                        end
                                    end
                                end
                            end
                        end
                        if #soundsAdded > 0 then
                            ms.saveSettings()
                            ms._discoverSounds()
                        end
                    end
                    os.execute("rm -rf " .. sq(tmpDir))
                    if roblox then pcall(function() roblox:activate() end) end
                    ms.playSlot("update")
                    hs.timer.doAfter(0.2, function()
                        local msg = "\"" .. meta.name .. "\" imported.\nSwitch to it from Settings \xe2\x86\x92 Profiles."
                        if #soundsAdded > 0 then
                            msg = msg .. "\n" .. #soundsAdded .. " sound" .. (#soundsAdded > 1 and "s" or "") .. " added to library."
                        end
                        ms.alert(msg, 6, true)
                        ms.ui.refresh()
                    end)
                end

                -- ── End Profile Management ───────────────────────────────────────────

                -- ── System Integrity / Update System ─────────────────────────────────

                ms.integrity = {}

                -- Synchronously compute the SHA-256 of `path` via shasum(1).
                -- Returns the 64-char lowercase hex string, or nil on failure.
                ms.integrity.hashFile = function(path)
                    local escaped = "'" .. path:gsub("'", "'\\'") .. "'"
                    local out = hs.execute("shasum -a 256 " .. escaped .. " 2>/dev/null")
                    if out and #out >= 64 then return out:sub(1, 64):lower() end
                    return nil
                end

                -- Read the locally-stored trusted hash from .ms_trusted_hash.
                -- Returns the 64-char lowercase hex string, or nil if no file exists.
                ms.integrity.readTrustedHash = function()
                    local f = io.open(trustedHashPath, "r")
                    if not f then return nil end
                    local h = f:read("*all"); f:close()
                    h = h and h:match("^%s*([0-9a-fA-F]+)%s*$")
                    return (h and #h == 64) and h:lower() or nil
                end

                -- Write `hash` to .ms_trusted_hash. Returns true on success.
                ms.integrity.writeTrustedHash = function(hash)
                    local f = io.open(trustedHashPath, "w")
                    if f then f:write(hash .. "\n"); f:close(); return true end
                    return false
                end

                -- Delete .ms_trusted_hash, disabling tamper protection until re-trusted.
                -- Returns true on success, false if the file didn't exist or couldn't be removed.
                ms.integrity.deleteTrustedHash = function()
                    return os.remove(trustedHashPath) ~= nil
                end

                -- Compare the current ms_core.lua hash to the stored trusted baseline.
                -- Returns: status ("trusted"|"mismatch"|"uninitialized"), currentHash, trustedHash
                ms.integrity.check = function()
                    local cur     = ms.integrity.hashFile(corePath)
                    local trusted = ms.integrity.readTrustedHash()
                    if not trusted            then return "uninitialized", cur, nil     end
                    if cur == trusted         then return "trusted",       cur, trusted end
                    return "mismatch", cur, trusted
                end

                -- Seal the current ms_core.lua as the trusted baseline.
                ms.integrity.trustCurrent = function()
                    local hash = ms.integrity.hashFile(corePath)
                    if not hash then
                        ms.alert("System integrity: could not hash ms_core.lua.", 4)
                        return false
                    end
                    if ms.integrity.writeTrustedHash(hash) then
                        ms.alert("Trusted hash saved.\n" .. hash:sub(1, 16) .. "\xe2\x80\xa6", 4, true)
                        return true
                    end
                    ms.alert("System integrity: could not write trusted hash file.", 4)
                    return false
                end

                -- Fetch MANIFEST.json from ms._updateManifestURL, verify the SHA-256 of the
                -- downloaded ms_core.lua against it, back up the current file, write the new one,
                -- update .ms_trusted_hash, then reload.  All network I/O is async.
                ms.integrity.update = function()
                    local manifestURL = ms._updateManifestURL
                    if not manifestURL or manifestURL == "" then
                        ms.alert("Update URL not configured.\nSet ms._updateManifestURL in ms_core.lua.", 6)
                        return
                    end
                    -- Require HTTPS.  An HTTP URL would allow a network observer to serve
                    -- a malicious manifest and file, completely bypassing hash verification.
                    if not manifestURL:match("^https://") then
                        ms.alert("Update URL must use HTTPS.\nHTTP URLs are not permitted.", 6)
                        return
                    end
                    ms.alert("Fetching update manifest\xe2\x80\xa6", 4, true)
                    hs.http.asyncGet(manifestURL, nil, function(mCode, mBody, _)
                        if mCode ~= 200 or not mBody then
                            ms.alert("Update failed: manifest request returned " .. tostring(mCode) .. ".", 5)
                            return
                        end
                        local manifest = hs.json.decode(mBody)
                        if not manifest or not manifest.sha256 or not manifest.url then
                            ms.alert("Update failed: manifest missing 'sha256' or 'url' field.", 5)
                            return
                        end
                        -- Verify the manifest signature when a public key is configured.
                        -- A missing signature field is allowed (backward-compat / unsigned
                        -- releases during development).  An INVALID signature is a hard
                        -- abort — it means the manifest was tampered with after signing.
                        if manifest.signature and manifest.signature ~= ""
                            and ms._updatePublicKey
                            and not ms._updatePublicKey:find("PLACEHOLDER") then
                            local _tmpDir  = archivePath
                            local _keyPath = _tmpDir .. "upd_pub.pem"
                            local _sigPath = _tmpDir .. "upd_sig.bin"
                            local _msgPath = _tmpDir .. "upd_msg.bin"
                            os.execute("mkdir -p '" .. _tmpDir .. "'")
                            -- Write public key.
                            local _kf = io.open(_keyPath, "w")
                            if _kf then _kf:write(ms._updatePublicKey); _kf:close() end
                            -- Decode base64 signature to binary.
                            -- Use macOS native `base64 -D` — openssl base64 silently
                            -- fails to write its -out file on macOS LibreSSL.
                            local _sf = io.open(_sigPath .. ".b64", "w")
                            if _sf then _sf:write(manifest.signature); _sf:close() end
                            hs.execute("base64 -D -i '" .. _sigPath .. ".b64' -o '" .. _sigPath .. "'")
                            os.remove(_sigPath .. ".b64")
                            -- Write the signed message (the sha256 hex string).
                            local _mf = io.open(_msgPath, "w")
                            if _mf then _mf:write(manifest.sha256:lower()); _mf:close() end
                            -- Verify — capture output so errors surface in the alert.
                            local _out, _ok = hs.execute(
                                "openssl dgst -sha256 -verify '" .. _keyPath ..
                                "' -signature '" .. _sigPath ..
                                "' '" .. _msgPath .. "' 2>&1"
                            )
                            os.remove(_keyPath); os.remove(_sigPath); os.remove(_msgPath)
                            if not _ok then
                                ms.alert("Update aborted: signature verification failed.\n" .. tostring(_out), 12)
                                return
                            end
                        end
                        local newVersion   = manifest.version or "?"
                        local expectedHash = manifest.sha256:lower()
                        ms.alert("Downloading v" .. newVersion .. "\xe2\x80\xa6", 4, true)
                        hs.http.asyncGet(manifest.url, nil, function(fCode, fBody, _)
                            if fCode ~= 200 or not fBody then
                                ms.alert("Update failed: file download returned " .. tostring(fCode) .. ".", 5)
                                return
                            end
                            -- Write to a temp file so we can hash it before touching ms_core.lua.
                            os.execute("mkdir -p '" .. archivePath .. "'")
                            local tmpPath = archivePath .. "ms_core_update_tmp.lua"
                            local tmpF = io.open(tmpPath, "w")
                            if not tmpF then
                                ms.alert("Update failed: could not write temp file.", 4)
                                return
                            end
                            tmpF:write(fBody); tmpF:close()
                            local actualHash = ms.integrity.hashFile(tmpPath)
                            -- Hash check: warn on mismatch but do not abort.
                            -- Both the manifest and the file come from the same GitHub repo
                            -- over HTTPS, so a mismatch almost always means the developer
                            -- forgot to run make_release.sh — not an attack.  Hard-failing
                            -- the update in that case just leaves the user on an older
                            -- version with no way to self-heal.  We install whatever was
                            -- downloaded, seed the trusted hash from the actual file, and
                            -- surface a notice so the developer can see it in the console.
                            if actualHash ~= expectedHash then
                                print("ms update: MANIFEST hash mismatch (expected "
                                    .. expectedHash:sub(1,16) .. "… got "
                                    .. (actualHash or "?"):sub(1,16) .. "…)"
                                    .. " — installing anyway and re-seeding trust from actual file.")
                            end
                            -- Back up current ms_core.lua.
                            local timestamp  = os.date("%Y-%m-%d_%H%M")
                            local backupFile = archivePath .. "ms_core_" .. timestamp .. ".lua.bak"
                            local bOk = moveFile(corePath, backupFile)
                            if not bOk then
                                os.remove(tmpPath)
                                ms.alert("Update failed: could not back up ms_core.lua.", 4)
                                return
                            end
                            -- Move verified temp into place.
                            local mOk = moveFile(tmpPath, corePath)
                            if not mOk then
                                moveFile(backupFile, corePath)  -- restore
                                ms.alert("Update failed: could not install new ms_core.lua.\nBackup restored.", 5)
                                return
                            end
                            ms.integrity.writeTrustedHash(actualHash)
                            ms.alert("Updated to v" .. newVersion .. ".\nReloading in 3 seconds\xe2\x80\xa6", 5, true)
                            hs.timer.doAfter(3, function() hs.reload() end)
                        end)
                    end)
                end

                -- ── End System Integrity / Update System ─────────────────────────────────

                -- Returns the effective bind config for an id, accounting for trackpad mode overrides
                ms.effectiveBind = function(id)
                    if ms.trackpadMode and ms.trackpadBindOverrides and ms.trackpadBindOverrides[id] then
                        return ms.trackpadBindOverrides[id]
                    end
                    local def = ms.registry._defs and ms.registry._defs[id]
                    return ms.bindConfig[id] or (def and def.default)
                end

                -- SOCD Engine --
                    ms._socdListener = nil
                    ms._socdHeld = { a = false, d = false, w = false, s = false }

                    local socdKeyCodes = {
                        a = hs.keycodes.map["a"],
                        d = hs.keycodes.map["d"],
                        w = hs.keycodes.map["w"],
                        s = hs.keycodes.map["s"],
                    }

                    local socdCodeToKey = {}
                    for name, code in pairs(socdKeyCodes) do
                        socdCodeToKey[code] = name
                    end

                    local function socdAxis(neg, pos, axisKey)
                        local negHeld = ms._socdHeld[neg]
                        local posHeld = ms._socdHeld[pos]
                        local mode = ms.socdMode or "lastWins"

                        if not negHeld and not posHeld then return end
                        if negHeld and not posHeld then return end
                        if posHeld and not negHeld then return end

                        -- Both held — resolve
                        if mode == "neutral" then
                            -- Release both physically
                            local negCode = socdKeyCodes[neg]
                            local posCode = socdKeyCodes[pos]
                            local evNeg = hs.eventtap.event.newKeyEvent({}, negCode, false)
                            local evPos = hs.eventtap.event.newKeyEvent({}, posCode, false)
                            evNeg:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                            evPos:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                            evNeg:post()
                            evPos:post()
                        elseif mode == "lastWins" then
                            -- Already handled at keydown time — no extra action needed here
                        elseif mode == "firstWins" then
                            -- Suppress the second key — handled at keydown time
                        end
                    end

                    ms.socdStart = function()
                        if ms._socdListener then return end
                        ms._socdHeld  = { a = false, d = false, w = false, s = false }

                        ms._socdListener = hs.eventtap.new({
                            hs.eventtap.event.types.keyDown,
                            hs.eventtap.event.types.keyUp,
                        }, function(event)
                            if BindValidity ~= 1 then return false end
                            local isSynthetic = event:getProperty(hs.eventtap.event.properties.eventSourceUserData) == 999
                            if isSynthetic then return false end

                            local keyCode = event:getKeyCode()
                            local key = socdCodeToKey[keyCode]
                            if not key then return false end

                            local isDown = event:getType() == hs.eventtap.event.types.keyDown
                            local mode = ms.socdMode or "lastWins"

                            if isDown then
                                ms._socdHeld[key] = true

                                if key == "a" or key == "d" then
                                    local opp = (key == "a") and "d" or "a"
                                    if ms._socdHeld[opp] then
                                        if mode == "lastWins" then
                                            -- Release the opposite key
                                            local oppCode = socdKeyCodes[opp]
                                            local ev = hs.eventtap.event.newKeyEvent({}, oppCode, false)
                                            ev:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                                            ev:post()
                                            ms.keytrack[oppCode] = false
                                        elseif mode == "firstWins" then
                                            -- Swallow this key, first key keeps priority
                                            ms._socdHeld[key] = false
                                            return true
                                        elseif mode == "neutral" then
                                            -- Release both
                                            local oppCode = socdKeyCodes[opp]
                                            local ev1 = hs.eventtap.event.newKeyEvent({}, oppCode, false)
                                            local ev2 = hs.eventtap.event.newKeyEvent({}, keyCode, false)
                                            ev1:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                                            ev2:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                                            ev1:post()
                                            ev2:post()
                                            ms.keytrack[oppCode] = false
                                            ms.keytrack[keyCode] = false
                                            return true
                                        end
                                    end

                                elseif key == "w" or key == "s" then
                                    local opp = (key == "w") and "s" or "w"
                                    if ms._socdHeld[opp] then
                                        if mode == "lastWins" then
                                            local oppCode = socdKeyCodes[opp]
                                            local ev = hs.eventtap.event.newKeyEvent({}, oppCode, false)
                                            ev:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                                            ev:post()
                                            ms.keytrack[oppCode] = false
                                        elseif mode == "firstWins" then
                                            ms._socdHeld[key] = false
                                            return true
                                        elseif mode == "neutral" then
                                            local oppCode = socdKeyCodes[opp]
                                            local ev1 = hs.eventtap.event.newKeyEvent({}, oppCode, false)
                                            local ev2 = hs.eventtap.event.newKeyEvent({}, keyCode, false)
                                            ev1:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                                            ev2:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                                            ev1:post()
                                            ev2:post()
                                            ms.keytrack[oppCode] = false
                                            ms.keytrack[keyCode] = false
                                            return true
                                        end
                                    end
                                end

                            else
                                -- Key released
                                ms._socdHeld[key] = false

                                -- In lastWins: when you release the last-pressed key,
                                -- re-press the opposite if it's still physically held
                                if mode == "lastWins" then
                                    local opp
                                    if key == "a" then opp = "d"
                                    elseif key == "d" then opp = "a"
                                    elseif key == "w" then opp = "s"
                                    elseif key == "s" then opp = "w"
                                    end
                                    if opp and ms._socdHeld[opp] then
                                        local oppCode = socdKeyCodes[opp]
                                        local ev = hs.eventtap.event.newKeyEvent({}, oppCode, true)
                                        ev:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                                        ev:post()
                                        ms.keytrack[oppCode] = true
                                    end
                                end
                            end

                            return false
                        end):start()
                    end

                    ms.socdStop = function()
                        if ms._socdListener then
                            ms._socdListener:stop()
                            ms._socdListener = nil
                        end
                        ms._socdHeld  = { a = false, d = false, w = false, s = false }
                    end

                    ms.socdApply = function()
                        if ms.socdEnabled then
                            ms.socdStart()
                        else
                            ms.socdStop()
                        end
                    end
                -- END SOCD Engine --

                if ms._menubar then pcall(function() ms._menubar:delete() end) end
                ms._menubar = hs.menubar.new()
                ms._menubar:setIcon(os.getenv("HOME") .. "/.hammerspoon/ui/icons/ms_icon_gen.tiff", true)
                -- The NSMenu dropdown below is kept (as an unused local) for reference/rollback
                -- only. It is no longer wired to ms.menu — Section 10 (ms.ui) replaces it with
                -- the webview Settings panel. Open it via the menu-bar icon or Alt+P.
                local _legacyNativeMenuBuilder = function()
                    -- Build ordered group lists from the registry.
                    local mainBindDefs, optionalBindDefs = {}, {}
                    for _, id in ipairs(ms.registry._defList or {}) do
                        local def = ms.registry._defs[id]
                        if def and not def.sub then
                            local entry = { id = id, label = def.label, info = def.info }
                            if def.group == "main" then
                                table.insert(mainBindDefs, entry)
                            elseif def.group == "optional" then
                                table.insert(optionalBindDefs, entry)
                            end
                        end
                    end

                    -- Shared helpers --

                    local function bindStr(c)
                        if not c then return "( unset )" end
                        if c.type == "mouse" then return "( Mouse " .. c.button .. " )" end
                        local parts = {}
                        for _, m in ipairs(c.mods or {}) do table.insert(parts, m) end
                        table.insert(parts, c.key)
                        return "( " .. table.concat(parts, "+") .. " )"
                    end

                    local function currentBindStr(id)
                        return bindStr(ms.effectiveBind(id))
                    end

                    -- Returns a flat ordered list of {item, depth} for all sub-items of parentId.
                    local function getSubItems(parentId, depth)
                        depth = depth or 0
                        local result = {}
                        for _, id in ipairs(ms.registry._defList or {}) do
                            local def = ms.registry._defs[id]
                            if def and def.sub == parentId then
                                table.insert(result, {
                                    item  = { id = id, label = def.label, mod = def.mod },
                                    depth = depth,
                                })
                                for _, child in ipairs(getSubItems(id, depth + 1)) do
                                    table.insert(result, child)
                                end
                            end
                        end
                        return result
                    end

                    local function indent(depth)
                        return string.rep("    ", depth)
                    end

                    -- Rebind capture --

                    local function makeRebindFn(bind)
                        return function()
                            ms.alert("Rebinding: " .. bind.label .. "\nPress your new key or mouse button.\nEscape to cancel.", 15)
                            local capture
                            local cancelTimer

                            capture = hs.eventtap.new({
                                hs.eventtap.event.types.keyDown,
                                hs.eventtap.event.types.leftMouseDown,
                                hs.eventtap.event.types.rightMouseDown,
                                hs.eventtap.event.types.otherMouseDown,
                            }, function(event)
                                capture:stop()
                                capture = nil
                                cancelTimer:stop()

                                local parsed = nil
                                local bindStr2 = ""
                                local t = event:getType()

                                if t == hs.eventtap.event.types.keyDown then
                                    local keyCode = event:getKeyCode()
                                    local flags = event:getFlags()
                                    if keyCode == 53 and not (flags.cmd or flags.alt or flags.ctrl or flags.shift) then
                                        ms.alert("Rebind cancelled.", 2)
                                        return true
                                    end
                                    local mods = {}
                                    if flags.cmd   then table.insert(mods, "cmd")   end
                                    if flags.alt   then table.insert(mods, "alt")   end
                                    if flags.ctrl  then table.insert(mods, "ctrl")  end
                                    if flags.shift then table.insert(mods, "shift") end
                                    local keyStr = hs.keycodes.map[keyCode]
                                    if keyStr then
                                        parsed = {type="key", mods=mods, key=keyStr}
                                        local parts = {}
                                        for _, m in ipairs(mods) do table.insert(parts, m) end
                                        table.insert(parts, keyStr)
                                        bindStr2 = table.concat(parts, "+")
                                    end
                                else
                                    local btn
                                    if t == hs.eventtap.event.types.leftMouseDown then btn = 0
                                    elseif t == hs.eventtap.event.types.rightMouseDown then btn = 1
                                    else btn = event:getProperty(hs.eventtap.event.properties.mouseEventButtonNumber) end
                                    parsed = {type="mouse", button=btn}
                                    bindStr2 = "Mouse " .. btn
                                end

                                if parsed then
                                    -- Interactive conflict check: block save if a sibling already uses this input.
                                    local conflictId = ms.bind.siblingConflict(bind.id, parsed)
                                    if conflictId then
                                        ms.playSlot("alert")
                                        local cLabel = (ms.registry._defs[conflictId] and ms.registry._defs[conflictId].label) or conflictId
                                        ms.alert("Bind Conflict: \"" .. bindStr2 .. "\" is already used by \"" .. cLabel .. "\". Try a different input.", 4)
                                        return true
                                    end
                                    ms.playSlot("interact")
                                    ms.ui.modal({
                                        title   = "Confirm Rebind",
                                        msg     = "Set \"" .. bind.label .. "\" to:  " .. bindStr2,
                                        confirm = "Confirm",
                                        cancel  = "Cancel",
                                    }, function(r)
                                        if r.confirmed then
                                            ms.bindConfig[bind.id] = parsed
                                            ms.saveSettings()
                                            ms.playSlot("update")
                                            ms.bind.rebind()
                                            hs.timer.doAfter(0.2, function()
                                                ms.alert(bind.label .. " rebound to: " .. bindStr2, 3, true)
                                            end)
                                        else
                                            ms.alert("Rebind cancelled.", 2, true)
                                        end
                                    end)
                                else
                                    ms.alert("Could not read input. Try again.", 2)
                                end
                                return true
                            end)

                            capture:start()
                            cancelTimer = hs.timer.doAfter(15, function()
                                if capture then
                                    capture:stop()
                                    capture = nil
                                    ms.alert("Rebind timed out.", 2)
                                end
                            end)
                        end
                    end

                    local function makeModRebindFn(item, parentLabel)
                        return function()
                            local cur = ms.getMod(item.id)
                            local curDisplay = cur or "unset"
                            ms.alert("Rebinding modifier for:\n" .. parentLabel .. " › " .. item.label
                                .. "\nCurrent: " .. curDisplay
                                .. "\nPress a key, or Backspace to clear.\nEscape to cancel.", 15)
                            local capture
                            local cancelTimer
                            capture = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(event)
                                capture:stop(); capture = nil; cancelTimer:stop()
                                local keyCode = event:getKeyCode()
                                local flags = event:getFlags()
                                if keyCode == 53 and not (flags.cmd or flags.alt or flags.ctrl or flags.shift) then ms.alert("Rebind cancelled.", 2); return true end
                                if keyCode == 51 then
                                    ms.playSlot("interact")
                                    ms.ui.modal({
                                        title   = "Clear Modifier",
                                        msg     = "Clear modifier for \"" .. item.label .. "\"?",
                                        confirm = "Clear",
                                        cancel  = "Cancel",
                                    }, function(r)
                                        if r.confirmed then
                                            ms.modConfig[item.id] = ""
                                            ms.saveSettings()
                                            ms.playSlot("reset")
                                            hs.timer.doAfter(0.2, function()
                                                ms.alert(item.label .. " modifier cleared.", 3, true)
                                            end)
                                        else
                                            ms.alert("Rebind cancelled.", 2)
                                        end
                                    end)
                                    return true
                                end
                                local keyStr = hs.keycodes.map[keyCode]
                                if keyStr then
                                    -- Interactive modifier conflict check.
                                    local conflictId = ms.bind.siblingModConflict(item.id, keyStr)
                                    if conflictId then
                                        ms.playSlot("alert")
                                        local cLabel = (ms.registry._defs[conflictId] and ms.registry._defs[conflictId].label) or conflictId
                                        ms.alert("Modifier Conflict: \"" .. keyStr .. "\" is already used by \"" .. cLabel .. "\". Try a different key.", 4)
                                        return true
                                    end
                                    ms.playSlot("interact")
                                    ms.ui.modal({
                                        title   = "Confirm Modifier",
                                        msg     = "Set modifier for \"" .. item.label .. "\" to:  " .. keyStr,
                                        confirm = "Confirm",
                                        cancel  = "Cancel",
                                    }, function(r)
                                        if r.confirmed then
                                            ms.modConfig[item.id] = keyStr
                                            ms.saveSettings()
                                            ms.playSlot("update")
                                            hs.timer.doAfter(0.2, function()
                                                ms.alert(item.label .. " modifier set to: " .. keyStr, 3, true)
                                            end)
                                        else
                                            ms.alert("Rebind cancelled.", 2)
                                        end
                                    end)
                                else
                                    ms.alert("Could not read key. Try again.", 2)
                                end
                                return true
                            end)
                            capture:start()
                            cancelTimer = hs.timer.doAfter(15, function()
                                if capture then capture:stop(); capture = nil; ms.alert("Rebind timed out.", 2) end
                            end)
                        end
                    end

                    local function makeSubBindFn(item, parentLabel)
                        return function()
                            if not ms.independentBindsEnabled then
                                ms.alert("Enable Independent Binds first.", 2)
                                return
                            end
                            local cur = ms.subBinds and ms.subBinds[item.id]
                            local curDisplay = cur and bindStr(cur) or "unset"
                            ms.alert("Rebinding: " .. parentLabel .. " › " .. item.label
                                .. "\nCurrent: " .. curDisplay
                                .. "\nPress your new key or mouse button.\nBackspace to clear. Escape to cancel.", 15)
                            local capture
                            local cancelTimer
                            capture = hs.eventtap.new({
                                hs.eventtap.event.types.keyDown,
                                hs.eventtap.event.types.leftMouseDown,
                                hs.eventtap.event.types.rightMouseDown,
                                hs.eventtap.event.types.otherMouseDown,
                            }, function(event)
                                capture:stop(); capture = nil; cancelTimer:stop()
                                local t = event:getType()
                                if t == hs.eventtap.event.types.keyDown and event:getKeyCode() == 53 then
                                    ms.alert("Rebind cancelled.", 2); return true
                                end
                                if t == hs.eventtap.event.types.keyDown and event:getKeyCode() == 51 then
                                    ms.playSlot("interact")
                                    ms.ui.modal({
                                        title   = "Clear Bind",
                                        msg     = "Clear independent bind for \"" .. item.label .. "\"?",
                                        confirm = "Clear",
                                        cancel  = "Cancel",
                                    }, function(r)
                                        if r.confirmed then
                                            ms.subBinds[item.id] = nil
                                            ms.saveSettings()
                                            ms.bind.rebind()
                                            ms.playSlot("reset")
                                            hs.timer.doAfter(0.2, function()
                                                ms.alert(item.label .. " independent bind cleared.", 3, true)
                                            end)
                                        else
                                            ms.alert("Rebind cancelled.", 2)
                                        end
                                    end)
                                    return true
                                end

                                local parsed, displayStr
                                if t == hs.eventtap.event.types.keyDown then
                                    local keyCode = event:getKeyCode()
                                    local flags   = event:getFlags()
                                    local mods = {}
                                    if flags.cmd   then table.insert(mods, "cmd")   end
                                    if flags.alt   then table.insert(mods, "alt")   end
                                    if flags.ctrl  then table.insert(mods, "ctrl")  end
                                    if flags.shift then table.insert(mods, "shift") end
                                    local keyStr = hs.keycodes.map[keyCode]
                                    if keyStr then
                                        parsed = {type="key", mods=mods, key=keyStr}
                                        local parts = {}
                                        for _, m in ipairs(mods) do table.insert(parts, m) end
                                        table.insert(parts, keyStr)
                                        displayStr = table.concat(parts, "+")
                                    end
                                else
                                    local btn
                                    if     t == hs.eventtap.event.types.leftMouseDown  then btn = 0
                                    elseif t == hs.eventtap.event.types.rightMouseDown then btn = 1
                                    else btn = event:getProperty(hs.eventtap.event.properties.mouseEventButtonNumber) end
                                    parsed     = {type="mouse", button=btn}
                                    displayStr = "Mouse " .. btn
                                end

                                if parsed then
                                    ms.playSlot("interact")
                                    ms.ui.modal({
                                        title   = "Confirm Sub-item Bind",
                                        msg     = "Set \"" .. parentLabel .. " › " .. item.label .. "\" to:  " .. displayStr,
                                        confirm = "Confirm",
                                        cancel  = "Cancel",
                                    }, function(r)
                                        if r.confirmed then
                                            ms.subBinds[item.id] = parsed
                                            ms.saveSettings()
                                            ms.bind.rebind()
                                            ms.playSlot("update")
                                            hs.timer.doAfter(0.2, function()
                                                ms.alert(item.label .. " bound to: " .. displayStr, 3, true)
                                            end)
                                        else
                                            ms.alert("Rebind cancelled.", 2)
                                        end
                                    end)
                                else
                                    ms.alert("Could not read input. Try again.", 2)
                                end
                                return true
                            end)
                            capture:start()
                            cancelTimer = hs.timer.doAfter(15, function()
                                if capture then capture:stop(); capture = nil; ms.alert("Rebind timed out.", 2) end
                            end)
                        end
                    end

                    -- Section builder --
                    -- Builds a submenu for a given set of bind defs (main or optional).
                    -- Contains: toggle+state list, separator, Rebind submenu.

                    local function buildBindSection(defs)
                        local section = {}
                        local rebindSub = {}

                        for _, bind in ipairs(defs) do
                            local enabled = ms.binds[bind.id]
                            -- Toggle entry
                            table.insert(section, {
                                title = (enabled and "✓ " or "✗ ") .. bind.label .. "  " .. currentBindStr(bind.id),
                                fn = function()
                                    ms.binds[bind.id] = not ms.binds[bind.id]
                                    ms.saveSettings()
                                    ms.bind.rebind()
                                    ms.playSlot("update")
                                    ms.alert(bind.label .. ": " .. (ms.binds[bind.id] and "ON" or "OFF"), 2, true)
                                end
                            })
                            -- Sub-items indented under each bind
                            local subs = getSubItems(bind.id)
                            if #subs > 0 then
                                for _, entry in ipairs(subs) do
                                    local item = entry.item
                                    local mod  = ms.getMod(item.id)
                                    local modDisplay = mod and ("( " .. mod .. " )") or "( unset )"
                                    local subBindCfg = ms.independentBindsEnabled and ms.subBinds and ms.subBinds[item.id]
                                    local bindDisplay = subBindCfg and bindStr(subBindCfg) or modDisplay
                                    table.insert(section, {
                                        title    = indent(entry.depth + 1) .. "↳ " .. item.label .. "  " .. bindDisplay,
                                        disabled = true
                                    })
                                end
                            end
                            -- Rebind entry for this bind
                            table.insert(rebindSub, { title = "Rebind: " .. bind.label, fn = makeRebindFn(bind) })
                            table.insert(rebindSub, {
                                title = "Set Cooldown: " .. bind.label,
                                fn = function()
                                    ms.playSlot("interact")
                                    local codeDef = ms.registry._defs[bind.id]
                                    local codeDefault = (codeDef and codeDef.cooldown) or 1000
                                    local current = ms.cooldowns[bind.id] or codeDefault
                                    ms.ui.prompt({
                                        title   = "Set Cooldown",
                                        msg     = "Cooldown for \"" .. bind.label .. "\" (ms).\nDefault: " .. tostring(codeDefault) .. "ms  |  0 = no cooldown:",
                                        confirm = "Set",
                                        cancel  = "Cancel",
                                        default = tostring(current),
                                    }, function(r)
                                        if r.confirmed then
                                            local num = tonumber(r.value)
                                            if num and num >= 0 then
                                                ms.cooldowns[bind.id] = math.floor(num)
                                                ms.saveSettings()
                                                ms.bind.rebind()
                                                ms.playSlot("update")
                                                hs.timer.doAfter(0.2, function()
                                                    ms.alert(bind.label .. " cooldown: " .. tostring(math.floor(num)) .. "ms", 2, true)
                                                    ms.ui.refresh()
                                                end)
                                            else
                                                ms.alert("Invalid value. Enter a non-negative number.", 2)
                                            end
                                        end
                                    end)
                                end
                            })
                            table.insert(rebindSub, {
                                title = "Reset Bind: " .. bind.label,
                                fn = function()
                                    ms.bindConfig[bind.id] = nil
                                    ms.saveSettings()
                                    ms.bind.rebind()
                                    ms.playSlot("reset")
                                    ms.alert(bind.label .. " bind reset to default.", 2, true)
                                end
                            })
                            table.insert(rebindSub, {
                                title = "Reset Cooldown: " .. bind.label,
                                fn = function()
                                    ms.cooldowns[bind.id] = nil
                                    ms.saveSettings()
                                    ms.bind.rebind()
                                    ms.playSlot("reset")
                                    local def = ms.registry._defs[bind.id]
                                    local defMs = (def and def.cooldown) or 1000
                                    ms.alert(bind.label .. " cooldown reset to " .. tostring(defMs) .. "ms.", 2, true)
                                end
                            })
                        end

                        table.insert(section, { title = "-" })
                        table.insert(section, { title = "Rebind", menu = rebindSub })
                        table.insert(section, { title = "-" })
                        table.insert(section, { title = "Reset All to Default...", fn = function()
                            ms.playSlot("interact")
                            ms.ui.modal({
                                title   = "Reset All to Default",
                                msg     = "Reset all binds and cooldowns in this section to their default values?",
                                confirm = "Reset",
                                cancel  = "Cancel",
                            }, function(r)
                                if r.confirmed then
                                    for _, bind in ipairs(defs) do
                                        ms.bindConfig[bind.id] = nil
                                        ms.cooldowns[bind.id]  = nil
                                    end
                                    ms.saveSettings()
                                    ms.bind.rebind()
                                    ms.playSlot("reset")
                                    hs.timer.doAfter(0.2, function()
                                        ms.alert("All binds reset to default.", 3, true)
                                        ms.ui.refresh()
                                    end)
                                end
                            end)
                        end })

                        return section
                    end

                    -- Modifiers submenu --

                    local function buildModifiersSubmenu()
                        local sub = {}
                        local allDefs = {}
                        for _, d in ipairs(mainBindDefs)     do table.insert(allDefs, d) end
                        for _, d in ipairs(optionalBindDefs) do table.insert(allDefs, d) end

                        for _, bind in ipairs(allDefs) do
                            local subs = getSubItems(bind.id)
                            if #subs > 0 then
                                for _, entry in ipairs(subs) do
                                    local item = entry.item
                                    local mod  = ms.getMod(item.id)
                                    local modDisplay = mod and ("( " .. mod .. " )") or "( unset )"
                                    table.insert(sub, {
                                        title = indent(entry.depth) .. bind.label .. " › " .. item.label .. "  " .. modDisplay,
                                        fn    = makeModRebindFn(item, bind.label)
                                    })
                                end
                            end
                        end

                        table.insert(sub, { title = "-" })
                        table.insert(sub, { title = "Reset All Modifiers to Default", fn = function()
                            ms.playSlot("interact")
                            ms.ui.modal({
                                title   = "Reset Modifiers",
                                msg     = "Reset all modifiers to their default values?",
                                confirm = "Reset",
                                cancel  = "Cancel",
                            }, function(r)
                                if r.confirmed then
                                    ms.modConfig = {}
                                    ms.saveSettings()
                                    ms.playSlot("reset")
                                    hs.timer.doAfter(0.2, function()
                                        ms.alert("All modifiers reset to default.", 3, true)
                                        ms.ui.refresh()
                                    end)
                                end
                            end)
                        end })

                        return sub
                    end

                    -- Independent Binds submenu --

                                        local function buildIndependentBindsSubmenu()
                                            local sub = {}
                                            local ibEnabled = ms.independentBindsEnabled

                                            table.insert(sub, { title = "-" })

                        local allDefs = {}
                        for _, d in ipairs(mainBindDefs)     do table.insert(allDefs, d) end
                        for _, d in ipairs(optionalBindDefs) do table.insert(allDefs, d) end

                        for _, bind in ipairs(allDefs) do
                            local subs = getSubItems(bind.id)
                            if #subs > 0 then
                                for _, entry in ipairs(subs) do
                                    local item    = entry.item
                                    local subCfg  = ms.subBinds and ms.subBinds[item.id]
                                    local display
                                    if ibEnabled then
                                        display = subCfg and bindStr(subCfg) or "( unset )"
                                    else
                                        local parentCfg = ms.effectiveBind(bind.id)
                                        local mod = ms.getMod(item.id)
                                        local modPart = mod and (mod .. "+") or ""
                                        display = "( " .. modPart .. bindStr(parentCfg):gsub("[()]", ""):gsub("^%s+", ""):gsub("%s+$", "") .. " )"
                                    end
                                    table.insert(sub, {
                                        title    = indent(entry.depth) .. bind.label .. " › " .. item.label .. "  " .. display,
                                        disabled = not ibEnabled,
                                        fn       = makeSubBindFn(item, bind.label)
                                    })
                                end
                            end
                        end

                        table.insert(sub, { title = "-" })
                        table.insert(sub, { title = "Reset All Binds to Default", fn = function()
                            ms.playSlot("interact")
                            ms.ui.modal({
                                title   = "Reset Binds",
                                msg     = "Reset all binds to their default values?",
                                confirm = "Reset",
                                cancel  = "Cancel",
                            }, function(r)
                                if r.confirmed then
                                    ms.bindConfig = {}
                                    ms.subBinds   = {}
                                    ms.modConfig  = {}
                                    ms.saveSettings()
                                    ms.bind.rebind()
                                    ms.playSlot("reset")
                                    hs.timer.doAfter(0.2, function()
                                        ms.alert("All binds reset to default.", 3, true)
                                        ms.ui.refresh()
                                    end)
                                end
                            end)
                        end })

                        return sub
                    end

                    -- System submenu --

                    local function buildSystemSubmenu()
                        local sub = {}
                        local systemBindDefs = {
                            {label = "Enable/Disable Shortcuts", bind = "/  or  Return"},
                            {label = "Panic Button / Stop All",  bind = "Alt+F10"},
                            {label = "Get Roblox Window Info",   bind = "Ctrl+Shift+R"},
                            {label = "Reload Shortcuts",         bind = "Alt+["},
                            {label = "Reload Settings",          bind = "Alt+]"},
                            {label = "Open Menu",                bind = "Alt+P"},
                        }
                        for _, bind in ipairs(systemBindDefs) do
                            table.insert(sub, { title = bind.label .. "  " .. bind.bind, disabled = true })
                        end
                        return sub
                    end

                    local function buildSoundSubmenu()
                        -- Always re-index the sounds folder so newly imported files
                        -- appear in the picker without requiring a full reload.
                        ms._discoverSounds()
                        local sub = {}
                        table.insert(sub, {
                            title = (ms.soundEnabled and "✓" or "✗") .. " Sound Effects",
                            fn = function()
                                ms.soundEnabled = not ms.soundEnabled
                                ms.saveSettings()
                                ms.playSlot("update")
                                ms.alert("Sound Effects: " .. (ms.soundEnabled and "ON" or "OFF"), 2, true)
                            end
                        })
                        table.insert(sub, { title = "-" })
                        table.insert(sub, { title = "Volume: " .. tostring(ms.soundVolume or 100) .. "%", disabled = true })
                        table.insert(sub, {
                            title = "Set Volume...",
                            fn = function()
                                ms.playSlot("interact")
                                ms.ui.prompt({
                                    title   = "Sound Volume",
                                    msg     = "Enter volume (0-100):",
                                    confirm = "Set",
                                    cancel  = "Cancel",
                                    default = tostring(ms.soundVolume or 100),
                                }, function(r)
                                    if r.confirmed then
                                        local num = tonumber(r.value)
                                        if num and num >= 0 and num <= 100 then
                                            ms.soundVolume = math.floor(num)
                                            ms.saveSettings()
                                            ms.playSlot("update")
                                            hs.timer.doAfter(0.2, function()
                                                ms.alert("Volume set to " .. tostring(ms.soundVolume) .. "%", 2, true)
                                                ms.ui.refresh()
                                            end)
                                        else
                                            ms.alert("Invalid value. Must be 0-100.", 2)
                                        end
                                    end
                                end)
                            end
                        })
                        table.insert(sub, {
                            title = "Reset Volume",
                            fn = function()
                                ms.soundVolume = 100
                                ms.saveSettings()
                                ms.playSlot("reset")
                                ms.alert("Volume reset to 100%", 2, true)
                            end
                        })
                        table.insert(sub, { title = "-" })
                        table.insert(sub, {
                            title = "Import Sound Files...",
                            fn = function()
                                ms.playSlot("alert")
                                hs.focus()
                                -- Strip trailing slash before testing attributes
                                local slibDir = SoundLib:match("^(.-)[/\\]*$") or SoundLib
                                local result = hs.dialog.chooseFileOrFolder(
                                    "Select one or more sound files to add to your library",
                                    hs.fs.attributes(slibDir) and SoundLib or os.getenv("HOME"),
                                    true, false, true
                                )
                                -- chooseFileOrFolder may return string keys ("1","2"...) instead
                                -- of integer keys (1,2...) depending on the Hammerspoon version.
                                -- Normalize to a plain integer-indexed table so ipairs works.
                                local paths = {}
                                for _, v in pairs(result or {}) do
                                    if type(v) == "string" then table.insert(paths, v) end
                                end
                                if #paths == 0 then return end
                                result = paths

                                -- Ensure sounds directory exists
                                if not hs.fs.attributes(slibDir) then
                                    hs.execute("mkdir -p '" .. SoundLib .. "'")
                                end
                                if not hs.fs.attributes(slibDir) then
                                    ms.alert("Could not create sounds folder at:\n" .. SoundLib, 4); return
                                end

                                local function sq(s) return "'" .. s:gsub("'", "'\\''") .. "'" end

                                local added, failed = {}, {}
                                for _, srcPath in ipairs(result) do
                                    local filename   = srcPath:match("([^/]+)$")
                                    local importName = filename and (filename:match("^(.+)%.[^%.]+$") or filename)
                                    if not filename or not importName then
                                        table.insert(failed, srcPath); goto nextFile
                                    end
                                    local dst = SoundLib .. filename
                                    -- Skip copy when the file is already in the sounds folder.
                                    if srcPath ~= dst then
                                        -- Primary: io.open read+write (works for any path
                                        -- Hammerspoon has read access to).
                                        local copied = false
                                        local f = io.open(srcPath, "rb")
                                        if f then
                                            local content = f:read("*all"); f:close()
                                            local g = io.open(dst, "wb")
                                            if g then
                                                g:write(content); g:close()
                                                copied = true
                                            else
                                                print("ms: import: io.open write failed for " .. tostring(srcPath))
                                            end
                                        else
                                            print("ms: import: io.open read failed for " .. tostring(srcPath))
                                        end
                                        -- Fallback: shell cp (catches cases where io.open
                                        -- lacks access but the shell subprocess does).
                                        if not copied then
                                            local _, st = hs.execute("/bin/cp " .. sq(srcPath) .. " " .. sq(dst))
                                            copied = (st == true) or (hs.fs.attributes(dst) ~= nil)
                                            if not copied then
                                                print("ms: import: shell cp failed for " .. tostring(srcPath))
                                            end
                                        end
                                        if not copied then
                                            table.insert(failed, importName); goto nextFile
                                        end
                                    end
                                    ms.importedSounds = ms.importedSounds or {}
                                    ms.importedSounds[importName] = filename
                                    table.insert(added, importName)
                                    ::nextFile::
                                end

                                if #added > 0 then
                                    ms.saveSettings()
                                    ms._discoverSounds()
                                    ms._pendingReopenToSound = true
                                end
                                -- Do not call roblox:activate() here — the persistent menu
                                -- session (_wrapFns) owns the reopen. Activating Roblox
                                -- before the doAfter(0) reopen fires would stomp the
                                -- menu context and swallow the update sound.
                                hs.timer.doAfter(0.2, function()
                                    if #added > 0 then
                                        ms.playSlot("update")
                                    end
                                    if #added > 0 and #failed == 0 then
                                        local label = #added == 1
                                            and ("Sound \"" .. added[1] .. "\" added.")
                                            or  (#added .. " sounds added.")
                                        ms.alert(label, 3, true)
                                    elseif #added > 0 then
                                        ms.alert(#added .. " added, " .. #failed .. " failed.", 3, true)
                                    else
                                        ms.alert("Import failed — grant Hammerspoon Full Disk Access\nfor importing from outside ~/.hammerspoon.", 5)
                                    end
                                end)
                            end
                        })
                        table.insert(sub, { title = "-" })
                        -- Per-event sound selection
                        local slots = {
                            { id = "load",         label = "Load Complete"   },
                            { id = "alert",        label = "Alert / Notice"  },
                            { id = "enabled",      label = "Macros Enabled"  },
                            { id = "disabled",     label = "Macros Disabled" },
                            { id = "update",       label = "Setting Updated" },
                            { id = "reset",        label = "Setting Reset"   },
                            { id = "interact",     label = "Menu Interact"   },
                            { id = "hover",        label = "Menu Hover"      },
                            { id = "back",         label = "Menu Back"       },
                            { id = "settingsOpen", label = "Settings Open"   },
                            { id = "settingsClose",label = "Settings Close"  },
                        }
                        -- Sound list from discovered + imported files.
                        -- Reads from ms.sounds which is populated by _discoverSounds() at
                        -- the top of this function and includes everything in ms.importedSounds.
                        local soundNames = {}
                        for name in pairs(ms.sounds or {}) do table.insert(soundNames, name) end
                        table.sort(soundNames)
                        for _, slot in ipairs(slots) do
                            local assigned = ms.soundAssign and ms.soundAssign[slot.id]
                            local display  = assigned or "off"
                            local picker   = {}
                            -- None / off option
                            table.insert(picker, {
                                title = (not assigned and "✓ " or "  ") .. "None",
                                fn = function()
                                    ms.soundAssign = ms.soundAssign or {}
                                    ms.soundAssign[slot.id] = nil
                                    ms.saveSettings()
                                    ms.playSlot("update")
                                    ms.alert(slot.label .. " sound: off", 2, true)
                                end
                            })
                            table.insert(picker, { title = "-" })
                            if #soundNames == 0 then
                                table.insert(picker, { title = "(no sound files imported)", disabled = true })
                            else
                                for _, name in ipairs(soundNames) do
                                    table.insert(picker, {
                                        title = (assigned == name and "✓ " or "  ") .. name,
                                        fn = function()
                                            ms.soundAssign = ms.soundAssign or {}
                                            ms.soundAssign[slot.id] = name
                                            ms.saveSettings()
                                            ms.playSlot("update")
                                            ms.alert(slot.label .. " sound: " .. name, 2, true)
                                        end
                                    })
                                end
                            end
                            table.insert(sub, {
                                title = slot.label .. "  ( " .. display .. " )",
                                menu  = picker
                            })
                        end
                        return sub
                    end

                    local function buildTrackpadHoldSubmenu()
                    local sub = {}
                    local keys = ms.trackpadHoldKeys or { left = "n", right = "j" }

                    table.insert(sub, {
                        title = "Left Click Hold  ( " .. (keys.left or "unset") .. " )",
                        fn = function()
                            ms.alert("Rebinding: Left Click Hold\nCurrent: " .. (keys.left or "unset")
                                .. "\nPress a key. Backspace to reset to default ( n ). Escape to cancel.", 15)
                            local capture, cancelTimer
                            capture = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(event)
                                capture:stop(); capture = nil; cancelTimer:stop()
                                local keyCode = event:getKeyCode()
                                local flags = event:getFlags()
                                if keyCode == 53 and not (flags.cmd or flags.alt or flags.ctrl or flags.shift) then ms.alert("Rebind cancelled.", 2); return true end
                                local newKey = (keyCode == 51) and "n" or hs.keycodes.map[keyCode]
                                if newKey then
                                    ms.playSlot("interact")
                                    ms.ui.modal({
                                        title   = "Confirm Rebind",
                                        msg     = "Set Left Click Hold to:  " .. newKey,
                                        confirm = "Confirm",
                                        cancel  = "Cancel",
                                    }, function(r)
                                        if r.confirmed then
                                            ms.trackpadHoldKeys.left = newKey
                                            ms.saveSettings()
                                            ms.bind.rebind()
                                            ms.playSlot("update")
                                            hs.timer.doAfter(0.2, function()
                                                ms.alert("Left Click Hold set to: " .. newKey, 3, true)
                                                ms.ui.refresh()
                                            end)
                                        else
                                            ms.alert("Rebind cancelled.", 2)
                                        end
                                    end)
                                else
                                    ms.alert("Could not read key. Try again.", 2)
                                end
                                return true
                            end)
                            capture:start()
                            cancelTimer = hs.timer.doAfter(15, function()
                                if capture then capture:stop(); capture = nil; ms.alert("Rebind timed out.", 2) end
                            end)
                        end
                    })

                    table.insert(sub, {
                        title = "Right Click Hold  ( " .. (keys.right or "unset") .. " )",
                        fn = function()
                            ms.alert("Rebinding: Right Click Hold\nCurrent: " .. (keys.right or "unset")
                                .. "\nPress a key. Backspace to reset to default ( j ). Escape to cancel.", 15)
                            local capture, cancelTimer
                            capture = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(event)
                                capture:stop(); capture = nil; cancelTimer:stop()
                                local keyCode = event:getKeyCode()
                                local flags = event:getFlags()
                                if keyCode == 53 and not (flags.cmd or flags.alt or flags.ctrl or flags.shift) then ms.alert("Rebind cancelled.", 2); return true end
                                local newKey = (keyCode == 51) and "j" or hs.keycodes.map[keyCode]
                                if newKey then
                                    ms.playSlot("interact")
                                    ms.ui.modal({
                                        title   = "Confirm Rebind",
                                        msg     = "Set Right Click Hold to:  " .. newKey,
                                        confirm = "Confirm",
                                        cancel  = "Cancel",
                                    }, function(r)
                                        if r.confirmed then
                                            ms.trackpadHoldKeys.right = newKey
                                            ms.saveSettings()
                                            ms.bind.rebind()
                                            ms.playSlot("update")
                                            hs.timer.doAfter(0.2, function()
                                                ms.alert("Right Click Hold set to: " .. newKey, 3, true)
                                                ms.ui.refresh()
                                            end)
                                        else
                                            ms.alert("Rebind cancelled.", 2)
                                        end
                                    end)
                                else
                                    ms.alert("Could not read key. Try again.", 2)
                                end
                                return true
                            end)
                            capture:start()
                            cancelTimer = hs.timer.doAfter(15, function()
                                if capture then capture:stop(); capture = nil; ms.alert("Rebind timed out.", 2) end
                            end)
                        end
                    })

                    table.insert(sub, { title = "-" })
                    table.insert(sub, {
                        title = "Reset both to default  ( n / j )",
                        fn = function()
                            ms.playSlot("interact")
                            ms.ui.modal({
                                title   = "Reset Hold Keys",
                                msg     = "Reset both hold keys to defaults?  ( n / j )",
                                confirm = "Reset",
                                cancel  = "Cancel",
                            }, function(r)
                                if r.confirmed then
                                    ms.trackpadHoldKeys.left  = "n"
                                    ms.trackpadHoldKeys.right = "j"
                                    ms.saveSettings()
                                    ms.bind.rebind()
                                    ms.playSlot("reset")
                                    hs.timer.doAfter(0.2, function()
                                        ms.alert("Hold keys reset to default  ( n / j )", 3, true)
                                        ms.ui.refresh()
                                    end)
                                end
                            end)
                        end
                    })

                    return sub
                end

                    local function buildProfilesSubmenu()
                        local sub = {}
                        local currentName = ms.macroMeta and ms.macroMeta.name
                        local profiles = getProfiles()
                        if currentName then
                            table.insert(sub, { title = "Active:  " .. currentName, disabled = true })
                            table.insert(sub, { title = "-" })
                        end
                        if #profiles == 0 then
                            table.insert(sub, { title = "No saved profiles.", disabled = true })
                        else
                            for _, name in ipairs(profiles) do
                                local isCurrent = (name == (currentName and sanitizeName(currentName)))
                                table.insert(sub, {
                                    title    = (isCurrent and "✓ " or "") .. name,
                                    disabled = isCurrent,
                                    fn       = not isCurrent and function()
                                        ms.ui.modal({
                                            title   = "Switch Profile",
                                            msg     = "Switch to \"" .. name .. "\"?\n\nThe current profile will be archived and Hammerspoon will reload in 3 seconds.",
                                            confirm = "Switch",
                                            cancel  = "Cancel",
                                        }, function(r)
                                            if r.confirmed then switchProfile(name) end
                                        end)
                                    end or nil,
                                })
                            end
                        end
                        table.insert(sub, { title = "-" })
                        table.insert(sub, {
                            title = "Import Profile...",
                            fn    = function() importProfile() end,
                        })
                        return sub
                    end

                    -- Keybinds top-level submenu

                    local keybindSubmenu = {
                        { title = "Main",              menu = buildBindSection(mainBindDefs) },
                        { title = "Optional",          menu = buildBindSection(optionalBindDefs) },
                        { title = "System",            menu = buildSystemSubmenu() },
                        { title = "-" },
                        { title = (ms.independentBindsEnabled and "✓" or "✗") .. " Independent Binds", fn = function()
                            ms.independentBindsEnabled = not ms.independentBindsEnabled
                            -- When turning ON from the native menu, also clear conflicting sub binds.
                            if ms.independentBindsEnabled then
                                local function _bk(c)
                                    if not c then return nil end
                                    if c.type == "mouse" then return "mouse:" .. tostring(c.button) end
                                    local m = {}; for _, v in ipairs(c.mods or {}) do table.insert(m, v) end
                                    table.sort(m); return "key:" .. table.concat(m, ",") .. ":" .. (c.key or "")
                                end
                                local used = {}
                                for _, rid in ipairs(ms.registry._defList or {}) do
                                    local rd = ms.registry._defs[rid]
                                    if rd and not rd.sub then
                                        local k = _bk(ms.effectiveBind(rid)); if k then used[k] = rid end
                                    end
                                end
                                for sid, sc in pairs(ms.subBinds or {}) do
                                    local k = _bk(sc)
                                    if k then
                                        if used[k] then ms.subBinds[sid] = nil
                                        else used[k] = sid end
                                    end
                                end
                            end
                            ms.saveSettings()
                            ms.bind.rebind()
                            ms.playSlot("update")
                            ms.alert("Independent Binds: " .. (ms.independentBindsEnabled and "ON" or "OFF"), 2, true)
                        end },
                        { title = "Independent Binds", menu = buildIndependentBindsSubmenu() },
                        { title = "-" },
                        { title = "Modifiers",         menu = buildModifiersSubmenu() },
                    }

                    -- Settings submenu --

                    local function buildSettingsSubmenu()
                        return {
                            { title = (ms.trackpadMode and "\xe2\x9c\x93" or "\xe2\x9c\x97") .. " Trackpad / Pen Mode", fn = function()
                                ms.trackpadMode = not ms.trackpadMode
                                ms.saveSettings()
                                ms.bind.rebind()
                                ms.playSlot("update")
                                ms.alert("Trackpad / Pen Mode: " .. (ms.trackpadMode and "ON" or "OFF"), 2, true)
                            end },
                            { title = "Trackpad Hold Keys", menu = buildTrackpadHoldSubmenu() },
                            { title = "-" },
                            { title = (ms.socdEnabled and "\xe2\x9c\x93" or "\xe2\x9c\x97") .. " SOCD Cleaning", fn = function()
                                ms.socdEnabled = not ms.socdEnabled
                                ms.saveSettings()
                                ms.socdApply()
                                ms.playSlot("update")
                                ms.alert("SOCD Cleaning: " .. (ms.socdEnabled and "ON" or "OFF"), 2, true)
                            end },
                            { title = "SOCD Mode: " .. (ms.socdMode == "lastWins" and "Last Input Wins" or ms.socdMode == "neutral" and "Neutral" or "First Input Wins"), menu = {
                                { title = (ms.socdMode == "lastWins" and "\xe2\x9c\x93" or "\xe2\x9c\x97") .. " Last Input Wins", fn = function()
                                    ms.socdMode = "lastWins"
                                    ms.saveSettings()
                                    ms.playSlot("update")
                                    ms.alert("SOCD Mode: Last Input Wins", 2, true)
                                end },
                                { title = (ms.socdMode == "neutral" and "\xe2\x9c\x93" or "\xe2\x9c\x97") .. " Neutral", fn = function()
                                    ms.socdMode = "neutral"
                                    ms.saveSettings()
                                    ms.playSlot("update")
                                    ms.alert("SOCD Mode: Neutral", 2, true)
                                end },
                                { title = (ms.socdMode == "firstWins" and "\xe2\x9c\x93" or "\xe2\x9c\x97") .. " First Input Wins", fn = function()
                                    ms.socdMode = "firstWins"
                                    ms.saveSettings()
                                    ms.playSlot("update")
                                    ms.alert("SOCD Mode: First Input Wins", 2, true)
                                end },
                            }},
                            { title = "-" },
                            { title = "Camera Sensitivity: " .. tostring(CUR_CAM_SENS), disabled = true },
                            { title = "Set Sensitivity...", fn = function()
                                ms.playSlot("interact")
                                ms.ui.prompt({
                                    title   = "Camera Sensitivity",
                                    msg     = "Enter your Roblox camera sensitivity:",
                                    confirm = "Set",
                                    cancel  = "Cancel",
                                    default = tostring(CUR_CAM_SENS),
                                }, function(r)
                                    if r.confirmed then
                                        local num = tonumber(r.value)
                                        if num and num >= 0.1 and num <= 4 then
                                            CUR_CAM_SENS = num
                                            ms.saveSettings()
                                            ms.cam.updateMultiplier()
                                            ms.playSlot("update")
                                            ms.alert("Sensitivity set to " .. tostring(num), 2, true)
                                            ms.ui.refresh()
                                        else
                                            ms.alert("Invalid value. Must be a number between 0.1 and 4.", 2)
                                        end
                                    end
                                end)
                            end },
                            { title = "Reset Sensitivity", fn = function()
                                local default = (ms.macroDefaults and ms.macroDefaults.sensitivity) or 1.5
                                CUR_CAM_SENS = default
                                ms.saveSettings()
                                ms.cam.updateMultiplier()
                                ms.playSlot("reset")
                                ms.alert("Sensitivity reset to " .. tostring(default), 2, true)
                            end },
                            { title = "-" },
                            { title = "Sound", menu = buildSoundSubmenu() },
                            { title = "-" },
                            { title = "Keybinds", menu = keybindSubmenu },
                            { title = "-" },
                            { title = "Save as Default...", fn = function()
                                ms.playSlot("interact")
                                ms.ui.modal({
                                    title   = "Save as Default",
                                    msg     = "Save current settings as the new default?\nThe existing default will be archived.",
                                    confirm = "Save",
                                    cancel  = "Cancel",
                                }, function(r)
                                    if r.confirmed then
                                        ms.saveDefault()
                                        ms.playSlot("update")
                                        ms.ui.refresh()
                                    end
                                end)
                            end },
                            { title = "Reset to Default...", fn = function()
                                ms.playSlot("interact")
                                ms.ui.modal({
                                    title   = "Reset to Default",
                                    msg     = "Reset all settings to the saved default?\nCurrent settings will be overwritten.",
                                    confirm = "Reset",
                                    cancel  = "Cancel",
                                }, function(r)
                                    if r.confirmed then
                                        if ms.resetToDefault() then
                                            ms.playSlot("reset")
                                            hs.timer.doAfter(0.2, function()
                                                ms.alert("Settings reset to default.", 3, true)
                                                ms.ui.refresh()
                                            end)
                                        end
                                    end
                                end)
                            end },
                        }
                    end

                    -- Developer submenu --

                    local function buildDeveloperSubmenu()
                        -- Check system integrity once at menu-build time so the Trust item
                        -- can be greyed out immediately if the file is already trusted.
                        local _trusted = (ms.integrity.check() == "trusted")
                        return {
                            { title = "Debug Roblox", fn = function()
                                ms.playSlot("interact")
                                ms.debugRoblox()
                            end },
                            { title = "Edit Macros", fn = function()
                                ms.playSlot("interact")
                                os.execute("open " .. os.getenv("HOME") .. "/.hammerspoon/ms_macros.lua")
                            end },
                            { title = "-" },
                            {
                                title    = _trusted and "\xe2\x9c\x93 Trust Current Version" or "Trust Current Version...",
                                disabled = _trusted or nil,
                                fn       = not _trusted and function()
                                    ms.playSlot("interact")
                                    local status, cur = ms.integrity.check()
                                    local prompt
                                    if status == "uninitialized" then
                                        prompt = "Seal this ms_core.lua as the trusted baseline?\nHash: " .. (cur and cur:sub(1, 16) or "?") .. "\xe2\x80\xa6"
                                    else
                                        prompt = "Hash mismatch detected. Trust the CURRENT (possibly modified) version?\nHash: " .. (cur and cur:sub(1, 16) or "?") .. "\xe2\x80\xa6"
                                    end
                                    ms.ui.modal({
                                        title   = "Trust Current Version",
                                        msg     = prompt,
                                        confirm = "Trust",
                                        cancel  = "Cancel",
                                    }, function(r)
                                        if r.confirmed then ms.integrity.trustCurrent() end
                                    end)
                                end or nil,
                            },
                        }
                    end

                    -- Help submenu --

                    local function buildHelpSubmenu()
                        return {
                            { title = "About", fn = function()
                                ms.playSlot("interact")
                                ms.alert("Hammerspoon mudscript Utility Library\nBy: mudbourn — https://mudbourn.info", 6)
                                if ms.macroMeta then
                                    local msg = "\"" .. (ms.macroMeta.name or "Unknown Macro Pack") .. "\"\n"
                                    if ms.macroMeta.author then msg = msg .. "By: " .. ms.macroMeta.author end
                                    if ms.macroMeta.website then msg = msg .. " \xe2\x80\x94 " .. ms.macroMeta.website end
                                    ms.alert(msg, 10)
                                end
                            end },
                            { title = "Documentation", fn = function()
                                ms.playSlot("interact")
                                hs.urlevent.openURL(ms._docsURL .. "?platform=mac")
                            end },
                            { title = "-" },
                            { title = "Check System Integrity", fn = function()
                                ms.playSlot("interact")
                                local status, cur, trusted = ms.integrity.check()
                                if status == "trusted" then
                                    ms.alert("\xe2\x9c\x93 ms_core.lua matches trusted hash.\n" .. (cur and cur:sub(1, 16) or "?") .. "\xe2\x80\xa6", 5, true)
                                elseif status == "mismatch" then
                                    ms.alert("\xe2\x9a\xa0 Hash mismatch!\nExpected: " .. (trusted and trusted:sub(1, 16) or "?") .. "\xe2\x80\xa6\nCurrent:  " .. (cur and cur:sub(1, 16) or "?") .. "\xe2\x80\xa6\n\nVerify the change or use Trust Current Version.", 9)
                                else
                                    ms.alert("No trusted hash on record.\nUse \"Trust Current Version\" to seed trust.", 5)
                                end
                            end },
                            { title = "Check for Update...", fn = function()
                                if not ms._updateManifestURL or ms._updateManifestURL == "" then
                                    ms.alert("No update URL configured.\nSet ms._updateManifestURL in ms_core.lua.", 5)
                                    return
                                end
                                ms.playSlot("interact")
                                ms.ui.modal({
                                    title   = "Check for Update",
                                    msg     = "Download and apply the latest ms_core.lua from GitHub?\n\nThe current file will be backed up to backups/ and Hammerspoon will reload.",
                                    confirm = "Update",
                                    cancel  = "Cancel",
                                }, function(r)
                                    if r.confirmed then ms.integrity.update() end
                                end)
                            end },
                            { title = "Macro Info", fn = function()
                                ms.playSlot("interact")
                                local path = os.getenv("HOME") .. "/.hammerspoon/ms_macro_info.txt"
                                local f = io.open(path, "w")
                                if f then
                                    f:write("Macro Modifiers & Usage\n")
                                    f:write("=======================\n\n")
                                    local function writeSection(defs)
                                        for _, bind in ipairs(defs) do
                                            if bind.info then
                                                f:write(bind.label .. "\n")
                                                f:write(string.rep("-", #bind.label) .. "\n")
                                                f:write(bind.info .. "\n")
                                            end
                                        end
                                    end
                                    writeSection(mainBindDefs)
                                    writeSection(optionalBindDefs)
                                    f:close()
                                    os.execute("open " .. path)
                                end
                            end },
                        }
                    end

                    -- Main menu --

                    local _menuItems = {
                        { title = "Macros: " .. (BindValidity == 1 and "ENABLED" or "DISABLED"), disabled = true },
                        { title = "-" },
                        { title = "Enable Macros ( Enter )",  fn = function() ms.setMacros(1) end },
                        { title = "Disable Macros ( / )",     fn = function() ms.setMacros(0) end },
                        { title = "-" },
                        { title = "Reload Macros ( alt+[ )",   fn = function() hs.reload() end },
                        { title = "Reload Settings ( alt+] )", fn = function() ms.reloadSettings() end },
                        { title = "-" },
                        { title = "Profiles",  menu = buildProfilesSubmenu() },
                        { title = "Settings",  menu = buildSettingsSubmenu() },
                        { title = "Developer", menu = buildDeveloperSubmenu() },
                        { title = "Help",       menu = buildHelpSubmenu() },
                    }
                    -- Wrap every fn so selecting an item reopens the menu,
                    -- unless ms._menuOpen was cleared (Escape / Alt+P to close).
                    local function _wrapFns(items)
                        for _, item in ipairs(items or {}) do
                            if item.fn then
                                local orig = item.fn
                                item.fn = function()
                                    ms._menuFnFired = true
                                    orig()
                                    if ms._menuOpen then
                                        hs.timer.doAfter(0, function()
                                            if ms._menuOpen then
                                                ms._menuFnFired = false
                                                ms.playSlot("settingsOpen")
                                                ms._menuHoverStart()
                                                ms._menuVisible = true
                                                ms._menubar:popupMenu(ms._biasedMenuPt(ms._lastMenuPoint))
                                                ms._menuVisible = false
                                                ms._menuHoverStop()
                                                if not ms._menuFnFired then
                                                    ms.playSlot("settingsClose")
                                                end
                                            end
                                        end)
                                    end
                                end
                            end
                            if item.menu then _wrapFns(item.menu) end
                        end
                    end
                    -- If an import just completed, show the Sound submenu directly
                    -- as the top-level menu on this one reopen instead of the full menu.
                    if ms._pendingReopenToSound then
                        ms._pendingReopenToSound = false
                        local soundItems = buildSoundSubmenu()
                        if ms._menuOpen then _wrapFns(soundItems) end
                        return soundItems
                    end
                    if ms._menuOpen then _wrapFns(_menuItems) end
                    return _menuItems
                end
            -- END Settings Menu --

            -- Icon click opens the webview Settings panel (Section 10) instead of the
            -- legacy NSMenu dropdown built above. ms.ui is defined later in the file,
            -- but that's fine — this callback only runs once the user actually clicks
            -- the icon, by which point the whole config has finished loading.
            ms._menubar:setClickCallback(function() ms.ui.toggle() end)
        -- END --

        -- 3. Keyboard Actions --
            local hskeymap = {
                left = 123, right = 124, down = 125, up = 126,
                shift = 56, lshift = 56, rshift = 62,
                ctrl = 59, lctrl = 59, rctrl = 61,
                alt = 58, lalt = 58, ralt = 61,
                cmd = 55, lcmd = 55, rcmd = 54,
                f1 = 122, f2 = 120, f3 = 99, f4 = 118,
                f5 = 96, f6 = 97, f7 = 98, f8 = 100,
                f9 = 101, f10 = 109, f11 = 103, f12 = 111,
                rightclick = 999
            }

            local function getCode(key)
                if type(key) == "number" then return key end
                local k = tostring(key):lower()
                return hskeymap[k] or hs.keycodes.map[k]
            end

            ms.keystate = function(...)
                local args = { ... }
                -- If the second argument is true, the first argument is treated as a raw keycode
                -- rather than a key name, bypassing getCode() lookup.
                if args[2] == true then
                    local code = args[1]
                    return code and ms.keytrack[code] == true or false
                end
                for _, key in ipairs(args) do
                    local code = getCode(key)
                    if code and ms.keytrack[code] then
                        return true
                    end
                end
                return false
            end

            -- Track previous modifier flag state so flagsChanged can emit
            -- discrete down/up events to the input monitor.
            local _prevModFlags = { shift = false, alt = false, ctrl = false, cmd = false }

            ms._keyListener = hs.eventtap.new({
                hs.eventtap.event.types.keyDown,
                hs.eventtap.event.types.keyUp,
                hs.eventtap.event.types.flagsChanged
            }, function(event)
                local isSynthetic = event:getProperty(hs.eventtap.event.properties.eventSourceUserData) == 999
                if isSynthetic then return false end

                local type = event:getType()
                local keyCode = event:getKeyCode()
                local flags = event:getFlags()

                if type == hs.eventtap.event.types.flagsChanged then
                    ms.keytrack[56] = flags.shift
                    ms.keytrack[62] = flags.shift
                    ms.keytrack[58] = flags.alt
                    ms.keytrack[59] = flags.ctrl
                    ms.keytrack[61] = flags.ctrl
                    ms.keytrack[55] = flags.cmd
                    ms.keytrack[54] = flags.cmd
                    -- Emit discrete down/up events to the input monitor for each
                    -- modifier that changed state.
                    if ms.dev and ms.dev._onKeyEvent then
                        local now = {
                            shift = flags.shift and true or false,
                            alt   = flags.alt   and true or false,
                            ctrl  = flags.ctrl  and true or false,
                            cmd   = flags.cmd   and true or false,
                        }
                        local modNames = {
                            { k="shift", code=56, name="shift" },
                            { k="alt",   code=58, name="alt"   },
                            { k="ctrl",  code=59, name="ctrl"  },
                            { k="cmd",   code=55, name="cmd"   },
                        }
                        for _, m in ipairs(modNames) do
                            if now[m.k] ~= _prevModFlags[m.k] then
                                pcall(ms.dev._onKeyEvent, m.code, m.name, now[m.k])
                            end
                        end
                        _prevModFlags = now
                    end
                    return false
                end

                if type == hs.eventtap.event.types.keyDown then
                    local isRepeat = ms.keytrack[keyCode] == true
                    ms.keytrack[keyCode] = true
                    if not isRepeat and ms.dev then
                        pcall(ms.dev._onKeyEvent, keyCode, hs.keycodes.map[keyCode], true)
                    end
                    -- Toggle macro state via in-game keys ( / = disable, Enter = enable ).
                    if not isRepeat and ms._robloxActive then
                        if     keyCode == 44 then ms.setMacros(0)
                        elseif keyCode == 36 then ms.setMacros(1) end
                    end
                    if not isRepeat and ms._keyBindings then
                        ms._currentFlags = flags
                        for _, binding in pairs(ms._keyBindings) do
                            if binding and binding.keyCode == keyCode then
                                local modsMatch = true
                                if binding.mods.cmd   and not flags.cmd   then modsMatch = false end
                                if binding.mods.alt   and not flags.alt   then modsMatch = false end
                                if binding.mods.ctrl  and not flags.ctrl  then modsMatch = false end
                                if binding.mods.shift and not flags.shift then modsMatch = false end
                                if modsMatch then
                                    if BindValidity == 1 then
                                        if binding.pressFn then
                                            local co = coroutine.create(binding.pressFn)
                                            local ok, err = coroutine.resume(co)
                                            if not ok then print("ms.key error: " .. tostring(err)) end
                                        end
                                        return binding.swallow
                                    else
                                        return false
                                    end
                                end
                            end
                        end
                    end
                elseif type == hs.eventtap.event.types.keyUp then
                    ms.keytrack[keyCode] = false
                    if ms.dev then
                        pcall(ms.dev._onKeyEvent, keyCode, hs.keycodes.map[keyCode], false)
                    end
                    if ms._keyBindings then
                        for _, binding in pairs(ms._keyBindings) do
                            if binding and binding.keyCode == keyCode then
                                local modsMatch = true
                                if binding.mods.cmd   and not flags.cmd   then modsMatch = false end
                                if binding.mods.alt   and not flags.alt   then modsMatch = false end
                                if binding.mods.ctrl  and not flags.ctrl  then modsMatch = false end
                                if binding.mods.shift and not flags.shift then modsMatch = false end
                                if modsMatch then
                                    if BindValidity == 1 then
                                        if binding.releaseFn then
                                            local co = coroutine.create(binding.releaseFn)
                                            local ok, err = coroutine.resume(co)
                                            if not ok then print("ms.key error: " .. tostring(err)) end
                                        end
                                        return binding.swallow
                                    else
                                        return false
                                    end
                                end
                            end
                        end
                    end
                end

                return false
            end):start()

            ms.press = function(key, mods, hidinject)
                local keyCode = getCode(key)
                if not keyCode then
                    print("Error: Could not find keyCode for " .. tostring(key))
                    return
                end
                ms._macroHeldKeys[keyCode] = { mods = mods or {}, hidinject = hidinject }
                local ev = hs.eventtap.event.newKeyEvent(mods or {}, keyCode, true)
                if hidinject then
                    local app = hs.application.get("Roblox")
                    if app then ev:post(app); return end
                end
                ev:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                ev:post()
            end

            ms.release = function(key, mods, hidinject)
                local keyCode = getCode(key)
                if not keyCode then return end
                ms._macroHeldKeys[keyCode] = nil
                local ev = hs.eventtap.event.newKeyEvent(mods or {}, keyCode, false)
                if hidinject then
                    local app = hs.application.get("Roblox")
                    if app then ev:post(app); return end
                end
                ev:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                ev:post()
            end

            ms.type = function(key, mods, hidinject)
                ms.press(key, mods, hidinject)
                ms.wait(15)
                ms.release(key, mods, hidinject)
            end

            ms.key = function(mods, key, swallow, pressFn, releaseFn)
                local keyCode = getCode(key)
                if not keyCode then
                    print("Error: Could not find keyCode for " .. tostring(key))
                    return
                end

                local modSet = {}
                for _, m in ipairs(mods or {}) do modSet[m] = true end

                local binding = {
                    keyCode = keyCode,
                    mods = modSet,
                    swallow = swallow,
                    pressFn = pressFn,
                    releaseFn = releaseFn,
                }

                table.insert(ms._keyBindings, binding)

                return { delete = function()
                    for i, b in ipairs(ms._keyBindings) do
                        if b == binding then
                            table.remove(ms._keyBindings, i)
                            break
                        end
                    end
                end}
            end
        -- END --

        -- 4. Mouse Actions --


            ms.scroll = function(direction, clicks)
                clicks = clicks or 1
                local dx, dy = 0, 0
                if direction == "up" then dy = clicks
                elseif direction == "down" then dy = -clicks
                elseif direction == "left" then dx = -clicks
                elseif direction == "right" then dx = clicks
                end
                local ev = hs.eventtap.event.newScrollEvent({dx, dy}, {}, "pixel")
                ev:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                ev:post()
            end

            ms.mouse = function(button, swallow, clickFn, hidinject)
                if not ms._mouseListener then
                    ms._mouseCallbacks = {}
                    local types = {
                        hs.eventtap.event.types.leftMouseDown,
                        hs.eventtap.event.types.leftMouseUp,
                        hs.eventtap.event.types.rightMouseDown,
                        hs.eventtap.event.types.rightMouseUp,
                        hs.eventtap.event.types.otherMouseDown,
                        hs.eventtap.event.types.otherMouseUp,
                    }
                    ms._mouseListener = hs.eventtap.new(types, function(event)
                        local type = event:getType()
                        local b
                        local isDown

                        if type == hs.eventtap.event.types.leftMouseDown then
                            b = 0; isDown = true
                        elseif type == hs.eventtap.event.types.leftMouseUp then
                            b = 0; isDown = false
                        elseif type == hs.eventtap.event.types.rightMouseDown then
                            b = 1; isDown = true
                            ms.keytrack[999] = true
                        elseif type == hs.eventtap.event.types.rightMouseUp then
                            b = 1; isDown = false
                            ms.keytrack[999] = false
                        elseif type == hs.eventtap.event.types.otherMouseDown then
                            b = event:getProperty(hs.eventtap.event.properties.mouseEventButtonNumber)
                            isDown = true
                        else -- otherMouseUp
                            b = event:getProperty(hs.eventtap.event.properties.mouseEventButtonNumber)
                            isDown = false
                        end

                        -- Always log to the input monitor regardless of BindValidity.
                        if ms.dev and ms.dev._onMouseEvent then
                            local _mp = hs.mouse.absolutePosition()
                            pcall(ms.dev._onMouseEvent, b, isDown,
                                math.floor(_mp.x), math.floor(_mp.y))
                        end

                        if BindValidity ~= 1 then return false end

                        -- Only fire macro callbacks on down events.
                        if not isDown then return false end

                        local callbackData = ms._mouseCallbacks[b]
                        if callbackData then
                            if callbackData.swallow and callbackData.hidinject then
                                local app = hs.application.get("Roblox")
                                if app then event:copy():post(app) end
                            end
                            local co = coroutine.create(callbackData.fn)
                            local ok, err = coroutine.resume(co)
                            if not ok then
                                print("ms.mouse callback error: " .. tostring(err))
                            end
                            return callbackData.swallow
                        end

                        return false
                    end):start()
                end
                ms._mouseCallbacks[button] = { fn = clickFn, swallow = swallow, hidinject = hidinject }
            end





            -- Unified mouse action function. Replaces ms.click, ms.clickMP, and ms.rawMouseButton.
            -- Window-relative coordinates are in REF space (1680×1044) and scaled to the actual
            -- window size by default. Pass the global Unscaled flag between the reference and the
            -- first coordinate to use raw pixel window offsets instead:
            --
            --   ms.Mouse(Click,  Left,  WindowTL, 900, 660)          -- REF-space (scaled)
            --   ms.Mouse(Click,  Left,  WindowTL, Unscaled, 445, 37) -- raw pixels from TL
            --   ms.Mouse(Drag,   Left,  Absolute, 100, 100, 300, 300)
            --   ms.Mouse(Move,   Left,  Mouse,    0,   0)
            ms.Mouse = function(operation, button, reference, ...)
                local OPS  = { Move=true, Click=true, DoubleClick=true,
                               TripleClick=true, Drag=true, Press=true, Release=true }
                local BTNS = { Left=0, Right=1, Center=2, Button4=3, Button5=4 }
                local REFS = {
                    Absolute=true,   Mouse=true,
                    WindowTL=true,   WindowTR=true,  WindowBL=true,
                    WindowBR=true,   WindowCenter=true,
                    ScreenTL=true,   ScreenTR=true,  ScreenBL=true,
                    ScreenBR=true,   ScreenCenter=true,
                }
                assert(OPS[operation],     "ms.Mouse: unknown operation '"  .. tostring(operation)  .. "'")
                assert(BTNS[button] ~= nil, "ms.Mouse: unknown button '"      .. tostring(button)     .. "'")
                assert(REFS[reference],    "ms.Mouse: unknown reference '"   .. tostring(reference)  .. "'")

                -- Unpack trailing args: [Unscaled,] x1, y1 [, x2, y2 [, hidinject]]
                -- The optional Unscaled boolean flag is detected by type at position 1.
                local unscaled, x1, y1, x2, y2, hidinject
                local _a, _b, _c, _d, _e, _f = ...
                if type(_a) == "boolean" then
                    unscaled                   = _a
                    x1, y1, x2, y2, hidinject = _b, _c, _d, _e, _f
                else
                    unscaled                   = false
                    x1, y1, x2, y2, hidinject = _a, _b, _c, _d, _e
                end

                local btn  = BTNS[button]
                local _app = hidinject and hs.application.get("Roblox") or nil

                -- Resolve (x, y) to absolute screen pixel coordinates.
                local function resolve(x, y) return ms.resolvePoint(x, y, reference, unscaled) end

                local ax1, ay1 = resolve(x1, y1)
                local ax2, ay2
                if x2 ~= nil and y2 ~= nil then
                    ax2, ay2 = resolve(x2, y2)
                else
                    ax2, ay2 = ax1, ay1
                end
                local pos1 = { x = ax1, y = ay1 }
                local pos2 = { x = ax2, y = ay2 }

                -- Event types for this button.
                local downT, upT, dragT
                if btn == 0 then
                    downT = hs.eventtap.event.types.leftMouseDown
                    upT   = hs.eventtap.event.types.leftMouseUp
                    dragT = hs.eventtap.event.types.leftMouseDragged
                elseif btn == 1 then
                    downT = hs.eventtap.event.types.rightMouseDown
                    upT   = hs.eventtap.event.types.rightMouseUp
                    dragT = hs.eventtap.event.types.rightMouseDragged
                else
                    downT = hs.eventtap.event.types.otherMouseDown
                    upT   = hs.eventtap.event.types.otherMouseUp
                    dragT = hs.eventtap.event.types.otherMouseDragged
                end

                local function post(evType, pos)
                    local ev = hs.eventtap.event.newMouseEvent(evType, pos)
                    if btn >= 2 then
                        ev:setProperty(hs.eventtap.event.properties.mouseEventButtonNumber, btn)
                    end
                    if _app then ev:post(_app)
                    else
                        ev:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                        ev:post()
                    end
                end

                local function moveTo(pos)
                    local mv = hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.mouseMoved, pos)
                    if _app then mv:post(_app)
                    else
                        mv:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                        mv:post()
                    end
                    hs.mouse.absolutePosition(pos)
                end

                local function singleClick(pos)
                    post(downT, pos); ms.wait(50); post(upT, pos)
                end

                if     operation == "Move"        then moveTo(pos1)
                elseif operation == "Click"       then moveTo(pos1); ms.wait(50); singleClick(pos1)
                elseif operation == "DoubleClick" then
                    moveTo(pos1); ms.wait(50)
                    singleClick(pos1); ms.wait(50); singleClick(pos1)
                elseif operation == "TripleClick" then
                    moveTo(pos1); ms.wait(50)
                    for i = 1, 3 do singleClick(pos1); if i < 3 then ms.wait(50) end end
                elseif operation == "Drag"        then
                    moveTo(pos1); ms.wait(50)
                    post(downT, pos1); ms.wait(50)
                    post(dragT, pos2)
                    hs.mouse.absolutePosition(pos2)
                    ms.wait(50)
                    post(upT, pos2)
                elseif operation == "Press"       then
                    moveTo(pos1); post(downT, pos1)
                    ms._macroHeldButtons[btn] = { upT = upT, pos = pos1, app = _app }
                elseif operation == "Release"     then
                    post(upT, pos1)
                    ms._macroHeldButtons[btn] = nil
                end
            end
        -- END --

        -- 5. Delay --
            ms.wait = function(ms_time)
                local co = coroutine.running()
                if co then
                    local ctx = ms._coroContext[co]  -- capture context at yield time
                    -- When the watcher is open, log significant waits (>= 50 ms) as step
                    -- entries so users can see execution progress and where a macro stalls.
                    if ms_time >= 50 and ms.dev and ms.dev._watcherPanel then
                        local _label = (ctx and ctx.label) or "macro"
                        local ok2, j2 = pcall(hs.json.encode, {
                            type = "step",
                            ts   = os.time(),
                            msg  = "[" .. _label .. "] wait " .. tostring(ms_time) .. "ms",
                        })
                        if ok2 then
                            pcall(function()
                                ms.dev._watcherPanel:evaluateJavaScript("appendEntry(" .. j2 .. ")")
                            end)
                        end
                    end
                    hs.timer.doAfter(ms_time / 1000, function()
                        -- Don't resume a coroutine whose macro has been cancelled.
                        if ctx and ctx.cancelled then return end
                        local ok, err = coroutine.resume(co)
                        if not ok then
                            print("ms.wait resume error: " .. tostring(err))
                        end
                        if coroutine.status(co) == "dead" then
                            ms._coroContext[co] = nil
                            if ctx then ms._activeContexts[ctx] = nil end
                        end
                    end)
                    coroutine.yield()
                else
                    -- Intentional blocking fallback for the rare case where ms.wait is called
                    -- outside a coroutine. This is NOT dead code — it is a deliberate safety net.
                    -- Macro authors using ms.fn()-wrapped functions will never reach this branch
                    -- in normal usage, since ms.fn() always guarantees a coroutine context.
                    hs.timer.usleep(ms_time * 1000)
                end
            end
        -- END --

        -- 6. Resolution & Window Scaling --
            ms.getRobloxWin = function()
                local app = hs.application.get("Roblox")
                if not app then return nil end
                local ok, win = pcall(function() return app:mainWindow() end)
                return (ok and win) or nil
            end

            ms.winCenter = function()
                local win = ms.getRobloxWin() or hs.window.focusedWindow()
                if not win then return 0, 0 end
                local f = win:frame()
                return f.x + (f.w / 2), f.y + (f.h / 2)
            end

            ms.getScaled = function(targetX, targetY)
                local win = ms.getRobloxWin() or hs.window.focusedWindow()
                if not win then
                    local screen = hs.screen.mainScreen():frame()
                    return targetX * (screen.w / REF_W), targetY * (screen.h / REF_H)
                end
                local f = win:frame()
                local finalX = f.x + (targetX * (f.w / REF_W))
                local finalY = f.y + (targetY * (f.h / REF_H))
                return finalX, finalY
            end

            -- Converts (x, y) in the given reference space to absolute screen coordinates.
            -- Shared by ms.Mouse and ms.pixelColor so the coordinate systems are identical.
            -- Reference constants: Absolute, Mouse, WindowTL/TR/BL/BR/Center, ScreenTL/TR/BL/BR/Center.
            ms.resolvePoint = function(x, y, reference, unscaled)
                local win = ms.getRobloxWin() or hs.window.focusedWindow()
                local f   = win and win:frame()
                local s   = hs.screen.mainScreen():frame()
                if     reference == "Absolute"     then return x, y
                elseif reference == "Mouse"        then
                    local p = hs.mouse.absolutePosition()
                    return p.x + x, p.y + y
                elseif reference == "WindowTL"     then
                    if not f then return x, y end
                    if unscaled then return f.x + x,         f.y + y         end
                    return f.x + (x * f.w / REF_W), f.y + (y * f.h / REF_H)
                elseif reference == "WindowTR"     then
                    if not f then return x, y end
                    if unscaled then return f.x + f.w + x,   f.y + y         end
                    return f.x + f.w + (x * f.w / REF_W), f.y + (y * f.h / REF_H)
                elseif reference == "WindowBL"     then
                    if not f then return x, y end
                    if unscaled then return f.x + x,         f.y + f.h + y   end
                    return f.x + (x * f.w / REF_W), f.y + f.h + (y * f.h / REF_H)
                elseif reference == "WindowBR"     then
                    if not f then return x, y end
                    if unscaled then return f.x + f.w + x,   f.y + f.h + y   end
                    return f.x + f.w + (x * f.w / REF_W), f.y + f.h + (y * f.h / REF_H)
                elseif reference == "WindowCenter" then
                    if not f then return x, y end
                    if unscaled then return f.x + f.w/2 + x, f.y + f.h/2 + y end
                    return f.x + f.w/2 + (x * f.w / REF_W), f.y + f.h/2 + (y * f.h / REF_H)
                elseif reference == "ScreenTL"     then return s.x + x,         s.y + y
                elseif reference == "ScreenTR"     then return s.x + s.w + x,   s.y + y
                elseif reference == "ScreenBL"     then return s.x + x,         s.y + s.h + y
                elseif reference == "ScreenBR"     then return s.x + s.w + x,   s.y + s.h + y
                elseif reference == "ScreenCenter" then return s.x + s.w/2 + x, s.y + s.h/2 + y
                end
                return x, y
            end

            ms.debugRoblox = function()
                local win = ms.getRobloxWin() or hs.window.find("Roblox")
                if win then
                    local f = win:frame()
                    local screen = win:screen():frame()
                    local currentRatio = f.w / f.h
                    local currentSens = CUR_CAM_SENS or 1.5
                    local output = {
                        "--- ROBLOX DEBUG INFO ---",
                        string.format("Window Title: %s", win:title()),
                        string.format("Resolution (Points): %.1f x %.1f", f.w, f.h),
                        string.format("Position: x=%.1f, y=%.1f", f.x, f.y),
                        string.format("Full Screen: %s", tostring(win:isFullScreen())),
                        "-------------------------",
                        string.format("Monitor Size: %.0f x %.0f", screen.w, screen.h),
                        string.format("Reference Target: %d x %d", REF_W or 1680, REF_H or 1044),
                        "-------------------------",
                        string.format("Aspect Ratio: %.2f", currentRatio),
                        string.format("Camera Sensitivity: %.2f", currentSens),
                        "-------------------------"
                    }
                    print(table.concat(output, "\n"))
                    ms.alert(string.format("Window: %.0f x %.0f | Ratio: %.2f", f.w, f.h, currentRatio), 4)
                    ms.alert("Camera Sensitivity: " .. string.format("%.2f", currentSens), 4)
                    if currentRatio < 4/3 then
                        ms.alert("Warning: Ratio too narrow.", 8)
                    end
                else
                    print("DEBUG ERROR: Roblox window not found.")
                    ms.alert("Roblox not found.", 2)
                end
            end
        -- END --

        -- 7. Camera Engine --
            ms.cam = {
                anchor = nil,
                -- button 5 is a synthetic-only internal channel: sits beyond the range of
                -- buttons on any common mouse (0–4), so Roblox's camera responds to it
                -- without any real mouse interaction. Never user-configurable.
                button = 5,
                cachedMult = 1.0,
                _lastFrame = nil,
                _updateTimer = nil,
                _enabled = false,

                updateMultiplier = function()
                    local curSens = (CUR_CAM_SENS and CUR_CAM_SENS > 0) and CUR_CAM_SENS or 1.5
                    local win = ms.getRobloxWin()
                    if not win then
                        ms.cam.cachedMult = 1.0
                        return
                    end
                    f = win:frame()
                    ratio = f.w / f.h
                    local refSens = (REF_SENS and REF_SENS > 0) and REF_SENS or 1.5
                    curSens = (CUR_CAM_SENS and CUR_CAM_SENS > 0) and CUR_CAM_SENS or 1.5
                    ms.cam.cachedMult = refSens / curSens
                end,

                updateAnchor = function()
                    local win = ms.getRobloxWin()
                    if not win then return end
                    local f = win:frame()
                    local last = ms.cam._lastFrame
                    if last and math.abs(f.x - last.x) < 2 and math.abs(f.y - last.y) < 2
                        and math.abs(f.w - last.w) < 2 and math.abs(f.h - last.h) < 2 then
                        return
                    end
                    -- True only when a prior frame existed and dimensions changed.
                    -- Prevents ratio alerts from firing on every tab-in after cam.disable().
                    local sizeChanged = last ~= nil
                        and (math.abs(f.w - last.w) >= 2 or math.abs(f.h - last.h) >= 2)
                    ms.cam._lastFrame = { x = f.x, y = f.y, w = f.w, h = f.h }
                    ms.cam.anchor = { x = f.x + (f.w / 2), y = f.y + (f.h / 2) }
                    ms.cam.updateMultiplier()
                    if sizeChanged then
                        if ratio and ratio < 4/3 and not _ratioWarnTimer then
                            ms.alert("Warning: Aspect ratio too narrow.\nMacros may not function correctly. Widen your Roblox window, or increase your screen resolution.", 13)
                            _ratioWarnTimer = hs.timer.doAfter(15, function()
                                _ratioWarnTimer = nil
                            end)
                        elseif ratio and loadfinish > 0 then
                            ms.alert("Current aspect ratio: (" .. string.format("%.2f", ratio) .. ").\nRecommended aspect ratio: >=1.33.", 8)
                        end
                    end
                end,

                scheduleUpdate = function()
                    if ms.cam._updateTimer then ms.cam._updateTimer:stop() end
                    ms.cam._updateTimer = hs.timer.doAfter(0.5, function()
                        ms.cam.updateAnchor()
                    end)
                end,

                -- Idempotent: calling enable when already enabled is a no-op.
                enable = function()
                    if ms.cam._enabled then return end
                    ms.cam._enabled = true
                    local cx, cy = ms.winCenter()
                    if cx == 0 and cy == 0 then
                        if not ms.cam._startAttempts then ms.cam._startAttempts = 0 end
                        ms.cam._startAttempts = ms.cam._startAttempts + 1
                        if ms.cam._startAttempts < 10 then
                            ms.cam._enabled = false
                            hs.timer.doAfter(1, function() ms.cam.enable() end)
                        else
                            ms.cam._startAttempts = 0
                            print("cam.enable: gave up after 10 attempts")
                        end
                        return
                    end
                    ms.cam._startAttempts = 0
                    ms.cam.updateAnchor()
                    -- Delay before posting button 5 init events: Roblox needs a moment
                    -- to fully claim input focus after activation before it will process them.
                    hs.timer.doAfter(0.3, function()
                        if not ms.cam._enabled then return end
                        local currentPos = hs.mouse.absolutePosition()
                        local lock = hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.otherMouseDown,
                            { x = currentPos.x, y = currentPos.y })
                        local unlock = hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.otherMouseUp,
                            { x = currentPos.x, y = currentPos.y })
                        if lock then
                            lock:setProperty(hs.eventtap.event.properties.mouseEventButtonNumber, ms.cam.button)
                            unlock:setProperty(hs.eventtap.event.properties.mouseEventButtonNumber, ms.cam.button)
                            lock:post()
                            hs.timer.usleep(10000)
                            unlock:post()
                        end
                    end)
                end,

                disable = function()
                    ms.cam._enabled = false
                    if ms.cam._uiWatcher then
                        ms.cam._uiWatcher:stop()
                        ms.cam._uiWatcher = nil
                    end
                    if ms.cam._updateTimer then
                        ms.cam._updateTimer:stop()
                        ms.cam._updateTimer = nil
                    end
                    ms.cam.anchor = nil
                    ms.cam._lastFrame = nil
                end,

                move = function(dy, dx)
                    if not ms.cam.anchor then
                        ms.wait(2)
                        return
                    end
                    local m = ms.cam.cachedMult
                    local final1 = math.floor((dx * m) + (dx >= 0 and 0.5 or -0.5))
                    local final2 = math.floor((dy * m) + (dy >= 0 and 0.5 or -0.5))
                    local drag = hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.otherMouseDragged, ms.cam.anchor)
                    if drag then
                        drag:setProperty(hs.eventtap.event.properties.mouseEventButtonNumber, ms.cam.button)
                        drag:setProperty(hs.eventtap.event.properties.mouseEventDeltaX, final1)
                        drag:setProperty(hs.eventtap.event.properties.mouseEventDeltaY, final2)
                        drag:post()
                    end
                end
            }

            ms.cam._setupWatcher = function()
                local robloxApp = hs.application.get("Roblox")
                if not robloxApp then return end
                if ms.cam._uiWatcher then ms.cam._uiWatcher:stop() end
                ms.cam._uiWatcher = robloxApp:newWatcher(function(el, event)
                    ms.cam.scheduleUpdate()
                end)
                ms.cam._uiWatcher:start({
                    hs.uielement.watcher.windowCreated,
                    hs.uielement.watcher.windowMoved,
                    hs.uielement.watcher.windowResized,
                    hs.uielement.watcher.mainWindowChanged,
                })
            end

            ms.cam._setupWatcher()
        -- END --

        -- 8. Macro Bind Controller
            -- Notification for enable/disable state changes.
            -- _doNotify is called synchronously by setMacros — no outer deferral
            -- that could swallow errors silently. The debounce lives *inside*
            -- _doNotify as a stored local upvalue, so it can't be GC'd, and any
            -- error in the callback still surfaces in the console.
            local _debounceTimer = nil
            local _stateSound    = nil  -- handle to the last state-change sound

            local function _doNotify(state)
                if loadfinish ~= 1 then return end
                -- Cancel any pending debounce; rapid toggles collapse to the settled state.
                if _debounceTimer then _debounceTimer:stop(); _debounceTimer = nil end
                _debounceTimer = hs.timer.doAfter(0.05, function()
                    _debounceTimer = nil
                    -- Cut off any previous state sound and toast before showing the new ones.
                    if _stateSound then pcall(function() _stateSound:stop() end); _stateSound = nil end
                    ms.alert.dismissAll()
                    if state == 1 then
                        _stateSound = ms.playSlot("enabled")
                        ms.alert("Macros enabled!",  3, true)
                    else
                        _stateSound = ms.playSlot("disabled")
                        ms.alert("Macros disabled.", 3, true)
                    end
                end)
            end

            ms.setMacros = function(state, silent)
                if state == 1 and BindValidity ~= 1 then
                    BindValidity = 1
                    pcall(function() ms.cam.enable() end)
                    if not silent then _doNotify(1) end
                elseif state == 0 and BindValidity ~= 0 then
                    BindValidity = 0
                    ms.cancelMacros()
                    ms.keytrack = {}
                    for _, timer in pairs(ms.running) do
                        if timer and timer.stop then timer:stop() end
                    end
                    ms.running = {}
                    pcall(function() ms.cam.disable() end)
                    if not silent then _doNotify(0) end
                end
            end

            ms._appWatcher = hs.application.watcher.new(function(appName, eventType, app)
                if eventType == hs.application.watcher.activated then
                    if appName == "Roblox" then
                        local fromDialog = ms._inputOpen
                        ms._inputOpen = false
                        ms._robloxActive = true
                        ms.cam._setupWatcher()
                        if fromDialog then
                            -- Returning from a Hammerspoon dialog/panel: re-enable silently.
                            BindValidity = 1
                            pcall(function() ms.cam.enable() end)
                        else
                            ms.setMacros(1)
                        end
                    else
                        -- If the settings panel is open and Hammerspoon itself is taking
                        -- focus, this is just the webview — don't disable macros or
                        -- change any state at all.  But if a third app (browser, terminal,
                        -- etc.) activates while the panel is open, still clear
                        -- ms._robloxActive so that / and return don't fire outside Roblox.
                        if ms.ui._open and appName == "Hammerspoon" then return end
                        ms._inputOpen    = (appName == "Hammerspoon") and ms._robloxActive
                        ms._robloxActive = false
                        if BindValidity == 1 then
                            ms.setMacros(0, ms._inputOpen)
                        end
                    end
                elseif eventType == hs.application.watcher.launched and appName == "Roblox" then
                    ms.cam._setupWatcher()
                end
            end):start()
            _G.__ms_appWatcher = ms._appWatcher  -- survives reload (lives outside the ms table) so next load's stop-guard can find this generation

            _G._initTimer = hs.timer.doAfter(0.3, function()
                local frontApp = hs.application.frontmostApplication()
                if frontApp and frontApp:name() == "Roblox" then
                    ms._robloxActive = true
                    ms.cam._setupWatcher()
                    ms.cam.enable()
                    -- Use silent=true: seeds BindValidity and _notifyLastPosted through
                    -- the canonical path without firing a startup toast.
                    ms.setMacros(1, true)
                end
            end)

            hs.hotkey.bind({ "alt" }, "F10", function()
                if not ms._robloxActive then return end
                ms.setMacros(0)
            end)

            hs.hotkey.bind({"alt"}, "[", function()
                hs.reload()
            end)

            hs.hotkey.bind({"alt"}, "]", function()
                ms.reloadSettings()
            end)

            -- hs.hotkey is blocked during NSMenu's modal tracking loop, so Alt+P
            -- would only fire *after* the menu closes — too late to close it.
            -- hs.eventtap operates at the CGEvent level and fires *during* the
            -- modal loop, letting us inject Escape while the menu is still open.
            -- Opening is deferred via doAfter(0) so the tap callback returns
            -- immediately (CGEventTap callbacks must not block; a long-running one
            -- gets disabled by macOS after ~1 s).
            -- Alt+P toggles the webview Settings panel (Section 10, ms.ui).
            -- The eventtap workaround this used to require — to intercept Alt+P
            -- *during* NSMenu's modal tracking loop, since hs.hotkey is blocked
            -- while a native menu is open — is no longer needed for a normal
            -- window, so a plain hotkey bind is sufficient here.
            hs.hotkey.bind({ "alt" }, "p", function()
                if not ms._robloxActive then return end
                ms.ui.toggle()
            end)
        -- END --

        -- 9. Misc --
            -- Wraps fn to run inside a coroutine when called, guaranteeing that
            -- ms.wait always has a coroutine context and never hits the blocking
            -- usleep fallback. async defaults to true; pass false to skip the wrap.
            ms.fn = function(fn, async)
                assert(type(fn) == "function", "ms.fn: fn must be a function")
                if async == false then return fn end
                return function(...)
                    local co  = coroutine.create(fn)
                    -- Inherit the pending label set by firedFn so ms.wait step entries
                    -- can identify which macro is running without needing an id param.
                    local ctx = { cancelled = false, label = ms._pendingLabel or "macro" }
                    ms._pendingLabel = nil
                    ms._coroContext[co]    = ctx
                    ms._activeContexts[ctx] = true
                    local ok, err = coroutine.resume(co, ...)
                    if not ok then
                        print("ms.fn error: " .. tostring(err))
                        ms.alert("Macro error — check Hammerspoon console.", 4)
                    end
                    -- Coroutine finished without ever yielding: clean up immediately.
                    if coroutine.status(co) == "dead" then
                        ms._coroContext[co]    = nil
                        ms._activeContexts[ctx] = nil
                    end
                end
            end

            ms.copy = function(text) hs.pasteboard.setContents(text) end

            -- Cancels all active ms.fn macro coroutines and releases any keys or mouse
            -- buttons that were left held by macro presses. Called automatically on every
            -- setMacros(0) so no held input leaks across focus changes or user-stops.
            ms.cancelMacros = function()
                -- Mark every live coroutine as cancelled so pending ms.wait /
                -- ms.sound callbacks don't resume it after this point.
                for ctx in pairs(ms._activeContexts) do
                    ctx.cancelled = true
                end
                ms._activeContexts = {}
                ms._coroContext     = {}

                -- Release every key currently held by a macro press.
                for keyCode, entry in pairs(ms._macroHeldKeys) do
                    local ev = hs.eventtap.event.newKeyEvent(entry.mods, keyCode, false)
                    if entry.hidinject then
                        local app = hs.application.get("Roblox")
                        if app then ev:post(app)
                        else
                            ev:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                            ev:post()
                        end
                    else
                        ev:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                        ev:post()
                    end
                end
                ms._macroHeldKeys = {}

                -- Release every mouse button currently held by a macro press.
                for btn, entry in pairs(ms._macroHeldButtons) do
                    local ev = hs.eventtap.event.newMouseEvent(entry.upT, entry.pos)
                    if btn >= 2 then
                        ev:setProperty(hs.eventtap.event.properties.mouseEventButtonNumber, btn)
                    end
                    if entry.app then ev:post(entry.app)
                    else
                        ev:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                        ev:post()
                    end
                end
                ms._macroHeldButtons = {}
            end

            -- Scans SoundLib for audio files and indexes them by name (without extension).
            -- Also folds in ms.importedSounds (settings-persisted list) so sounds imported
            -- through the menu are always available even if SoundLib is temporarily missing.
            -- Safe to call multiple times; re-indexes from scratch each time.
            ms._discoverSounds = function()
                ms.sounds = {}
                if hs.fs.attributes(SoundLib) then
                    for file in hs.fs.dir(SoundLib) do
                        if file ~= "." and file ~= ".." then
                            local name = file:match("^(.+)%.[^%.]+$")
                            if name then
                                ms.sounds[name] = SoundLib .. file
                            end
                        end
                    end
                end
                -- Merge in settings-tracked imports (fills gaps when folder is missing)
                for name, filename in pairs(ms.importedSounds or {}) do
                    if not ms.sounds[name] then
                        local path = SoundLib .. filename
                        if hs.fs.attributes(path) then
                            ms.sounds[name] = path
                        end
                    end
                end
            end

            -- Plays a sound by path or ms.sounds.* table entry.
            -- async: true (default) = fire-and-forget; false = yield until complete.
            -- device: output device name string; nil = system default.
            ms.sound = function(path, async, device)
                if not ms.soundEnabled then return end
                if not path then return end
                local s = hs.sound.getByFile(path) or hs.sound.getByName(path)
                if not s then
                    print("ms.sound: could not load sound: " .. tostring(path))
                    return
                end
                if ms.soundVolume ~= nil then
                    s:volume(ms.soundVolume / 100)
                end
                if device then
                    local dev = hs.audiodevice.findOutputByName(device)
                    if dev then s:device(dev:uid()) end
                end
                async = (async ~= false)
                if not async then
                    local co  = coroutine.running()
                    local ctx = co and ms._coroContext[co]  -- capture at yield time
                    if co then
                        s:setCallback(function(snd, state)
                            if state == "stop" then
                                snd:setCallback(nil)
                                if ctx and ctx.cancelled then return end
                                local ok, err = coroutine.resume(co)
                                if not ok then
                                    print("ms.sound resume error: " .. tostring(err))
                                end
                                if coroutine.status(co) == "dead" then
                                    ms._coroContext[co] = nil
                                    if ctx then ms._activeContexts[ctx] = nil end
                                end
                            end
                        end)
                        s:play()
                        coroutine.yield()
                        return
                    end
                end
                s:play()
                return s  -- return handle so callers can stop playback
            end

            -- Plays the sound assigned to a named slot (e.g. "update", "reset", "alert").
            -- Falls back to a file auto-discovered under the same slot name in SoundLib.
            -- Returns true if a sound was found and played; false if disabled or no file.
            ms.playSlot = function(slotId)
                if not ms.soundEnabled then return false end
                -- Suppress if the same slot played within 50 ms.
                local now = hs.timer.absoluteTime()
                ms._playSlotTimes = ms._playSlotTimes or {}
                if (now - (ms._playSlotTimes[slotId] or 0)) < 0.05 then return false end
                ms._playSlotTimes[slotId] = now
                -- Cut off any still-playing instance of this same slot so sounds
                -- never overlap themselves (e.g. rapid-fire alerts in the console).
                ms._slotHandles = ms._slotHandles or {}
                if ms._slotHandles[slotId] then
                    pcall(function() ms._slotHandles[slotId]:stop() end)
                    ms._slotHandles[slotId] = nil
                end
                local assigned = ms.soundAssign and ms.soundAssign[slotId]
                local path
                if assigned then
                    path = (ms.sounds and ms.sounds[assigned]) or assigned
                else
                    path = ms.sounds and ms.sounds[slotId]
                end
                if not path then return false end
                local handle = ms.sound(path) or false
                if handle then ms._slotHandles[slotId] = handle end
                return handle
            end

            -- Returns the menu open point pulled 25% toward the screen center.
            -- Applied at popupMenu call time so ms._lastMenuPoint stays as the raw
            -- cursor position and successive reopens don't accumulate drift.
            ms._biasedMenuPt = function(raw)
                local p  = raw or hs.mouse.absolutePosition()
                local sf = hs.screen.mainScreen():frame()
                return {
                    x = p.x * 0.75 + (sf.x + sf.w * 0.2) * 0.12,
                    y = p.y * 0.75 + (sf.y + sf.h * 0.2) * 0.12,
                }
            end

            -- Poll the focused AX element every 25 ms while the menu is open.
            -- hs.uielement.focusedElement() returns the highlighted menu item during
            -- NSMenu tracking. When its screen position changes, a new item is highlighted.
            -- This fires correctly for both mouse and keyboard navigation.
            ms._menuHoverStart = function()
                if ms._menuHoverWatcher then return end
                local lastKey = nil
                ms._menuHoverWatcher = hs.timer.doEvery(0.025, function()
                    if not ms._menuVisible then return end
                    local el = hs.uielement.focusedElement()
                    if not el then return end
                    local ok, frame = pcall(function() return el:frame() end)
                    if not ok or not frame then return end
                    local key = frame.x .. "," .. frame.y
                    if key ~= lastKey then
                        lastKey = key
                        ms.playSlot("hover")
                    end
                end)
            end

            ms._menuHoverStop = function()
                if ms._menuHoverWatcher then
                    ms._menuHoverWatcher:stop()
                    ms._menuHoverWatcher = nil
                end
            end

            ms.mousePos = function()
                local win = ms.getRobloxWin() or hs.window.focusedWindow()
                local pos = hs.mouse.absolutePosition()
                if not win then return pos.x, pos.y end
                local f = win:frame()
                local relX = (pos.x - f.x) * (REF_W / f.w)
                local relY = (pos.y - f.y) * (REF_H / f.h)
                return relX, relY
            end

            -- Returns the colour of a single pixel at (x, y) in the given reference space.
            -- Uses the same coordinate system as ms.Mouse: WindowTL, Absolute, Mouse, etc.
            -- The returned table has integer r, g, b, a fields in [0, 255].
            -- Returns nil on capture failure (off-screen position, no display, etc.).
            ms.pixelColor = function(x, y, reference)
                reference = reference or "Absolute"
                local ax, ay = ms.resolvePoint(x, y, reference)
                if not ax or not ay then return nil end

                -- Find the display that owns this point (multi-monitor aware).
                local screen = hs.screen.mainScreen()
                for _, scr in ipairs(hs.screen.allScreens()) do
                    local f = scr:frame()
                    if ax >= f.x and ax < f.x + f.w
                    and ay >= f.y and ay < f.y + f.h then
                        screen = scr; break
                    end
                end

                local img = screen:snapshot({ x = ax, y = ay, w = 1, h = 1 })
                if not img then return nil end
                local c = img:colorAt({ x = 0, y = 0 })
                if not c then return nil end

                return {
                    r = math.floor((c.red   or 0) * 255 + 0.5),
                    g = math.floor((c.green or 0) * 255 + 0.5),
                    b = math.floor((c.blue  or 0) * 255 + 0.5),
                    a = math.floor((c.alpha or 1) * 255 + 0.5),
                }
            end

            -- Returns true if the pixel at (x, y) matches the given r, g, b target
            -- within the per-channel tolerance (default 10, scale 0-255).
            ms.pixelMatch = function(x, y, reference, r, g, b, tolerance)
                tolerance = tolerance or 10
                local c = ms.pixelColor(x, y, reference)
                if not c then return false end
                return math.abs(c.r - r) <= tolerance
                   and math.abs(c.g - g) <= tolerance
                   and math.abs(c.b - b) <= tolerance
            end
        -- END --

        -- 10. Registry, Bind System & Sub-item Helpers --

            -- Single entry point for declaring a macro and optionally wiring its function.
            -- Signature: ms.bind.define(id, fn, opts)  — preferred: action first, config last
            --        or: ms.bind.define(id, opts, fn)  — old order, still accepted
            -- Both fn and opts are optional; types are detected automatically.
            --
            -- opts fields (all optional — init.lua supplies defaults for everything):
            --   label=id  group=nil  enabled=true  cooldown=1000
            --   sub=nil   mod=nil    info=nil       default=nil    shared=nil
            ms.bind.define = function(id, a, b)
                assert(type(id) == "string", "ms.bind.define: id must be a string")
                local fn   = type(a) == "function" and a or (type(b) == "function" and b or nil)
                local opts = type(a) == "table"    and a or (type(b) == "table"    and b or {})
                if opts.sub then
                    assert(ms.registry._defs[opts.sub],
                        "ms.bind.define: parent '" .. tostring(opts.sub) .. "' must be defined before '" .. id .. "'")
                end
                local label, group
                if not opts.sub then
                    if opts.label then
                        label = opts.label
                    else
                        ms.bind._autoCount = ms.bind._autoCount + 1
                        label = "Macro" .. ms.bind._autoCount
                    end
                    group = opts.group or "main"
                else
                    label = opts.label or id
                    group = opts.group
                end
                ms.registry._defs[id] = {
                    label    = label,
                    group    = group,
                    enabled  = (opts.enabled ~= false),
                    cooldown = opts.cooldown or 1000,
                    shared   = opts.shared,
                    sub      = opts.sub,
                    mod      = opts.mod,
                    info     = opts.info,
                    default  = opts.default,
                }
                table.insert(ms.registry._defList, id)
                if fn ~= nil then
                    assert(type(fn) == "function",
                        "ms.bind.define: fn must be a function for id '" .. id .. "'")
                    ms.bind._wires[id] = fn
                end
            end

            -- Returns the cooldown group key for a macro id.
            -- If opts.shared is set on the id or its root, uses that.
            -- Otherwise auto-derives "G_<rootId>" by walking the sub chain.
            ms.bind.group = function(id)
                local def = ms.registry._defs[id]
                if not def then return "G_" .. tostring(id) end
                if def.shared then return def.shared end
                local current, seen = id, {}
                while true do
                    local d = ms.registry._defs[current]
                    if not d or not d.sub or seen[current] then break end
                    seen[current] = true
                    current = d.sub
                end
                local rootDef = ms.registry._defs[current]
                if rootDef and rootDef.shared then return rootDef.shared end
                return "G_" .. current
            end

            -- Optional: clears the cooldown for id's group before the timer fires.
            -- Useful for completion-based locking on slow macros. The core system
            -- never requires this to be called — it is purely optional sugar.
            ms.done = function(id)
                local group = ms.bind.group(id)
                local timer = ms.running[group]
                if timer then
                    timer:stop()
                    ms.running[group] = nil
                end
            end

            -- Tears down all active key and mouse binds without touching the
            -- trackpad listeners (they are started/stopped by rebind).
            ms.bind.teardown = function()
                for id, handle in pairs(ms.bindHandles) do
                    if handle and handle.delete then handle:delete() end
                end
                ms.bindHandles = {}
                ms._mouseCallbacks = {}
            end

            -- Rebuilds all binds from the current registry + wire table.
            -- Replaces ms.rebindAll.
            ms.bind.rebind = function()
                ms.bind.teardown()

                -- Helper: canonical string for bind-conflict comparison.
                local function bindKey(c)
                    if not c then return nil end
                    if c.type == "mouse" then return "mouse:" .. tostring(c.button) end
                    local mods = {}
                    for _, m in ipairs(c.mods or {}) do table.insert(mods, m) end
                    table.sort(mods)
                    return "key:" .. table.concat(mods, ",") .. ":" .. (c.key or "")
                end

                -- Phase 1: Conflict detection.
                -- Conflicts suppress registration this pass without permanently
                -- altering ms.binds. The user resolves them via the settings menu.
                local conflicted = {}

                -- Root bind conflicts: two enabled root binds with the same effective bind.
                local rootUsed = {}
                for _, id in ipairs(ms.registry._defList) do
                    local def = ms.registry._defs[id]
                    if not def or def.sub then goto c1 end
                    local enabled = ms.binds[id]; if enabled == nil then enabled = def.enabled end
                    if not enabled then goto c1 end
                    local key = bindKey(ms.effectiveBind(id))
                    if key then
                        if rootUsed[key] then
                            local other = rootUsed[key]
                            conflicted[id] = true; conflicted[other] = true
                            local l1 = ms.registry._defs[id].label
                            local l2 = ms.registry._defs[other].label
                            hs.timer.doAfter(0, function()
                                ms.alert("Bind conflict: \"" .. l1 .. "\" and \"" .. l2
                                    .. "\" share the same input.\nBoth disabled — resolve via Settings › Keybinds.", 10)
                            end)
                        else
                            rootUsed[key] = id
                        end
                    end
                    ::c1::
                end

                -- Sub-item modifier conflicts: two siblings sharing the same modifier key.
                local modUsed = {}
                for _, id in ipairs(ms.registry._defList) do
                    local def = ms.registry._defs[id]
                    if not def or not def.sub then goto c2 end
                    local mod = ms.getMod(id)
                    if not mod then goto c2 end
                    local parent = def.sub
                    modUsed[parent] = modUsed[parent] or {}
                    if modUsed[parent][mod] then
                        local other = modUsed[parent][mod]
                        conflicted[id] = true; conflicted[other] = true
                        local l1 = ms.registry._defs[id].label
                        local l2 = ms.registry._defs[other].label
                        local lp = (ms.registry._defs[parent] and ms.registry._defs[parent].label) or parent
                        hs.timer.doAfter(0, function()
                            ms.alert("Modifier conflict: \"" .. l1 .. "\" and \"" .. l2
                                .. "\" share modifier \"" .. mod .. "\" under " .. lp
                                .. ".\nBoth disabled — resolve via Settings › Modifiers.", 10)
                        end)
                    else
                        modUsed[parent][mod] = id
                    end
                    ::c2::
                end

                -- Phase 2: Registration — skip conflicted ids.
                -- Every registered function is wrapped with fire-based cooldown logic.
                -- The cooldown group is derived from ms.bind.group(id); firing any member
                -- of a group locks out all others in that group for the cooldown duration.
                for _, id in ipairs(ms.registry._defList) do
                    if conflicted[id] then goto continue end
                    local fn  = ms.bind._wires[id]
                    local def = ms.registry._defs[id]
                    if not fn or not def then goto continue end

                    local group    = ms.bind.group(id)
                    local cooldown = ms.cooldowns[id] or def.cooldown or 1000

                    if def.sub then
                        -- Sub-item: register when independent binds is on and a bind is configured.
                        -- Cooldown check + auto-dispatch (_activeSub) are both inside the wrapper.
                        if ms.independentBindsEnabled and ms.subBinds and ms.subBinds[id] then
                            local c = ms.subBinds[id]
                            local function firedFn()
                                if ms.running[group] then return end
                                ms.running[group] = hs.timer.doAfter(cooldown / 1000, function()
                                    ms.running[group] = nil
                                end)
                                ms._activeSub = id
                                if ms.dev then
                                    local _pd = ms.registry._defs[def.sub]
                                    local _trig = c.type=="mouse" and ("M"..c.button) or (function()
                                        local _p = {}
                                        for _, m in ipairs(c.mods or {}) do _p[#_p+1] = m end
                                        _p[#_p+1] = c.key or ""; return table.concat(_p, "+")
                                    end)()
                                    pcall(ms.dev._onMacroFire, id, def.label, def.sub, _pd and _pd.label, _trig)
                                end
                                ms._pendingLabel = def.label
                                fn()
                            end
                            if c.type == "mouse" then
                                ms.mouse(c.button, false, firedFn)
                            elseif c.type == "key" then
                                ms.bindHandles[id] = ms.key(c.mods, c.key, false, firedFn)
                            end
                        end
                    else
                        -- Root bind: honour enabled state, then look up effective bind.
                        local enabled = ms.binds[id]
                        if enabled == nil then enabled = def.enabled end
                        if not enabled then goto continue end
                        local c = ms.effectiveBind(id)
                        if not c then goto continue end
                        local function firedFn()
                            if ms.running[group] then return end
                            ms.running[group] = hs.timer.doAfter(cooldown / 1000, function()
                                ms.running[group] = nil
                            end)
                            ms._activeSub = nil  -- clear sub-item state before root bind fires
                            if ms.dev then
                                local _trig = c.type=="mouse" and ("M"..c.button) or (function()
                                    local _p = {}
                                    for _, m in ipairs(c.mods or {}) do _p[#_p+1] = m end
                                    _p[#_p+1] = c.key or ""; return table.concat(_p, "+")
                                end)()
                                pcall(ms.dev._onMacroFire, id, def.label, nil, nil, _trig)
                            end
                            ms._pendingLabel = def.label
                            fn()
                        end
                        if c.type == "mouse" then
                            ms.mouse(c.button, false, firedFn)
                        elseif c.type == "key" then
                            ms.bindHandles[id] = ms.key(c.mods, c.key, false, firedFn)
                        end
                    end

                    ::continue::
                end

                -- Trackpad hold listeners: start or stop based on current mode.
                if ms.trackpadMode then
                    if ms._trackpadLeftListener  then ms._trackpadLeftListener:start()  end
                    if ms._trackpadRightListener then ms._trackpadRightListener:start() end
                else
                    if ms._trackpadLeftListener  then ms._trackpadLeftListener:stop()  end
                    if ms._trackpadRightListener then ms._trackpadRightListener:stop() end
                end
            end

            -- Returns the id of a sibling root bind that already uses the given bind config,
            -- or nil if there is no conflict. Sibling scope for root binds is all other
            -- enabled root binds (they share the top level).
            ms.bind.siblingConflict = function(id, c)
                local def = ms.registry._defs[id]
                if not def or def.sub or not c then return nil end
                local function key(cfg)
                    if not cfg then return nil end
                    if cfg.type == "mouse" then return "mouse:" .. tostring(cfg.button) end
                    local mods = {}; for _, m in ipairs(cfg.mods or {}) do table.insert(mods, m) end
                    table.sort(mods)
                    return "key:" .. table.concat(mods, ",") .. ":" .. (cfg.key or "")
                end
                local ck = key(c)
                if not ck then return nil end
                for _, sibId in ipairs(ms.registry._defList) do
                    if sibId ~= id then
                        local sibDef = ms.registry._defs[sibId]
                        if sibDef and not sibDef.sub then
                            local sibEnabled = ms.binds[sibId]
                            if sibEnabled == nil then sibEnabled = sibDef.enabled end
                            if sibEnabled and key(ms.effectiveBind(sibId)) == ck then
                                return sibId
                            end
                        end
                    end
                end
                return nil
            end

            -- Returns the id of a sub-item sibling that already uses the given modifier key,
            -- or nil. Sibling scope is direct siblings (same immediate parent).
            ms.bind.siblingModConflict = function(id, modKey)
                local def = ms.registry._defs[id]
                if not def or not def.sub or not modKey then return nil end
                for _, sibId in ipairs(ms.registry._defList) do
                    if sibId ~= id then
                        local sibDef = ms.registry._defs[sibId]
                        if sibDef and sibDef.sub == def.sub and ms.getMod(sibId) == modKey then
                            return sibId
                        end
                    end
                end
                return nil
            end

            -- One-time creation of persistent trackpad hold listeners.
            -- They start stopped; ms.bind.rebind() starts/stops them per mode.
            -- Key codes are read from ms.trackpadHoldKeys at event time so
            -- hold-key rebinds take effect without listener recreation.
            local _tpModMap = {shift=56, ctrl=59, alt=58, cmd=55}

            if not ms._trackpadLeftListener then
                local leftPhysicallyHeld = false
                local leftActive = false
                ms._trackpadLeftListener = hs.eventtap.new({
                    hs.eventtap.event.types.keyDown,
                    hs.eventtap.event.types.keyUp,
                }, function(event)
                    if BindValidity ~= 1 then return false end
                    local isSynthetic = event:getProperty(hs.eventtap.event.properties.eventSourceUserData) == 999
                    if isSynthetic then return false end
                    local leftHoldCode = _tpModMap[ms.trackpadHoldKeys.left] or hs.keycodes.map[ms.trackpadHoldKeys.left]
                    if not leftHoldCode then return false end
                    local evType  = event:getType()
                    local keyCode = event:getKeyCode()
                    if keyCode ~= leftHoldCode then return false end
                    local isDown = evType == hs.eventtap.event.types.keyDown
                    leftPhysicallyHeld = isDown
                    ms.keytrack[keyCode] = isDown
                    if isDown and not leftActive then
                        leftActive = true
                        local co = coroutine.create(function()
                            ms.Mouse(Press, Left, Mouse, 0, 0)
                            while leftPhysicallyHeld and BindValidity == 1 do ms.wait(10) end
                            ms.Mouse(Release, Left, Mouse, 0, 0)
                            ms.wait(50)
                            leftActive = false
                        end)
                        coroutine.resume(co)
                    end
                    return true
                end)
            end

            if not ms._trackpadRightListener then
                local rightPhysicallyHeld = false
                local rightActive = false
                ms._trackpadRightListener = hs.eventtap.new({
                    hs.eventtap.event.types.keyDown,
                    hs.eventtap.event.types.keyUp,
                }, function(event)
                    if BindValidity ~= 1 then return false end
                    local isSynthetic = event:getProperty(hs.eventtap.event.properties.eventSourceUserData) == 999
                    if isSynthetic then return false end
                    local rightHoldCode = _tpModMap[ms.trackpadHoldKeys.right] or hs.keycodes.map[ms.trackpadHoldKeys.right]
                    if not rightHoldCode then return false end
                    local evType  = event:getType()
                    local keyCode = event:getKeyCode()
                    if keyCode ~= rightHoldCode then return false end
                    local isDown = evType == hs.eventtap.event.types.keyDown
                    rightPhysicallyHeld = isDown
                    ms.keytrack[keyCode] = isDown
                    if isDown and not rightActive then
                        rightActive = true
                        local co = coroutine.create(function()
                            ms.Mouse(Press, Right, Mouse, 0, 0)
                            while rightPhysicallyHeld and BindValidity == 1 do ms.wait(10) end
                            ms.Mouse(Release, Right, Mouse, 0, 0)
                            ms.wait(50)
                            rightActive = false
                        end)
                        coroutine.resume(co)
                    end
                    return true
                end)
            end

            -- Returns the default modifier key for a sub-item id, using the registry.
            ms.getMod = function(id)
                if ms.modConfig[id] ~= nil then return ms.modConfig[id] end
                local def = ms.registry._defs[id]
                return def and def.mod or nil
            end

            ms.modHeld = function(id)
                local key = ms.getMod(id)
                if not key then return false end
                return ms.keystate(key)
            end

            -- Returns true if the given sub-item id should fire for this invocation.
            -- Self-clearing on match so only one variant fires per call sequence.
            ms.isSub = function(id)
                if ms._activeSub == id or (not ms._activeSub and ms.modHeld(id)) then
                    ms._activeSub = nil
                    -- Log modifier-triggered sub-items to the dev monitor.
                    -- Independent-bind subs are already logged from firedFn;
                    -- this branch catches the modifier-hold path.
                    if ms.dev then
                        local def = ms.registry._defs[id]
                        if def and def.sub then
                            local pd  = ms.registry._defs[def.sub]
                            pcall(ms.dev._onMacroFire, id, def.label,
                                def.sub, pd and pd.label, ms.getMod(id) or "")
                        end
                    end
                    return true
                end
                return false
            end
        -- END --

        -- 11. Webview Settings Panel --
            -- Replaces the native NSMenu dropdown (Section 1, now dead code under
            -- `_legacyNativeMenuBuilder`) with the custom HTML/CSS/JS panel in
            -- ms_settings_ui.html, hosted in an hs.webview. The page talks to this
            -- Lua side over a single WKScriptMessageHandler named "ms":
            --   JS  → Lua : window.webkit.messageHandlers.ms.postMessage(JSON string)
            --   Lua → JS  : panel:evaluateJavaScript("receiveState(" .. json .. ")")
            require("hs.webview")
            require("hs.webview.usercontent")

            ms.ui = { _panel = nil, _open = false, _modalCallback = nil, _panelPos = nil }

            local uiHTMLPath   = os.getenv("HOME") .. "/.hammerspoon/ui/ms_settings_ui.html"
            local uiBasePath    = "file://" .. os.getenv("HOME") .. "/.hammerspoon/ui/"
            local panelW, panelH = 360, 640  -- 9:16 portrait

            local function _loadPanelHTML()
                local f = io.open(uiHTMLPath, "r")
                if not f then
                    return "<body style='background:#1c1c1e;color:#fff;font:13px -apple-system, sans-serif;padding:20px'>"
                        .. "Could not read ms_settings_ui.html.<br><br>Expected at:<br>" .. uiHTMLPath .. "</body>"
                end
                local html = f:read("*all")
                f:close()
                return html
            end

            -- "Mouse 3" / "Alt+V" style display string for the macro-row pill.
            local function _bindDisplay(c)
                if not c then return nil end
                if c.type == "mouse" then return "Mouse " .. tostring(c.button) end
                local parts = {}
                for _, m in ipairs(c.mods or {}) do
                    table.insert(parts, m:sub(1, 1):upper() .. m:sub(2))
                end
                table.insert(parts, (c.key or ""):upper())
                return table.concat(parts, "+")
            end

            -- Snapshots all live runtime state into the plain table the page's
            -- receiveState(state) expects. See ms_settings_ui.html for the shape.
            local function _buildUIState()
                local macros = {}
                for _, id in ipairs(ms.registry._defList or {}) do
                    local def = ms.registry._defs[id]
                    if def and not def.sub and (def.group == "main" or def.group == "optional") then
                        local enabled = ms.binds[id]
                        if enabled == nil then enabled = def.enabled end
                        -- Collect direct sub-items for this root bind,
                        -- and for each sub also collect its own sub-items (one more level).
                        local subs = {}
                        for _, subId in ipairs(ms.registry._defList or {}) do
                            local subDef = ms.registry._defs[subId]
                            if subDef and subDef.sub == id then
                                -- Collect sub-of-sub entries.
                                local subsubs = {}
                                for _, ss in ipairs(ms.registry._defList or {}) do
                                    local ssDef = ms.registry._defs[ss]
                                    if ssDef and ssDef.sub == subId then
                                        table.insert(subsubs, {
                                            id    = ss,
                                            label = ssDef.label or ss,
                                            mod   = ms.modConfig[ss] or ssDef.mod or "",
                                            bind  = _bindDisplay(ms.subBinds[ss]),
                                        })
                                    end
                                end
                                table.insert(subs, {
                                    id      = subId,
                                    label   = subDef.label or subId,
                                    mod     = ms.modConfig[subId] or subDef.mod or "",
                                    bind    = _bindDisplay(ms.subBinds[subId]),
                                    subsubs = #subsubs > 0 and subsubs or nil,
                                })
                            end
                        end
                        table.insert(macros, {
                            id      = id,
                            label   = def.label,
                            group   = def.group,
                            bind    = _bindDisplay(ms.effectiveBind(id)),
                            enabled = enabled and true or false,
                            subs    = subs,
                        })
                    end
                end

                ms._discoverSounds()
                local soundNames = {}
                for name in pairs(ms.sounds or {}) do table.insert(soundNames, name) end
                table.sort(soundNames)

                local status, curHash = ms.integrity.check()
                local meta = ms.macroMeta or {}

                -- Collect user-defined sound slots for the Sound section.
                local userSoundSlots = {}
                for _, def in ipairs(ms._userSettingDefs) do
                    if def.type == "soundSlot" then
                        table.insert(userSoundSlots, { key = def.key, label = def.label or def.key })
                    end
                end
                for _, menuDef in ipairs(ms._userMenuDefs) do
                    for _, item in ipairs(menuDef.items or {}) do
                        if item.type == "soundSlot" then
                            table.insert(userSoundSlots, { key = item.key, label = item.label or item.key })
                        end
                    end
                end

                -- Serialize user setting defs (strip function references for JSON).
                local userSettings = {}
                for _, def in ipairs(ms._userSettingDefs) do
                    local item = {
                        type    = def.type,
                        key     = def.key,
                        label   = def.label,
                        hint    = def.hint,
                    }
                    if def.type == "slider" then
                        item.min  = def.min;  item.max  = def.max
                        item.step = def.step; item.unit = def.unit
                    elseif def.type == "seg" then
                        item.options = def.options
                    elseif def.type == "action" then
                        item.btnLabel = def.btnLabel; item.danger = def.danger
                    end
                    if def.key then
                        item.value   = ms.settings.get(def.key)
                        item.default = def.default
                    end
                    table.insert(userSettings, item)
                end
                -- Serialize custom section defs.
                local userMenus = {}
                for _, menuDef in ipairs(ms._userMenuDefs) do
                    local items = {}
                    for _, item in ipairs(menuDef.items) do
                        local entry = {
                            type  = item.type,
                            key   = item.key,
                            label = item.label,
                            hint  = item.hint,
                        }
                        if item.type == "slider" then
                            entry.min  = item.min;  entry.max  = item.max
                            entry.step = item.step; entry.unit = item.unit
                        elseif item.type == "seg" then
                            entry.options = item.options
                        elseif item.type == "action" then
                            entry.btnLabel = item.btnLabel; entry.danger = item.danger
                        end
                        if item.key then
                            entry.value   = ms.settings.get(item.key)
                            entry.default = item.default
                        end
                        table.insert(items, entry)
                    end
                    table.insert(userMenus, {
                        id    = menuDef.id,
                        title = menuDef.title,
                        icon  = menuDef.icon,
                        items = items,
                    })
                end

                -- Build theme state (resolve file paths to file:// URLs for the panel).
                local themeOut = {}
                for k, v in pairs(ms._theme) do themeOut[k] = v end
                -- Resolve the settings-panel UIFC to a file:// URL; strip raw paths.
                themeOut.uifcURL = nil
                if type(themeOut.uifc) == "table" and themeOut.uifc.settings ~= "" then
                    local wp = os.getenv("HOME") .. "/.hammerspoon/" .. themeOut.uifc.settings
                    themeOut.uifcURL = hs.fs.attributes(wp) and ("file://" .. wp) or nil
                end
                themeOut.uifc = nil
                -- Resolve font file to a file:// URL if it looks like a path.
                if themeOut.font and themeOut.font:match("%.[ot]tf$")
                    or (themeOut.font and themeOut.font:match("%.woff2?$"))
                then
                    local fp = os.getenv("HOME") .. "/.hammerspoon/" .. themeOut.font
                    if hs.fs.attributes(fp) then
                        themeOut.fontURL  = "file://" .. fp
                        themeOut.font = themeOut.font:match("([^/\\]+)%.[^%.]+$") or themeOut.font
                    end
                end

                return {
                    macrosEnabled           = (BindValidity == 1),
                    macros                  = macros,
                    sensitivity             = CUR_CAM_SENS or 1.5,
                    trackpadMode            = ms.trackpadMode or false,
                    socdEnabled             = ms.socdEnabled or false,
                    socdMode                = ms.socdMode or "lastWins",
                    independentBindsEnabled = ms.independentBindsEnabled or false,
                    soundEnabled            = ms.soundEnabled,
                    soundVolume             = ms.soundVolume or 100,
                    soundAssign             = ms.soundAssign or {},
                    soundNames              = soundNames,
                    currentProfile          = meta.name and sanitizeName(meta.name) or "",
                    profiles                = getProfiles(),
                    integrityStatus         = status,
                    integrityHash           = curHash,
                    macroMeta               = { name = meta.name, author = meta.author, website = meta.website },
                    docsURL                 = ms._docsURL,
                    updateManifestURL       = ms._updateManifestURL,
                    userSettings            = userSettings,
                    userSoundSlots          = userSoundSlots,
                    userMenus               = userMenus,
                    hiddenFeatures          = ms._hiddenFeatures,
                    theme                   = themeOut,
                }
            end

            -- Pushes a fresh state snapshot into the open panel. Safe to call even
            -- when the panel hasn't been built yet (no-op) or isn't visible.
            ms.ui.refresh = function()
                if not ms.ui._panel then return end
                local ok, json = pcall(hs.json.encode, _buildUIState())
                if not ok then
                    print("ms.ui.refresh: state encode error: " .. tostring(json))
                    return
                end
                pcall(function()
                    ms.ui._panel:evaluateJavaScript("receiveState(" .. json .. ");")
                end)
            end

            local function _emptyToNil(s) if s == nil or s == "" then return nil end; return s end

            -- One handler per `action` the page can send via sendToHost({action=...}).
            -- Each mirrors the equivalent native-menu code path 1:1 (same save/rebind/
            -- playSlot calls) so behaviour matches the old menu exactly.
            ms.ui._actions = {
                ready = function() ms.ui.refresh() end,

                setMacros = function(data)
                    ms.setMacros(tonumber(data.value) == 1 and 1 or 0)
                    ms.ui.refresh()
                end,

                playSlot = function(data) if data.slot then ms.playSlot(data.slot) end end,

                alert = function(data)
                    if data.msg then
                        ms.alert(tostring(data.msg), tonumber(data.duration) or 3, data.noSound == true)
                    end
                end,

                close = function() ms.ui.hide() end,

                moveWindow = function(data)
                    if not ms.ui._panel then return end
                    pcall(function()
                        local dx = tonumber(data.dx) or 0
                        local dy = tonumber(data.dy) or 0
                        -- Never read panel:frame() here — the getter returns the last
                        -- *committed* (rendered) position, which lags behind the last
                        -- requested position under fast movement.  Applying a delta to a
                        -- stale position discards the previous move request, causing the
                        -- rubber-band stutter.  Instead we accumulate into _panelPos, a
                        -- Lua-side tracker that is always up-to-date.
                        if not ms.ui._panelPos then
                            -- Fallback: seed from the webview if somehow unset.
                            local f = ms.ui._panel:frame()
                            ms.ui._panelPos = { x = f.x, y = f.y, w = f.w, h = f.h }
                        end
                        ms.ui._panelPos.x = ms.ui._panelPos.x + dx
                        ms.ui._panelPos.y = ms.ui._panelPos.y + dy
                        ms.ui._panel:frame(ms.ui._panelPos)
                    end)
                end,

                reloadMacros = function() hs.reload() end,

                reloadSettings = function()
                    ms.reloadSettings()
                    ms.ui.refresh()
                end,

                setMacroEnabled = function(data)
                    if not data.id then return end
                    ms.binds[data.id] = (data.value == true)
                    ms.saveSettings()
                    ms.bind.rebind()
                    ms.playSlot("update")
                    ms.ui.refresh()
                end,

                setSensitivity = function(data)
                    local num = tonumber(data.value)
                    if num and num >= 0.1 and num <= 4 then
                        CUR_CAM_SENS = num
                        ms.saveSettings()
                        ms.cam.updateMultiplier()
                        ms.playSlot("update")
                    end
                    ms.ui.refresh()
                end,

                setClickLevel = function(data)
                    local num = tonumber(data.value)
                    if num and (num == 1 or num == 2 or num == 3 or num == 4) then
                        clickLevel = num
                        ms.saveSettings()
                        ms.playSlot("update")
                    end
                    ms.ui.refresh()
                end,

                setTrackpadMode = function(data)
                    ms.trackpadMode = (data.value == true)
                    ms.saveSettings()
                    ms.bind.rebind()
                    ms.playSlot("update")
                    ms.ui.refresh()
                end,

                setSocdEnabled = function(data)
                    ms.socdEnabled = (data.value == true)
                    ms.saveSettings()
                    ms.socdApply()
                    ms.playSlot("update")
                    ms.ui.refresh()
                end,

                setSocdMode = function(data)
                    if data.value == "lastWins" or data.value == "neutral" or data.value == "firstWins" then
                        ms.socdMode = data.value
                        ms.saveSettings()
                        ms.playSlot("update")
                    end
                    ms.ui.refresh()
                end,

                setIndependentBinds = function(data)
                    local turningOn = (data.value == true)
                    ms.independentBindsEnabled = turningOn
                    -- When turning ON: pre-clear any sub bind that conflicts with a root
                    -- bind or with another sub bind, so rebind() starts clean.
                    if turningOn then
                        local function bindKey(c)
                            if not c then return nil end
                            if c.type == "mouse" then return "mouse:" .. tostring(c.button) end
                            local mods = {}
                            for _, m in ipairs(c.mods or {}) do table.insert(mods, m) end
                            table.sort(mods)
                            return "key:" .. table.concat(mods, ",") .. ":" .. (c.key or "")
                        end
                        local usedKeys = {}
                        for _, id in ipairs(ms.registry._defList or {}) do
                            local def = ms.registry._defs[id]
                            if def and not def.sub then
                                local k = bindKey(ms.effectiveBind(id))
                                if k then usedKeys[k] = id end
                            end
                        end
                        for subId, c in pairs(ms.subBinds or {}) do
                            local k = bindKey(c)
                            if k then
                                if usedKeys[k] then
                                    ms.subBinds[subId] = nil
                                else
                                    usedKeys[k] = subId
                                end
                            end
                        end
                    end
                    ms.saveSettings()
                    ms.bind.rebind()
                    ms.playSlot("update")
                    ms.ui.refresh()
                end,

                saveDefault = function()
                    ms.saveDefault()
                    ms.ui.refresh()
                end,

                resetToDefault = function()
                    if ms.resetToDefault() then ms.playSlot("reset") end
                    ms.ui.refresh()
                end,

                setSoundEnabled = function(data)
                    ms.soundEnabled = (data.value == true)
                    ms.saveSettings()
                    ms.playSlot("update")
                    ms.ui.refresh()
                end,

                setSoundVolume = function(data)
                    local num = tonumber(data.value)
                    if num and num >= 0 and num <= 100 then
                        ms.soundVolume = math.floor(num)
                        ms.saveSettings()
                        ms.playSlot("update")
                    end
                    ms.ui.refresh()
                end,

                setSoundAssign = function(data)
                    if not data.slot then return end
                    ms.soundAssign = ms.soundAssign or {}
                    ms.soundAssign[data.slot] = _emptyToNil(data.name)
                    ms.saveSettings()
                    ms.playSlot("update")
                    ms.ui.refresh()
                end,

                -- switchProfile() reloads Hammerspoon ~3s after success (see Profile
                -- Management above), so no explicit refresh is needed on success.
                switchProfile = function(data) if data.name then switchProfile(data.name) end end,

                -- importProfile() drives its own native file picker / alerts.
                importProfile    = function() importProfile() end,
                importProfilePkg = function() importProfilePkg() end,
                exportProfilePkg = function() exportProfilePkg() end,

                importSounds = function()
                    ms.playSlot("alert")
                    local slibDir = SoundLib:match("^(.-)[/\\]*$") or SoundLib
                    local result = hs.dialog.chooseFileOrFolder(
                        "Select one or more sound files to add to your library",
                        hs.fs.attributes(slibDir) and SoundLib or os.getenv("HOME"),
                        true, false, true
                    )
                    local paths = {}
                    for _, v in pairs(result or {}) do
                        if type(v) == "string" then table.insert(paths, v) end
                    end
                    if #paths == 0 then ms.ui.show(); return end
                    if not hs.fs.attributes(slibDir) then
                        hs.execute("mkdir -p '" .. SoundLib .. "'")
                    end
                    if not hs.fs.attributes(slibDir) then
                        ms.ui.show()
                        ms.alert("Could not create sounds folder:\n" .. SoundLib, 4)
                        return
                    end
                    local function sq(s) return "'" .. s:gsub("'", "'\\''" ) .. "'" end
                    local added, failed = {}, {}
                    for _, srcPath in ipairs(paths) do
                        local filename   = srcPath:match("([^/]+)$")
                        local importName = filename and (filename:match("^(.+)%.[^%.]+$") or filename)
                        if not filename or not importName then
                            table.insert(failed, srcPath)
                        else
                            local dst    = SoundLib .. filename
                            local copied = false
                            if srcPath ~= dst then
                                local f = io.open(srcPath, "rb")
                                if f then
                                    local content = f:read("*all"); f:close()
                                    local g = io.open(dst, "wb")
                                    if g then g:write(content); g:close(); copied = true end
                                end
                                if not copied then
                                    local _, st = hs.execute("/bin/cp " .. sq(srcPath) .. " " .. sq(dst))
                                    copied = (st == true) or (hs.fs.attributes(dst) ~= nil)
                                end
                                if not copied then table.insert(failed, importName) end
                            else
                                copied = true
                            end
                            if copied then
                                ms.importedSounds = ms.importedSounds or {}
                                ms.importedSounds[importName] = filename
                                table.insert(added, importName)
                            end
                        end
                    end
                    if #added > 0 then
                        ms.saveSettings()
                        ms._discoverSounds()
                    end
                    ms.ui.show()
                    hs.timer.doAfter(0.15, function()
                        if #added > 0 then ms.playSlot("update") end
                        if #added > 0 and #failed == 0 then
                            local label = #added == 1
                                and ("Sound \"" .. added[1] .. "\" added.")
                                or  (#added .. " sounds added.")
                            ms.alert(label, 3, true)
                        elseif #added > 0 then
                            ms.alert(#added .. " added, " .. #failed .. " failed.", 3, true)
                        else
                            ms.alert("Import failed.\nGrant Hammerspoon Full Disk Access if importing from outside ~/.hammerspoon.", 5)
                        end
                        ms.ui.refresh()
                    end)
                end,

                -- Import a sound file and assign it directly to a specific slot.
                importSoundForSlot = function(data)
                    if not data.slot then return end
                    local slot = data.slot
                    ms.playSlot("alert")
                    local slibDir = SoundLib:match("^(.-)[/\\]*$") or SoundLib
                    local result = hs.dialog.chooseFileOrFolder(
                        "Select a sound file for \"" .. (data.label or slot) .. "\"",
                        hs.fs.attributes(slibDir) and SoundLib or os.getenv("HOME"),
                        true, false, false
                    )
                    local selectedPath
                    for _, v in pairs(result or {}) do
                        if type(v) == "string" then selectedPath = v; break end
                    end
                    if not selectedPath then ms.ui.show(); return end
                    if not hs.fs.attributes(slibDir) then
                        hs.execute("mkdir -p '" .. SoundLib .. "'")
                    end
                    local function sq(s) return "'" .. s:gsub("'", "'\\''" ) .. "'" end
                    local filename   = selectedPath:match("([^/]+)$")
                    local importName = filename and (filename:match("^(.+)%.[^%.]+$") or filename)
                    if not filename or not importName then
                        ms.ui.show(); ms.alert("Could not read filename.", 3); return
                    end
                    local dst    = SoundLib .. filename
                    local copied = false
                    if selectedPath ~= dst then
                        local f = io.open(selectedPath, "rb")
                        if f then
                            local content = f:read("*all"); f:close()
                            local g = io.open(dst, "wb")
                            if g then g:write(content); g:close(); copied = true end
                        end
                        if not copied then
                            local _, st = hs.execute("/bin/cp " .. sq(selectedPath) .. " " .. sq(dst))
                            copied = (st == true) or (hs.fs.attributes(dst) ~= nil)
                        end
                    else
                        copied = true
                    end
                    ms.ui.show()
                    if not copied then
                        hs.timer.doAfter(0.15, function()
                            ms.alert("Import failed.\nGrant Hammerspoon Full Disk Access if needed.", 5)
                        end)
                        return
                    end
                    ms.importedSounds = ms.importedSounds or {}
                    ms.importedSounds[importName] = filename
                    ms.soundAssign = ms.soundAssign or {}
                    ms.soundAssign[slot] = importName
                    ms.saveSettings()
                    ms._discoverSounds()
                    ms.playSlot("update")
                    hs.timer.doAfter(0.15, function()
                        ms.alert("\"" .. importName .. "\" imported and assigned.", 3, true)
                        ms.ui.refresh()
                    end)
                end,

                openWindowMonitor = function() if ms.dev and ms.dev.window then ms.dev.window.toggle() end end,

                openConsole = function() hs.openConsole() end,

                editMacros = function()
                    os.execute("open " .. os.getenv("HOME") .. "/.hammerspoon/ms_macros.lua")
                end,

                editTheme = function()
                    os.execute("open " .. themePath)
                end,

                reloadTheme = function()
                    ms.loadTheme()
                    -- Rebuild the panel if open so uifc/size changes take effect.
                    if ms.ui._open then
                        ms.ui.hide()
                        hs.timer.doAfter(0.1, function() ms.ui.show() end)
                    else
                        ms.ui.refresh()
                    end
                end,

                trustCurrentVersion = function()
                    ms.integrity.trustCurrent()
                    ms.ui.refresh()
                end,

                deleteTrustedHash = function()
                    ms.integrity.deleteTrustedHash()
                    ms.alert("Trusted hash deleted.\nTamper protection is now OFF until you re-trust.", 5)
                    ms.ui.refresh()
                end,

                checkIntegrity = function()
                    local status, cur, trusted = ms.integrity.check()
                    if status == "trusted" then
                        ms.alert("\xe2\x9c\x93 ms_core.lua matches trusted hash.\n" .. (cur and cur:sub(1, 16) or "?") .. "\xe2\x80\xa6", 5, true)
                        ms.ui.refresh()
                    elseif status == "mismatch" then
                        -- Reload so the startup guardian seizes full control.
                        hs.reload()
                    else
                        ms.alert("No trusted hash on record.\nUse \"Trust Current Version\" to seed trust.", 5)
                        ms.ui.refresh()
                    end
                end,

                openURL = function(data) if data.url then hs.urlevent.openURL(data.url) end end,

                checkForUpdate = function() ms.integrity.update() end,

                openConsole       = function() ms.dev.console.toggle()  end,
                openWatcher       = function() ms.dev.watcher.toggle()  end,
                openKeys          = function() ms.dev.keys.toggle()     end,
                openWindowMonitor = function() ms.dev.window.toggle()   end,

                -- Triggered by right-click › Rebind… on a macro row in the webview.
                -- Runs the same eventtap capture used by the native menu rebind flow.
                startRebind = function(data)
                    if not data.id then return end
                    local def = ms.registry._defs[data.id]
                    if not def then return end
                    local label = def.label or data.id

                    local function bindDisplay(c)
                        if not c then return "unset" end
                        if c.type == "mouse" then return "Mouse " .. tostring(c.button) end
                        local parts = {}
                        for _, m in ipairs(c.mods or {}) do table.insert(parts, m) end
                        table.insert(parts, c.key or "")
                        return table.concat(parts, "+")
                    end

                    ms.alert("Rebinding: " .. label
                        .. "\nCurrent: " .. bindDisplay(ms.effectiveBind(data.id))
                        .. "\nPress your new key or mouse button.\nEscape to cancel.", 15)

                    -- Mark as input-open so the app watcher treats the upcoming focus
                    -- shift to Hammerspoon (for the confirm dialog) as a dialog cycle
                    -- rather than a genuine app switch, suppressing the disable toast.
                    -- Also temporarily clear _open so the app watcher's early-return
                    -- guard (which skips _inputOpen when the panel is visible) doesn't
                    -- swallow the Hammerspoon activation event.
                    ms._inputOpen = true
                    ms.ui._open   = false

                    local capture
                    local cancelTimer

                    local function restorePanel()
                        -- Re-flag the panel as open (it was never actually closed),
                        -- then hand focus back to Roblox so the app watcher fires
                        -- the Roblox-activated path and re-enables macros properly.
                        ms.ui._open = true
                        local roblox = hs.application.get("Roblox")
                        if roblox then
                            hs.timer.doAfter(0.05, function()
                                local ok, win = pcall(function() return roblox:mainWindow() end)
                                if ok and win then pcall(function() win:focus() end) end
                                pcall(function() roblox:activate() end)
                            end)
                        end
                    end

                    capture = hs.eventtap.new({
                        hs.eventtap.event.types.keyDown,
                        hs.eventtap.event.types.leftMouseDown,
                        hs.eventtap.event.types.rightMouseDown,
                        hs.eventtap.event.types.otherMouseDown,
                    }, function(event)
                        capture:stop(); capture = nil; cancelTimer:stop()

                        local parsed, bindStr2
                        local t = event:getType()

                        if t == hs.eventtap.event.types.keyDown then
                            local keyCode = event:getKeyCode()
                            local flags = event:getFlags()
                            if keyCode == 53 and not (flags.cmd or flags.alt or flags.ctrl or flags.shift) then
                                ms._inputOpen = false
                                ms.alert("Rebind cancelled.", 2)
                                restorePanel()
                                return true
                            end
                            local mods = {}
                            if flags.cmd   then table.insert(mods, "cmd")   end
                            if flags.alt   then table.insert(mods, "alt")   end
                            if flags.ctrl  then table.insert(mods, "ctrl")  end
                            if flags.shift then table.insert(mods, "shift") end
                            local keyStr = hs.keycodes.map[keyCode]
                            if keyStr then
                                parsed   = { type="key", mods=mods, key=keyStr }
                                local parts = {}
                                for _, m in ipairs(mods) do table.insert(parts, m) end
                                table.insert(parts, keyStr)
                                bindStr2 = table.concat(parts, "+")
                            end
                        else
                            local btn
                            if     t == hs.eventtap.event.types.leftMouseDown  then btn = 0
                            elseif t == hs.eventtap.event.types.rightMouseDown then btn = 1
                            else btn = event:getProperty(hs.eventtap.event.properties.mouseEventButtonNumber) end
                            parsed   = { type="mouse", button=btn }
                            bindStr2 = "Mouse " .. btn
                        end

                        if parsed then
                            local conflictId = ms.bind.siblingConflict(data.id, parsed)
                            if conflictId then
                                local cLabel = (ms.registry._defs[conflictId] and ms.registry._defs[conflictId].label) or conflictId
                                ms.playSlot("alert")
                                ms._inputOpen = false
                                ms.alert("Bind Conflict: \"" .. bindStr2 .. "\" is already used by \"" .. cLabel .. "\".\nChoose a different input.", 4)
                                restorePanel()
                                return true
                            end
                            ms.playSlot("interact")
                            ms._inputOpen = false
                            ms.ui.modal({
                                title   = "Confirm Rebind",
                                msg     = "Set \"" .. label .. "\" to:  " .. bindStr2,
                                confirm = "Confirm",
                                cancel  = "Cancel",
                            }, function(r)
                                if r.confirmed then
                                    -- Sub-items store in subBinds; root binds in bindConfig.
                                    if def.sub then
                                        ms.subBinds[data.id] = parsed
                                    else
                                        ms.bindConfig[data.id] = parsed
                                    end
                                    ms.saveSettings()
                                    ms.playSlot("update")
                                    ms.bind.rebind()
                                    restorePanel()
                                    hs.timer.doAfter(0.2, function()
                                        ms.alert(label .. " rebound to: " .. bindStr2, 3, true)
                                        ms.ui.refresh()
                                    end)
                                else
                                    ms.alert("Rebind cancelled.", 2)
                                    restorePanel()
                                    ms.ui.refresh()
                                end
                            end)
                        else
                            ms._inputOpen = false
                            ms.alert("Could not read input. Try again.", 2)
                            restorePanel()
                        end
                        return true
                    end)

                    capture:start()
                    cancelTimer = hs.timer.doAfter(15, function()
                        if capture then
                            capture:stop(); capture = nil
                            ms._inputOpen = false
                            ms.alert("Rebind timed out.", 2)
                            restorePanel()
                            ms.ui.refresh()
                        end
                    end)
                end,

                -- Resets a single system setting to its macro-pack default (ms.macroDefaults).
                resetSetting = function(data)
                    local key = data.key
                    local def = ms.macroDefaults or {}
                    if key == "sensitivity" then
                        CUR_CAM_SENS = tonumber(def.sensitivity) or 1.5
                        ms.saveSettings(); ms.cam.updateMultiplier()
                    elseif key == "trackpadMode" then
                        ms.trackpadMode = (def.trackpadMode == true)
                        ms.saveSettings(); ms.bind.rebind()
                    elseif key == "socdEnabled" then
                        ms.socdEnabled = (def.socdEnabled == true)
                        ms.saveSettings(); ms.socdApply()
                    elseif key == "socdMode" then
                        ms.socdMode = def.socdMode or "lastWins"
                        ms.saveSettings()
                    elseif key == "independentBinds" then
                        ms.independentBindsEnabled = (def.independentBinds == true)
                        ms.saveSettings(); ms.bind.rebind()
                    elseif key == "soundEnabled" then
                        ms.soundEnabled = true
                        ms.saveSettings()
                    elseif key == "soundVolume" then
                        ms.soundVolume = 100
                        ms.saveSettings()
                    end
                    ms.playSlot("reset")
                    ms.ui.refresh()
                end,

                -- Changes a user-defined setting value from the panel.
                -- Routes through ms.settings.set for validation, persistence, and onChange.
                userSettingChange = function(data)
                    if not data.key then return end
                    ms.settings.set(data.key, data.value)
                    ms.playSlot("update")
                    ms.ui.refresh()
                end,

                -- Fires the onAction callback for an action-type user setting.
                userSettingAction = function(data)
                    if not data.key then return end
                    local def = ms._userSettingIndex[data.key]
                    if def and def.type == "action" and type(def.onAction) == "function" then
                        pcall(def.onAction)
                    end
                    ms.ui.refresh()
                end,

                -- Resets a user-defined setting to its declared default value.
                resetUserSetting = function(data)
                    if not data.key then return end
                    local def = ms._userSettingIndex[data.key]
                    if not def or def.default == nil then return end
                    ms.settings.set(data.key, def.default)
                    ms.playSlot("reset")
                    ms.ui.refresh()
                end,

                -- Receives the result of a Lua-initiated HTML modal (openLuaModal in JS).
                -- Fires the pending _modalCallback and clears it.
                modalResult = function(data)
                    if ms.ui._modalCallback then
                        local cb = ms.ui._modalCallback
                        ms.ui._modalCallback = nil
                        pcall(cb, {
                            confirmed = data.confirmed == true,
                            value     = type(data.value) == "string" and data.value or "",
                        })
                    end
                end,

                -- Resets a macro's bind back to its defined default.
                resetBind = function(data)
                    if not data.id then return end
                    local def = ms.registry._defs[data.id]
                    if not def then return end
                    -- Sub-items use subBinds; root binds use bindConfig.
                    if def.sub then
                        ms.subBinds[data.id] = nil
                        -- In independent bind mode, clearing a sub's bind means it can no
                        -- longer fire at all — disable it so the UI reflects that.
                        if ms.independentBindsEnabled then
                            ms.binds[data.id] = false
                        end
                    else
                        ms.bindConfig[data.id] = nil
                    end
                    ms.saveSettings()
                    ms.bind.rebind()
                    ms.playSlot("reset")
                    hs.timer.doAfter(0.1, function()
                        ms.alert((def.label or data.id) .. " reset to default.", 2, true)
                        ms.ui.refresh()
                    end)
                end,

                -- Sets the modifier key for a sub-item.
                setModifier = function(data)
                    if not data.id then return end
                    local key = type(data.key) == "string" and data.key:match("^%s*(.-)%s*$") or ""
                    ms.modConfig[data.id] = (key ~= "") and key or nil
                    ms.saveSettings()
                    ms.bind.rebind()
                    ms.playSlot("update")
                    ms.ui.refresh()
                end,

                -- Clears the modifier key for a sub-item to "no modifier" (empty string).
                -- An empty string means "explicitly cleared", distinct from nil which means
                -- "use declared default". getMod() returns "" → keystate("") = false.
                clearModifier = function(data)
                    if not data.id then return end
                    ms.modConfig[data.id] = ""
                    ms.saveSettings()
                    ms.bind.rebind()
                    ms.playSlot("reset")
                    ms.ui.refresh()
                end,

                -- Starts a key-capture session to set the modifier for a sub-item.
                -- Captures the next keyDown or modifier-key press.
                -- Backspace clears the modifier; bare Escape cancels.
                startModRebind = function(data)
                    if not data.id then return end
                    local def = ms.registry._defs[data.id]
                    if not def or not def.sub then return end
                    local label = def.label or data.id
                    local cur   = ms.getMod(data.id)

                    ms.alert("Modifier for \"" .. label .. "\""
                        .. "\nCurrent: " .. (cur or "unset")
                        .. "\nPress a key  —  Backspace to clear  —  Escape to cancel.", 15)

                    ms._inputOpen = true
                    ms.ui._open   = false

                    local capture, cancelTimer
                    local prevFlags = {}

                    local function finish(newKey, cancelled)
                        ms._inputOpen = false
                        if not cancelled then
                            ms.modConfig[data.id] = newKey  -- nil = cleared
                            ms.saveSettings()
                            ms.bind.rebind()
                            ms.playSlot(newKey and "update" or "reset")
                        end
                        ms.ui.show()
                        hs.timer.doAfter(0.1, function()
                            if not cancelled then
                                if newKey then
                                    ms.alert("Modifier set to: " .. newKey, 3, true)
                                else
                                    ms.alert("Modifier cleared.", 3, true)
                                end
                            else
                                ms.alert("Modifier rebind cancelled.", 2)
                            end
                            ms.ui.refresh()
                        end)
                    end

                    capture = hs.eventtap.new({
                        hs.eventtap.event.types.keyDown,
                        hs.eventtap.event.types.flagsChanged,
                    }, function(event)
                        local t     = event:getType()
                        local flags = event:getFlags()

                        if t == hs.eventtap.event.types.flagsChanged then
                            -- Detect which modifier key was just pressed (not released).
                            local newMod = nil
                            if flags.shift and not prevFlags.shift then newMod = "shift"
                            elseif flags.alt   and not prevFlags.alt   then newMod = "alt"
                            elseif flags.ctrl  and not prevFlags.ctrl  then newMod = "ctrl"
                            elseif flags.cmd   and not prevFlags.cmd   then newMod = "cmd" end
                            prevFlags = flags
                            if not newMod then return false end  -- modifier released
                            capture:stop(); capture = nil; cancelTimer:stop()
                            finish(newMod, false)
                            return false
                        end

                        -- keyDown event.
                        capture:stop(); capture = nil; cancelTimer:stop()
                        local keyCode = event:getKeyCode()
                        if keyCode == 53 and not (flags.cmd or flags.alt or flags.ctrl or flags.shift) then
                            finish(nil, true)   -- bare Escape = cancel
                        elseif keyCode == 51 then
                            finish(nil, false)  -- Backspace = clear
                        else
                            local keyName = hs.keycodes.map[keyCode]
                            finish(keyName or nil, keyName == nil)
                        end
                        return true
                    end)

                    capture:start()
                    cancelTimer = hs.timer.doAfter(15, function()
                        if capture then
                            capture:stop(); capture = nil
                            finish(nil, true)
                        end
                    end)
                end,
            }

            -- Freeze the dispatch table so macro-sandbox code cannot inject new handlers
            -- by writing to nested ms.* sub-tables.  The frozenMs proxy only blocks direct
            -- writes to ms itself (e.g. ms.foo = x); it does not proxy writes to tables
            -- that are reachable through it (e.g. ms.ui._actions.evil = fn).  Applying a
            -- __newindex here means any such write errors immediately, regardless of where
            -- in the call stack it originates.  Reads (action dispatch) still work via
            -- __index on the backing table.
            do
                local _backing = ms.ui._actions
                ms.ui._actions = setmetatable({}, {
                    __index    = _backing,
                    __newindex = function(_, k)
                        error("ms.ui._actions is read-only (attempted write to '" .. tostring(k) .. "')", 2)
                    end,
                    __len      = function() return #_backing end,
                })
            end
            -- always posts a JSON string of the form { action = "...", ... }.
            local _ucMS = hs.webview.usercontent.new("ms")
            _ucMS:setCallback(function(message)
                local ok, data = pcall(hs.json.decode, message.body)
                if not ok or type(data) ~= "table" or not data.action then
                    print("ms.ui: malformed message from panel: " .. tostring(message.body))
                    return
                end
                local handler = ms.ui._actions[data.action]
                if not handler then
                    print("ms.ui: unknown action from panel: " .. tostring(data.action))
                    return
                end
                local ok2, err = pcall(handler, data)
                if not ok2 then
                    print("ms.ui: action '" .. data.action .. "' error: " .. tostring(err))
                end
            end)

            -- Positions the panel in the left half of the screen — centred between
            -- the left edge and the screen midpoint, near the top of the usable area.
            local function _panelFrame()
                local screen = hs.screen.mainScreen():frame()
                local w, h = panelW, panelH
                -- Expand 1.25× when a UI Frame Cosmetic is set for the settings panel.
                -- The extra space is pure padding for the frame; inner content unchanged.
                if type(ms._theme and ms._theme.uifc) == "table"
                    and ms._theme.uifc.settings ~= "" then
                    local wp = os.getenv("HOME") .. "/.hammerspoon/" .. ms._theme.uifc.settings
                    if hs.fs.attributes(wp) then
                        w = math.floor(w * 1.25)
                        h = math.floor(h * 1.25)
                    end
                end
                -- X: centred between the left screen edge and the screen midpoint.
                local x = screen.x + math.floor((screen.w / 2 - w) / 2)
                -- Y: vertically centred on the usable screen area.
                local y = screen.y + math.floor((screen.h - h) / 2)
                h = math.min(h, (screen.y + screen.h) - y - 20)
                return { x = x, y = y, w = w, h = h }
            end

            local function _buildPanel()
                local panel = hs.webview.new(_panelFrame(), { developerExtrasEnabled = true }, _ucMS)
                if not panel then return nil end
                -- Borderless (0): no title bar, no traffic lights, no chrome.
                -- The HTML has its own close button; native window decorations aren't needed.
                -- shadow(true) keeps depth cues without any chrome.
                pcall(function() panel:windowStyle(0) end)
                pcall(function() panel:level(hs.canvas.windowLevels.floating) end)
                pcall(function() panel:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces) end)
                pcall(function() panel:allowTextEntry(true) end)
                pcall(function() panel:shadow(true) end)
                pcall(function() panel:closeOnEscape(true) end)
                -- Keep _open in sync when the user closes via the X button or Escape.
                pcall(function()
                    panel:windowCallback(function(action)
                        if action == "closing" then
                            ms.ui._open     = false
                            ms.ui._panel    = nil   -- nil out stale ref; next show() will rebuild
                            ms.ui._panelPos = nil   -- discard tracked position; will re-seed on next show()
                            ms._inputOpen = true -- suppress spurious "Macros: ENABLED" toast
                            ms.playSlot("settingsClose")
                            local roblox = hs.application.get("Roblox")
                            if roblox then
                                hs.timer.doAfter(0.05, function()
                                    local ok, win = pcall(function() return roblox:mainWindow() end)
                                    if ok and win then pcall(function() win:focus() end) end
                                    pcall(function() roblox:activate() end)
                                end)
                            end
                        end
                    end)
                end)
                panel:html(_loadPanelHTML(), uiBasePath)
                return panel
            end

            ms.ui.show = function()
                if not ms.ui._panel then
                    ms.ui._panel = _buildPanel()
                    if not ms.ui._panel then
                        ms.alert("Settings panel failed to load — check the Hammerspoon Console.", 5)
                        return
                    end
                end
                local _pf = _panelFrame()
                ms.ui._panelPos = { x = _pf.x, y = _pf.y, w = _pf.w, h = _pf.h }
                pcall(function() ms.ui._panel:frame(_pf) end)
                ms.ui._panel:show()
                pcall(function() ms.ui._panel:bringToFront(true) end)
                ms.ui._open = true
                ms.playSlot("settingsOpen")
                ms.ui.refresh()
            end

            ms.ui.hide = function()
                if ms.ui._panel then ms.ui._panel:hide() end
                if ms.ui._open then ms.playSlot("settingsClose") end
                ms.ui._open = false
                -- Restore Roblox focus silently via the _inputOpen path.
                local roblox = hs.application.get("Roblox")
                if roblox then
                    ms._inputOpen = true
                    hs.timer.doAfter(0.05, function()
                        local ok, win = pcall(function() return roblox:mainWindow() end)
                        if ok and win then pcall(function() win:focus() end) end
                        pcall(function() roblox:activate() end)
                    end)
                end
            end

            ms.ui.toggle = function()
                if ms.ui._open then ms.ui.hide() else ms.ui.show() end
            end

            -- ── ms.ui.modal(data, callback) ─────────────────────────────────────────────
            -- Shows an HTML confirmation modal in the settings panel.
            -- Opens the panel automatically if not currently visible.
            -- data:     { title, msg, confirm, cancel }
            -- callback: function({ confirmed = bool })
            --
            ms.ui.modal = function(data, callback)
                if not callback then return end
                if not ms.ui._panel then
                    pcall(callback, { confirmed = false })
                    return
                end
                ms.ui._modalCallback = callback
                if not ms.ui._open then ms.ui.show() end
                local ok, json = pcall(hs.json.encode, {
                    title   = data.title   or "",
                    msg     = data.msg     or "",
                    confirm = data.confirm or "OK",
                    cancel  = data.cancel  or "Cancel",
                })
                if not ok then pcall(callback, { confirmed = false }); return end
                hs.timer.doAfter(0.05, function()
                    pcall(function()
                        ms.ui._panel:evaluateJavaScript("openLuaModal(" .. json .. ")")
                    end)
                end)
            end

            -- ── ms.ui.prompt(data, callback) ─────────────────────────────────────────────
            -- Shows an HTML text-input modal in the settings panel.
            -- Opens the panel automatically if not currently visible.
            -- data:     { title, msg, confirm, cancel, default }
            -- callback: function({ confirmed = bool, value = string })
            --
            ms.ui.prompt = function(data, callback)
                if not callback then return end
                if not ms.ui._panel then
                    pcall(callback, { confirmed = false, value = "" })
                    return
                end
                ms.ui._modalCallback = callback
                if not ms.ui._open then ms.ui.show() end
                local ok, json = pcall(hs.json.encode, {
                    title        = data.title   or "",
                    msg          = data.msg     or "",
                    confirm      = data.confirm or "OK",
                    cancel       = data.cancel  or "Cancel",
                    hasInput     = true,
                    inputDefault = data.default or "",
                })
                if not ok then pcall(callback, { confirmed = false, value = "" }); return end
                hs.timer.doAfter(0.05, function()
                    pcall(function()
                        ms.ui._panel:evaluateJavaScript("openLuaModal(" .. json .. ")")
                    end)
                end)
            end
        -- END --

        -- 13. Developer Panels --
            do
                local _devBase = "file://" .. os.getenv("HOME") .. "/.hammerspoon/ui/"
                local _home    = os.getenv("HOME")

                -- Helper: read the dev log and push history to a panel.
                local function _loadDevHistory(panel, filter)
                    local f = io.open(_devLogPath, "r")
                    if not f then return end
                    local entries = {}
                    for line in f:lines() do
                        local ok, entry = pcall(hs.json.decode, line)
                        if ok and entry and (not filter or filter(entry)) then
                            table.insert(entries, entry)
                        end
                    end
                    f:close()
                    if #entries == 0 then return end
                    local ok, json = pcall(hs.json.encode, entries)
                    if ok then
                        pcall(function()
                            panel:evaluateJavaScript("loadHistory(" .. json .. ")")
                        end)
                    end
                end

                -- Helper: build a JS snippet that injects the current ms._theme
                -- colors into a dev panel's CSS variables. Called in each panel's
                -- navigationCallback so the panel stays in sync with the theme file.
                local function _devThemeJS()
                    local t = ms._theme or {}
                    local parts = {}
                    local function sv(prop, key)
                        local val = t[key]
                        if type(val) == "string" then
                            -- Sanitize: only accept valid hex colors or named values
                            if val:match("^#[0-9a-fA-F]+$") or val:match("^rgb") then
                                table.insert(parts, string.format("r.setProperty('%s','%s')", prop, val))
                            end
                        end
                    end
                    sv("--bg",       "bg")
                    sv("--surface",  "surface")
                    sv("--surface2", "surface2")
                    sv("--accent",   "accent")
                    sv("--text",     "text")
                    -- text2 is derived: we use warning color for mouse/scroll highlights
                    sv("--mouse",    "warning")
                    if type(t.radius) == "number" then
                        table.insert(parts, string.format("r.setProperty('--radius','%dpx')", math.max(0, t.radius)))
                    end
                    -- Font family
                    local font = t.font
                    if type(font) == "string" and font ~= "" and not font:match("%.[ot]tf$") and not font:match("%.woff") then
                        local safe = font:gsub("'", "\'")
                        table.insert(parts, string.format("document.body.style.fontFamily=\"'%s',Palatino,Georgia,serif\"", safe))
                    end
                    if #parts == 0 then return "" end
                    return "(function(){var r=document.documentElement.style;" .. table.concat(parts, ";") .. "})()"
                end

                -- Helper: make a small floating panel.
                local function _makeDevPanel(ucName, w, h, xOff, yOff)
                    local uc = hs.webview.usercontent.new(ucName)
                    local screen = hs.screen.mainScreen():frame()
                    local x = screen.x + screen.w - w - xOff
                    local y = screen.y + yOff
                    local panel = hs.webview.new({ x=x, y=y, w=w, h=h }, { developerExtrasEnabled = true }, uc)
                    if not panel then return nil, uc end
                    pcall(function() panel:windowStyle(0) end)
                    pcall(function() panel:level(hs.canvas.windowLevels.floating) end)
                    pcall(function() panel:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces) end)
                    pcall(function() panel:allowTextEntry(true) end)
                    pcall(function() panel:shadow(true) end)
                    return panel, uc, { x=x, y=y, w=w, h=h }
                end

                -- ── Console ───────────────────────────────────────────────────────────
                local _ucCon = hs.webview.usercontent.new("msConsole")
                _ucCon:setCallback(function(msg)
                    local ok, data = pcall(hs.json.decode, msg.body)
                    if not ok or type(data) ~= "table" then return end
                    if data.action == "execute" and data.code then
                        -- Try as expression, fall back to statement.
                        local fn, err = load("return " .. data.code)
                        if not fn then fn, err = load(data.code) end
                        if not fn then
                            _devWrite({ type = "error", msg = err or "syntax error" })
                        else
                            local res = table.pack(pcall(fn))
                            local success = table.remove(res, 1)
                            if not success then
                                _devWrite({ type = "error", msg = tostring(res[1]) })
                            elseif #res > 0 then
                                local parts = {}
                                for _, v in ipairs(res) do parts[#parts+1] = tostring(v) end
                                _devWrite({ type = "result", msg = table.concat(parts, "\t") })
                            end
                        end
                    elseif data.action == "clear" then
                        local f = io.open(_devLogPath, "w"); if f then f:close() end
                    elseif data.action == "close" then
                        if ms.dev._consolePanel then ms.dev._consolePanel:hide() end
                        ms.dev._consoleOpen = false
                    elseif data.action == "openWatcher" then
                        ms.dev.watcher.show()
                    elseif data.action == "openKeys" then
                        ms.dev.keys.show()
                    elseif data.action == "move" and ms.dev._consolePanelPos then
                        ms.dev._consolePanelPos.x = ms.dev._consolePanelPos.x + (data.dx or 0)
                        ms.dev._consolePanelPos.y = ms.dev._consolePanelPos.y + (data.dy or 0)
                        if ms.dev._consolePanel then
                            pcall(function() ms.dev._consolePanel:frame(ms.dev._consolePanelPos) end)
                        end
                    end
                end)

                ms.dev.console = {}
                ms.dev.console.show = function()
                    if not ms.dev._consolePanel then
                        local screen  = hs.screen.mainScreen():frame()
                        local w, h    = 360, 640
                        local x = screen.x + screen.w - w - 20
                        local y = screen.y + 20
                        local panel = hs.webview.new({ x=x, y=y, w=w, h=h },
                            { developerExtrasEnabled = true }, _ucCon)
                        if not panel then return end
                        pcall(function() panel:windowStyle(0) end)
                        pcall(function() panel:level(hs.canvas.windowLevels.floating) end)
                        pcall(function() panel:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces) end)
                        pcall(function() panel:allowTextEntry(true) end)
                        pcall(function() panel:shadow(true) end)
                        local html = io.open(_home .. "/.hammerspoon/ui/ms_console.html", "r")
                        if html then
                            panel:html(html:read("*all"), _devBase); html:close()
                        end
                        ms.dev._consolePanel    = panel
                        ms.dev._consolePanelPos = { x=x, y=y, w=w, h=h }
                        panel:navigationCallback(function()
                            _loadDevHistory(panel, function(e)
                                return e.type == "macro" or e.type == "print"
                                    or e.type == "result" or e.type == "error"
                                    or e.type == "input"
                            end)
                            local tj = _devThemeJS(); if tj ~= "" then pcall(function() panel:evaluateJavaScript(tj) end) end
                        end)
                    end
                    ms.dev._consolePanel:show()
                    pcall(function() ms.dev._consolePanel:bringToFront(true) end)
                    ms.dev._consoleOpen = true
                    ms.playSlot("settingsOpen")
                end
                ms.dev.console.hide   = function()
                    if ms.dev._consolePanel then
                        ms.playSlot("settingsClose")
                        ms.dev._consolePanel:hide()
                    end
                    ms.dev._consoleOpen = false
                end
                ms.dev.console.toggle = function()
                    if ms.dev._consoleOpen then ms.dev.console.hide()
                    else ms.dev.console.show() end
                end

                -- ── Macro Watcher ─────────────────────────────────────────────────────
                local _ucWatcher = hs.webview.usercontent.new("msWatcher")
                _ucWatcher:setCallback(function(msg)
                    local ok, data = pcall(hs.json.decode, msg.body)
                    if not ok or type(data) ~= "table" then return end
                    if data.action == "clear" then
                        -- Clear only macro/print/error entries from the log (keep keys).
                        -- Simplest: just clear the whole log.
                        local f = io.open(_devLogPath, "w"); if f then f:close() end
                    elseif data.action == "close" then
                        if ms.dev._watcherPanel then ms.dev._watcherPanel:hide() end
                        ms.dev._watcherOpen = false
                    elseif data.action == "move" and ms.dev._watcherPanelPos then
                        ms.dev._watcherPanelPos.x = ms.dev._watcherPanelPos.x + (data.dx or 0)
                        ms.dev._watcherPanelPos.y = ms.dev._watcherPanelPos.y + (data.dy or 0)
                        if ms.dev._watcherPanel then
                            pcall(function() ms.dev._watcherPanel:frame(ms.dev._watcherPanelPos) end)
                        end
                    end
                end)

                ms.dev.watcher = {}
                ms.dev.watcher.show = function()
                    if not ms.dev._watcherPanel then
                        local screen  = hs.screen.mainScreen():frame()
                        local w, h    = 360, 640
                        local x = screen.x + screen.w - w - 20
                        local y = screen.y + 44
                        local panel = hs.webview.new({ x=x, y=y, w=w, h=h },
                            { developerExtrasEnabled = true }, _ucWatcher)
                        if not panel then return end
                        pcall(function() panel:windowStyle(0) end)
                        pcall(function() panel:level(hs.canvas.windowLevels.floating) end)
                        pcall(function() panel:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces) end)
                        pcall(function() panel:shadow(true) end)
                        local html = io.open(_home .. "/.hammerspoon/ui/ms_watcher.html", "r")
                        if html then
                            panel:html(html:read("*all"), _devBase); html:close()
                        end
                        ms.dev._watcherPanel    = panel
                        ms.dev._watcherPanelPos = { x=x, y=y, w=w, h=h }
                        panel:navigationCallback(function()
                            _loadDevHistory(panel, function(e)
                                return e.type=="macro" or e.type=="print" or e.type=="error"
                            end)
                            local tj = _devThemeJS(); if tj ~= "" then pcall(function() panel:evaluateJavaScript(tj) end) end
                        end)
                    end
                    ms.dev._watcherPanel:show()
                    pcall(function() ms.dev._watcherPanel:bringToFront(true) end)
                    ms.dev._watcherOpen = true
                    ms.playSlot("settingsOpen")
                end
                ms.dev.watcher.hide   = function()
                    if ms.dev._watcherPanel then
                        ms.playSlot("settingsClose")
                        ms.dev._watcherPanel:hide()
                    end
                    ms.dev._watcherOpen = false
                end
                ms.dev.watcher.toggle = function()
                    if ms.dev._watcherOpen then ms.dev.watcher.hide()
                    else ms.dev.watcher.show() end
                end

                -- ── Key Monitor ───────────────────────────────────────────────────────
                local _ucKeys = hs.webview.usercontent.new("msKeys")
                _ucKeys:setCallback(function(msg)
                    local ok, data = pcall(hs.json.decode, msg.body)
                    if not ok or type(data) ~= "table" then return end
                    if data.action == "clear" then
                        local f = io.open(_devLogPath, "w"); if f then f:close() end
                    elseif data.action == "close" then
                        if ms.dev._keysPanel then ms.dev._keysPanel:hide() end
                        ms.dev._keysOpen = false
                    elseif data.action == "move" and ms.dev._keysPanelPos then
                        ms.dev._keysPanelPos.x = ms.dev._keysPanelPos.x + (data.dx or 0)
                        ms.dev._keysPanelPos.y = ms.dev._keysPanelPos.y + (data.dy or 0)
                        if ms.dev._keysPanel then
                            pcall(function() ms.dev._keysPanel:frame(ms.dev._keysPanelPos) end)
                        end
                    end
                end)

                ms.dev.keys = {}
                ms.dev.keys.show = function()
                    if not ms.dev._keysPanel then
                        local screen  = hs.screen.mainScreen():frame()
                        local w, h    = 360, 640
                        local x = screen.x + screen.w - w - 20
                        local y = screen.y + 68
                        local panel = hs.webview.new({ x=x, y=y, w=w, h=h },
                            { developerExtrasEnabled = true }, _ucKeys)
                        if not panel then return end
                        pcall(function() panel:windowStyle(0) end)
                        pcall(function() panel:level(hs.canvas.windowLevels.floating) end)
                        pcall(function() panel:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces) end)
                        pcall(function() panel:shadow(true) end)
                        local html = io.open(_home .. "/.hammerspoon/ui/ms_keys.html", "r")
                        if html then
                            panel:html(html:read("*all"), _devBase); html:close()
                        end
                        ms.dev._keysPanel    = panel
                        ms.dev._keysPanelPos = { x=x, y=y, w=w, h=h }
                        panel:navigationCallback(function()
                            -- Seed the actual current mouse position on page load.
                            local _p = hs.mouse.absolutePosition()
                            ms.dev._mousePos = { x = math.floor(_p.x), y = math.floor(_p.y) }
                            _loadDevHistory(panel, function(e)
                                return e.type=="key" or e.type=="mouse"
                                    or e.type=="scroll" or e.type=="mousemove"
                            end)
                            pcall(function() ms.dev._pushMouseState() end)
                            local tj = _devThemeJS(); if tj ~= "" then pcall(function() panel:evaluateJavaScript(tj) end) end
                        end)
                    end
                    ms.dev._keysPanel:show()
                    pcall(function() ms.dev._keysPanel:bringToFront(true) end)
                    ms.dev._keysOpen = true
                    ms.playSlot("settingsOpen")
                    -- Poll mouse position every 100 ms so display stays current
                    if ms.dev._mousePoller then ms.dev._mousePoller:stop() end
                    ms.dev._mousePoller = hs.timer.doEvery(0.1, function()
                        if not ms.dev._keysPanel then
                            if ms.dev._mousePoller then
                                ms.dev._mousePoller:stop(); ms.dev._mousePoller = nil
                            end
                            return
                        end
                        local _p = hs.mouse.absolutePosition()
                        local _x, _y = math.floor(_p.x), math.floor(_p.y)
                        if _x ~= ms.dev._mousePos.x or _y ~= ms.dev._mousePos.y then
                            ms.dev._mousePos = { x = _x, y = _y }
                            ms.dev._pushMouseState(_x, _y)
                        end
                    end)
                end
                ms.dev.keys.hide   = function()
                    if ms.dev._mousePoller then
                        ms.dev._mousePoller:stop(); ms.dev._mousePoller = nil
                    end
                    if ms.dev._keysPanel then
                        ms.playSlot("settingsClose")
                        ms.dev._keysPanel:hide()
                    end
                    ms.dev._keysOpen = false
                end
                ms.dev.keys.toggle = function()
                    if ms.dev._keysOpen then ms.dev.keys.hide()
                    else ms.dev.keys.show() end
                end

                -- ── Mouse state pusher ────────────────────────────────────────────────
                -- Defined here so both the nav callback and the poller can call it.
                ms.dev._pushMouseState = function(x, y)
                    if not ms.dev._keysPanel then return end
                    local _x = x or (ms.dev._mousePos and ms.dev._mousePos.x) or 0
                    local _y = y or (ms.dev._mousePos and ms.dev._mousePos.y) or 0
                    local j = string.format('{"x":%d,"y":%d}', _x, _y)
                    pcall(function()
                        ms.dev._keysPanel:evaluateJavaScript("updateMouseState(" .. j .. ")")
                    end)
                end

                -- ── Dev step logger (call from macros to trace execution) ────────────────
                ms.dev.step = function(msg)
                    if not ms.dev._watcherPanel then return end
                    local ok, j = pcall(hs.json.encode, {
                        type = "step",
                        ts   = os.time(),
                        msg  = tostring(msg or ""),
                    })
                    if ok then
                        pcall(function()
                            ms.dev._watcherPanel:evaluateJavaScript("appendEntry(" .. j .. ")")
                        end)
                    end
                end

                -- ── Window Monitor ────────────────────────────────────────────────────
                local _ucWindow = hs.webview.usercontent.new("msWindow")
                _ucWindow:setCallback(function(msg)
                    local ok, data = pcall(hs.json.decode, msg.body)
                    if not ok or type(data) ~= "table" then return end
                    if data.action == "clear" then
                        ms.dev._windowHistory = {}
                    elseif data.action == "close" then
                        if ms.dev._windowPanel then ms.dev._windowPanel:hide() end
                        ms.dev._windowOpen = false
                        if ms.dev._windowPoller then
                            ms.dev._windowPoller:stop(); ms.dev._windowPoller = nil
                        end
                    elseif data.action == "move" and ms.dev._windowPanelPos then
                        ms.dev._windowPanelPos.x = ms.dev._windowPanelPos.x + (data.dx or 0)
                        ms.dev._windowPanelPos.y = ms.dev._windowPanelPos.y + (data.dy or 0)
                        if ms.dev._windowPanel then
                            pcall(function() ms.dev._windowPanel:frame(ms.dev._windowPanelPos) end)
                        end
                    end
                end)

                ms.dev._windowHistory = {}
                ms.dev._windowMaxHistory = 80
                ms.dev._windowLast = nil  -- last focused window id, for change detection

                -- Push an entry into the panel and history ring buffer.
                local function _pushWindowEvent(entry)
                    table.insert(ms.dev._windowHistory, entry)
                    if #ms.dev._windowHistory > ms.dev._windowMaxHistory then
                        table.remove(ms.dev._windowHistory, 1)
                    end
                    if ms.dev._windowPanel then
                        local ok, j = pcall(hs.json.encode, entry)
                        if ok then
                            pcall(function()
                                ms.dev._windowPanel:evaluateJavaScript(
                                    "appendEntry(" .. j .. ");updateCurrentWindow(" .. j .. ")"
                                )
                            end)
                        end
                    end
                end

                ms.dev.window = {}
                ms.dev.window.show = function()
                    if not ms.dev._windowPanel then
                        local screen = hs.screen.mainScreen():frame()
                        local w, h   = 360, 520
                        local x = screen.x + screen.w - w - 20
                        local y = screen.y + 68
                        local panel = hs.webview.new({ x=x, y=y, w=w, h=h },
                            { developerExtrasEnabled = true }, _ucWindow)
                        if not panel then return end
                        pcall(function() panel:windowStyle(0) end)
                        pcall(function() panel:level(hs.canvas.windowLevels.floating) end)
                        pcall(function() panel:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces) end)
                        pcall(function() panel:shadow(true) end)
                        local html = io.open(_home .. "/.hammerspoon/ui/ms_window.html", "r")
                        if html then
                            panel:html(html:read("*all"), _devBase); html:close()
                        end
                        ms.dev._windowPanel    = panel
                        ms.dev._windowPanelPos = { x=x, y=y, w=w, h=h }
                        panel:navigationCallback(function()
                            -- Push theme CSS.
                            local tj = _devThemeJS()
                            if tj ~= "" then pcall(function() panel:evaluateJavaScript(tj) end) end
                            -- Load history.
                            if #ms.dev._windowHistory > 0 then
                                local ok, j = pcall(hs.json.encode, ms.dev._windowHistory)
                                if ok then pcall(function() panel:evaluateJavaScript("loadHistory(" .. j .. ")") end) end
                            end
                            -- Seed the current window.
                            local win = hs.window.focusedWindow()
                            if win then
                                local app   = (win:application() and win:application():name()) or "?"
                                local title = win:title() or ""
                                local f     = win:frame()
                                local ok2, j2 = pcall(hs.json.encode, {
                                    type="focus", ts=os.time(),
                                    app=app, title=title,
                                    w=math.floor(f.w), h=math.floor(f.h),
                                    x=math.floor(f.x), y=math.floor(f.y),
                                })
                                if ok2 then pcall(function() panel:evaluateJavaScript("updateCurrentWindow(" .. j2 .. ")") end) end
                            end
                        end)
                    end
                    ms.dev._windowPanel:show()
                    pcall(function() ms.dev._windowPanel:bringToFront(true) end)
                    ms.dev._windowOpen = true
                    ms.playSlot("settingsOpen")
                    -- Poll every 0.4 s for focused window changes.
                    if ms.dev._windowPoller then ms.dev._windowPoller:stop() end
                    ms.dev._windowPoller = hs.timer.doEvery(0.4, function()
                        if not ms.dev._windowOpen then
                            if ms.dev._windowPoller then ms.dev._windowPoller:stop(); ms.dev._windowPoller = nil end
                            return
                        end
                        local win = hs.window.focusedWindow()
                        if not win then return end
                        local winId = win:id()
                        if winId == ms.dev._windowLast then return end
                        ms.dev._windowLast = winId
                        local app   = (win:application() and win:application():name()) or "?"
                        local title = win:title() or ""
                        local f     = win:frame()
                        _pushWindowEvent({
                            type="focus", ts=os.time(),
                            app=app, title=title,
                            w=math.floor(f.w), h=math.floor(f.h),
                            x=math.floor(f.x), y=math.floor(f.y),
                        })
                    end)
                end
                ms.dev.window.hide = function()
                    if ms.dev._windowPoller then ms.dev._windowPoller:stop(); ms.dev._windowPoller = nil end
                    if ms.dev._windowPanel then
                        ms.playSlot("settingsClose")
                        ms.dev._windowPanel:hide()
                    end
                    ms.dev._windowOpen = false
                end
                ms.dev.window.toggle = function()
                    if ms.dev._windowOpen then ms.dev.window.hide()
                    else ms.dev.window.show() end
                end
            end
        -- END --

        -- 12. Safety Nets --
            -- Load ms_macros.lua inside a restricted sandbox environment.
            -- Blocks direct hs API access, require, filesystem ops, and environment
            -- escape hatches. The ms table is wrapped in a proxy that errors on any
            -- write except ms.macroMeta.
            --
            -- Note: unknown globals fall through to the real _G rather than erroring.
            -- This is a conservative bridge; once §1.2 (ms.fn) lands and all direct
            -- coroutine usage is wrapped, this fallback can be tightened to error on
            -- any unlisted global.
            do
                local macrosPath = os.getenv("HOME") .. "/.hammerspoon/ms_macros.lua"

                -- Frozen ms proxy: permits reads of all existing ms.* keys,
                -- permits ms.macroMeta writes only; ms.macroDefaults is owned by init.lua.
                -- ms.integrity is explicitly hidden: macros have no legitimate use for
                -- integrity functions and could call deleteTrustedHash() to silently
                -- disable tamper protection.  ms.has("integrity") still works because
                -- it calls ms.integrity.check() from privileged scope, not through this proxy.
                local frozenMs = setmetatable({}, {
                    __index    = function(t, k)
                        if k == "integrity" or k == "dev" then
                            error("ms_macros.lua: ms." .. k .. " is not accessible from macros.", 2)
                        end
                        return ms[k]
                    end,
                    __newindex = function(t, k, v)
                        if k == "macroMeta" then
                            rawset(ms, k, v)
                        else
                            error("ms_macros.lua: unauthorized write to ms." .. tostring(k)
                                .. "  —  only ms.macroMeta and ms.bind.define are permitted.", 2)
                        end
                    end,
                })

                -- Globals that are explicitly blocked and will error on access.
                local BLOCKED = {
                    hs=true, require=true, os=true, io=true,
                    _G=true, load=true, loadfile=true, loadstring=true,
                    dofile=true, rawget=true, rawset=true,
                    debug=true, package=true, collectgarbage=true,
                    setfenv=true, getfenv=true,
                    setmetatable=true, getmetatable=true,
                    -- Live globals reachable via the _G fallthrough that macro code
                    -- must not touch.  These are the runtime counterparts of the
                    -- scanner-only checks (:activate, :launch, etc.): even if the
                    -- lexer pass above is somehow confused, access is still denied here.
                    roblox=true,               -- hs.application handle; :activate() risk
                    -- _G-scoped handles that carry dangerous methods (:stop() etc.).
                    -- Macro code must not be able to halt the integrity timer, kill the
                    -- app watcher, or otherwise manipulate Hammerspoon's own internals.
                    __ms_appWatcher=true,        -- hs.eventtap: :stop() kills app monitoring
                    _integrityPollTimer=true,    -- hs.timer: :stop() disables integrity poll
                    _initTimer=true,             -- hs.timer: deferred init timer
                }

                local sandbox = {
                    ms        = frozenMs,
                    -- Safe Lua builtins
                    math      = math,
                    string    = string,
                    table     = table,
                    coroutine = coroutine,  -- needed until ms.fn replaces direct coroutine use
                    ipairs    = ipairs,
                    pairs     = pairs,
                    next      = next,
                    select    = select,
                    pcall     = pcall,
                    xpcall    = xpcall,
                    tostring  = tostring,
                    tonumber  = tonumber,
                    type      = type,
                    unpack    = table.unpack or unpack,
                    error     = error,
                    assert    = assert,
                    print     = print,
                    -- ms.Mouse operation constants (seeded explicitly so the sandbox
                    -- __newindex cannot overwrite them in _G via the fallthrough).
                    Move        = Move,        Click       = Click,       DoubleClick  = DoubleClick,
                    TripleClick = TripleClick, Drag        = Drag,        Press        = Press,
                    Release     = Release,
                    -- ms.Mouse button constants
                    Left        = Left,        Right       = Right,       Center       = Center,
                    Button4     = Button4,     Button5     = Button5,
                    -- ms.Mouse reference constants
                    Unscaled     = Unscaled,
                    Absolute     = Absolute,   Mouse        = Mouse,
                    WindowTL     = WindowTL,   WindowTR     = WindowTR,
                    WindowBL     = WindowBL,   WindowBR     = WindowBR,   WindowCenter = WindowCenter,
                    ScreenTL     = ScreenTL,   ScreenTR     = ScreenTR,
                    ScreenBL     = ScreenBL,   ScreenBR     = ScreenBR,   ScreenCenter = ScreenCenter,
                }

                setmetatable(sandbox, {
                    __index = function(t, k)
                        if BLOCKED[k] then
                            error("ms_macros.lua: access to '" .. tostring(k)
                                .. "' is not permitted.", 2)
                        end
                        -- Fall through to real globals (safe read-only bridge for any
                        -- additional constants the macro author may define in init.lua).
                        return rawget(_G, k)
                    end,
                    -- All global writes from ms_macros.lua are forbidden.
                    -- Previously this fell through to rawset(_G, k, v), which let macro
                    -- code silently overwrite init.lua globals such as BindValidity and
                    -- REF_W. Now any bare global assignment is a hard error; macro
                    -- authors must use 'local' for all variables.
                    __newindex = function(t, k, v)
                        error("ms_macros.lua: cannot write global '" .. tostring(k)
                            .. "' — use 'local' for all variables.", 2)
                    end,
                })

                -- Security audit: scan the raw source before any code is executed.
                -- Hard-errors on policy violations so a tampered file never reaches load().
                -- rawSrc is declared outside the do-block so the load() call below can
                -- compile the exact same bytes the auditor read, closing the TOCTOU window.
                local rawSrc
                do
                    local af = io.open(macrosPath, "r")
                    if not af then
                        error("ms_macros.lua: cannot open file for security audit: " .. macrosPath)
                    end
                    rawSrc = af:read("*all"); af:close()
                    local auditErrs = auditMacros(rawSrc)
                    if #auditErrs > 0 then
                        local msg = "ms_macros.lua failed security audit ("
                            .. #auditErrs .. " violation"
                            .. (#auditErrs > 1 and "s" or "") .. "):\n"
                        for _, e in ipairs(auditErrs) do
                            msg = msg .. "  \xe2\x80\xa2 " .. e .. "\n"
                        end
                        error(msg, 0)
                    end
                end

                -- Load the file with the sandbox as its environment.
                -- Lua 5.2+: loadfile accepts an env parameter directly.
                -- Lua 5.1 fallback: use setfenv if available.
                local chunk, loadErr
                if _VERSION and _VERSION >= "Lua 5.2" or not setfenv then
                    -- Use load() on the already-read source bytes rather than re-opening
                    -- the file with loadfile().  This closes the TOCTOU window: auditMacros
                    -- ran on rawSrc; load() compiles those exact same bytes, so there is no
                    -- opportunity for another process to swap the file between the audit
                    -- read and the load step.
                    chunk, loadErr = load(rawSrc, "@ms_macros.lua", "bt", sandbox)
                else
                    -- Lua 5.1 fallback (LuaJIT should never reach here).
                    chunk, loadErr = loadstring(rawSrc, "@ms_macros.lua")
                    if chunk then setfenv(chunk, sandbox) end
                end
                if not chunk then
                    error("ms_macros.lua: failed to load: " .. tostring(loadErr))
                end
                local ok, runErr = pcall(chunk)
                if not ok then
                    error("ms_macros.lua: error during execution: " .. tostring(runErr))
                end

                -- Validation pass
                if not ms.macroMeta then
                    print("Warning: ms_macros.lua did not set ms.macroMeta.")
                    hs.timer.doAfter(0.5, function()
                        ms.alert("Warning: ms_macros.lua did not declare ms.macroMeta.", 6)
                    end)
                end
                if not next(ms.registry._defs) then
                    error("ms_macros.lua: no ms.bind.define calls found — file may be malformed.")
                end
            end

            -- Macro pack preferred defaults — seeded into ms_settings_default.json on first run.
            -- Defined here (not in ms_macros.lua) so they cannot be accidentally removed by the user.
            -- Values already saved in ms_settings.json always take priority and are never overwritten.
            ms.macroDefaults = {
                sensitivity  = 1.5,
                frameLevel   = 3,
                trackpadMode = false,
                socdEnabled  = false,
                socdMode     = "lastWins",
                macros = {
                    spawnAlt = { enabled = false },
                },
            }
        -- END Safety Nets --
    -- END Hammerspoon mudscript Utility Library --

    -- Startup Executions --
        -- Seed ms.binds from registry defaults for any id not set by the settings file.
        for _, id in ipairs(ms.registry._defList) do
            local def = ms.registry._defs[id]
            if def and not def.sub and ms.binds[id] == nil then
                ms.binds[id] = def.enabled
            end
        end
        ms._discoverSounds()
        ms.loadSettings()
        ms.loadTheme()
        ms.cam.updateMultiplier()
        ms.bind.rebind()
        ms.socdApply()
        -- System integrity: mismatch is impossible here — the guardian blocked it at
        -- load time before any ms code ran.  If no trusted hash exists yet, try to
        -- auto-seed from MANIFEST.json before showing the manual-trust reminder.
        -- This means a clean install cloned from GitHub is trusted silently on first
        -- run — no "Trust Current Version" needed — as long as the developer kept
        -- MANIFEST.json in sync (via bin/make_release.sh) before pushing.
        hs.timer.doAfter(3, function()
            if ms.integrity.check() ~= "uninitialized" then return end
            -- Attempt bootstrap: read sha256 from MANIFEST.json and compare to
            -- the live file.  Only trust if they match exactly — this prevents
            -- a stale or tampered MANIFEST from silently seeding the wrong hash.
            local _mPath = os.getenv("HOME") .. "/.hammerspoon/MANIFEST.json"
            local _mf    = io.open(_mPath, "r")
            if _mf then
                local _ok, _manifest = pcall(hs.json.decode, _mf:read("*all")); _mf:close()
                if _ok and type(_manifest) == "table"
                    and type(_manifest.sha256) == "string"
                    and #_manifest.sha256 == 64 then
                    local _cur = ms.integrity.hashFile(corePath)
                    if _cur and _cur:lower() == _manifest.sha256:lower() then
                        ms.integrity.writeTrustedHash(_cur)
                        return  -- clean install — seeded silently, no alert needed
                    end
                end
            end
            -- MANIFEST missing, stale, or hash mismatch — ask the user to trust manually.
            ms.alert("\xe2\x9a\xa0 No trusted hash on record.\nSettings \xe2\x86\x92 Developer \xe2\x86\x92 Trust Current Version.", 10)
        end)
        -- Play the load-complete sound right after startup finishes.
        -- loadfinish is still 0 here (toast suppression), but playSlot
        -- doesn't need it — it just plays whichever file is assigned.

        roblox:activate()

        notice = 0
        loadfinish = 0

        _G._loadfinishTimer = hs.timer.doAfter(3000 / 1000, function()
            _G._loadfinishTimer = nil
            loadfinish = 1
        end)

        -- Periodic system integrity check — runs every 60 s once macros are fully loaded.
        -- If ms_core.lua has been tampered with since it was trusted, the guardian seizes
        -- control immediately without requiring a manual check.
        _G._integrityPollTimer = hs.timer.doEvery(5, function()
            if loadfinish ~= 1 then return end  -- skip startup grace period
            local status = ms.integrity.check()
            if status == "mismatch" then
                hs.reload()  -- startup guardian will halt ms_core.lua and show the dialog
            end
        end)

        if notice ~= 1 then
            hs.timer.doAfter(0.5, function()
                pcall(function()
                    ms.playSlot("load")
                    ms.alert("Hammerspoon mudscript Utility Library\nBy: mudbourn — https://mudbourn.info", 6)
                    if ms.macroMeta then
                        local msg = "\"" .. (ms.macroMeta.name or "Unknown Macro Pack") .. "\"\n"
                        if ms.macroMeta.author then msg = msg .. "By: " .. ms.macroMeta.author end
                        if ms.macroMeta.website then msg = msg .. " — " .. ms.macroMeta.website end
                        ms.alert(msg, 6)
                    end
                    ms.alert("Macros loaded. Press ⌥ and P to open settings.", 6)
                end)
            end)
            notice = 1
        end
    -- END Startup Executions --
-- END Core System --
