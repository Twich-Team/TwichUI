-- Test-only fixed-width current tuples. No frames, saved data or custom codec
-- framework. The actual Pricing/Estimate/OpportunityEngine stay unchanged.
local F={WIDTH=135}
local widths={8,64,1,10,10,10,14,1,1,10,2,2,2}
local offsets={};local offset=0
for i,width in ipairs(widths)do offsets[i]=offset;offset=offset+width end
assert(offset==F.WIDTH)
local function number(word)
    if word==string.rep('z',#word)then return false end
    assert(not word:find('[^0-9a-f]'),'fixed integer syntax')
    -- Lua 5.1 can use 32-bit unsigned long for base conversion on Windows.
    -- Convert at most seven hex digits at a time, then combine exact doubles.
    if #word>7 then return assert(tonumber(word:sub(1,-8),16))*268435456+assert(tonumber(word:sub(-7),16))end
    return assert(tonumber(word,16))
end
function F.Count(data)
    if type(data)=='table'then return #data end
    assert(type(data)=='string'and #data%F.WIDTH==0,'fixed record length')
    return #data/F.WIDTH
end
function F.Key(data,position)
    if type(data)=='table'then local r=data[position];return r[1],r[2]end
    assert(position>=1 and position<=F.Count(data),'fixed record position')
    local start=(position-1)*F.WIDTH
    return number(data:sub(start+1,start+8)),data:sub(start+9,start+72)
end
function F.Row(data,position)
    if type(data)=='table'then return data[position]end
    assert(position>=1 and position<=F.Count(data),'fixed record position')
    local start=(position-1)*F.WIDTH;local row={}
    for i,width in ipairs(widths)do
        local word=data:sub(start+offsets[i]+1,start+offsets[i]+width)
        row[i]=i==2 and word or number(word)
    end
    return row
end
return F
