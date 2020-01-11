-- Tape Archive (tar) archiver/unarchiver library (using UStar)
-- Use in the shell or with require

local function trim(s) return string.match(s, '^()[%s%z]*$') and '' or string.match(s, '^[%s%z]*(.*[^%s%z])') end
local function u2cc(p) return bit.band(p, 0x1) * 8 + bit.band(p, 0x2) + bit.band(p, 0x4) / 4 + 4 end
local function cc2u(p) return bit.band(p, 0x8) / 8 + bit.band(p, 0x2) + bit.band(p, 0x1) * 4 end
local function pad(str, len, c) return string.len(str) < len and string.sub(str, 1, len) .. string.rep(c or " ", len - string.len(str)) or str end
local function lpad(str, len, c) return string.len(str) < len and string.rep(c or " ", len - string.len(str)) .. string.sub(str, 1, len) or str end
local function tidx(t, i, ...)
    if i and t[i] == nil then t[i] = {} end
    return i ~= nil and tidx(t[i], ...) or t 
end
local function split(str, sep)
    local t={}
    for s in string.gmatch(str, "([^"..(sep or "%s").."]+)") do table.insert(t, s) end
    return t
end
local verbosity = 0
local ignore_zero = false

local tar = {}

-- Converts a serial list of tar entries into a hierarchy
function tar.unserialize(data)
    local retval = {}
    local links = {}
    for k,v in pairs(data) do
        local components = split(v.name, "/")
        local name = table.remove(components, table.maxn(components))
        local dir = tidx(retval, table.unpack(components))
        if v.type == 0 or v.type == 7 then dir[name] = v 
        elseif v.type == 1 or v.type == 2 then table.insert(links, v) 
        elseif v.type == 5 then dir[name] = {["//"] = v} end
    end
    for k,v in pairs(links) do
        local components = split(v.name, "/")
        local name = table.remove(components, table.maxn(components))
        tidx(retval, table.unpack(components))[name] = tidx(retval, table.unpack(split(v.link, "/")))
    end
    return retval
end

-- Converts a hierarchy into a serial list of tar entries
function tar.serialize(data)
    --if data["//"] == nil then error("Invalid directory " .. data.name) end
    local retval = (data["//"] ~= nil and #data["//"] > 0) and {data["//"]} or {}
    for k,v in pairs(data) do if k ~= "//" then
        if v["//"] ~= nil or v.name == nil then
            local t = table.maxn(retval)
            for l,w in ipairs(tar.serialize(v)) do retval[t+l] = w end
        else table.insert(retval, v) end
    end end
    return retval
end

-- Loads an archive into a table
function tar.load(path, noser, rawdata)
    if not fs.exists(path) and not rawdata then error("Path does not exist", 2) end
    local file 
    if rawdata then
        local s = 1
        file = {
            read = function(num)
                if num then
                    s=s+num
                    return string.sub(path, s-num, s-1)
                end
                s=s+1
                return string.byte(string.sub(path, s-1, s-1))
            end,
            close = function() end,
            seek = true,
        }
    else file = fs.open(path, "rb") end
    local oldread = file.read
    local sum = 0
    local seek = 0
    file.read = function(c) 
        c = c or 1
        if c < 1 then return end
        local retval = nil
        if file.seek then
            retval = oldread(c)
            for ch in retval:gmatch(".") do sum = sum + ch:byte() end
        else
            for i = 1, c do
                local n = oldread()
                if n == nil then return retval end
                retval = (retval or "") .. string.char(n)
                sum = sum + n
                if i % 1000000 == 0 then
                    os.queueEvent("nosleep")
                    os.pullEvent()
                end
            end
        end
        seek = seek + c
        return retval
    end
    local retval = {}
    local empty_blocks = 0
    while true do
        local data = {}
        sum = 0
        data.name = file.read(100)
        assert(seek % 512 == 100)
        if data.name == nil then break
        elseif data.name == string.rep("\0", 100) then
            file.read(412)
            assert(seek % 512 == 0)
            empty_blocks = empty_blocks + 1
            if empty_blocks == 2 and not ignore_zero then break end
        else
            data.name = trim(data.name)
            data.mode = tonumber(trim(file.read(8)), 8)
            data.owner = tonumber(trim(file.read(8)), 8)
            data.group = tonumber(trim(file.read(8)), 8)
            local size = tonumber(trim(file.read(12)), 8)
            data.timestamp = tonumber(trim(file.read(12)), 8)
            local o = sum
            local checksum = tonumber(trim(file.read(8)), 8)
            sum = o + 256
            local t = file.read()
            data.type = tonumber(t == "\0" and "0" or t) or t
            data.link = trim(file.read(100))
            if trim(file.read(6)) == "ustar" then
                file.read(2)
                data.ownerName = trim(file.read(32))
                data.groupName = trim(file.read(32))
                data.deviceNumber = {tonumber(trim(file.read(8))), tonumber(trim(file.read(8)))}
                if data.deviceNumber[1] == nil and data.deviceNumber[2] == nil then data.deviceNumber = nil end
                data.name = trim(file.read(155)) .. data.name
            end
            file.read(512 - (seek % 512))
            assert(seek % 512 == 0)
            if sum ~= checksum then print("Warning: checksum mismatch for " .. data.name) end
            if size ~= nil and size > 0 then
                data.data = file.read(size)
                if size % 512 ~= 0 then file.read(512 - (seek % 512)) end
            end
            assert(seek % 512 == 0)
            table.insert(retval, data)
        end
        os.queueEvent("nosleep")
        os.pullEvent()
    end
    file.close()
    return noser and retval or tar.unserialize(retval)
end

-- Extracts files from a table or file to a directory
function tar.extract(data, path, link)
    fs.makeDir(path)
    local links = {}
    for k,v in pairs(data) do if k ~= "//" then
        local p = fs.combine(path, k)
        if v["//"] ~= nil then 
            local l = tar.extract(v, p, kernel ~= nil) 
            if kernel then for l,w in pairs(l) do table.insert(links, w) end end
        elseif (v.type == 1 or v.type == 2) and kernel then table.insert(links, v)
        elseif v.type == 0 or v.type == 7 then
            local file = fs.open(p, "wb")
            for s in string.gmatch(v.data, ".") do file.write(string.byte(s)) end
            file.close()
            if kernel and v.owner ~= nil then
                fs.setPermissions(p, "*", u2cc(bit.brshift(v.mode, 6)) + bit.band(v.mode, 0x800) / 0x80)
                if v.ownerName ~= nil and v.ownerName ~= "" then
                    fs.setPermissions(p, users.getUIDFromName(v.ownerName), u2cc(v.mode) + bit.band(v.mode, 0x800) / 0x80)
                    fs.setOwner(p, users.getUIDFromName(v.ownerName))
                else
                    fs.setPermissions(p, v.owner, u2cc(v.mode) + bit.band(v.mode, 0x800) / 0x80)
                    fs.setOwner(p, v.owner)
                end
            end
        elseif v.type ~= nil then print("Unimplemented type " .. v.type) end
        if verbosity > 0 then print(((v["//"] and v["//"].name or v.name) or "?") .. " => " .. (p or "?")) end
        os.queueEvent("nosleep")
        os.pullEvent()
    end end
    if link then return links
    elseif kernel then for k,v in pairs(links) do
        -- soon(tm)
    end end
end

-- Reads a file into a table entry
function tar.read(base, p)
    local file = fs.open(fs.combine(base, p), "rb")
    local retval = {
        name = p,
        mode = fs.getPermissions and cc2u(fs.getPermissions(p, fs.getOwner(p) or 0)) * 0x40 + cc2u(fs.getPermissions(p, "*")) + bit.band(fs.getPermissions(p, "*"), 0x10) * 0x80 or 0x1FF, 
        owner = fs.getOwner and fs.getOwner(p) or 0, 
        group = 0,
        timestamp = os.epoch and math.floor(os.epoch("utc") / 1000) or 0,
        type = 0,
        link = "",
        ownerName = fs.getOwner and users.getShortName(fs.getOwner(p)) or "",
        groupName = "",
        deviceNumber = nil,
        data = ""
    }
    if file.seek then retval.data = file.read(fs.getSize(fs.combine(base, p))) else
        local c = file.read()
        while c ~= nil do 
            retval.data = retval.data .. string.char(c)
            c = file.read()
        end
    end
    file.close()
    return retval
end

-- Packs files in a directory into a table
function tar.pack(base, path)
    if not fs.isDir(base) then return tar.read(base, path) end
    local retval = {["//"] = {
        name = path .. "/",
        mode = fs.getPermissions and cc2u(fs.getPermissions(path, fs.getOwner(path) or 0)) * 0x40 + cc2u(fs.getPermissions(path, "*")) + bit.band(fs.getPermissions(path, "*"), 0x10) * 0x80 or 0x1FF,
        owner = fs.getOwner and fs.getOwner(path) or 0,
        group = 0,
        timestamp = os.epoch and math.floor(os.epoch("utc") / 1000) or 0,
        type = 5,
        link = "",
        ownerName = fs.getOwner and users.getShortName(fs.getOwner(path)) or "",
        groupName = "",
        deviceNumber = nil,
        data = nil
    }}
    if string.sub(base, -1) == "/" then base = string.sub(base, 1, -1) end
    if path and string.sub(path, 1, 1) == "/" then path = string.sub(path, 2) end
    if path and string.sub(path, -1) == "/" then path = string.sub(path, 1, -1) end
    local p = path and (base .. "/" .. path) or base
    for k,v in pairs(fs.list(p)) do
        if fs.isDir(fs.combine(p, v)) then retval[v] = tar.pack(base, path and (path .. "/" .. v) or v)
        else retval[v] = tar.read(base, path and (path .. "/" .. v) or v) end
        if verbosity > 0 then print(fs.combine(p, v) .. " => " .. (path and (path .. "/" .. v) or v)) end
    end
    return retval
end

-- Saves a table to an archive file
function tar.save(data, path, noser)
    if not noser then data = tar.serialize(data) end
    local nosave = path == nil
    local file 
    local seek = 0
    if not nosave then 
        file = fs.open(path, "wb")
        local oldwrite = file.write
        file.write = function(str) 
            for c in string.gmatch(str, ".") do oldwrite(string.byte(c)) end
            seek = seek + string.len(str)
        end
    else file = "" end
    for k,v in pairs(data) do
        local header = ""
        header = header .. pad(string.sub(v.name, -100), 100, "\0")
        header = header .. (v.mode and string.format("%07o\0", v.mode) or string.rep("\0", 8))
        header = header .. (v.owner and string.format("%07o\0", v.owner) or string.rep("\0", 8))
        header = header .. (v.group and string.format("%07o\0", v.group) or string.rep("\0", 8))
        header = header .. (v.data and string.format("%011o\0", string.len(v.data)) or (string.rep("0", 11) .. "\0"))
        header = header .. (v.timestamp and string.format("%011o\0", v.timestamp) or string.rep("\0", 12))
        header = header .. v.type
        header = header .. (v.link and pad(v.link, 100, "\0") or string.rep("\0", 100))
        header = header .. "ustar  \0"
        header = header .. (v.ownerName and pad(v.ownerName, 32, "\0") or string.rep("\0", 32))
        header = header .. (v.groupName and pad(v.groupName, 32, "\0") or string.rep("\0", 32))
        header = header .. (v.deviceNumber and v.deviceNumber[1] and string.format("%07o\0", v.deviceNumber[1]) or string.rep("\0", 8))
        header = header .. (v.deviceNumber and v.deviceNumber[2] and string.format("%07o\0", v.deviceNumber[2]) or string.rep("\0", 8))
        header = header .. (string.len(v.name) > 100 and pad(string.sub(v.name, 1, -101), 155, "\0") or string.rep("\0", 155))
        if string.len(header) < 504 then header = header .. string.rep("\0", 504 - string.len(header)) end
        local sum = 256
        for c in string.gmatch(header, ".") do sum = sum + string.byte(c) end
        header = string.sub(header, 1, 148) .. string.format("%06o\0 ", sum) .. string.sub(header, 149)
        if nosave then file = file .. header else file.write(header) end
        --assert(seek % 512 == 0)
        if v.data ~= nil and v.data ~= "" then 
            if nosave then file = file .. pad(v.data, math.ceil(string.len(v.data) / 512) * 512, "\0") 
            else file.write(pad(v.data, math.ceil(string.len(v.data) / 512) * 512, "\0")) end
        end
    end
    if nosave then file = file .. string.rep("\0", 1024) else file.write(string.rep("\0", 1024)) end
    if nosave then file = file .. string.rep("\0", 10240 - (string.len(file) % 10240)) else file.write(string.rep("\0", 10240 - (seek % 10240))) end
    if not nosave then file.close() end
    os.queueEvent("nosleep")
    os.pullEvent()
    if nosave then return file end
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

local usage_str = [=[Usage: tar [OPTION...] [FILE]...
CraftOS 'tar' saves many files together into a single tape or disk archive, and
can restore individual files from the archive.

Examples:
  tar -cf archive.tar foo bar  # Create archive.tar from files foo and bar.
  tar -tvf archive.tar         # List all files in archive.tar verbosely.
  tar -xf archive.tar          # Extract all files from archive.tar.

 Local file name selection:

      --add-file=FILE        add given FILE to the archive (useful if its name
                             starts with a dash)
  -C, --directory=DIR        change to directory DIR
      --no-null              disable the effect of the previous --null option
      --no-recursion         avoid descending automatically in directories
      --null                 -T reads null-terminated names; implies
                             --verbatim-files-from
      --recursion            recurse into directories (default)
  -T, --files-from=FILE      get names to extract or create from FILE
  
 Main operation mode:

  -A, --catenate, --concatenate   append tar files to an archive
  -c, --create               create a new archive
  -d, --diff, --compare      find differences between archive and file system
      --delete               delete from the archive (not on mag tapes!)
  -r, --append               append files to the end of an archive
  -t, --list                 list the contents of an archive
  -u, --update               only append files newer than copy in archive
  -x, --extract, --get       extract files from an archive

 Overwrite control:

  -k, --keep-old-files       don't replace existing files when extracting,
                             treat them as errors
      --overwrite            overwrite existing files when extracting
      --remove-files         remove files after adding them to the archive
  -W, --verify               attempt to verify the archive after writing it

 Device selection and switching:

  -f, --file=ARCHIVE         use archive file or device ARCHIVE
   
 Device blocking:

  -i, --ignore-zeros         ignore zeroed blocks in archive (means EOF)
  
 Compression options:

  -z, --gzip, --gunzip, --ungzip   filter the archive through gzip
  
 Local file selection:

  -N, --newer=DATE-OR-FILE, --after-date=DATE-OR-FILE
                             only store files newer than DATE-OR-FILE
  
 Informative output:

  -v, --verbose              verbosely list files processed
  
 Other options:

  -?, --help                 give this help list
      --usage                give a short usage message
      --version              print program version]=]

if pcall(require, "tar") then
    local args = {...}
    local arch = nil
    local files = {}
    local mode = nil
    local nextarg = nil
    local replace = true
    local delete = false
    local verify = false
    local outdir = nil
    local preserve = false
    local compress = false
    local start = nil
    local newerthan = 0
    local null = false
    local norecurse = false
    for k,v in pairs(args) do
        if nextarg then
            if nextarg == 0 then arch = v
            elseif nextarg == 1 then outdir = v
            elseif nextarg == 2 then start = v
            elseif nextarg == 3 then newerthan = tonumber(v)
            elseif nextarg == 4 then
                local file = fs.open(shell.resolve(v), "r")
                local line = file.readLine()
                while line ~= nil do
                    if null then table.insert(files, line) else table.insert(args, line) end
                    line = file.readLine()
                end
                file.close()
            end
            nextarg = nil
        elseif k == 1 or (string.sub(v, 1, 1) == "-" and string.sub(v, 2, 2) ~= "-") then
            if string.find(v, "A") then mode = 0 end
            if string.find(v, "d") then mode = 2 end
            if string.find(v, "c") then mode = 1 end
            if string.find(v, "r") then mode = 3 end
            if string.find(v, "t") then mode = 4 end
            if string.find(v, "u") then mode = 5 end
            if string.find(v, "x") then mode = 6 end
            if string.find(v, "f") then nextarg = 0 end
            if string.find(v, "k") then replace = false end
            if string.find(v, "U") then delete = true end
            if string.find(v, "W") then verify = true end
            if string.find(v, "O") then outdir = 0 end
            if string.find(v, "p") and kernel then preserve = true end
            if string.find(v, "i") then ignore_zero = true end
            if string.find(v, "z") then compress = true end
            if string.find(v, "C") then nextarg = 1 end
            if string.find(v, "K") then nextarg = 2 end
            if string.find(v, "N") then nextarg = 3 end
            if string.find(v, "T") then nextarg = 4 end
            if string.find(v, "v") then verbosity = 1  end
            if string.find(v, "?") then
                print(usage_str)
                return 2
            end
        elseif string.sub(v, 1, 2) == "--" then
            if v == "--catenate" then mode = 0
            elseif v == "--concatenate" then mode = 0
            elseif v == "--create" then mode = 1
            elseif v == "--diff" then mode = 2
            elseif v == "--compare" then mode = 2
            elseif v == "--delete" then mode = 7
            elseif v == "--append" then mode = 3
            elseif v == "--list" then mode = 4
            elseif v == "--update" then mode = 5
            elseif v == "--extract" then mode = 6
            elseif v == "--get" then mode = 6
            elseif v == "--help" or v == "--usage" then 
                print(usage_str)
                return 2
            elseif v == "--version" then
                print("CraftOS tar v1.0")
                return 2
            elseif v == "--keep-old-files" then replace = false
            elseif v == "--overwrite" then replace = true
            elseif v == "--remove-files" then delete = true
            elseif v == "--unlink-first" then delete = true
            elseif v == "--verify" then verify = true
            elseif v == "--to-stdout" then outdir = 0
            elseif v == "--preserve-permissions" and kernel then preserve = true
            elseif v == "--same-permissions" and kernel then preserve = true
            elseif v == "--preserve" and kernel then preserve = true
            elseif string.find(v, "--file=") then arch = string.sub(v, 8)
            elseif v == "--ignore-zeros" then ignore_zero = true
            elseif v == "--gzip" or v == "--gunzip" or v == "--ungzip" then compress = true
            elseif string.find(v, "--add-file=") then table.insert(files, string.sub(v, 12))
            elseif string.find(v, "--directory=") then outdir = string.sub(v, 13)
            elseif string.find(v, "--starting-file=") then start = string.sub(v, 17)
            elseif v == "--no-null" then null = false
            elseif v == "--null" then null = true
            elseif string.find(v, "--newer=") then newerthan = tonumber(string.sub(v, 9))
            elseif string.find(v, "--after-date=") then newerthan = tonumber(string.sub(v, 14))
            elseif string.find(v, "--files-from=") then
                local file = fs.open(shell.resolve(string.sub(v, 14)), "r")
                local line = file.readLine()
                while line ~= nil do
                    if null then table.insert(files, line) else table.insert(args, line) end
                    line = file.readLine()
                end
                file.close()
            elseif v == "--verbose" then verbosity = 1 
            elseif v == "--no-recursion" then norecurse = true end
        else table.insert(files, v) end
    end
    if compress and LibDeflate == nil then 
        LibDeflate = require "LibDeflate"
        if LibDeflate == nil then error("Compression is only supported when LibDeflate.lua is available in the PATH.") end
    end
    local olddir = shell.dir()
    if type(outdir) == "string" then shell.setDir(shell.resolve(outdir)) end
    local function err(str)
        shell.setDir(olddir)
        error(str)
    end
    local function loadFile(noser)
        if compress then
            local rawdata = ""
            local file = fs.open(shell.resolve(arch), "rb")
            local c = file.read()
            while c ~= nil do
                rawdata = rawdata .. string.char(c)
                c = file.read()
                if string.len(rawdata) % 10240 == 0 then
                    os.queueEvent("nosleep")
                    os.pullEvent()
                end
            end
            file.close()
            return load(LibDeflate:DecompressGzip(rawdata), noser, true)
        else return load(shell.resolve(arch), noser) end
    end
    local function saveFile(data)
        if not compress and arch then tar.save(data, shell.resolve(arch)) else
            local retval = tar.save(data, nil)
            if compress then retval = LibDeflate:CompressGzip(retval) end
            if outdir == 0 then write(retval)
            elseif retval then
                local file = fs.open(shell.resolve(arch), "wb")
                for c in string.gmatch(retval, ".") do file.write(string.byte(c)) end
                file.close()
            end
        end
    end
    --[[ reminder:
    local args = {...}
    local arch = nil
    local files = {}

    local replace = true
    local delete = false
    local verify = false
    local preserve = false
    local start = nil
    local newerthan = 0
    ]]
    if mode == 0 then --concatenate
        if compress == true then err("Compressed files cannot be concatenated") end
        if arch == nil then err("You must specify an arhive with -f <first.tar>.") end
        local fout = fs.open(shell.resolve(arch), "ab")
        for k,v in pairs(files) do
            local fin = fs.open(shell.resolve(v), "rb")
            local c = fin.read()
            while c do
                fout.write(c)
                c = fin.read()
            end
            fin.close()
        end
        fout.close()
    elseif mode == 1 then --create
        if arch == nil and outdir ~= 0 then err("You must specify an archive with -f <output.tar> or -O.") end
        local data = {}
        for k,v in pairs(files) do
            local components = split(v, "/")
            local d = data
            local path = nil
            for k,v in pairs(components) do
                if k == #components then break end
                path = path and fs.combine(path, v) or v
                if d[v] == nil then d[v] = {--[[["//"] = {
                    name = path,
                    mode = fs.getPermissions and cc2u(fs.getPermissions(path, fs.getOwner(path) or 0)) * 0x40 + cc2u(fs.getPermissions(path, "*")) + bit.band(fs.getPermissions(path, "*"), 0x10) * 0x80 or 0x1FF,
                    owner = fs.getOwner and fs.getOwner(path) or 0,
                    group = 0,
                    timestamp = os.epoch and math.floor(os.epoch("utc") / 1000) or 0,
                    type = 5,
                    link = "",
                    ownerName = fs.getOwner and users.getShortName(fs.getOwner(p)) or "",
                    groupName = "",
                    deviceNumber = nil,
                    data = nil
                }]]} end
                d = d[v]
            end
            if string.sub(v, 1, 1) == "/" then d[components[#components]] = (norecurse and tar.read or tar.pack)("/", string.sub(v, 2))
            else d[components[#components]] = (norecurse and tar.read or tar.pack)(shell.dir(), v) end
            if delete then fs.delete(shell.resolve(v)) end
        end
        saveFile(data)
    elseif mode == 2 then --diff
        err("Not implemented")
    elseif mode == 3 then --append
        if arch == nil and outdir ~= 0 then err("You must specify an archive with -f <output.tar> or -O.") end
        local data = loadFile(true)
        for k,v in pairs(files) do
            if string.sub(v, 1, 1) == "/" then table.insert(data, (norecurse and tar.read or tar.pack)("/", string.sub(v, 2)))
            else table.insert(data, (norecurse and tar.read or tar.pack)(shell.dir(), v)) end
            if delete then fs.delete(shell.resolve(v)) end
        end
        saveFile(data)
    elseif mode == 4 then --list
        if arch == nil then err("You must specify an archive with -f <file.tar>.") end
        local data = loadFile(true)
        if verbosity > 0 then
            local tmp = {}
            local max = {0, 0, 0, 0, 0}
            for k,v in pairs(data) do
                local date = CurrentTime(v.timestamp or 0)
                local d = string.format("%04d-%02d-%02d %02d:%02d", date.year, date.month, date.day, date.hours, date.minutes)
                local p = {strmap(v.mode + (v.type == 5 and 0x200 or 0), "drwxrwxrwx", "-"), (v.ownerName or v.owner or 0) .. "/" .. (v.groupName or v.group or 0), string.len(v.data or ""), d, v.name .. (v.link and v.link ~= "" and (" -> " .. v.link) or "")}
                for l,w in pairs(p) do if string.len(w) + 1 > max[l] then max[l] = string.len(w) + 1 end end
                table.insert(tmp, p)
            end
            for k,v in pairs(tmp) do
                for l,w in pairs(v) do write((l == 3 and lpad or pad)(w, max[l]) .. (l == 3 and " " or "")) end
                print("")   
            end
        else for k,v in pairs(data) do print(v.name) end end
    elseif mode == 5 then --update
        if arch == nil and outdir ~= 0 then err("You must specify an archive with -f <output.tar> or -O.") end
        local data = loadFile()
        for k,v in pairs(files) do
            local components = split(v, "/")
            local d = data
            local path = nil
            for k,v in pairs(components) do
                if k == #components then break end
                path = path and fs.combine(path, v) or v
                if d[v] == nil then d[v] = {["//"] = {
                    name = path,
                    mode = fs.getPermissions and cc2u(fs.getPermissions(path, fs.getOwner(path) or 0)) * 0x40 + cc2u(fs.getPermissions(path, "*")) + bit.band(fs.getPermissions(path, "*"), 0x10) * 0x80 or 0x1FF,
                    owner = fs.getOwner and fs.getOwner(path) or 0,
                    group = 0,
                    timestamp = os.epoch and math.floor(os.epoch("utc") / 1000) or 0,
                    type = 5,
                    link = "",
                    ownerName = fs.getOwner and users.getShortName(fs.getOwner(path)) or "",
                    groupName = "",
                    deviceNumber = nil,
                    data = nil
                }} end
                d = d[v]
            end
            if string.sub(v, 1, 1) == "/" then d[components[#components]] = (norecurse and tar.read or tar.pack)("/", string.sub(v, 2))
            else d[components[#components]] = (norecurse and tar.read or tar.pack)(shell.dir(), v) end
            if delete then fs.delete(shell.resolve(v)) end
        end
        saveFile(data)
    elseif mode == 6 then --extract
        if arch == nil then err("You must specify an archive with -f <file.tar>.") end
        local data = loadFile()
        tar.extract(data, shell.dir())
    elseif mode == 7 then --delete
        if arch == nil then err("You must specify an archive with -f <file.tar>.") end
        local data = loadFile(true)
        for k,v in pairs(files) do for l,w in pairs(data) do if w.name == v then
            data[l] = nil
            break
        end end end
        saveFile(data)
    else err("You must specify one of -Acdrtux, see --help for details.") end
    shell.setDir(olddir)
end

return tar