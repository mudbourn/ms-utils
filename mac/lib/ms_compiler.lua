-- ms_compiler — Visual Macro Compiler --
    return function(ms)

        local home       = os.getenv("HOME")
        local dataDir    = home .. "/.hammerspoon/data"
        local jsonPath   = dataDir .. "/ms_macros_visual.json"
        local luaPath    = dataDir .. "/ms_macros_visual.lua"

        ms.compiler = {}

        -- Helpers --
            local function serialize(val)
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
                local ms_val = (step.params and step.params.ms) or 100
                return indent(lvl) .. "ms.wait(" .. tostring(ms_val) .. ")"
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
                return indent(lvl) .. "ms.cam(" .. tostring(p.dx or 0) .. ", " .. tostring(p.dy or 0) .. ")"
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
                parts[#parts + 1] = tostring(p.x or 0)
                parts[#parts + 1] = tostring(p.y or 0)
                return indent(lvl) .. "ms.Mouse(" .. table.concat(parts, ", ") .. ")"
            end

            emitters["var_set"] = function(step, lvl)
                local p = step.params or {}
                local name  = p.name or "v"
                local value = serialize(p.value)
                return indent(lvl) .. "local " .. name .. " = " .. value
            end

            emitters["var_add"] = function(step, lvl)
                local p = step.params or {}
                local name   = p.name or "v"
                local amount = p.amount or 1
                return indent(lvl) .. name .. " = " .. name .. " + " .. tostring(amount)
            end

            emitters["var_sub"] = function(step, lvl)
                local p = step.params or {}
                local name   = p.name or "v"
                local amount = p.amount or 1
                return indent(lvl) .. name .. " = " .. name .. " - " .. tostring(amount)
            end

            emitters["var_mul"] = function(step, lvl)
                local p = step.params or {}
                local name   = p.name or "v"
                local amount = p.amount or 2
                return indent(lvl) .. name .. " = " .. name .. " * " .. tostring(amount)
            end

            local _flowCounter = 0

            emitters["if"] = function(step, lvl)
                local cond = step.condition or "true"
                local lines = {}
                lines[#lines + 1] = indent(lvl) .. "if " .. cond .. " then"
                lines[#lines + 1] = indent(lvl + 1) .. "ms.log('if', '" .. cond:gsub("'", "\\'") .. "', true)"
                if step.then_steps then
                    for _, s in ipairs(step.then_steps) do
                        lines[#lines + 1] = emitStep(s, lvl + 1)
                    end
                end
                if step.else_steps then
                    lines[#lines + 1] = indent(lvl) .. "else"
                    lines[#lines + 1] = indent(lvl + 1) .. "ms.log('if', '" .. cond:gsub("'", "\\'") .. "', false)"
                    for _, s in ipairs(step.else_steps) do
                        lines[#lines + 1] = emitStep(s, lvl + 1)
                    end
                end
                lines[#lines + 1] = indent(lvl) .. "end"
                return table.concat(lines, "\n")
            end

            emitters["for"] = function(step, lvl)
                local p = step.params or {}
                local varName = p.var or "i"
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
                local cond = step.condition or "true"
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
                local cond = step.condition or "true"
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
