-- ms_plugins — Plugin Loading & Teardown --
--
-- Spoons/ is the only place third-party code enters the process. This module
-- decides which of them run, and — the harder half — how to make one stop.
--
-- Hammerspoon has no unload. `require` caches the module, and anything the
-- code registered on its way in (hotkeys, timers, eventtaps, bus handlers)
-- is held by whoever it registered with, not by the module table. So a plugin
-- switched off at the settings level keeps firing until the next reload, and
-- an off switch that does nothing for a minute is worse than no off switch.
--
-- The fix is to know what each plugin registered. Every plugin is loaded with
-- an `ms` of its own: a proxy that forwards everything to the real one, but
-- records an undo closure for each registration it sees pass through. Turning
-- the plugin off replays that list backwards.
--
-- The proxy reaches the plugin through `_ENV`, not through a swapped global.
-- hs.loadSpoon loads Spoons with `require`, so package.preload is the seam:
-- a preload entry compiles the Spoon's init.lua against an environment whose
-- `ms` is the proxy. Closures defined in that chunk capture the environment as
-- an upvalue, so a callback that fires an hour later still registers against
-- the plugin that owns it. Hammerspoon still does everything else — meta.json,
-- :init(), docs, the spoon.<Name> global — because loadSpoon still runs.
--
-- What this cannot see is a plugin calling hs.hotkey.bind or hs.timer.new
-- directly, behind mudscript's back. Nothing in-process can: those register
-- with Hammerspoon itself. That is why "register through ms, implement
-- :stop()" is a library requirement rather than a hope — every plugin in the
-- validated library is reviewed, so it is enforceable at the door.
return function(ms)

    local _home    = os.getenv("HOME")
    local _hsDir   = _home .. "/.hammerspoon"
    local _spoons  = _hsDir .. "/Spoons"

    -- loaded: dir -> true, for plugins whose code is in the process now.
    -- failed: dir -> error string.
    -- _undo:  dir -> array of teardown closures, newest last.
    ms.plugins = {
        loaded = {},
        failed = {},
        _undo  = {},
    }

    -- Helpers --
        local function shortName(dir) return (dir:gsub("%.spoon$", "")) end

        local function record(dir, fn)
            local list = ms.plugins._undo[dir]
            if list then list[#list + 1] = fn end
        end

        -- Removes the first identity match from an array, in place.
        local function removeValue(list, value)
            if type(list) ~= "table" then return end
            for i, v in ipairs(list) do
                if v == value then table.remove(list, i); return end
            end
        end
    -- END Helpers --

    -- Recording Proxy --
        -- Forwards to `real`, except for the keys in `overrides`. Writes go
        -- straight through: a plugin setting ms.something is configuring the
        -- real install, and pretending otherwise would give it a private copy
        -- of state that nothing else reads.
        local function subProxy(real, overrides)
            return setmetatable({}, {
                __index = function(_, k)
                    local o = overrides[k]
                    if o ~= nil then return o end
                    return real[k]
                end,
                __newindex = function(_, k, v) real[k] = v end,
            })
        end

        -- The wrapped surfaces. Each one calls straight through and then
        -- records how to take it back out again.
        --
        -- Only surfaces that keep *executing* after teardown matter for
        -- correctness — binds, bus handlers, key and mouse callbacks. The
        -- settings and tools definitions are cleaned up too, but that is so
        -- a disabled plugin's rows leave the settings panel; a stale row is
        -- cosmetic, a stale keybind is not.
        local function makeProxy(dir)
            local overrides = {}

            -- ms.bind.define(id, ...) — the dispatcher reads _wires and _defs
            -- at fire time, so clearing them stops the bind on the very next
            -- keystroke. No unregistration with the OS is involved.
            overrides.bind = subProxy(ms.bind, {
                define = function(id, a, b)
                    local out = ms.bind.define(id, a, b)
                    record(dir, function()
                        ms.bind._wires[id] = nil
                        if ms.registry and ms.registry._defs then
                            ms.registry._defs[id] = nil
                            removeValue(ms.registry._defList, id)
                        end
                        if ms.binds then ms.binds[id] = nil end
                        if ms.bindConfig then ms.bindConfig[id] = nil end
                    end)
                    return out
                end,
            })

            overrides.bus = subProxy(ms.bus, {
                on = function(topic, fn)
                    local out = ms.bus.on(topic, fn)
                    record(dir, function() pcall(ms.bus.off, topic, fn) end)
                    return out
                end,
            })

            -- ms.key already hands back a handle with :delete(), which is
            -- exactly the undo closure this needs.
            overrides.key = function(...)
                local handle = ms.key(...)
                if type(handle) == "table" and type(handle.delete) == "function" then
                    record(dir, function() pcall(handle.delete) end)
                end
                return handle
            end

            -- ms.mouse keeps one callback per button and returns nothing, so
            -- the undo has to find its own registration again. The identity
            -- check matters: if something else has since claimed the button,
            -- clearing it would disable a binding this plugin does not own.
            overrides.mouse = function(button, ...)
                local out = ms.mouse(button, ...)
                local mine = ms._mouseCallbacks and ms._mouseCallbacks[button]
                record(dir, function()
                    if mine and ms._mouseCallbacks
                        and ms._mouseCallbacks[button] == mine then
                        ms._mouseCallbacks[button] = nil
                    end
                end)
                return out
            end

            -- Same handle shape as ms.key, but the callback is per-direction
            -- rather than per-registration: deleting blindly would clear
            -- whatever registered last, so the undo checks it is still ours.
            overrides.scrollBind = function(direction, fn)
                local handle = ms.scrollBind(direction, fn)
                record(dir, function()
                    if ms._scrollCallbacks
                        and ms._scrollCallbacks[direction] == fn then
                        ms._scrollCallbacks[direction] = nil
                    end
                end)
                return handle
            end

            overrides.settings = subProxy(ms.settings, {
                define = function(def)
                    local out = ms.settings.define(def)
                    record(dir, function()
                        removeValue(ms._userSettingDefs, def)
                        local keys = {}
                        if type(def) == "table" then
                            if def.key then keys[#keys + 1] = def.key end
                            for _, sub in ipairs(def.items or {}) do
                                if type(sub) == "table" and sub.key then
                                    keys[#keys + 1] = sub.key
                                end
                            end
                        end
                        for _, k in ipairs(keys) do
                            if ms._userSettingIndex then ms._userSettingIndex[k] = nil end
                            if ms._userSettingVals  then ms._userSettingVals[k]  = nil end
                        end
                    end)
                    return out
                end,
            })

            overrides.tools = subProxy(ms.tools, {
                define = function(def)
                    local out = ms.tools.define(def)
                    record(dir, function()
                        if type(def) == "table" and def.id and ms._toolIndex then
                            ms._toolIndex[def.id] = nil
                        end
                        removeValue(ms._toolDefs, def)
                    end)
                    return out
                end,
            })

            return setmetatable({}, {
                __index = function(_, k)
                    local o = overrides[k]
                    if o ~= nil then return o end
                    return ms[k]
                end,
                __newindex = function(_, k, v) ms[k] = v end,
            })
        end
    -- END Recording Proxy --

    -- Load --
        -- Loads one plugin by bundle dir name ("Alpha.spoon"). Returns
        -- true, or false plus a message.
        --
        -- Nothing is verified here. Guardian refuses to reach ms_core at all
        -- if Spoons/ holds anything the ledger does not vouch for, so by the
        -- time this runs every bundle on disk arrived through install.
        ms.plugins.load = function(dir)
            if not (ms.package and ms.package.validSpoonName
                and ms.package.validSpoonName(dir)) then
                return false, "Invalid plugin name."
            end
            if ms.plugins.loaded[dir] then return true end

            local short = shortName(dir)
            local init  = _spoons .. "/" .. dir .. "/init.lua"
            if not hs.fs.attributes(init) then
                return false, "No init.lua in " .. dir .. "."
            end

            ms.plugins._undo[dir] = {}

            -- The environment the plugin sees. Reads fall through to _G, so
            -- hs and the standard library are all present; only `ms` is
            -- swapped. Writes go to _G, because a plugin declaring a global
            -- is doing something visible and should not get a private one.
            local env = setmetatable(
                { ms = makeProxy(dir) },
                { __index = _G, __newindex = _G }
            )

            -- require checks package.preload before searching the path, so
            -- this hands loadSpoon our chunk without reimplementing it.
            local prevPreload = package.preload[short]
            package.preload[short] = function()
                local chunk, err = loadfile(init, "t", env)
                if not chunk then error(err, 0) end
                return chunk(short, init)
            end

            local ok, err = pcall(function() return hs.loadSpoon(short) end)

            package.preload[short] = prevPreload

            if not ok then
                -- A plugin that threw halfway through may already have
                -- registered. Replay what it managed before giving up, or the
                -- failure leaves live binds nothing will ever clean up.
                ms.plugins.unload(dir, { quiet = true })
                ms.plugins.failed[dir] = tostring(err)
                return false, tostring(err)
            end

            ms.plugins.loaded[dir] = true
            ms.plugins.failed[dir] = nil
            return true
        end

        ms.plugins.loadAll = function()
            if not (ms.package and ms.package.listPlugins) then return end
            for _, p in ipairs(ms.package.listPlugins()) do
                if p.enabled and p.status == "ok" then
                    -- pcall per plugin: a third-party error costs that plugin,
                    -- not the rest of the boot.
                    local ok, err = ms.plugins.load(p.dir)
                    if not ok then
                        print("Plugin " .. p.dir .. " failed to load: " .. tostring(err))
                    end
                end
            end
        end
    -- END Load --

    -- Unload --
        -- Stops a plugin as far as it can be stopped in a live process.
        --
        -- Three steps, in order. The Spoon's own :stop() first, because it is
        -- the only one that knows about state this module never saw. Then the
        -- recorded undo list, newest first, so a plugin that registered and
        -- re-registered the same id unwinds in the order it wound up. Then the
        -- module caches, so re-enabling actually re-runs the file instead of
        -- handing back the warm copy require kept.
        ms.plugins.unload = function(dir, opts)
            opts = opts or {}
            if not (ms.package and ms.package.validSpoonName
                and ms.package.validSpoonName(dir)) then
                return false, "Invalid plugin name."
            end

            local short = shortName(dir)
            local obj   = _G.spoon and _G.spoon[short]

            if type(obj) == "table" and type(obj.stop) == "function" then
                local ok, err = pcall(function() obj:stop() end)
                if not ok and not opts.quiet then
                    print("Plugin " .. dir .. " stop() error: " .. tostring(err))
                end
            end

            local undo = ms.plugins._undo[dir] or {}
            for i = #undo, 1, -1 do
                local ok, err = pcall(undo[i])
                if not ok and not opts.quiet then
                    print("Plugin " .. dir .. " teardown error: " .. tostring(err))
                end
            end
            ms.plugins._undo[dir] = nil

            package.loaded[short] = nil
            if _G.spoon then _G.spoon[short] = nil end
            ms.plugins.loaded[dir] = nil

            -- The settings panel may have just lost rows, and the bind list
            -- may have just lost entries.
            if ms.ui and ms.ui.markDirty then pcall(ms.ui.markDirty) end
            return true
        end
    -- END Unload --

    -- Apply --
        -- Brings the running set in line with what is enabled on disk. This is
        -- what the panel's toggle calls: it does not need to know which way
        -- the switch went, only that the answer may have changed.
        ms.plugins.apply = function()
            if not (ms.package and ms.package.listPlugins) then return end
            for _, p in ipairs(ms.package.listPlugins()) do
                local running = ms.plugins.loaded[p.dir] == true
                local want    = p.enabled and p.status == "ok"
                if want and not running then
                    ms.plugins.load(p.dir)
                elseif running and not want then
                    ms.plugins.unload(p.dir)
                end
            end
            -- A plugin removed from disk is gone from listPlugins entirely,
            -- so the loop above never sees it. Sweep anything still marked
            -- running whose bundle no longer exists.
            for dir in pairs(ms.plugins.loaded) do
                if not hs.fs.attributes(_spoons .. "/" .. dir) then
                    ms.plugins.unload(dir, { quiet = true })
                end
            end
        end
    -- END Apply --

end
-- END ms_plugins --
