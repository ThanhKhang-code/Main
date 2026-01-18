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

gg.clearResults()
gg.setRanges(gg.REGION_ANONYMOUS)

--------------------------------------------------
-- CONFIG
--------------------------------------------------
local Z_VALUE = 4119
local FLAG = gg.TYPE_DWORD
local MIN_Z = 800

-- OFFSETS
local OFF_UID     = 0x22A90C
local OFF_GOLD    = 0x22ACD4
local OFF_DIAMOND = 0x22ACF4
local OFF_DP      = 0x22EA1C

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
        local input = gg.prompt({"Nhập số tab_id"}, {""}, {"number"})
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

-- Ghi dữ liệu GOLD|DIAMONDS|DP|TIME
local function saveData(tabID, gold, dia, dp)
    local scriptDir = gg.getFile():gsub("[^/]+$", "")
    local filePath = scriptDir .. "id/" .. tabID .. ".txt"  -- folder "id" bạn đã tạo
    local f = io.open(filePath, "w")  -- ghi đè file
    if f then
        f:write(string.format("%d|%d|%d|%s", gold, dia, dp, now()))
        f:close()
    end
end

--------------------------------------------------
-- 1. Scan Z
--------------------------------------------------
local zs = {}
while true do
    gg.clearResults()
    gg.searchNumber(Z_VALUE, FLAG)
    if gg.getResultCount() >= MIN_Z then
        zs = gg.getResults(MIN_Z)
        break
    end
    gg.sleep(500)
end
gg.clearResults()

--------------------------------------------------
-- 2. Find Z *38C
--------------------------------------------------
local baseZ
for i = 1, #zs do
    if (zs[i].address & 0xFFF) == 0x9BC then
        baseZ = zs[i].address
        break
    end
end
if not baseZ then return end

--------------------------------------------------
-- 3. Build monitor addresses
--------------------------------------------------
local uidAddr  = baseZ + OFF_UID
local goldAddr = baseZ + OFF_GOLD
local diaAddr  = baseZ + OFF_DIAMOND
local dpAddr   = baseZ + OFF_DP

local last = gg.getValues({
    {address = uidAddr,  flags = FLAG},
    {address = goldAddr, flags = FLAG},
    {address = diaAddr,  flags = FLAG},
    {address = dpAddr,   flags = FLAG}
})

local lastUID   = last[1].value
local lastGold  = last[2].value
local lastDia   = last[3].value
local lastDP    = last[4].value

--------------------------------------------------
-- 4. Prepare freeze list for all X/Y/Z
--------------------------------------------------
local allList = {}
for i = 1, #zs do
    allList[#allList+1] = {address = zs[i].address - 4, value = 0, flags = FLAG, freeze = true} -- X
    allList[#allList+1] = {address = zs[i].address - 8, value = 0, flags = FLAG, freeze = true} -- Y
    allList[#allList+1] = {address = zs[i].address,     value = 0, flags = FLAG, freeze = true} -- Z
end

local checkX = {address = zs[1].address - 4, flags = FLAG}
local checkY = {address = zs[1].address - 8, flags = FLAG}

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
        gg.sleep(200)  -- freeze tạm thời
        gg.removeListItems(allList)
    end

    gg.sleep(100)
end
