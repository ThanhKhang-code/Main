local KEY = "MySecretKey123"
local PATH = "/sdcard/Movies/license.bin"

local function xorDecrypt(data, key)
    local out = {}
    for i = 1, #data do
        local k = key:byte(((i - 1) % #key) + 1)
        out[i] = string.char(bit32.bxor(data:byte(i), k))
    end
    return table.concat(out)
end

local function parseTime(str)
    local y, m, d, h, mi, s = str:match("(%d+)%-(%d+)%-(%d+) (%d+):(%d+):(%d+)")
    if not y then return nil end
    return os.time({
        year = tonumber(y),
        month = tonumber(m),
        day = tonumber(d),
        hour = tonumber(h),
        min = tonumber(mi),
        sec = tonumber(s)
    })
end

local f = io.open(PATH, "rb")
if not f then
    gg.alert("License file not found")
    os.exit()
end

local enc = f:read("*all")
f:close()

local text = xorDecrypt(enc, KEY)
local _, timeStr = text:match("([^|]+)|(.+)")
if not timeStr then
    gg.alert("Invalid license")
    os.exit()
end

local licenseTime = parseTime(timeStr)
if not licenseTime then
    gg.alert("Invalid time format")
    os.exit()
end

local now = os.time()
local maxAge = 30 * 24 * 60 * 60

if now - licenseTime > maxAge then
    gg.alert("License expired")
    os.exit()
end

gg.setRanges(gg.REGION_ANONYMOUS)
gg.clearResults()

local FLAG = gg.TYPE_DWORD
local Z_VALUE = 4119--0435A9BC
local MIN_Z = 800

local OFF_BALL     = 0x23F044--04599A00
local OFF_DISTANCE = 0x23F048--04599A04
local OFF_CAMERA   = 0x171F8C--044CC948
local OFF_TISO     = 0x2559A8--045B0364

local START_X_POS = 1850000
local END_X_POS   = 1885000
local START_X_NEG = -1850000
local END_X_NEG   = -1885000

local MOVE_DURATION = 1000  -- ms
local MOVE_STEPS    = 20
local SLEEP_MS      = MOVE_DURATION / MOVE_STEPS

----------------------------------------------------------
-- 1. Scan Z ≥ 4119
----------------------------------------------------------
local zs = {}
while true do
    gg.clearResults()
    gg.searchNumber(Z_VALUE, FLAG)
    if gg.getResultCount() >= MIN_Z then
        zs = gg.getResults(800)
        break
    end
    gg.sleep(1000)
end

local function getV(addr, offset)
    local t = {{address = addr + offset, flags = gg.TYPE_DWORD}}
    return gg.getValues(t)[1].value
end

local allList = {}
for i = 1, #zs do
    allList[#allList+1] = {address = zs[i].address - 4, value = 0, flags = FLAG, freeze = true}
    allList[#allList+1] = {address = zs[i].address - 8, value = 0, flags = FLAG, freeze = true}
    allList[#allList+1] = {address = zs[i].address,     value = 4119, flags = FLAG, freeze = true}
end

----------------------------------------------------------
-- 2. Filter first 10 Z by *38C pattern
----------------------------------------------------------
local savedList = {}
for i = 1, #zs do
    local z = zs[i].address
    if (z & 0xFFF) == 0x9BC then
        savedList[#savedList + 1] = {
            zAddr    = z,
            xAddr    = z - 4,
            yAddr    = z - 8,
            ballAddr = z + OFF_BALL,
            distAddr = z + OFF_DISTANCE,
            camAddr  = z + OFF_CAMERA,
            tisoAddr = z + OFF_TISO
        }
        if #savedList >= 1 then break end
    end
end

----------------------------------------------------------
-- 3. Wait for Tiso = 0 → freeze Ball & Distance + control X/Y for all Z
----------------------------------------------------------
while true do
    local tisoVal = gg.getValues({
        {address = savedList[1].tisoAddr, flags = FLAG}
    })[1].value

    if tisoVal == 0 then
        break
    end

    -- Check XY and freeze = 0 to prevent error at the goal
    local X = getV(zs[2].address, -4)
    local Y = getV(zs[2].address, -8)
    if math.abs(X)>1200000 or math.abs(Y) > 1000000 then
        gg.addListItems(allList)
        gg.sleep(500)
        gg.removeListItems(allList)
    end
    gg.sleep(200)
end

-- Freeze Ball = 3, Distance = 0
local bd = {}
for i = 1, #savedList do
    bd[#bd+1] = {address = savedList[i].ballAddr, value = 3, flags = FLAG, freeze = true}
    bd[#bd+1] = {address = savedList[i].distAddr, value = 0, flags = FLAG, freeze = true}
    bd[#bd+1] = {address = savedList[i].camAddr, name = "Camera", flags = FLAG, freeze = false}
    bd[#bd+1] = {address = savedList[i].tisoAddr, name = "Tiso", flags = FLAG, freeze = false}
end
gg.addListItems(bd)
gg.sleep(3000)

----------------------------------------------------------
-- 4. Determine movement direction based on Camera
----------------------------------------------------------
local cam = gg.getValues({{address = savedList[1].camAddr, flags = FLAG}})[1].value
local movePos = cam < 0  -- negative → move positive direction, positive → move negative direction
gg.sleep(5000)

----------------------------------------------------------
-- 5. Move all X/Y (more than 700 values) + freeze Z = 0
----------------------------------------------------------
local fromX = movePos and START_X_POS or START_X_NEG
local toX   = movePos and END_X_POS   or END_X_NEG
local step  = (toX - fromX) / MOVE_STEPS

t = 0
while t<15 do
    t=t+1
    for s = 1, MOVE_STEPS do
        local xVal = math.floor(fromX + step * s)
        local setList = {}

        for i = 1, #zs do
            local z = zs[i].address
            setList[#setList+1] = {address = z-4, value = xVal, flags = FLAG} -- X
            setList[#setList+1] = {address = z-8, value = 0, flags = FLAG}    -- Y always = 0
            setList[#setList+1] = {address = z, value = 4119, flags = FLAG} -- Freeze Z = 4119
        end

        gg.setValues(setList)
        gg.sleep(SLEEP_MS)
    end

    -- Pause 13s
    local i = 0
    while i < 13001 do
        local X = getV(zs[2].address, -4)
        local Y = getV(zs[2].address, -8)
        if math.abs(X)>1200000 or math.abs(Y) > 1000000 then
            gg.addListItems(allList)
            gg.sleep(200)
            gg.removeListItems(allList)
        else 
            gg.sleep(200)
        end
        i=i+200
    end

    -- Check Tiso ≥ 5 → break loop
    local tisoVal = gg.getValues({{address = savedList[1].tisoAddr, flags = FLAG}})[1].value
    if tisoVal >= 5 then
        break
    end
end
while true do
    local X = getV(zs[2].address, -4)
    local Y = getV(zs[2].address, -8)
    if math.abs(X)>1200000 or math.abs(Y) > 1000000 then
        gg.addListItems(allList)
        gg.sleep(1000)
        gg.removeListItems(allList)
    else
        gg.sleep(200)
    end
end
