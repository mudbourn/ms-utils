-- Core System ---- PLEASE EDIT CAREFULLY --
    -- Hammerspoon mudscript Utility Library --
        -- 0. Pre-Load --
            -- hs.reload() leaves stale objects. Stop the prior generation before
            -- this load creates a new one. The primary guard is in init.lua.
                if _G.__ms_appWatcher then pcall(function() _G.__ms_appWatcher:stop() end) end
            -- END --

            -- Guardian moved to MsGuardian.spoon/init.lua --
            -- END --

            -- One-time migration: move settings/hash files from root into data/ --
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
            -- END --

            -- Font installation --
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
                        hs.reload(); return
                    end
                end
            -- END --
        -- END --

        -- 1. Prefix Variables & State Tracking --
            ms = {}
            ms.vars = {}
            ms.keytrack = {}
            ms._keyBindings = {}
            ms.bindConfig = {}
            ms.bindHandles = {}
            ms._activeSub = nil
            ms.systemBinds             = { _config = {}, _handles = {} }
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
            -- ms._targetHandle is refreshed on every reload via the target app lookup.

            ms._targetApp     = "Roblox"                   -- target application name; change via ms.setTargetApp()
            ms._targetHandle  = hs.application.get(ms._targetApp)  -- cached handle, refreshed on reload
            ms._robloxActive  = false  -- true while target app is focused
            ms._qrOptions = { macros = true, theme = true, settings = true, ui = true }
            ms.getTargetWin = function()
                local app = hs.application.get(ms._targetApp)
                if not app then return nil end
                local ok, win = pcall(function() return app:mainWindow() end)
                return (ok and win) or nil
            end

            -- Change the target application at runtime. Refreshes the cached handle
            -- and forces a watcher re-check. Pass nil to disable target-specific behavior.
            ms.setTargetApp = function(name)
                ms._targetApp    = name or nil
                ms._targetHandle = name and hs.application.get(name) or nil
                if ms._targetHandle then
                    ms._robloxActive = true
                end
            end
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
            ms._updateChannel     = "stable"  -- "stable" (MANIFEST.json) or "testing" (GitHub Actions)
            ms._testingWorkflow   = "testing" -- workflow filename (without .yml) for the testing channel
            ms._testingRepo       = "mudbourn/ms-utils"  -- GitHub owner/repo for Actions API

            -- RSA-2048 public key for MANIFEST.json signature verification.
            -- Matching private key: GitHub Secrets (MS_SIGNING_KEY).
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

            -- User Settings & Menu API State --
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
                    fadeMs   = 150,
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

                -- Developer Tools — ms.dev --
                ms.dev = {
                    _consolePanel    = nil,
                    _watcherPanel    = nil,
                    _keysPanel       = nil,
                    _consolePanelPos = nil,
                    _watcherPanelPos = nil,
                    _keysPanelPos    = nil,
                    _activeKeys      = {},
                    _activeButtons   = {},  -- button number → true while held
                    _coordMode       = "screen",  -- screen | window | ref | screenCenter
                }
                -- ── Dev Log Infrastructure ──────────────────────────────────
                -- Writes to per-category log files so you can tail just system
                -- events or just errors without input noise.
                --
                -- Categories:  input | macro | system | error | console
                -- Cat files:   ms_dev_logs/ms_dev_input.log    ms_dev_logs/ms_dev_system.log
                --              ms_dev_logs/ms_dev_macro.log    ms_dev_logs/ms_dev_error.log
                --              ms_dev_logs/ms_dev_console.log
                -- Archives:    ms_dev_logs/backups/  (pruned to limit per category)
                local _devLogDir  = os.getenv("HOME") .. "/Documents/"
                local _devBaseDir = _devLogDir .. "ms_dev_logs/"
                local _devArchDir = _devBaseDir .. "backups/"
                -- Map entry.type → category.  Entries with an explicit .category
                -- field are left alone; everything else goes through this table.
                local _typeToCategory = {
                    key       = "input",
                    mouse     = "input",
                    scroll    = "input",
                    mousemove = "input",
                    macro     = "macro",
                    system    = "system",
                    error     = "error",
                    warn      = "error",
                    print     = "console",
                    result    = "console",
                }

                -- Category → file path (built once).
                local _catPaths = {}
                for _, cat in ipairs({"input", "macro", "system", "error", "console"}) do
                    _catPaths[cat] = _devBaseDir .. "ms_dev_" .. cat .. ".log"
                end

                -- Archive helper: moves a log file into backups/ with a timestamp.
                local function _archiveLog(path, stamp)
                    if not hs.fs.attributes(path) then return end
                    hs.fs.mkdir(_devBaseDir)
                    hs.fs.mkdir(_devArchDir)
                    local base = path:match("([^/]+)%.log$")  -- e.g. "ms_dev_system"
                    os.rename(path, _devArchDir .. base .. "_" .. stamp .. ".log")
                end

                -- Prune helper: keep at most `limit` files matching a prefix pattern.
                local function _pruneArchives(prefixPattern, limit)
                    if not hs.fs.attributes(_devArchDir) then return end
                    local list = {}
                    for name in hs.fs.dir(_devArchDir) do
                        if name:match(prefixPattern) then table.insert(list, name) end
                    end
                    table.sort(list)
                    while #list > limit do
                        os.remove(_devArchDir .. list[1])
                        table.remove(list, 1)
                    end
                end

                -- On every reload, archive all log files so each session starts clean.
                do
                    local stamp = os.date("%Y-%m-%d_%H%M%S")
                    for _, p in pairs(_catPaths) do _archiveLog(p, stamp) end

                    -- Prune: category logs use the configurable archive limit.
                    local catLimit = (type(ms._devArchiveLimit) == "number" and ms._devArchiveLimit >= 0)
                        and ms._devArchiveLimit or 15
                    _pruneArchives("^ms_dev_%w+_%d%d%d%d%-%d%d%-%d%d_%d%d%d%d%d%d%.log$", catLimit)
                end

                local _devBusy = false
                local _devLastConsoleType = nil  -- last key/mouse/macro type sent; gates repeat suppression

                local function _devWrite(entry)
                    if _devBusy then return end
                    _devBusy = true
                    entry.ts = os.date("%H:%M:%S")

                    -- Derive category from type if not explicitly set.
                    if not entry.category then
                        entry.category = _typeToCategory[entry.type] or "system"
                    end

                    local ok, json = pcall(hs.json.encode, entry)
                    if not ok then _devBusy = false; return end

                    -- Write to category-specific log.
                    local catPath = _catPaths[entry.category]
                    if catPath then
                        pcall(function()
                            hs.fs.mkdir(_devBaseDir)
                            local f = io.open(catPath, "a")
                            if f then f:write(json .. "\n"); f:close() end
                        end)
                    end

                    -- Panel routing (unchanged logic).
                    local t = entry.type
                    -- Console routing with consecutive-repeat suppression.
                    -- key/mouse/macro: only send when the type changes from the last sent.
                    -- print/error/result/system: always send and reset the gate.
                    if ms.dev._consolePanel and t ~= "mousemove" then
                        local send = false
                        if t == "key" or t == "mouse" or t == "macro" then
                            if _devLastConsoleType ~= t then
                                _devLastConsoleType = t
                                send = true
                            end
                        else
                            _devLastConsoleType = nil
                            send = true
                        end
                        if send then
                            pcall(function()
                                ms.dev._consolePanel:evaluateJavaScript("appendEntry(" .. json .. ")")
                            end)
                        end
                    end
                    -- Watcher: macro, print, error, system
                    if ms.dev._watcherPanel and (t=="macro" or t=="print" or t=="error" or t=="system") then
                        pcall(function()
                            ms.dev._watcherPanel:evaluateJavaScript("appendEntry(" .. json .. ")")
                        end)
                    end
                    if ms.dev._keysPanel and ms.dev._keysReady
                        and (t=="key" or t=="mouse" or t=="scroll" or t=="mousemove") then
                        pcall(function()
                            ms.dev._keysPanel:evaluateJavaScript("appendEntry(" .. json .. ")")
                        end)
                    end
                    _devBusy = false
                end

                -- Public API: any code can call ms.dev.log({ type = "system", event = "...", ... })
                -- .category is auto-derived from .type unless you override it.
                ms.dev.log = function(entry) _devWrite(entry) end

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
                    if isDown then ms.dev._activeButtons[button] = true
                    else            ms.dev._activeButtons[button] = nil end
                    if ms.dev._keysPanel and ms.dev._keysReady then
                        local active = {}
                        for btn in pairs(ms.dev._activeButtons) do table.insert(active, btn) end
                        local aok, aj = pcall(hs.json.encode, { x = x, y = y, buttons = active })
                        if aok then
                            pcall(function()
                                ms.dev._keysPanel:evaluateJavaScript("updateMouseState(" .. aj .. ")")
                            end)
                        end
                    end
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

                        -- Read theme at render time so every toast reflects the current ms_theme.json.
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

                    return setmetatable({ dismissAll = dismissAll }, {
                        __call = function(_, msg, duration, noDefaultSound)
                            duration = duration or 5

                            -- Auto-log every alert to the dev log.  Heuristic:
                            -- error-like messages get category "error", rest get "system".
                            if ms.dev and ms.dev.log then
                                local isError = msg and (
                                    msg:find("[Ff]ailed") or msg:find("[Ee]rror")
                                    or msg:find("[Cc]ould not") or msg:find("[Cc]annot")
                                    or msg:find("[Rr]ejected") or msg:find("[Dd]enied")
                                    or msg:find("[Aa]borted")
                                )
                                ms.dev.log({
                                    type    = isError and "error" or "system",
                                    event   = "alert",
                                    msg     = (msg or ""):sub(1, 200),  -- truncate long messages
                                })
                            end

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

                -- User Settings — validation helpers --
                    local _SETTING_TYPES = {
                        toggle = true, slider    = true, seg       = true,
                        action = true, divider   = true, groupLabel = true,
                        soundSlot = true,  -- user-defined sound event slot
                        group     = true,  -- collapsible group of nested settings
                    }
                    local _HIDEABLE_FEATURES = {
                        socd             = true,
                        trackpad         = true,
                        independentBinds = true,
                        sensitivity      = true,
                    }
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

                    ms._applySettings = function(data)
                        if not data then return end
                        if data.sensitivity ~= nil then
                            local num = tonumber(data.sensitivity)
                            if num and num >= 0.1 and num <= 4 then CUR_CAM_SENS = num end
                        end
                        if data.frameLevel ~= nil then
                            -- frameLevel was the old baked-in persistence key for clickLevel.
                            -- Migrate it into the user settings table on load so the user
                            -- setting picks it up, then discard the root-level key.
                            data.user = data.user or {}
                            if data.user.clickLevel == nil then
                                local num = tonumber(data.frameLevel)
                                if num and num >= 1 and num <= 4 then
                                    data.user.clickLevel = num
                                end
                            end
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
                        if data.soundAssign and type(data.soundAssign) == "table" then
                            local _sa = {}
                            for k, v in pairs(data.soundAssign) do
                                -- Keys are slot IDs (strings); values must be plain sound names
                                -- with no path separators to prevent SoundLib boundary escapes.
                                if type(k) == "string" and type(v) == "string"
                                    and not v:find("[/\\]") and not v:find("%.%.")
                                then
                                    _sa[k] = v
                                end
                            end
                            ms.soundAssign = _sa
                        end
                        if data.importedSounds and type(data.importedSounds) == "table" then
                            local _is = {}
                            for k, v in pairs(data.importedSounds) do
                                if type(k) == "string" and type(v) == "string"
                                    and not v:find("[/\\]") and not v:find("%.%.")
                                then
                                    _is[k] = v
                                end
                            end
                            ms.importedSounds = _is
                        end
                        if data.quickReloaded ~= nil then ms._quickReloaded = tonumber(data.quickReloaded) or 0 end
                        if data.qrOptions and type(data.qrOptions) == "table" then
                            local qr = ms._qrOptions
                            if data.qrOptions.macros   ~= nil then qr.macros   = (data.qrOptions.macros   == true) end
                            if data.qrOptions.theme    ~= nil then qr.theme    = (data.qrOptions.theme    == true) end
                            if data.qrOptions.settings ~= nil then qr.settings = (data.qrOptions.settings == true) end
                            if data.qrOptions.ui       ~= nil then qr.ui       = (data.qrOptions.ui       == true) end
                        end
                        if data.skipDevPrewarm ~= nil then ms._skipDevPrewarm = (data.skipDevPrewarm == true) end
                        if data.devArchiveLimit ~= nil then
                            local n = tonumber(data.devArchiveLimit)
                            if n and n >= 0 and n <= 50 then ms._devArchiveLimit = math.floor(n) end
                        end
                        if data.updateChannel == "testing" or data.updateChannel == "stable" then
                            ms._updateChannel = data.updateChannel
                        end
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
                        -- System bind overrides (enable/disable/toggle macros).
                        if data.systemBinds and type(data.systemBinds) == "table" then
                            ms.systemBinds._config = {}
                            for id, cfg in pairs(data.systemBinds) do
                                if cfg.type and (cfg.key or cfg.button) then
                                    ms.systemBinds._config[id] = cfg
                                end
                            end
                        end
                        -- Runs last so user settings always take final effect.
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

                    ms._convertFlatSettings = function(file)
                        local data    = { macros = {} }
                        local skipped = {}
                        for line in file:lines() do
                            local key, val = line:match("^(.-)=(.+)$")
                            if not key then
                            elseif key == "sensitivity" then
                                local num = tonumber(val)
                                if num and num >= 0.1 and num <= 4 then data.sensitivity = num end
                            elseif key == "clickLevel" or key == "frameLevel" then
                                -- Legacy key — migrate into user settings on next save.
                                local num = tonumber(val)
                                if num and num >= 1 and num <= 4 then
                                    data.user = data.user or {}
                                    if not data.user.clickLevel then
                                        data.user.clickLevel = num
                                    end
                                end
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
                        if ms.ui and ms.ui.markDirty then ms.ui.markDirty() end
                        local data = {
                            sensitivity      = CUR_CAM_SENS,
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
                            skipDevPrewarm   = ms._skipDevPrewarm or false,
                            devArchiveLimit  = ms._devArchiveLimit or 15,
                            updateChannel    = ms._updateChannel or "stable",
                            quickReloaded    = ms._quickReloaded or 0,
                            qrOptions        = ms._qrOptions or { macros = true, theme = true, settings = true, ui = true },
                            user             = ms._userSettingVals or {},
                            systemBinds      = {},
                            macros = {},
                        }
                        -- Save system bind overrides (only non-default values).
                        for id, cfg in pairs(ms.systemBinds._config or {}) do
                            data.systemBinds[id] = cfg
                        end
                        for id, enabled in pairs(ms.binds or {}) do
                            data.macros[id] = data.macros[id] or {}
                            data.macros[id].enabled = enabled
                        end
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
                        for id, key in pairs(ms.modConfig or {}) do
                            data.macros[id] = data.macros[id] or {}
                            data.macros[id].mod = key
                        end
                        for id, cfg in pairs(ms.subBinds or {}) do
                            data.macros[id] = data.macros[id] or {}
                            data.macros[id].bind = cfg
                        end
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
                        ms.dev.log({ type = "system", event = "settings_load_start" })
                        if ms.ui and ms.ui.markDirty then ms.ui.markDirty() end
                        local f = io.open(jsonPath, "r")
                        if f then
                            local content = f:read("*all")
                            f:close()
                            local data = hs.json.decode(content)
                            if data then
                                ms._applySettings(data)
                                ms.dev.log({ type = "system", event = "settings_loaded", source = "json" })
                                return
                            end
                            -- JSON present but unreadable; fall through to flat-file check.
                            ms.dev.log({ type = "error", event = "settings_parse_failed", source = "json" })
                        end
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
                        ms._buildDefaultSettings()
                        local df2 = io.open(defaultPath, "r")
                        if df2 then
                            local content2 = df2:read("*all"); df2:close()
                            local data2 = hs.json.decode(content2)
                            if data2 then ms._applySettings(data2) end
                        end
                    end

                    ms.saveDefault = function()
                        ms.saveSettings()
                        local sf = io.open(jsonPath, "r")
                        if not sf then ms.alert("Could not read current settings.", 3); return end
                        local content = sf:read("*all")
                        sf:close()
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
                        local df = io.open(defaultPath, "w")
                        if df then
                            df:write(content)
                            df:close()
                            ms.alert("Default settings saved.", 3)
                        end
                    end

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

                    -- Reloads settings only (no macro re-execution).
                    ms.reloadSettings = function()
                        ms.loadSettings()
                        ms.bind.rebind()
                        ms.cam.updateAnchor()
                        ms.cam.updateMultiplier()
                        ms.socdApply()
                        if not ms._quickReloading then
                            ms.playSlot("update")
                            ms.alert("Settings reloaded.", 5, true)
                        end
                    end

                    -- Full UI rebuild: teardown macros, re-exec, load settings
                    -- + theme, rebind, camera, SOCD.  Silent when called from
                    -- ms.quickReload() via the _quickReloading flag.
                    ms.reloadUI = function()
                        ms.bind.teardown()
                        ms.registry       = { _defs = {}, _defList = {} }
                        ms.bind._wires    = {}
                        ms.bind._autoCount = 0
                        ms.macroMeta       = nil
                        ms._userSettingDefs  = {}
                        ms._userSettingIndex = {}
                        ms._userSettingVals  = {}

                        local macrosPath = os.getenv("HOME") .. "/.hammerspoon/ms_macros.lua"
                        local af = io.open(macrosPath, "r")
                        if af then
                            local rawSrc = af:read("*all"); af:close()
                            local chunk = load(rawSrc, "@ms_macros.lua", "bt", ms._macroSandbox)
                            if chunk then pcall(chunk) end
                        end
                        for _, id in ipairs(ms.registry._defList) do
                            local def = ms.registry._defs[id]
                            if def and not def.sub and ms.binds[id] == nil then
                                ms.binds[id] = def.enabled
                            end
                        end
                        ms._systemActions = {}
                        if ms._userSettingIndex["showTamperWarning"] then
                            ms._systemActions["showTamperWarning"] = function()
                                ms.showGuardian()
                            end
                        end
                        ms.loadSettings()
                        ms.loadTheme()
                        if not ms.registry._defs["__panicButton"] then ms.bind._registerSystemBinds() end
                        ms.bind.rebind()
                        ms.cam.updateAnchor()
                        ms.cam.updateMultiplier()
                        ms.socdApply()
                        if not ms._quickReloading then
                            ms.playSlot("update")
                        end
                        ms.ui.hide()
                        hs.timer.doAfter(0.15, function() ms.ui.show() end)
                    end

                    -- Quick Reload: fires selected functions sequentially (no overlap),
                    -- closes the settings UI, unfocuses/refocuses the target app, then toasts.
                    ms.quickReload = function()
                        ms.dev.log({ type = "system", event = "quick_reload_start" })
                        -- 0. Mark quick reload in progress so it persists across the reload.
                        ms._quickReloaded = 1
                        ms._quickReloading = true   -- suppress per-module toasts
                        ms.saveSettings()

                        local qr = ms._qrOptions or { macros = true, theme = true, settings = true, ui = true }

                        -- 1. Reload macros.
                        if qr.macros then ms.ui._actions.reloadMacros() end

                        -- 2. Reload theme.
                        if qr.theme then ms.loadTheme() end

                        -- 3. Reload settings (rebind, camera, SOCD).
                        if qr.settings then ms.reloadSettings() end

                        -- 4. Full UI rebuild.
                        if qr.ui then ms.reloadUI() end

                        -- Done with module reloads — clear the suppression flag.
                        ms._quickReloading = false

                        -- 5. Clear the persistent flag on success.
                        if ms._quickReloaded == 1 then
                            ms._quickReloaded = 0
                            ms.saveSettings()
                        end

                        -- 6. Always toast the result (warn if nothing selected).
                        local anySelected = qr.macros or qr.theme or qr.settings or qr.ui
                        hs.timer.doAfter(1.0, function()
                            ms.playSlot("update")
                            if anySelected then
                                ms.alert("Quick Reload complete.", 5, true)
                            else
                                ms.alert("Quick Reload: no options selected.", 5, true)
                            end
                        end)
                    end

                    -- User Settings & Menu API --
                -- END --

                -- ms.settings.define(def) --
                    ms.settings.define = function(def)
                        assert(type(def) == "table",
                            "ms.settings.define: argument must be a table")
                        local t = def.type
                        assert(_SETTING_TYPES[t],
                            "ms.settings.define: unknown type '" .. tostring(t) .. "'")
                        if t == "divider" or t == "groupLabel" then
                            table.insert(ms._userSettingDefs, def)
                            return
                        end
                        if t == "group" then
                            assert(type(def.items) == "table",
                                "ms.settings.define: 'items' is required for type 'group'")
                            for _, subDef in ipairs(def.items) do
                                if type(subDef) == "table"
                                    and type(subDef.key) == "string" and #subDef.key > 0 then
                                    assert(not ms._userSettingIndex[subDef.key],
                                        "ms.settings.define: duplicate key '" .. subDef.key .. "' in group")
                                    ms._userSettingIndex[subDef.key] = subDef
                                    local st = subDef.type
                                    if st ~= "action" and st ~= "soundSlot"
                                        and st ~= "divider" and st ~= "groupLabel" then
                                        ms._userSettingVals[subDef.key] = subDef.default
                                        if subDef.default ~= nil
                                            and type(subDef.onChange) == "function" then
                                            pcall(subDef.onChange, subDef.default)
                                        end
                                    end
                                end
                            end
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
                        if t == "action" then return end
                        -- Seed with declared default; _applySettings will override with the
                        -- saved value once settings load from disk (after ms_macros.lua runs).
                        ms._userSettingVals[key] = def.default
                        if def.default ~= nil and type(def.onChange) == "function" then
                            pcall(def.onChange, def.default)
                        end
                    end

                -- END --

                -- ms.settings.get(key) --
                    ms.settings.get = function(key)
                        assert(type(key) == "string", "ms.settings.get: key must be a string")
                        local def = ms._userSettingIndex[key]
                        if not def then return nil end
                        -- soundSlot values live in ms.soundAssign, not _userSettingVals.
                        if def.type == "soundSlot" then
                            return (ms.soundAssign and ms.soundAssign[key]) or def.default
                        end
                        local v = ms._userSettingVals[key]
                        return v ~= nil and v or def.default
                    end

                -- END --

                -- ms.settings.set(key, value) --
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
                        if def.type == "soundSlot" then
                            -- soundSlot assignments are managed by the Sound panel, not _userSettingVals.
                            -- Calling set() on a soundSlot key is not supported; use the Sound section UI.
                            print("ms.settings.set: '" .. key .. "' is a soundSlot — assign sounds via Settings \xc2\xbb Sound.")
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

                -- END --

                -- ms.menu.define(def) --
                    ms.menu.define = function(def)
                        assert(type(def) == "table",
                            "ms.menu.define: argument must be a table")
                        assert(type(def.id) == "string" and #def.id > 0,
                            "ms.menu.define: 'id' is required")
                        assert(type(def.title) == "string" and #def.title > 0,
                            "ms.menu.define: 'title' is required")
                        assert(type(def.items) == "table",
                            "ms.menu.define: 'items' must be a table")
                        for _, item in ipairs(def.items) do
                            if type(item) == "table"
                                and type(item.key) == "string" and #item.key > 0
                                and not ms._userSettingIndex[item.key] then
                                if item.onChange then
                                    assert(type(item.onChange) == "function",
                                        "ms.menu.define: item onChange must be a function")
                                end
                                if item.onAction then
                                    assert(type(item.onAction) == "function",
                                        "ms.menu.define: item onAction must be a function")
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

                -- END --

                -- ms.features.hide(name) --
                    ms.features.hide = function(name)
                        if not _HIDEABLE_FEATURES[name] then
                            print("ms.features.hide: '" .. tostring(name)
                                .. "' is not a hideable feature. "
                                .. "Accepted: sensitivity, socd, trackpad, independentBinds")
                            return
                        end
                        ms._hiddenFeatures[name] = true
                    end

                -- END --

                -- END User Settings & Menu API --

                -- Theme System --
                ms.loadTheme = function()
                    ms.dev.log({ type = "system", event = "theme_load" })
                    if ms.ui and ms.ui.markDirty then ms.ui.markDirty() end
                    for k, v in pairs(ms._themeDefaults) do ms._theme[k] = v end
                    local f = io.open(themePath, "r")
                    if not f then return end
                    local content = f:read("*all"); f:close()
                    local data = hs.json.decode(content)
                    if not data then return end
                    ms._themeLoaded = true
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
                    if type(data.radius) == "number" then
                        ms._theme.radius = math.max(0, math.min(40, math.floor(data.radius)))
                    end
                    if type(data.fadeMs) == "number" then
                        ms._theme.fadeMs = math.max(0, math.min(500, math.floor(data.fadeMs)))
                    end
                    -- Validate font.
                    if type(data.font) == "string" and #data.font > 0 then
                        local clean = data.font:gsub("[;{}()<>\"']", "")
                        if #clean > 0 then ms._theme.font = clean end
                    end
                end
                -- END Theme System --

                -- Capability Detection --
                ms.has = function(feature)
                    local home = os.getenv("HOME") .. "/.hammerspoon"

                    if feature == "theme" then
                        return ms._themeLoaded == true

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

                -- END Capability Detection --

                -- Profile Management --

                ms._buildDefaultSettings = function()
                    local data = {
                        sensitivity      = 1.5,
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
                    -- Run the chunk with an instruction-count watchdog so a malicious
                    -- file containing `while true do end` cannot hang Hammerspoon.
                    -- pcall alone catches thrown errors but not spinning loops; wrapping
                    -- in a coroutine lets us attach a debug hook that aborts after a
                    -- generous ceiling of VM instructions (far more than any legitimate
                    -- macroMeta block will ever use).  JIT is disabled so the count hook
                    -- fires on every instruction on both Lua 5.x and LuaJIT.
                    if jit then pcall(jit.off, chunk, true) end

                    local _co = coroutine.create(chunk)
                    local _hookFires = 0

                    debug.sethook(
                        _co,
                        function()
                            _hookFires = _hookFires + 1
                            if _hookFires > 2000 then  -- 2000 × 1000 = ~2 M VM instructions
                                error("readMacroMeta: instruction limit exceeded (possible infinite loop in " .. filePath .. ")")
                            end
                        end,
                        "",
                        1000
                    )

                    coroutine.resume(_co)  -- errors and the watchdog error alike are harmless here
                    return captured.macroMeta
                end

                ms._profilesDirty = true
                local _profilesCache = nil
                local function getProfiles()
                    if not ms._profilesDirty and _profilesCache then return _profilesCache end
                    ms._profilesDirty = false
                    local list = {}
                    if not hs.fs.attributes(profilesPath) then _profilesCache = list; return list end
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
                    -- The active profile's ms_macros.lua lives at the root, not in its
                    -- folder, so the directory scan above won't find it.  Include it
                    -- explicitly whenever its folder exists on disk.
                    local activeName = ms.macroMeta and sanitizeName(ms.macroMeta.name or "") or ""
                    if activeName ~= "" and hs.fs.attributes(profilesPath .. activeName) then
                        local found = false
                        for _, p in ipairs(list) do
                            if p == activeName then found = true; break end
                        end
                        if not found then
                            table.insert(list, activeName)
                        end
                    end
                    table.sort(list)
                    _profilesCache = list
                    return list
                end

                -- Forward declaration so switchProfile can call auditMacros,
                -- which is defined below in the same scope.
                local auditMacros

                local function switchProfile(targetName)
                    ms.dev.log({ type = "system", event = "profile_switch_start", target = targetName })
                    -- Security: audit the target profile before touching any files.
                    -- A file manually dropped into profiles/ bypasses importProfile's audit,
                    -- so we check here as well.
                    local targetFile = profilesPath .. targetName .. "/ms_macros.lua"
                    local tf = io.open(targetFile, "r")
                    if not tf then
                        ms.dev.log({ type = "error", event = "profile_switch_failed", reason = "cannot_read", target = targetName })
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
                    local hadTheme    = hs.fs.attributes(themePath)   and moveFile(themePath,   profilesPath .. currentName .. "/ms_theme.json")

                    ok, err = moveFile(profilesPath .. targetName .. "/ms_macros.lua", macrosPath)
                    if not ok then
                        moveFile(profilesPath .. currentName .. "/ms_macros.lua", macrosPath)
                        if hadSettings then moveFile(profilesPath .. currentName .. "/ms_settings.json",         jsonPath)    end
                        if hadDefaults then moveFile(profilesPath .. currentName .. "/ms_settings_default.json", defaultPath) end
                        if hadTheme    then moveFile(profilesPath .. currentName .. "/ms_theme.json",            themePath)   end
                        ms.alert("Profile switch failed: could not activate \"" .. targetName .. "\".\n" .. tostring(err), 5)
                        return
                    end
                    if hs.fs.attributes(profilesPath .. targetName .. "/ms_settings.json") then
                        moveFile(profilesPath .. targetName .. "/ms_settings.json",         jsonPath)
                    end
                    if hs.fs.attributes(profilesPath .. targetName .. "/ms_settings_default.json") then
                        moveFile(profilesPath .. targetName .. "/ms_settings_default.json", defaultPath)
                    end
                    if hs.fs.attributes(profilesPath .. targetName .. "/ms_theme.json") then
                        moveFile(profilesPath .. targetName .. "/ms_theme.json", themePath)
                    end

                    ms.alert("Switched to \"" .. targetName .. "\".\nReloading in 3 seconds...", 4)
                    ms.dev.log({ type = "system", event = "profile_switch_complete", target = targetName })
                    hs.timer.doAfter(3, function() hs.reload() end)
                end

                -- A leading space is prepended so [^%w%.]-anchored patterns also
                -- fire at position 1 of the cleaned source.
                auditMacros = function(src)
                    -- Lexer pass: neutralize string literals and comments --
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
                                -- Short quoted string --
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

                                -- END --

                            elseif c == "-" and src:sub(i + 1, i + 1) == "-" then
                                -- Comment --
                                    local j      = i + 2   -- first char after --
                                    local isLong = false
                                    if src:sub(j, j) == "[" then
                                        local eq = 0
                                        while src:sub(j + 1 + eq, j + 1 + eq) == "=" do eq = eq + 1 end
                                        if src:sub(j + 1 + eq, j + 1 + eq) == "[" then
                                            local closer = "]" .. string.rep("=", eq) .. "]"
                                            local _, ce  = src:find(closer, j + 2 + eq, true)
                                            out[#out + 1] = blank(src:sub(i, ce or n))
                                            i = ce and ce + 1 or n + 1
                                            isLong = true
                                        end
                                    end
                                    if not isLong then
                                        local nl = src:find("\n", j)
                                        if nl then
                                            out[#out + 1] = blank(src:sub(i, nl - 1)) .. "\n"
                                            i = nl + 1
                                        else
                                            out[#out + 1] = blank(src:sub(i))
                                            i = n + 1
                                        end
                                    end

                                -- END --

                            elseif c == "[" then
                                -- Long string [=*[...]=*] --
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

                                -- END --

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
                            -- Scan ALL occurrences of this prefix, not just the first.
                            -- The old clean:find() returned only the first hit: a macro
                            -- could place a first occurrence next to a media extension to
                            -- earn an exemption, leaving subsequent occurrences unchecked.
                            local pos = 1
                            while true do
                                local found = clean:find(sysPath, pos)
                                if not found then break end
                                if not nearMedia(found) then
                                    local snip = clean:sub(found, math.min(#clean, found+35))
                                                     :gsub("%s+", " ")
                                    table.insert(errs, "disallowed path: " .. snip)
                                    break  -- one error per prefix is enough
                                end
                                pos = found + 1
                            end
                        end

                        -- Non-local global function definitions.
                        -- All helpers in ms_macros.lua must be declared with 'local'.
                        -- A bare 'function name()' at the start of a line creates a global.
                        for line in clean:gmatch("[^\n]+") do
                            local name = line:match("^%s*function%s+([%a_][%w_]*)%s*%(")
                    -- END --

                        if name then
                            table.insert(errs, "non-local global function definition: " .. name .. "()")
                        end
                    end

                    return errs
                end

                local function importProfile()
                    ms.playSlot("alert")
                    hs.focus()
                    local result = hs.dialog.chooseFileOrFolder(
                        "Select an ms_macros.lua file to import",
                        os.getenv("HOME") .. "/Downloads/",
                        true, false, false
                    )
                    local roblox = hs.application.get(ms._targetApp or "Roblox")
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
                    local sq = function(s) return "'" .. s:gsub("'", "'\\''" ) .. "'" end

                    local function _commit()
                        hs.execute("mkdir -p " .. sq(profilesPath .. folderName))
                        if not hs.fs.attributes(profilesPath .. folderName) then
                            if roblox then pcall(function() roblox:activate() end) end
                            ms.alert("Could not create profile folder.", 3)
                            return
                        end
                        local f = io.open(selectedPath, "rb")
                        if not f then
                            if roblox then pcall(function() roblox:activate() end) end
                            ms.alert("Could not read the selected file.", 3)
                            return
                        end
                        local content = f:read("*all"); f:close()
                        local auditErrs = auditMacros(content)
                        if #auditErrs > 0 then
                            if roblox then pcall(function() roblox:activate() end) end
                            ms.alert("Import rejected \xe2\x80\x94 security scan failed:\n  \xe2\x80\xa2 "
                                .. table.concat(auditErrs, "\n  \xe2\x80\xa2 "), 8)
                            return
                        end
                        local dst    = profilesPath .. folderName .. "/ms_macros.lua"
                        local copied = false
                        local g = io.open(dst, "wb")
                        if g then
                            g:write(content); g:close()
                            copied = true
                        end
                        -- Fallback: shell cp.
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
                        ms._profilesDirty = true
                        ms.ui.refresh()
                        if roblox then pcall(function() roblox:activate() end) end
                        hs.timer.doAfter(0.2, function()
                            ms.alert("Profile \"" .. meta.name .. "\" imported.\nSwitch to it from Settings \xe2\x86\x92 Profiles.", 5, true)
                        end)
                    end

                    if hs.fs.attributes(profilesPath .. folderName) then
                        ms.ui.modal({
                            title   = "Overwrite Profile?",
                            msg     = "\"" .. meta.name .. "\" is already in your library.\nReplace it with this file?",
                            confirm = "Replace",
                            cancel  = "Cancel",
                        }, function(r)
                            if r.confirmed then
                                _commit()
                            else
                                if roblox then pcall(function() roblox:activate() end) end
                            end
                        end)
                    else
                        _commit()
                    end
                end

                local function createNewProfile()
                    local name = ms.macroMeta and ms.macroMeta.name
                    if not name or name == "" then
                        ms.alert("Cannot create: current profile has no name.\nSet ms.macroMeta = { name = \"...\" } in your macros file.", 5)
                        return
                    end
                    local folderName = sanitizeName(name)
                    local sq = function(s) return "'" .. s:gsub("'", "'\\''") .. "'" end

                    -- Archive current profile (same as switchProfile archiving).
                    hs.fs.mkdir(profilesPath)
                    hs.execute("mkdir -p " .. sq(profilesPath .. folderName))
                    if not hs.fs.attributes(profilesPath .. folderName) then
                        ms.alert("Could not create profile folder.", 3)
                        return
                    end
                    local _, st = hs.execute("/bin/cp " .. sq(macrosPath) .. " " .. sq(profilesPath .. folderName .. "/ms_macros.lua"))
                    if st ~= true then
                        ms.alert("Could not archive current macros.", 3)
                        return
                    end
                    if hs.fs.attributes(jsonPath) then
                        hs.execute("/bin/cp " .. sq(jsonPath) .. " " .. sq(profilesPath .. folderName .. "/ms_settings.json"))
                    end
                    if hs.fs.attributes(defaultPath) then
                        hs.execute("/bin/cp " .. sq(defaultPath) .. " " .. sq(profilesPath .. folderName .. "/ms_settings_default.json"))
                    end
                    if hs.fs.attributes(themePath) then
                        hs.execute("/bin/cp " .. sq(themePath) .. " " .. sq(profilesPath .. folderName .. "/ms_theme.json"))
                    end

                    -- Write blank template ms_macros.lua.
                    local templatePath = home .. "/templates/ms_macros.lua"
                    local tpl = io.open(templatePath, "r")
                    local blankSrc
                    if tpl then
                        blankSrc = tpl:read("*a"); tpl:close()
                    else
                        blankSrc = 'ms.macroMeta = {\n    name    = "My Macros",\n    author  = "",\n    website = "",\n}\n'
                    end
                    local mf = io.open(macrosPath, "w")
                    if mf then
                        mf:write(blankSrc); mf:close()
                    else
                        ms.alert("Could not write blank macros file.", 3)
                        return
                    end

                    -- Remove active settings/defaults/theme so the new profile starts clean.
                    os.remove(jsonPath)
                    os.remove(defaultPath)
                    os.remove(themePath)

                    ms.playSlot("update")
                    ms._profilesDirty = true
                    ms.alert("Profile \"" .. name .. "\" archived.\nNew blank profile active.\nReloading in 3 seconds...", 4)
                    hs.timer.doAfter(3, function() hs.reload() end)
                end

                local function saveCurrentProfile()
                    local name = ms.macroMeta and ms.macroMeta.name
                    if not name or name == "" then
                        ms.alert("Cannot save: current profile has no name.\nSet ms.macroMeta = { name = \"...\" } in your macros file.", 5)
                        return
                    end
                    local folderName = sanitizeName(name)
                    local existing = getProfiles()
                    local found = false
                    for _, p in ipairs(existing) do
                        if p == folderName then found = true; break end
                    end
                    if not found then
                        ms.alert("No saved profile named \"" .. name .. "\" found.\nUse Save as New Profile instead.", 4)
                        return
                    end
                    local sq = function(s) return "'" .. s:gsub("'", "'\\''") .. "'" end
                    local dst = profilesPath .. folderName .. "/ms_macros.lua"
                    local _, st = hs.execute("/bin/cp " .. sq(macrosPath) .. " " .. sq(dst))
                    if st ~= true then
                        ms.alert("Could not update profile.", 3)
                        return
                    end
                    if hs.fs.attributes(jsonPath) then
                        hs.execute("/bin/cp " .. sq(jsonPath) .. " " .. sq(profilesPath .. folderName .. "/ms_settings.json"))
                    end
                    if hs.fs.attributes(defaultPath) then
                        hs.execute("/bin/cp " .. sq(defaultPath) .. " " .. sq(profilesPath .. folderName .. "/ms_settings_default.json"))
                    end
                    if hs.fs.attributes(themePath) then
                        hs.execute("/bin/cp " .. sq(themePath) .. " " .. sq(profilesPath .. folderName .. "/ms_theme.json"))
                    end
                    ms.playSlot("update")
                    ms._profilesDirty = true
                    ms.ui.markDirty()
                    ms.ui.refresh()
                    hs.timer.doAfter(0.2, function()
                        ms.alert("Profile \"" .. name .. "\" updated.", 3, true)
                    end)
                end

                local function exportProfilePkg()
                    local sq = function(s) return "'" .. s:gsub("'", "'\\''") .. "'" end
                    local name = sanitizeName((ms.macroMeta and ms.macroMeta.name) or "unnamed")
                    local outName = name .. ".mspkg"
                    local outPath = os.getenv("HOME") .. "/Downloads/" .. outName
                    local tmpDir  = archivePath .. "mspkg_export/"
                    os.execute("mkdir -p " .. sq(archivePath))
                    os.execute("rm -rf " .. sq(tmpDir))
                    os.execute("mkdir -p " .. sq(tmpDir))
                    local _, cpOk = hs.execute("/bin/cp " .. sq(macrosPath) .. " " .. sq(tmpDir .. "ms_macros.lua"))
                    if not hs.fs.attributes(tmpDir .. "ms_macros.lua") then
                        ms.alert("Export failed: could not read ms_macros.lua.", 4)
                        os.execute("rm -rf " .. sq(tmpDir)); return
                    end
                    if hs.fs.attributes(jsonPath) then
                        hs.execute("/bin/cp " .. sq(jsonPath) .. " " .. sq(tmpDir .. "ms_settings.json"))
                    end
                    if hs.fs.attributes(defaultPath) then
                        hs.execute("/bin/cp " .. sq(defaultPath) .. " " .. sq(tmpDir .. "ms_settings_default.json"))
                    end
                    if hs.fs.attributes(themePath) then
                        hs.execute("/bin/cp " .. sq(themePath) .. " " .. sq(tmpDir .. "ms_theme.json"))
                    end
                    -- Includes manually-dropped files, not just UI-imported ones.
                    local soundsDir = tmpDir .. "sounds/"
                    local soundsCopied = 0
                    local bundledFiles = {}  -- deduplicate by filename
                    for _, soundName in pairs(ms.soundAssign or {}) do
                        if type(soundName) == "string" and ms.sounds then
                            local soundPath = ms.sounds[soundName]
                            if soundPath and hs.fs.attributes(soundPath) then
                                local filename = soundPath:match("([^/\\]+)$")
                                if filename and not bundledFiles[filename] then
                                    os.execute("mkdir -p " .. sq(soundsDir))
                                    hs.execute("/bin/cp " .. sq(soundPath) .. " " .. sq(soundsDir .. filename))
                                    bundledFiles[filename] = true
                                    soundsCopied = soundsCopied + 1
                                end
                            end
                        end
                    end
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

                local function importProfilePkg()
                    hs.focus()
                    local result = hs.dialog.chooseFileOrFolder(
                        "Select a .mspkg profile package to import",
                        os.getenv("HOME") .. "/Downloads/",
                        true, false, false, { "mspkg", "zip" }
                    )
                    local roblox = hs.application.get(ms._targetApp or "Roblox")
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

                    local function _commit()
                        hs.execute("mkdir -p " .. sq(profilesPath .. folderName))
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
                        local settingsSrc = tmpDir .. "ms_settings.json"
                        if hs.fs.attributes(settingsSrc) then
                            hs.execute("/bin/cp " .. sq(settingsSrc) .. " " .. sq(profilesPath .. folderName .. "/ms_settings.json"))
                        end
                        local defSrc = tmpDir .. "ms_settings_default.json"
                        if hs.fs.attributes(defSrc) then
                            hs.execute("/bin/cp " .. sq(defSrc) .. " " .. sq(profilesPath .. folderName .. "/ms_settings_default.json"))
                        end
                        local themeSrc = tmpDir .. "ms_theme.json"
                        if hs.fs.attributes(themeSrc) then
                            hs.execute("/bin/cp " .. sq(themeSrc) .. " " .. sq(profilesPath .. folderName .. "/ms_theme.json"))
                        end
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
                                ms._soundsDirty = true
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
                            ms._profilesDirty = true
                            ms.ui.markDirty()
                            ms.ui.refresh()
                        end)
                    end

                    if hs.fs.attributes(profilesPath .. folderName) then
                        ms.ui.modal({
                            title   = "Overwrite Profile?",
                            msg     = "\"" .. meta.name .. "\" is already in your library.\nReplace it with this package?",
                            confirm = "Replace",
                            cancel  = "Cancel",
                        }, function(r)
                            if r.confirmed then
                                _commit()
                            else
                                os.execute("rm -rf " .. sq(tmpDir))
                                if roblox then pcall(function() roblox:activate() end) end
                            end
                        end)
                    else
                        _commit()
                    end
                end

                -- END Profile Management --

                -- System Integrity --

                ms.integrity = {}

                ms.integrity.hashFile = function(path)
                    local escaped = "'" .. path:gsub("'", "'\\'") .. "'"
                    local out = hs.execute("shasum -a 256 " .. escaped .. " 2>/dev/null")
                    if out and #out >= 64 then return out:sub(1, 64):lower() end
                    return nil
                end

                ms.integrity.readTrustedHash = function()
                    local f = io.open(trustedHashPath, "r")
                    if not f then return nil end
                    local h = f:read("*all"); f:close()
                    h = h and h:match("^%s*([0-9a-fA-F]+)%s*$")
                    return (h and #h == 64) and h:lower() or nil
                end

                ms.integrity.writeTrustedHash = function(hash)
                    local f = io.open(trustedHashPath, "w")
                    if f then
                        f:write(hash .. "\n"); f:close()
                        ms.dev.log({ type = "system", event = "hash_seeded", hash = hash:sub(1,16) .. "…" })
                        return true
                    end
                    ms.dev.log({ type = "error", event = "hash_seed_failed" })
                    return false
                end

                ms.integrity.deleteTrustedHash = function()
                    return os.remove(trustedHashPath) ~= nil
                end

                -- Non-blocking: always returns the last-known cached value immediately and
                -- kicks off a background hs.task hash when the 60-second window expires.
                -- The task callback handles mismatch reloads and UI badge refreshes so the
                -- Hammerspoon main thread is never stalled by shasum.
                local _intCache         = { status = nil, cur = nil, trusted = nil, t = 0 }
                local _intHashInProgress = false  -- guard against concurrent hs.task runs
                ms.integrity.invalidateCache = function()
                    _intCache.t = 0
                    ms.dev.log({ type = "system", event = "integrity_cache_invalidated" })
                end
                ms.integrity.check = function()
                    local now = os.time()
                    if _intCache.status ~= nil and (now - _intCache.t) < 60 then
                        return _intCache.status, _intCache.cur, _intCache.trusted
                    end
                    if not _intHashInProgress then
                        _intHashInProgress = true
                        local _t = hs.task.new("/usr/bin/shasum", function(_, out, _)
                            _intHashInProgress = false
                            local cur     = (out and #out >= 64) and out:sub(1, 64):lower() or nil
                            local trusted = ms.integrity.readTrustedHash()
                            local status
                            if not trusted        then status = "uninitialized"
                            elseif cur == trusted then status = "trusted"
                            else                       status = "mismatch" end
                            _intCache = { status = status, cur = cur, trusted = trusted, t = os.time() }
                            ms.dev.log({
                                type    = "system",
                                event   = "integrity_check",
                                status  = status,
                                cur     = cur     and cur:sub(1,16) .. "…" or nil,
                                trusted = trusted and trusted:sub(1,16) .. "…" or nil,
                            })
                            if status == "mismatch" then hs.reload() end
                        end, {"-a", "256", corePath})
                        if _t then _t:start() else _intHashInProgress = false end
                    end
                    return _intCache.status or "uninitialized", _intCache.cur, _intCache.trusted
                end

                ms.integrity.trustCurrent = function()
                    local hash = ms.integrity.hashFile(corePath)
                    if not hash then
                        ms.alert("System integrity: could not hash ms_core.lua.", 4)
                        return false
                    end
                    if ms.integrity.writeTrustedHash(hash) then
                        ms.integrity.invalidateCache()  -- force fresh check on next open
                        ms.alert("Trusted hash saved.\n" .. hash:sub(1, 16) .. "\xe2\x80\xa6", 4, true)
                        return true
                    end
                    ms.alert("System integrity: could not write trusted hash file.", 4)
                    return false
                end

                -- ── Bundle update helper ───────────────────────────────────────────
                -- Applies files from an extracted release tar.gz.
                -- Always-replace: ms_core.lua, init.lua, ui/, bin/, Spoons/
                -- Create-if-missing: ms_macros.lua, profiles/Default/
                local function _applyBundleUpdate(bundleDir, timestamp)
                    local hsDir = os.getenv("HOME") .. "/.hammerspoon/"

                    -- Find the top-level directory inside the bundle.
                    -- tar.gz extracts as mudscript-macos-X.Y.Z/...
                    local topDir = nil
                    local dh = io.popen("ls -d '" .. bundleDir .. "'/mudscript-* 2>/dev/null | head -1")
                    if dh then topDir = dh:read("*l"); dh:close() end
                    if not topDir or topDir == "" then
                        -- Fallback: maybe files are at the root of bundleDir
                        topDir = bundleDir
                    end
                    -- Normalise: ensure trailing slash
                    if not topDir:match("/$") then topDir = topDir .. "/" end

                    -- Always-replace list (files and directories).
                    local replaceList = { "ms_core.lua", "init.lua", "ui", "bin", "Spoons" }
                    -- Create-if-missing list (files and directories).
                    local templateList = { "ms_macros.lua", "profiles/Default" }

                    os.execute("mkdir -p '" .. archivePath .. "'")

                    for _, name in ipairs(replaceList) do
                        local src = topDir .. name
                        local dst = hsDir .. name
                        if hs.fs.attributes(src) then
                            -- Back up existing (files and dirs).
                            if hs.fs.attributes(dst) then
                                local safeName = name:gsub("/", "_")
                                local bak = archivePath .. safeName .. "_" .. timestamp
                                    .. (hs.fs.attributes(dst).mode == "directory" and ".d.bak" or ".bak")
                                os.execute("rm -rf '" .. bak .. "'")
                                os.execute("cp -R '" .. dst .. "' '" .. bak .. "'")
                            end
                            -- Replace: remove old, copy new.
                            os.execute("rm -rf '" .. dst .. "'")
                            os.execute("cp -R '" .. src .. "' '" .. dst .. "'")
                        end
                    end

                    for _, name in ipairs(templateList) do
                        local src = topDir .. name
                        local dst = hsDir .. name
                        if hs.fs.attributes(src) and not hs.fs.attributes(dst) then
                            os.execute("mkdir -p '" .. dst:match("(.+)/[^/]+$") .. "'")
                            os.execute("cp -R '" .. src .. "' '" .. dst .. "'")
                        end
                    end

                    return true
                end

                -- ── Signature verification helper ───────────────────────────────
                local function _verifySignature(manifest)
                    if not manifest.signature or manifest.signature == ""
                        or not ms._updatePublicKey
                        or ms._updatePublicKey:find("PLACEHOLDER") then
                        return true  -- no signature to verify
                    end
                    local _tmpDir  = archivePath
                    local _keyPath = _tmpDir .. "upd_pub.pem"
                    local _sigPath = _tmpDir .. "upd_sig.bin"
                    local _msgPath = _tmpDir .. "upd_msg.bin"
                    os.execute("mkdir -p '" .. _tmpDir .. "'")
                    local _keyContent = ms._updatePublicKey
                        :gsub("^[%s\n]+", "")
                        :gsub("\n[%s]+", "\n")
                        :gsub("[%s]+$", "\n")
                    local _kf = io.open(_keyPath, "w")
                    if _kf then _kf:write(_keyContent); _kf:close() end
                    local _sf = io.open(_sigPath .. ".b64", "w")
                    if _sf then _sf:write(manifest.signature); _sf:close() end
                    hs.execute("base64 -D -i '" .. _sigPath .. ".b64' -o '" .. _sigPath .. "'")
                    os.remove(_sigPath .. ".b64")
                    local _signTarget = manifest.bundle and manifest.bundle.sha256 or manifest.sha256
                    local _mf = io.open(_msgPath, "w")
                    if _mf then _mf:write(_signTarget:lower()); _mf:close() end
                    local _out, _ok = hs.execute(
                        "openssl dgst -sha256 -verify '" .. _keyPath ..
                        "' -signature '" .. _sigPath ..
                        "' '" .. _msgPath .. "' 2>&1"
                    )
                    os.remove(_keyPath); os.remove(_sigPath); os.remove(_msgPath)
                    if not _ok then
                        ms.dev.log({ type = "error", event = "signature_failed", output = tostring(_out) })
                        ms.alert("Update aborted: signature verification failed.\n" .. tostring(_out), 12)
                        return false
                    end
                    ms.dev.log({ type = "system", event = "signature_verified" })
                    return true
                end

                ms.integrity.update = function()
                    ms.dev.log({ type = "system", event = "update_start", channel = "stable" })
                    local manifestURL = ms._updateManifestURL
                    if not manifestURL or manifestURL == "" then
                        ms.dev.log({ type = "error", event = "update_failed", reason = "no_url" })
                        ms.alert("Update URL not configured.\nSet ms._updateManifestURL in ms_core.lua.", 6)
                        return
                    end
                    if not manifestURL:match("^https://") then
                        ms.dev.log({ type = "error", event = "update_failed", reason = "not_https" })
                        ms.alert("Update URL must use HTTPS.\nHTTP URLs are not permitted.", 6)
                        return
                    end
                    ms.alert("Fetching update manifest\xe2\x80\xa6", 4, true)
                    hs.http.asyncGet(manifestURL, nil, function(mCode, mBody, _)
                        if mCode ~= 200 or not mBody then
                            ms.dev.log({ type = "error", event = "update_failed", reason = "manifest_http", code = mCode })
                            ms.alert("Update failed: manifest request returned " .. tostring(mCode) .. ".", 5)
                            return
                        end
                        local manifest = hs.json.decode(mBody)
                        if not manifest then
                            ms.dev.log({ type = "error", event = "update_failed", reason = "manifest_parse" })
                            ms.alert("Update failed: could not parse manifest.", 5)
                            return
                        end

                        local isBundle = manifest.bundle
                            and manifest.bundle.url and manifest.bundle.sha256

                        -- Validate required fields.
                        if isBundle then
                            -- ok
                        elseif manifest.sha256 and manifest.url then
                            -- legacy single-file manifest
                        else
                            ms.alert("Update failed: manifest missing required fields.", 5)
                            return
                        end

                        -- Signature verification (works for both formats).
                        if not _verifySignature(manifest) then return end

                        local newVersion = manifest.version or "?"

                        if isBundle then
                            -- ── Bundle update (tar.gz) ──────────────────────────────
                            local bundleURL  = manifest.bundle.url
                            local bundleHash = manifest.bundle.sha256:lower()
                            ms.alert("Downloading v" .. newVersion .. " bundle\xe2\x80\xa6", 4, true)
                            ms.dev.log({ type = "system", event = "update_download_start", version = newVersion, format = "bundle" })
                            hs.http.asyncGet(bundleURL, nil, function(fCode, fBody, _)
                                if fCode ~= 200 or not fBody then
                                    ms.dev.log({ type = "error", event = "update_failed", reason = "download_http", code = fCode, version = newVersion })
                                    ms.alert("Update failed: bundle download returned " .. tostring(fCode) .. ".", 5)
                                    return
                                end
                                os.execute("mkdir -p '" .. archivePath .. "'")
                                local tmpArchive = archivePath .. "ms_bundle_update.tar.gz"
                                local tmpF = io.open(tmpArchive, "w")
                                if not tmpF then
                                    ms.alert("Update failed: could not write temp file.", 4)
                                    return
                                end
                                tmpF:write(fBody); tmpF:close()
                                local actualHash = ms.integrity.hashFile(tmpArchive)
                                if actualHash ~= bundleHash then
                                    print("ms update: bundle hash mismatch (expected "
                                        .. bundleHash:sub(1,16) .. "… got "
                                        .. (actualHash or "?"):sub(1,16) .. "…)"
                                        .. " — installing anyway.")
                                end
                                -- Extract to temp directory.
                                local tmpExtract = archivePath .. "ms_bundle_extract/"
                                os.execute("rm -rf '" .. tmpExtract .. "'")
                                os.execute("mkdir -p '" .. tmpExtract .. "'")
                                local _, tarOk = hs.execute(
                                    "tar xzf '" .. tmpArchive .. "' -C '" .. tmpExtract .. "' 2>&1"
                                )
                                os.remove(tmpArchive)
                                if not tarOk then
                                    os.execute("rm -rf '" .. tmpExtract .. "'")
                                    ms.dev.log({ type = "error", event = "update_failed", reason = "extract_failed", version = newVersion })
                                    ms.alert("Update failed: could not extract bundle.", 5)
                                    return
                                end
                                local timestamp = os.date("%Y-%m-%d_%H%M")
                                ms._updateInProgress = true
                                os.execute("mkdir -p '" .. os.getenv("HOME") .. "/.hammerspoon/data'")
                                local _sp = io.open(os.getenv("HOME") .. "/.hammerspoon/data/.ms_update_pending", "w")
                                if _sp then _sp:close() end
                                local ok = _applyBundleUpdate(tmpExtract, timestamp)
                                ms._updateInProgress = false; os.remove(os.getenv("HOME") .. "/.hammerspoon/data/.ms_update_pending")
                                os.execute("rm -rf '" .. tmpExtract .. "'")
                                if not ok then
                                    ms.dev.log({ type = "error", event = "update_failed", reason = "apply_failed", version = newVersion })
                                    ms.alert("Update failed: could not apply bundle.", 5)
                                    return
                                end
                                ms.dev.log({ type = "system", event = "update_applied", version = newVersion, format = "bundle" })
                                -- Re-seed trusted hash from the new ms_core.lua so the
                                -- Guardian and auto-seed don't fire on the post-update reload.
                                local newCoreHash = ms.integrity.hashFile(corePath)
                                if newCoreHash then
                                    ms.integrity.writeTrustedHash(newCoreHash)
                                end
                                ms.integrity.invalidateCache()
                                -- Write local MANIFEST.
                                local _mf = io.open(os.getenv("HOME") .. "/.hammerspoon/MANIFEST.json", "w")
                                if _mf then
                                    _mf:write(hs.json.encode({
                                        version = newVersion,
                                        sha256  = newCoreHash or manifest.sha256,
                                        bundle  = manifest.bundle,
                                    })); _mf:close()
                                end
                                ms.alert("Updated to v" .. newVersion .. ".\nReloading in 3 seconds\xe2\x80\xa6", 5, true)
                                hs.timer.doAfter(3, function() hs.reload() end)
                            end)
                        else
                            -- ── Legacy single-file update (ms_core.lua only) ────────
                            local expectedHash = manifest.sha256:lower()
                            ms.alert("Downloading v" .. newVersion .. "\xe2\x80\xa6", 4, true)
                            ms.dev.log({ type = "system", event = "update_download_start", version = newVersion, format = "single-file" })
                            hs.http.asyncGet(manifest.url, nil, function(fCode, fBody, _)
                                if fCode ~= 200 or not fBody then
                                    ms.dev.log({ type = "error", event = "update_failed", reason = "download_http", code = fCode, version = newVersion })
                                    ms.alert("Update failed: file download returned " .. tostring(fCode) .. ".", 5)
                                    return
                                end
                                os.execute("mkdir -p '" .. archivePath .. "'")
                                local tmpPath = archivePath .. "ms_core_update_tmp.lua"
                                local tmpF = io.open(tmpPath, "w")
                                if not tmpF then
                                    ms.alert("Update failed: could not write temp file.", 4)
                                    return
                                end
                                tmpF:write(fBody); tmpF:close()
                                local actualHash = ms.integrity.hashFile(tmpPath)
                                if actualHash ~= expectedHash then
                                    print("ms update: MANIFEST hash mismatch (expected "
                                        .. expectedHash:sub(1,16) .. "… got "
                                        .. (actualHash or "?"):sub(1,16) .. "…)"
                                        .. " — installing anyway and re-seeding trust from actual file.")
                                end
                                local timestamp  = os.date("%Y-%m-%d_%H%M")
                                local backupFile = archivePath .. "ms_core_" .. timestamp .. ".lua.bak"
                                ms._updateInProgress = true
                                os.execute("mkdir -p '" .. os.getenv("HOME") .. "/.hammerspoon/data'")
                                local _sp = io.open(os.getenv("HOME") .. "/.hammerspoon/data/.ms_update_pending", "w")
                                if _sp then _sp:close() end
                                local bOk = moveFile(corePath, backupFile)
                                if not bOk then
                                    ms._updateInProgress = false; os.remove(os.getenv("HOME") .. "/.hammerspoon/data/.ms_update_pending")
                                    os.remove(tmpPath)
                                    ms.alert("Update failed: could not back up ms_core.lua.", 4)
                                    return
                                end
                                local mOk = moveFile(tmpPath, corePath)
                                if not mOk then
                                    moveFile(backupFile, corePath)
                                    ms._updateInProgress = false; os.remove(os.getenv("HOME") .. "/.hammerspoon/data/.ms_update_pending")
                                    ms.alert("Update failed: could not install new ms_core.lua.\nBackup restored.", 5)
                                    return
                                end
                                ms._updateInProgress = false; os.remove(os.getenv("HOME") .. "/.hammerspoon/data/.ms_update_pending")
                                ms.integrity.writeTrustedHash(actualHash)
                                ms.integrity.invalidateCache()
                                local _mf = io.open(os.getenv("HOME") .. "/.hammerspoon/MANIFEST.json", "w")
                                if _mf then
                                    _mf:write(hs.json.encode({
                                        version = newVersion,
                                        sha256  = expectedHash,
                                        url     = manifest.url,
                                    })); _mf:close()
                                end
                                ms.alert("Updated to v" .. newVersion .. ".\nReloading in 3 seconds\xe2\x80\xa6", 5, true)
                                ms.dev.log({ type = "system", event = "update_applied", version = newVersion, format = "single-file" })
                                hs.timer.doAfter(3, function() hs.reload() end)
                            end)
                        end
                    end)
                end

                -- Parse a dotted version string into a table of numeric components
                -- for comparison.  "1.2.10" → {1, 2, 10}.  Non-numeric or missing
                -- segments default to 0 so "1.2" compares equal to "1.2.0".
                local function _parseVersion(v)
                    local t = {}
                    if type(v) == "string" then
                        for n in v:gmatch("%d+") do t[#t + 1] = tonumber(n) or 0 end
                    end
                    return t
                end

                -- Returns true when `remote` is strictly newer than `local`.
                -- Compares component-by-component: 1.2.10 > 1.2.3, 2.0 > 1.99.
                local function _remoteIsNewer(localV, remoteV)
                    local a, b = _parseVersion(localV), _parseVersion(remoteV)
                    local len = math.max(#a, #b)
                    for i = 1, len do
                        local la, ra = a[i] or 0, b[i] or 0
                        if ra > la then return true  end
                        if ra < la then return false end
                    end
                    return false  -- equal
                end

                -- Checks if a newer version is available without downloading.
                -- A version mismatch means the repo has changed enough to warrant
                -- a manifest bump, so version comparison alone is the signal.
                ms.integrity.checkForUpdate = function(callback)
                    local manifestURL = ms._updateManifestURL
                    if not manifestURL or manifestURL == "" or not manifestURL:match("^https://") then
                        if callback then pcall(callback, nil) end
                        return
                    end
                    -- Read local manifest for version comparison.
                    local localVersion
                    do
                        local lf = io.open(os.getenv("HOME") .. "/.hammerspoon/MANIFEST.json", "r")
                        if lf then
                            local ok, lm = pcall(hs.json.decode, lf:read("*all")); lf:close()
                            if ok and lm and lm.version then localVersion = lm.version end
                        end
                    end
                    hs.http.asyncGet(manifestURL, nil, function(mCode, mBody, _)
                        if mCode ~= 200 or not mBody then
                            ms.dev.log({ type = "error", event = "update_check_failed", reason = "manifest_http", code = mCode, channel = "stable" })
                            if callback then pcall(callback, nil); return end
                        end
                        local manifest = hs.json.decode(mBody)
                        if not manifest or not manifest.version then
                            ms.dev.log({ type = "error", event = "update_check_failed", reason = "manifest_parse", channel = "stable" })
                            if callback then pcall(callback, nil); return end
                        end
                        local remoteVersion = manifest.version
                        -- Version mismatch → update available.
                        if _remoteIsNewer(localVersion, remoteVersion) then
                            ms.dev.log({ type = "system", event = "update_available", local_v = localVersion, remote_v = remoteVersion, channel = "stable" })
                            if callback then
                                pcall(callback, {
                                    version = remoteVersion or "?",
                                    sha256  = manifest.sha256,
                                })
                            end
                            return
                        end
                        if callback then pcall(callback, nil) end
                    end)
                end

                -- Path for persisting the last-installed testing run ID.
                local _testingRunPath = os.getenv("HOME")
                    .. "/.hammerspoon/data/.ms_testing_run"

                local function _readTestingRun()
                    local f = io.open(_testingRunPath, "r")
                    if not f then return 0 end
                    local n = tonumber(f:read("*a")) or 0; f:close(); return n
                end
                local function _writeTestingRun(n)
                    os.execute("mkdir -p '" .. os.getenv("HOME") .. "/.hammerspoon/data'")
                    local f = io.open(_testingRunPath, "w")
                    if f then f:write(tostring(n)); f:close() end
                end

                -- Fetch the latest successful testing workflow run from GitHub Actions.
                -- Calls `callback(info)` with { runId, sha, display } on success, or
                -- `callback(nil)` on failure / no runs found.
                local function _fetchLatestTestingRun(callback)
                    local repo = ms._testingRepo or "mudbourn/ms-utils"
                    local wf   = ms._testingWorkflow or "testing"
                    local apiURL = "https://api.github.com/repos/" .. repo
                        .. "/actions/workflows/" .. wf .. ".yml/runs"
                        .. "?per_page=1"
                    hs.http.asyncGet(apiURL, {
                        ["Accept"] = "application/vnd.github+json",
                    }, function(code, body, _)
                        if code ~= 200 or not body then
                            if callback then pcall(callback, nil) end
                            return
                        end
                        local ok, data = pcall(hs.json.decode, body)
                        if not ok or not data or not data.workflow_runs
                            or #data.workflow_runs == 0 then
                            if callback then pcall(callback, nil) end
                            return
                        end
                        local run = data.workflow_runs[1]
                        if callback then pcall(callback, {
                            runId     = run.run_number or run.id,
                            sha       = run.head_sha,
                            display   = "build " .. tostring(run.run_number or run.id),
                            createdAt = run.created_at or "",
                        }) end
                    end)
                end

                ms.integrity.updateBeta = function()
                    ms.dev.log({ type = "system", event = "update_start", channel = "testing" })
                    local repo = ms._testingRepo or "mudbourn/ms-utils"
                    if not repo or repo == "" then
                        ms.alert("Testing channel: no repo configured.\nSet ms._testingRepo in ms_core.lua.", 6)
                        return
                    end
                    ms.alert("Fetching latest testing build\xe2\x80\xa6", 4, true)
                    _fetchLatestTestingRun(function(info)
                        if not info or not info.runId then
                            -- No workflow run found — fall back to main branch.
                            ms.dev.log({ type = "system", event = "update_beta_fallback", reason = "no_workflow_run", target = "main" })
                            ms.alert("Downloading latest from main branch\xe2\x80\xa6", 4, true)
                            local fileURL = "https://raw.githubusercontent.com/" .. repo
                                .. "/main/mac/ms_core.lua"
                            hs.http.asyncGet(fileURL, nil, function(fCode, fBody, _)
                                if fCode ~= 200 or not fBody then
                                    ms.alert("Download failed: HTTP " .. tostring(fCode) .. ".", 5)
                                    return
                                end
                                os.execute("mkdir -p '" .. archivePath .. "'")
                                local tmpPath = archivePath .. "ms_core_update_tmp.lua"
                                local tmpF = io.open(tmpPath, "w")
                                if not tmpF then
                                    ms.alert("Update failed: could not write temp file.", 4)
                                    return
                                end
                                tmpF:write(fBody); tmpF:close()
                                local actualHash = ms.integrity.hashFile(tmpPath)
                                local timestamp  = os.date("%Y-%m-%d_%H%M")
                                local backupFile = archivePath .. "ms_core_" .. timestamp .. ".lua.bak"
                                ms._updateInProgress = true
                                os.execute("mkdir -p '" .. os.getenv("HOME") .. "/.hammerspoon/data'")
                                local _sp = io.open(os.getenv("HOME") .. "/.hammerspoon/data/.ms_update_pending", "w")
                                if _sp then _sp:close() end
                                local bOk = moveFile(corePath, backupFile)
                                if not bOk then
                                    ms._updateInProgress = false; os.remove(os.getenv("HOME") .. "/.hammerspoon/data/.ms_update_pending")
                                    os.remove(tmpPath)
                                    ms.alert("Update failed: could not back up ms_core.lua.", 4)
                                    return
                                end
                                local mOk = moveFile(tmpPath, corePath)
                                if not mOk then
                                    moveFile(backupFile, corePath)
                                    ms._updateInProgress = false; os.remove(os.getenv("HOME") .. "/.hammerspoon/data/.ms_update_pending")
                                    ms.alert("Update failed: could not install.\nBackup restored.", 5)
                                    return
                                end
                                ms._updateInProgress = false; os.remove(os.getenv("HOME") .. "/.hammerspoon/data/.ms_update_pending")
                                ms.integrity.writeTrustedHash(actualHash)
                                ms.integrity.invalidateCache()
                                ms.alert("Updated to latest main.\nReloading in 3 seconds\xe2\x80\xa6", 5, true)
                                ms.dev.log({ type = "system", event = "update_applied", version = "main-latest", format = "single-file" })
                                hs.timer.doAfter(3, function() hs.reload() end)
                            end)
                            return
                        end
                        local buildNum = info.runId
                        local bundleURL = "https://github.com/" .. repo
                            .. "/releases/download/pre-" .. buildNum
                            .. "/mudscript-macos-pre-" .. buildNum .. ".tar.gz"
                        ms.dev.log({ type = "system", event = "update_download_start", version = "pre-" .. buildNum, format = "bundle" })
                        ms.alert("Downloading build " .. buildNum .. "\xe2\x80\xa6", 4, true)
                        hs.http.asyncGet(bundleURL, nil, function(fCode, fBody, _)
                            if fCode ~= 200 or not fBody then
                                -- Fallback: try single-file download for older builds.
                                ms.dev.log({ type = "system", event = "update_beta_fallback", reason = "bundle_http_" .. tostring(fCode), target = "single-file" })
                                local fileURL = "https://raw.githubusercontent.com/" .. repo
                                    .. "/" .. info.sha .. "/mac/ms_core.lua"
                                hs.http.asyncGet(fileURL, nil, function(fCode2, fBody2, _)
                                    if fCode2 ~= 200 or not fBody2 then
                                        ms.alert("Download failed: HTTP " .. tostring(fCode2) .. ".", 5)
                                        return
                                    end
                                    os.execute("mkdir -p '" .. archivePath .. "'")
                                    local tmpPath = archivePath .. "ms_core_update_tmp.lua"
                                    local tmpF = io.open(tmpPath, "w")
                                    if not tmpF then
                                        ms.alert("Update failed: could not write temp file.", 4)
                                        return
                                    end
                                    tmpF:write(fBody2); tmpF:close()
                                    local actualHash = ms.integrity.hashFile(tmpPath)
                                    local timestamp  = os.date("%Y-%m-%d_%H%M")
                                    local backupFile = archivePath .. "ms_core_" .. timestamp .. ".lua.bak"
                                    ms._updateInProgress = true
                                os.execute("mkdir -p '" .. os.getenv("HOME") .. "/.hammerspoon/data'")
                                local _sp = io.open(os.getenv("HOME") .. "/.hammerspoon/data/.ms_update_pending", "w")
                                if _sp then _sp:close() end
                                    local bOk = moveFile(corePath, backupFile)
                                    if not bOk then
                                        ms._updateInProgress = false; os.remove(os.getenv("HOME") .. "/.hammerspoon/data/.ms_update_pending")
                                        os.remove(tmpPath)
                                        ms.alert("Update failed: could not back up ms_core.lua.", 4)
                                        return
                                    end
                                    local mOk = moveFile(tmpPath, corePath)
                                    if not mOk then
                                        moveFile(backupFile, corePath)
                                        ms._updateInProgress = false; os.remove(os.getenv("HOME") .. "/.hammerspoon/data/.ms_update_pending")
                                        ms.alert("Update failed: could not install.\nBackup restored.", 5)
                                        return
                                    end
                                    ms._updateInProgress = false; os.remove(os.getenv("HOME") .. "/.hammerspoon/data/.ms_update_pending")
                                    ms.integrity.writeTrustedHash(actualHash)
                                    ms.integrity.invalidateCache()
                                    _writeTestingRun(buildNum)
                                    ms.alert("Updated to build " .. buildNum .. ".\nReloading in 3 seconds\xe2\x80\xa6", 5, true)
                                    ms.dev.log({ type = "system", event = "update_applied", version = "pre-" .. buildNum, format = "single-file-fallback" })
                                    hs.timer.doAfter(3, function() hs.reload() end)
                                end)
                                return
                            end
                            -- Bundle download succeeded — extract and apply.
                            os.execute("mkdir -p '" .. archivePath .. "'")
                            local tmpArchive = archivePath .. "ms_bundle_update.tar.gz"
                            local tmpF = io.open(tmpArchive, "w")
                            if not tmpF then
                                ms.alert("Update failed: could not write temp file.", 4)
                                return
                            end
                            tmpF:write(fBody); tmpF:close()
                            local tmpExtract = archivePath .. "ms_bundle_extract/"
                            os.execute("rm -rf '" .. tmpExtract .. "'")
                            os.execute("mkdir -p '" .. tmpExtract .. "'")
                            local _, tarOk = hs.execute(
                                "tar xzf '" .. tmpArchive .. "' -C '" .. tmpExtract .. "' 2>&1"
                            )
                            os.remove(tmpArchive)
                            if not tarOk then
                                os.execute("rm -rf '" .. tmpExtract .. "'")
                                ms.alert("Update failed: could not extract bundle.", 5)
                                return
                            end
                            local timestamp = os.date("%Y-%m-%d_%H%M")
                            ms._updateInProgress = true
                            os.execute("mkdir -p '" .. os.getenv("HOME") .. "/.hammerspoon/data'")
                            local _sp = io.open(os.getenv("HOME") .. "/.hammerspoon/data/.ms_update_pending", "w")
                            if _sp then _sp:close() end
                            local ok = _applyBundleUpdate(tmpExtract, timestamp)
                            ms._updateInProgress = false; os.remove(os.getenv("HOME") .. "/.hammerspoon/data/.ms_update_pending")
                            os.execute("rm -rf '" .. tmpExtract .. "'")
                            if not ok then
                                ms.alert("Update failed: could not apply bundle.", 5)
                                return
                            end
                            -- Re-seed trusted hash from the new ms_core.lua so the
                            -- Guardian and auto-seed don't fire on the post-update reload.
                            local newCoreHash = ms.integrity.hashFile(corePath)
                            if newCoreHash then
                                ms.integrity.writeTrustedHash(newCoreHash)
                            end
                            ms.integrity.invalidateCache()
                            _writeTestingRun(buildNum)
                            ms.alert("Updated to build " .. buildNum .. ".\nReloading in 3 seconds\xe2\x80\xa6", 5, true)
                            ms.dev.log({ type = "system", event = "update_applied", version = "pre-" .. buildNum, format = "bundle" })
                            hs.timer.doAfter(3, function() hs.reload() end)
                        end)
                    end)
                end

                ms.integrity.checkForUpdateBeta = function(callback)
                    local latestRun = _readTestingRun()
                    _fetchLatestTestingRun(function(info)
                        if not info or not info.runId then
                            if callback then pcall(callback, nil) end
                            return
                        end
                        if info.runId > latestRun then
                            if callback then pcall(callback, {
                                version = info.display,
                                runId   = info.runId,
                            }) end
                        else
                            if callback then pcall(callback, nil) end
                        end
                    end)
                end

                -- END System Integrity --

                -- ms.showGuardian --
                ms.showGuardian = function(trusted, current)
                    trusted = trusted or ("a3f8" .. string.rep("0", 12))
                    current = current or ("9c1e" .. string.rep("f", 12))
                    local _home = os.getenv("HOME")
                    local _htmlPath = _home .. "/.hammerspoon/ui/ms_guardian.html"
                    local _baseURL  = "file://" .. _home .. "/.hammerspoon/ui/"
                    local _uc = hs.webview.usercontent.new("guardianPreview")
                    local _panel = nil
                    local _pos   = nil
                    _uc:setCallback(function(msg)
                        local body = msg.body
                        if body == "keepBlocked" or body == "confirmDelete" then
                            pcall(function() if _panel then _panel:delete() end end)
                        else
                            local ok, data = pcall(hs.json.decode, body)
                            if ok and data and data.action == "move" and _pos then
                                _pos.x = _pos.x + (data.dx or 0)
                                _pos.y = _pos.y + (data.dy or 0)
                                pcall(function() _panel:frame(_pos) end)
                            end
                        end
                    end)
                    local sf = hs.screen.mainScreen():frame()
                    local w, h = 360, 300
                    local x = sf.x + math.floor((sf.w - w) / 2)
                    local y = sf.y + math.floor((sf.h - h) / 2)
                    _pos   = { x = x, y = y, w = w, h = h }
                    _panel = hs.webview.new(_pos, {}, _uc)
                    if not _panel then return end
                    pcall(function() _panel:windowStyle(0) end)
                    pcall(function() _panel:level(hs.canvas.windowLevels.popUpMenu or 101) end)
                    pcall(function() _panel:shadow(true) end)
                    local f = io.open(_htmlPath, "r")
                    if not f then return end
                    _panel:html(f:read("*all"), _baseURL); f:close()
                    _panel:show()
                    _panel:navigationCallback(function()
                        pcall(function()
                            local t = trusted:sub(1, 16) .. "\xe2\x80\xa6"
                            local c = current:sub(1, 16)  .. "\xe2\x80\xa6"
                            _panel:evaluateJavaScript(
                                "setHashes('" .. t .. "', '" .. c .. "')"
                            )
                            _panel:evaluateJavaScript("setPreviewMode()")
                            local tj = hs.json.encode(ms._theme or {})
                            if tj then
                                _panel:evaluateJavaScript("applyTheme(" .. tj .. ")")
                            end
                        end)
                    end)
                end

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

                    local function buildBindSection(defs)
                        local section = {}
                        local rebindSub = {}

                        for _, bind in ipairs(defs) do
                            local enabled = ms.binds[bind.id]
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
                                    ms.systemBinds._config = {}
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
                        -- Rebindable system binds (enable/disable/toggle).
                        for _, id in ipairs({"enable", "disable", "toggle"}) do
                            local def = ms.systemBinds._defs[id]
                            if def then
                                local bindStr = ms.systemBinds.bindStr(id)
                                table.insert(sub, { title = def.label .. "  " .. bindStr, disabled = true })
                                table.insert(sub, {
                                    title = "  Rebind: " .. def.label,
                                    fn = function()
                                        ms.alert("Rebinding: " .. def.label
                                            .. "\nCurrent: " .. bindStr
                                            .. "\nPress your new key or mouse button.\nEscape to cancel.", 15)
                                        local capture
                                        local cancelTimer
                                        capture = hs.eventtap.new({
                                            hs.eventtap.event.types.keyDown,
                                            hs.eventtap.event.types.leftMouseDown,
                                            hs.eventtap.event.types.rightMouseDown,
                                            hs.eventtap.event.types.otherMouseDown,
                                        }, function(event)
                                            capture:stop(); capture = nil; cancelTimer:stop()
                                            local parsed, newBindStr
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
                                                    newBindStr = table.concat(parts, "+")
                                                end
                                            else
                                                local btn
                                                if t == hs.eventtap.event.types.leftMouseDown then btn = 0
                                                elseif t == hs.eventtap.event.types.rightMouseDown then btn = 1
                                                else btn = event:getProperty(hs.eventtap.event.properties.mouseEventButtonNumber) end
                                                parsed = {type="mouse", button=btn}
                                                newBindStr = "Mouse " .. btn
                                            end
                                            if parsed then
                                                ms.playSlot("interact")
                                                ms.ui.modal({
                                                    title   = "Confirm Rebind",
                                                    msg     = "Set \"" .. def.label .. "\" to:  " .. newBindStr,
                                                    confirm = "Confirm",
                                                    cancel  = "Cancel",
                                                }, function(r)
                                                    if r.confirmed then
                                                        ms.systemBinds._config[id] = parsed
                                                        ms.saveSettings()
                                                        ms.systemBinds.rebind()
                                                        ms.playSlot("update")
                                                        hs.timer.doAfter(0.2, function()
                                                            ms.alert(def.label .. " rebound to: " .. newBindStr, 3, true)
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
                                            if capture then capture:stop(); capture = nil; ms.alert("Rebind timed out.", 2) end
                                        end)
                                    end
                                })
                                table.insert(sub, {
                                    title = "  Reset: " .. def.label,
                                    fn = function()
                                        ms.systemBinds._config[id] = nil
                                        ms.saveSettings()
                                        ms.systemBinds.rebind()
                                        ms.playSlot("reset")
                                        ms.alert(def.label .. " reset to default.", 2, true)
                                    end
                                })
                            end
                        end
                        table.insert(sub, { title = "-" })
                        -- Display-only system binds (hardcoded hs.hotkey.bind).
                        local displayBinds = {
                            {label = "Panic Button / Stop All",  bind = "Alt+F10"},
                            {label = "Get Roblox Window Info",   bind = "Ctrl+Shift+R"},
                            {label = "Quick Reload",              bind = "Alt+[→ Reload Options"},
                            {label = "Full Reload",               bind = "Alt+]→ Reload Options"},
                            {label = "Open Menu",                bind = "Alt+P"},
                        }
                        for _, bind in ipairs(displayBinds) do
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
                                    if srcPath ~= dst then
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
                                    ms._soundsDirty = true
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
                        local slots = {
                            { id = "startup",      label = "Loading Screen Start" },
                            { id = "load",         label = "Loading Screen End"   },
                            { id = "launch",       label = "Launch Announcement"  },
                            { id = "updateAvailable", label = "Update Available" },
                            { id = "alert",        label = "Alert / Notice"       },
                            { id = "enabled",      label = "Macros Enabled"       },
                            { id = "disabled",     label = "Macros Disabled"      },
                            { id = "update",       label = "Setting Updated"      },
                            { id = "reset",        label = "Setting Reset"        },
                            { id = "interact",     label = "Menu Interact"        },
                            { id = "hover",        label = "Menu Hover"           },
                            { id = "back",         label = "Menu Back"            },
                            { id = "settingsOpen", label = "Settings Open"        },
                            { id = "settingsClose",label = "Settings Close"       },
                        }
                        local soundNames = {}
                        for name in pairs(ms.sounds or {}) do table.insert(soundNames, name) end
                        table.sort(soundNames)
                        for _, slot in ipairs(slots) do
                            local assigned = ms.soundAssign and ms.soundAssign[slot.id]
                            local display  = assigned or "off"
                            local picker   = {}
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
                            title = "Create New Profile...",
                            fn    = function() createNewProfile() end,
                        })
                        -- Disable "Save Current Profile" unless the active profile name
                        -- matches an existing saved profile.
                        local activeFolder = currentName and sanitizeName(currentName) or ""
                        local hasMatching = false
                        for _, p in ipairs(profiles) do
                            if p == activeFolder then hasMatching = true; break end
                        end
                        table.insert(sub, {
                            title    = "Save Current Profile",
                            disabled = not hasMatching,
                            fn       = hasMatching and function() saveCurrentProfile() end or nil,
                        })
                        table.insert(sub, {
                            title = "Import Profile...",
                            fn    = function() importProfile() end,
                        })
                        return sub
                    end

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
                            { title = "Update Channel: " .. (ms._updateChannel == "testing" and "Testing" or "Stable"), menu = {
                                { title = (ms._updateChannel == "stable" and "\xe2\x9c\x93" or "\xe2\x9c\x97") .. " Stable (MANIFEST.json)", fn = function()
                                    ms._updateChannel = "stable"
                                    ms.saveSettings()
                                    ms.playSlot("update")
                                    ms.alert("Update channel: Stable", 2, true)
                                end },
                                { title = (ms._updateChannel == "testing" and "\xe2\x9c\x93" or "\xe2\x9c\x97") .. " Testing (GitHub Actions)", fn = function()
                                    ms._updateChannel = "testing"
                                    ms.saveSettings()
                                    ms.playSlot("update")
                                    ms.alert("Update channel: Testing", 2, true)
                                end },
                            }},
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
                                if ms._updateChannel == "testing" then
                                    if not ms._testingRepo or ms._testingRepo == "" then
                                        ms.alert("No testing repo configured.\nSet ms._testingRepo in ms_core.lua.", 5)
                                        return
                                    end
                                else
                                    if not ms._updateManifestURL or ms._updateManifestURL == "" then
                                        ms.alert("No update URL configured.\nSet ms._updateManifestURL in ms_core.lua.", 5)
                                        return
                                    end
                                end
                                local _chan = (ms._updateChannel == "testing") and "testing" or "stable"
                                ms.playSlot("interact")
                                ms.ui.modal({
                                    title   = "Check for Update",
                                    msg     = "Channel: " .. _chan .. "\nDownload and apply the latest ms_core.lua from GitHub?\n\nThe current file will be backed up to backups/ and Hammerspoon will reload.",
                                    confirm = "Update",
                                    cancel  = "Cancel",
                                }, function(r)
                                    if r.confirmed then
                                        if ms._updateChannel == "testing" then
                                            ms.integrity.updateBeta()
                                        else
                                            ms.integrity.update()
                                        end
                                    end
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

                    local function _buildMenuItems()
                        return {
                            { title = "Macros: " .. (BindValidity == 1 and "ENABLED" or "DISABLED"), disabled = true },
                            { title = "-" },
                            { title = "Enable Macros ( Enter )",  fn = function() ms.setMacros(1) end },
                            { title = "Disable Macros ( / )",     fn = function() ms.setMacros(0) end },
                            { title = "-" },
                            { title = "Reload Options", menu = {
                                { title = "Quick Reload ( ⌥[ )",   fn = function() ms.quickReload() end },
                                { title = "Full Reload ( ⌥] )",    fn = function() hs.reload() end },
                            }},
                            { title = "-" },
                            { title = "Profiles",  menu = buildProfilesSubmenu() },
                            { title = "Settings",  menu = buildSettingsSubmenu() },
                            { title = "Developer", menu = buildDeveloperSubmenu() },
                            { title = "Help",       menu = buildHelpSubmenu() },
                        }
                    end
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
                    local freshItems = _buildMenuItems()
                    if ms._menuOpen then _wrapFns(freshItems) end
                    return freshItems
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
                                    if BindValidity == 1 or binding.system then
                                        if binding.pressFn then
                                            print("ms.key dispatch: firing " .. (binding.system and "SYSTEM" or "normal") .. " bind, BindValidity=" .. BindValidity)
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
                                    if BindValidity == 1 or binding.system then
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

            -- Macro Watcher tracing helpers --
                local _camMoveAccum  = 0   -- consecutive cam.move calls awaiting flush
                local _traceSuppress = false  -- true while ms.type is dispatching internally

                local function _watcherStep(msg)
                    if not ms.dev._watcherPanel then return end
                    local co  = coroutine.running()
                    local ctx = co and ms._coroContext[co]
                    if ctx and ctx.cancelled then return end
                    local label = (ctx and ctx.label) or "macro"
                    local ok, j = pcall(hs.json.encode, {
                        type = "step", ts = os.time(),
                        msg  = "[" .. label .. "] " .. msg,
                    })
                    if ok then
                        pcall(function()
                            ms.dev._watcherPanel:evaluateJavaScript("appendEntry(" .. j .. ")")
                        end)
                    end
                end

                -- Flush accumulated cam.move calls before logging a different action.
                local function _flushCam()
                    if _camMoveAccum > 0 then
                        _watcherStep("cam.move \xc3\x97" .. _camMoveAccum)
                        _camMoveAccum = 0
                    end
                end

                ms.press = function(key, mods, hidinject)
                    if ms.dev._watcherPanel and not _traceSuppress then
                        _flushCam()
                        local modsStr = (mods and #mods > 0) and (" [" .. table.concat(mods, "+") .. "]") or ""
                        _watcherStep("↓ " .. tostring(key) .. modsStr)
                    end
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
                    if ms.dev._watcherPanel and not _traceSuppress then
                        _flushCam()
                        _watcherStep("↑ " .. tostring(key))
                    end
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
                    if ms.dev._watcherPanel then
                        _flushCam()
                        local modsStr = (mods and #mods > 0) and (" [" .. table.concat(mods, "+") .. "]") or ""
                        _watcherStep("type " .. tostring(key) .. modsStr)
                    end
                    local _saved = _traceSuppress
                    _traceSuppress = true
                    ms.press(key, mods, hidinject)
                    ms.wait(15)
                    ms.release(key, mods, hidinject)
                    _traceSuppress = _saved  -- restore rather than reset; safe across cancellation
                end

                ms.key = function(mods, key, swallow, pressFn, releaseFn, isSystem)
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
                        system = isSystem or false,
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
        -- END --

        -- 4. Mouse Actions -
            ms.scroll = function(direction, clicks)
                if ms.dev._watcherPanel then
                    _flushCam()
                    _watcherStep("scroll " .. tostring(direction)
                        .. (clicks and clicks > 1 and " \xc3\x97" .. clicks or ""))
                end
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

            ms.mouse = function(button, swallow, clickFn, hidinject, isSystem)
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
                            -- Track scroll-wheel click (button 2) hold state so
                            -- ms.keystate(998, true) works like ms.keystate(999, true) for right-click.
                            if b == 2 then ms.keytrack[998] = true end
                        else -- otherMouseUp
                            b = event:getProperty(hs.eventtap.event.properties.mouseEventButtonNumber)
                            isDown = false
                            if b == 2 then ms.keytrack[998] = false end
                        end

                        if ms.dev and ms.dev._onMouseEvent then
                            local _mp = hs.mouse.absolutePosition()
                            pcall(ms.dev._onMouseEvent, b, isDown,
                                math.floor(_mp.x), math.floor(_mp.y))
                        end

                        if BindValidity ~= 1 then
                            -- System mouse binds (e.g. macro-enable buttons) still fire
                            -- when macros are disabled; the callback has its own
                            -- _robloxActive guard.
                            if not (callbackData and callbackData.system) then return false end
                        end

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
                ms._mouseCallbacks[button] = { fn = clickFn, swallow = swallow, hidinject = hidinject, system = isSystem or false }
            end





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
                if ms.dev._watcherPanel then
                    _flushCam()
                    _watcherStep("Mouse " .. tostring(operation) .. " " .. tostring(button))
                end
                assert(OPS[operation],     "ms.Mouse: unknown operation '"  .. tostring(operation)  .. "'")
                assert(BTNS[button] ~= nil, "ms.Mouse: unknown button '"      .. tostring(button)     .. "'")
                assert(REFS[reference],    "ms.Mouse: unknown reference '"   .. tostring(reference)  .. "'")

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
                    -- When the watcher is open, log waits as step entries.
                    -- Flush any accumulated cam.move calls first so ordering is correct.
                    if ms.dev and ms.dev._watcherPanel then
                        _flushCam()
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
                        -- Don't resume a coroutine whose macro has been cancelled or paused.
                        if ctx and (ctx.cancelled or ctx.paused) then return end
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
                return ms.getTargetWin()
            end

            ms.winCenter = function()
                local win = ms.getTargetWin() or hs.window.focusedWindow()
                if not win then return 0, 0 end
                local f = win:frame()
                return f.x + (f.w / 2), f.y + (f.h / 2)
            end

            ms.getScaled = function(targetX, targetY)
                local win = ms.getTargetWin() or hs.window.focusedWindow()
                if not win then
                    local screen = hs.screen.mainScreen():frame()
                    return targetX * (screen.w / REF_W), targetY * (screen.h / REF_H)
                end
                local f = win:frame()
                local finalX = f.x + (targetX * (f.w / REF_W))
                local finalY = f.y + (targetY * (f.h / REF_H))
                return finalX, finalY
            end

            ms.resolvePoint = function(x, y, reference, unscaled)
                local win = ms.getTargetWin() or hs.window.focusedWindow()
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
                    if ms.dev._watcherPanel then
                        _camMoveAccum = _camMoveAccum + 1
                    end
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
                local robloxApp = hs.application.get("Roblox") or hs.application.get(ms._targetApp)
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

        -- 8. Macro Bind Controller --
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
                if ms.ui and ms.ui.markDirty then ms.ui.markDirty() end
                if state == 1 and BindValidity ~= 1 then
                    BindValidity = 1
                    pcall(function() ms.cam.enable() end)
                    ms.dev.log({ type = "system", event = "macros_enabled" })
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
                    ms.dev.log({ type = "system", event = "macros_disabled" })
                    if not silent then _doNotify(0) end
                end
                -- Repaint the panel immediately when it is open so the macro
                -- enabled/disabled indicator updates the moment the user tabs.
                if ms.ui and ms.ui._open then ms.ui.refresh() end
            end

            ms._appWatcher = hs.application.watcher.new(function(appName, eventType, app)
                if eventType == hs.application.watcher.activated then
                    if appName == "Roblox" then
                        local fromDialog = ms._inputOpen
                        ms._inputOpen = false
                        ms._robloxActive = true
                        ms.dev.log({ type = "system", event = "roblox_focus", fromDialog = fromDialog or false })
                        ms.cam._setupWatcher()
                        -- Don't enable macros while the loading screen is still up.
                        if not ms._loadComplete then return end
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
                        ms.dev.log({ type = "system", event = "roblox_blur", to = appName })
                        if BindValidity == 1 then
                            ms.setMacros(0, ms._inputOpen)
                        end
                    end
                elseif ms._targetApp and eventType == hs.application.watcher.launched and appName == ms._targetApp then
                    ms.cam._setupWatcher()
                end
            end):start()
            _G.__ms_appWatcher = ms._appWatcher  -- survives reload (lives outside the ms table) so next load's stop-guard can find this generation

            _G._initTimer = hs.timer.doAfter(0.3, function()
                local frontApp = hs.application.frontmostApplication()
                if ms._targetApp and frontApp and frontApp:name() == ms._targetApp then
                    ms._robloxActive = true
                    ms.cam._setupWatcher()
                    ms.cam.enable()
                    -- Macro activation is deferred to _announceLoad, which fires
                    -- after the loading screen fully dismisses and toasts play.
                end
            end)

            hs.hotkey.bind({ "alt" }, "F10", function()
                if not ms._loadComplete then return end
                if not ms._robloxActive then return end
                ms.setMacros(0)
            end)

            hs.hotkey.bind({"alt"}, "[", function()
                if not ms._loadComplete then return end
                ms.quickReload()
            end)

            hs.hotkey.bind({"alt"}, "]", function()
                if not ms._loadComplete then return end
                hs.reload()
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
                if not ms._loadComplete then return end
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
                    local ctx = { cancelled = false, paused = false, label = ms._pendingLabel or "macro" }
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

            -- Pauses a running macro by id (label from ms.bind.define).
            -- The macro's current ms.wait completes but does not resume until ms.resume() is called.
            -- Pass no argument to pause all running macros.
            ms.pause = function(id)
                if not id then
                    for _, ctx in pairs(ms._activeContexts) do ctx.paused = true end
                    return
                end
                for _, ctx in pairs(ms._activeContexts) do
                    if ctx.label == id then ctx.paused = true; return end
                end
            end

            -- Resumes a paused macro by id. If its wait timer already expired, the
            -- coroutine resumes immediately at the next instruction.
            -- Pass no argument to resume all paused macros.
            ms.resume = function(id)
                local function _resume(co)
                    local ctx = ms._coroContext[co]
                    if not ctx then return end
                    ctx.paused = false
                    if coroutine.status(co) ~= "suspended" then return end
                    local ok, err = coroutine.resume(co)
                    if not ok then
                        print("ms.resume error: " .. tostring(err))
                    end
                    if coroutine.status(co) == "dead" then
                        ms._coroContext[co] = nil
                        ms._activeContexts[ctx] = nil
                    end
                end
                if not id then
                    for co in pairs(ms._coroContext) do _resume(co) end
                    return
                end
                for co, ctx in pairs(ms._coroContext) do
                    if ctx.label == id then _resume(co); return end
                end
            end

            ms.copy = function(text)
                if ms.dev._watcherPanel then
                    _flushCam()
                    _watcherStep("copy")
                end
                hs.pasteboard.setContents(text)
            end

            -- Cancels all active ms.fn macros and releases held keys/buttons.
            -- Called automatically on every setMacros(0).
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
            -- Only rescans when ms._soundsDirty is true; callers that add/remove sound files
            -- must set ms._soundsDirty = true before calling.
            ms._soundsDirty = true  -- force the first scan at startup
            ms._discoverSounds = function()
                if not ms._soundsDirty then return end
                ms._soundsDirty = false
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
                if ms.dev._watcherPanel and path then
                    _flushCam()
                    local fname = tostring(path):match("([^/\\]+)$") or tostring(path)
                    _watcherStep("sound " .. fname)
                end
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

            -- Resolution order for each slot:
            --   1. ms.soundAssign[slotId]  — user override saved in settings
            --   2. ms.sounds[slotId]       — file named exactly after the slot id
            --   3. ms.sounds[_slotDefaults[slotId][n]] — built-in default filenames (tried in order)
            -- Returns true if a sound was found and played; false if disabled or no file.
            -- Default candidates use the PascalCase convention of the bundled sounds folder
            -- (e.g. MacrosOn.wav, SettingsOpen.wav) then fall back to the spaced variant.
            local _slotDefaults = {
                startup = { "LoadStart", "Load Start" },
                load    = { "LoadEnd",   "Load End"   },
                launch  = { "Launch" },
                updateAvailable = { "UpdateAvailable", "Update Available" },
            }
            ms.playSlot = function(slotId)
                if not ms.soundEnabled then return false end
                -- Suppress all non-load sounds during startup so only launch.wav plays
                -- while the loading screen is visible.  Gate opens in _announceLoad.
                if not ms._startupSoundDone and slotId ~= "load" and slotId ~= "startup" and slotId ~= "updateAvailable" then return false end
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
                    if not path then
                        local candidates = _slotDefaults[slotId]
                        if candidates then
                            for _, name in ipairs(candidates) do
                                path = ms.sounds and ms.sounds[name]
                                if path then break end
                            end
                        end
                    end
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
                local win = ms.getTargetWin() or hs.window.focusedWindow()
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

            -- ms.bind.define(id, fn|opts, opts|fn)
            -- opts: label=id, group, enabled, cooldown, sub, mod, info, default, shared, system
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
                    system   = opts.system or false,
                }
                table.insert(ms.registry._defList, id)
                if fn ~= nil then
                    assert(type(fn) == "function",
                        "ms.bind.define: fn must be a function for id '" .. id .. "'")
                    ms.bind._wires[id] = fn
                end
            end

            -- Register display-only system binds (handled by hs.hotkey.bind).
            -- Enable/Disable/Toggle are handled separately by ms.systemBinds.
            ms.bind._registerSystemBinds = function()
                ms.bind.define("__panicButton", nil, {
                    label      = "Panic Button / Stop All",
                    group      = "system",
                    enabled    = true,
                    system     = true,
                    default    = { type = "key", mods = {"alt"}, key = "F10" },
                })
                ms.bind.define("__quickReload", nil, {
                    label      = "Quick Reload",
                    group      = "system",
                    enabled    = true,
                    system     = true,
                    default    = { type = "key", mods = {"alt"}, key = "[" },
                })
                ms.bind.define("__fullReload", nil, {
                    label      = "Full Reload",
                    group      = "system",
                    enabled    = true,
                    system     = true,
                    default    = { type = "key", mods = {"alt"}, key = "]" },
                })
                ms.bind.define("__openMenu", nil, {
                    label      = "Open Menu",
                    group      = "system",
                    enabled    = true,
                    system     = true,
                    default    = { type = "key", mods = {"alt"}, key = "p" },
                })
            end

            -- System binds: hardware key listeners that bypass the registry/bind
            -- pipeline entirely. Uses ms.key() (eventtap) with swallow=false so
            -- keys pass through to the active app. User-configurable via settings.
            ms.systemBinds._defs = {
                enable  = { label = "Enable Macros",  default = { type = "key", mods = {}, key = "return" } },
                disable = { label = "Disable Macros", default = { type = "key", mods = {}, key = "/" } },
                toggle  = { label = "Toggle Macros",  default = { type = "key", mods = {}, key = "escape" } },
            }
            ms.systemBinds._actions = {
                enable  = function() ms.setMacros(1) end,
                disable = function() ms.setMacros(0) end,
                toggle  = function() ms.setMacros(BindValidity == 1 and 0 or 1) end,
            }

            ms.systemBinds.effective = function(id)
                return ms.systemBinds._config[id]
                    or (ms.systemBinds._defs[id] and ms.systemBinds._defs[id].default)
            end

            ms.systemBinds.bindStr = function(id)
                local c = ms.systemBinds.effective(id)
                if not c then return "( unset )" end
                if c.type == "mouse" then return "Mouse " .. tostring(c.button) end
                local parts = {}
                for _, m in ipairs(c.mods or {}) do table.insert(parts, m:sub(1, 1):upper() .. m:sub(2)) end
                table.insert(parts, (c.key or ""):upper())
                return table.concat(parts, "+")
            end

            ms.systemBinds.rebind = function()
                -- Tear down previous handles.
                for _, h in pairs(ms.systemBinds._handles) do
                    if h and h.delete then h:delete() end
                end
                ms.systemBinds._handles = {}

                for id, action in pairs(ms.systemBinds._actions) do
                    local c = ms.systemBinds.effective(id)
                    if not c then goto sysBindContinue end
                    if c.type == "key" then
                        ms.systemBinds._handles[id] = ms.key(c.mods, c.key, false, function()
                            if not ms._robloxActive then return end
                            local co = coroutine.create(action)
                            local ok, err = coroutine.resume(co)
                            if not ok then print("ms.systemBind error: " .. tostring(err)) end
                        end, nil, true)
                    elseif c.type == "mouse" then
                        ms.systemBinds._handles[id] = ms.mouse(c.button, false, function()
                            if not ms._robloxActive then return end
                            local co = coroutine.create(action)
                            local ok, err = coroutine.resume(co)
                            if not ok then print("ms.systemBind error: " .. tostring(err)) end
                        end, true)
                    end
                    ::sysBindContinue::
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
                -- Register system binds (always active regardless of BindValidity).
                ms.bind.rebindSystem()
            end
            -- Must be called after ms.bind.rebind() and whenever _robloxActive changes.
            ms.bind.rebindSystem = function()
                -- Tear down previous system bind handles.
                if ms._systemBindHandles then
                    for _, h in pairs(ms._systemBindHandles) do
                        if h and h.delete then h:delete() end
                    end
                end
                ms._systemBindHandles = {}

                for _, id in ipairs(ms.registry._defList) do
                    local def = ms.registry._defs[id]
                    if not def or not def.system then goto sysContinue end
                    local enabled = ms.binds[id]
                    if enabled == nil then enabled = def.enabled end
                    if not enabled then goto sysContinue end
                    local c = ms.effectiveBind(id)
                    if not c then goto sysContinue end
                    local fn = ms.bind._wires[id]
                    if not fn then goto sysContinue end
                    print("rebindSystem: registering " .. id .. " as system bind")
                    if c.type == "key" then
                        ms._systemBindHandles[id] = ms.key(c.mods, c.key, false, function()
                            if not ms._robloxActive then return end
                            local co = coroutine.create(fn)
                            local ok, err = coroutine.resume(co)
                            if not ok then print("ms.systemBind error: " .. tostring(err)) end
                        end, nil, true)
                    elseif c.type == "mouse" then
                        ms._systemBindHandles[id] = ms.mouse(c.button, false, function()
                            if not ms._robloxActive then return end
                            local co = coroutine.create(fn)
                            local ok, err = coroutine.resume(co)
                            if not ok then print("ms.systemBind error: " .. tostring(err)) end
                        end, true)
                    end
                    ::sysContinue::
                end
                -- Also refresh the standalone system binds (enable/disable/toggle).
                ms.systemBinds.rebind()
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

            ms.ui = { _panel = nil, _open = false, _modalCallback = nil, _panelPos = nil, _uiFadeTimer = nil }

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

            -- Snapshots runtime state for the webview panel.
            local function _buildUIState()
                local macros = {}

                -- Pre-build a children map: parentId → list of child ids.
                -- This turns the O(n³) nested scan into a single O(n) pass.
                local childrenOf = {}
                for _, id in ipairs(ms.registry._defList or {}) do
                    local def = ms.registry._defs[id]
                    if def and def.sub then
                        childrenOf[def.sub] = childrenOf[def.sub] or {}
                        table.insert(childrenOf[def.sub], id)
                    end
                end

                for _, id in ipairs(ms.registry._defList or {}) do
                    local def = ms.registry._defs[id]
                    if def and not def.sub and (def.group == "main" or def.group == "optional" or def.group == "system") then
                        local enabled = ms.binds[id]
                        if enabled == nil then enabled = def.enabled end
                        local subs = {}
                        for _, subId in ipairs(childrenOf[id] or {}) do
                            local subDef = ms.registry._defs[subId]
                            if subDef then
                                local subsubs = {}
                                for _, ss in ipairs(childrenOf[subId] or {}) do
                                    local ssDef = ms.registry._defs[ss]
                                    if ssDef then
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
                            id        = id,
                            label     = def.label,
                            group     = def.group,
                            bind      = _bindDisplay(ms.effectiveBind(id)),
                            enabled   = enabled and true or false,
                            subs      = subs,
                        })
                    end
                end
                -- Inject system binds (enable/disable/toggle) as virtual entries.
                for _, id in ipairs({"enable", "disable", "toggle"}) do
                    local def = ms.systemBinds._defs[id]
                    if def then
                        table.insert(macros, {
                            id         = id,
                            label      = def.label,
                            group      = "system",
                            bind       = _bindDisplay(ms.systemBinds.effective(id)),
                            systemBind = true,
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

                -- Serialize user setting defs, routed by target section.
                -- Helper: serialize a single def to a JSON-safe item table.
                local function _serItem(d)
                    local it = {
                        type    = d.type,
                        key     = d.key,
                        label   = d.label,
                        hint    = d.hint,
                    }
                    if d.type == "slider" then
                        it.min  = d.min;  it.max  = d.max
                        it.step = d.step; it.unit = d.unit
                    elseif d.type == "seg" then
                        it.options = d.options
                    elseif d.type == "action" then
                        it.btnLabel = d.btnLabel; it.danger = d.danger
                    elseif d.type == "group" then
                        local subs = {}
                        for _, sd in ipairs(d.items or {}) do
                            local si = {
                                type    = sd.type,
                                key     = sd.key,
                                label   = sd.label,
                                hint    = sd.hint,
                            }
                            if sd.type == "slider" then
                                si.min  = sd.min;  si.max  = sd.max
                                si.step = sd.step; si.unit = sd.unit
                            elseif sd.type == "seg"    then si.options  = sd.options
                            elseif sd.type == "action" then
                                si.btnLabel = sd.btnLabel; si.danger = sd.danger
                            end
                            if sd.key and sd.type ~= "action"
                                and sd.type ~= "divider" and sd.type ~= "groupLabel" then
                                si.value   = ms.settings.get(sd.key)
                                si.default = sd.default
                            end
                            table.insert(subs, si)
                        end
                        it.items = subs
                    end
                    if d.key and d.type ~= "action"
                        and d.type ~= "divider" and d.type ~= "groupLabel"
                        and d.type ~= "group" then
                        it.value   = ms.settings.get(d.key)
                        it.default = d.default
                    end
                    return it
                end

                local userSettings = {}
                local userCalibrationSettings = {}
                for _, def in ipairs(ms._userSettingDefs) do
                    local item = _serItem(def)
                    if (def.section or "settings") == "calibration" then
                        table.insert(userCalibrationSettings, item)
                    else
                        table.insert(userSettings, item)
                    end
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
                for k, v in pairs(ms._theme) do
                    if k ~= "_uifcW" and k ~= "_uifcH" then themeOut[k] = v end
                end
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
                    userCalibrationSettings = userCalibrationSettings,
                    userSoundSlots          = userSoundSlots,
                    userMenus               = userMenus,
                    hiddenFeatures          = ms._hiddenFeatures,
                    preloadDevTools         = not (ms._skipDevPrewarm or false),
                    devArchiveLimit         = ms._devArchiveLimit or 15,
                    updateChannel           = ms._updateChannel or "stable",
                    qrOptions               = ms._qrOptions or { macros = true, theme = true, settings = true, ui = true },
                    theme                   = themeOut,
                }
            end

            -- UI State Cache --
                -- Pre-encodes the full state JSON so ms.ui.refresh() is instant.
                -- Built once at startup, then rebuilt only when state actually changes.
                local _uiStateDirty = true   -- true = cache needs rebuilding
                local _uiStateJSON  = nil    -- "receiveState(...)" ready to eval

                -- Rebuilds the cache synchronously. Safe to call before the panel exists.
                local function _rebuildUICache()
                    local ok, json = pcall(hs.json.encode, _buildUIState())
                    if ok then
                        _uiStateJSON  = "receiveState(" .. json .. ");"
                        _uiStateDirty = false
                    end
                end

                -- Mark the cache stale. Refresh will rebuild on next call.
                ms.ui.markDirty = function() _uiStateDirty = true end

                -- Pushes a fresh state snapshot into the open panel. Safe to call even
                -- when the panel hasn't been built yet (no-op) or isn't visible.
                ms.ui.refresh = function()
                    if not ms.ui._panel then return end
                    if _uiStateDirty or not _uiStateJSON then _rebuildUICache() end
                    if _uiStateJSON then
                        pcall(function()
                            ms.ui._panel:evaluateJavaScript(_uiStateJSON)
                        end)
                    end
                end

                -- Pre-builds the UI state cache so the first panel open is instant.
                -- Called once at startup (via doAfter(0)) so _applySettings has had
                -- a full event-loop tick to finish before the snapshot is taken.
                ms.ui.prebuild = function()
                    if _uiStateDirty or not _uiStateJSON then _rebuildUICache() end
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

                    reloadMacros = function()
                        -- Re-run just the macro sandbox (no settings/theme reload).
                        ms.bind.teardown()
                        ms.registry       = { _defs = {}, _defList = {} }
                        ms.bind._wires    = {}
                        ms.bind._autoCount = 0
                        ms.macroMeta       = nil
                        ms._userSettingDefs  = {}
                        ms._userSettingIndex = {}
                        ms._userSettingVals  = {}

                        local macrosPath = os.getenv("HOME") .. "/.hammerspoon/ms_macros.lua"
                        local af = io.open(macrosPath, "r")
                        if not af then
                            ms.alert("Reload failed:\nCannot open ms_macros.lua.", 6)
                            return
                        end
                        local rawSrc = af:read("*all"); af:close()
                        local auditErrs = auditMacros(rawSrc)
                        if #auditErrs > 0 then
                            ms.alert("Reload blocked — audit failed.", 6)
                            return
                        end
                        local chunk, loadErr = load(rawSrc, "@ms_macros.lua", "bt", ms._macroSandbox)
                        if not chunk then
                            ms.alert("Reload failed:\n" .. tostring(loadErr), 6)
                            return
                        end
                        local ok, runErr = pcall(chunk)
                        if not ok then
                            ms.alert("Reload failed:\n" .. tostring(runErr), 6)
                            return
                        end
                        if not next(ms.registry._defs) then
                            ms.alert("Reload failed:\nNo ms.bind.define calls found.", 6)
                            return
                        end
                        for _, id in ipairs(ms.registry._defList) do
                            local def = ms.registry._defs[id]
                            if def and not def.sub and ms.binds[id] == nil then
                                ms.binds[id] = def.enabled
                            end
                        end
                        ms._systemActions = {}
                        if ms._userSettingIndex["showTamperWarning"] then
                            ms._systemActions["showTamperWarning"] = function()
                                ms.showGuardian()
                            end
                        end
                        ms.loadSettings()
                        if not ms.registry._defs["__panicButton"] then ms.bind._registerSystemBinds() end
                        ms.bind.rebind()
                        ms.cam.updateAnchor()
                        ms.cam.updateMultiplier()
                        ms.socdApply()
                        -- When called from ms.quickReload(), suppress the
                        -- per-module toast — quickReload shows one unified
                        -- toast at the end instead.
                        if not ms._quickReloading then
                            ms.playSlot("update")
                            ms.alert("Macros reloaded.", 4, true)
                        end
                        ms.ui.hide()
                        hs.timer.doAfter(0.15, function()
                            ms.ui.show()
                            -- Unfocus → refocus the target app so it picks up
                            -- the new macro/key state.
                            hs.timer.doAfter(0.35, function()
                                pcall(function()
                                    local app = ms._targetApp and hs.application.get(ms._targetApp)
                                    if app then
                                        app:hide()
                                        hs.timer.doAfter(0.15, function()
                                            pcall(function() app:activate() end)
                                        end)
                                    end
                                end)
                            end)
                        end)
                    end,

                    reloadSettings = function()
                        ms.loadSettings()
                        ms.bind.rebind()
                        ms.cam.updateAnchor()
                        ms.cam.updateMultiplier()
                        ms.socdApply()
                        ms.playSlot("update")
                        ms.alert("Settings reloaded.", 4, true)
                        ms.ui.refresh()
                    end,

                    reloadTheme = function()
                        ms.loadTheme()
                        ms.playSlot("update")
                        ms.alert("Theme reloaded.", 4, true)
                        ms.ui.hide()
                        hs.timer.doAfter(0.15, function() ms.ui.show() end)
                    end,

                    reloadUI = function()
                        ms.reloadUI()
                    end,

                    reloadAll = function() hs.reload() end,

                    quickReload = function()
                        ms.quickReload()
                    end,

                    setQROption = function(data)
                        if data.key and ms._qrOptions then
                            ms._qrOptions[data.key] = (data.value == true)
                            ms.saveSettings()
                            ms.playSlot("interact")
                        end
                    end,

                    setPreloadDevTools = function(data)
                        ms._skipDevPrewarm = not (data.value and true or false)
                        ms.saveSettings()
                        ms.playSlot("update")
                        ms.ui.refresh()
                    end,

                    setDevArchiveLimit = function(data)
                        local n = tonumber(data.value)
                        if n and n >= 0 and n <= 50 then
                            ms._devArchiveLimit = math.floor(n)
                            ms.saveSettings()
                            ms.playSlot("update")
                        end
                        ms.ui.refresh()
                    end,

                    setUpdateChannel = function(data)
                        local ch = data.value
                        if ch == "testing" or ch == "stable" then
                            ms._updateChannel = ch
                            ms.saveSettings()
                            ms.playSlot("update")
                        end
                        ms.ui.refresh()
                    end,

                    setMacroEnabled = function(data)
                        if not data.id then return end
                        local def = ms.registry._defs[data.id]
                        if def and def.system then return end  -- system binds cannot be disabled
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

                    -- Deletes a single non-active saved profile.
                    deleteProfile = function(data)
                        if not data.name then return end
                        local targetName = sanitizeName(data.name)
                        local activeName = ms.macroMeta and sanitizeName(ms.macroMeta.name or "") or ""
                        -- Hard guard: never delete the active profile.
                        if targetName == "" or targetName == activeName then return end
                        local dir = profilesPath .. targetName
                        if not hs.fs.attributes(dir) then return end
                        local sq = function(s) return "'" .. s:gsub("'", "'\\''" ) .. "'" end
                        os.execute("rm -rf " .. sq(dir))
                        ms._profilesDirty = true
                        ms.ui.markDirty()
                        ms.playSlot("reset")
                        hs.timer.doAfter(0.05, function()
                            ms.alert("Profile \"" .. data.name .. "\" deleted.", 2, true)
                            ms.ui.refresh()
                        end)
                    end,

                    -- Deletes all saved profiles except the active one.
                    clearProfiles = function()
                        local activeName = ms.macroMeta and sanitizeName(ms.macroMeta.name or "") or ""
                        -- Guard: if the active profile name is blank we can't safely identify
                        -- which folder to protect, so refuse to delete anything.
                        if activeName == "" then return end
                        if not hs.fs.attributes(profilesPath) then return end
                        local sq = function(s) return "'" .. s:gsub("'", "'\\''" ) .. "'" end
                        local deleted = 0
                        for entry in hs.fs.dir(profilesPath) do
                            if entry ~= "." and entry ~= ".." then
                                local safe = sanitizeName(entry)
                                if safe ~= "" and safe ~= activeName then
                                    local dir = profilesPath .. entry
                                    local attr = hs.fs.attributes(dir)
                                    if attr and attr.mode == "directory" then
                                        os.execute("rm -rf " .. sq(dir))
                                        deleted = deleted + 1
                                    end
                                end
                            end
                        end
                        ms._profilesDirty = true
                        ms.ui.markDirty()
                        ms.playSlot("reset")
                        hs.timer.doAfter(0.05, function()
                            ms.alert(deleted .. " profile" .. (deleted == 1 and "" or "s") .. " deleted.", 3, true)
                            ms.ui.refresh()
                        end)
                    end,

                    -- importProfile() drives its own native file picker / alerts.
                    importProfile     = function() importProfile() end,
                    importProfilePkg  = function() importProfilePkg() end,
                    exportProfilePkg  = function() exportProfilePkg() end,
                    createNewProfile  = function() createNewProfile() end,
                    saveCurrentProfile = function() saveCurrentProfile() end,

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
                            ms._soundsDirty = true
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
                        ms._soundsDirty = true
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

                    openDevLogs = function()
                        local logDir = os.getenv("HOME") .. "/Documents/ms_dev_logs/"
                        hs.fs.mkdir(logDir)
                        os.execute("open " .. logDir)
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

                    checkForUpdate = function()
                        if ms._updateChannel == "testing" then
                            ms.integrity.updateBeta()
                        else
                            ms.integrity.update()
                        end
                    end,

                    openConsole       = function() ms.dev.console.toggle()  end,
                    openWatcher       = function() ms.dev.watcher.toggle()  end,
                    openKeys          = function() ms.dev.keys.toggle()     end,
                    openWindowMonitor = function() ms.dev.window.toggle()   end,

                    -- Triggered by right-click › Rebind… on a macro row in the webview.
                    -- Runs the same eventtap capture used by the native menu rebind flow.
                    startRebind = function(data)
                        if not data.id then return end

                        -- System bind rebind (enable/disable/toggle macros).
                        if data.systemBind then
                            local sysDef = ms.systemBinds._defs[data.id]
                            if not sysDef then return end
                            local label = sysDef.label
                            local curBind = ms.systemBinds.effective(data.id)

                            local function bindDisplay(c)
                                if not c then return "unset" end
                                if c.type == "mouse" then return "Mouse " .. tostring(c.button) end
                                local parts = {}
                                for _, m in ipairs(c.mods or {}) do table.insert(parts, m) end
                                table.insert(parts, c.key or "")
                                return table.concat(parts, "+")
                            end

                            ms.alert("Rebinding: " .. label
                                .. "\nCurrent: " .. bindDisplay(curBind)
                                .. "\nPress your new key or mouse button.\nEscape to cancel.", 15)

                            ms._inputOpen = true
                            ms.ui._open   = false

                            local capture
                            local cancelTimer

                            local function restorePanel()
                                ms.ui._open = true
                                local roblox = hs.application.get(ms._targetApp or "Roblox")
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
                                    ms.playSlot("interact")
                                    ms._inputOpen = false
                                    ms.ui.modal({
                                        title   = "Confirm Rebind",
                                        msg     = "Set \"" .. label .. "\" to:  " .. bindStr2,
                                        confirm = "Confirm",
                                        cancel  = "Cancel",
                                    }, function(r)
                                        if r.confirmed then
                                            ms.systemBinds._config[data.id] = parsed
                                            ms.saveSettings()
                                            ms.playSlot("update")
                                            ms.systemBinds.rebind()
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
                            return
                        end

                        -- Regular macro rebind (registry-based).
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
                            local roblox = hs.application.get(ms._targetApp or "Roblox")
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

                    -- Resets a single system setting to its macro-pack default.
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
                    -- After the sandboxed onAction runs, any entry in ms._systemActions
                    -- for the same key is also called.  That table is populated by
                    -- ms_core.lua after the sandbox finishes, so macros cannot set it.
                    userSettingAction = function(data)
                        if not data.key then return end
                        local def = ms._userSettingIndex[data.key]
                        if def and def.type == "action" and type(def.onAction) == "function" then
                            pcall(def.onAction)
                        end
                        local sysAction = ms._systemActions and ms._systemActions[data.key]
                        if type(sysAction) == "function" then pcall(sysAction) end
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

                        -- System bind reset.
                        if data.systemBind then
                            ms.systemBinds._config[data.id] = nil
                            ms.saveSettings()
                            ms.systemBinds.rebind()
                            ms.playSlot("reset")
                            local def = ms.systemBinds._defs[data.id]
                            hs.timer.doAfter(0.1, function()
                                ms.alert((def and def.label or data.id) .. " reset to default.", 2, true)
                                ms.ui.refresh()
                            end)
                            return
                        end

                        -- Regular macro bind reset.
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
                                ms.ui.hide()
                            end
                        end)
                    end)
                    panel:html(_loadPanelHTML(), uiBasePath)
                    return panel
                end

                ms.ui.show = function()
                    if ms.ui._uiFadeTimer then ms.ui._uiFadeTimer:stop(); ms.ui._uiFadeTimer = nil end
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
                    ms.ui._open = true
                    ms.playSlot("settingsOpen")
                    pcall(function() ms.ui._panel:alpha(0) end)
                    ms.ui._panel:show()
                    pcall(function() ms.ui._panel:bringToFront(true) end)
                    ms.ui.refresh()
                    local step, steps = 0, 6
                    ms.ui._uiFadeTimer = hs.timer.doEvery((ms._theme.fadeMs or 150) / 1000 / steps, function()
                        step = step + 1
                        pcall(function() ms.ui._panel:alpha(step / steps) end)
                        if step >= steps then
                            ms.ui._uiFadeTimer:stop()
                            ms.ui._uiFadeTimer = nil
                        end
                    end)
                end

                ms.ui.hide = function()
                    if ms.ui._uiFadeTimer then ms.ui._uiFadeTimer:stop(); ms.ui._uiFadeTimer = nil end
                    if ms.ui._open then ms.playSlot("settingsClose") end
                    ms.ui._open = false
                    local panel = ms.ui._panel
                    if panel then
                        local step, steps = 0, 6
                        ms.ui._uiFadeTimer = hs.timer.doEvery((ms._theme.fadeMs or 150) / 1000 / steps, function()
                            step = step + 1
                            pcall(function() panel:alpha(1 - (step / steps)) end)
                            if step >= steps then
                                ms.ui._uiFadeTimer:stop()
                                ms.ui._uiFadeTimer = nil
                                if ms.ui._panel == panel then
                                    pcall(function() panel:hide() end)
                                    ms.ui._panel    = nil
                                    ms.ui._panelPos = nil
                                end
                            end
                        end)
                    end
                    ms._inputOpen = true
                    local roblox = hs.application.get("Roblox")
                    if roblox then
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

                -- Pre-builds the WebView panel (hidden) so WebKit loads HTML, CSS,
                -- fonts, and JS in the background during startup.  By the time the
                -- user first opens the panel the heavy initialisation is already done.
                -- Defined here (after _buildPanel) so the upvalue is properly in scope.
                -- Called from the Startup Executions block via doAfter(0).
                ms.ui.prewarm = function()
                    if not ms.ui._panel then
                        ms.ui._panel = _buildPanel()
                    end
                    -- Push the pre-built state once WebKit has had time to register
                    -- receiveState().  Skipped if the panel is already open.
                    hs.timer.doAfter(2, function()
                        if ms.ui._panel and not ms.ui._open then
                            ms.ui.refresh()
                        end
                    end)
                end

            -- END --

            -- ms.ui.modal(data, callback) --
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

            -- END --

            -- ms.ui.prompt(data, callback) --
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
        -- END --

        -- 12. Developer Panels --
            do
                local _devBase = "file://" .. os.getenv("HOME") .. "/.hammerspoon/ui/"
                local _home    = os.getenv("HOME")

                -- Helper: read category-specific dev logs and push history to a panel.
                local _HIST_MAX = 300  -- mirrors MAX_ENTRIES in the panel JS
                local function _loadDevHistory(panel, categories)
                    local entries = {}
                    for _, cat in ipairs(categories) do
                        local path = _catPaths[cat]
                        if path then
                            local f = io.open(path, "r")
                            if f then
                                for line in f:lines() do
                                    local ok, entry = pcall(hs.json.decode, line)
                                    if ok and entry then
                                        entries[#entries + 1] = entry
                                    end
                                end
                                f:close()
                            end
                        end
                    end
                    if #entries == 0 then return end
                    -- Sort by timestamp so entries from different files interleave correctly.
                    table.sort(entries, function(a, b) return (a.ts or "") < (b.ts or "") end)
                    -- Keep only the last _HIST_MAX after merging.
                    while #entries > _HIST_MAX do table.remove(entries, 1) end
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
                            -- Hex-only: matches the loadTheme validation policy.
                            -- The old `^rgb` branch is removed: it was a prefix-only
                            -- check that would allow arbitrary content after "rgb",
                            -- and loadTheme never stores non-hex colors anyway.
                            if val:match("^#[0-9a-fA-F]+$") then
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
                    -- Font family.
                    -- loadTheme strips [;{}()<>"'] from font names before storing them,
                    -- so no injection-relevant characters can reach this point.
                    local font = t.font
                    if type(font) == "string" and font ~= "" and not font:match("%.[ot]tf$") and not font:match("%.woff") then
                        table.insert(parts, string.format("document.body.style.fontFamily=\"'%s',Palatino,Georgia,serif\"", font))
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


                -- Dev panel fade helpers --
                    -- Shared 150 ms fade-in / fade-out for all four developer panels.
                    -- Each panel gets its own timer slot keyed by a short string so a
                    -- re-open while fading out cancels the out-animation and reverses.
                    local _devFadeTimers = {}

                    local function _devFadeIn(panel, key)
                        if _devFadeTimers[key] then
                            _devFadeTimers[key]:stop()
                            _devFadeTimers[key] = nil
                        end
                        pcall(function() panel:alpha(0) end)
                        local step, steps = 0, 6
                        _devFadeTimers[key] = hs.timer.doEvery((ms._theme.fadeMs or 150) / 1000 / steps, function()
                            step = step + 1
                            pcall(function() panel:alpha(step / steps) end)
                            if step >= steps then
                                _devFadeTimers[key]:stop()
                                _devFadeTimers[key] = nil
                            end
                        end)
                    end

                    local function _devFadeOut(panel, key, onDone)
                        if _devFadeTimers[key] then
                            _devFadeTimers[key]:stop()
                            _devFadeTimers[key] = nil
                        end
                        local step, steps = 0, 6
                        _devFadeTimers[key] = hs.timer.doEvery((ms._theme.fadeMs or 150) / 1000 / steps, function()
                            step = step + 1
                            pcall(function() panel:alpha(1 - (step / steps)) end)
                            if step >= steps then
                                _devFadeTimers[key]:stop()
                                _devFadeTimers[key] = nil
                                if onDone then onDone() end
                            end
                        end)
                    end

                -- END --

                -- Console --
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
                            for _, cat in ipairs({"macro", "console", "error", "system", "input"}) do
                                local p = _catPaths[cat]; if p then local f = io.open(p, "w"); if f then f:close() end end
                            end
                        elseif data.action == "close" then
                            ms.dev.console.hide()
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
                        elseif data.action == "playSlot" and data.slot then
                            ms.playSlot(data.slot)
                        end
                    end)

                    -- Builds the console WebView (hidden). Called at startup by
                    -- ms.dev.prewarm() so the panel is ready before the user opens it.
                    local function _buildConsolePanel()
                        local screen = hs.screen.mainScreen():frame()
                        local w, h   = 360, 640
                        local x = screen.x + screen.w - w - 20
                        local y = screen.y + 20
                        local panel = hs.webview.new({ x=x, y=y, w=w, h=h },
                            { developerExtrasEnabled = true }, _ucCon)
                        if not panel then return nil end
                        pcall(function() panel:windowStyle(0) end)
                        pcall(function() panel:level(hs.canvas.windowLevels.floating) end)
                        pcall(function() panel:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces) end)
                        pcall(function() panel:allowTextEntry(true) end)
                        pcall(function() panel:shadow(true) end)
                        local f = io.open(_home .. "/.hammerspoon/ui/ms_console.html", "r")
                        if f then panel:html(f:read("*all"), _devBase); f:close() end
                        ms.dev._consolePanelPos = { x=x, y=y, w=w, h=h }
                        panel:navigationCallback(function(_, action)
                            if action == "navigating" then return end
                            -- History is loaded in console.show() so the log read
                            -- never blocks the startup prewarm sequence.
                            hs.timer.doAfter(0, function()
                                local tj = _devThemeJS()
                                if tj ~= "" then pcall(function() panel:evaluateJavaScript(tj) end) end
                            end)
                        end)
                        return panel
                    end

                    ms.dev.console = {}
                    ms.dev.console.show = function()
                        if not ms.dev._consolePanel then
                            ms.dev._consolePanel = _buildConsolePanel()
                            if not ms.dev._consolePanel then return end
                        end
                        ms.dev._consoleOpen = true
                        ms.playSlot("settingsOpen")
                        ms.dev._consolePanel:show()
                        pcall(function() ms.dev._consolePanel:bringToFront(true) end)
                        _devFadeIn(ms.dev._consolePanel, "console")
                        -- Inject history and theme after the panel is visible.
                        hs.timer.doAfter(0.1, function()
                            if not ms.dev._consolePanel or not ms.dev._consoleOpen then return end
                            _loadDevHistory(ms.dev._consolePanel, {"macro", "console", "error", "system", "input"})
                            local tj = _devThemeJS()
                            if tj ~= "" then
                                pcall(function() ms.dev._consolePanel:evaluateJavaScript(tj) end)
                            end
                        end)
                    end
                    ms.dev.console.hide = function()
                        ms.dev._consoleOpen = false
                        if ms.dev._consolePanel then
                            ms.playSlot("settingsClose")
                            _devFadeOut(ms.dev._consolePanel, "console", function()
                                if ms.dev._consolePanel then ms.dev._consolePanel:hide() end
                            end)
                        end
                    end
                    ms.dev.console.toggle = function()
                        if ms.dev._consoleOpen then ms.dev.console.hide()
                        else ms.dev.console.show() end
                    end

                -- END --

                -- Macro Watcher --
                    local _ucWatcher = hs.webview.usercontent.new("msWatcher")
                    _ucWatcher:setCallback(function(msg)
                        local ok, data = pcall(hs.json.decode, msg.body)
                        if not ok or type(data) ~= "table" then return end
                        if data.action == "clear" then
                            for _, cat in ipairs({"macro", "error", "system"}) do
                                local p = _catPaths[cat]; if p then local f = io.open(p, "w"); if f then f:close() end end
                            end
                        elseif data.action == "close" then
                            ms.dev.watcher.hide()
                        elseif data.action == "move" and ms.dev._watcherPanelPos then
                            ms.dev._watcherPanelPos.x = ms.dev._watcherPanelPos.x + (data.dx or 0)
                            ms.dev._watcherPanelPos.y = ms.dev._watcherPanelPos.y + (data.dy or 0)
                            if ms.dev._watcherPanel then
                                pcall(function() ms.dev._watcherPanel:frame(ms.dev._watcherPanelPos) end)
                            end
                        elseif data.action == "playSlot" and data.slot then
                            ms.playSlot(data.slot)
                        end
                    end)

                    -- Builds the macro watcher WebView (hidden). Pre-warmed at startup.
                    local function _buildWatcherPanel()
                        local screen = hs.screen.mainScreen():frame()
                        local w, h   = 360, 640
                        local x = screen.x + screen.w - w - 50
                        local y = screen.y + 44
                        local panel = hs.webview.new({ x=x, y=y, w=w, h=h },
                            { developerExtrasEnabled = true }, _ucWatcher)
                        if not panel then return nil end
                        pcall(function() panel:windowStyle(0) end)
                        pcall(function() panel:level(hs.canvas.windowLevels.floating) end)
                        pcall(function() panel:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces) end)
                        pcall(function() panel:shadow(true) end)
                        local f = io.open(_home .. "/.hammerspoon/ui/ms_watcher.html", "r")
                        if f then panel:html(f:read("*all"), _devBase); f:close() end
                        ms.dev._watcherPanelPos = { x=x, y=y, w=w, h=h }
                        panel:navigationCallback(function(_, action)
                            if action == "navigating" then return end
                            -- History is loaded in watcher.show() so the log read
                            -- never blocks the startup prewarm sequence.
                            hs.timer.doAfter(0, function()
                                local tj = _devThemeJS()
                                if tj ~= "" then pcall(function() panel:evaluateJavaScript(tj) end) end
                            end)
                        end)
                        return panel
                    end

                    ms.dev.watcher = {}
                    ms.dev.watcher.show = function()
                        if not ms.dev._watcherPanel then
                            ms.dev._watcherPanel = _buildWatcherPanel()
                            if not ms.dev._watcherPanel then return end
                        end
                        ms.dev._watcherOpen = true
                        ms.playSlot("settingsOpen")
                        ms.dev._watcherPanel:show()
                        pcall(function() ms.dev._watcherPanel:bringToFront(true) end)
                        _devFadeIn(ms.dev._watcherPanel, "watcher")
                        -- Inject history and theme after the panel is visible.
                        hs.timer.doAfter(0.1, function()
                            if not ms.dev._watcherPanel or not ms.dev._watcherOpen then return end
                            _loadDevHistory(ms.dev._watcherPanel, {"macro", "error", "system"})
                            local tj = _devThemeJS()
                            if tj ~= "" then
                                pcall(function() ms.dev._watcherPanel:evaluateJavaScript(tj) end)
                            end
                        end)
                    end
                    ms.dev.watcher.hide = function()
                        ms.dev._watcherOpen = false
                        if ms.dev._watcherPanel then
                            ms.playSlot("settingsClose")
                            _devFadeOut(ms.dev._watcherPanel, "watcher", function()
                                if ms.dev._watcherPanel then ms.dev._watcherPanel:hide() end
                            end)
                        end
                    end
                    ms.dev.watcher.toggle = function()
                        if ms.dev._watcherOpen then ms.dev.watcher.hide()
                        else ms.dev.watcher.show() end
                    end

                -- END --

                -- Key Monitor --
                    local _ucKeys = hs.webview.usercontent.new("msKeys")
                    _ucKeys:setCallback(function(msg)
                        local ok, data = pcall(hs.json.decode, msg.body)
                        if not ok or type(data) ~= "table" then return end
                        if data.action == "clear" then
                            local p = _catPaths["input"]; if p then local f = io.open(p, "w"); if f then f:close() end end
                        elseif data.action == "close" then
                            ms.dev.keys.hide()
                        elseif data.action == "ready" then
                            -- DOMContentLoaded fired: page JS is parsed and ready.
                            -- Only record that the panel is ready here — no evaluateJavaScript
                            -- calls, because the navigation is still in-flight and any
                            -- synchronous JS call from within this usercontent callback
                            -- re-enters WebKit and deadlocks the loading sequence.
                            -- History + theme injection happen in keys.show() instead.
                            if not ms.dev._keysReady then
                                ms.dev._keysReady = true
                                local _p = hs.mouse.absolutePosition()
                                ms.dev._mousePos = { x = math.floor(_p.x), y = math.floor(_p.y) }
                            end
                        elseif data.action == "setCoordMode" then
                            ms.dev._coordMode = data.mode or "screen"
                            -- Re-push current position immediately in the new coordinate system.
                            hs.timer.doAfter(0.01, function()
                                if ms.dev._keysPanel then
                                    pcall(function() ms.dev._pushMouseState() end)
                                end
                            end)
                        elseif data.action == "move" and ms.dev._keysPanelPos then
                            ms.dev._keysPanelPos.x = ms.dev._keysPanelPos.x + (data.dx or 0)
                            ms.dev._keysPanelPos.y = ms.dev._keysPanelPos.y + (data.dy or 0)
                            if ms.dev._keysPanel then
                                pcall(function() ms.dev._keysPanel:frame(ms.dev._keysPanelPos) end)
                            end
                        elseif data.action == "playSlot" and data.slot then
                            ms.playSlot(data.slot)
                        end
                    end)

                    -- Builds the input monitor WebView (hidden). Pre-warmed at startup.
                    local function _buildKeysPanel()
                        local screen = hs.screen.mainScreen():frame()
                        local w, h   = 360, 640
                        local x = screen.x + screen.w - w - 80
                        local y = screen.y + 68
                        local panel = hs.webview.new({ x=x, y=y, w=w, h=h },
                            { developerExtrasEnabled = true }, _ucKeys)
                        if not panel then return nil end
                        pcall(function() panel:windowStyle(0) end)
                        pcall(function() panel:level(hs.canvas.windowLevels.floating) end)
                        pcall(function() panel:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces) end)
                        pcall(function() panel:shadow(true) end)
                        local f = io.open(_home .. "/.hammerspoon/ui/ms_keys.html", "r")
                        if not f then return nil end
                        panel:html(f:read("*all"), _devBase); f:close()
                        ms.dev._keysPanelPos = { x=x, y=y, w=w, h=h }
                        ms.dev._keysReady    = false
                        panel:navigationCallback(function(_, action)
                            if action ~= "didNavigate" then return end
                            -- Mark the panel ready so live key/mouse events are routed to it.
                            -- No evaluateJavaScript here: calling JS from inside a navigation
                            -- callback re-enters WebKit synchronously and hangs the load sequence.
                            -- History + theme are injected in keys.show() once the panel is visible.
                            if not ms.dev._keysReady then
                                ms.dev._keysReady = true
                                local _p = hs.mouse.absolutePosition()
                                ms.dev._mousePos = { x = math.floor(_p.x), y = math.floor(_p.y) }
                            end
                        end)
                        return panel
                    end

                    ms.dev.keys = {}
                    ms.dev.keys.show = function()
                        if not ms.dev._keysPanel then
                            ms.dev._keysPanel = _buildKeysPanel()
                            if not ms.dev._keysPanel then return end
                        end
                        ms.dev._keysOpen = true
                        ms.dev._keysReady = true
                        ms.playSlot("settingsOpen")
                        ms.dev._keysPanel:show()
                        pcall(function() ms.dev._keysPanel:bringToFront(true) end)
                        _devFadeIn(ms.dev._keysPanel, "keys")
                        -- Inject history and theme after the panel is visible and WebKit is
                        -- fully idle.  doAfter(0.1) gives the show animation one frame and
                        -- ensures navigation is long-settled before evaluateJavaScript runs.
                        hs.timer.doAfter(0.1, function()
                            if not ms.dev._keysPanel or not ms.dev._keysOpen then return end
                            _loadDevHistory(ms.dev._keysPanel, {"input"})
                            pcall(function() ms.dev._pushMouseState() end)
                            local tj = _devThemeJS()
                            if tj ~= "" then
                                pcall(function() ms.dev._keysPanel:evaluateJavaScript(tj) end)
                            end
                        end)
                        -- Poll mouse position every 100 ms so display stays current.
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
                            local prev = ms.dev._mousePos
                            if not prev or _x ~= prev.x or _y ~= prev.y then
                                ms.dev._mousePos = { x = _x, y = _y }
                                ms.dev._pushMouseState(_x, _y)
                            end
                        end)
                    end
                    ms.dev.keys.hide = function()
                        if ms.dev._mousePoller then
                            ms.dev._mousePoller:stop(); ms.dev._mousePoller = nil
                        end
                        ms.dev._keysReady = false
                        ms.dev._keysOpen  = false
                        if ms.dev._keysPanel then
                            ms.playSlot("settingsClose")
                            _devFadeOut(ms.dev._keysPanel, "keys", function()
                                if ms.dev._keysPanel then ms.dev._keysPanel:hide() end
                            end)
                        end
                    end
                    ms.dev.keys.toggle = function()
                        if ms.dev._keysOpen then ms.dev.keys.hide()
                        else ms.dev.keys.show() end
                    end

                -- END --

                -- Mouse state pusher --
                    -- Defined here so both the nav callback and the poller can call it.
                    -- Applies the coordinate transform selected by the user's dropdown.
                    ms.dev._pushMouseState = function(x, y)
                        if not ms.dev._keysPanel then return end
                        local _x = x or (ms.dev._mousePos and ms.dev._mousePos.x) or 0
                        local _y = y or (ms.dev._mousePos and ms.dev._mousePos.y) or 0
                        -- Transform raw screen coordinates to the selected reference frame.
                        local mode = ms.dev._coordMode or "screen"
                        local tx, ty = _x, _y
                        if mode == "window" or mode == "ref" then
                            local win = ms.getTargetWin()
                            if win then
                                local f = win:frame()
                                tx = _x - f.x
                                ty = _y - f.y
                                if mode == "ref" then
                                    tx = math.floor(tx * (1680 / f.w) + 0.5)
                                    ty = math.floor(ty * (1044 / f.h) + 0.5)
                                end
                            end
                        elseif mode == "screenCenter" then
                            local sf = hs.screen.mainScreen():frame()
                            tx = _x - math.floor(sf.w / 2)
                            ty = _y - math.floor(sf.h / 2)
                        end
                        local j = string.format('{"x":%d,"y":%d}', math.floor(tx), math.floor(ty))
                        pcall(function()
                            ms.dev._keysPanel:evaluateJavaScript("updateMouseState(" .. j .. ")")
                        end)
                    end

                -- END --

                -- Dev step logger (call from macros to trace execution) --
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

                -- END --

                -- Window Monitor --
                    local _ucWindow = hs.webview.usercontent.new("msWindow")
                    _ucWindow:setCallback(function(msg)
                        local ok, data = pcall(hs.json.decode, msg.body)
                        if not ok or type(data) ~= "table" then return end
                        if data.action == "clear" then
                            ms.dev._windowHistory = {}
                        elseif data.action == "close" then
                            ms.dev.window.hide()
                        elseif data.action == "move" and ms.dev._windowPanelPos then
                            ms.dev._windowPanelPos.x = ms.dev._windowPanelPos.x + (data.dx or 0)
                            ms.dev._windowPanelPos.y = ms.dev._windowPanelPos.y + (data.dy or 0)
                            if ms.dev._windowPanel then
                                pcall(function() ms.dev._windowPanel:frame(ms.dev._windowPanelPos) end)
                            end
                        elseif data.action == "playSlot" and data.slot then
                            ms.playSlot(data.slot)
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

                    -- Builds the window monitor WebView (hidden). Pre-warmed at startup.
                    local function _buildWindowPanel()
                        local screen = hs.screen.mainScreen():frame()
                        local w, h   = 360, 480
                        local x = screen.x + screen.w - w - 110
                        local y = screen.y + 68
                        local panel = hs.webview.new({ x=x, y=y, w=w, h=h },
                            { developerExtrasEnabled = true }, _ucWindow)
                        if not panel then return nil end
                        pcall(function() panel:windowStyle(0) end)
                        pcall(function() panel:level(hs.canvas.windowLevels.floating) end)
                        pcall(function() panel:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces) end)
                        pcall(function() panel:shadow(true) end)
                        local f = io.open(_home .. "/.hammerspoon/ui/ms_window.html", "r")
                        if f then panel:html(f:read("*all"), _devBase); f:close() end
                        ms.dev._windowPanelPos = { x=x, y=y, w=w, h=h }
                        panel:navigationCallback(function(_, action)
                            if action == "navigating" then return end
                            hs.timer.doAfter(0, function()
                                local tj = _devThemeJS()
                                if tj ~= "" then pcall(function() panel:evaluateJavaScript(tj) end) end
                                if #ms.dev._windowHistory > 0 then
                                    local ok, j = pcall(hs.json.encode, ms.dev._windowHistory)
                                    if ok then pcall(function() panel:evaluateJavaScript("loadHistory(" .. j .. ")") end) end
                                end
                                local win = hs.window.focusedWindow()
                                if win then
                                    local app   = (win:application() and win:application():name()) or "?"
                                    local title = win:title() or ""
                                    local wf    = win:frame()
                                    local ok2, j2 = pcall(hs.json.encode, {
                                        type="focus", ts=os.time(),
                                        app=app, title=title,
                                        w=math.floor(wf.w), h=math.floor(wf.h),
                                        x=math.floor(wf.x), y=math.floor(wf.y),
                                    })
                                    if ok2 then pcall(function() panel:evaluateJavaScript("updateCurrentWindow(" .. j2 .. ")") end) end
                                end
                            end)
                        end)
                        return panel
                    end

                    ms.dev.window = {}
                    ms.dev.window.show = function()
                        if not ms.dev._windowPanel then
                            ms.dev._windowPanel = _buildWindowPanel()
                            if not ms.dev._windowPanel then return end
                        end
                        ms.dev._windowOpen = true
                        ms.playSlot("settingsOpen")
                        ms.dev._windowPanel:show()
                        pcall(function() ms.dev._windowPanel:bringToFront(true) end)
                        _devFadeIn(ms.dev._windowPanel, "window")
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
                        ms.dev._windowOpen = false
                        if ms.dev._windowPanel then
                            ms.playSlot("settingsClose")
                            _devFadeOut(ms.dev._windowPanel, "window", function()
                                if ms.dev._windowPanel then ms.dev._windowPanel:hide() end
                            end)
                        end
                    end
                    ms.dev.window.toggle = function()
                        if ms.dev._windowOpen then ms.dev.window.hide()
                        else ms.dev.window.show() end
                    end

                    -- Pre-warm all four developer panels (hidden) so they load instantly
                    -- when the user first opens them.  Called from startup after a delay
                    -- so it doesn't compete with the main settings panel prewarm.
                    -- Each builder is a local in this scope, so upvalues resolve correctly.
                    ms.dev.prewarm = function()
                        if not ms.dev._consolePanel then
                            ms.dev._consolePanel = _buildConsolePanel()
                        end
                        if not ms.dev._watcherPanel then
                            ms.dev._watcherPanel = _buildWatcherPanel()
                        end
                        if not ms.dev._keysPanel then
                            ms.dev._keysPanel = _buildKeysPanel()
                        end
                        if not ms.dev._windowPanel then
                            ms.dev._windowPanel = _buildWindowPanel()
                        end
                    end

                    -- Builds a single named dev panel. Used by the startup loading sequence
                    -- to spread WebView creation across separate timer ticks so the main
                    -- thread is never blocked for longer than ~300 ms at a time.
                    ms.dev.prewarmStep = function(which)
                        if     which == "console" and not ms.dev._consolePanel then
                            ms.dev._consolePanel = _buildConsolePanel()
                        elseif which == "watcher" and not ms.dev._watcherPanel then
                            ms.dev._watcherPanel = _buildWatcherPanel()
                        elseif which == "keys"    and not ms.dev._keysPanel    then
                            ms.dev._keysPanel    = _buildKeysPanel()
                        elseif which == "window"  and not ms.dev._windowPanel  then
                            ms.dev._windowPanel  = _buildWindowPanel()
                        end
                    end
                -- END --

            end
        -- END --

        -- 13. Safety Nets --
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
                        if k == "integrity" or k == "dev" or k == "showGuardian" or k == "_systemActions" then
                            error("ms_macros.lua: ms." .. k .. " is not accessible from macros.", 2)
                        end
                        -- Wrap ms.key and ms.mouse to strip the internal isSystem
                        -- flag so macro code cannot bypass BindValidity.
                        if k == "key" then
                            return function(mods, key, swallow, pressFn, releaseFn)
                                return ms.key(mods, key, swallow, pressFn, releaseFn, false)
                            end
                        elseif k == "mouse" then
                            return function(button, swallow, clickFn, hidinject)
                                return ms.mouse(button, swallow, clickFn, hidinject, false)
                            end
                        elseif k == "bind" then
                            -- Return a proxy that wraps define() to force system=false,
                            -- preventing macros from registering system binds that bypass
                            -- the BindValidity gate.
                            return setmetatable({}, {
                                __index = function(_, bk)
                                    if bk == "define" then
                                        return function(id, a, b)
                                            local opts = type(a) == "table" and a or (type(b) == "table" and b or {})
                                            opts.system = false
                                            return ms.bind.define(id, a, b)
                                        end
                                    end
                                    return ms.bind[bk]
                                end,
                            })
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
                        -- Primitive-only bridge to _G: allows string/number/boolean
                        -- constants that the macro author may define in init.lua to
                        -- remain accessible, while blocking every non-primitive type
                        -- (functions, tables, userdata, threads).  This closes the
                        -- open-ended _G fallthrough without breaking the init.lua
                        -- custom-constant pattern.  Once §1.2 (ms.fn) lands and all
                        -- coroutine use is wrapped, this can be tightened further to
                        -- error on any unlisted global regardless of type.
                        local v = rawget(_G, k)
                        local vt = type(v)
                        if vt == "string" or vt == "number" or vt == "boolean" or v == nil then
                            return v
                        end
                        error("ms_macros.lua: access to '" .. tostring(k)
                            .. "' is not permitted (non-primitive globals are not accessible from macros).", 2)
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

                -- Store sandbox reference so ms.quickReload() can reuse it.
                ms._macroSandbox = sandbox

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
                trackpadMode = false,
                socdEnabled  = false,
                socdMode     = "lastWins",
                macros = {
                    spawnAlt = { enabled = false },
                },
            }
        -- END --
    -- END Hammerspoon mudscript Utility Library --

    -- Startup Executions --
        -- Privileged system actions: registered here (outside the sandbox) so
        -- macros cannot set or spoof them.  Each entry is keyed by the setting
        -- key it belongs to and called by userSettingAction after the sandboxed
        -- onAction has run.
        ms._systemActions = {}
        if ms._userSettingIndex["showTamperWarning"] then
            ms._systemActions["showTamperWarning"] = function()
                ms.showGuardian()
            end
        end

        -- Seed ms.binds from registry defaults for any id not set by the settings file.
        for _, id in ipairs(ms.registry._defList) do
            local def = ms.registry._defs[id]
            if def and not def.sub and ms.binds[id] == nil then
                ms.binds[id] = def.enabled
            end
        end
        ms._skipDevPrewarm   = false  -- overridden by loadSettings() if previously saved
        ms._devArchiveLimit   = 15     -- overridden by loadSettings() if previously saved
        ms._loadComplete   = false  -- gates macro activation; set to true by _announceLoad
        ms._discoverSounds()
        ms.loadSettings()
        ms.loadTheme()
        ms.cam.updateMultiplier()
        -- Clean up any stale update sentinel from a previous session.
        os.remove(os.getenv("HOME") .. "/.hammerspoon/data/.ms_update_pending")
        ms.bind._registerSystemBinds()
        ms.bind.rebind()
        ms.socdApply()
        BindValidity = 0  -- block macros during loading; _announceLoad re-enables when toasts fire
        ms._startupSoundDone = false  -- suppresses all non-load sounds until _announceLoad runs
        -- Startup Loading Indicator --
            -- Lightweight hs.canvas panel that shows progress while WebViews initialise
            -- in the background.  Each WebView creation is pushed into its own timer tick
            -- so the main thread never blocks for more than ~300 ms at a stretch.
            local _lCanvas, _lBarMax, _lBarY, _lFadingOut, _lFadeTimer
            local _lUpdate, _lFadeOut, _loadAnnounced, _announceLoad
            local _needsIntegrityWarning = false  -- set by the integrity timer; shown after announce toasts
            do
                local sf  = hs.screen.mainScreen():frame()
                local lw, lh = 300, 104
                local lx  = sf.x + math.floor((sf.w - lw) / 2)
                local ly  = sf.y + sf.h - 150 - lh  -- bottom edge aligns with toast baseline
                _lBarMax  = lw - 32
                _lBarY    = 62
                -- Derive palette from the loaded theme so the canvas respects the active profile.
                -- Falls back to the original dark crimson defaults when a key is absent.
                local function _themeColor(hex, fallR, fallG, fallB, alpha)
                    local r, g, b = (hex or ""):match("^#?(%x%x)(%x%x)(%x%x)$")
                    if r then
                        return {
                            red   = tonumber(r, 16) / 255,
                            green = tonumber(g, 16) / 255,
                            blue  = tonumber(b, 16) / 255,
                            alpha = alpha or 1.0,
                        }
                    end
                    return { red = fallR, green = fallG, blue = fallB, alpha = alpha or 1.0 }
                end
                local _t = ms._theme or {}
                local clrBg     = _themeColor(_t.bg,       0.024, 0.016, 0.008, 0.95)
                local clrAccent = _themeColor(_t.accent,   0.769, 0.102, 0.102, 1.0)
                local clrText   = _themeColor(_t.text,     0.941, 0.867, 0.690, 1.0)
                local clrText2  = _themeColor(_t.warning,  0.824, 0.647, 0.392, 0.72)
                local clrTrack  = _themeColor(_t.surface2, 0.063, 0.039, 0.024, 1.0)
                local clrBorder = _themeColor(_t.hover,    0.510, 0.196, 0.086, 0.55)
                -- Derive font: accept any plain name (no path separators), fall back to Almendra.
                local _titleFont = (type(_t.font) == "string" and #_t.font > 0
                    and not _t.font:find("[/\\]"))
                    and _t.font or "Almendra"
                _lCanvas = hs.canvas.new({ x=lx, y=ly, w=lw, h=lh })
                _lCanvas:level(hs.canvas.windowLevels.popUpMenu or 25)
                _lCanvas:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
                _lCanvas:alpha(0)
                _lCanvas:appendElements(
                    -- 1: background
                    { type="rectangle", action="strokeAndFill",
                      fillColor=clrBg, strokeColor=clrBorder, strokeWidth=1,
                      roundedRectRadii={ xRadius=5, yRadius=5 } },
                    -- 2: top accent strip
                    { type="rectangle", action="fill", fillColor=clrAccent,
                      frame={ x=0, y=0, w=lw, h=2 },
                      roundedRectRadii={ xRadius=5, yRadius=5 } },
                    -- 3: title (static)
                    { type="text", text="mudscript",
                      frame={ x=16, y=13, w=lw-32, h=22 },
                      textFont=_titleFont, textSize=15,
                      textColor=clrText, textAlignment="left" },
                    -- 4: status line (updated by _lUpdate)
                    { type="text", text="Starting up\xe2\x80\xa6",
                      frame={ x=16, y=37, w=lw-32, h=16 },
                      textFont="Helvetica Neue", textSize=11,
                      textColor=clrText2, textAlignment="left" },
                    -- 5: progress track
                    { type="rectangle", action="fill", fillColor=clrTrack,
                      frame={ x=16, y=_lBarY, w=_lBarMax, h=3 },
                      roundedRectRadii={ xRadius=1.5, yRadius=1.5 } },
                    -- 6: progress fill (frame.w updated by _lUpdate)
                    { type="rectangle", action="fill", fillColor=clrAccent,
                      frame={ x=16, y=_lBarY, w=0, h=3 },
                      roundedRectRadii={ xRadius=1.5, yRadius=1.5 } },
                    -- 7: separator above checkbox row
                    { type="rectangle", action="fill", fillColor=clrBorder,
                      frame={ x=16, y=75, w=_lBarMax, h=1 } },
                    -- 8: hit area — transparent full-width row, trackMouseDown for click detection
                    { type="rectangle", action="fill",
                      fillColor={ red=0, green=0, blue=0, alpha=0 },
                      frame={ x=16, y=80, w=_lBarMax, h=18 },
                      trackMouseDown=true },
                    -- 9: checkbox glyph (☐ / ☑) — updated on toggle
                    { type="text",
                      text=(ms._skipDevPrewarm and "\xe2\x98\x91" or "\xe2\x98\x90"),
                      frame={ x=17, y=80, w=18, h=18 },
                      textFont="Helvetica Neue", textSize=13,
                      textColor=clrText2, textAlignment="left" },
                    -- 10: label
                    { type="text", text="Skip dev tool preloading",
                      frame={ x=36, y=83, w=_lBarMax-22, h=14 },
                      textFont="Helvetica Neue", textSize=11,
                      textColor=(ms._skipDevPrewarm and clrText or clrText2),
                      textAlignment="left" },
                    -- 11: active profile name (right-aligned in the title row)
                    { type="text",
                      text=(ms.macroMeta and ms.macroMeta.name) or "",
                      frame={ x=16, y=15, w=lw-32, h=18 },
                      textFont="Helvetica Neue", textSize=10,
                      textColor=clrText2, textAlignment="right" }
                )
                _lCanvas:show()
                ms.playSlot("startup")  -- loading sequence start sound
                local function _lfade()
                    local step, steps = 0, 6
                    local t = hs.timer.doEvery((ms._theme.fadeMs or 150) / 1000 / steps, function()
                        step = step + 1
                        if _lCanvas then _lCanvas:alpha(step / steps) end
                        if step >= steps and t then t:stop() end
                    end)
                end
                _lfade()
                _lCanvas:mouseCallback(function(canvas, event, id, x, y)
                    if event ~= "mouseDown" or id ~= 8 then return end
                    ms._skipDevPrewarm = not ms._skipDevPrewarm
                    pcall(ms.saveSettings)
                    canvas[9].text       = ms._skipDevPrewarm and "\xe2\x98\x91" or "\xe2\x98\x90"
                    canvas[10].textColor = ms._skipDevPrewarm and clrText or clrText2
                    if ms._skipDevPrewarm and not _lFadingOut then
                        _lUpdate(100, "Developer tools skipped.")
                        hs.timer.doAfter(0.8, _lFadeOut)
                    end
                end)
            end

            _lUpdate = function(pct, msg)
                if not _lCanvas then return end
                _lCanvas[4].text  = msg
                _lCanvas[6].frame = {
                    x=16, y=_lBarY,
                    w=math.max(4, math.floor(_lBarMax * pct / 100)), h=3,
                }
            end

            -- Plays the load-complete sounds and shows the startup toasts.  Fires once
            -- (guarded by _loadAnnounced) — triggered from the canvas delete callback
            -- so it runs immediately after the loading screen is gone.
            -- doAfter(7.0) below acts as a fallback in case the canvas never fades.
            _announceLoad = function()
                if _loadAnnounced then return end
                _loadAnnounced = true
                -- Load-end sound fires the instant the canvas disappears.
                pcall(function() ms.playSlot("load") end)
                -- Brief pause before opening the gate so the load-end sound
                -- has a moment before any subsequent sounds can play.
                hs.timer.doAfter(0.4, function()
                    -- Open the sound gate for all future sounds.
                    ms._startupSoundDone = true
                    -- Launch sound plays with the first toast.
                    pcall(function() ms.playSlot("launch") end)
                    -- 1. Settings notice (immediate)
                    ms.alert("Macros loaded. Press \xe2\x8c\xa5 and P to open settings.", 3, true)
                    -- 2. Library creator \xe2\x80\x94 after first toast fades
                    hs.timer.doAfter(3, function()
                        ms.alert("Hammerspoon mudscript Utility Library\nBy: mudbourn \xe2\x80\x94 https://mudbourn.info", 3, true)
                    end)
                    -- 3. Macro pack creator \xe2\x80\x94 after second toast fades
                    hs.timer.doAfter(6, function()
                        if ms.macroMeta then
                            local msg = "\"" .. (ms.macroMeta.name or "Unknown Macro Pack") .. "\"\n"
                            if ms.macroMeta.author  then msg = msg .. "By: " .. ms.macroMeta.author end
                            if ms.macroMeta.website then msg = msg .. " \xe2\x80\x94 " .. ms.macroMeta.website end
                            ms.alert(msg, 3, true)
                        end
                    end)
                    -- Loading complete: allow macros to run and activate them if Roblox is already focused.
                    ms._loadComplete = true
                    ms.dev.log({ type = "system", event = "startup_complete" })
                    if ms._robloxActive then ms.setMacros(1, true) end
                    -- 4. Integrity warning / update check — after all three announce toasts
                    -- have faded (3 x 3 s = 9 s total) plus a 1 s gap.
                    hs.timer.doAfter(10, function()
                        if _needsIntegrityWarning then
                            ms.alert("\xe2\x9a\xa0 No trusted hash on record.\nSettings \xe2\x86\x92 Developer \xe2\x86\x92 Trust Current Version.", 10)
                        else
                            local _checkFn = (ms._updateChannel == "testing")
                                and ms.integrity.checkForUpdateBeta
                                or  ms.integrity.checkForUpdate
                            _checkFn(function(u)
                                if u then
                                    ms.playSlot("updateAvailable")
                                    ms.alert("Update " .. u.version .. " available.\nSettings \xe2\x86\x92 Help \xe2\x86\x92 Check for Update to install.", 8, true)
                                end
                            end)
                        end
                    end)
                end)
            end

            _lFadeOut = function()
                if not _lCanvas or _lFadingOut then return end
                _lFadingOut = true
                local step, steps = 0, 6
                _lFadeTimer = hs.timer.doEvery((ms._theme.fadeMs or 150) / 1000 / steps, function()
                    step = step + 1
                    if _lCanvas then _lCanvas:alpha(1 - (step / steps)) end
                    if step >= steps then
                        if _lFadeTimer then _lFadeTimer:stop(); _lFadeTimer = nil end
                        if _lCanvas then _lCanvas:delete(); _lCanvas = nil end
                        hs.timer.doAfter(0.1, _announceLoad)
                    end
                end)
            end

            -- Stagger each WebView creation into its own timer tick so startup
            -- never freezes for more than one build at a time.
            hs.timer.doAfter(0, function()
                ms.ui.prebuild()
                _lUpdate(18, "Building UI state cache\xe2\x80\xa6")
            end)
            hs.timer.doAfter(0.3, function()
                ms.ui.prewarm()
                _lUpdate(32, "Loading settings panel\xe2\x80\xa6")
            end)
            -- Each dev-panel step is split across two ticks:
            --   tick 1 (doAfter N): update the progress label and bar, then return so
            --                       Core Animation can flush the redraw to the screen.
            --   tick 2 (doAfter 0): create the WebView (potentially slow) in the next
            --                       run-loop iteration so the user sees the label update
            --                       before any brief block.
            hs.timer.doAfter(2.0, function()
                if ms._skipDevPrewarm then return end
                _lUpdate(50, "Loading console\xe2\x80\xa6")
                hs.timer.doAfter(0, function()
                    if not ms._skipDevPrewarm then pcall(function() ms.dev.prewarmStep("console") end) end
                end)
            end)
            hs.timer.doAfter(2.6, function()
                if ms._skipDevPrewarm then return end
                _lUpdate(62, "Loading macro monitor\xe2\x80\xa6")
                hs.timer.doAfter(0, function()
                    if not ms._skipDevPrewarm then pcall(function() ms.dev.prewarmStep("watcher") end) end
                end)
            end)
            hs.timer.doAfter(3.2, function()
                if ms._skipDevPrewarm then return end
                _lUpdate(75, "Loading input monitor\xe2\x80\xa6")
                hs.timer.doAfter(0, function()
                    if not ms._skipDevPrewarm then pcall(function() ms.dev.prewarmStep("keys") end) end
                end)
            end)
            hs.timer.doAfter(3.8, function()
                if ms._skipDevPrewarm then return end
                _lUpdate(88, "Loading window monitor\xe2\x80\xa6")
                hs.timer.doAfter(0, function()
                    if not ms._skipDevPrewarm then pcall(function() ms.dev.prewarmStep("window") end) end
                end)
            end)
            hs.timer.doAfter(4.6, function()
                if not _lFadingOut then
                    _lUpdate(100, "Ready.")
                    hs.timer.doAfter(0.8, _lFadeOut)
                end
            end)
            -- Failsafe: if any prewarm step stalls and the normal fade never fires,
            -- force-dismiss the loading screen after 8 s so startup always completes.
            hs.timer.doAfter(8, function()
                if _lCanvas and not _lFadingOut then _lFadeOut() end
                -- Also open the sound gate so sounds are never permanently suppressed.
                ms._startupSoundDone = true
            end)
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
                -- Bootstrap failed: flag the warning so _announceLoad shows it after
                -- the startup toasts have had time to display and fade.
                _needsIntegrityWarning = true
            end)

        -- Activate Roblox so the app watcher can seed _robloxActive correctly
        -- on first launch.

            if roblox then roblox:activate() end

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
                if ms._updateInProgress then return end  -- skip during updates
                -- Non-blocking: returns the cached value immediately and kicks off a
                -- background hs.task hash when the 60-second window expires.
                -- hs.reload() on mismatch is called inside the task callback.
                ms.integrity.check()
            end)

            if notice ~= 1 then
                -- Primary path: _announceLoad fires from the canvas delete callback (see _lFadeOut)
                -- so toasts appear immediately after the loading screen is gone.
                -- This doAfter(7.0) is a belt-and-suspenders fallback for edge cases where
                -- the canvas never fades (e.g., Hammerspoon is killed mid-load and relaunched).
                hs.timer.doAfter(7.0, _announceLoad)
                notice = 1
            end
        -- END --
    -- END Startup Executions --
-- END Core System --
