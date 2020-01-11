-- Loads Lua libraries from *.a files
-- Use arlib.require(<lib.a>, <file.lua>) as a stand-in for require()
local ar = require "ar"

local arlib = {}

-- I wrote this a long time ago, when I actually knew what the point of this function is
function arlib.loadAPIs(path, ...)
    local arch = ar.load(path)
    local lib = {}
    for k,v in pairs(arch) do
        local env = setmetatable({}, {__index = _ENV})
        local func, err = load(v.data, v.name, "t", env)
        if not func then return false, err end
        local res = func(...)
        if type(res) == "table" then for k,v in pairs(res) do lib[k] = v end
        elseif type(res) == "function" then lib[string.sub(v.name, string.find(v.name, ".") - 1)] = res
        else for k,v in pairs(env) do lib[k] = v end end
    end
    _G[string.sub(path, string.find(path, ".") - 1)] = lib
    return true
end

local sentinel = {}
local function loadfrompkg(pkg, name)
    for _,v in ipairs(pkg) do if v.name == name or v.name == name .. ".lua" then
        local fnFile, sError = load(v.data, "@" .. name, "t", setmetatable({require = function(name)
            if type( name ) ~= "string" then
                error( "bad argument #1 (expected string, got " .. type( name ) .. ")", 2 )
            end
            if package.loaded[name] == sentinel then
                error("Loop detected requiring '" .. name .. "'", 0)
            end
            if package.loaded[name] then
                return package.loaded[name]
            end
        
            local sError = "Error loading module '" .. name .. "':"
            local loader, err = loadfrompkg(pkg, name)
            if loader then
                package.loaded[name] = sentinel
                local result = loader( err )
                if result ~= nil then
                    package.loaded[name] = result
                    return result
                else
                    package.loaded[name] = true
                    return true
                end
            else
                sError = sError .. "\n" .. err
            end
            error(sError, 2)
        end}, {__index = _ENV}))
        if fnFile then
            return fnFile, name
        else
            return nil, sError
        end
    end end
end
local function searcher( name, name2 )
    local sError = ""
    for pattern in string.gmatch(package.path:gsub("%.lua", "%.a"), "[^;]+") do
        local sPath = string.gsub(pattern, "%?", name)
        if sPath:sub(1,1) ~= "/" then
            sPath = fs.combine(shell.path(), sPath)
        end
        if fs.exists(sPath) and not fs.isDir(sPath) then
            local pkg = ar.load(sPath)
            if pkg then
                return loadfrompkg(pkg, name2)
            else
                return nil, "could not load archive"
            end
        else
            if #sError > 0 then
                sError = sError .. "\n"
            end
            sError = sError .. "no file '" .. sPath .. "'!"
        end
    end
    return nil, sError
end
function arlib.require(path, name)
    if type( path ) ~= "string" then
        error( "bad argument #1 (expected string, got " .. type( path ) .. ")", 2 )
    end
    if type( name ) ~= "string" then
        error( "bad argument #2 (expected string, got " .. type( name ) .. ")", 2 )
    end
    if package.loaded[name] == sentinel then
        error("Loop detected requiring '" .. name .. "'", 0)
    end
    if package.loaded[name] then
        return package.loaded[name]
    end

    local sError = "Error loading module '" .. name .. "':"
    local loader, err = searcher(path, name)
    if loader then
        package.loaded[name] = sentinel
        local result = loader( err )
        if result ~= nil then
            package.loaded[name] = result
            return result
        else
            package.loaded[name] = true
            return true
        end
    else
        sError = sError .. "\n" .. err
    end
    error(sError, 2)
end

return arlib