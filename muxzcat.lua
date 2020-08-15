--[[
    XZ/LZMA decompressor ported from https://github.com/pts/muxzcat
    Licensed under GNU GPL 2.0 or later
    This should work under all Lua 5.1+
    To use:
        muxzcat.DecompressXzOrLzmaFile(input, output) will read an XZ/LZMA file from input (FILE* or path) and write the result to output (FILE* or path)
        muxzcat.DecompressXzOrLzmaString(input) will decompress a loaded XZ/LZMA file and returns the result
        muxzcat.GetError(num) will return a string representation for an error code
        muxzcat.ErrorCodes is a table that reverses GetError()
    Written by pts@fazekas.hu at Sat Feb  2 13:28:42 CET 2019
    Ported to Lua by JackMacWindows
]]

local bitlib
if bit32 ~= nil then bitlib = bit32
elseif pcall(require, "bit32") then bitlib = require "bit32"
elseif pcall(require, "bit") then bitlib = require "bit"
elseif bit ~= nil then bitlib = bit
else
    --[[---------------
    LuaBit v0.4
    -------------------
    a bitwise operation lib for lua.

    http:

    How to use:
    -------------------
    bit.bnot(n) -- bitwise not (~n)
    bit.band(m, n) -- bitwise and (m & n)
    bit.bor(m, n) -- bitwise or (m | n)
    bit.bxor(m, n) -- bitwise xor (m ^ n)
    bit.brshift(n, bits) -- right shift (n >> bits)
    bit.blshift(n, bits) -- left shift (n << bits)
    bit.blogic_rshift(n, bits) -- logic right shift(zero fill >>>)

    Please note that bit.brshift and bit.blshift only support number within
    32 bits.

    2 utility functions are provided too:
    bit.tobits(n) -- convert n into a bit table(which is a 1/0 sequence)
    -- high bits first
    bit.tonumb(bit_tbl) -- convert a bit table into a number
    -------------------

    Under the MIT license.

    copyright(c) 2006~2007 hanzhao (abrash_han@hotmail.com)
    --]]---------------
    ------------------------
    -- bit lib implementions

    local function check_int(n)
        -- checking not float
        if(n - math.floor(n) > 0) then
            error("trying to use bitwise operation on non-integer!")
        end
    end

    local function to_bits(n)
        check_int(n)
        if(n < 0) then
            -- negative
            return to_bits(bitlib.bnot(math.abs(n)) + 1)
        end
        -- to bits table
        local tbl = {}
        local cnt = 1
        while (n > 0) do
            local last = math.mod(n,2)
            if(last == 1) then
                tbl[cnt] = 1
            else
                tbl[cnt] = 0
            end
            n = (n-last)/2
            cnt = cnt + 1
        end

        return tbl
    end

    local function tbl_to_number(tbl)
        local n = table.getn(tbl)

        local rslt = 0
        local power = 1
        for i = 1, n do
            rslt = rslt + tbl[i]*power
            power = power*2
        end

        return rslt
    end

    local function expand(tbl_m, tbl_n)
        local big = {}
        local small = {}
        if(table.getn(tbl_m) > table.getn(tbl_n)) then
            big = tbl_m
            small = tbl_n
        else
            big = tbl_n
            small = tbl_m
        end
        -- expand small
        for i = table.getn(small) + 1, table.getn(big) do
            small[i] = 0
        end

    end

    local function bit_or(m, n)
        local tbl_m = to_bits(m)
        local tbl_n = to_bits(n)
        expand(tbl_m, tbl_n)

        local tbl = {}
        local rslt = math.max(table.getn(tbl_m), table.getn(tbl_n))
        for i = 1, rslt do
            if(tbl_m[i]== 0 and tbl_n[i] == 0) then
                tbl[i] = 0
            else
                tbl[i] = 1
            end
        end

        return tbl_to_number(tbl)
    end

    local function bit_and(m, n)
        local tbl_m = to_bits(m)
        local tbl_n = to_bits(n)
        expand(tbl_m, tbl_n)

        local tbl = {}
        local rslt = math.max(table.getn(tbl_m), table.getn(tbl_n))
        for i = 1, rslt do
            if(tbl_m[i]== 0 or tbl_n[i] == 0) then
                tbl[i] = 0
            else
                tbl[i] = 1
            end
        end

        return tbl_to_number(tbl)
    end

    local function bit_not(n)

        local tbl = to_bits(n)
        local size = math.max(table.getn(tbl), 32)
        for i = 1, size do
            if(tbl[i] == 1) then
                tbl[i] = 0
            else
                tbl[i] = 1
            end
        end
        return tbl_to_number(tbl)
    end

    local function bit_xor(m, n)
        local tbl_m = to_bits(m)
        local tbl_n = to_bits(n)
        expand(tbl_m, tbl_n)

        local tbl = {}
        local rslt = math.max(table.getn(tbl_m), table.getn(tbl_n))
        for i = 1, rslt do
            if(tbl_m[i] ~= tbl_n[i]) then
                tbl[i] = 1
            else
                tbl[i] = 0
            end
        end

        --table.foreach(tbl, --print)

        return tbl_to_number(tbl)
    end

    local function bit_rshift(n, bits)
        check_int(n)

        local high_bit = 0
        if(n < 0) then
            -- negative
            n = bit_not(math.abs(n)) + 1
            high_bit = 2147483648 -- 0x80000000
        end

        for i=1, bits do
            n = n/2
            n = bit_or(math.floor(n), high_bit)
        end
        return math.floor(n)
    end

    -- logic rightshift assures zero filling shift
    local function bit_logic_rshift(n, bits)
        check_int(n)
        if(n < 0) then
            -- negative
            n = bit_not(math.abs(n)) + 1
        end
        for i=1, bits do
            n = n/2
        end
        return math.floor(n)
    end

    local function bit_lshift(n, bits)
        check_int(n)

        if(n < 0) then
            -- negative
            n = bit_not(math.abs(n)) + 1
        end

        for i=1, bits do
            n = n*2
        end
        return bit_and(n, 4294967295) -- 0xFFFFFFFF
    end

    --------------------
    -- bit lib interface

    bitlib = {
        -- bit operations
        bnot = bit_not,
        band = bit_and,
        bor = bit_or,
        bxor = bit_xor,
        brshift = bit_rshift,
        blshift = bit_lshift,
        blogic_rshift = bit_logic_rshift,
    }
end
if bitlib.blogic_rshift then
    bitlib = {
        arshift = bitlib.brshift,
        band = bitlib.band,
        bnot = bitlib.bnot,
        bor = bitlib.bor,
        btest = function(a, b) return bitlib.band(a, b) ~= 0 end,
        bxor = bitlib.bxor,
        lshift = bitlib.blshift,
        rshift = bitlib.blogic_rshift
    }
end

local band = {}
local bor = {}
local bxor = {}
local bnot = {}
local blshift = {}
local brshift = {}

setmetatable(band, {__sub = function(lhs)
    local mt = {lhs, __sub = function(self, b) return bitlib.band(self[1], b) end}
    return setmetatable(mt, mt)
end})

setmetatable(bor, {__sub = function(lhs)
    local mt = {lhs, __sub = function(self, b) return bitlib.bor(self[1], b) end}
    return setmetatable(mt, mt)
end})

setmetatable(bxor, {__sub = function(lhs)
    local mt = {lhs, __sub = function(self, b) return bitlib.bxor(self[1], b) end}
    return setmetatable(mt, mt)
end})

setmetatable(blshift, {__sub = function(lhs)
    local mt = {lhs, __sub = function(self, b) return bitlib.lshift(self[1], b) end}
    return setmetatable(mt, mt)
end})

setmetatable(brshift, {__sub = function(lhs)
    local mt = {lhs, __sub = function(self, b) return bitlib.rshift(self[1], b) end}
    return setmetatable(mt, mt)
end})

setmetatable(bnot, {__sub = function(_, rhs) return bitlib.bnot(rhs) end})

local str_input, str_output

local function writeTableSeq(tab, i, n, ...) if n ~= nil then tab[i] = n return writeTableSeq(tab, i+1, ...) end end

local function READ_FROM_STDIN_TO_ARY8(a, fromIdx, size)
    local str
    if str_input then
        str, str_input = str_input:sub(1, size), str_input:sub(size+1)
        for i = 1, #str, 256 do writeTableSeq(a, fromIdx + i - 1, str:byte(i, i + 256)) end
        return #str
    else
        str = io.input():read(size)
        for i = 1, #str, 256 do writeTableSeq(a, fromIdx + i - 1, str:byte(i, i + 256)) end
        --assert(#a - fromIdx == #str - 1, (#a - fromIdx) .. ", " .. #str .. ", " .. size)
        return #str
    end
end

local function readTableSeq(tab, i, j) if i == j then return tab[i] elseif i > j then return nil else return tab[i], readTableSeq(tab, i+1, j) end end

local function WRITE_TO_STDOUT_FROM_ARY8(a, fromIdx, size)
    if str_output then
        for i = fromIdx, fromIdx + size - 1, 256 do str_output = str_output .. string.char(readTableSeq(a, i, math.min(fromIdx + size - 1, i + 255))) end
        return size
    else
        for i = 1, size, 256 do io.output():write(string.char(readTableSeq(a, i+fromIdx-1, math.min(fromIdx + size - 1, i + fromIdx + 254)))) end
        return size
    end
end

local bufCur = 0;
local dicSize = 0;
local range = 0;
local code = 0;
local dicPos = 0;
local dicBufSize = 0;
local processedPos = 0;
local checkDicSize = 0;
local state = 0;
local rep0 = 1;
local rep1 = 1;
local rep2 = 1;
local rep3 = 1;
local remainLen = 0;
local tempBufSize = 0;
local readCur = 0;
local readEnd = 0;
local needFlush = 0;
local needInitLzma = 0;
local needInitDic = 0;
local needInitState = 0;
local needInitProp = 0;
local lc = 0;
local lp = 0;
local pb = 0;
local lcm8 = 0;
local _probs16 = {}
local probs16 = setmetatable({}, {__index = function(_, idx) return _probs16[idx] --[[-band- 0xFFFF]] end, __newindex = function(_, idx, val) _probs16[idx] = val -band- 0xFFFF end});
local _readBuf8 = {}
local readBuf8 = setmetatable({}, {__index = function(_, idx) return _readBuf8[idx] --[[-band- 0xFF]] end, __newindex = function(_, idx, val) _readBuf8[idx] = val -band- 0xFF end});
local _dic8 = {}
local dic8 = setmetatable({}, {__index = function(_, idx) return _dic8[idx] --[[-band- 0xFF]] end, __newindex = function(_, idx, val) _dic8[idx] = val -band- 0xFF end});

local function ResetGlobals()
    bufCur = 0;
    dicSize = 0;
    range = 0;
    code = 0;
    dicPos = 0;
    dicBufSize = 0;
    processedPos = 0;
    checkDicSize = 0;
    state = 0;
    rep0 = 1;
    rep1 = 1;
    rep2 = 1;
    rep3 = 1;
    remainLen = 0;
    tempBufSize = 0;
    readCur = 0;
    readEnd = 0;
    needFlush = 0;
    needInitLzma = 0;
    needInitDic = 0;
    needInitState = 0;
    needInitProp = 0;
    lc = 0;
    lp = 0;
    pb = 0;
    lcm8 = 0;
    _probs16 = {}
    _readBuf8 = {}
    _dic8 = {}
end

local function LzmaDec_WriteRem(wrDicLimit)

    if (((remainLen) ~= (0)) and ((remainLen) < (274))) then
        local wrLen = remainLen;
        if (((wrDicLimit - dicPos) < (wrLen))) then
            wrLen = wrDicLimit - dicPos ;
        end
        if (((checkDicSize) == (0)) and ((dicSize - processedPos) <= (wrLen))) then
            checkDicSize = dicSize;
        end
        processedPos = processedPos + wrLen;
        remainLen = remainLen - wrLen;
        while (((wrLen) ~= (0))) do
            wrLen=wrLen-1;
            dic8[dicPos] = dic8[(dicPos - rep0) + (((dicPos) < (rep0)) and dicBufSize or 0)] -band- 0xFF;
            dicPos=dicPos+1;
        end
    end
end


local function LzmaDec_DecodeReal2(drDicLimit, drBufLimit)
    local pbMask = ((1) -blshift- (pb)) - 1;
    local lpMask = ((1) -blshift- (lp)) - 1;
    local drI = 0;
    local lastTime
    if textutils then 
        os.queueEvent("nosleep")
        lastTime = os.epoch("utc")
    end

    repeat
        local drDicLimit2 = (((checkDicSize) == (0)) and ((dicSize - processedPos) < (drDicLimit - dicPos))) and (dicPos + (dicSize - processedPos)) or drDicLimit;
        --print("drDicLimit2", drDicLimit2, "checkDicSize", checkDicSize, "dicSize", dicSize, "processedPos", processedPos, "drDicLimit", drDicLimit, "dicPos", dicPos)
        remainLen = 0;
        repeat
            local drProbIdx = 0;
            local drBound = 0;
            local drTtt = 0;
            local distance = 0;
            local drPosState = processedPos -band- pbMask;
            if textutils and os.epoch("utc") - lastTime > 3000 then 
                --write(".")
                lastTime = os.epoch("utc")
                os.queueEvent(os.pullEvent())
            end
            --print(rep0, rep1, rep2, rep3)
            drProbIdx = 0 + (state -blshift- (4)) + drPosState ;
            drTtt = probs16[drProbIdx] ;
            if (((range) < (16777216))) then
                range = range -blshift- (8) ;
                code = ((code -blshift- 8) -bor- (readBuf8[bufCur])) ;
                bufCur = bufCur + 1;
            end
            drBound = (bitlib.rshift((range), 11)) * drTtt ;
            if (((code) < (drBound))) then
                local drSymbol = 0;
                assert((drTtt <= 0x7fffffff) and ((drTtt) <= (2048)));
                range = (drBound) ;
                probs16[drProbIdx] = drTtt + ((bitlib.rshift((2048 - drTtt), (5))));
                drProbIdx = 1846 ;
                if (((checkDicSize) ~= (0)) or ((processedPos) ~= (0))) then
                    drProbIdx = drProbIdx + (768 * (((processedPos -band- lpMask) -blshift- lc) + (bitlib.rshift((dic8[(((dicPos) == (0)) and dicBufSize or dicPos) - 1]), (lcm8))))) ;
                end
                if (((state) < (7))) then
                    state = state - ((((state) < (4))) and state or 3);
                    drSymbol = 1 ;
                    repeat
                        drTtt = probs16[drProbIdx + drSymbol] ;
                        if (((range) < (16777216))) then
                            range = range -blshift- (8) ;
                            code = ((code -blshift- 8) -bor- (readBuf8[bufCur])) ;
                            bufCur=bufCur+1;
                        end
                        drBound = ((bitlib.rshift((range), 11))) * drTtt ;
                        if (((code) < (drBound))) then
                            range = (drBound) ;
                            probs16[drProbIdx + drSymbol] = drTtt + (bitlib.rshift((2048 - drTtt), (5)));
                            drSymbol = (drSymbol + drSymbol);
                        else
                            range = range - (drBound) ;
                            code = code - (drBound) ;
                            probs16[drProbIdx + drSymbol] = drTtt - (bitlib.rshift((drTtt), (5)));
                            drSymbol = (drSymbol + drSymbol) + 1;
                        end
                    until not (((drSymbol) < (0x100)))
                else
                    local drMatchByte = dic8[(dicPos - rep0) + (((dicPos) < (rep0)) and dicBufSize or 0)];
                    local drMatchMask = 0x100;
                    state = state - (((state) < (10)) and 3 or 6);
                    drSymbol = 1 ;
                    repeat
                        local drBit;
                        local drProbLitIdx;
                        assert(drMatchMask == 0 or drMatchMask == 0x100);
                        drMatchByte = drMatchByte -blshift- 1 ;
                        drBit = (drMatchByte -band- drMatchMask) ;
                        drProbLitIdx = drProbIdx + drMatchMask + drBit + drSymbol ;
                        drTtt = probs16[drProbLitIdx] ;
                        if (((range) < (16777216))) then
                            range = range -blshift- (8) ;
                            code = ((code -blshift- 8) -bor- (readBuf8[bufCur])) ;
                            bufCur=bufCur+1;
                        end
                        drBound = (bitlib.rshift((range), 11)) * drTtt ;
                        if (((code) < (drBound))) then
                            range = (drBound) ;
                            probs16[drProbLitIdx] = drTtt + (bitlib.rshift((2048 - drTtt), (5)));
                            drSymbol = (drSymbol + drSymbol) ;
                            drMatchMask = drMatchMask -band- (bnot-drBit) ;
                        else
                            range = range - (drBound) ;
                            code = code - (drBound) ;
                            probs16[drProbLitIdx] = drTtt - (bitlib.rshift((drTtt), (5)));
                            drSymbol = (drSymbol + drSymbol) + 1 ;
                            drMatchMask = drMatchMask -band- drBit ;
                        end
                    until not (((drSymbol) < (0x100)));
                end
                dic8[dicPos] = drSymbol -band- 0xFF;
                dicPos=dicPos+1;
                processedPos=processedPos+1;
                --print("continue2")
            else
                range = range - (drBound) ;
                code = code - (drBound) ;
                probs16[drProbIdx] = drTtt - (bitlib.rshift((drTtt), (5)));
                drProbIdx = 192 + state ;
                drTtt = probs16[drProbIdx] ;
                if (((range) < (16777216))) then
                    range = range -blshift- (8) ;
                    code = ((code -blshift- 8) -bor- (readBuf8[bufCur])) ;
                    bufCur=bufCur+1;
                end
                drBound = (bitlib.rshift((range), 11)) * drTtt ;
                local shouldContinue = true
                if (((code) < (drBound))) then
                    assert((drTtt <= 0x7fffffff) and ((drTtt) <= (2048)));
                    range = (drBound) ;
                    probs16[drProbIdx] = drTtt + (bitlib.rshift((2048 - drTtt), (5)));
                    state = state + 12;
                    drProbIdx = 818 ;
                else
                    range = range - (drBound) ;
                    code = code - (drBound) ;
                    probs16[drProbIdx] = drTtt - (bitlib.rshift((drTtt), (5)));
                    if (((checkDicSize) == (0)) and ((processedPos) == (0))) then
                        --print("A")
                        return 1;
                    end
                    drProbIdx = 204 + state ;
                    drTtt = probs16[drProbIdx] ;
                    if (((range) < (16777216))) then
                        range = range -blshift- (8) ;
                        code = ((code -blshift- 8) -bor- (readBuf8[bufCur])) ;
                        bufCur=bufCur+1;
                    end
                    drBound = (bitlib.rshift((range), 11)) * drTtt ;
                    if (((code) < (drBound))) then
                        assert((drTtt <= 0x7fffffff) and ((drTtt) <= (2048)));
                        range = (drBound) ;
                        probs16[drProbIdx] = drTtt + (bitlib.rshift((2048 - drTtt), (5)));
                        drProbIdx = 240 + (state -blshift- (4)) + drPosState ;
                        drTtt = probs16[drProbIdx] ;
                        if (((range) < (16777216))) then
                            range = range -blshift- (8) ;
                            code = ((code -blshift- 8) -bor- (readBuf8[bufCur])) ;
                            bufCur=bufCur+1;
                        end
                        drBound = (bitlib.rshift((range), 11)) * drTtt ;
                        if (((code) < (drBound))) then
                            range = (drBound) ;
                            probs16[drProbIdx] = drTtt + (bitlib.rshift((2048 - drTtt), (5)));
                            dic8[dicPos] = dic8[(dicPos - rep0) + (((dicPos) < (rep0)) and dicBufSize or 0)] -band- 0xFF;
                            dicPos=dicPos+1;
                            processedPos=processedPos+1;
                            state = ((state) < (7)) and 9 or 11;
                            --print("continue")
                            shouldContinue = false
                        end
                        if shouldContinue then
                            range = range - (drBound) ;
                            code = code - (drBound) ;
                            probs16[drProbIdx] = drTtt - (bitlib.rshift((drTtt), (5)));
                        end
                    else
                        range = range - (drBound) ;
                        code = code - (drBound) ;
                        probs16[drProbIdx] = drTtt - (bitlib.rshift((drTtt), (5)));
                        drProbIdx = 216 + state ;
                        drTtt = probs16[drProbIdx] ;
                        if (((range) < (16777216))) then
                            range = range -blshift- (8) ;
                            code = ((code -blshift- 8) -bor- (readBuf8[bufCur])) ;
                            bufCur=bufCur+1;
                        end
                        drBound = (bitlib.rshift((range), 11)) * drTtt ;
                        if (((code) < (drBound))) then
                            range = (drBound) ;
                            probs16[drProbIdx] = drTtt + (bitlib.rshift((2048 - drTtt), (5)));
                            distance = rep1 ;
                        else
                            range = range - (drBound) ;
                            code = code - (drBound) ;
                            probs16[drProbIdx] = drTtt - (bitlib.rshift((drTtt), (5)));
                            drProbIdx = 228 + state ;
                            drTtt = probs16[drProbIdx] ;
                            if (((range) < (16777216))) then
                                range = range -blshift- (8) ;
                                code = ((code -blshift- 8) -bor- (readBuf8[bufCur])) ;
                                bufCur=bufCur+1;
                            end
                            drBound = (bitlib.rshift((range), 11)) * drTtt ;
                            if (((code) < (drBound))) then
                                range = (drBound) ;
                                probs16[drProbIdx] = drTtt + (bitlib.rshift((2048 - drTtt), (5)));
                                distance = rep2 ;
                            else
                                range = range - (drBound) ;
                                code = code - (drBound) ;
                                probs16[drProbIdx] = drTtt - (bitlib.rshift((drTtt), (5)));
                                distance = rep3 ;
                                rep3 = rep2;
                            end
                            rep2 = rep1;
                        end
                        rep1 = rep0;
                        rep0 = distance;
                    end
                    if shouldContinue then
                        state = ((state) < (7)) and 8 or 11;
                        drProbIdx = 1332 ;
                    end
                end
                if shouldContinue then
                    --print(distance)
                    do
                        local drLimitSub;
                        local drOffset;
                        local drProbLenIdx = drProbIdx + 0;
                        drTtt = probs16[drProbLenIdx] ;
                        if (((range) < (16777216))) then
                            range = range -blshift- (8) ;
                            code = ((code -blshift- 8) -bor- (readBuf8[bufCur])) ;
                            bufCur=bufCur+1;
                        end
                        drBound = (bitlib.rshift((range), 11)) * drTtt ;
                        if (((code) < (drBound))) then
                            assert((drTtt <= 0x7fffffff) and ((drTtt) <= (2048)));
                            range = (drBound) ;
                            probs16[drProbLenIdx] = drTtt + (bitlib.rshift((2048 - drTtt), (5)));
                            drProbLenIdx = drProbIdx + 2 + (drPosState -blshift- (3)) ;
                            drOffset = 0 ;
                            drLimitSub = (8) ;
                        else
                            range = range - (drBound) ;
                            code = code - (drBound) ;
                            probs16[drProbLenIdx] = drTtt - (bitlib.rshift((drTtt), (5)));
                            drProbLenIdx = drProbIdx + 1 ;
                            drTtt = probs16[drProbLenIdx] ;
                            if (((range) < (16777216))) then
                                range = range -blshift- (8) ;
                                code = ((code -blshift- 8) -bor- (readBuf8[bufCur])) ;
                                bufCur=bufCur+1;
                            end
                            drBound = (bitlib.rshift((range), 11)) * drTtt ;
                            if (((code) < (drBound))) then
                                assert((drTtt <= 0x7fffffff) and ((drTtt) <= (2048)));
                                range = (drBound) ;
                                probs16[drProbLenIdx] = drTtt + (bitlib.rshift((2048 - drTtt), (5)));
                                drProbLenIdx = drProbIdx + 130 + (drPosState -blshift- (3)) ;
                                drOffset = 8 ;
                                drLimitSub = 8 ;
                            else
                                range = range - (drBound) ;
                                code = code - (drBound) ;
                                probs16[drProbLenIdx] = drTtt - (bitlib.rshift((drTtt), (5)));
                                drProbLenIdx = drProbIdx + 258 ;
                                drOffset = 8 + 8 ;
                                drLimitSub = 256 ;
                            end
                        end
                        do
                            remainLen = (1) ;
                            repeat
                                drTtt = probs16[(drProbLenIdx + remainLen)] ;
                                if (((range) < (16777216))) then
                                    range = range -blshift- (8) ;
                                    code = ((code -blshift- 8) -bor- (readBuf8[bufCur])) ;
                                    bufCur=bufCur+1;
                                end
                                drBound = (bitlib.rshift((range), 11)) * drTtt ;
                                if (((code) < (drBound))) then
                                    range = (drBound) ;
                                    probs16[(drProbLenIdx + remainLen)] = drTtt + (bitlib.rshift((2048 - drTtt), (5)));
                                    remainLen = ((remainLen + remainLen));
                                else
                                    range = range - (drBound) ;
                                    code = code - (drBound) ;
                                    probs16[(drProbLenIdx + remainLen)] = drTtt - (bitlib.rshift((drTtt), (5)));
                                    remainLen = ((remainLen + remainLen) + 1);
                                end
                            until not (((remainLen) < (drLimitSub)));
                            remainLen = remainLen - (drLimitSub) ;
                        end
                        remainLen = remainLen + (drOffset) ;
                    end

                    if (((state) >= (12))) then
                        drProbIdx = 432 + ((((remainLen) < (4)) and remainLen or 4 - 1) -blshift- (6)) ;
                        do
                            distance = 1 ;
                            repeat
                                drTtt = probs16[(drProbIdx + distance)] ;
                                if (((range) < (16777216))) then
                                    range = range -blshift- (8) ;
                                    code = ((code -blshift- 8) -bor- (readBuf8[bufCur])) ;
                                    bufCur=bufCur+1;
                                end
                                drBound = (bitlib.rshift((range), 11)) * drTtt ;
                                if (((code) < (drBound))) then
                                    range = (drBound) ;
                                    probs16[(drProbIdx + distance)] = drTtt + (bitlib.rshift((2048 - drTtt), (5)));
                                    distance = (distance + distance);
                                else
                                    range = range - (drBound) ;
                                    code = code - (drBound) ;
                                    probs16[(drProbIdx + distance)] = drTtt - (bitlib.rshift((drTtt), (5)));
                                    distance = (distance + distance) + 1;
                                end
                            until not (((distance) < ((64))));
                            distance = distance - (64) ;
                        end
                        assert((distance <= 0x7fffffff) and ((distance) < (64)));
                        if (((distance) >= (4))) then
                            local drPosSlot = distance;
                            local drDirectBitCount = (bitlib.rshift((distance), (1))) - 1;
                            distance = (2 -bor- (distance -band- 1)) ;
                            if (((drPosSlot) < (14))) then
                                distance = distance -blshift- drDirectBitCount ;
                                drProbIdx = 688 + distance - drPosSlot - 1 ;
                                do
                                    local mask = 1;
                                    drI = 1;
                                    repeat
                                        drTtt = probs16[drProbIdx + drI] ;
                                        if (((range) < (16777216))) then
                                            range = range -blshift- (8) ;
                                            code = ((code -blshift- 8) -bor- (readBuf8[bufCur])) ;
                                            bufCur=bufCur+1;
                                        end
                                        drBound = (bitlib.rshift((range), 11)) * drTtt ;
                                        if (((code) < (drBound))) then
                                            range = (drBound) ;
                                            probs16[drProbIdx + drI] = drTtt + (bitlib.rshift((2048 - drTtt), (5)));
                                            drI = (drI + drI);
                                        else
                                            range = range - (drBound) ;
                                            code = code - (drBound) ;
                                            probs16[drProbIdx + drI] = drTtt - (bitlib.rshift((drTtt), (5)));
                                            drI = (drI + drI) + 1 ;
                                            distance = distance -bor- mask ;
                                        end
                                        mask = mask -blshift- 1 ;
                                        drDirectBitCount = drDirectBitCount - 1
                                    until not (((drDirectBitCount) ~= (0)));
                                end
                            else
                                drDirectBitCount = drDirectBitCount - 4 ;
                                repeat
                                    if (((range) < (16777216))) then
                                        range = range -blshift- (8) ;
                                        code = ((code -blshift- 8) -bor- (readBuf8[bufCur])) ;
                                        bufCur=bufCur+1;
                                    end

                                    range = ((bitlib.rshift((range), 1)));
                                    if (((code - range) -band- 0x80000000 ~= 0)) then
                                        distance = distance -blshift- 1;
                                    else
                                        code = code - (range);

                                        distance = (distance -blshift- 1) + 1;
                                    end
                                    drDirectBitCount = drDirectBitCount-1;
                                until not (((drDirectBitCount) ~= (0)));
                                drProbIdx = 802 ;
                                distance = distance -blshift- 4 ;
                                do
                                    drI = 1;
                                    drTtt = probs16[drProbIdx + drI];
                                    assert((drTtt <= 0x7fffffff) and ((drTtt) <= (2048)));
                                    if (((range) < (16777216))) then
                                        range = range -blshift- (8) ;
                                        code = ((code -blshift- 8) -bor- (readBuf8[bufCur])) ;
                                        bufCur=bufCur+1;
                                    end
                                    drBound = (bitlib.rshift((range), 11)) * drTtt ;
                                    if (((code) < (drBound))) then
                                        range = (drBound) ;
                                        probs16[drProbIdx + drI] = drTtt + (bitlib.rshift((2048 - drTtt), (5)));
                                        drI = (drI + drI);
                                    else
                                        range = range - (drBound) ;
                                        code = code - (drBound) ;
                                        probs16[drProbIdx + drI] = drTtt - (bitlib.rshift((drTtt), (5)));
                                        drI = (drI + drI) + 1 ;
                                        distance = distance -bor- 1 ;
                                    end
                                    drTtt = probs16[drProbIdx + drI];
                                    assert((drTtt <= 0x7fffffff) and ((drTtt) <= (2048)));
                                    if (((range) < (16777216))) then
                                        range = range -blshift- (8) ;
                                        code = ((code -blshift- 8) -bor- (readBuf8[bufCur])) ;
                                        bufCur=bufCur+1;
                                    end
                                    drBound = (bitlib.rshift((range), 11)) * drTtt ;
                                    if (((code) < (drBound))) then
                                        range = (drBound) ;
                                        probs16[drProbIdx + drI] = drTtt + (bitlib.rshift((2048 - drTtt), (5)));
                                        drI = (drI + drI);
                                    else range = range - (drBound) ;
                                        code = code - (drBound) ;
                                        probs16[drProbIdx + drI] = drTtt - (bitlib.rshift((drTtt), (5)));
                                        drI = (drI + drI) + 1 ;
                                        distance = distance -bor- 2 ;
                                    end
                                    drTtt = probs16[drProbIdx + drI];
                                    assert((drTtt <= 0x7fffffff) and ((drTtt) <= (2048)));
                                    if (((range) < (16777216))) then
                                        range = range -blshift- (8) ;
                                        code = ((code -blshift- 8) -bor- (readBuf8[bufCur])) ;
                                        bufCur=bufCur+1;
                                    end
                                    drBound = (bitlib.rshift((range), 11)) * drTtt ;
                                    if (((code) < (drBound))) then
                                        range = (drBound) ;
                                        probs16[drProbIdx + drI] = drTtt + (bitlib.rshift((2048 - drTtt), (5)));
                                        drI = (drI + drI);
                                    else range = range - (drBound) ;
                                        code = code - (drBound) ;
                                        probs16[drProbIdx + drI] = drTtt - (bitlib.rshift((drTtt), (5)));
                                        drI = (drI + drI) + 1 ;
                                        distance = distance -bor- 4 ;
                                    end
                                    drTtt = probs16[drProbIdx + drI];
                                    assert((drTtt <= 0x7fffffff) and ((drTtt) <= (2048)));
                                    if (((range) < (16777216))) then
                                        range = range -blshift- (8) ;
                                        code = ((code -blshift- 8) -bor- (readBuf8[bufCur])) ;
                                        bufCur=bufCur+1;
                                    end
                                    drBound = (bitlib.rshift((range), 11)) * drTtt ;
                                    if (((code) < (drBound))) then
                                        range = (drBound) ;
                                        probs16[drProbIdx + drI] = drTtt + (bitlib.rshift((2048 - drTtt), (5)));
                                        drI = (drI + drI);
                                    else range = range - (drBound) ;
                                        code = code - (drBound) ;
                                        probs16[drProbIdx + drI] = drTtt - (bitlib.rshift((drTtt), (5)));
                                        drI = (drI + drI) + 1 ;
                                        distance = distance -bor- 8 ;
                                    end
                                end
                                if (((bnot-distance) == 0)) then
                                    remainLen = remainLen + (274) ;
                                    state = state - 12;
                                    --print("break")
                                    break;
                                end
                            end
                        end

                        assert((distance <= 0x7fffffff) and ((distance) <= (1610612736)));
                        rep3 = rep2;
                        rep2 = rep1;
                        rep1 = rep0;
                        rep0 = distance + 1;
                        if (((checkDicSize) == (0))) then
                            if (((distance) >= (processedPos))) then
                                --print("B")
                                return 1;
                            end
                        else
                            if (((distance) >= (checkDicSize))) then
                                --print("C")
                                return 1;
                            end
                        end
                        state = ((state) < (12 + 7)) and 7 or 7 + 3;
                    end

                    remainLen = remainLen + (2) ;

                    if (((drDicLimit2) == (dicPos))) then
                        --print("D")
                        return 1;
                    end
                    do
                        local drRem = drDicLimit2 - dicPos;
                        local curLen = (((drRem) < (remainLen)) and drRem or remainLen);
                        local pos = (dicPos - rep0) + (((dicPos) < (rep0)) and dicBufSize or 0);

                        processedPos = processedPos + curLen;

                        remainLen = remainLen - (curLen) ;
                        if (((pos + curLen) <= (dicBufSize))) then
                            assert(((dicPos) > (pos)));
                            assert(((curLen) > (0)));
                            repeat

                                dic8[dicPos] = dic8[pos] -band- 0xFF;
                                dicPos=dicPos+1
                                pos=pos+1
                                curLen=curLen-1
                            until not (((curLen) ~= (0)));
                        else
                            repeat
                                dic8[dicPos] = dic8[pos] -band- 0xFF;
                                dicPos=dicPos+1
                                pos=pos+1
                                if (((pos) == (dicBufSize))) then
                                    pos = 0 ;
                                end
                            until not (((curLen) ~= (0)));
                        end
                    end
                end
            end
            --print("drDicLimit2", drDicLimit2, "drBufLimit", drBufLimit, "dicPos", dicPos, "bufCur", bufCur)
        until not (((dicPos) < (drDicLimit2)) and ((bufCur) < (drBufLimit)));

        if (((range) < (16777216))) then
            range = range -blshift- (8) ;
            code = ((code -blshift- 8) -bor- (readBuf8[bufCur])) ;
            bufCur=bufCur+1;
        end
        if (((processedPos) >= (dicSize))) then
            checkDicSize = dicSize;
        end
        LzmaDec_WriteRem(drDicLimit);
    until not (((dicPos) < (drDicLimit)) and ((bufCur) < (drBufLimit)) and ((remainLen) < (274)));

    if (((remainLen) > (274))) then
        remainLen = 274;
    end
    return 0;
end

local function LzmaDec_TryDummy(tdCur, tdBufLimit)
    local tdRange = range;
    local tdCode = code;
    local tdState = state;
    local tdRes;
    local tdProbIdx;
    local tdBound;
    local tdTtt;
    local tdPosState = (processedPos) -band- ((1 -blshift- pb) - 1);


    tdProbIdx = 0 + (tdState -blshift- (4)) + tdPosState ;
    tdTtt = probs16[tdProbIdx] ;
    if (((tdRange) < (16777216))) then
        if (((tdCur) >= (tdBufLimit))) then
            return 0;
        end
        tdRange = tdRange -blshift- 8 ;
        tdCode = (tdCode -blshift- 8) -bor- (readBuf8[tdCur]) ;
        tdCur=tdCur+1;
    end
    tdBound = (bitlib.rshift((tdRange), 11)) * tdTtt ;
    if (((tdCode) < (tdBound))) then
        local tdSymbol = 1;
        tdRange = tdBound ;
        tdProbIdx = 1846 ;
        if (((checkDicSize) ~= (0)) or ((processedPos) ~= (0))) then
            tdProbIdx = tdProbIdx + (768 * ((((processedPos) -band- ((1 -blshift- (lp)) - 1)) -blshift- lc) + (bitlib.rshift((dic8[(((dicPos) == (0)) and dicBufSize or dicPos) - 1]), (lcm8))))) ;
        end

        if (((tdState) < (7))) then
            repeat
                tdTtt = probs16[tdProbIdx + tdSymbol] ;
                if (((tdRange) < (16777216))) then
                    if (((tdCur) >= (tdBufLimit))) then
                        return 0;
                    end
                    tdRange = tdRange -blshift- 8 ;
                    tdCode = (tdCode -blshift- 8) -bor- (readBuf8[tdCur]) ;
                    tdCur=tdCur+1;
                end
                tdBound = (bitlib.rshift((tdRange), 11)) * tdTtt ;
                if (((tdCode) < (tdBound))) then
                    tdRange = tdBound ;
                    tdSymbol = (tdSymbol + tdSymbol);
                else tdRange = tdRange - tdBound ;
                    tdCode = tdCode - tdBound ;
                    tdSymbol = (tdSymbol + tdSymbol) + 1;
                end
            until not (((tdSymbol) < (0x100)));
        else
            local tdMatchByte = dic8[dicPos - rep0 + (((dicPos) < (rep0)) and dicBufSize or 0)];
            local tdMatchMask = 0x100;
            repeat
                local tdBit;
                local tdProbLitIdx;
                assert(tdMatchMask == 0 or tdMatchMask == 0x100);
                tdMatchByte = tdMatchByte -blshift- 1 ;
                tdBit = (tdMatchByte -band- tdMatchMask) ;
                tdProbLitIdx = tdProbIdx + tdMatchMask + tdBit + tdSymbol ;
                tdTtt = probs16[tdProbLitIdx] ;
                if (((tdRange) < (16777216))) then
                    if (((tdCur) >= (tdBufLimit))) then
                        return 0;
                    end
                    tdRange = tdRange -blshift- 8 ;
                    tdCode = (tdCode -blshift- 8) -bor- (readBuf8[tdCur]) ;
                    tdCur=tdCur+1;
                end
                tdBound = (bitlib.rshift((tdRange), 11)) * tdTtt ;
                if (((tdCode) < (tdBound))) then
                    tdRange = tdBound ;
                    tdSymbol = (tdSymbol + tdSymbol) ;
                    tdMatchMask = tdMatchMask -band- (bnot-tdBit) ;
                else tdRange = tdRange - tdBound ;
                    tdCode = tdCode - tdBound ;
                    tdSymbol = (tdSymbol + tdSymbol) + 1 ;
                    tdMatchMask = tdMatchMask -band- tdBit ;
                end
            until not (((tdSymbol) < (0x100)));
        end
        tdRes = 1 ;
    else
        local tdLen;
        tdRange = tdRange - tdBound ;
        tdCode = tdCode - tdBound ;
        tdProbIdx = 192 + tdState ;
        tdTtt = probs16[tdProbIdx] ;
        if (((tdRange) < (16777216))) then
            if (((tdCur) >= (tdBufLimit))) then
                return 0;
            end
            tdRange = tdRange -blshift- 8 ;
            tdCode = (tdCode -blshift- 8) -bor- (readBuf8[tdCur]) ;
            tdCur=tdCur+1;
        end
        tdBound = (bitlib.rshift((tdRange), 11)) * tdTtt ;
        if (((tdCode) < (tdBound))) then
            tdRange = tdBound ;
            tdState = 0 ;
            tdProbIdx = 818 ;
            tdRes = 2 ;
        else
            tdRange = tdRange - tdBound ;
            tdCode = tdCode - tdBound ;
            tdRes = 3 ;
            tdProbIdx = 204 + tdState ;
            tdTtt = probs16[tdProbIdx] ;
            if (((tdRange) < (16777216))) then
                if (((tdCur) >= (tdBufLimit))) then
                    return 0;
                end
                tdRange = tdRange -blshift- 8 ;
                tdCode = (tdCode -blshift- 8) -bor- (readBuf8[tdCur]) ;
                tdCur=tdCur+1;
            end
            tdBound = (bitlib.rshift((tdRange), 11)) * tdTtt ;
            if (((tdCode) < (tdBound))) then
                tdRange = tdBound ;
                tdProbIdx = 240 + (tdState -blshift- (4)) + tdPosState ;
                tdTtt = probs16[tdProbIdx] ;
                if (((tdRange) < (16777216))) then
                    if (((tdCur) >= (tdBufLimit))) then
                        return 0;
                    end
                    tdRange = tdRange -blshift- 8 ;
                    tdCode = (tdCode -blshift- 8) -bor- (readBuf8[tdCur]) ;
                    tdCur=tdCur+1;
                end
                tdBound = (bitlib.rshift((tdRange), 11)) * tdTtt ;
                if (((tdCode) < (tdBound))) then
                    tdRange = tdBound ;
                    if (((tdRange) < (16777216))) then
                        if (((tdCur) >= (tdBufLimit))) then
                            return 0;
                        end
                        tdRange = tdRange -blshift- 8 ;
                        tdCode = (tdCode -blshift- 8) -bor- (readBuf8[tdCur]) ;
                        tdCur=tdCur+1;
                    end
                    return 3;
                else
                    tdRange = tdRange - tdBound ;
                    tdCode = tdCode - tdBound ;
                end
            else
                tdRange = tdRange - tdBound ;
                tdCode = tdCode - tdBound ;
                tdProbIdx = 216 + tdState ;
                tdTtt = probs16[tdProbIdx] ;
                if (((tdRange) < (16777216))) then
                    if (((tdCur) >= (tdBufLimit))) then
                        return 0;
                    end
                    tdRange = tdRange -blshift- 8 ;
                    tdCode = (tdCode -blshift- 8) -bor- (readBuf8[tdCur]) ;
                    tdCur=tdCur+1;
                end
                tdBound = (bitlib.rshift((tdRange), 11)) * tdTtt ;
                if (((tdCode) < (tdBound))) then
                    tdRange = tdBound ;
                else
                    tdRange = tdRange - tdBound ;
                    tdCode = tdCode - tdBound ;
                    tdProbIdx = 228 + tdState ;
                    tdTtt = probs16[tdProbIdx] ;
                    if (((tdRange) < (16777216))) then
                        if (((tdCur) >= (tdBufLimit))) then
                            return 0;
                        end
                        tdRange = tdRange -blshift- 8 ;
                        tdCode = (tdCode -blshift- 8) -bor- (readBuf8[tdCur]) ;
                        tdCur=tdCur+1;
                    end
                    tdBound = (bitlib.rshift((tdRange), 11)) * tdTtt ;
                    if (((tdCode) < (tdBound))) then
                        tdRange = tdBound ;
                    else
                        tdRange = tdRange - tdBound ;
                        tdCode = tdCode - tdBound ;
                    end
                end
            end
            tdState = 12 ;
            tdProbIdx = 1332 ;
        end
        do
            local tdLimitSub;
            local tdOffset;
            local tdProbLenIdx = tdProbIdx + 0;
            tdTtt = probs16[tdProbLenIdx] ;
            if (((tdRange) < (16777216))) then
                if (((tdCur) >= (tdBufLimit))) then
                    return 0;
                end
                tdRange = tdRange -blshift- 8 ;
                tdCode = (tdCode -blshift- 8) -bor- (readBuf8[tdCur]) ;
                tdCur=tdCur+1;
            end
            tdBound = (bitlib.rshift((tdRange), 11)) * tdTtt ;
            if (((tdCode) < (tdBound))) then
                tdRange = tdBound ;
                tdProbLenIdx = tdProbIdx + 2 + (tdPosState -blshift- (3)) ;
                tdOffset = 0 ;
                tdLimitSub = 8 ;
            else
                tdRange = tdRange - tdBound ;
                tdCode = tdCode - tdBound ;
                tdProbLenIdx = tdProbIdx + 1 ;
                tdTtt = probs16[tdProbLenIdx] ;
                if (((tdRange) < (16777216))) then
                    if (((tdCur) >= (tdBufLimit))) then
                        return 0;
                    end
                    tdRange = tdRange -blshift- 8 ;
                    tdCode = (tdCode -blshift- 8) -bor- (readBuf8[tdCur]) ;
                    tdCur=tdCur+1;
                end
                tdBound = (bitlib.rshift((tdRange), 11)) * tdTtt ;
                if (((tdCode) < (tdBound))) then
                    tdRange = tdBound ;
                    tdProbLenIdx = tdProbIdx + 130 + (tdPosState -blshift- (3)) ;
                    tdOffset = 8 ;
                    tdLimitSub = 8 ;
                else
                    tdRange = tdRange - tdBound ;
                    tdCode = tdCode - tdBound ;
                    tdProbLenIdx = tdProbIdx + 258 ;
                    tdOffset = 8 + 8 ;
                    tdLimitSub = 256 ;
                end
            end
            do
                tdLen = 1 ;
                repeat
                    tdTtt = probs16[tdProbLenIdx + tdLen] ;
                    if (((tdRange) < (16777216))) then
                        if (((tdCur) >= (tdBufLimit))) then
                            return 0;
                        end
                        tdRange = tdRange -blshift- 8 ;
                        tdCode = (tdCode -blshift- 8) -bor- (readBuf8[tdCur]) ;
                        tdCur=tdCur+1;
                    end
                    tdBound = (bitlib.rshift((tdRange), 11)) * tdTtt ;
                    if (((tdCode) < (tdBound))) then
                        tdRange = tdBound ;
                        tdLen = (tdLen + tdLen);
                    else tdRange = tdRange - tdBound ;
                        tdCode = tdCode - tdBound ;
                        tdLen = (tdLen + tdLen) + 1;
                    end
                until not (((tdLen) < (tdLimitSub)));
                tdLen = tdLen - tdLimitSub ;
            end
            tdLen = tdLen + tdOffset ;
        end

        if (((tdState) < (4))) then
            local tdPosSlot;
            tdProbIdx = 432 + ((((tdLen) < (4)) and tdLen or 4 - 1) -blshift- (6)) ;
            do
                tdPosSlot = 1 ;
                repeat
                    tdTtt = probs16[tdProbIdx + tdPosSlot] ;
                    if (((tdRange) < (16777216))) then
                        if (((tdCur) >= (tdBufLimit))) then
                            return 0;
                        end
                        tdRange = tdRange -blshift- 8 ;
                        tdCode = (tdCode -blshift- 8) -bor- (readBuf8[tdCur]) ;
                        tdCur=tdCur+1;
                    end
                    tdBound = (bitlib.rshift((tdRange), 11)) * tdTtt ;
                    if (((tdCode) < (tdBound))) then
                        tdRange = tdBound ;
                        tdPosSlot = (tdPosSlot + tdPosSlot);
                    else tdRange = tdRange - tdBound ;
                        tdCode = tdCode - tdBound ;
                        tdPosSlot = (tdPosSlot + tdPosSlot) + 1;
                    end
                until not (((tdPosSlot) < (64)));
                tdPosSlot = tdPosSlot - (64) ;
            end

            assert((tdPosSlot <= 0x7fffffff) and ((tdPosSlot) < (64)));
            if (((tdPosSlot) >= (4))) then
                local tdDirectBitCount = (bitlib.rshift((tdPosSlot), (1))) - 1;
                if (((tdPosSlot) < (14))) then
                    tdProbIdx = 688 + ((2 -bor- (tdPosSlot -band- 1)) -blshift- tdDirectBitCount) - tdPosSlot - 1 ;
                else
                    tdDirectBitCount = tdDirectBitCount - 4 ;
                    repeat
                        if (((tdRange) < (16777216))) then
                            if (((tdCur) >= (tdBufLimit))) then
                                return 0;
                            end
                            tdRange = tdRange -blshift- 8 ;
                            tdCode = (tdCode -blshift- 8) -bor- (readBuf8[tdCur]) ;
                            tdCur=tdCur+1;
                        end
                        tdRange = (bitlib.rshift((tdRange), 1));
                        if (((tdCode - tdRange) -band- 0x80000000) == 0) then
                            tdCode = tdCode - tdRange;
                        end
                        tdDirectBitCount=tdDirectBitCount-1;
                    until not (((tdDirectBitCount) ~= (0)));
                    tdProbIdx = 802 ;
                    tdDirectBitCount = 4 ;
                end
                do
                    local tdI = 1;
                    repeat
                        tdTtt = probs16[tdProbIdx + tdI] ;
                        if (((tdRange) < (16777216))) then
                            if (((tdCur) >= (tdBufLimit))) then
                                return 0;
                            end
                            tdRange = tdRange -blshift- 8 ;
                            tdCode = (tdCode -blshift- 8) -bor- (readBuf8[tdCur]) ;
                            tdCur=tdCur+1;
                        end
                        tdBound = (bitlib.rshift((tdRange), 11)) * tdTtt ;
                        if (((tdCode) < (tdBound))) then
                            tdRange = tdBound ;
                            tdI = (tdI + tdI);
                        else tdRange = tdRange - tdBound ;
                            tdCode = tdCode - tdBound ;
                            tdI = (tdI + tdI) + 1;
                        end
                        tdDirectBitCount=tdDirectBitCount-1;
                    until not (((tdDirectBitCount) ~= (0)));
                end
            end
        end
    end
    if (((tdRange) < (16777216))) then
        if (((tdCur) >= (tdBufLimit))) then
            return 0;
        end
        tdRange = tdRange -blshift- 8 ;
        tdCode = (tdCode -blshift- 8) -bor- (readBuf8[tdCur]) ;
        tdCur=tdCur+1;
    end
    return tdRes;
end

local function LzmaDec_InitDicAndState(idInitDic, idInitState)


    needFlush = 1;
    remainLen = 0;
    tempBufSize = 0;

    if ((idInitDic ~= 0)) then
        processedPos = 0;
        checkDicSize = 0;
        needInitLzma = 1;
    end
    if ((idInitState ~= 0)) then
        needInitLzma = 1;
    end
end





local function LzmaDec_DecodeToDic(ddSrcLen)

    local decodeLimit = readCur + ddSrcLen;
    local checkEndMarkNow;
    local dummyRes;

    LzmaDec_WriteRem(dicBufSize);

    while (((remainLen) ~= (274))) do
        if ((needFlush ~= 0)) then



            while (((decodeLimit) > (readCur)) and ((tempBufSize) < (5))) do
                readBuf8[(6 + 65536 + 6) + tempBufSize] = readBuf8[readCur];
                tempBufSize=tempBufSize+1
                readCur=readCur+1
            end
            if (((tempBufSize) < (5))) then





            end
            if (((readBuf8[(6 + 65536 + 6)]) ~= (0))) then
                --print("E")
                return 1;
            end
            code = ((((readBuf8[(6 + 65536 + 6) + 1]) -blshift- 24) -bor- ((readBuf8[(6 + 65536 + 6) + 2]) -blshift- 16)) -bor- ((readBuf8[(6 + 65536 + 6) + 3]) -blshift- 8)) -bor- ((readBuf8[(6 + 65536 + 6) + 4]));
            range = 0xffffffff;
            needFlush = 0;
            tempBufSize = 0;
        end

        checkEndMarkNow = 0 ;
        if (((dicPos) >= (dicBufSize))) then
            if (((remainLen) == (0)) and ((code) == 0)) then
                if (((readCur) ~= (decodeLimit))) then
                    return 18;
                end
                return 0 ;
            end
            if (((remainLen) ~= (0))) then
                return 16;
            end
            checkEndMarkNow = 1 ;
        end

        if ((needInitLzma ~= 0)) then
            local numProbs = 1846 + ((768) -blshift- (lc + lp));
            for ddProbIdx = 0, numProbs-1, 1 do
                probs16[ddProbIdx] = (bitlib.rshift((2048), (1)));
            end
            rep3 = 1;
            rep2 = rep3;
            rep1 = rep2;
            rep0 = rep1;
            state = 0;
            needInitLzma = 0;
        end

        if (((tempBufSize) == (0))) then
            local bufLimit;
            if (((decodeLimit - readCur) < (20)) or (checkEndMarkNow ~= 0)) then
                dummyRes = LzmaDec_TryDummy(readCur, decodeLimit) ;
                if (((dummyRes) == (0))) then

                    tempBufSize = 0;
                    while (((readCur) ~= (decodeLimit))) do
                        readBuf8[(6 + 65536 + 6) + tempBufSize] = readBuf8[readCur];
                        tempBufSize=tempBufSize+1;
                        readCur=readCur+1;
                    end



                    if (((readCur) ~= (decodeLimit))) then
                        return 17;
                    end
                    return 17;

                end
                if ((checkEndMarkNow ~= 0) and ((dummyRes) ~= (2))) then
                    return 16;
                end
                bufLimit = readCur ;
            else
                bufLimit = decodeLimit - 20 ;
            end
            bufCur = readCur;
            if (((LzmaDec_DecodeReal2(dicBufSize, bufLimit)) ~= (0))) then
                --print("F")
                return 1;
            end
            readCur = bufCur;
        else
            local ddRem = tempBufSize;
            local lookAhead = 0;
            while (((ddRem) < (20)) and ((lookAhead) < (decodeLimit - readCur))) do
                readBuf8[(6 + 65536 + 6) + ddRem] = readBuf8[readCur + lookAhead];
                ddRem=ddRem+1;
                lookAhead=lookAhead+1;
            end
            tempBufSize = ddRem;
            if (((ddRem) < (20)) or (checkEndMarkNow ~= 0)) then
                dummyRes = LzmaDec_TryDummy((6 + 65536 + 6), (6 + 65536 + 6) + ddRem) ;
                if (((dummyRes) == (0))) then
                    readCur = readCur + lookAhead;



                    if (((readCur) ~= (decodeLimit))) then
                        return 17;
                    end
                    return 17;

                end
                if ((checkEndMarkNow ~= 0) and ((dummyRes) ~= (2))) then
                    return 16;
                end
            end

            bufCur = (6 + 65536 + 6);
            if (((LzmaDec_DecodeReal2(0, (6 + 65536 + 6))) ~= (0))) then
                --print("G")
                return 1;
            end
            lookAhead = lookAhead - ddRem - (bufCur - (6 + 65536 + 6)) ;
            readCur = readCur + lookAhead;
            tempBufSize = 0;
        end
    end
    if (((code) ~= 0)) then
        --print("H");
        return 1;
    end
    return 15;
end
local function Preread(prSize)



    local prPos = readEnd - readCur;
    local prGot;

    assert(((prSize) <= ((6 + 65536 + 6))));
    if (((prPos) < (prSize))) then
        if ((((6 + 65536 + 6) - readCur) < (prSize))) then


            readEnd = 0
            while readEnd < prPos do
                readBuf8[readEnd] = readBuf8[readCur + readEnd];
                readEnd=readEnd+1
            end
            readCur = 0;
        end
        while (((prPos) < (prSize))) do




            prGot = READ_FROM_STDIN_TO_ARY8(readBuf8, readEnd, prSize - prPos);
            if (((prGot + 1) <= (1))) then
                break;
            end
            readEnd = readEnd + prGot;
            prPos = prPos + prGot ;
        end
    end

    return prPos;





end

local function IgnoreVarint()
    while (((readBuf8[readCur]) >= (0x80))) do readCur = readCur + 1 end
    readCur = readCur + 1
end

local function IgnoreZeroBytes(izCount)

    while ((izCount) ~= (0)) do
        readCur=readCur+1
        if (((readBuf8[readCur-1]) ~= (0))) then
            return 57;
        end
        izCount=izCount-1;
    end
    return 0;
end

local function GetLE4(glPos)
    --return ((readBuf8[glPos] -bor- (readBuf8[glPos + 1] -blshift- 8)) -bor- (readBuf8[glPos + 2] -blshift- 16)) -bor- (readBuf8[glPos + 3] -blshift- 24);
    --print("glPos", glPos)
    return bitlib.band(readBuf8[glPos], 0xff) + bitlib.blshift(bitlib.band(readBuf8[glPos+1], 0xff), 8) + bitlib.blshift(bitlib.band(readBuf8[glPos+2], 0xff), 16) + bit.blshift(bitlib.band(readBuf8[glPos+3], 0xff), 24)
end


local function InitDecode()


    dicBufSize = 0;
    needInitDic = 1;
    needInitState = 1;
    needInitProp = 1;
    dicPos = 0;
    LzmaDec_InitDicAndState(1, 1);
end

local function InitProp(ipByte)

    if (((ipByte) >= (9 * 5 * 5))) then
        return 68;
    end
    lc = ipByte % 9;
    lcm8 = 8 - lc;
    ipByte = math.floor(ipByte / 9) ;
    pb = math.floor(ipByte / 5);
    lp = ipByte % 5;
    if (((lc + lp) > (4))) then
        return 68;
    end
    needInitProp = 0;
    return 0;
end


local function WriteFrom(wfDicPos)


    local lastTime = os.epoch("utc")


    while (((wfDicPos) ~= (dicPos))) do
        local wfGot = WRITE_TO_STDOUT_FROM_ARY8(dic8, wfDicPos, dicPos - wfDicPos);
        if (wfGot -band- 0x80000000) ~= 0 then
            return 9;
        end
        wfDicPos = wfDicPos + wfGot ;
        if textutils and os.epoch("utc") - lastTime > 3000 then 
            --write(",")
            lastTime = os.epoch("utc")
            os.queueEvent(os.pullEvent())
        end
    end

    return 0;
end






local function DecompressXzOrLzma()
    local checksumSize;
    local bhf;
    local dxRes;




    if (((Preread(12 + 12 + 6)) < (12 + 12 + 6))) then
        return 6;
    end

    if (((readBuf8[0]) == (0xfd)) and ((readBuf8[1]) == (0x37)) and
    ((readBuf8[2]) == (0x7a)) and ((readBuf8[3]) == (0x58)) and
    ((readBuf8[4]) == (0x5a)) and ((readBuf8[5]) == (0)) and
    ((readBuf8[6]) == (0))) then --print("xz")
    elseif (
        (
            (readBuf8[readCur]) <= (225)
        ) and (
            (readBuf8[readCur + 13]) == (0)
        ) and (
            (
                (
                    (function() bhf = GetLE4(readCur + 9); return bhf end)()
                ) == 0
            ) or (
                (bnot-bhf) == 0
            )
        ) and (
            (
                (function() dicSize = GetLE4(readCur + 1); return dicSize end)()
            ) >= ((4096))
        ) and (
            (dicSize) < bitlib.band((1610612736 + 1), 0x7fffffff)
        )
    ) then

        local readBufUS;
        local srcLen;
        local fromDicPos;
        InitDecode();





        if ((((function() dxRes = InitProp(readBuf8[readCur]); return dxRes end)()) ~= (0))) then
            return dxRes;
        end
        if (((bhf) == 0)) then
            readBufUS = GetLE4(readCur + 5);
            dicBufSize = readBufUS;
            if (not ((readBufUS) < bitlib.band((1610612736 + 1), 0x7fffffff))) then
                return 2;
            end
        else
            readBufUS = bhf ;

            dicBufSize = 1610612736;
        end

        readCur = readCur + 13;







        while ((((function() srcLen = Preread((6 + 65536 + 6)); return srcLen end)()) ~= (0))) do
            fromDicPos = dicPos ;
            dxRes = LzmaDec_DecodeToDic(srcLen) ;

            if (((readBufUS) < (dicPos))) then
                dicPos = readBufUS;
            end
            if ((((function() dxRes = WriteFrom(fromDicPos); return dxRes end)()) ~= (0))) then
                return dxRes;
            end
            if (((dxRes) == (15))) then
                break;
            end
            if (((dxRes) ~= (17)) and ((dxRes) ~= (0))) then
                return dxRes;
            end
            if (((dicPos - readBufUS) == 0)) then
                break;
            end
        end
        return 0;
    else
        return 51;
    end

    checksumSize = readBuf8[readCur + 7];
    if (((checksumSize) == (0))) then
        checksumSize = 1;
    elseif (((checksumSize) == (1))) then
        checksumSize = 4;
    elseif (((checksumSize) == (4))) then
        checksumSize = 8;
    elseif (((checksumSize) == (10))) then
        checksumSize = 32;
    else return 60;
    end

    readCur = readCur + 12;
    while true do

        local blockSizePad = 3;
        local bhs;
        local bhs2;
        local dicSizeProp;
        local readAtBlock;
        assert(((readEnd - readCur) >= (12)));
        readAtBlock = readCur ;
        readCur=readCur+1;
        if ((((function() bhs = readBuf8[readCur-1]; return bhs end)()) == (0))) then
            break;
        end

        bhs = (bhs + 1) -blshift- 2;


        if (((Preread(bhs)) < (bhs))) then
            return 6;
        end
        readAtBlock = readCur ;
        bhf = readBuf8[readCur] ;
        --print("bhf", string.format("%x\n", bhf))
        readCur=readCur+1;
        if (((bhf -band- 2) ~= (0))) then
            return 53;
        end

        if (((bhf -band- 20) ~= (0))) then
            return 54;
        end
        if (((bhf -band- 64) ~= (0))) then

            IgnoreVarint();
        end
        if (((bhf -band- 128) ~= (0))) then

            IgnoreVarint();
        end
        if (((readBuf8[readCur]) ~= (0x21))) then
            return 55;
        end
        readCur=readCur+1;
        if (((readBuf8[readCur]) ~= (1))) then
            return 56;
        end
        readCur=readCur+1;
        dicSizeProp = readBuf8[readCur] ;
        readCur=readCur+1;
        if (((dicSizeProp) > (40))) then
            return 61;
        end



        if (((dicSizeProp) > (37))) then
            return 62;
        end
        dicSize = (((2) -bor- ((dicSizeProp) -band- 1)) -blshift- (math.floor((dicSizeProp) / 2) + 11));
        assert(((dicSize) >= ((4096))));





        bhs2 = readCur - readAtBlock + 5 ;

        if (((bhs2) > (bhs))) then
            return 58;
        end
        if ((((function() dxRes = IgnoreZeroBytes(bhs - bhs2); return dxRes end)()) ~= (0))) then
            return dxRes;
        end
        readCur = readCur + 4;


        do

            local chunkUS;
            local chunkCS;
            local initDic;
            InitDecode();

            while true do
                local control;
                assert(((dicPos) == (dicBufSize)));



                if (((Preread(6)) < (6))) then
                    return 6;
                end
                control = readBuf8[readCur] ;

                if (((control) == (0))) then

                    readCur=readCur+1;
                    break;
                elseif ((((bitlib.band((control - 3), 0xff))) < (0x80 - 3))) then
                    return 59;
                end
                chunkUS = (readBuf8[readCur + 1] -blshift- 8) + readBuf8[readCur + 2] + 1 ;
                --print("chunkUS", chunkUS, "readCur", readCur, "@1", readBuf8[readCur + 1], "@2", readBuf8[readCur + 2])
                if (((control) < (3))) then
                    initDic = (((control) == (1)) and 1 or 0);
                    chunkCS = chunkUS ;
                    readCur = readCur + 3;

                    blockSizePad = blockSizePad - 3;
                    if ((initDic ~= 0)) then
                        needInitState = 1;
                        needInitProp = needInitState;
                        needInitDic = 0;
                    elseif ((needInitDic ~= 0)) then
                        --print("I")
                        return 1;
                    end
                    LzmaDec_InitDicAndState(initDic, 0);
                else
                    local mode = ((bitlib.rshift(((control)), (5))) -band- 3);
                    local initState = (((mode) ~= (0)) and 1 or 0);
                    local isProp = ((((control -band- 64)) ~= (0)) and 1 or 0);
                    initDic = (((mode) == (3)) and 1 or 0);
                    chunkUS = chunkUS + ((control -band- 31) -blshift- 16) ;
                    chunkCS = (readBuf8[readCur + 3] -blshift- 8) + readBuf8[readCur + 4] + 1 ;
                    if ((isProp ~= 0)) then
                        if ((((function() dxRes = InitProp(readBuf8[readCur + 5]); return dxRes end)()) ~= (0))) then
                            return dxRes;
                        end
                        readCur=readCur+1;
                        blockSizePad=blockSizePad-1;
                    else
                        if ((needInitProp ~= 0)) then
                            return 67;
                        end
                    end
                    readCur = readCur + 5;
                    blockSizePad = blockSizePad - 5 ;
                    if (((initDic == 0) and (needInitDic ~= 0)) or ((initState == 0) and (needInitState ~= 0))) then
                        --print("J")
                        return 1;
                    end
                    LzmaDec_InitDicAndState(initDic, initState);
                    needInitDic = 0;
                    needInitState = 0;
                end
                assert(((dicPos) == (dicBufSize)));
                dicBufSize = dicBufSize + chunkUS;

                if (((dicBufSize) > (1610612736))) then
                    return 2;
                end




                if (((Preread(chunkCS + 6)) < (chunkCS))) then
                    return 6;
                end

                if (((control) < (0x80))) then

                    while (((dicPos) ~= (dicBufSize))) do
                        dic8[dicPos] = readBuf8[readCur] -band- 0xFF;
                        dicPos=dicPos+1;
                        readCur=readCur+1;
                    end
                    if (((checkDicSize) == (0)) and ((dicSize - processedPos) <= (chunkUS))) then
                        checkDicSize = dicSize;
                    end
                    processedPos = processedPos + chunkUS;
                else


                    if ((((function() dxRes = LzmaDec_DecodeToDic(chunkCS); return dxRes end)()) ~= (0))) then
                        return dxRes;
                    end
                end
                if (((dicPos) ~= (dicBufSize))) then
                    return 65;
                end
                if ((((function() dxRes = WriteFrom(dicPos - chunkUS); return dxRes end)()) ~= (0))) then
                    return dxRes;
                end
                blockSizePad = blockSizePad - chunkCS ;




            end
        end




        if (((Preread(7 + 12 + 6)) < (7 + 12 + 6))) then
            return 6;
        end


        if ((((function() dxRes = IgnoreZeroBytes(blockSizePad -band- 3); return dxRes end)()) ~= (0))) then
            return dxRes;
        end
        readCur = readCur + checksumSize;
    end

    return 0;
end

local error_table = {
    UNKNOWN_ERROR = -1,
    OK = 0,
    ERROR_DATA = 1,
    ERROR_MEM = 2,
    ERROR_CRC = 3,
    ERROR_UNSUPPORTED = 4,
    ERROR_PARAM = 5,
    ERROR_INPUT_EOF = 6,
    ERROR_OUTPUT_EOF = 7,
    ERROR_READ = 8,
    ERROR_WRITE = 9,
    ERROR_FINISHED_WITH_MARK = 15,
    ERROR_NOT_FINISHED = 16,
    ERROR_NEEDS_MORE_INPUT = 17,
    ERROR_CHUNK_NOT_CONSUMED = 18,
    ERROR_NEEDS_MORE_INPUT_PARTIAL = 17,
    ERROR_BAD_MAGIC = 51,
    ERROR_BAD_STREAM_FLAGS = 52,
    ERROR_UNSUPPORTED_FILTER_COUNT = 53,
    ERROR_BAD_BLOCK_FLAGS = 54,
    ERROR_UNSUPPORTED_FILTER_ID = 55,
    ERROR_UNSUPPORTED_FILTER_PROPERTIES_SIZE = 56,
    ERROR_BAD_PADDING = 57,
    ERROR_BLOCK_HEADER_TOO_LONG = 58,
    ERROR_BAD_CHUNK_CONTROL_BYTE = 59,
    ERROR_BAD_CHECKSUM_TYPE = 60,
    ERROR_BAD_DICTIONARY_SIZE = 61,
    ERROR_UNSUPPORTED_DICTIONARY_SIZE = 62,
    ERROR_FEED_CHUNK = 63,
    ERROR_NOT_FINISHED_WITH_MARK = 64,
    ERROR_BAD_DICPOS = 65,
    ERROR_MISSING_INITPROP = 67,
    ERROR_BAD_LCLPPB_PROP = 68,
}

return {
    --- Decompresses an XZ or LZMA file using file I/O. Both files will be closed after decompression finishes.
    -- @param input The input file (path) to read from
    -- @param output The output file (path) to write to
    -- @return Whether the decompression succeeded
    -- @return If failure, an error code describing the issue
    DecompressXzOrLzmaFile = function(input, output)
        if type(input) ~= "userdata" and (_HOST == nil or type(input) ~= "table") and type(input) ~= "string" then error("bad argument #1 (expected string or file, got " .. type(input) .. ")", 2) end
        if type(output) ~= "userdata" and (_HOST == nil or type(output) ~= "table") and type(output) ~= "string" then error("bad argument #2 (expected string or file, got " .. type(output) .. ")", 2) end
        str_input = nil
        str_output = nil
        local old_input = io.input()
        local old_output = io.output()
        if type(input) == "string" then
            input = io.open(input, "rb")
            if input == nil then return false, -1 end
        end
        if type(output) == "string" then
            output = io.open(output, "wb")
            if output == nil then return false, -1 end
        end
        io.input(input)
        io.output(output)
        ResetGlobals()
        local ok, res = pcall(DecompressXzOrLzma)
        io.input(old_input)
        io.output(old_output)
        input:close()
        output:close()
        if not ok then
            if res then io.stderr:write(res .. "\n") end
            return false, -1 
        else return res == 0, res end
    end,
    --- Decompresses XZ or LZMA data.
    -- @param input The input data to decompress
    -- @return The decompressed data, or nil if failure
    -- @return If failure, an error code describing the issue
    DecompressXzOrLzmaString = function(input)
        if type(input) ~= "string" then error("bad argument #1 (expected string, got " .. type(input) .. ")", 2) end
        str_input = input
        str_output = ""
        ResetGlobals()
        local ok, res = pcall(DecompressXzOrLzma)
        if not ok then
            if res then io.stderr:write(res .. "\n") end
            return -1
        elseif res == 0 then return str_output
        elseif res == 53 and #str_output > 0 then return str_output, res
        else return nil, res end
    end,
    --- Translates error codes to a semi-understandable meaning.
    -- @param code The error code
    -- @return A string describing the error
    GetError = function(code) for k,v in pairs(error_table) do if v == code then return k end end return nil end,
    --- Error code table for your convenience
    Errors = error_table,
}

