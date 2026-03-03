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
local maxAge = 7 * 24 * 60 * 60

if now - licenseTime > maxAge then
    gg.alert("License expired")
    os.exit()
end
gg.clearResults()
gg.setRanges(gg.REGION_ANONYMOUS)

--------------------------------------------------
-- CONFIG
--------------------------------------------------
local Z_VALUE = 4119
local FLAG = gg.TYPE_DWORD
local MIN_Z = 800

-- OFFSETS
local OFF_GOLD    = 0x22AD5C--047FE118
local OFF_DIAMOND = 0x22AD7C
local OFF_DP      = 0x22EAA4--04801E60

-- LIMIT
local LIMIT_X = 1200000
local LIMIT_Y = 1000000

-- TAB_ID FILE
local TAB_FILE = "/sdcard/tab_id.txt"

--------------------------------------------------
-- UTILS
--------------------------------------------------
local function fileExists(path)
    local f = io.open(path, "r")
    if f then f:close() return true end
    return false
end

local function getTabID()
    if not fileExists(TAB_FILE) then
        local input = gg.prompt({"Enter tab_id"}, {""}, {"number"})
        if input ~= nil and input[1] ~= "" then
            local f = io.open(TAB_FILE, "w")
            f:write(input[1])
            f:close()
        else
            return nil
        end
    end
    local f = io.open(TAB_FILE, "r")
    local id = f:read("*a")
    f:close()
    return id
end

local function now()
    return os.date("%Y-%m-%d %H:%M:%S")
end
local function saveData(tabID, gold, dia, dp)
    local scriptDir = gg.getFile():gsub("[^/]+$", "")
    local filePath = scriptDir .. "id/" .. tabID .. ".txt"
    local f = io.open(filePath, "w") 
    if f then
        f:write(string.format("%d|%d|%d|%s", gold, dia, dp, now()))
        f:close()
    end
end

--------------------------------------------------
-- 1. Scan Z
--------------------------------------------------
local zs = {}
gg.sleep(3000)
while true do
    gg.clearResults()
    gg.searchNumber(Z_VALUE, FLAG)
    if gg.getResultCount() >= MIN_Z then
        zs = gg.getResults(MIN_Z)
        local low = zs[1].address & 0xFFF
        if low == 0xB7C or low == 0xFA4  then
            break
        end
    end
    gg.sleep(500)
end
gg.clearResults()

--------------------------------------------------
-- 2. Find Z *38C
--------------------------------------------------
local baseZ
local low = zs[1].address & 0xFFF

if low == 0xB7C then
    OFF_GOLD    = 0x22C0AC
    OFF_DIAMOND = 0x22C0CC
    OFF_DP      = 0x22FE04
    baseZ = zs[1].address

elseif low == 0xFA4 then
    OFF_GOLD    = 0x22C0B4
    OFF_DIAMOND = 0x22C0D4
    OFF_DP      = 0x22FE0C
    baseZ = zs[1].address
end
if not baseZ then return end

--------------------------------------------------
-- 3. Build monitor addresses
--------------------------------------------------
local goldAddr = baseZ + OFF_GOLD
local diaAddr  = baseZ + OFF_DIAMOND
local dpAddr   = baseZ + OFF_DP

local last = gg.getValues({
    {address = goldAddr, flags = FLAG},
    {address = diaAddr,  flags = FLAG},
    {address = dpAddr,   flags = FLAG}
})

local lastGold  = last[1].value
local lastDia   = last[2].value
local lastDP    = last[3].value

--------------------------------------------------
-- 4. Prepare freeze list for all X/Y/Z
--------------------------------------------------
local allList = {}
for i = 1, #zs do
    if i > 500 then break end
    allList[#allList+1] = {address = zs[i].address - 4, value = 0, flags = FLAG, freeze = true} -- X
    allList[#allList+1] = {address = zs[i].address - 8, value = 0, flags = FLAG, freeze = true} -- Y
    allList[#allList+1] = {address = zs[i].address,     value = 0, flags = FLAG, freeze = true} -- Z
end

local checkX = {address = zs[10].address - 4, flags = FLAG}
local checkY = {address = zs[10].address - 8, flags = FLAG}

local tabID = getTabID()
if not tabID then return end

--------------------------------------------------
-- 5. MAIN LOOP
--------------------------------------------------
while true do
    -- CHECK GOLD / DIAMOND / DP
    local v = gg.getValues({
        {address = goldAddr, flags = FLAG},
        {address = diaAddr,  flags = FLAG},
        {address = dpAddr,   flags = FLAG}
    })

    local gold, dia, dp = v[1].value, v[2].value, v[3].value
    if gold ~= lastGold or dia ~= lastDia then
        saveData(tabID, gold, dia, dp)
        lastGold, lastDia, lastDP = gold, dia, dp
    end

    -- CHECK X/Y
    local xy = gg.getValues({checkX, checkY})
    if math.abs(xy[1].value) > LIMIT_X or math.abs(xy[2].value) > LIMIT_Y then
        gg.addListItems(allList)
        gg.sleep(200)
        gg.removeListItems(allList)
    end
    gg.sleep(100)
end
