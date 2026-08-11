-- MsUI — converted from a Spoon; Spoons/ is reserved for plugins.
return function(ms)
-- MsUI --
    local MsUI = {}

    MsUI.name    = "MsUI"
    MsUI.version = "1.0"

    -- Shell-quote a path for hs.execute/os.execute. Defined once at file
    -- scope: it used to be re-declared as a local inside five separate
    -- handlers, and the sound-import handler grew two calls above its own
    -- copy — so `sq` was a nil global there and the handler died before it
    -- copied anything.
    local function sq(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end
-- END MsUI --

-- Init --
    function MsUI:init()
    end
-- END Init --

-- Start --
    function MsUI:start()
        if not _G.ms then return end
        local ms = _G.ms
        if ms.checkGuardian and not ms.checkGuardian("MsUI") then return end

        -- Run the webview panel initialization
        self:_initPanel(ms)
    end
-- END Start --

-- Webview Panel --
    function MsUI:_initPanel(ms)
    require("hs.webview")
    require("hs.webview.usercontent")
    -- Panel State & Builders --
        ms.ui = {
            _panel         = nil,
            _open          = false,
            _modalCallback = nil,
            _panelPos      = nil,
            _uiFadeTimer   = nil,
        }

        local function _bindDisplay(c)
            if not c then return nil end
            -- Accumulated modifiers first, then the trigger. Derived sub-binds
            -- resolve to their root's trigger type (mouse/scroll/gamepad/key)
            -- but carry their own mods in c.mods; every branch below must show
            -- them, or a sub of a mouse/scroll/gamepad parent reads as the bare
            -- root bind with its modifier silently dropped.
            local parts = {}
            for _, m in ipairs(c.mods or {}) do
                table.insert(parts, m:sub(1, 1):upper() .. m:sub(2))
            end
            local trigger
            if c.type == "mouse" then
                trigger = "Mouse " .. tostring(c.button)
            elseif c.type == "scroll" then
                local d = c.direction or "?"
                trigger = "Scroll " .. d:sub(1,1):upper() .. d:sub(2)
            elseif c.type == "gamepad" then
                trigger = "Pad " .. (c.button or "?"):upper()
            elseif c.type == "combo" then
                local ks = {}
                for _, k in ipairs(c.keys or {}) do ks[#ks+1] = (k or ""):upper() end
                trigger = table.concat(ks, "+")
            else
                trigger = (c.key or ""):upper()
            end
            table.insert(parts, trigger)
            return table.concat(parts, "+")
        end

        -- Same content as _bindDisplay, but as an ordered list of individual
        -- tokens (each modifier, then each trigger key) rather than a joined
        -- string — so the rebind prompt can render one spotlighted key cap per
        -- token. A combo splits into a cap per key; single-shot triggers are one.
        local function _bindTokens(c)
            if not c then return {} end
            local out = {}
            for _, m in ipairs(c.mods or {}) do
                out[#out + 1] = m:sub(1, 1):upper() .. m:sub(2)
            end
            if c.type == "mouse" then
                out[#out + 1] = "Mouse " .. tostring(c.button)
            elseif c.type == "scroll" then
                local d = c.direction or "?"
                out[#out + 1] = "Scroll " .. d:sub(1,1):upper() .. d:sub(2)
            elseif c.type == "gamepad" then
                out[#out + 1] = "Pad " .. (c.button or "?"):upper()
            elseif c.type == "combo" then
                for _, k in ipairs(c.keys or {}) do out[#out + 1] = (k or ""):upper() end
            else
                out[#out + 1] = (c.key or ""):upper()
            end
            return out
        end

        -- A bind is *derived* (a sub-bind of another macro) when its
        -- default.type names another registered bind id — the same test
        -- ms.bind.define uses. Testing default.type alone is not enough:
        -- ordinary binds carry default.type = "key"/"mouse"/"scroll"/"gamepad",
        -- and treating those as derived hides them from the macro list.
        local function _parentOf(def)
            if not def then return nil end
            local d = def.default
            if type(d) ~= "table" or not d.type then return nil end
            if ms.registry._defs[d.type] then return d.type end
            return nil
        end

        -- A derived bind is *severed* from its parent once the user gives it a
        -- concrete override via a full rebind: bindConfig then holds a real
        -- trigger (key/combo/mouse/scroll/gamepad) instead of { type = <parentId> }.
        -- A severed sub graduates to its own top-level row — branched off into
        -- its own adjacent tree — rather than nesting under the parent it no
        -- longer inherits from. Clearing the modifier (or resetting) writes the
        -- derived link back and re-nests it.
        local function _severedFromParent(id)
            local cfg = ms.bindConfig and ms.bindConfig[id]
            if type(cfg) ~= "table" or not cfg.type then return false end
            return ms.registry._defs[cfg.type] == nil
        end

        -- Builds the full macro list: top-level macros in registration order,
        -- each carrying its derived sub-binds, followed by the system binds.
        local function _buildMacroList()
            local macros  = {}
            local byId    = {}

            for _, id in ipairs(ms.registry._defList or {}) do
                local def = ms.registry._defs[id]
                if def and not def.system and (not _parentOf(def) or _severedFromParent(id)) then
                    local eff = ms.effectiveBind(id)
                    local bindable = eff ~= nil
                    local enabled = ms.binds[id]
                    if enabled == nil then enabled = def.enabled end
                    local entry = {
                        id        = id,
                        label     = def.label,
                        group     = def.group,
                        bind      = _bindDisplay(eff),
                        -- Without a bind there is no trigger, so the macro can
                        -- never be effectively on — report it off and let the
                        -- UI lock the toggle (see `bindable`).
                        enabled   = (enabled and bindable) and true or false,
                        bindable  = bindable,
                        subs      = {},
                    }
                    byId[id] = entry
                    table.insert(macros, entry)
                end
            end

            -- Attach derived binds to their parent. Walk up the chain so a
            -- sub-of-a-sub (e.g. throwLow → superThrow → superJump) lands on
            -- the nearest ancestor that is itself top-level.
            for _, id in ipairs(ms.registry._defList or {}) do
                local def    = ms.registry._defs[id]
                local parent = _parentOf(def)
                if def and not def.system and parent and not _severedFromParent(id) then
                    local seen = { [id] = true }
                    while parent and not byId[parent] and not seen[parent] do
                        seen[parent] = true
                        parent = _parentOf(ms.registry._defs[parent])
                    end
                    local host = parent and byId[parent]
                    if host then
                        table.insert(host.subs, {
                            id     = id,
                            label  = def.label,
                            bind   = _bindDisplay(ms.effectiveBind(id)),
                            parent = parent,
                        })
                    end
                end
            end

            for _, id in ipairs({"enable", "disable", "toggle"}) do
                local def = ms.systemBinds._defs[id]
                if def then
                    table.insert(macros, {
                        id         = id,
                        label      = def.label,
                        group      = "system",
                        bind       = _bindDisplay(ms.systemBinds.effective(id)),
                        systemBind = true,
                        subs       = {},
                    })
                end
            end

            return macros
        end
        ms.ui._buildMacroList = _buildMacroList

        local function _buildUIState()
            local macros = _buildMacroList()

            ms._discoverSounds()
            local soundNames = {}
            for name in pairs(ms.sounds or {}) do table.insert(soundNames, name) end
            table.sort(soundNames)

            local macroSoundNames = {}
            for name in pairs(ms.macroSounds or {}) do table.insert(macroSoundNames, name) end
            table.sort(macroSoundNames)

            -- One entry per sound *file*, which is the axis the Sounds tab
            -- lists on — slots are a separate axis, and several slots can
            -- point at one file. `kind` is derived from the directory the
            -- scan found it in rather than the name prefix, because the
            -- directory is what _autoSortSounds actually guarantees.
            local soundEntries = {}
            -- `role` is what the file *is*, from the directory it sits in.
            -- `imported` is where it came from. These used to be the same
            -- field, so an import was labelled "imported" and nothing else —
            -- there was no way to see, or say, whether it was an active sound
            -- or a macro sound. Provenance does not decide type.
            local function _entry(name, path, role)
                local imported = (ms.importedSounds or {})[name] ~= nil
                soundEntries[#soundEntries + 1] = {
                    name      = name,
                    -- What the Sounds tab groups on. Imports keep their own
                    -- group so something you brought in stays findable
                    -- whichever role you give it.
                    kind      = imported and "imported" or role,
                    role      = role,
                    imported  = imported,
                    -- Defaults are the fallback floor; removing one would
                    -- leave slots resolving to nothing.
                    removable = (role ~= "default"),
                }
            end
            for _, name in ipairs(soundNames) do
                local path = (ms.sounds or {})[name] or ""
                _entry(name, path,
                    path:find("/sounds/defaults/") and "default" or "active")
            end
            for _, name in ipairs(macroSoundNames) do
                _entry(name, (ms.macroSounds or {})[name] or "", "macro")
            end

            -- Build sound presets from the d_* (default) and a_* (active)
            -- series named by ms.soundSlots. Preset 1 is the a_* sample with
            -- no suffix; 2 and 3 are the numbered variants, each falling back
            -- through the unsuffixed a_* to the slot's default. Slots the
            -- registry gives no sample of their own are skipped — a preset has
            -- nothing to say about a slot that borrows.
            local soundPresets = ms.buildSoundPresets()

            local status, curHash = ms.integrity.check()
            local meta = ms.macroMeta or {}

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

            -- What the theme editor can offer as a font: every font file under
            -- ui/fonts/ (each file is its own @font-face family) plus the
            -- families macOS always has. Values are what ms_theme.json stores —
            -- a path relative to ~/.hammerspoon for files, a family name for the rest.
            local themeFonts = {}
            for _, fam in ipairs({ "Almendra", "Palatino", "Georgia", "Helvetica", "Menlo" }) do
                table.insert(themeFonts, { label = fam, value = fam })
            end
            local _fontDir = os.getenv("HOME") .. "/.hammerspoon/ui/fonts/"
            if hs.fs.attributes(_fontDir) then
                local files = {}
                for entry in hs.fs.dir(_fontDir) do
                    if entry:match("%.[ot]tf$") or entry:match("%.woff2?$") then
                        table.insert(files, entry)
                    end
                end
                table.sort(files)
                for _, entry in ipairs(files) do
                    table.insert(themeFonts, {
                        label = entry:match("^(.+)%.[^%.]+$") or entry,
                        value = "ui/fonts/" .. entry,
                    })
                end
            end

            -- The raw file, so the editor can show which keys are actually set.
            local themeFile = ms.readThemeFile and ms.readThemeFile() or {}
            local themeSet  = {}
            for k in pairs(themeFile) do themeSet[k] = true end

            local themeOut = {}
            for k, v in pairs(ms._theme) do themeOut[k] = v end
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
                trackpadMode            = ms.trackpadMode or false,
                socdEnabled             = ms.socdEnabled or false,
                socdMode                = ms.socdMode or "lastWins",

                soundEnabled            = ms.soundEnabled,
                soundVolume             = ms.soundVolume or 100,
                soundAssign             = ms.soundAssign or {},
                -- The Sounds tab builds its rows, its group headings and its
                -- Default preset from this rather than from a list of its own.
                soundSlots              = ms.soundSlots or {},
                soundNames              = soundNames,
                macroSoundNames         = macroSoundNames,
                soundEntries            = soundEntries,
                bundleSoundsWithTheme   = ms.bundleSoundsWithTheme ~= false,
                soundPresets            = soundPresets,
                currentProfile          = meta.name and ms.sanitizeName(meta.name) or "",
                profiles                = ms.getProfiles(),
                integrityStatus         = status,
                integrityHash           = curHash,
                -- Installed plugins, with this session's load outcome folded
                -- in. `enabled` is what the user asked for and `loadError` is
                -- what happened — a plugin can be on and still not running,
                -- and the panel has to be able to tell those apart.
                plugins                 = (function()
                    if not (ms.package and ms.package.listPlugins) then return {} end
                    local ok, list = pcall(ms.package.listPlugins)
                    if not ok or type(list) ~= "table" then return {} end
                    local failed = (ms.plugins and ms.plugins.failed) or {}
                    local loaded = (ms.plugins and ms.plugins.loaded) or {}
                    for _, p in ipairs(list) do
                        p.loadError = failed[p.dir]
                        p.running   = loaded[p.dir] == true
                    end
                    return list
                end)(),
                macroMeta               = {
                    name    = meta.name,
                    author  = meta.author,
                    website = meta.website,
                },
                docsURL                 = ms._docsURL,
                updateManifestURL       = ms._updateManifestURL,
                userSettings            = userSettings,
                userCalibrationSettings = userCalibrationSettings,
                userSoundSlots          = userSoundSlots,
                userMenus               = userMenus,
                hiddenFeatures          = ms._hiddenFeatures,
                customThemeEnabled      = not (ms._customThemeDisabled or false),
                devArchiveLimit         = ms._devArchiveLimit or 15,
                updateChannel           = ms._updateChannel or "stable",
                testingSource           = ms._testingSource or "release",
                cacheCleanerEnabled     = ms._cacheCleanerEnabled or false,
                octaneMode              = ms._octaneMode or false,
                octaneMuteSounds        = ms._octaneMuteSounds or false,
                macroLabEnabled         = ms._macroLabEnabled ~= false,
                githubToken             = (function()
                    if ms._githubToken then return ms._githubToken end
                    local f = io.open(os.getenv("HOME") .. "/.hammerspoon/data/.ms_github_token", "r")
                    if f then local t = f:read("*l"); f:close(); if t then ms._githubToken = t; return t end end
                    return ""
                end)(),
                qrOptions               = ms._qrOptions or {
                    macros   = true,
                    theme    = true,
                    settings = true,
                    ui       = true,
                },
                consoleOpen             = ms.dev._consoleOpen or false,
                watcherOpen             = ms.dev._watcherOpen or false,
                keysOpen                = ms.dev._keysOpen or false,
                windowOpen              = ms.dev._windowOpen or false,
                theme                   = themeOut,
                themeFonts              = themeFonts,
                themeSet                = themeSet,
                -- themeOut.font is the display family; this is the value on disk.
                themeFontValue          = themeFile.font or ms._theme.font or "",
                msVersion               = (function()
                    local p = os.getenv("HOME") .. "/.hammerspoon/MANIFEST.json"
                    local f = io.open(p, "r")
                    if not f then return nil end
                    local ok, m = pcall(hs.json.decode, f:read("*all")); f:close()
                    local base = (ok and m and m.version) or nil
                    if not base then return nil end

                    if ms._updateChannel == "testing" then
                        local maj, min, pat = base:match("^(%d+)%.(%d+)%.(%d+)$")
                        if maj and min and pat then
                            local nextVer = maj .. "." .. min .. "." .. tostring(tonumber(pat) + 1)
                            local buildPath = os.getenv("HOME") .. "/.hammerspoon/data/.ms_build_num"
                            local bf = io.open(buildPath, "r")
                            local buildNum = 0
                            if bf then buildNum = tonumber(bf:read("*all")) or 0; bf:close() end
                            return nextVer .. "-pre." .. tostring(buildNum)
                        end
                    end
                    return base
                end)(),
            }
        end
    -- END Panel State & Builders --

    -- UI State Cache --
        local _uiStateDirty = true   -- true = cache needs rebuilding
        local _uiStateJSON  = nil    -- "receiveState(...)" ready to eval

        local function _rebuildUICache()
            local ok, json = pcall(hs.json.encode, _buildUIState())
            if ok then
                _uiStateJSON  = "receiveState(" .. json .. ");"
                _uiStateDirty = false
            end
        end

        ms.ui.markDirty = function() _uiStateDirty = true end

        ms.ui.refresh = function()
            if _uiStateDirty or not _uiStateJSON then _rebuildUICache() end
            if _uiStateJSON then
                -- Push to shell if active
                if ms.shell and ms.shell.isReady and ms.shell.isReady() then
                    pcall(function()
                        -- shellReceive routes to the registered "settings" panel handler
                        -- (shellDispatch would send BACK to Lua — wrong direction)
                        ms.shell.eval("shellReceive('settings', 'state', " .. (_uiStateJSON:match("^receiveState%((.*)%);$") or "null") .. ")")
                    end)
                end
            end
            -- The macros panel owns rebinding, so it needs the same refresh
            -- signal: a completed capture must repaint its bind list too.
            pcall(function() ms.ui.pushBindList() end)
        end

        --- Push the full macro/bind list to the macros panel.
        ms.ui.pushBindList = function()
            if not (ms.shell and ms.shell.isReady and ms.shell.isReady()) then return end
            local ok, json = pcall(hs.json.encode, _buildMacroList())
            if not ok or not json then return end
            pcall(function()
                ms.shell.eval("shellReceive('macros', 'bindList', " .. json .. ")")
            end)
        end

        ms.ui.prebuild = function()
            if _uiStateDirty or not _uiStateJSON then _rebuildUICache() end
        end

        ms.ui._precacheHTML = function()
            -- No-op since the legacy standalone panel was deleted (2026-07-13);
            -- kept so boot warmup callers don't break.
        end

        local function _emptyToNil(s) if s == nil or s == "" then return nil end; return s end

        -- Bring focus back to the target app after a capture flow, and mark the
        -- panel open again so ms_core's focus watcher restores macros correctly.
        local function _restoreAfterCapture()
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

        -- Unified rebind prompt. One modal carries the whole flow — it informs
        -- the user, streams the keys being held live, then turns into a confirm
        -- for the detected bind — replacing the old floating alert toast plus a
        -- separate confirm modal. It lives in the shell webview above whichever
        -- panel is active, so a rebind started from Macros › Binds prompts there.
        --
        --   opts.label     bind label, shown in the prompt
        --   opts.current   current bind display string (or nil → "unset")
        --   opts.gamepad   also capture controller buttons
        --   opts.validate  function(parsed, bindStr) → error string | nil
        --                   (e.g. a sibling conflict); shown as a retry prompt
        --   opts.apply     function(parsed, bindStr) — commit the accepted bind
        --   opts.onCancel  function() — restore focus/refresh on cancel/timeout
        --
        -- Phases: "capture" (eventtap live, confirm button hidden — a click would
        -- itself land as a mouse bind, so Escape is the only cancel here) →
        -- "confirm" or "conflict" (eventtap stopped, so the modal's own buttons
        -- and Enter/Escape work again).
        local function _rebindModal(opts)
            local label   = opts.label or "bind"
            local current = opts.current or "unset"

            ms.ui.ensureVisible()

            local phase = "capture"          -- capture | confirm | conflict
            local capturedParsed, capturedStr
            local capture, cancelTimer
            local settled   = false          -- capture eventtap has finished
            local heldCodes = {}
            local heldCount = 0
            local comboKeys = {}
            local comboSeen = {}
            local comboMods = {}
            local started   = false

            local INSTRUCTIONS =
                "Press a key, or hold a combo. Mouse buttons, scroll,\n"
                .. "and controller buttons work too.\n"
                .. "Release to set  ·  Escape to cancel."

            -- The detected keys render as spotlighted caps below this text
            -- (see the keys[] payload), so the message stays instructional only.
            local function captureMsg()
                return "Current:  " .. current .. "\n\n" .. INSTRUCTIONS
            end

            local function stopCapture()
                if capture then capture:stop(); capture = nil end
                if cancelTimer then cancelTimer:stop(); cancelTimer = nil end
                if ms._gamepadCallbacks then ms._gamepadCallbacks._rebind = nil end
            end

            local function modList()
                local mods = {}
                for _, m in ipairs({ "cmd", "alt", "ctrl", "shift" }) do
                    if comboMods[m] then mods[#mods + 1] = m end
                end
                return mods
            end

            local startCapture   -- forward declaration (conflict → "Try Again")

            -- The single close callback for the modal opened by startCapture.
            -- Which branch runs depends on the phase the modal was in when closed.
            local function onClosed(r)
                local confirmed = r and r.confirmed
                if phase == "conflict" and confirmed then
                    startCapture()          -- "Try Again": re-open and re-capture
                    return
                end
                ms._inputOpen = false
                if phase == "confirm" and confirmed then
                    opts.apply(capturedParsed, capturedStr)
                    _restoreAfterCapture()
                    ms.ui.refresh()
                else
                    -- capture-phase close (Escape), a declined confirm, or a
                    -- declined conflict retry all land here as a cancel.
                    if opts.onCancel then opts.onCancel() end
                end
            end

            -- Capture settled on a bind. Stop listening, then either flag a
            -- conflict (retry prompt) or move the modal into its confirm phase.
            local function toConfirm(parsed)
                if settled then return end
                settled = true
                stopCapture()
                local bindStr = _bindDisplay(parsed)
                capturedParsed, capturedStr = parsed, bindStr

                local err = opts.validate and opts.validate(parsed, bindStr) or nil
                if err then
                    phase = "conflict"
                    ms.playSlot("alert")
                    ms.ui.modalUpdate({
                        title       = "Bind Conflict",
                        msg         = err .. "\n\nTry a different input?",
                        keys        = _bindTokens(parsed),
                        confirm     = "Try Again",
                        cancel      = "Cancel",
                        showConfirm = true,
                        showCancel  = true,
                    })
                    return
                end

                phase = "confirm"
                ms.playSlot("interact")
                ms.ui.modalUpdate({
                    title       = "Confirm Rebind",
                    msg         = "Set \"" .. label .. "\" to:",
                    keys        = _bindTokens(parsed),
                    confirm     = "Confirm",
                    cancel      = "Cancel",
                    showConfirm = true,
                    showCancel  = true,
                })
            end

            startCapture = function()
                phase     = "capture"
                settled   = false
                started   = false
                heldCodes = {}
                heldCount = 0
                comboKeys = {}
                comboSeen = {}
                comboMods = {}
                ms._inputOpen = true

                ms.ui.modal({
                    title   = "Rebind — " .. label,
                    msg     = captureMsg(),
                    confirm = "Set",
                    cancel  = "Cancel",
                }, onClosed)
                -- Hide both buttons during capture: a click would be swallowed by
                -- the eventtap and registered as a mouse bind, and Escape (below)
                -- is the intended cancel. They return in the confirm/conflict phase.
                -- keys = {} lights the empty placeholder cap, so the user can see
                -- where their keys will appear before pressing anything.
                ms.ui.modalUpdate({ showConfirm = false, showCancel = false, keys = {} })

                -- The eventtap only sees keyDown for real (non-modifier) keys —
                -- bare modifiers arrive as flagsChanged, which it doesn't watch —
                -- so by the time this runs there is always at least one key, and
                -- the empty state stays on the placeholder cap set above.
                local function livePreview()
                    if #comboKeys == 0 then return end
                    local preview
                    if #comboKeys > 1 then
                        preview = { type = "combo", mods = modList(), keys = comboKeys }
                    else
                        preview = { type = "key",   mods = modList(), key  = comboKeys[1] }
                    end
                    ms.ui.modalUpdate({ keys = _bindTokens(preview) })
                end

                local function finalizeKeys()
                    if settled or #comboKeys == 0 then return end
                    local mods = modList()
                    if #comboKeys == 1 then
                        toConfirm({ type = "key",   mods = mods, key  = comboKeys[1] })
                    else
                        toConfirm({ type = "combo", mods = mods, keys = comboKeys })
                    end
                end

                capture = hs.eventtap.new({
                    hs.eventtap.event.types.keyDown,
                    hs.eventtap.event.types.keyUp,
                    hs.eventtap.event.types.leftMouseDown,
                    hs.eventtap.event.types.rightMouseDown,
                    hs.eventtap.event.types.otherMouseDown,
                    hs.eventtap.event.types.scrollWheel,
                }, function(event)
                    local t = event:getType()

                    if t == hs.eventtap.event.types.keyDown then
                        local keyCode = event:getKeyCode()
                        local flags   = event:getFlags()
                        -- Bare Escape cancels; Escape with modifiers is a real key.
                        if keyCode == 53 and not (flags.cmd or flags.alt or flags.ctrl or flags.shift) then
                            settled = true
                            stopCapture()
                            ms.ui.modalClose(false)   -- resolves onClosed as cancel
                            return true
                        end
                        local keyStr = hs.keycodes.map[keyCode]
                        if not keyStr then return true end   -- unmappable key: ignore
                        if not heldCodes[keyCode] then
                            heldCodes[keyCode] = true
                            heldCount = heldCount + 1
                            if not comboSeen[keyStr] then
                                comboSeen[keyStr] = true
                                comboKeys[#comboKeys + 1] = keyStr
                            end
                        end
                        if flags.cmd   then comboMods.cmd   = true end
                        if flags.alt   then comboMods.alt   = true end
                        if flags.ctrl  then comboMods.ctrl  = true end
                        if flags.shift then comboMods.shift = true end
                        started = true
                        livePreview()
                        return true

                    elseif t == hs.eventtap.event.types.keyUp then
                        local keyCode = event:getKeyCode()
                        if heldCodes[keyCode] then
                            heldCodes[keyCode] = nil
                            heldCount = heldCount - 1
                            if heldCount <= 0 and started then finalizeKeys() end
                        end
                        return true

                    elseif t == hs.eventtap.event.types.scrollWheel then
                        if settled or started then return true end
                        local dy  = event:getProperty(hs.eventtap.event.properties.scrollWheelEventDeltaAxis1)
                        local dir = dy > 0 and "up" or "down"
                        toConfirm({ type = "scroll", direction = dir })
                        return true

                    else
                        if settled or started then return true end
                        local btn
                        if     t == hs.eventtap.event.types.leftMouseDown  then btn = 0
                        elseif t == hs.eventtap.event.types.rightMouseDown then btn = 1
                        else btn = event:getProperty(hs.eventtap.event.properties.mouseEventButtonNumber) end
                        toConfirm({ type = "mouse", button = btn })
                        return true
                    end
                end)

                if opts.gamepad and ms.gamepadEnabled then
                    if not ms._gamepadTask then ms.gamepadStart() end
                    ms._gamepadCallbacks._rebind = function(btn)
                        if settled or started then return end
                        toConfirm({ type = "gamepad", button = btn })
                    end
                end

                capture:start()
                cancelTimer = hs.timer.doAfter(15, function()
                    if settled then return end
                    settled = true
                    stopCapture()
                    ms.ui.modalClose(false)   -- timeout resolves as cancel
                end)
            end

            startCapture()
        end

        ms.ui._actions = {
            ready = function() ms.ui.refresh() end,

            setMacros = function(data)
                ms.setMacros(tonumber(data.value) == 1 and 1 or 0)
                ms.ui.refresh()
            end,

            playSlot = function(data) if data.slot then ms.playSlot(data.slot) end end,

            -- Preview by file name rather than by slot: the sound library
            -- lists files, and a macro sound has no slot to play through.
            previewSound = function(data)
                if data and type(data.name) == "string" and data.name ~= "" then
                    ms.sound(data.name)
                end
            end,

            alert = function(data)
                if data.msg then
                    ms.alert(tostring(data.msg), tonumber(data.duration) or 3, data.noSound == true)
                end
            end,

            close = function() ms.ui.hide() end,

            reloadMacros = function()
                -- Phase 1: Validate source (no destructive ops — bind system untouched)
                local macrosPath = os.getenv("HOME") .. "/.hammerspoon/ms_macros.lua"
                local af = io.open(macrosPath, "r")
                if not af then
                    ms.alert("Reload failed:\nCannot open ms_macros.lua.", 6)
                    return false
                end
                local rawSrc = af:read("*all"); af:close()
                local auditErrs = ms.auditMacros(rawSrc)
                if #auditErrs > 0 then
                    ms.alert("Reload blocked — audit failed.", 6)
                    return false
                end
                local chunk, loadErr = load(
                    rawSrc,
                    "@ms_macros.lua",
                    "bt",
                    ms._macroSandbox
                )
                if not chunk then
                    ms.alert("Reload failed:\n" .. tostring(loadErr), 6)
                    return false
                end

                -- Phase 2: Teardown + execute (source validated — safe to destroy)
                ms.bind.teardown()
                ms.registry       = { _defs = {}, _defList = {} }
                ms.bind._wires    = {}
                ms.bind._autoCount = 0
                ms.macroMeta       = nil
                ms._userSettingDefs  = {}
                ms._userSettingIndex = {}
                ms._userSettingVals  = {}

                local ok, runErr = xpcall(chunk, debug.traceback)
                if not ok then
                    local tb = tostring(runErr)
                    print("═══ ms_macros.lua reload error ═══\n" .. tb)
                    if ms.dev and ms.dev.log then
                        ms.dev.log({ type = "error", event = "reload_error", msg = tb })
                    end
                    ms.alert("Reload failed — see console", 6)
                    -- Restore system binds so the user isn't stuck
                    pcall(function()
                        ms.bind._registerSystemBinds()
                        ms.bind.rebindSystem()
                    end)
                    return false
                end
                if not next(ms.registry._defs) then
                    ms.alert("Reload failed:\nNo ms.bind.define calls found.", 6)
                    pcall(function()
                        ms.bind._registerSystemBinds()
                        ms.bind.rebindSystem()
                    end)
                    return false
                end
                for _, id in ipairs(ms.registry._defList) do
                    local def = ms.registry._defs[id]
                    if def and not (def.default and def.default.type) and ms.binds[id] == nil then
                        ms.binds[id] = def.enabled
                    end
                end
                ms._systemActions = {}
                if ms._userSettingIndex["showTamperWarning"] then
                    ms._systemActions["showTamperWarning"] = function()
                        ms.showGuardian()
                    end
                    ms._systemActions["showIntegrityError"] = function()
                        ms.showGuardian()
                    end
                end
                ms.loadSettings()
                if not ms.registry._defs["__panicButton"] then ms.bind._registerSystemBinds() end
                ms.bind.rebind()
                ms.socdApply()
                if not ms._quickReloading then
                    ms.playSlot("update")
                    ms.alert("Macros reloaded.", 4, true)
                end
                -- Roblox unfocus/refocus (macro-specific)
                -- Skip during quick reload — UI operations will steal focus,
                -- so the refocus is handled after they complete.
                if not ms._quickReloading then
                    hs.timer.doAfter(0.15, function()
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
                end
                return true
            end,

            reloadSettings = function()
                ms.loadSettings()
                ms.bind.rebind()
                ms.socdApply()
                ms.playSlot("update")
                ms.alert("Settings reloaded.", 4, true)
                ms.ui.refresh()
            end,

            reloadTheme = function()
                ms.loadTheme()
                pcall(function() ms.alert:recolor() end)
                pcall(function() ms.dev:recolor() end)
                ms.playSlot("update")
                ms.alert("Theme reloaded.", 4, true, { priority = "low" })
                ms.ui.hide()
                hs.timer.doAfter(0.15, function() ms.ui.show() end)
            end,

            reloadUI = function()
                ms.reloadUI()
            end,

            reloadAll = function() hs.reload() end,

            shutdown = function() ms.shutdown() end,

            quickReload = function()
                ms.reload()
            end,

            setQROption = function(data)
                if data.key and ms._qrOptions then
                    ms._qrOptions[data.key] = (data.value == true)
                    ms.saveSettings()
                    ms.playSlot("interact")
                end
            end,

            setCustomTheme = function(data)
                ms._customThemeDisabled = not (data.value and true or false)
                if ms._customThemeDisabled then
                    -- Revert to defaults
                    for k, v in pairs(ms._themeDefaults) do ms._theme[k] = v end
                    -- Turning theming off un-indexes the whole a_* series, so
                    -- every slot has to be walked back to its default in the
                    -- same breath — one left behind points at a sample that no
                    -- longer resolves.
                    for sid, def in pairs(ms.soundSlotDefaults()) do
                        ms.soundAssign[sid] = def
                    end
                    -- Save + discover + recolor
                    ms.saveSettings()
                    ms._soundsDirty = true
                    ms._discoverSounds()
                else
                    -- Reload custom theme
                    ms.loadTheme()
                    -- Re-discover sounds FIRST so preset restore can resolve a_* variants
                    ms._soundsDirty = true
                    ms._discoverSounds()
                    -- Re-apply saved sound preset (restores user's preset after disable/enable cycle)
                    -- The presets are rebuilt from what is on disk now that
                    -- the a_* series is indexed again, so restoring one is
                    -- just replaying its assignments — the same table the
                    -- Sounds tab would have sent.
                    local savedPreset = ms._soundPreset
                    if savedPreset and savedPreset ~= "custom" then
                        local assigns
                        if savedPreset == "default" then
                            assigns = ms.soundSlotDefaults()
                        else
                            local num = tonumber(savedPreset)
                            for _, p in ipairs(ms.buildSoundPresets()) do
                                if p.num == num then assigns = p.assigns; break end
                            end
                        end
                        for sid, name in pairs(assigns or {}) do
                            ms.soundAssign[sid] = name
                        end
                    end
                    -- Save after preset restore
                    ms.saveSettings()
                end
                -- Recolor existing toasts to match new theme
                pcall(function() ms.alert:recolor() end)
                pcall(function() ms.dev:recolor() end)
                local snd = ms.sounds[data.value and 'a_Update' or 'd_Update']; if snd then ms.sound(snd) end
                ms.ui.refresh()
                -- Delayed refresh to ensure shell preset detection picks up new soundAssign
                hs.timer.doAfter(0.2, function() ms.ui.refresh() end)
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

            setTestingSource = function(data)
                local src = data.value
                if src == "release" or src == "artifact" then
                    ms._testingSource = src
                    ms.saveSettings()
                    ms.playSlot("update")
                end
                ms.ui.refresh()
            end,

            setCacheCleanerEnabled = function(data)
                local enabled = data.value and true or false
                ms._cacheCleanerEnabled = enabled
                local home = os.getenv("HOME")
                local plistSrc = home .. "/.hammerspoon/bin/com.mudscript.cache-cleaner.plist"
                local scriptSrc = home .. "/.hammerspoon/bin/clean_roblox_cache.sh"
                local plistDst = home .. "/Library/LaunchAgents/com.mudscript.cache-cleaner.plist"
                if enabled then
                    -- Install the launch agent
                    if hs.fs.attributes(plistSrc) and hs.fs.attributes(scriptSrc) then
                        local f = io.open(plistSrc, "r")
                        if f then
                            local content = f:read("*all"); f:close()
                            content = content:gsub("%%AGENT_PATH%%", scriptSrc)
                            local g = io.open(plistDst, "w")
                            if g then g:write(content); g:close() end
                            os.execute("chmod 755 '" .. scriptSrc .. "'")
                            os.execute("launchctl unload '" .. plistDst .. "' 2>/dev/null; launchctl load '" .. plistDst .. "'")
                        end
                    end
                else
                    -- Uninstall the launch agent
                    os.execute("launchctl unload '" .. plistDst .. "' 2>/dev/null")
                    os.remove(plistDst)
                end
                ms.saveSettings()
                ms.ui.refresh()
            end,

            setOctaneMode = function(data)
                local enabled = data.value and true or false
                ms._octaneMode = enabled
                ms.saveSettings()
                -- Apply/remove octane state at runtime
                if ms.octane then
                    if enabled then ms.octane._apply() else ms.octane._remove() end
                end
                ms.ui.refresh()
            end,

            setOctaneMuteSounds = function(data)
                ms._octaneMuteSounds = data.value and true or false
                ms.saveSettings()
                ms.ui.refresh()
            end,

            setMacroLabEnabled = function(data)
                local enabled = data.value and true or false
                ms._macroLabEnabled = enabled
                if ms._userSettingVals then ms._userSettingVals["macroLabEnabled"] = enabled end
                ms.saveSettings()
                -- (Legacy fallback removed 2026-07-13: the shell is the only
                -- settings UI now; disabling Macro Lab no longer swaps windows.)
                ms.ui.refresh()
            end,

            setGithubToken = function(data)
                ms._githubToken = data.value or ""
                -- Store in a restricted file (not settings.json, not keychain)
                local tokenPath = os.getenv("HOME") .. "/.hammerspoon/data/.ms_github_token"
                if ms._githubToken ~= "" then
                    local f = io.open(tokenPath, "w")
                    if f then f:write(ms._githubToken); f:close() end
                    os.execute("chmod 600 '" .. tokenPath .. "'")
                else
                    os.remove(tokenPath)
                end
                ms.playSlot("update")
                ms.ui.refresh()
            end,

            setMacroEnabled = function(data)
                if not data.id then return end
                local def = ms.registry._defs[data.id]
                if def and def.system then return end  -- system binds cannot be disabled
                local want = (data.value == true)
                -- A macro with no effective bind has no trigger, so enabling it
                -- would do nothing. Refuse it, keep the state off, and tell the
                -- user to set a bind first. Disabling is always allowed.
                if want and ms.effectiveBind(data.id) == nil then
                    ms.binds[data.id] = false
                    ms.saveSettings()
                    ms.bind.rebind()
                    hs.timer.doAfter(0.1, function()
                        ms.alert((def and def.label or data.id)
                            .. " has no bind — set one before enabling.", 2, true)
                        ms.ui.refresh()
                    end)
                    return
                end
                ms.binds[data.id] = want
                ms.saveSettings()
                ms.bind.rebind()
                ms.ui.refresh()
            end,

            setTrackpadMode = function(data)
                ms.trackpadMode = (data.value == true)
                ms.saveSettings()
                ms.bind.rebind()
                ms.ui.refresh()
            end,

            setSocdEnabled = function(data)
                ms.socdEnabled = (data.value == true)
                ms.saveSettings()
                ms.socdApply()
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

            setSoundPreset = function(data)
                if not data.assigns then return end
                ms.soundAssign = ms.soundAssign or {}
                -- Clear all loading slots first so missing slots get reset
                local loadSlots = { "themeLoaded", "load", "launch" }
                for _, sid in ipairs(loadSlots) do
                    ms.soundAssign[sid] = nil
                end
                -- Apply preset assignments
                for slotId, soundName in pairs(data.assigns) do
                    ms.soundAssign[slotId] = soundName
                end
                -- Persist preset selection
                ms._soundPreset = data.preset or "default"
                ms.saveSettings()
                ms.playSlot("update")
                ms.ui.refresh()
            end,

            clearSoundPreset = function(data)
                if not data.slots then return end
                ms.soundAssign = ms.soundAssign or {}
                for _, slotId in ipairs(data.slots) do
                    ms.soundAssign[slotId] = nil
                end
                -- Persist custom selection
                ms._soundPreset = "custom"
                ms.saveSettings()
                ms.playSlot("update")
                ms.ui.refresh()
            end,

            switchProfile = function(data) if data.name then ms.switchProfile(data.name) end end,

            deleteProfile = function(data)
                if not data.name then return end
                local targetName = ms.sanitizeName(data.name)
                local activeName = ms.macroMeta and ms.sanitizeName(ms.macroMeta.name or "") or ""
                if targetName == "" or targetName == activeName then return end
                local dir = profilesPath .. targetName
                if not hs.fs.attributes(dir) then return end
                os.execute("rm -rf " .. sq(dir))
                ms._profilesDirty = true
                ms.ui.markDirty()
                ms.playSlot("reset")
                hs.timer.doAfter(0.05, function()
                    ms.alert("Profile \"" .. data.name .. "\" deleted.", 2, true)
                    ms.ui.refresh()
                end)
            end,

            clearProfiles = function()
                local activeName = ms.macroMeta and ms.sanitizeName(ms.macroMeta.name or "") or ""
                if activeName == "" then return end
                if not hs.fs.attributes(profilesPath) then return end
                local deleted = 0
                for entry in hs.fs.dir(profilesPath) do
                    if entry ~= "." and entry ~= ".." then
                        local safe = ms.sanitizeName(entry)
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

            importProfile     = function() ms.importProfile() end,
            importProfilePkg  = function() ms.importProfilePkg() end,
            exportProfilePkg  = function() ms.exportProfilePkg() end,
            createNewProfile  = function() ms.createNewProfile() end,
            saveCurrentProfile = function() ms.saveCurrentProfile() end,

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
                -- Ensure subdirectories exist
                hs.execute("mkdir -p " .. sq(SoundActiveDir))
                hs.execute("mkdir -p " .. sq(SoundMacroDir))
                if not hs.fs.attributes(slibDir) then
                    ms.ui.show()
                    ms.alert("Could not create sounds folder:\n" .. SoundLib, 4)
                    return
                end
                local added, failed = {}, {}
                for _, srcPath in ipairs(paths) do
                    local filename   = srcPath:match("([^/]+)$")
                    local importName = filename and (filename:match("^(.+)%.[^%.]+$") or filename)
                    if not filename or not importName then
                        table.insert(failed, srcPath)
                    else
                        local dst    = SoundActiveDir .. filename
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
                        ms.alert(
                            #added .. " added, " .. #failed .. " failed.",
                            3,
                            true
                        )
                    else
                        ms.alert("Import failed.\nGrant Hammerspoon Full Disk Access if importing from outside ~/.hammerspoon.", 5)
                    end
                    ms.ui.refresh()
                end)
            end,

            importSoundForSlot = function(data)
                if not data.slot then return end
                local slot = data.slot
                ms.playSlot("alert")
                local slibDir = SoundLib:match("^(.-)[/\\]*$") or SoundLib
                local result = hs.dialog.chooseFileOrFolder(
                    "Select a sound file for \"" .. (data.label or slot) .. "\"",
                    hs.fs.attributes(slibDir) and SoundLib or os.getenv("HOME"),
                    true, false, false,
                    ms.soundExtensions
                )
                local selectedPath
                for _, v in pairs(result or {}) do
                    if type(v) == "string" then selectedPath = v; break end
                end
                if not selectedPath then ms.ui.show(); return end
                if not hs.fs.attributes(slibDir) then
                    hs.execute("mkdir -p '" .. SoundLib .. "'")
                end
                local filename = selectedPath:match("([^/]+)$")
                if not filename then
                    ms.ui.show(); ms.alert("Could not read filename.", 3); return
                end

                -- The picker is filtered, but it is a file dialog: a typed
                -- path or a dragged alias can still get something else in
                -- here, and the library has to hold sounds only.
                if not ms.isSoundFile(filename) then
                    ms.ui.show()
                    ms.alert("Not a sound file.\nSupported: "
                        .. table.concat(ms.soundExtensions, ", ") .. ".", 4)
                    return
                end

                -- An import never lands on a name the theme system owns, and
                -- never overwrites a file already in the library. What it is
                -- called on disk follows the name it gets, so the two cannot
                -- drift apart later.
                local ext        = filename:match("(%.[^%.]+)$") or ""
                local stem       = filename:match("^(.+)%.[^%.]+$") or filename
                local importName = ms.safeSoundName(stem, "a_")
                filename         = importName .. ext

                local dst    = SoundActiveDir .. filename
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

            -- ── Sound removal ─────────────────────────────────────────────
            -- Deletes the file behind a sound and every reference to it.
            -- Defaults are never removable: they are the floor every slot
            -- falls back to, so deleting one would leave a slot pointing at
            -- nothing. The UI greys the control, and this refuses again —
            -- the check belongs on the side that touches the disk.
            removeSound = function(data)
                local name = data and data.name
                if type(name) ~= "string" or name == "" then return end

                ms._discoverSounds()
                local path = (ms.sounds or {})[name] or (ms.macroSounds or {})[name]
                if not path then
                    ms.alert("No such sound: " .. name, 3)
                    return
                end
                if path:find("/sounds/defaults/") or name:sub(1, 2) == "d_" then
                    ms.alert("Default sounds cannot be removed.", 3)
                    return
                end

                local ok = os.remove(path)
                if not ok then
                    local _, st = hs.execute("/bin/rm -f " .. sq(path))
                    ok = (st == true) or (hs.fs.attributes(path) == nil)
                end
                if not ok then
                    ms.alert("Could not remove \"" .. name .. "\".", 4)
                    return
                end

                -- Drop every slot that pointed at it so nothing resolves to a
                -- file that is gone; a cleared slot falls back to its default.
                ms.soundAssign = ms.soundAssign or {}
                for slot, assigned in pairs(ms.soundAssign) do
                    if assigned == name then ms.soundAssign[slot] = nil end
                end
                if ms.importedSounds then ms.importedSounds[name] = nil end

                ms.saveSettings()
                ms._soundsDirty = true
                ms._discoverSounds()
                ms.playSlot("reset")
                hs.timer.doAfter(0.15, function()
                    ms.alert("\"" .. name .. "\" removed.", 3, true)
                    ms.ui.refresh()
                end)
            end,

            -- Declare what an imported sound is. The library files sounds by
            -- name prefix — ms._autoSortSounds moves d_/a_/m_ into defaults/,
            -- active/ and macro/ — so an import that kept its original name
            -- matches no prefix, is moved nowhere, and is stuck as whatever
            -- the importer happened to drop it in. Renaming it to the
            -- destination's prefix is how a sound says what it is, and is the
            -- same normalisation the package importer applies on the way in.
            setSoundKind = function(data)
                local name = data and data.name
                local kind = data and data.kind
                if type(name) ~= "string" or name == "" then return end
                if kind ~= "active" and kind ~= "macro" then return end

                ms._discoverSounds()
                local path = (ms.sounds or {})[name] or (ms.macroSounds or {})[name]
                if not path then
                    ms.alert("No such sound: " .. name, 3)
                    return
                end
                if path:find("/sounds/defaults/") or name:sub(1, 2) == "d_" then
                    ms.alert("Default sounds cannot be re-typed.", 3)
                    return
                end

                local dstDir = (kind == "macro") and SoundMacroDir or SoundActiveDir
                local prefix = (kind == "macro") and "m_" or "a_"
                local file   = path:match("([^/]+)$") or ""
                local stem   = file:match("^(.+)%.[^%.]+$") or file
                local ext    = file:match("(%.[^%.]+)$") or ""
                -- Strip the prefix it carries now, so re-typing twice cannot
                -- stack them into m_a_Name.
                stem = stem:gsub("^[dam]_", "")

                local newName = prefix .. stem
                local dst     = dstDir .. newName .. ext

                -- Already sitting where this kind belongs (an import whose
                -- filename happened to carry the right prefix). Nothing to
                -- move, but it still has to stop being "imported" — that is
                -- the whole point of the click.
                if dst == path then
                    if ms.importedSounds then ms.importedSounds[name] = nil end
                    ms.saveSettings()
                    ms._soundsDirty = true
                    ms._discoverSounds()
                    ms.playSlot("update")
                    hs.timer.doAfter(0.15, function() ms.ui.refresh() end)
                    return
                end
                if hs.fs.attributes(dst) then
                    ms.alert("A sound named \"" .. newName .. "\" already exists.", 4)
                    return
                end
                if not hs.fs.attributes(dstDir) then
                    hs.execute("mkdir -p " .. sq(dstDir))
                end

                local ok = os.rename(path, dst)
                if not ok then
                    local _, st = hs.execute("/bin/mv " .. sq(path) .. " " .. sq(dst))
                    ok = (st == true) or (hs.fs.attributes(dst) ~= nil)
                end
                if not ok then
                    ms.alert("Could not move \"" .. name .. "\".", 4)
                    return
                end

                -- Slots point at names, so they follow the rename or they
                -- dangle. A slot pointing at a macro sound still resolves,
                -- since playSlot falls through ms.sounds to ms.macroSounds.
                ms.soundAssign = ms.soundAssign or {}
                for slot, assigned in pairs(ms.soundAssign) do
                    if assigned == name then ms.soundAssign[slot] = newName end
                end

                -- Drop the imported flag rather than re-keying it. "Imported"
                -- is the staging state for a sound that has not been given a
                -- type yet; once it has one it belongs in that type's group,
                -- and the Imported group empties out and disappears.
                if ms.importedSounds then ms.importedSounds[name] = nil end

                ms.saveSettings()
                ms._soundsDirty = true
                ms._discoverSounds()
                ms.playSlot("update")
                hs.timer.doAfter(0.15, function()
                    ms.alert("\"" .. newName .. "\" is now a "
                        .. kind .. " sound.", 3, true)
                    ms.ui.refresh()
                end)
            end,

            setBundleSoundsWithTheme = function(data)
                ms.bundleSoundsWithTheme = (data and data.value) == true
                ms.saveSettings()
                ms.playSlot("update")
                ms.ui.refresh()
            end,

            openWindowMonitor = function() if ms.dev and ms.dev.window then ms.dev.window.toggle() end end,

            openConsole = function() hs.openConsole() end,

            editMacros = function()
                os.execute("open " .. os.getenv("HOME") .. "/.hammerspoon/ms_macros.lua")
            end,

            editTheme = function()
                os.execute("open '" .. os.getenv("HOME") .. "/.hammerspoon/data/ms_theme.json'")
            end,

            -- ── Theme editor ──────────────────────────────────────────────
            -- One key at a time; the panel previews locally and only commits
            -- on change, so this is not on the drag path of a colour picker.
            setThemeKey = function(data)
                if not data.key or not ms.saveTheme then return end
                local value = data.value
                if type(value) ~= "string" and type(value) ~= "number" then return end
                ms.saveTheme({ [data.key] = value })
                ms.playSlot("update")
                ms.ui.refresh()
            end,

            resetTheme = function()
                if not ms.resetTheme then return end
                ms.resetTheme()
                ms.playSlot("reset")
                ms.alert("Theme reset to defaults.\nYour old file was kept as ms_theme.json.bak", 4, true)
                ms.ui.refresh()
            end,

            -- ── Packages ──────────────────────────────────────────────────
            -- Sound is a theme aspect, so a theme package may carry audio and
            -- the slot map with it (see bundleSoundsWithTheme). The sound type
            -- remains for sharing a set on its own; a sound pack still cannot
            -- carry a theme, because that direction was never the ambiguity.
            exportPackage = function(data)
                local kind = data and data.type
                if not (ms.package and ms.package.collect and kind) then return end

                local files = ms.package.collect(kind)
                if kind == "sound" then
                    local assignPath = ms.package.exportSoundAssign()
                    if assignPath then files["sound_assign.json"] = assignPath end
                end
                if next(files) == nil then
                    ms.alert("Nothing to export as a " .. kind .. " package.", 4)
                    return
                end

                ms.playSlot("alert")
                local chosen = hs.dialog.chooseFileOrFolder(
                    "Choose where to save the " .. kind .. " package",
                    os.getenv("HOME") .. "/Documents", false, true, false
                )
                local dir
                for _, v in pairs(chosen or {}) do
                    if type(v) == "string" then dir = v; break end
                end
                ms.ui.show()
                if not dir then return end

                local meta = ms.macroMeta or {}
                local base = ms.sanitizeName(meta.name or "mudscript")
                if base == "" then base = "mudscript" end
                local out = dir:gsub("/$", "") .. "/" .. base .. "-" .. kind .. ".mspkg"

                local manifest, err = ms.package.pack({
                    type    = kind,
                    name    = base .. " " .. kind,
                    author  = meta.author,
                    website = meta.website,
                    files   = files,
                    out     = out,
                })
                hs.timer.doAfter(0.15, function()
                    if manifest then
                        ms.playSlot("update")
                        -- Name the build OS on the way out. The manifest has
                        -- carried it since packages were typed, and import
                        -- warns on a mismatch, but the person sharing the file
                        -- is the one who needs to know who it will work for.
                        ms.alert("Exported " .. out:match("([^/]+)$") ..
                            "\nBuilt on " .. ms.package.osLabel(manifest) .. ".", 3, true)
                    else
                        ms.alert("Export failed:\n" .. tostring(err), 5)
                    end
                end)
            end,

            importPackage = function()
                if not (ms.package and ms.package.install) then return end
                ms.playSlot("alert")
                local chosen = hs.dialog.chooseFileOrFolder(
                    "Select a .mspkg package to import",
                    os.getenv("HOME") .. "/Documents", true, false, false
                )
                local path
                for _, v in pairs(chosen or {}) do
                    if type(v) == "string" then path = v; break end
                end
                ms.ui.show()
                if not path then return end

                local result, err = ms.package.install(path)
                -- An unsigned package is the normal case until the validated
                -- library lands; confirm rather than refuse. Plugins are the
                -- exception — they run as code, so install refuses them
                -- outright and there is no prompt to offer.
                local _peek = ms.package.inspect(path)
                local _isPlugin = type(_peek) == "table" and _peek.type == "plugin"
                if not result and not _isPlugin and tostring(err):find("validated library") then
                    local answer = hs.dialog.blockAlert(
                        "This package is not in the validated library.",
                        "Import " .. path:match("([^/]+)$") .. " anyway?",
                        "Import", "Cancel"
                    )
                    if answer ~= "Import" then return end
                    result, err = ms.package.install(path, { force = true })
                end

                hs.timer.doAfter(0.15, function()
                    if not result then
                        ms.alert("Import failed:\n" .. tostring(err), 5)
                        return
                    end
                    if ms._soundsDirty then ms._discoverSounds() end
                    if ms.loadTheme then ms.loadTheme() end
                    ms.playSlot("update")
                    ms.alert(
                        (result.manifest.name or "Package") .. " imported (" ..
                        #result.installed .. " files).", 4, true
                    )
                    ms.ui.refresh()
                end)
            end,

            -- Plugins --
            -- The flag decides, ms.plugins.apply() enforces: it loads what is
            -- newly enabled and tears down what is newly off, so the switch
            -- takes effect on the keystroke after you flip it rather than at
            -- the next reload.
            setPluginEnabled = function(data)
                if not (data and data.dir and ms.package and ms.package.setPluginEnabled) then return end
                ms.package.setPluginEnabled(data.dir, data.value == true)
                if ms.plugins and ms.plugins.apply then
                    local ok, err = pcall(ms.plugins.apply)
                    if not ok then print("[MsUI] plugin apply failed: " .. tostring(err)) end
                end
                ms.ui.markDirty()
                ms.ui.refresh()
            end,

            removePlugin = function(data)
                if not (data and data.dir and ms.package and ms.package.removePlugin) then return end
                local dir = data.dir

                ms.playSlot("alert")
                local answer = hs.dialog.blockAlert(
                    "Remove " .. (data.label or dir) .. "?",
                    "The plugin's files are deleted from Spoons/. This cannot be undone.",
                    "Remove", "Cancel"
                )
                if answer ~= "Remove" then return end

                -- Teardown first, delete second. The undo list is only good
                -- while the plugin is still loaded, and running it after the
                -- files are gone would mean stopping a plugin that can no
                -- longer be asked to stop itself.
                if ms.plugins and ms.plugins.unload then
                    pcall(ms.plugins.unload, dir)
                end

                local ok, err = ms.package.removePlugin(dir)
                if not ok then
                    ms.alert("Could not remove plugin:\n" .. tostring(err), 5)
                    return
                end

                ms.ui.markDirty()
                ms.ui.refresh()
                ms.alert((data.label or dir) .. " removed.", 4, true)
            end,

            openPluginsFolder = function()
                local dir = os.getenv("HOME") .. "/.hammerspoon/Spoons"
                hs.fs.mkdir(dir)
                os.execute("open '" .. dir .. "'")
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
                ms.alert("Trusted manifest deleted.\nIntegrity protection is now OFF until you re-trust.", 5)
                ms.ui.refresh()
            end,

            checkIntegrity = function()
                local status, cur, trusted = ms.integrity.check()
                if status == "trusted" then
                    ms.alert("\xe2\x9c\x93 ms_core.lua matches trusted hash.\n" .. (cur and cur:sub(1, 16) or "?") .. "\xe2\x80\xa6", 5, true)
                    ms.ui.refresh()
                elseif status == "mismatch" then
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

            startRebind = function(data)
                if not data.id then return end

                if data.systemBind then
                    local sysDef = ms.systemBinds._defs[data.id]
                    if not sysDef then return end
                    local label = sysDef.label
                    _rebindModal({
                        label    = label,
                        current  = _bindDisplay(ms.systemBinds.effective(data.id)),
                        gamepad  = true,
                        onCancel = function() _restoreAfterCapture(); ms.ui.refresh() end,
                        apply    = function(parsed)
                            ms.systemBinds._config[data.id] = parsed
                            ms.saveSettings()
                            ms.playSlot("update")
                            ms.systemBinds.rebind()
                        end,
                    })
                    return
                end

                local def = ms.registry._defs[data.id]
                if not def then return end
                local label = def.label or data.id
                _rebindModal({
                    label    = label,
                    current  = _bindDisplay(ms.effectiveBind(data.id)),
                    gamepad  = true,
                    onCancel = function() _restoreAfterCapture(); ms.ui.refresh() end,
                    validate = function(parsed, bindStr)
                        local conflictId = ms.bind.siblingConflict(data.id, parsed)
                        if not conflictId then return nil end
                        local cLabel = (ms.registry._defs[conflictId] and ms.registry._defs[conflictId].label) or conflictId
                        return "\"" .. bindStr .. "\" is already used by \"" .. cLabel .. "\"."
                    end,
                    apply    = function(parsed)
                        ms.bindConfig[data.id] = parsed
                        ms.saveSettings()
                        ms.playSlot("update")
                        ms.bind.rebind()
                    end,
                })
            end,

            resetSetting = function(data)
                local key = data.key
                local def = ms.macroDefaults or {}
                if key == "trackpadMode" then
                    ms.trackpadMode = (def.trackpadMode == true)
                    ms.saveSettings(); ms.bind.rebind()
                elseif key == "socdEnabled" then
                    ms.socdEnabled = (def.socdEnabled == true)
                    ms.saveSettings(); ms.socdApply()
                elseif key == "socdMode" then
                    ms.socdMode = def.socdMode or "lastWins"
                    ms.saveSettings()
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

            userSettingChange = function(data)
                if not data.key then return end
                ms.settings.set(data.key, data.value)
                ms.playSlot("update")
                ms.ui.refresh()
            end,

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

            resetUserSetting = function(data)
                if not data.key then return end
                local def = ms._userSettingIndex[data.key]
                if not def or def.default == nil then return end
                ms.settings.set(data.key, def.default)
                ms.playSlot("reset")
                ms.ui.refresh()
            end,

            -- Add a setting authored in the Tools panel's Setting Builder.
            -- Delegates all validation and persistence to ms.addAuthoredSetting
            -- (ms_settings.lua); this only surfaces the outcome to the user.
            addUserSetting = function(data)
                local ok, err = ms.addAuthoredSetting(data and data.def)
                if ok then
                    ms.playSlot("update")
                    ms.ui.refresh()
                    ms.alert("Setting added to your pack.", 3)
                else
                    ms.playSlot("alert")
                    ms.alert("Couldn't add setting: " .. (err or "invalid"), 4)
                end
            end,

            -- Remove an authored setting (a "tool"). Reached from the macro
            -- builder's tool detail; delegates validation to
            -- ms.removeAuthoredSetting, which refuses anything but an authored
            -- key. Only refreshes on success so a stray key is a quiet no-op
            -- notice, not a panel churn.
            removeUserSetting = function(data)
                local ok, err = ms.removeAuthoredSetting(data and data.key)
                if ok then
                    ms.playSlot("reset")
                    ms.ui.refresh()
                    ms.alert("Tool removed from your pack.", 3)
                else
                    ms.playSlot("alert")
                    ms.alert("Couldn't remove tool: " .. (err or "invalid"), 4)
                end
            end,

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

            resetBind = function(data)
                if not data.id then return end

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

                local def = ms.registry._defs[data.id]
                if not def then return end
                -- Clearing the override drops back to the bind defined in
                -- ms_macros.lua / ms_macros_visual.lua (def.default). If the
                -- macro was never given a default bind, there is nothing to
                -- fall back to — it is now unbound, and an unbound macro has no
                -- trigger to fire it, so it must go off rather than sit
                -- "enabled" with no way to activate.
                ms.bindConfig[data.id] = nil
                local restored = ms.effectiveBind(data.id) ~= nil
                if not restored then ms.binds[data.id] = false end
                ms.saveSettings()
                ms.bind.rebind()
                ms.playSlot("reset")
                hs.timer.doAfter(0.1, function()
                    ms.alert((def.label or data.id) .. (restored
                        and " reset to default."
                        or " has no default bind — disabled."), 2, true)
                    ms.ui.refresh()
                end)
            end,

            setModifier = function(data)
                -- Handled by startModRebind — this entry is a no-op.
            end,

            clearModifier = function(data)
                if not data.id then return end
                local def = ms.registry._defs and ms.registry._defs[data.id]
                if not def or not def.default then return end
                ms.bindConfig[data.id] = { type = def.default.type, mods = {} }
                ms.saveSettings()
                ms.bind.rebind()
                ms.playSlot("reset")
                ms.ui.refresh()
            end,

            startModRebind = function(data)
                if not data.id then return end
                local def = ms.registry._defs[data.id]
                if not def or not def.default then return end
                local label = def.label or data.id
                -- Get current modifier from bindConfig override or definition default
                local curCfg  = ms.bindConfig[data.id] or def.default
                local curMods = curCfg and curCfg.mods or {}
                local cur     = curMods[1]

                ms.alert("Modifier for \"" .. label .. "\""
                    .. "\nCurrent: " .. (cur or "unset")
                    .. "\nPress a key  —  Backspace to clear  —  Escape to cancel.", 15, false, { id = "_rebind" })

                ms._inputOpen = true
                ms.ui._open   = false

                local capture, cancelTimer
                local prevFlags = {}

                local function finish(newKey, cancelled)
                    ms._inputOpen = false
                    if not cancelled then
                        -- Update bindConfig: preserve parent type, swap modifier
                        if newKey then
                            ms.bindConfig[data.id] = { type = def.default.type, mods = { newKey } }
                        else
                            ms.bindConfig[data.id] = { type = def.default.type, mods = {} }
                        end
                        ms.saveSettings()
                        ms.bind.rebind()
                        ms.playSlot(newKey and "update" or "reset")
                    end
                    -- Shell stayed visible through the modifier capture, so only
                    -- bring it forward — a full ms.ui.show() would replay the
                    -- fade-in on an already-visible window.
                    ms.ui.ensureVisible()
                    hs.timer.doAfter(0.1, function()
                        if not cancelled then
                            if newKey then
                                ms.alert("Modifier set to: " .. newKey, 3, true, { id = "_rebind" })
                            else
                                ms.alert("Modifier cleared.", 3, true, { id = "_rebind" })
                            end
                        else
                            ms.alert("Modifier rebind cancelled.", 2, false, { id = "_rebind" })
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

            setSoundPreset = function(data)
                if not data.assigns or type(data.assigns) ~= "table" then return end
                ms.soundAssign = ms.soundAssign or {}
                for slotId, soundName in pairs(data.assigns) do
                    ms.soundAssign[slotId] = soundName
                end
                ms._soundPreset = data.preset or "default"
                ms.saveSettings()
                ms.playSlot("interact")
                ms.ui.refresh()
            end,

            clearSoundPreset = function(data)
                if not data.slots or type(data.slots) ~= "table" then return end
                ms.soundAssign = ms.soundAssign or {}
                for _, slotId in ipairs(data.slots) do
                    ms.soundAssign[slotId] = nil
                end
                ms._soundPreset = "custom"
                ms.saveSettings()
                ms.playSlot("interact")
                ms.ui.refresh()
            end,
        }

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
        -- Shell integration: route bus messages to the same action handlers
        -- Topic shape: ui:<panel>:<action> (emitted by ms.shell's msShell channel)
        if ms.bus then
            local function _routeAction(topic, body)
                if not body or type(body) ~= "table" then return end
                local action = body.action
                if not action then return end
                local handler = ms.ui._actions[action]
                if handler then
                    local ok, err = pcall(handler, body)
                    if not ok then print("[MsUI] handler error: " .. tostring(err)) end
                end
            end

            ms.bus.on("ui:settings:*", _routeAction)
            -- The macros panel owns rebinding, so it needs the same action set
            -- (startRebind, resetBind, startModRebind, clearModifier,
            -- setMacroEnabled). Compiler-owned actions on this channel
            -- (listMacros, saveMacro, …) are absent from ms.ui._actions and
            -- fall through untouched to their own handlers in ms_core.
            ms.bus.on("ui:macros:*", _routeAction)
            ms.bus.on("ui:tools:*",  _routeAction)
            -- The plugins panel sends on its own channel so its actions read
            -- as plugin actions in the log, but they resolve in the same set.
            ms.bus.on("ui:plugins:*", _routeAction)
        end

        -- ms.ui window methods are a thin adapter over the shell — the legacy
        -- standalone panel (ui/ms_settings_ui.html) was deleted 2026-07-13.
        -- ms.ui._open stays as adapter-local state: the rebind capture flows
        -- flip it and ms_core's focus watcher reads it.
        ms.ui.show = function()
            if ms.shell and ms.shell.show then ms.shell.show() end
        end

        -- Bring the shell forward for a flow that needs it visible, but skip the
        -- alpha-0 → 1 fade (and the open sound) when it is already up. ms.ui.show
        -- always replays that intro; calling it mid-session — as the rebind
        -- confirm did — made an already-visible shell flash a full fade-in for no
        -- reason. When it really is hidden, fall through to the normal show.
        ms.ui.ensureVisible = function()
            local visible = ms._shellState and ms._shellState.visible
            local ready   = ms.shell and ms.shell.isReady and ms.shell.isReady()
            if visible and ready then
                ms.ui._open = true
                return
            end
            ms.ui.show()
        end

        ms.ui.hide = function()
            ms.ui._open = false
            if ms.shell and ms.shell.hide then ms.shell.hide() end
        end

        ms.ui.toggle = function()
            if ms.shell and ms.shell.toggle then ms.shell.toggle() end
        end

        ms.ui.prewarm = function()
            -- Build the shell webview during boot rather than on the first
            -- open, so its page is loaded and already sitting on the default
            -- panel by the time the hotkey is pressed. This used to be a
            -- no-op whose comment claimed the boot build happened elsewhere;
            -- nothing did it, so the page only loaded on first show.
            --
            -- init() leaves the window at alpha 0 and never shows it, so this
            -- is invisible — it only warms the page.
            if not (ms.shell and ms.shell.init) then return end

            pcall(function()
                if ms.shell.webview and ms.shell.webview() then return end
                ms.shell.init()
            end)
        end
    -- END UI State Cache --

    -- ms.ui.modal --
        ms.ui.modal = function(data, callback)
            if not callback then return end
            -- Shell modal host (openLuaModal → modalResult round-trip)
            if not (ms.shell and ms.shell.isReady and ms.shell.isReady()) then
                pcall(callback, { confirmed = false })
                return
            end
            local ok, json = pcall(hs.json.encode, {
                title   = data.title   or "",
                msg     = data.msg     or "",
                confirm = data.confirm or "OK",
                cancel  = data.cancel  or "Cancel",
            })
            if not ok then pcall(callback, { confirmed = false }); return end
            ms.ui._modalCallback = callback
            pcall(function()
                ms.shell.eval("openLuaModal(" .. json .. ")")
            end)
        end

        -- Mutate the already-open modal without opening a new one. `data` may
        -- carry any of title/msg/confirm/cancel/showConfirm/showCancel; omitted
        -- fields are left as they are. Drives the rebind prompt's live capture →
        -- confirm phases in a single modal (see updateLuaModal in the shell).
        ms.ui.modalUpdate = function(data)
            if not (ms.shell and ms.shell.isReady and ms.shell.isReady()) then
                return
            end
            local ok, json = pcall(hs.json.encode, data or {})
            if not ok then return end
            pcall(function()
                ms.shell.eval("updateLuaModal(" .. json .. ")")
            end)
        end

        -- Close the open modal from Lua, resolving its callback as if the user
        -- clicked Confirm (true) or Cancel (false). Needed because during rebind
        -- capture an eventtap swallows the keyboard, so the modal's own
        -- Enter/Escape handlers never fire — Escape has to close it from here.
        ms.ui.modalClose = function(confirmed)
            if not (ms.shell and ms.shell.isReady and ms.shell.isReady()) then
                return
            end
            pcall(function()
                ms.shell.eval("closeModal(" .. (confirmed and "true" or "false") .. ")")
            end)
        end
    -- END ms.ui.modal --

    -- ms.ui.prompt --
        ms.ui.prompt = function(data, callback)
            if not callback then return end
            -- Shell modal host with text input (openLuaModal → modalResult)
            if not (ms.shell and ms.shell.isReady and ms.shell.isReady()) then
                pcall(callback, { confirmed = false, value = "" })
                return
            end
            local ok, json = pcall(hs.json.encode, {
                title        = data.title   or "",
                msg          = data.msg     or "",
                confirm      = data.confirm or "OK",
                cancel       = data.cancel  or "Cancel",
                hasInput     = true,
                inputDefault = data.default or "",
            })
            if not ok then pcall(callback, { confirmed = false, value = "" }); return end
            ms.ui._modalCallback = callback
            pcall(function()
                ms.shell.eval("openLuaModal(" .. json .. ")")
            end)
        end
    -- END ms.ui.prompt --

    end
-- END Webview Panel --

return MsUI

end
