-- Unix ar archive library & program
-- Use in the shell or with require

local function trim(s) return string.match(s, '^()%s*$') and '' or string.match(s, '^%s*(.*%S)') end
local function u2cc(p) return bit.band(p, 0x1) * 8 + bit.band(p, 0x2) + bit.band(p, 0x4) / 4 + 4 end
local function cc2u(p) return bit.band(p, 0x8) / 8 + bit.band(p, 0x2) + bit.band(p, 0x1) * 4 end
local function pad(str, len, c) return string.len(str) < len and string.sub(str, 1, len) .. string.rep(c or " ", len - string.len(str)) or str end
local verbosity = 0

local ar = {}

-- Loads an archive into a table
function ar.load(path)
    if not fs.exists(path) then return nil end
    local file = fs.open(path, "rb")
    local oldread = file.read
    local seek = 0
    file.read = function(c) if c then
        local retval = nil
        for i = 1, c do
            local n = oldread()
            if n == nil then return retval end
            retval = (retval or "") .. string.char(n)
            if (seek + i) % 10240 == 0 then os.queueEvent(os.pullEvent()) end 
        end
        seek = seek + c
        return retval
    else return string.char(oldread()) end end
    if file.read(8) ~= "!<arch>\n" then
        file.close()
        error("Not an ar archive", 2)
    end
    local retval = {}
    local name_table = nil
    local name_rep = {}
    os.queueEvent("nosleep")
    while true do
        local data = {}
        local first_c = file.read()
        while first_c == "\n" do first_c = file.read() end
        if first_c == nil then break end
        local name = file.read(15)
        if name == nil then break end
        name = first_c .. name
        if string.find(name, "/") and string.find(name, "/") > 1 then name = string.sub(name, 1, string.find(name, "/") - 1)
        else name = trim(name) end
        data.timestamp = tonumber(trim(file.read(12)))
        data.owner = tonumber(trim(file.read(6)))
        data.group = tonumber(trim(file.read(6)))
        data.mode = tonumber(trim(file.read(8)), 8)
        local size = tonumber(trim(file.read(10)))
        if file.read(2) ~= "`\n" then error("Invalid header for file " .. name, 2) end
        if string.match(name, "^#1/%d+$") then name = file.read(tonumber(string.match(name, "#1/(%d+)"))) 
        elseif string.match(name, "^/%d+$") then if name_table then 
            local n = tonumber(string.match(name, "/(%d+)"))
            name = string.sub(name_table, n+1, string.find(name_table, "/", n) - 1)
        else table.insert(name_rep, name) end end
        data.name = name
        data.data = file.read(size)
        if name == "//" then name_table = data.data
        elseif name ~= "/" and name ~= "/SYM64/" then table.insert(retval, data) end
        os.queueEvent(os.pullEvent())
    end
    file.close()
    if name_table then for k,v in pairs(name_rep) do
        local n = tonumber(string.match(v, "/(%d+)"))
        for l,w in pairs(retval) do if w.name == v then w.name = string.sub(name_table, n, string.find(name_table, "/", n) - 1); break end end
    end end
    return retval
end

-- Writes a table entry to a file
function ar.write(v, p)
    local file = fs.open(p, "wb")
    for s in string.gmatch(v.data, ".") do file.write(string.byte(s)) end
    file.close()
    if fs.setPermissions and v.owner ~= 0 then
        fs.setPermissions(p, v.owner, u2cc(v.mode) + bit.band(v.mode, 0x800) / 0x80)
        fs.setPermissions(p, "*", u2cc(bit.brshift(v.mode, 6)) + bit.band(v.mode, 0x800) / 0x80)
        fs.setOwner(p, v.owner)
    end
    if verbosity > 0 then print("Extracted to " .. p) end
end

-- Extracts files from a table or file to a directory
function ar.extract(data, path)
    if type(data) == "string" then data = load(data) end
    if not fs.exists(path) then fs.makeDir(path) end
    for k,v in pairs(data) do
        local p = fs.combine(path, v.name)
        ar.write(v, p)
    end
end

-- Reads a file into a table entry
function ar.read(p)
    local file = fs.open(p, "rb")
    local retval = {
        name = fs.getName(p),
        timestamp = os.epoch and math.floor(os.epoch("utc") / 1000) or 0, 
        owner = fs.getOwner and fs.getOwner(p) or 0, 
        group = 0,
        mode = fs.getPermissions and cc2u(fs.getPermissions(p, fs.getOwner(p) or 0)) * 0x40 + cc2u(fs.getPermissions(p, "*")) + bit.band(fs.getPermissions(p, "*"), 0x10) * 0x80 or 0x1FF,
        data = ""
    }
    local c = file.read()
    while c ~= nil do 
        retval.data = retval.data .. string.char(c)
        c = file.read()
    end
    file.close()
    return retval
end

-- Packs files in a directory into a table (skips subdirectories)
function ar.pack(path)
    local retval = {}
    for k,v in pairs(fs.list(path)) do
        local p = fs.combine(path, v)
        retval[v] = read(p)
    end
    return retval
end

-- Saves a table to an archive file
function ar.save(data, path)
    local file = fs.open(path, "wb")
    local oldwrite = file.write
    local seek = 0
    file.write = function(str) 
        for c in string.gmatch(str, ".") do oldwrite(string.byte(c)) end
        seek = seek + string.len(str)
    end
    file.write("!<arch>\n")
    local name_table = {}
    local name_str = nil
    for k,v in pairs(data) do if string.len(v.name) > 16 then 
        name_table[v.name] = string.len(name_str)
        name_str = (name_str or "") .. v.name .. "/\n"
    end end
    if name_str then
        file.write("//" .. string.rep(" ", 46) .. pad(tostring(string.len(name_str)), 10) .. "`\n" .. name_str)
        if seek / 2 == 1 then file.write("\n") end
    end
    for k,v in pairs(data) do
        local name = name_table[v.name] and "/" .. name_table[v.name] or v.name .. (name_str and "/" or "")
        file.write(pad(name, 16) .. pad(tostring(v.timestamp), 12) .. pad(tostring(v.owner), 6) .. pad(tostring(v.group), 6))
        file.write(pad(string.format("%o", v.mode), 8) .. pad(tostring(string.len(v.data)), 10) .. "`\n" .. v.data)
        if seek % 2 == 1 then file.write("\n") end
    end
    file.close()
    os.queueEvent("nosleep")
    os.pullEvent()
end

local function strmap(num, str, c)
    local retval = ""
    for i = 1, string.len(str) do retval = retval .. (bit.band(num, bit.blshift(1, string.len(str)-i)) == 0 and c or string.sub(str, i, i)) end
    return retval
end

local function CurrentDate(z)
    local z = math.floor(z / 86400) + 719468
    local era = math.floor(z / 146097)
    local doe = math.floor(z - era * 146097)
    local yoe = math.floor((doe - doe / 1460 + doe / 36524 - doe / 146096) / 365)
    local y = math.floor(yoe + era * 400)
    local doy = doe - math.floor((365 * yoe + yoe / 4 - yoe / 100))
    local mp = math.floor((5 * doy + 2) / 153)
    local d = math.ceil(doy - (153 * mp + 2) / 5 + 1)
    local m = math.floor(mp + (mp < 10 and 3 or -9))
    return y + (m <= 2 and 1 or 0), m, d
end
    
local function CurrentTime(unixTime)
    local hours = math.floor(unixTime / 3600 % 24)
    local minutes = math.floor(unixTime / 60 % 60)
    local seconds = math.floor(unixTime % 60)
    local year, month, day = CurrentDate(unixTime)
    return {
        year = year,
        month = month,
        day = day,
        hours = hours,
        minutes = minutes < 10 and "0" .. minutes or minutes,
        seconds = seconds < 10 and "0" .. seconds or seconds
    }
end

local months = {"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"}

if pcall(require, "ar") then
    local args = {...}
    if #args < 2 then error("Usage: ar <dpqrtx[cfTuv]> <archive.a> [path] [files...]") end
    if args[1] == "--version" then
        print("CraftOS ar (CCKernel2 binutils) 1.0 (compatible with GNU/BSD ar)\nCopyright (c) 2019 JackMacWindows.")
        return 2
    end
    local mode = nil
    local update = false
    local truncate = false
    if string.find(args[1], "d") then mode = 0 end -- delete
    if string.find(args[1], "p") then mode = 1 end -- print file
    if string.find(args[1], "q") then mode = 2 end -- quick append
    if string.find(args[1], "r") then mode = 3 end -- replace or add
    if string.find(args[1], "t") then mode = 4 end -- list
    if string.find(args[1], "x") then mode = 5 end -- extract
    if string.find(args[1], "c") then verbosity = -1 end
    if string.find(args[1], "v") then verbosity = 1 end
    if string.find(args[1], "u") then update = true end
    if string.find(args[1], "T") then truncate = true end
    if string.find(args[1], "f") then truncate = true end
    local data = ar.load(shell.resolve(args[2]))
    local files = {...}
    table.remove(files, 1)
    table.remove(files, 1)
    if data == nil then
        if verbosity > -1 then print("ar: Creating archive " .. shell.resolve(args[2])) end
        data = {}
    end
    if mode == 0 then
        for k,v in pairs(data) do for l,w in pairs(files) do if v.name == w then data[k] = nil; break end end end
        ar.save(data, shell.resolve(args[2]))
    elseif mode == 1 then
        if #args > 2 then for k,v in pairs(data) do for l,w in pairs(files) do if v.name == w then print(v.data); break end end end
        else for k,v in pairs(data) do print(v.data) end end
    elseif mode == 2 then
        for k,v in pairs(files) do 
            local f = ar.read(shell.resolve(v))
            f.name = string.sub(f.name, 1, truncate and 15 or nil)
            table.insert(data, f) 
        end
        ar.save(data, shell.resolve(args[2]))
    elseif mode == 3 then
        for k,v in pairs(files) do
            local f = ar.read(shell.resolve(v))
            f.name = string.sub(f.name, 1, truncate and 15 or nil)
            local found = false
            for l,w in pairs(data) do if w.name == f.name then
                found = true
                for m,x in pairs(f) do w[m] = f[m] end
                break
            end end
            if not found then table.insert(data, f) end
        end
        ar.save(data, shell.resolve(args[2]))
    elseif mode == 4 then
        if verbosity > 0 then
            local tmp = {}
            local max = {0, 0, 0, 0, 0}
            for k,v in pairs(data) do
                local date = CurrentTime(v.timestamp)
                local d = months[date.month] .. " " .. date.day .. " " .. date.hours .. ":" .. date.minutes .. " " .. date.year
                local p = {strmap(v.mode, "rwxrwxrwx", "-"), v.owner .. "/" .. v.group, string.len(v.data), d, v.name}
                for l,w in pairs(p) do if string.len(w) + 3 > max[l] then max[l] = string.len(w) + 3 end end
                table.insert(tmp, p)
            end
            for k,v in pairs(tmp) do
                for l,w in pairs(v) do write(pad(w, max[l])) end
                print("")   
            end
        else for k,v in pairs(data) do print(v.name) end end
    elseif mode == 5 then
        local path = #files > 0 and table.remove(files, 1) or "."
        local f
        if #files > 0 then
            f = {}
            for k,v in pairs(data) do for l,w in pairs(files) do if v.name == w then table.insert(f, v); break end end end
        else f = data end
        ar.extract(f, shell.resolve(path))
    else error("Unknown mode") end
end

return ar