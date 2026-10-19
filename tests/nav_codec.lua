-- A stand-in for the client's C_EncodingUtil (Base64, zlib, CBOR) for the navigation tests, in plain Lua 5.1.
-- zlib is LibDeflate's (TwichUI already ships it in libs/); Base64 and CBOR are small implementations of the subset
-- the walking maps use (tools/navbake/cbor.py writes: unsigned and negative integers, 32/64-bit floats, text, arrays,
-- maps, true/false/null). Arrays come back 1-based, as the client's DeserializeCBOR gives them. Test-only.
local LD = dofile(ROOT .. "libs/LibDeflate/LibDeflate.lua")
local bit = bit or require("bit")
local band, bor, lshift, rshift = bit.band, bit.bor, bit.lshift, bit.rshift

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local DEC = {}
for i = 1, 64 do DEC[B64:byte(i)] = i - 1 end

local function DecodeBase64(s)
  local out, n = {}, 0
  local acc, bits = 0, 0
  for i = 1, #s do
    local v = DEC[s:byte(i)]
    if v then
      acc = bor(lshift(acc, 6), v)
      bits = bits + 6
      if bits >= 8 then
        bits = bits - 8
        n = n + 1
        out[n] = string.char(band(rshift(acc, bits), 0xFF))
        acc = band(acc, lshift(1, bits) - 1)
      end
    end
  end
  return table.concat(out)
end

local function EncodeBase64(s)
  local out = {}
  for i = 1, #s, 3 do
    local a, b, c = s:byte(i, i + 2)
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    local c1, c2, c3, c4 = rshift(n, 18), band(rshift(n, 12), 63), band(rshift(n, 6), 63), band(n, 63)
    out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
      .. (b and B64:sub(c3 + 1, c3 + 1) or "=") .. (c and B64:sub(c4 + 1, c4 + 1) or "=")
  end
  return table.concat(out)
end

-- IEEE 754 single and double, big-endian
local function Float32(b1, b2, b3, b4)
  local sign = b1 >= 128 and -1 or 1
  local exp = band(b1, 127) * 2 + rshift(b2, 7)
  local man = band(b2, 127) * 65536 + b3 * 256 + b4
  if exp == 0 then return sign * man * 2 ^ -149 end
  if exp == 255 then return man == 0 and sign * math.huge or 0 / 0 end
  return sign * (1 + man / 8388608) * 2 ^ (exp - 127)
end
local function Float64(s, p)
  local b = { s:byte(p, p + 7) }
  local sign = b[1] >= 128 and -1 or 1
  local exp = band(b[1], 127) * 16 + rshift(b[2], 4)
  local man = band(b[2], 15)
  for i = 3, 8 do man = man * 256 + b[i] end
  if exp == 0 then return sign * man * 2 ^ -1074 end
  if exp == 2047 then return man == 0 and sign * math.huge or 0 / 0 end
  return sign * (1 + man / 2 ^ 52) * 2 ^ (exp - 1023)
end

local function DeserializeCBOR(s)
  local pos = 1
  local function arg(info)
    if info < 24 then return info end
    local size = ({ [24] = 1, [25] = 2, [26] = 4, [27] = 8 })[info]
    local v = 0
    for i = 0, size - 1 do v = v * 256 + s:byte(pos + i) end
    pos = pos + size
    return v
  end
  local item
  function item()
    local b = s:byte(pos)
    pos = pos + 1
    local major, info = rshift(b, 5), band(b, 31)
    if major == 0 then return arg(info) end
    if major == 1 then return -1 - arg(info) end
    if major == 3 then
      local n = arg(info)
      local v = s:sub(pos, pos + n - 1)
      pos = pos + n
      return v
    end
    if major == 4 then
      local n = arg(info)
      local t = {}
      for i = 1, n do t[i] = item() end
      return t
    end
    if major == 5 then
      local n = arg(info)
      local t = {}
      for _ = 1, n do
        local k = item()
        t[k] = item()
      end
      return t
    end
    if major == 7 then
      if info == 20 then return false end
      if info == 21 then return true end
      if info == 22 then return nil end
      if info == 26 then
        local v = Float32(s:byte(pos, pos + 3))
        pos = pos + 4
        return v
      end
      if info == 27 then
        local v = Float64(s, pos)
        pos = pos + 8
        return v
      end
    end
    error("unsupported CBOR item " .. b)
  end
  return item()
end

-- Encoder for building fixtures (integers, text, arrays, string-keyed maps)
local function Head(major, n, out)
  if n < 24 then out[#out + 1] = string.char(major * 32 + n)
  elseif n < 256 then out[#out + 1] = string.char(major * 32 + 24, n)
  elseif n < 65536 then out[#out + 1] = string.char(major * 32 + 25, rshift(n, 8), band(n, 255))
  else out[#out + 1] = string.char(major * 32 + 26, band(rshift(n, 24), 255), band(rshift(n, 16), 255), band(rshift(n, 8), 255), band(n, 255)) end
end
local function Enc(v, out)
  local t = type(v)
  if t == "number" then
    assert(v % 1 == 0, "fixture numbers are integers")
    if v >= 0 then Head(0, v, out) else Head(1, -1 - v, out) end
  elseif t == "string" then
    Head(3, #v, out); out[#out + 1] = v
  elseif t == "table" then
    if #v > 0 or next(v) == nil then
      Head(4, #v, out)
      for i = 1, #v do Enc(v[i], out) end
    else
      local keys = {}
      for k in pairs(v) do keys[#keys + 1] = k end
      table.sort(keys)
      Head(5, #keys, out)
      for _, k in ipairs(keys) do Enc(k, out); Enc(v[k], out) end
    end
  elseif t == "boolean" then out[#out + 1] = string.char(v and 0xF5 or 0xF4)
  else error("cannot encode " .. t) end
end
local function SerializeCBOR(v)
  local out = {}
  Enc(v, out)
  return table.concat(out)
end

NAV_CODEC = {
  C_EncodingUtil = {
    DecodeBase64 = function(s) return DecodeBase64(s) end,
    DecompressString = function(s, method)
      assert(method == 1, "the walking maps are zlib (Enum.CompressionMethod.Zlib)")
      return LD:DecompressZlib(s)
    end,
    DeserializeCBOR = function(s) return DeserializeCBOR(s) end,
  },
  Enum = { CompressionMethod = { Deflate = 0, Zlib = 1, Gzip = 2 } },
  -- fixture side: a table to the string the data addon would hold
  Pack = function(v) return EncodeBase64(LD:CompressZlib(SerializeCBOR(v))) end,
}
