local muxzcat = require "muxzcat"

local function help()
    print([[Usage: unxz [OPTION]... [FILE]...
Decompress FILEs in the .xz format.

  -k, --keep         keep (don't delete) input files
  -f, --force        force overwrite of output file
  -c, --stdout       write to standard output and don't delete input files
  -h, --help         display this help and exit
  -V, --version      display the version number and exit

Report bugs to https://github.com/MCJack123/CC-Archive/issues.
Uses JackMacWindows's Lua port of muxzcat. Licensed under GPL v2.0.]])
end

local input = {}
local keep = false
local force = false
local stdout = false
local ignoreCheck = false

for _,v in ipairs({...}) do
    if #v == 2 then
        if v == "-z" or v == "-t" or v == "-l" then error("unxz: This program only supports decompression.")
        elseif v == "-k" then keep = true
        elseif v == "-f" then force = true
        elseif v == "-c" then stdout = true; keep = true
        elseif v == "-h" then return help()
        elseif v == "-V" then print("unxz 0.9 for ComputerCraft"); return end
    elseif v:sub(1, 2) == "--" then
        if v == "--compress" or v == "--test" or v == "--list" then error("unxz: This program only supports decompression.")
        elseif v == "--keep" then keep = true
        elseif v == "--force" then force = true
        elseif v == "--stdout" or v == "--to-stdout" then stdout = true
        elseif v == "--ignore-check" then ignoreCheck = true
        elseif v == "--help" then return help()
        elseif v == "--version" then print("unxz 0.9 for ComputerCraft"); return end
    else table.insert(input, shell.resolve(v)) end
end

local good = true

if #input == 0 then error("unxz: Missing input. Type --help for help.") end
for _,v in ipairs(input) do
    if not fs.exists(v) then io.stderr:write("unxz: Could not open " .. v .. ": File not found\n")
    elseif fs.isDir(v) then io.stderr:write("unxz: Could not open " .. v .. ": Is a directory\n")
    elseif v:sub(-3) ~= ".xz" then io.stderr:write("unxz: " .. v .. ": Filename has an unknown suffix, skipping\n")
    elseif fs.exists(v:sub(1, -4)) and not force then io.stderr:write("unxz: " .. v:sub(1, -4) .. ": File exists\n")
    elseif stdout then
        local file = fs.open(v, "rb")
        local data
        if file.seek then data = file.read(fs.getSize(v)) else
            data = ""
            for i = 1, fs.getSize(v) do data = data .. string.char(file.read()) end
        end
        file.close()
        local str, err = muxzcat.DecompressXzOrLzmaString(data)
        if str == nil then io.stderr:write("unxz: " .. v .. ": Could not decompress: " .. muxzcat.GetError(err) .. "\n"); good = false else io.stdout:write(str) end
    else
        local ok, err = muxzcat.DecompressXzOrLzmaFile(v, v:sub(1, -4))
        if not ok then io.stderr:write("unxz: " .. v .. ": Could not decompress: " .. muxzcat.GetError(err) .. "\n"); good = false
        elseif not keep then fs.delete(v) end
    end
end

return good