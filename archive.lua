-- Archive library for CC
local LibDeflate = require "LibDeflate"

compression_level = nil -- compression level (nil for default)

local function split(inputstr, sep)
    if sep == nil then
        sep = "%s"
    end
    local t={}
    for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
        table.insert(t, str)
    end
    return t
end

local function getComponent(tab, keys)
    if #keys == 0 then return tab end
    local k = table.remove(keys, 1)
    if tab[k] == nil then return nil
    elseif type(tab[k]) ~= "table" then return tab[k]
    elseif k == "." then return getComponent(tab, keys)
    else return getComponent(tab[k], keys) end
end

local function extract(data, path)
    if string.sub(path, 1, 1) == "/" then path = string.sub(path, 2) end
    fs.makeDir(path)
    for k,v in pairs(data) do
        if type(v) == "table" then extract(v, path .. "/" .. k) else
            local file = fs.open(path .. "/" .. k, "wb")
            for s in string.gmatch(v, ".") do file.write(string.byte(s)) end
            file.close()
        end
    end
end

local function import(path)
    local retval = {}
    if path == nil then error("Path is nil", 2) end
    if not fs.isDir(path) then error(path .. ": Not a directory", 2) end
    for k,v in pairs(fs.list(path)) do
        if fs.isDir(path .. "/" .. v) then retval[v] = import(path .. "/" .. v) else
            local file = fs.open(path .. "/" .. v, "rb")
            local r = ""
            local b = file.read()
            while b ~= nil do
                r = r .. string.char(b)
                b = file.read()
            end
            file.close()
            retval[v] = r
        end
    end
    return retval
end

local function create(data)
    local retval = {}
    retval.data = data

    function retval.write(path)
        local str = LibDeflate:CompressGzip(textutils.serialize(retval.data), compression_level and {level=compression_level})
        local file = fs.open(path, "wb")
        for s in string.gmatch(str, ".") do file.write(string.byte(s)) end
        file.close()
    end

    function retval.extract(path) extract(retval.data, path) end

    function retval.list(path)
        if string.sub(path, 1, 1) == "/" then path = string.sub(path, 2) end
        local dir = getComponent(retval.data, split(path, "/"))
        if type(dir) ~= "table" then error(path .. ": Directory not found", 2) end
        local retval = {}
        for k,v in pairs(dir) do table.insert(retval, k) end
        return retval
    end

    function retval.exists(path)
        if string.sub(path, 1, 1) == "/" then path = string.sub(path, 2) end
        return getComponent(retval.data, split(path, "/")) ~= nil
    end

    function retval.isDir(path)
        if string.sub(path, 1, 1) == "/" then path = string.sub(path, 2) end
        return type(getComponent(retval.data, split(path, "/"))) == "table"
    end

    function retval.isReadOnly() return false end

    function retval.getSize(path)
        if string.sub(path, 1, 1) == "/" then path = string.sub(path, 2) end
        local file = getComponent(retval.data, split(path, "/"))
        if type(file) ~= "string" then error(path .. ": File not found", 2) end
        return string.len(file)
    end

    function retval.getFreeSpace() return math.huge end

    function retval.makeDir(path)
        if string.sub(path, 1, 1) == "/" then path = string.sub(path, 2) end
        local dir = getComponent(retval.data, split(fs.getDir(path), "/"))
        if type(dir) ~= "table" then error(fs.getDir(path) .. ": Directory not found", 2) end
        dir[fs.getName(path)] = {}
    end

    function retval.move(path, toPath)
        retval.copy(path, toPath, 1)
        retval.delete(path, 1)
    end

    function retval.copy(path, toPath, offset)
        offset = offset or 0
        if string.sub(path, 1, 1) == "/" then path = string.sub(path, 2 + offset) end
        local file = getComponent(retval.data, split(path, "/"))
        if type(file) ~= "string" then error(path .. ": File not found", 2 + offset) end
        local toDir = getComponent(retval.data, split(fs.getDir(toPath), "/"))
        if type(toDir) ~= "table" then error(fs.getDir(toPath) .. ": Directory not found", 2 + offset) end
        toDir[fs.getName(toPath)] = file
    end

    function retval.delete(path, offset)
        offset = offset or 0
        if string.sub(path, 1, 1) == "/" then path = string.sub(path, 2) end
        local fromDir = getComponent(retval.data, split(fs.getDir(path), "/"))
        if type(fromDir) ~= "table" then error(fs.getDir(path) .. ": Directory not found", 2 + offset) end
        fromDir[fs.getName(path)] = nil
    end

    function retval.open(path, mode)
        if string.sub(path, 1, 1) == "/" then path = string.sub(path, 2) end
        local file = getComponent(retval.data, split(path, "/"))
        if type(file) ~= "string" and not string.find(mode, "a") then error(path .. ": File not found", 2) end
        if string.find(mode, "a") then file = "" end
        local retval = {close = function() if retval.flush ~= nil then retval.flush() end end}
        local pos = string.find(mode, "a") and string.len(file) or 1
        if string.find(mode, "b") then
            if string.find(mode, "r") then
                retval.read = function()
                    pos = pos + 1
                    return string.byte(string.sub(file, pos - 1, pos - 1))
                end
            elseif string.find(mode, "w") or string.find(mode, "a") then
                retval.write = function(c)
                    if pos > string.len(file) then file = file .. string.char(c)
                    else file = string.sub(file, 1, pos - 1) .. string.char(c) .. string.sub(file, pos + 1) end
                    pos = pos + 1
                end
                retval.flush = function()
                    local dir = getComponent(retval.data, split(fs.getDir(path), "/"))
                    dir[fs.getName(path)] = file
                end
            end
        else
            if string.find(mode, "r") then
                retval.readLine = function()
                    if pos > string.len(file) then return nil end
                    local retval = ""
                    local c = string.sub(file, pos, pos)
                    pos = pos + 1
                    while c ~= "\n" and pos <= string.len(file) do
                        retval = retval .. c
                        c = string.sub(file, pos, pos)
                        pos = pos + 1
                    end
                    return retval
                end
                retval.readAll = function()
                    if pos > string.len(file) then return nil end
                    pos = string.len(file) + 1
                    return file
                end
            elseif string.find(mode, "w") or string.find(mode, "a") then
                retval.write = function(text)
                    if pos > string.len(file) then file = file .. text 
                    else file = string.sub(file, 1, pos - 1) .. text .. string.sub(file, pos + string.len(text)) end
                    pos = pos + string.len(text)
                end
                retval.writeLine = function(text) retval.write(text .. "\n") end
                retval.flush = function()
                    local dir = getComponent(retval.data, split(fs.getDir(path), "/"))
                    dir[fs.getName(path)] = file
                end
            end
        end
        return retval
    end

    -- for CCKernel2
    function retval.getPermissions() return 15 end
    function retval.setPermissions() end
    function retval.getOwner() return 0 end
    function retval.setOwner() end

    return retval
end

function new() return create({}) end

function load(path) return create(import(path)) end

function read(path)
    local file = fs.open(path, "rb")
    local retval = ""
    local b = file.read()
    while b ~= nil do
        retval = retval .. string.char(b)
        b = file.read()
    end
    file.close()
    return create(textutils.unserialize(LibDeflate:DecompressGzip(retval)))
end

function setCompressionLevel(level) compression_level = level end

local archive = {new = new, load = load, read = read, setCompressionLevel = setCompressionLevel}
setmetatable(archive, {__call = function(self, path) if path ~= nil and fs.exists(path) then if fs.isDir(path) then return load(path) else return read(path) end else return new() end end})
return archive