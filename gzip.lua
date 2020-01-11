local LibDeflate = require "LibDeflate"
local args = {...}

local mode = 0
local input
local output
local keep = false
local overwrite = false
local level
local verbose = false

for k,v in pairs(args) do
    if v == "-c" or v == "--stdout" then output = "stdout"
    elseif v == "-d" or v == "--decompress" then mode = 1
    elseif v == "-f" or v == "--force" then overwrite = true
    elseif v == "-h" or v == "--help" then
        print([[Usage: gzip [OPTION]... [FILE]
        Compress or uncompress FILEs (by default, compress FILES in-place).
        
          -c, --stdout      write on standard output, keep original files unchanged
          -d, --decompress  decompress
          -f, --force       force overwrite of output file
          -h, --help        give this help
          -k, --keep        keep (don't delete) input files
          -l, --list        list compressed file contents
          -t, --test        test compressed file integrity
          -v, --verbose     verbose mode
          -V, --version     display version number
          -1, --fast        compress faster
          -9, --best        compress better
        
        With no FILE, or when FILE is -, read standard input.]])
        return
    elseif v == "-k" or v == "--keep" then keep = true
    elseif v == "-l" or v == "--list" then mode = 2
    elseif v == "-t" or v == "--test" then mode = 3
    elseif v == "-v" or v == "--verbose" then verbose = true
    elseif v == "-V" or v == "--version" then 
        print("gzip v1.0")
        return
    elseif v == "-1" or v == "--fast" then level = 1
    elseif v == "-9" or v == "--best" then level = 9
    elseif input == nil then
        if v == "-" then
            input = "stdin"
            output = "stdout"
        else
            input = v
        end
    end
end

if input == nil then input = "stdin" end
if output == nil then 
    if mode == 0 and input ~= "stdin" then output = input .. ".gz"
    elseif mode == 1 and input ~= "stdin" then output = string.gsub(input, ".gz", "")
    else output = "stdout" end
end

local function readInput()
    if input == "stdin" then
        local retval = ""
        local line = read()
        while line ~= nil do
            retval = retval .. line
            line = read()
        end
        return retval
    else
        local file = fs.open(shell.resolve(input), "rb")
        local retval = ""
        local b = file.read()
        while b ~= nil do
            retval = retval .. string.char(b)
            b = file.read()
            if string.len(retval) % 40960 == 0 then
                os.queueEvent("nosleep")
                os.pullEvent()
            end
        end
        file.close()
        return retval
    end
end

local function writeOutput(str)
    if str == nil then error(input .. ": not in gzip format", 2) end
    if output == "stdout" then write(str) else
        local file = fs.open(shell.resolve(output), "wb")
        for s in string.gmatch(str, ".") do file.write(string.byte(s)) end
        file.close()
    end
    if verbose and output ~= "stdout" then print("Wrote " .. string.len(str) .. " bytes") end
end

if output ~= "stdout" and not overwrite and fs.exists(output) then error(output .. ": File exists") end
if mode == 0 then -- compress
    writeOutput(LibDeflate:CompressGzip(readInput(), {level=level}))
elseif mode == 1 then -- decompress
    writeOutput(LibDeflate:DecompressGzip(readInput()))
elseif mode == 2 then -- list
    local info = LibDeflate.internal.GetGzipInfo(readInput())
    if info == nil then error(input .. ": not in gzip format") end
    local keys = {}
    local vals = {}
    for k,v in pairs(info) do
        table.insert(keys, k)
        table.insert(vals, v)
    end
    textutils.tabulate(keys, vals)
elseif mode == 3 then -- test
    local gzip, err = LibDeflate:DecompressGzip(readInput())
    if gzip == nil then
        if err == -2 then error(input .. ": invalid compressed data--crc error")
        elseif err == -1 then error(input .. ": not in gzip format")
        elseif err == -3 then error(input .. " has unsupported flags")
        elseif err == -4 then error(input .. ": unknown method -- not supported")
        else error(input .. ": unknown error") end
    end
    if verbose then print(input .. ":    OK") end
else error("This should never happen.") end
if not keep and input ~= "stdin" and output ~= "stdout" then fs.delete(input) end