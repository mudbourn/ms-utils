-- MsDevTools --
    local MsDevTools = {}

    MsDevTools.name    = "MsDevTools"
    MsDevTools.version = "1.0"

    MsDevTools.archiveLimit = 15
    MsDevTools.logDir       = "~/Documents/ms_dev_logs/"
    MsDevTools.branchTrace  = true

    -- Panel push helper: route through shellReceive when panel is in shell,
    -- fall back to direct evaluateJavaScript for standalone webviews.
    local function _pushToPanel(panelView, panelId, js)
        -- Try shell path first (panel inline in shell)
        local ms = _G.ms
        if ms and ms.shell and ms.shell.isReady and ms.shell.isReady() then
            -- Extract function call: "appendEntry({...})" → fn="appendEntry", args="{...}"
            local fnName, argStr = js:match("^(%w+)%((.+)%)$")
            if fnName and argStr then
                -- shellReceive routes to the registered JS panel handler
                -- (shellDispatch would send BACK to Lua — wrong direction)
                local receiveJs = "shellReceive(\"" .. panelId .. "\",\"" .. fnName .. "\"," .. argStr .. ")"
                pcall(function() ms.shell.eval(receiveJs) end)
                return
            end
        end
        -- Fallback: direct webview push (standalone panel)
        if panelView then
            pcall(function() panelView:evaluateJavaScript(js) end)
        end
    end
-- END MsDevTools --

-- State --
    local _home       = os.getenv("HOME")
    local _devLogDir  = _home .. "/Documents/"
    local _devBaseDir = _devLogDir .. "ms_dev_logs/"
    local _devArchDir = _devBaseDir .. "backups/"
    local _devBase    = "file://" .. _home .. "/.hammerspoon/ui/"

    local _jsonDir, _readDir
    local _catPaths, _readablePaths

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

    local _devBusy            = false
    local _devLastConsoleType = nil
    local _consoleMacroActive = false
    local _lastReadLine       = nil
    local _readRepeatCount    = 0
    local _lastReadCategory   = nil

    local function _flushReadLine()
        if not _lastReadLine then return end

        local catPath = _readablePaths and _readablePaths[_lastReadCategory]

        if catPath then
            pcall(function()
                hs.fs.mkdir(_devBaseDir)
                hs.fs.mkdir(_readDir)

                local f = io.open(catPath, "a")

                if f then
                    if _readRepeatCount > 1 then
                        f:write(_lastReadLine .. " \195\151" .. _readRepeatCount .. "\n")
                    else
                        f:write(_lastReadLine .. "\n")
                    end

                    f:close()
                end
            end)
        end

        _lastReadLine     = nil
        _readRepeatCount  = 0
        _lastReadCategory = nil
    end

    local _consolePanel, _watcherPanel, _keysPanel, _windowPanel
    local _consolePanelPos, _watcherPanelPos, _keysPanelPos, _windowPanelPos
    local _consoleOpen, _watcherOpen, _keysOpen, _windowOpen
    local _keysReady, _activeKeys, _activeButtons, _coordMode
    local _mousePos, _mousePoller, _windowPoller
    local _windowHistory, _windowLast, _windowMaxHistory
    local _pushMouseState

    local _camMoveAccum  = 0
    local _waitAccum     = 0

    -- Shell-mode helper: returns true when the shell is the active display
    -- (standalone panels are nil, but shell panels are inline and ready)
    local function _shellActive()
        local m = _G.ms
        return m and m.shell and m.shell.isReady and m.shell.isReady() or false
    end
    local _waitDuration  = 0
    local _traceSuppress = false
    local _branchState   = {}

    local _devFadeTimers = {}
    local _htmlCache = {}

    local function _cacheDevHTML()
        local files = {
            console = _home .. "/.hammerspoon/ui/ms_console.html",
            watcher = _home .. "/.hammerspoon/ui/ms_watcher.html",
            keys    = _home .. "/.hammerspoon/ui/ms_keys.html",
            window  = _home .. "/.hammerspoon/ui/ms_window.html",
        }
        for name, path in pairs(files) do
            local f = io.open(path, "r")
            if f then
                _htmlCache[name] = f:read("*all")
                f:close()
            end
        end
    end
-- END State --

-- Lifecycle --
    function MsDevTools:init()
        _jsonDir = _devBaseDir .. "json/"
        _readDir = _devBaseDir .. "readable/"

        _catPaths = {}
        _readablePaths = {}

        for _, cat in ipairs({"input", "macro", "system", "error", "console"}) do
            _catPaths[cat]      = _jsonDir .. "ms_dev_" .. cat .. ".log"
            _readablePaths[cat] = _readDir .. "ms_dev_" .. cat .. ".txt"
        end

        self:_archiveOnReload()

        _activeKeys       = {}
        _activeButtons    = {}
        _coordMode        = "screen"
        _keysReady        = false
        _windowHistory    = {}
        _windowLast       = nil
        _windowMaxHistory = 80
    end

    function MsDevTools:start()
        if not ms then return end
        if ms.checkGuardian and not ms.checkGuardian("MsDevTools") then return end

        _cacheDevHTML()

        ms.dev = {
            _consolePanel    = nil,
            _watcherPanel    = nil,
            _keysPanel       = nil,
            _consolePanelPos = nil,
            _watcherPanelPos = nil,
            _keysPanelPos    = nil,
            _activeKeys      = _activeKeys,
            _activeButtons   = _activeButtons,
            _coordMode       = _coordMode,
            _keysReady       = false,
        }

        setmetatable(ms.dev, {
            __index = function(t, k)
                if     k == "_consolePanel" then return _consolePanel
                elseif k == "_watcherPanel" then return _watcherPanel
                elseif k == "_keysPanel"    then return _keysPanel
                elseif k == "_keysReady"    then return _keysReady
                elseif k == "_consoleOpen"  then return _consoleOpen
                elseif k == "_watcherOpen"  then return _watcherOpen
                elseif k == "_keysOpen"     then return _keysOpen
                elseif k == "_windowOpen"   then return _windowOpen
                elseif k == "recolor"       then return function() self:recolor() end
                end
            end,
        })

        ms.dev.log = function(entry)
            self:log(entry)
        end

        ms.dev._onMacroFire = function(...)
            self:onMacroFire(...)
        end

        ms.dev._onKeyEvent = function(...)
            self:onKeyEvent(...)
        end

        ms.dev._onMouseEvent = function(...)
            self:onMouseEvent(...)
        end

        ms.dev.console = {}
        ms.dev.console.show   = function() self:showConsole() end
        ms.dev.console.hide   = function() self:hideConsole() end
        ms.dev.console.toggle = function() self:toggleConsole() end

        ms.dev.watcher = {}
        ms.dev.watcher.show   = function() self:showWatcher() end
        ms.dev.watcher.hide   = function() self:hideWatcher() end
        ms.dev.watcher.toggle = function() self:toggleWatcher() end

        ms.dev.keys = {}
        ms.dev.keys.show   = function() self:showKeys() end
        ms.dev.keys.hide   = function() self:hideKeys() end
        ms.dev.keys.toggle = function() self:toggleKeys() end

        ms.dev.window = {}
        ms.dev.window.show   = function() self:showWindow() end
        ms.dev.window.hide   = function() self:hideWindow() end
        ms.dev.window.toggle = function() self:toggleWindow() end

        ms.dev.prewarm     = function() self:prewarm() end
        ms.dev.prewarmStep = function(which) self:prewarmStep(which) end
        ms.dev.step        = function(msg) self:step(msg) end

        ms.dev._pushMouseState = function(x, y)
            self:pushMouseState(x, y)
        end
        _pushMouseState = ms.dev._pushMouseState

        self._origPrint = print

        _G.print = function(...)
            self._origPrint(...)

            local parts = {}

            for i = 1, select('#', ...) do
                parts[i] = tostring(select(i, ...))
            end

            self:log({
                type = "print",
                msg  = table.concat(parts, "\t"),
            })
        end

        -- Shell bus subscribers: handle messages from dev tool panels in shell
        if ms.bus then
            -- Console panel actions
            ms.bus.on("ui:console:*", function(topic, body)
                if not body or type(body) ~= "table" then return end
                local action = body.action
                if action == "execute" and body.code then
                    local fn, err = load("return " .. body.code)
                    if not fn then fn, err = load(body.code) end
                    if not fn then
                        self:_devWrite({ type = "error", msg = err or "syntax error" })
                    else
                        local res = table.pack(pcall(fn))
                        local success = table.remove(res, 1)
                        if not success then
                            self:_devWrite({ type = "error", msg = tostring(res[1]) })
                        elseif #res > 0 then
                            local parts = {}
                            for _, v in ipairs(res) do parts[#parts + 1] = tostring(v) end
                            self:_devWrite({ type = "result", msg = table.concat(parts, "\t") })
                        end
                    end
                elseif action == "clear" then
                    for _, cat in ipairs({"macro", "console", "error", "system", "input"}) do
                        local p = _catPaths[cat]
                        if p then local f = io.open(p, "w"); if f then f:close() end end
                        local r = _readablePaths[cat]
                        if r then local f = io.open(r, "w"); if f then f:close() end end
                    end
                elseif action == "playSlot" and body.slot then
                    ms.playSlot(body.slot)
                elseif action == "ready" then
                    _loadDevHistory(nil, {"macro", "console", "error", "system", "input"}, "console")
                end
            end)

            -- Watcher panel actions
            ms.bus.on("ui:watcher:*", function(topic, body)
                if not body or type(body) ~= "table" then return end
                local action = body.action
                if action == "clear" then
                    for _, cat in ipairs({"macro", "error", "system"}) do
                        local p = _catPaths[cat]
                        if p then local f = io.open(p, "w"); if f then f:close() end end
                        local r = _readablePaths[cat]
                        if r then local f = io.open(r, "w"); if f then f:close() end end
                    end
                elseif action == "playSlot" and body.slot then
                    ms.playSlot(body.slot)
                elseif action == "ready" then
                    _loadDevHistory(nil, {"macro", "error", "system"}, "watcher")
                end
            end)

            -- Inputs (keys) panel actions
            ms.bus.on("ui:keys:*", function(topic, body)
                if not body or type(body) ~= "table" then return end
                local action = body.action
                if action == "clear" then
                    local p = _catPaths["input"]
                    if p then local f = io.open(p, "w"); if f then f:close() end end
                    local r = _readablePaths["input"]
                    if r then local f = io.open(r, "w"); if f then f:close() end end
                elseif action == "playSlot" and body.slot then
                    ms.playSlot(body.slot)
                elseif action == "ready" then
                    if not _keysReady then
                        _keysReady = true
                        local _p = hs.mouse.absolutePosition()
                        _mousePos = { x = math.floor(_p.x), y = math.floor(_p.y) }
                    end
                    _loadDevHistory(nil, {"input"}, "keys")
                elseif action == "setCoordMode" then
                    _coordMode = body.mode or "screen"
                end
            end)

            -- Window panel actions
            ms.bus.on("ui:window:*", function(topic, body)
                if not body or type(body) ~= "table" then return end
                local action = body.action
                if action == "clear" then
                    _windowHistory = {}
                elseif action == "playSlot" and body.slot then
                    ms.playSlot(body.slot)
                elseif action == "ready" then
                    -- History + current window loaded in showWindow() shell path
                end
            end)

            -- Rail navigation: load history + start pollers when panel changes
            ms.bus.on("ui:_shell:navigate", function(data)
                if not data or not data.panel then return end
                local p = data.panel
                if p == "console" then
                    _consoleOpen = true
                    hs.timer.doAfter(0.1, function()
                        _loadDevHistory(nil, {"macro", "console", "error", "system", "input"}, "console")
                    end)
                elseif p == "watcher" then
                    _watcherOpen = true
                    hs.timer.doAfter(0.1, function()
                        _loadDevHistory(nil, {"macro", "error", "system"}, "watcher")
                    end)
                elseif p == "keys" then
                    if not _keysReady then _keysReady = true end
                    hs.timer.doAfter(0.1, function()
                        _loadDevHistory(nil, {"input"}, "keys")
                    end)
                elseif p == "window" then
                    _windowOpen = true
                    hs.timer.doAfter(0.15, function()
                        if #_windowHistory > 0 then
                            local ok, j = pcall(hs.json.encode, _windowHistory)
                            if ok then pcall(function() ms.shell.eval("shellReceive('window','loadHistory'," .. j .. ")") end) end
                        end
                        local win = hs.window.focusedWindow()
                        if win then
                            local app   = (win:application() and win:application():name()) or "?"
                            local title = win:title() or ""
                            local wf    = win:frame()
                            local ok2, j2 = pcall(hs.json.encode, {
                                type = "focus", ts = os.date("%H:%M:%S"),
                                app = app, title = title,
                                w = math.floor(wf.w), h = math.floor(wf.h),
                                x = math.floor(wf.x), y = math.floor(wf.y),
                            })
                            if ok2 then pcall(function() ms.shell.eval("shellReceive('window','updateCurrentWindow'," .. j2 .. ")") end) end
                        end
                    end)
                    -- Start window focus poller
                    if _windowPoller then _windowPoller:stop() end
                    _windowPoller = hs.timer.doEvery(0.4, function()
                        if not _windowOpen or not _shellActive() then
                            if _windowPoller then _windowPoller:stop(); _windowPoller = nil end
                            return
                        end
                        local win = hs.window.focusedWindow()
                        if not win then return end
                        local winId = win:id()
                        if winId == _windowLast then return end
                        _windowLast = winId
                        local app   = (win:application() and win:application():name()) or "?"
                        local title = win:title() or ""
                        local f     = win:frame()
                        self:_pushWindowEvent({
                            type = "focus", ts = os.time(),
                            app = app, title = title,
                            w = math.floor(f.w), h = math.floor(f.h),
                            x = math.floor(f.x), y = math.floor(f.y),
                        })
                    end)
                end
            end)
        end
    end
-- END Lifecycle --

-- Archive Helpers --
    function MsDevTools:_archiveLog(path, stamp, subdir)
        if not hs.fs.attributes(path) then return end

        local sessionDir = _devArchDir .. "session_" .. stamp .. "/"
        local destDir    = sessionDir .. subdir .. "/"

        hs.fs.mkdir(_devBaseDir)
        hs.fs.mkdir(_devArchDir)
        hs.fs.mkdir(sessionDir)
        hs.fs.mkdir(destDir)

        local filename = path:match("([^/]+)$")

        if filename then
            os.rename(path, destDir .. filename)
        end
    end

    function MsDevTools:_pruneSessionArchives(limit)
        if not hs.fs.attributes(_devArchDir) then return end

        local list = {}

        for name in hs.fs.dir(_devArchDir) do
            if name:match("^session_%d%d%d%d%-%d%d%-%d%d_%d%d%d%d%d%d$") then
                table.insert(list, name)
            end
        end

        table.sort(list)

        -- Cap at 5 folders per reload so we never block the main thread.
        local pruned = 0

        while #list > limit and pruned < 5 do
            local dir = _devArchDir .. list[1]

            for _, sub in ipairs({"json", "readable"}) do
                local sp = dir .. "/" .. sub

                if hs.fs.attributes(sp) then
                    for fname in hs.fs.dir(sp) do
                        if fname ~= "." and fname ~= ".." then
                            os.remove(sp .. "/" .. fname)
                        end
                    end

                    hs.fs.rmdir(sp)
                end
            end

            hs.fs.rmdir(dir)
            table.remove(list, 1)
            pruned = pruned + 1
        end
    end

    function MsDevTools:_archiveOnReload()
        _flushReadLine()

        -- Prune first so we never accumulate unbounded folders.
        local limit = (type(self.archiveLimit) == "number" and self.archiveLimit >= 0)
            and self.archiveLimit or 15

        self:_pruneSessionArchives(limit)

        local stamp = os.date("%Y-%m-%d_%H%M%S")

        hs.fs.mkdir(_jsonDir)
        hs.fs.mkdir(_readDir)

        for _, p in pairs(_catPaths) do
            self:_archiveLog(p, stamp, "json")
        end

        for _, p in pairs(_readablePaths) do
            self:_archiveLog(p, stamp, "readable")
        end
    end
-- END Archive Helpers --

-- Core Logging --
    function MsDevTools:_devWrite(entry)
        if _devBusy then return end

        _devBusy = true

        -- Flush any buffered readable line from the previous entry.
        _flushReadLine()

        entry.ts = os.date("%H:%M:%S")

        if not entry.category then
            entry.category = _typeToCategory[entry.type] or "system"
        end

        if not entry.msg or entry.msg == "" then
            local headline = entry.event or entry.key or entry.type or "log"
            local details  = {}

            if entry.source then table.insert(details, "  source: " .. entry.source) end
            if entry.reason then table.insert(details, "  reason: " .. entry.reason) end
            if entry.output then table.insert(details, "  output: " .. tostring(entry.output):sub(1, 200)) end

            if #details > 0 then
                entry.msg = headline .. "\n" .. table.concat(details, "\n")
            else
                entry.msg = headline
            end
        end

        local ok, json = pcall(hs.json.encode, entry)

        if not ok then
            _devBusy = false
            return
        end

        local catPath = _catPaths[entry.category]

        if catPath then
            pcall(function()
                hs.fs.mkdir(_devBaseDir)
                hs.fs.mkdir(_jsonDir)

                local f = io.open(catPath, "a")

                if f then
                    f:write(json .. "\n")
                    f:close()
                end
            end)
        end

        local readPath = _readablePaths[entry.category]

        if readPath then
            pcall(function()
                hs.fs.mkdir(_devBaseDir)
                hs.fs.mkdir(_readDir)

                local f = io.open(readPath, "a")

                if f then
                    local t    = entry.type
                    local line

                    if t == "key" then
                        local arrow = entry.down and "\226\134\147" or "\226\134\145"

                        line = "[" .. entry.ts .. "] " .. arrow .. " "
                            .. (entry.key or "?") .. " (" .. tostring(entry.keyCode or "?") .. ")"

                    elseif t == "mouse" then
                        local arrow = entry.down and "\226\134\147" or "\226\134\145"
                        local pos   = ""

                        if entry.x and entry.y then
                            pos = "  " .. entry.x .. "," .. entry.y
                        end

                        line = "[" .. entry.ts .. "] " .. arrow .. " mouse:"
                            .. tostring(entry.button or "?") .. pos

                    elseif t == "scroll" then
                        line = "[" .. entry.ts .. "] \226\134\165 scroll " .. (entry.direction or "")

                    elseif t == "mousemove" then
                        line = "[" .. entry.ts .. "] \226\134\146 " .. (entry.x or "?") .. ", " .. (entry.y or "?")

                    else
                        local parts = {}

                        local function add(label, val)
                            if val ~= nil and val ~= "" then
                                parts[#parts + 1] = "  " .. label .. ": " .. tostring(val)
                            end
                        end

                        local headline = entry.msg or entry.label or entry.event or entry.type or "log"
                        local first, rest = headline:match("^([^\n]+)\n(.*)$")

                        if first then
                            headline = first
                            add("detail", rest:gsub("\n", " | "))
                        end

                        add("fromDialog", entry.fromDialog)
                        add("to",          entry.to)
                        add("status",      entry.status)
                        add("cur",         entry.cur)
                        add("trusted",     entry.trusted)
                        add("code",        entry.code)
                        add("version",     entry.version)
                        add("channel",     entry.channel)
                        add("target",      entry.target)
                        add("format",      entry.format)
                        add("id",          entry.id)
                        add("label",       entry.label)
                        add("parent",      entry.parentLabel)
                        add("trigger",     entry.trigger)

                        line = "[" .. entry.ts .. "] " .. headline

                        if #parts > 0 then
                            line = line .. "\n" .. table.concat(parts, "\n")
                        end
                    end

                    -- Consecutive suppression: collapse repeated identical lines.
                    if line == _lastReadLine then
                        _readRepeatCount = _readRepeatCount + 1
                    else
                        if _lastReadLine then
                            if _readRepeatCount > 1 then
                                f:write(_lastReadLine .. " \195\151" .. _readRepeatCount .. "\n")
                            else
                                f:write(_lastReadLine .. "\n")
                            end
                        end

                        _lastReadLine     = line
                        _readRepeatCount  = 1
                        _lastReadCategory = entry.category
                    end
                    f:close()
                end
            end)
        end

        local t = entry.type

        if (_consolePanel or _shellActive()) and t ~= "mousemove" and t ~= "step" then
            local send = false

            if t == "macro" then
                _devLastConsoleType = t
                _consoleMacroActive = true
                send = true
            elseif _consoleMacroActive and (t == "key" or t == "mouse" or t == "sound") then
                -- Suppress input/sound noise while macro is active
                send = false
            elseif t == "key" or t == "mouse" or t == "sound" then
                if _devLastConsoleType ~= t then
                    _devLastConsoleType = t
                    send = true
                end
            else
                _devLastConsoleType = nil
                _consoleMacroActive = false
                send = true
            end

            if send then
                pcall(function()
                    _pushToPanel(_consolePanel, "console", "appendEntry(" .. json .. ")")
                end)
            end
        end

        if (_watcherPanel or _shellActive()) and (t == "macro" or t == "print" or t == "error" or t == "system" or t == "sound") then
            pcall(function()
                _pushToPanel(_watcherPanel, "watcher", "appendEntry(" .. json .. ")")
            end)
        end

        if (_keysPanel or _shellActive()) and _keysReady
            and (t == "key" or t == "mouse" or t == "scroll" or t == "mousemove") then
            pcall(function()
                _pushToPanel(_keysPanel, "keys", "appendEntry(" .. json .. ")")
            end)
        end

        _devBusy = false
    end

    function MsDevTools:log(entry)
        self:_devWrite(entry)
    end
-- END Core Logging --

-- Event Hooks --
    function MsDevTools:onMacroFire(id, label, parentId, parentLabel, trigger)
        -- Log subroutine handoff when a macro calls a sub-function
        if parentLabel then
            self:_devWrite({
                type  = "step",
                category = "macro",
                msg   = "[" .. (parentLabel or "macro") .. "] → " .. (label or id),
            })
        end
        self:_devWrite({
            type        = "macro",
            id          = id,
            label       = label or id,
            parentLabel = parentLabel,
            trigger     = trigger,
        })
    end

    function MsDevTools:onKeyEvent(keyCode, keyName, isDown)
        self:_devWrite({
            type    = "key",
            key     = keyName or ("code:" .. tostring(keyCode)),
            keyCode = keyCode,
            down    = isDown,
        })

        if isDown then
            _activeKeys[keyCode] = keyName or tostring(keyCode)
        else
            _activeKeys[keyCode] = nil
        end

        if _keysPanel or _shellActive() then
            local active = {}

            for code, name in pairs(_activeKeys) do
                table.insert(active, {
                    name = name,
                    code = code,
                })
            end

            local aok, aj = pcall(hs.json.encode, active)

            if aok then
                pcall(function()
                    _pushToPanel(_keysPanel, "keys", "updateActiveKeys(" .. aj .. ")")
                end)
            end
        end
    end

    function MsDevTools:onMouseEvent(button, isDown, x, y)
        self:_devWrite({
            type   = "mouse",
            button = button,
            down   = isDown,
            x      = x,
            y      = y,
        })

        if isDown then
            _activeButtons[button] = true
        else
            _activeButtons[button] = nil
        end

        if (_keysPanel or _shellActive()) and _keysReady then
            local active = {}

            for btn in pairs(_activeButtons) do
                table.insert(active, btn)
            end

            local aok, aj = pcall(hs.json.encode, {
                x       = x,
                y       = y,
                buttons = active,
            })

            if aok then
                pcall(function()
                    _pushToPanel(_keysPanel, "keys", "updateMouseState(" .. aj .. ")")
                end)
            end
        end
    end
-- END Event Hooks --

-- Watcher Helpers --
    function MsDevTools:watcherStep(msg)
        if not _watcherPanel then return end

        local co  = coroutine.running()
        local ctx = co and ms._coroContext[co]

        if ctx and ctx.cancelled then return end

        local label = (ctx and ctx.label) or "macro"

        local ok, j = pcall(hs.json.encode, {
            type = "step",
            ts   = os.date("%H:%M:%S"),
            msg  = "[" .. label .. "] " .. msg,
        })

        if ok then
            pcall(function()
                _pushToPanel(_watcherPanel, "watcher", "appendEntry(" .. j .. ")")
            end)
        end
    end

    function MsDevTools:macroLog(msg)
        local co  = coroutine.running()
        local ctx = co and ms._coroContext[co]

        if ctx and ctx.cancelled then return end

        local label = (ctx and ctx.label) or ms._pendingLabel or "macro"

        self:log({
            type     = "step",
            category = "macro",
            msg      = "[" .. label .. "] " .. msg,
        })
    end

    function MsDevTools:flushCam()
        if _camMoveAccum > 1 then
            if _watcherPanel then
                self:watcherStep("cam.move \195\151" .. _camMoveAccum)
            end

            self:macroLog("cam.move \195\151" .. _camMoveAccum)
        end

        _camMoveAccum = 0
    end

    function MsDevTools:flushWait()
        if _waitAccum > 0 then
            local msg = "wait " .. _waitDuration .. "ms"

            if _waitAccum > 1 then
                msg = msg .. " \195\151" .. _waitAccum
            end

            if _watcherPanel then
                self:watcherStep(msg)
            end

            self:macroLog(msg)
            _waitAccum = 0
        end
    end

    function MsDevTools:flushAll()
        self:flushCam()
        self:flushWait()
    end

    function MsDevTools:accCamMove()
        _camMoveAccum = _camMoveAccum + 1
    end

    function MsDevTools:accWait(duration)
        if _waitAccum > 0 and duration == _waitDuration then
            _waitAccum = _waitAccum + 1
        else
            self:flushWait()
            _waitAccum    = 1
            _waitDuration = duration
        end
    end

    function MsDevTools:setTraceSuppress(val)
        _traceSuppress = val
    end

    function MsDevTools:getTraceSuppress()
        return _traceSuppress
    end
-- END Watcher Helpers --

-- Branch Tracing --
    function MsDevTools:_traceLog(co, msg)
        local st = _branchState[co]

        if not st then return end

        table.insert(st.buffer, "[" .. os.date("%H:%M:%S") .. "] [" .. st.label .. "] " .. msg)
    end

    function MsDevTools:flushTraceBuffer(co)
        local st = _branchState[co]

        if not st or #st.buffer == 0 then return end

        pcall(function()
            hs.fs.mkdir(_devBaseDir)
            hs.fs.mkdir(_readDir)

            local f = io.open(_readablePaths["macro"], "a")

            if f then
                for _, line in ipairs(st.buffer) do
                    f:write(line .. "\n")
                end

                f:close()
            end
        end)

        if _watcherPanel then
            for _, line in ipairs(st.buffer) do
                local ok, j = pcall(hs.json.encode, {
                    type = "step",
                    ts   = os.date("%H:%M:%S"),
                    msg  = line,
                })

                if ok then
                    pcall(function()
                        _pushToPanel(_watcherPanel, "watcher", "appendEntry(" .. j .. ")")
                    end)
                end
            end
        end

        st.buffer = {}
    end

    function MsDevTools:startTrace(co, label)
        if not co then return end

        _branchState[co] = {
            label  = label or "macro",
            buffer = {},
        }
    end

    function MsDevTools:stopTrace(co)
        self:flushTraceBuffer(co)

        _branchState[co] = nil
    end
-- END Branch Tracing --

-- Panel Helpers --
    local _HIST_MAX = 500

    local function _loadDevHistory(panel, categories, shellPanelId)
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

        table.sort(entries, function(a, b)
            return (a.ts or "") < (b.ts or "")
        end)

        while #entries > _HIST_MAX do
            table.remove(entries, 1)
        end

        local ok, json = pcall(hs.json.encode, entries)

        if ok then
            if shellPanelId then
                _pushToPanel(nil, shellPanelId, "loadHistory(" .. json .. ")")
            elseif panel then
                pcall(function()
                    panel:evaluateJavaScript("loadHistory(" .. json .. ")")
                end)
            end
        end
    end

    local function _devThemeJS()
        local t = ms._theme or {}

        -- Build a clean theme object for applyTheme()
        local safe = {}
        for _, k in ipairs({"bg","surface","surface2","hover","accent","accentHi",
            "success","dangerBg","danger","warning","text","text2","text3",
            "border","borderDim","accentGlow","accentGlowFaint","dangerGlow",
            "dangerBorder","radius","font"}) do
            if t[k] ~= nil then safe[k] = t[k] end
        end

        -- Handle font URL for custom font files
        if type(t.font) == "string" and t.font:match("%.[ot]tf$") then
            local fp = hs.configdir .. "/sounds/" .. t.font
            local f = io.open(fp, "r")
            if not f then
                fp = _home .. "/.hammerspoon/sounds/" .. t.font
                f = io.open(fp, "r")
            end
            if f then f:close(); safe.fontURL = "file://" .. fp end
        end

        local ok, json = pcall(hs.json.encode, safe)
        if not ok or json == "{}" then return "" end

        return "applyTheme(" .. json .. ")"
    end

    local function _makeDevPanel(ucName, w, h, xOff, yOff)
        local uc     = hs.webview.usercontent.new(ucName)
        local screen = hs.screen.mainScreen():frame()
        local x      = screen.x + screen.w - w - xOff
        local y      = screen.y + yOff
        local panel  = hs.webview.new(
            { x = x, y = y, w = w, h = h },
            { developerExtrasEnabled = true },
            uc
        )

        if not panel then return nil, uc end

        pcall(function() panel:windowStyle(0) end)
        pcall(function() panel:level(hs.canvas.windowLevels.floating) end)
        pcall(function() panel:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces) end)
        pcall(function() panel:allowTextEntry(true) end)
        pcall(function() panel:shadow(true) end)

        return panel, uc, { x = x, y = y, w = w, h = h }
    end

    local function _setupDevPanelTheme(panel, timerKey, onReady)
        if ms and ms.theme and ms.theme.applyWindowRadius then ms.theme.applyWindowRadius(panel) end
        if ms and ms.theme and ms.theme.onChanged then
            ms.theme.onChanged(function()
                if ms and ms.theme and ms.theme._pushWindowRadius then ms.theme._pushWindowRadius(panel) end
            end)
        end

        panel:navigationCallback(function(_, action)
            if action == "navigating" then return end

            _devFadeTimers[timerKey] = hs.timer.doAfter(0, function()
                _devFadeTimers[timerKey] = nil
                local tj = _devThemeJS()

                if tj ~= "" then
                    pcall(function() panel:evaluateJavaScript(tj) end)
                end
            end)

            if onReady then onReady() end
        end)
    end

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

    function MsDevTools:pushMouseState(x, y)
        if not _keysPanel and not _shellActive() then return end

        local _x   = x or (_mousePos and _mousePos.x) or 0
        local _y   = y or (_mousePos and _mousePos.y) or 0
        local mode = _coordMode or "screen"
        local tx, ty = _x, _y

        if mode == "window" or mode == "windowTR" or mode == "windowBL"
            or mode == "windowBR" or mode == "windowCenter" or mode == "ref" then

            local win = ms.getTargetWin()

            if win then
                local f = win:frame()

                if mode == "window" then
                    tx = _x - f.x
                    ty = _y - f.y

                elseif mode == "windowTR" then
                    tx = _x - (f.x + f.w)
                    ty = _y - f.y

                elseif mode == "windowBL" then
                    tx = _x - f.x
                    ty = _y - (f.y + f.h)

                elseif mode == "windowBR" then
                    tx = _x - (f.x + f.w)
                    ty = _y - (f.y + f.h)

                elseif mode == "windowCenter" then
                    tx = _x - (f.x + f.w / 2)
                    ty = _y - (f.y + f.h / 2)

                elseif mode == "ref" then
                    tx = _x - f.x
                    ty = _y - f.y
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
            _pushToPanel(_keysPanel, "keys", "updateMouseState(" .. j .. ")")
        end)
    end
-- END Panel Helpers --

-- Console Panel --
    function MsDevTools:_buildConsolePanel()
        local panel, ucCon, pos = _makeDevPanel("console", 360, 480, 20, 20)

        if not panel then return nil end

        ucCon:setCallback(function(msg)
            local ok, data = pcall(hs.json.decode, msg.body)

            if not ok or type(data) ~= "table" then return end

            if data.action == "execute" and data.code then
                local fn, err = load("return " .. data.code)

                if not fn then fn, err = load(data.code) end

                if not fn then
                    self:_devWrite({
                        type = "error",
                        msg  = err or "syntax error",
                    })
                else
                    local res     = table.pack(pcall(fn))
                    local success = table.remove(res, 1)

                    if not success then
                        self:_devWrite({
                            type = "error",
                            msg  = tostring(res[1]),
                        })
                    elseif #res > 0 then
                        local parts = {}

                        for _, v in ipairs(res) do
                            parts[#parts + 1] = tostring(v)
                        end

                        self:_devWrite({
                            type = "result",
                            msg  = table.concat(parts, "\t"),
                        })
                    end
                end

            elseif data.action == "clear" then
                for _, cat in ipairs({"macro", "console", "error", "system", "input"}) do
                    local p = _catPaths[cat]
                    if p then local f = io.open(p, "w"); if f then f:close() end end

                    local r = _readablePaths[cat]
                    if r then local f = io.open(r, "w"); if f then f:close() end end
                end

            elseif data.action == "close" then
                self:hideConsole()

            elseif data.action == "openWatcher" then
                self:showWatcher()

            elseif data.action == "openKeys" then
                self:showKeys()

            elseif data.action == "move" and _consolePanelPos then
                _consolePanelPos.x = _consolePanelPos.x + (data.dx or 0)
                _consolePanelPos.y = _consolePanelPos.y + (data.dy or 0)

                if _consolePanel then
                    pcall(function() _consolePanel:frame(_consolePanelPos) end)
                end

            elseif data.action == "playSlot" and data.slot then
                ms.playSlot(data.slot)
            end
        end)

        _consolePanelPos = pos
        _setupDevPanelTheme(panel, "_themeConsole")

        if _htmlCache["console"] then
            panel:html(_htmlCache["console"], _devBase)
        end

        return panel
    end

    function MsDevTools:showConsole()
        -- Shell path: switch to console tab and load history
        local ms = _G.ms
        if ms and ms.shell and ms.shell.isReady and ms.shell.isReady() then
            _consoleOpen = true
            ms.shell.show()
            ms.shell.eval("showPanel('console')")
            hs.timer.doAfter(0.15, function()
                _loadDevHistory(nil, {"macro", "console", "error", "system", "input"}, "console")
            end)
            return
        end

        if not _consolePanel then
            _consolePanel = self:_buildConsolePanel()

            if not _consolePanel then return end
        end

        _consoleOpen = true

        if ms.ui and ms.ui.markDirty then ms.ui.markDirty() end
        if ms.ui and ms.ui.refresh then pcall(function() ms.ui.refresh() end) end

        ms.playSlot("settingsOpen")

        _consolePanel:show()

        pcall(function() _consolePanel:bringToFront(true) end)

        _devFadeIn(_consolePanel, "console")

        _devFadeTimers["_histConsole"] = hs.timer.doAfter(0.1, function()
            _devFadeTimers["_histConsole"] = nil
            if not _consolePanel or not _consoleOpen then return end

            _loadDevHistory(_consolePanel, {"macro", "console", "error", "system", "input"})
        end)
    end

    function MsDevTools:hideConsole()
        _consoleOpen = false

        if ms.ui and ms.ui.markDirty then ms.ui.markDirty() end
        if ms.ui and ms.ui.refresh then pcall(function() ms.ui.refresh() end) end

        if _consolePanel then
            ms.playSlot("settingsClose")

            _devFadeOut(_consolePanel, "console", function()
                if _consolePanel then _consolePanel:hide() end
            end)
        end
    end

    function MsDevTools:toggleConsole()
        if _consoleOpen then
            self:hideConsole()
        else
            self:showConsole()
        end
    end
-- END Console Panel --

-- Watcher Panel --
    function MsDevTools:_buildWatcherPanel()
        local panel, ucWatcher, pos = _makeDevPanel("watcher", 360, 480, 50, 44)

        if not panel then return nil end

        ucWatcher:setCallback(function(msg)
            local ok, data = pcall(hs.json.decode, msg.body)

            if not ok or type(data) ~= "table" then return end

            if data.action == "clear" then
                for _, cat in ipairs({"macro", "error", "system"}) do
                    local p = _catPaths[cat]
                    if p then local f = io.open(p, "w"); if f then f:close() end end

                    local r = _readablePaths[cat]
                    if r then local f = io.open(r, "w"); if f then f:close() end end
                end

            elseif data.action == "close" then
                self:hideWatcher()

            elseif data.action == "move" and _watcherPanelPos then
                _watcherPanelPos.x = _watcherPanelPos.x + (data.dx or 0)
                _watcherPanelPos.y = _watcherPanelPos.y + (data.dy or 0)

                if _watcherPanel then
                    pcall(function() _watcherPanel:frame(_watcherPanelPos) end)
                end

            elseif data.action == "playSlot" and data.slot then
                ms.playSlot(data.slot)
            end
        end)

        _watcherPanelPos = pos
        _setupDevPanelTheme(panel, "_themeWatcher")

        if _htmlCache["watcher"] then
            panel:html(_htmlCache["watcher"], _devBase)
        end

        return panel
    end

    function MsDevTools:showWatcher()
        local ms = _G.ms
        if ms and ms.shell and ms.shell.isReady and ms.shell.isReady() then
            _watcherOpen = true
            ms.shell.show()
            ms.shell.eval("showPanel('watcher')")
            hs.timer.doAfter(0.15, function()
                _loadDevHistory(nil, {"macro", "error", "system"}, "watcher")
            end)
            return
        end

        if not _watcherPanel then
            _watcherPanel = self:_buildWatcherPanel()

            if not _watcherPanel then return end
        end

        _watcherOpen = true

        if ms.ui and ms.ui.markDirty then ms.ui.markDirty() end
        if ms.ui and ms.ui.refresh then pcall(function() ms.ui.refresh() end) end

        ms.playSlot("settingsOpen")

        _watcherPanel:show()

        pcall(function() _watcherPanel:bringToFront(true) end)

        _devFadeIn(_watcherPanel, "watcher")

        _devFadeTimers["_histWatcher"] = hs.timer.doAfter(0.1, function()
            _devFadeTimers["_histWatcher"] = nil
            if not _watcherPanel or not _watcherOpen then return end

            _loadDevHistory(_watcherPanel, {"macro", "error", "system"})
        end)
    end

    function MsDevTools:hideWatcher()
        _watcherOpen = false

        if ms.ui and ms.ui.markDirty then ms.ui.markDirty() end
        if ms.ui and ms.ui.refresh then pcall(function() ms.ui.refresh() end) end

        if _watcherPanel then
            ms.playSlot("settingsClose")

            _devFadeOut(_watcherPanel, "watcher", function()
                if _watcherPanel then _watcherPanel:hide() end
            end)
        end
    end

    function MsDevTools:toggleWatcher()
        if _watcherOpen then
            self:hideWatcher()
        else
            self:showWatcher()
        end
    end
-- END Watcher Panel --

-- Inputs Panel --
    function MsDevTools:_buildKeysPanel()
        local panel, ucKeys, pos = _makeDevPanel("keys", 360, 480, 80, 68)

        if not panel then return nil end

        ucKeys:setCallback(function(msg)
            local ok, data = pcall(hs.json.decode, msg.body)

            if not ok or type(data) ~= "table" then return end

            if data.action == "clear" then
                local p = _catPaths["input"]
                if p then local f = io.open(p, "w"); if f then f:close() end end

                local r = _readablePaths["input"]
                if r then local f = io.open(r, "w"); if f then f:close() end end

            elseif data.action == "close" then
                self:hideKeys()

            elseif data.action == "ready" then
                if not _keysReady then
                    _keysReady = true

                    local _p = hs.mouse.absolutePosition()

                    _mousePos = {
                        x = math.floor(_p.x),
                        y = math.floor(_p.y),
                    }
                end

            elseif data.action == "setCoordMode" then
                _coordMode = data.mode or "screen"

                _devFadeTimers["_coordPush"] = hs.timer.doAfter(0.01, function()
                    _devFadeTimers["_coordPush"] = nil
                    if _keysPanel then
                        pcall(function() _pushMouseState() end)
                    end
                end)

            elseif data.action == "move" and _keysPanelPos then
                _keysPanelPos.x = _keysPanelPos.x + (data.dx or 0)
                _keysPanelPos.y = _keysPanelPos.y + (data.dy or 0)

                if _keysPanel then
                    pcall(function() _keysPanel:frame(_keysPanelPos) end)
                end

            elseif data.action == "playSlot" and data.slot then
                ms.playSlot(data.slot)
            end
        end)

        if not _htmlCache["keys"] then return nil end

        _keysPanelPos = pos
        _keysReady    = false

        local function keysOnReady()
            if not _keysReady then
                _keysReady = true

                local _p = hs.mouse.absolutePosition()

                _mousePos = {
                    x = math.floor(_p.x),
                    y = math.floor(_p.y),
                }
            end
        end

        _setupDevPanelTheme(panel, "_themeKeys", keysOnReady)

        panel:html(_htmlCache["keys"], _devBase)

        return panel
    end

    function MsDevTools:showKeys()
        local ms = _G.ms
        if ms and ms.shell and ms.shell.isReady and ms.shell.isReady() then
            _keysOpen = true
            _keysReady = true
            ms.shell.show()
            ms.shell.eval("showPanel('keys')")
            hs.timer.doAfter(0.15, function()
                _loadDevHistory(nil, {"input"}, "keys")
            end)
            return
        end

        if not _keysPanel then
            _keysPanel = self:_buildKeysPanel()

            if not _keysPanel then return end
        end

        _keysOpen  = true
        _keysReady = true

        if ms.ui and ms.ui.markDirty then ms.ui.markDirty() end
        if ms.ui and ms.ui.refresh then pcall(function() ms.ui.refresh() end) end

        ms.playSlot("settingsOpen")

        _keysPanel:show()

        pcall(function() _keysPanel:bringToFront(true) end)

        _devFadeIn(_keysPanel, "keys")

        _devFadeTimers["_histKeys"] = hs.timer.doAfter(0.1, function()
            _devFadeTimers["_histKeys"] = nil
            if not _keysPanel or not _keysOpen then return end

            _loadDevHistory(_keysPanel, {"input"})

            pcall(function() _pushMouseState() end)
        end)

        if _mousePoller then _mousePoller:stop() end

        _mousePoller = hs.timer.doEvery(0.1, function()
            if not _keysPanel then
                if _mousePoller then
                    _mousePoller:stop()
                    _mousePoller = nil
                end

                return
            end

            local _p      = hs.mouse.absolutePosition()
            local _x, _y  = math.floor(_p.x), math.floor(_p.y)
            local prev    = _mousePos

            if not prev or _x ~= prev.x or _y ~= prev.y then
                _mousePos = { x = _x, y = _y }

                _pushMouseState(_x, _y)
            end
        end)
    end

    function MsDevTools:hideKeys()
        if _mousePoller then
            _mousePoller:stop()
            _mousePoller = nil
        end

        _keysReady = false
        _keysOpen  = false

        if ms.ui and ms.ui.markDirty then ms.ui.markDirty() end
        if ms.ui and ms.ui.refresh then pcall(function() ms.ui.refresh() end) end

        if _keysPanel then
            ms.playSlot("settingsClose")

            _devFadeOut(_keysPanel, "keys", function()
                if _keysPanel then _keysPanel:hide() end
            end)
        end
    end

    function MsDevTools:toggleKeys()
        if _keysOpen then
            self:hideKeys()
        else
            self:showKeys()
        end
    end
-- END Inputs Panel --

-- Window Panel --
    function MsDevTools:_pushWindowEvent(entry)
        table.insert(_windowHistory, entry)

        if #_windowHistory > _windowMaxHistory then
            table.remove(_windowHistory, 1)
        end

        if _windowPanel or _shellActive() then
            local ok, j = pcall(hs.json.encode, entry)

            if ok then
                pcall(function()
                    _pushToPanel(_windowPanel, "window", "appendEntry(" .. j .. ")")
                end)
                pcall(function()
                    _pushToPanel(_windowPanel, "window", "updateCurrentWindow(" .. j .. ")")
                end)
            end
        end
    end

    function MsDevTools:_buildWindowPanel()
        local panel, ucWindow, pos = _makeDevPanel("window", 360, 480, 110, 68)

        if not panel then return nil end

        ucWindow:setCallback(function(msg)
            local ok, data = pcall(hs.json.decode, msg.body)

            if not ok or type(data) ~= "table" then return end

            if data.action == "clear" then
                _windowHistory = {}

            elseif data.action == "close" then
                self:hideWindow()

            elseif data.action == "move" and _windowPanelPos then
                _windowPanelPos.x = _windowPanelPos.x + (data.dx or 0)
                _windowPanelPos.y = _windowPanelPos.y + (data.dy or 0)

                if _windowPanel then
                    pcall(function() _windowPanel:frame(_windowPanelPos) end)
                end

            elseif data.action == "playSlot" and data.slot then
                ms.playSlot(data.slot)
            end
        end)

        _windowPanelPos = pos
        _setupDevPanelTheme(panel, "_themeWindow")

        if _htmlCache["window"] then
            panel:html(_htmlCache["window"], _devBase)
        end

        -- Load history and current window state once on build
        _devFadeTimers["_histWindow"] = hs.timer.doAfter(0.05, function()
            _devFadeTimers["_histWindow"] = nil
            if not _windowPanel then return end

            if #_windowHistory > 0 then
                local ok, j = pcall(hs.json.encode, _windowHistory)
                if ok then
                    pcall(function() panel:evaluateJavaScript("loadHistory(" .. j .. ")") end)
                end
            end

            local win = hs.window.focusedWindow()
            if win then
                local app   = (win:application() and win:application():name()) or "?"
                local title = win:title() or ""
                local wf    = win:frame()
                local ok2, j2 = pcall(hs.json.encode, {
                    type  = "focus",
                    ts    = os.date("%H:%M:%S"),
                    app   = app,
                    title = title,
                    w     = math.floor(wf.w),
                    h     = math.floor(wf.h),
                    x     = math.floor(wf.x),
                    y     = math.floor(wf.y),
                })
                if ok2 then
                    pcall(function() panel:evaluateJavaScript("updateCurrentWindow(" .. j2 .. ")") end)
                end
            end
        end)

        return panel
    end

    function MsDevTools:showWindow()
        local ms = _G.ms
        if ms and ms.shell and ms.shell.isReady and ms.shell.isReady() then
            _windowOpen = true
            ms.shell.show()
            ms.shell.eval("showPanel('window')")
            -- Load window history and current state
            hs.timer.doAfter(0.15, function()
                if #_windowHistory > 0 then
                    local ok, j = pcall(hs.json.encode, _windowHistory)
                    if ok then
                        pcall(function() ms.shell.eval("shellReceive('window','loadHistory'," .. j .. ")") end)
                    end
                end
                local win = hs.window.focusedWindow()
                if win then
                    local app   = (win:application() and win:application():name()) or "?"
                    local title = win:title() or ""
                    local wf    = win:frame()
                    local ok2, j2 = pcall(hs.json.encode, {
                        type  = "focus",
                        ts    = os.date("%H:%M:%S"),
                        app   = app,
                        title = title,
                        w     = math.floor(wf.w),
                        h     = math.floor(wf.h),
                        x     = math.floor(wf.x),
                        y     = math.floor(wf.y),
                    })
                    if ok2 then
                        pcall(function() ms.shell.eval("shellReceive('window','updateCurrentWindow'," .. j2 .. ")") end)
                    end
                end
            end)
            -- Start window focus poller for shell mode
            if _windowPoller then _windowPoller:stop() end
            _windowPoller = hs.timer.doEvery(0.4, function()
                if not _windowOpen or (not _windowPanel and not _shellActive()) then
                    if _windowPoller then _windowPoller:stop(); _windowPoller = nil end
                    return
                end
                local win = hs.window.focusedWindow()
                if not win then return end
                local winId = win:id()
                if winId == _windowLast then return end
                _windowLast = winId
                local app   = (win:application() and win:application():name()) or "?"
                local title = win:title() or ""
                local f     = win:frame()
                self:_pushWindowEvent({
                    type  = "focus",
                    ts    = os.time(),
                    app   = app,
                    title = title,
                    w     = math.floor(f.w),
                    h     = math.floor(f.h),
                    x     = math.floor(f.x),
                    y     = math.floor(f.y),
                })
            end)
            return
        end

        if not _windowPanel then
            _windowPanel = self:_buildWindowPanel()

            if not _windowPanel then return end
        end

        _windowOpen = true

        if ms.ui and ms.ui.markDirty then ms.ui.markDirty() end
        if ms.ui and ms.ui.refresh then pcall(function() ms.ui.refresh() end) end

        ms.playSlot("settingsOpen")

        _windowPanel:show()

        pcall(function() _windowPanel:bringToFront(true) end)

        _devFadeIn(_windowPanel, "window")

        -- Push current window immediately (don't wait for poller)
        local win = hs.window.focusedWindow()
        if win then
            local app   = (win:application() and win:application():name()) or "?"
            local title = win:title() or ""
            local f     = win:frame()
            self:_pushWindowEvent({
                type  = "focus",
                ts    = os.time(),
                app   = app,
                title = title,
                w     = math.floor(f.w),
                h     = math.floor(f.h),
                x     = math.floor(f.x),
                y     = math.floor(f.y),
            })
        end

        if _windowPoller then _windowPoller:stop() end

        _windowPoller = hs.timer.doEvery(0.4, function()
            if not _windowOpen or (not _windowPanel and not _shellActive()) then
                if _windowPoller then
                    _windowPoller:stop()
                    _windowPoller = nil
                end

                return
            end

            local win = hs.window.focusedWindow()

            if not win then return end

            local winId = win:id()

            if winId == _windowLast then return end

            _windowLast = winId

            local app   = (win:application() and win:application():name()) or "?"
            local title = win:title() or ""
            local f     = win:frame()

            self:_pushWindowEvent({
                type  = "focus",
                ts    = os.time(),
                app   = app,
                title = title,
                w     = math.floor(f.w),
                h     = math.floor(f.h),
                x     = math.floor(f.x),
                y     = math.floor(f.y),
            })
        end)
    end

    function MsDevTools:hideWindow()
        if _windowPoller then
            _windowPoller:stop()
            _windowPoller = nil
        end

        _windowOpen = false

        if ms.ui and ms.ui.markDirty then ms.ui.markDirty() end
        if ms.ui and ms.ui.refresh then pcall(function() ms.ui.refresh() end) end

        if _windowPanel then
            ms.playSlot("settingsClose")

            local panel = _windowPanel

            _windowPanel = nil

            _devFadeOut(panel, "window", function()
                if panel then panel:hide() end
            end)
        end
    end

    function MsDevTools:toggleWindow()
        if _windowOpen then
            self:hideWindow()
        else
            self:showWindow()
        end
    end
-- END Window Panel --

-- Prewarm --
    function MsDevTools:prewarm()
        if not _consolePanel then _consolePanel = self:_buildConsolePanel() end
        if not _watcherPanel then _watcherPanel = self:_buildWatcherPanel() end
        if not _keysPanel    then _keysPanel    = self:_buildKeysPanel() end
        if not _windowPanel  then _windowPanel  = self:_buildWindowPanel() end
    end

    function MsDevTools:recolor()
        local js = _devThemeJS()
        if js == "" then return end
        if _consolePanel then pcall(function() _consolePanel:evaluateJavaScript(js) end) end
        if _watcherPanel then pcall(function() _watcherPanel:evaluateJavaScript(js) end) end
        if _keysPanel    then pcall(function() _keysPanel:evaluateJavaScript(js) end) end
        if _windowPanel  then pcall(function() _windowPanel:evaluateJavaScript(js) end) end
    end

    function MsDevTools:prewarmStep(which)
        if     which == "console" and not _consolePanel then
            _consolePanel = self:_buildConsolePanel()

        elseif which == "watcher" and not _watcherPanel then
            _watcherPanel = self:_buildWatcherPanel()

        elseif which == "keys" and not _keysPanel then
            _keysPanel = self:_buildKeysPanel()

        elseif which == "window" and not _windowPanel then
            _windowPanel = self:_buildWindowPanel()
        end
    end

    function MsDevTools:step(msg)
        local entry = {
            type = "step",
            ts   = os.date("%H:%M:%S"),
            msg  = tostring(msg or ""),
        }

        self:log(entry)

        if _watcherPanel or _shellActive() then
            local ok, j = pcall(hs.json.encode, entry)

            if ok then
                pcall(function()
                    _pushToPanel(_watcherPanel, "watcher", "appendEntry(" .. j .. ")")
                end)
            end
        end
    end
-- END Prewarm --

-- Public Accessors --
    function MsDevTools:getPanel(name)
        if     name == "console" then return _consolePanel
        elseif name == "watcher" then return _watcherPanel
        elseif name == "keys"    then return _keysPanel
        elseif name == "window"  then return _windowPanel
        end
    end
-- END Public Accessors --

return MsDevTools
