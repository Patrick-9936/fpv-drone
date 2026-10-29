--[[
    PlayerData — рекорды и настройки игрока с сохранением в DataStore.

    Всё, что переживает перезаход, живёт здесь:
      * лучший круг и сколько кругов пройдено;
      * сколько дронов разбито;
      * личные настройки полёта (Tuning).

    Модуль серверный по смыслу: на клиенте он ничего не делает, поэтому все
    обращения к DataStore проходят через pcall — если доступ к API не включён
    (Studio без API Access), игра продолжает работать, просто без сохранения.

    Отказоустойчивость: значения кэшируются в памяти, поэтому запись в DataStore
    идёт не чаще раза в RECORD_AUTOSAVE секунд, а не на каждый круг.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("DroneConfig"))
local Tuning = require(ReplicatedStorage:WaitForChild("Tuning"))

local PlayerData = {}

local cache  = {}   -- [player] = data
local loadedListeners = {}   -- колбэки: узнают, когда данные игрока пришли из DataStore
local dirty  = {}   -- [player] = true, если есть несохранённые изменения
local stores = nil  -- { main = DataStore, ordered = OrderedDataStore }
local storeTried = false
local nameCache = {}

local function now()
    return os.clock()
end

local function newData()
    return {
        bestLap  = 0,
        laps     = 0,
        crashes  = 0,
        tuning   = Tuning.defaults(),
        loaded   = false,
        savedAt  = 0,
        lb       = nil,   -- ссылки на значения leaderstats
    }
end

local function getStores()
    if stores then return stores end
    if storeTried then return nil end
    storeTried = true

    local ok, DataStoreService = pcall(function()
        return game:GetService("DataStoreService")
    end)
    if not ok or not DataStoreService then return nil end

    local okMain, main = pcall(function()
        return DataStoreService:GetDataStore(Config.RECORD_STORE)
    end)
    local okOrdered, ordered = pcall(function()
        return DataStoreService:GetOrderedDataStore(Config.RECORD_ORDERED_STORE)
    end)

    if okMain and okOrdered then
        stores = { main = main, ordered = ordered }
        return stores
    end

    warn("[PlayerData] DataStore недоступен — рекорды не сохраняются:", main)
    return nil
end

local function keyFor(player)
    return "player_" .. tostring(player.UserId)
end

-- ── LEADERBOARD (leaderstats) ─────────────────────────────
local function buildLeaderstats(player, data)
    local folder = player:FindFirstChild("leaderstats")
    if not folder then
        folder = Instance.new("Folder")
        folder.Name = "leaderstats"
        folder.Parent = player
    end

    local function ensure(className, name, value)
        local v = folder:FindFirstChild(name)
        if not v then
            v = Instance.new(className)
            v.Name = name
            v.Parent = folder
        end
        v.Value = value
        return v
    end

    data.lb = {
        laps    = ensure("IntValue", "Круги", data.laps or 0),
        best    = ensure("NumberValue", "Лучший круг", data.bestLap or 0),
        crashes = ensure("IntValue", "Разбито", data.crashes or 0),
    }
end

local function ensureLeaderboards()
    for _, player in ipairs(Players:GetPlayers()) do
        local data = PlayerData.get(player)
        if not data.lb then buildLeaderstats(player, data) end
    end
end

local function refreshLeaderstats(data)
    local lb = data.lb
    if not lb then return end
    if lb.laps and lb.laps.Parent then lb.laps.Value = data.laps or 0 end
    if lb.best and lb.best.Parent then lb.best.Value = data.bestLap or 0 end
    if lb.crashes and lb.crashes.Parent then lb.crashes.Value = data.crashes or 0 end
end

-- ── ПУБЛИЧНОЕ API ─────────────────────────────────────────
function PlayerData.get(player)
    local data = cache[player]
    if data then return data end
    data = newData()
    cache[player] = data
    return data
end

function PlayerData.getTuning(player)
    return PlayerData.get(player).tuning
end

local function save(player, force)
    local data = cache[player]
    if not data then return end
    if not force and not dirty[player] then return end
    if not force and (now() - (data.savedAt or 0)) < Config.RECORD_AUTOSAVE then return end

    local s = getStores()
    if not s then
        dirty[player] = false
        return
    end

    local payload = {
        bestLap = data.bestLap,
        laps    = data.laps,
        crashes = data.crashes,
        tuning  = data.tuning,
    }

    local ok, err = pcall(function()
        s.main:UpdateAsync(keyFor(player), function()
            return payload
        end)
    end)

    if ok then
        dirty[player] = false
        data.savedAt = now()
    else
        warn("[PlayerData] не сохранилось для " .. player.Name .. ": " .. tostring(err))
    end
end

PlayerData.save = save

function PlayerData.load(player)
    local data = PlayerData.get(player)
    local s = getStores()
    if s then
        local ok, stored = pcall(function()
            return s.main:GetAsync(keyFor(player))
        end)
        if ok and type(stored) == "table" then
            data.bestLap = tonumber(stored.bestLap) or 0
            data.laps    = math.floor(tonumber(stored.laps) or 0)
            data.crashes = math.floor(tonumber(stored.crashes) or 0)
            data.tuning  = Tuning.sanitize(stored.tuning)
        end
    end
    data.loaded = true
    buildLeaderstats(player, data)

    for _, fn in ipairs(loadedListeners) do
        task.spawn(fn, player, data)
    end

    return data
end

-- Подписка на окончание загрузки (нужна серверу дронов, чтобы применить
-- сохранённые настройки, а не значения по умолчанию).
function PlayerData.onLoaded(fn)
    table.insert(loadedListeners, fn)
end

function PlayerData.setTuning(player, partial)
    local data = PlayerData.get(player)
    data.tuning = Tuning.sanitize(partial)
    dirty[player] = true
    save(player, false)
    return data.tuning
end

-- Возвращает { improved, best, laps, lap }
function PlayerData.recordLap(player, seconds, lapNumber)
    local data = PlayerData.get(player)
    seconds = tonumber(seconds) or 0
    if seconds <= 0 then return { improved = false, best = data.bestLap, laps = data.laps } end

    data.laps = math.max(data.laps + 1, lapNumber or 0)
    local improved = (data.bestLap <= 0) or (seconds < data.bestLap)
    if improved then data.bestLap = seconds end

    dirty[player] = true
    refreshLeaderstats(data)

    if improved then
        PlayerData.pushBestLap(player, seconds)
    end
    save(player, false)

    return { improved = improved, best = data.bestLap, laps = data.laps, lap = seconds }
end

function PlayerData.addCrash(player)
    local data = PlayerData.get(player)
    data.crashes = data.crashes + 1
    dirty[player] = true
    refreshLeaderstats(data)
    save(player, false)
end

-- ── ГЛОБАЛЬНЫЙ ТОП ────────────────────────────────────────
function PlayerData.pushBestLap(player, seconds)
    local s = getStores()
    if not s then return end

    -- Меньше секунд — лучше. OrderedDataStore сортирует по убыванию,
    -- поэтому переворачиваем: приоритет = 10^7 - миллисекунды.
    local prio = math.max(1, 10000000 - math.floor(seconds * 1000))

    pcall(function()
        s.ordered:SetAsync(tostring(player.UserId), prio)
    end)

    nameCache[player.UserId] = player.Name
    if player:GetAttribute("BestLapName") ~= player.Name then
        player:SetAttribute("BestLapName", player.Name)
    end
end

local function nameForUserId(userId)
    if nameCache[userId] then return nameCache[userId] end
    local ok, name = pcall(function()
        return Players:GetNameFromUserIdAsync(userId)
    end)
    if ok and name then
        nameCache[userId] = name
        return name
    end
    return "Игрок " .. tostring(userId)
end

-- Возвращает массив { name, seconds } от лучшего к худшему.
function PlayerData.getTop(count)
    local result = {}
    local s = getStores()
    if not s then return result end

    local ok, pages = pcall(function()
        return s.ordered:GetSortedAsync(false, math.clamp(count or 10, 1, 25))
    end)
    if not ok or not pages then return result end

    local okPage, page = pcall(function()
        return pages:GetCurrentPage()
    end)
    if not okPage or not page then return result end

    for _, entry in ipairs(page) do
        local userId = tonumber(entry.key)
        local seconds = (10000000 - (tonumber(entry.value) or 0)) / 1000
        if userId and seconds > 0 then
            table.insert(result, {
                name    = nameForUserId(userId),
                seconds = seconds,
            })
        end
    end

    return result
end

-- ── ПОДКЛЮЧЕНИЕ ───────────────────────────────────────────
function PlayerData.attach()
    if not RunService:IsServer() then return end

    local function onPlayer(player)
        cache[player] = newData()
        task.spawn(function()
            PlayerData.load(player)
        end)
    end

    Players.PlayerAdded:Connect(onPlayer)
    for _, p in ipairs(Players:GetPlayers()) do onPlayer(p) end

    Players.PlayerRemoving:Connect(function(player)
        save(player, true)
        cache[player] = nil
        dirty[player] = nil
    end)

    -- Периодическая запись: игрок мог уйти с открытой вкладкой
    task.spawn(function()
        while true do
            task.wait(Config.RECORD_AUTOSAVE)
            for player in pairs(cache) do
                save(player, true)
            end
        end
    end)

    game:BindToClose(function()
        for player in pairs(cache) do
            save(player, true)
        end
    end)

    ensureLeaderboards()
end

return PlayerData
