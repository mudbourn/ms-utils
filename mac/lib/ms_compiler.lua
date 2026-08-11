-- ms_compiler — Visual Macro Compiler --
    return function(ms)

        local home       = os.getenv("HOME")
        local dataDir    = home .. "/.hammerspoon/data"
        local jsonPath   = dataDir .. "/ms_macros_visual.json"
        local luaPath    = dataDir .. "/ms_macros_visual.lua"

        ms.compiler = {}

        -- Helpers --
            -- A parameter can be wired to a live "tool" (an authored setting)
            -- instead of a literal. The builder sends such a binding as the
            -- table { __toolRef = "settingKey" }; it compiles to a
            -- ms.settings.get("settingKey") call so the macro reads the tool's
            -- current value at run time — the whole point of the feature is to
            -- make a macro configurable from the Settings panel without editing
            -- and reloading its source. Anything else is not a binding.
            -- The key is validated as an identifier so a hostile JSON payload
            -- can never break out of the string into arbitrary Lua.
            local function toolRef(val)
                if type(val) == "table"
                    and type(val.__toolRef) == "string"
                    and val.__toolRef:match("^[%a_][%w_]*$") then
                    return 'ms.settings.get("' .. val.__toolRef .. '")'
                end
                return nil
            end

            local function serialize(val)
                local ref = toolRef(val)
                if ref then return ref end
                local t = type(val)
                if t == "string"  then return string.format("%q", val) end
                if t == "number"  then return tostring(val) end
                if t == "boolean" then return tostring(val) end
                if t == "nil"     then return "nil" end
                if t == "table" then
                    local parts = {}
                    local isList = (#val > 0)
                    if isList then
                        for _, v in ipairs(val) do
                            parts[#parts + 1] = serialize(v)
                        end
                    else
                        for k, v in pairs(val) do
                            local key
                            if type(k) == "string" and k:match("^%a[%w_]*$") then
                                key = k
                            else
                                key = "[" .. serialize(k) .. "]"
                            end
                            parts[#parts + 1] = key .. " = " .. serialize(v)
                        end
                    end
                    return "{" .. table.concat(parts, ", ") .. "}"
                end
                return tostring(val)
            end

            -- An unset identifier arrives from the builder as "" (not nil),
            -- which is truthy in Lua — `p.name or "v"` would keep the empty
            -- string and emit invalid code (`local  = 1`). Fall back explicitly.
            local function ident(v, default)
                if v == nil or v == "" then return default end
                return v
            end

            -- A numeric argument that may instead be a tool binding. The plain
            -- numeric emitters (waits, camera deltas, coordinates) drop values
            -- in with tostring() rather than serialize(), so they need their
            -- own funnel to honour a binding. Returns a Lua expression string.
            local function numArg(v, default)
                local ref = toolRef(v)
                if ref then return ref end
                if type(v) == "number" then return tostring(v) end
                if type(v) == "string" and v ~= "" and tonumber(v) then return v end
                return tostring(default)
            end

            local function buildArgs(params, argOrder)
                if not params or not argOrder then return "" end
                local parts = {}
                for _, key in ipairs(argOrder) do
                    local v = params[key]
                    if v ~= nil then
                        parts[#parts + 1] = serialize(v)
                    end
                end
                return table.concat(parts, ", ")
            end
        -- END Helpers --

        -- Emitters --
            local INDENT = "    "

            local function indent(n)
                local s = ""
                for _ = 1, n do s = s .. INDENT end
                return s
            end

            local emitStep

            local emitters = {}

            emitters["ms.type"] = function(step, lvl)
                local p = step.params or {}
                local args
                if p.mods and #p.mods > 0 then
                    args = serialize(p.key) .. ", " .. serialize(p.mods)
                else
                    args = serialize(p.key)
                end
                return indent(lvl) .. "ms.type(" .. args .. ")"
            end

            emitters["ms.wait"] = function(step, lvl)
                local p = step.params or {}
                return indent(lvl) .. "ms.wait(" .. numArg(p.ms, 100) .. ")"
            end

            emitters["ms.copy"] = function(step, lvl)
                local text = (step.params and step.params.text) or ""
                return indent(lvl) .. "ms.copy(" .. serialize(text) .. ")"
            end

            emitters["ms.paste"] = function(step, lvl)
                return indent(lvl) .. "ms.paste()"
            end

            emitters["ms.press"] = function(step, lvl)
                local p = step.params or {}
                local args
                if p.mods and #p.mods > 0 then
                    args = serialize(p.key) .. ", " .. serialize(p.mods)
                else
                    args = serialize(p.key)
                end
                return indent(lvl) .. "ms.press(" .. args .. ")"
            end

            emitters["ms.hold"] = function(step, lvl)
                local p = step.params or {}
                local args
                if p.mods and #p.mods > 0 then
                    args = serialize(p.key) .. ", " .. serialize(p.mods)
                else
                    args = serialize(p.key)
                end
                return indent(lvl) .. "ms.hold(" .. args .. ")"
            end

            emitters["ms.release"] = function(step, lvl)
                local key = (step.params and step.params.key) or ""
                return indent(lvl) .. "ms.release(" .. serialize(key) .. ")"
            end

            emitters["ms.cam"] = function(step, lvl)
                local p = step.params or {}
                return indent(lvl) .. "ms.cam(" .. numArg(p.dx, 0) .. ", " .. numArg(p.dy, 0) .. ")"
            end

            emitters["ms.cam.rebalance"] = function(step, lvl)
                return indent(lvl) .. "ms.cam.rebalance()"
            end

            emitters["ms.cam.reset"] = function(step, lvl)
                return indent(lvl) .. "ms.cam.reset()"
            end

            emitters["ms.scroll"] = function(step, lvl)
                local p = step.params or {}
                local dir = serialize(p.direction or "up")
                -- A bound clicks count is always emitted (its value is unknown
                -- at compile time); a literal one is only emitted when > 1, the
                -- pre-binding behaviour.
                if toolRef(p.clicks) then
                    return indent(lvl) .. "ms.scroll(" .. dir .. ", " .. numArg(p.clicks, 1) .. ")"
                end
                if p.clicks and p.clicks > 1 then
                    return indent(lvl) .. "ms.scroll(" .. dir .. ", " .. tostring(p.clicks) .. ")"
                end
                return indent(lvl) .. "ms.scroll(" .. dir .. ")"
            end

            emitters["ms.alert"] = function(step, lvl)
                local p = step.params or {}
                local args = serialize(p.message or p.msg or "")
                if p.duration then args = args .. ", " .. tostring(p.duration) end
                return indent(lvl) .. "ms.alert(" .. args .. ")"
            end

            emitters["ms.Mouse"] = function(step, lvl)
                local p = step.params or {}
                local parts = {}
                parts[#parts + 1] = serialize(p.operation or "Click")
                parts[#parts + 1] = serialize(p.button or "Left")
                parts[#parts + 1] = serialize(p.reference or "Mouse")
                parts[#parts + 1] = numArg(p.x, 0)
                parts[#parts + 1] = numArg(p.y, 0)
                return indent(lvl) .. "ms.Mouse(" .. table.concat(parts, ", ") .. ")"
            end

            emitters["var_set"] = function(step, lvl)
                local p = step.params or {}
                local name  = ident(p.name, "v")
                local value = serialize(p.value)
                return indent(lvl) .. "local " .. name .. " = " .. value
            end

            emitters["var_add"] = function(step, lvl)
                local p = step.params or {}
                local name   = ident(p.name, "v")
                return indent(lvl) .. name .. " = " .. name .. " + " .. numArg(p.amount, 1)
            end

            emitters["var_sub"] = function(step, lvl)
                local p = step.params or {}
                local name   = ident(p.name, "v")
                return indent(lvl) .. name .. " = " .. name .. " - " .. numArg(p.amount, 1)
            end

            emitters["var_mul"] = function(step, lvl)
                local p = step.params or {}
                local name   = ident(p.name, "v")
                return indent(lvl) .. name .. " = " .. name .. " * " .. numArg(p.amount, 2)
            end

            local _flowCounter = 0

            -- The visual canvas (ToolCanvas) is the canonical shape: it stores
            -- branches as step.then / step.else / step.body and the condition in
            -- step.params.condition. Older/hand-authored JSON used step.condition
            -- and step.then_steps / step.else_steps. Read both, canvas first.
            local function stepCond(step)
                local c = step.condition
                if c == nil then c = step.params and step.params.condition end
                -- An empty string is truthy in Lua and would emit `if  then`;
                -- fall back to `true` so an unset condition is still valid code.
                if c == nil or c == "" then c = "true" end
                return c
            end
            -- `then`/`else` are reserved words, so the canvas keys must be
            -- reached with bracket syntax rather than dot access.
            local function thenSteps(step) return step["then"] or step.then_steps end
            local function elseSteps(step) return step["else"] or step.else_steps end

            emitters["if"] = function(step, lvl)
                local cond = stepCond(step)
                local lines = {}
                lines[#lines + 1] = indent(lvl) .. "if " .. cond .. " then"
                lines[#lines + 1] = indent(lvl + 1) .. "ms.log('if', '" .. cond:gsub("'", "\\'") .. "', true)"
                local ts = thenSteps(step)
                if ts then
                    for _, s in ipairs(ts) do
                        lines[#lines + 1] = emitStep(s, lvl + 1)
                    end
                end
                local es = elseSteps(step)
                if es and #es > 0 then
                    lines[#lines + 1] = indent(lvl) .. "else"
                    lines[#lines + 1] = indent(lvl + 1) .. "ms.log('if', '" .. cond:gsub("'", "\\'") .. "', false)"
                    for _, s in ipairs(es) do
                        lines[#lines + 1] = emitStep(s, lvl + 1)
                    end
                end
                lines[#lines + 1] = indent(lvl) .. "end"
                return table.concat(lines, "\n")
            end

            emitters["for"] = function(step, lvl)
                local p = step.params or {}
                local varName = ident(p.var, "i")
                local from    = p.from or 1
                local to      = p.to or 1
                local stepVal = p.step
                local lines = {}
                local forArgs = tostring(from) .. ", " .. tostring(to)
                if stepVal then forArgs = forArgs .. ", " .. tostring(stepVal) end
                _flowCounter = _flowCounter + 1
                local fc = "_fc" .. _flowCounter
                lines[#lines + 1] = indent(lvl) .. "local " .. fc .. " = 0"
                lines[#lines + 1] = indent(lvl) .. "for " .. varName .. " = " .. forArgs .. " do"
                lines[#lines + 1] = indent(lvl + 1) .. fc .. " = " .. fc .. " + 1"
                if step.body then
                    for _, s in ipairs(step.body) do
                        lines[#lines + 1] = emitStep(s, lvl + 1)
                    end
                end
                lines[#lines + 1] = indent(lvl) .. "end"
                lines[#lines + 1] = indent(lvl) .. "ms.log('for', '" .. varName .. "=" .. forArgs .. "', " .. fc .. ")"
                return table.concat(lines, "\n")
            end

            emitters["while"] = function(step, lvl)
                local cond = stepCond(step)
                local lines = {}
                _flowCounter = _flowCounter + 1
                local fc = "_fc" .. _flowCounter
                lines[#lines + 1] = indent(lvl) .. "local " .. fc .. " = 0"
                lines[#lines + 1] = indent(lvl) .. "while " .. cond .. " do"
                lines[#lines + 1] = indent(lvl + 1) .. fc .. " = " .. fc .. " + 1"
                if step.body then
                    for _, s in ipairs(step.body) do
                        lines[#lines + 1] = emitStep(s, lvl + 1)
                    end
                end
                lines[#lines + 1] = indent(lvl) .. "end"
                lines[#lines + 1] = indent(lvl) .. "ms.log('while', '" .. cond:gsub("'", "\\'") .. "', " .. fc .. ")"
                return table.concat(lines, "\n")
            end

            emitters["repeat"] = function(step, lvl)
                local cond = stepCond(step)
                local lines = {}
                _flowCounter = _flowCounter + 1
                local fc = "_fc" .. _flowCounter
                lines[#lines + 1] = indent(lvl) .. "local " .. fc .. " = 0"
                lines[#lines + 1] = indent(lvl) .. "repeat"
                lines[#lines + 1] = indent(lvl + 1) .. fc .. " = " .. fc .. " + 1"
                if step.body then
                    for _, s in ipairs(step.body) do
                        lines[#lines + 1] = emitStep(s, lvl + 1)
                    end
                end
                lines[#lines + 1] = indent(lvl) .. "until " .. cond
                lines[#lines + 1] = indent(lvl) .. "ms.log('repeat', '" .. cond:gsub("'", "\\'") .. "', " .. fc .. ")"
                return table.concat(lines, "\n")
            end

            emitters["comment"] = function(step, lvl)
                local text = (step.params and step.params.text) or ""
                return indent(lvl) .. "-- " .. text
            end

            emitters["code"] = function(step, lvl)
                local src = (step.params and step.params.source) or ""
                local lines = {}
                for line in src:gmatch("([^\n]*)\n?") do
                    if line ~= "" then
                        lines[#lines + 1] = indent(lvl) .. line
                    end
                end
                return table.concat(lines, "\n")
            end

            local function genericEmitter(step, lvl)
                local action = step.action
                local p = step.params or {}
                if p.args then
                    local parts = {}
                    for _, v in ipairs(p.args) do
                        parts[#parts + 1] = serialize(v)
                    end
                    return indent(lvl) .. action .. "(" .. table.concat(parts, ", ") .. ")"
                end
                local parts = {}
                for k, v in pairs(p) do
                    parts[#parts + 1] = k .. "=" .. serialize(v)
                end
                if #parts == 0 then
                    return indent(lvl) .. action .. "()"
                end
                return indent(lvl) .. action .. "(" .. serialize(p) .. ")"
            end

            emitStep = function(step, lvl)
                lvl = lvl or 1
                local action = step.action
                if not action then return indent(lvl) .. "-- [empty step]" end
                local emitter = emitters[action]
                if emitter then
                    return emitter(step, lvl)
                end
                return genericEmitter(step, lvl)
            end
        -- END Emitters --

        -- Compile --
            ms.compiler.compile = function(macroDef)
                assert(type(macroDef) == "table", "ms.compiler.compile: macroDef must be a table")
                assert(type(macroDef.id) == "string", "ms.compiler.compile: macroDef.id must be a string")

                local id     = macroDef.id
                local name   = macroDef.name or id
                local author = macroDef.author or "Visual"
                local group  = macroDef.group or "visual"
                local steps  = macroDef.steps or {}
                local bind   = macroDef.bind or {}
                local cooldown = macroDef.cooldown

                assert(id:match("^[%a_][%w_]*$"),
                    "ms.compiler.compile: invalid macro id '" .. id .. "' (must be a valid Lua identifier)")

                local fnName = id .. "Function"
                local lines = {}

                lines[#lines + 1] = "local " .. fnName .. " = ms.fn(function()"
                lines[#lines + 1] = indent(1) .. "local t = 100"
                for _, step in ipairs(steps) do
                    lines[#lines + 1] = emitStep(step, 1)
                end
                lines[#lines + 1] = 'end, "' .. name .. '")'
                lines[#lines + 1] = ""

                lines[#lines + 1] = 'ms.bind.define("' .. id .. '", ' .. fnName .. ", {"
                lines[#lines + 1] = indent(1) .. 'group   = "' .. group .. '",'
                lines[#lines + 1] = indent(1) .. 'label   = "' .. name .. '",'
                if cooldown then
                    lines[#lines + 1] = indent(1) .. "cooldown = " .. tostring(cooldown) .. ","
                end
                if bind.type or bind.key then
                    lines[#lines + 1] = indent(1) .. "default = {"
                    lines[#lines + 1] = indent(2) .. 'type = "' .. (bind.type or "key") .. '",'
                    if bind.mods and #bind.mods > 0 then
                        local modParts = {}
                        for _, m in ipairs(bind.mods) do modParts[#modParts + 1] = '"' .. m .. '"' end
                        lines[#lines + 1] = indent(2) .. "mods = {" .. table.concat(modParts, ", ") .. "},"
                    else
                        lines[#lines + 1] = indent(2) .. "mods = {},"
                    end
                    if bind.key then
                        lines[#lines + 1] = indent(2) .. 'key  = "' .. bind.key .. '",'
                    end
                    lines[#lines + 1] = indent(1) .. "},"
                end
                lines[#lines + 1] = "})"

                return table.concat(lines, "\n")
            end
        -- END Compile --

        -- Write File --
            ms.compiler._writeFile = function(sources)
                local lines = {}
                lines[#lines + 1] = "-- ══════════════════════════════════════════════════════════════"
                lines[#lines + 1] = "-- AUTO-GENERATED by ms.compiler — DO NOT EDIT BY HAND"
                lines[#lines + 1] = "-- Source: data/ms_macros_visual.json"
                lines[#lines + 1] = "-- Rebuild: ms.compiler.rebuild()"
                lines[#lines + 1] = "-- ══════════════════════════════════════════════════════════════"
                lines[#lines + 1] = ""
                lines[#lines + 1] = "-- Creator Credits --"
                lines[#lines + 1] = "    ms.macroMeta = {"
                lines[#lines + 1] = '        name    = "Visual Macros",'
                lines[#lines + 1] = '        author  = "ms.compiler"'
                lines[#lines + 1] = "    }"
                lines[#lines + 1] = "-- END Creator Credits --"
                lines[#lines + 1] = ""

                for _, entry in ipairs(sources) do
                    lines[#lines + 1] = "-- " .. entry.id .. " --"
                    lines[#lines + 1] = entry.source
                    lines[#lines + 1] = "-- END " .. entry.id .. " --"
                    lines[#lines + 1] = ""
                end

                local out = table.concat(lines, "\n") .. "\n"

                os.execute("mkdir -p '" .. dataDir .. "'")

                local f = io.open(luaPath, "w")
                if not f then
                    error("ms.compiler: cannot open " .. luaPath .. " for writing")
                end
                f:write(out)
                f:close()

                return true
            end
        -- END Write File --

        -- Rebuild --
            ms.compiler.rebuild = function()
                local f = io.open(jsonPath, "r")
                if not f then
                    error("ms.compiler.rebuild: cannot open " .. jsonPath)
                end
                local raw = f:read("*all")
                f:close()

                local ok, data = pcall(hs.json.decode, raw)
                if not ok or type(data) ~= "table" then
                    error("ms.compiler.rebuild: invalid JSON in " .. jsonPath .. ": " .. tostring(data))
                end

                local macros = data.macros or {}
                local sources = {}
                local count = 0

                for id, macroDef in pairs(macros) do
                    macroDef.id = id
                    local srcOk, src = pcall(ms.compiler.compile, macroDef)
                    if not srcOk then
                        print("ms.compiler: compile error for '" .. id .. "': " .. tostring(src))
                        src = "-- [COMPILE ERROR for " .. id .. "]\n"
                        .. "-- " .. tostring(src) .. "\n"
                    end
                    sources[#sources + 1] = { id = id, source = src }
                    count = count + 1
                end

                table.sort(sources, function(a, b) return a.id < b.id end)

                ms.compiler._writeFile(sources)

                print("ms.compiler.rebuild: compiled " .. count .. " macro(s) → " .. luaPath)
                return count
            end
        -- END Rebuild --

        -- Load --
            ms.compiler.load = function()
                if not hs.fs.attributes(luaPath) then
                    print("ms.compiler.load: no compiled file at " .. luaPath .. " — skipping")
                    return false
                end

                local f = io.open(luaPath, "r")
                if not f then
                    print("ms.compiler.load: cannot open " .. luaPath)
                    return false
                end
                local rawSrc = f:read("*all")
                f:close()

                if ms.auditMacros then
                    local auditErrs = ms.auditMacros(rawSrc)
                    if #auditErrs > 0 then
                        local msg = "ms_macros_visual.lua failed security audit ("
                            .. #auditErrs .. " violation"
                            .. (#auditErrs > 1 and "s" or "") .. "):\n"
                        for _, e in ipairs(auditErrs) do
                            msg = msg .. "  • " .. e .. "\n"
                        end
                        print(msg)
                        ms.alert("Visual macros audit failed — see console", 6)
                        return false
                    end
                end

                local sandbox = ms._macroSandbox
                if not sandbox then
                    error("ms.compiler.load: macro sandbox not initialized")
                end

                local chunk, loadErr
                if _VERSION and _VERSION >= "Lua 5.2" or not setfenv then
                    chunk, loadErr = load(rawSrc, "@ms_macros_visual.lua", "bt", sandbox)
                else
                    chunk, loadErr = loadstring(rawSrc, "@ms_macros_visual.lua")
                    if chunk then setfenv(chunk, sandbox) end
                end
                if not chunk then
                    print("ms.compiler.load: failed to load: " .. tostring(loadErr))
                    ms.alert("Visual macros load error — see console", 6)
                    return false
                end

                local ok, runErr = pcall(chunk)
                if not ok then
                    print("ms.compiler.load: execution error: " .. tostring(runErr))
                    ms.alert("Visual macros runtime error — see console", 6)
                    return false
                end

                print("ms.compiler.load: visual macros loaded into sandbox")
                return true
            end
        -- END Load --

        -- Write --
            ms.compiler.write = function(macroId, macroDef)
                assert(type(macroId) == "string", "ms.compiler.write: macroId must be a string")
                assert(type(macroDef) == "table",  "ms.compiler.write: macroDef must be a table")

                macroDef.id = macroId

                local data = { macros = {} }
                local f = io.open(jsonPath, "r")
                if f then
                    local raw = f:read("*all"); f:close()
                    local ok, parsed = pcall(hs.json.decode, raw)
                    if ok and type(parsed) == "table" then
                        data = parsed
                        data.macros = data.macros or {}
                    end
                end

                data.macros[macroId] = {
                    name     = macroDef.name,
                    author   = macroDef.author,
                    group    = macroDef.group,
                    bind     = macroDef.bind,
                    steps    = macroDef.steps,
                    cooldown = macroDef.cooldown,
                }

                os.execute("mkdir -p '" .. dataDir .. "'")
                local jf = io.open(jsonPath, "w")
                if not jf then
                    error("ms.compiler.write: cannot open " .. jsonPath .. " for writing")
                end
                jf:write(hs.json.encode(data, true))
                jf:close()

                ms.compiler.rebuild()

                print("ms.compiler.write: saved '" .. macroId .. "' to JSON and recompiled")
                return true
            end
        -- END Write --

        -- Delete --
            ms.compiler.delete = function(macroId)
                assert(type(macroId) == "string", "ms.compiler.delete: macroId must be a string")

                local f = io.open(jsonPath, "r")
                if not f then
                    print("ms.compiler.delete: no JSON file found")
                    return false
                end
                local raw = f:read("*all"); f:close()
                local ok, data = pcall(hs.json.decode, raw)
                if not ok or type(data) ~= "table" then
                    error("ms.compiler.delete: invalid JSON")
                end

                data.macros = data.macros or {}
                if not data.macros[macroId] then
                    print("ms.compiler.delete: macro '" .. macroId .. "' not found")
                    return false
                end

                data.macros[macroId] = nil

                local jf = io.open(jsonPath, "w")
                if not jf then
                    error("ms.compiler.delete: cannot write JSON")
                end
                jf:write(hs.json.encode(data, true))
                jf:close()

                ms.compiler.rebuild()
                print("ms.compiler.delete: removed '" .. macroId .. "' and recompiled")
                return true
            end
        -- END Delete --

        -- List --
            ms.compiler.list = function()
                local f = io.open(jsonPath, "r")
                if not f then return {} end
                local raw = f:read("*all"); f:close()
                local ok, data = pcall(hs.json.decode, raw)
                if not ok or type(data) ~= "table" or type(data.macros) ~= "table" then
                    return {}
                end
                local ids = {}
                for id in pairs(data.macros) do ids[#ids + 1] = id end
                table.sort(ids)
                return ids
            end
        -- END List --

        -- Get --
            ms.compiler.get = function(macroId)
                local f = io.open(jsonPath, "r")
                if not f then return nil end
                local raw = f:read("*all"); f:close()
                local ok, data = pcall(hs.json.decode, raw)
                if not ok or type(data) ~= "table" or type(data.macros) ~= "table" then
                    return nil
                end
                local def = data.macros[macroId]
                if def then def.id = macroId end
                return def
            end
        -- END Get --

        -- Paths --
            ms.compiler.paths = {
                json = jsonPath,
                lua  = luaPath,
                data = dataDir,
            }
        -- END Paths --
    end
-- END ms_compiler --
