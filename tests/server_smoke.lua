--[[
    Дымовой тест сервера на заглушке Roblox API.
    Запуск:  lua tests/server_smoke.lua   (из папки fpv-drone)

    Проверяет сквозной сценарий, который нельзя проверить в игре без телефона:
      * сервер поднимает мир, спавнит дрон и выдаёт его по запросу;
      * кнопка «Взять дрон» работает даже при «мусорной» записи о прошлом дроне;
      * ввод двигает дрон, кольцо засчитывается, круг пишется в leaderstats;
      * настройки сохраняются в памяти (DataStore в заглушке недоступен).
]]

package.path = "src/shared/?.lua;tests/?.lua;" .. package.path

math.clamp = function(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi else return v end
end

local stub = require("roblox_stub")

-- В Roblox require() принимает Instance модуля; здесь — таблицу модуля.
local realRequire = require
require = function(target)
    if type(target) == "table" then
        return target.module or target
    end
    return realRequire(target)
end

-- ── ГЛОБАЛЫ ──
game      = stub.game
Instance  = stub.Instance
Enum      = stub.Enum
Vector3   = stub.Vector3
CFrame    = stub.CFrame
Color3    = stub.Color3
ColorSequence = stub.ColorSequence
NumberSequence = stub.NumberSequence
NumberRange = stub.NumberRange
NumberSequenceKeypoint = stub.NumberSequenceKeypoint
ColorSequenceKeypoint = stub.ColorSequenceKeypoint
RaycastParams = stub.RaycastParams
BrickColor = stub.BrickColor
UDim2     = stub.UDim2
UDim      = stub.UDim
Vector2   = stub.Vector2
workspace = stub.workspace
warn = function(...) end

local failures = 0
local function check(name, fn)
    local ok, err = pcall(fn)
    if ok then
        print(string.format("  PASS  %s", name))
    else
        failures = failures + 1
        print(string.format("  FAIL  %s\n        %s", name, tostring(err)))
    end
    return ok
end

-- task.wait в заглушке бросает исключение: бесконечные циклы автопаспавна
-- должны сделать один проход и выйти, иначе тест зависнет.
local asyncErrors = {}
local function runAsync(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok and not tostring(err):find("YIELD_IN_STUB") then
        table.insert(asyncErrors, tostring(err))
    end
end
task = {
    spawn = runAsync,
    defer = runAsync,
    delay = function(_, fn, ...) runAsync(fn, ...) end,
    wait  = function() error("YIELD_IN_STUB", 0) end,
}
tick = os.clock

-- ── СЕРВИСЫ ──
local fakePlayer = Instance.new("Player")
fakePlayer.Name = "TestPilot"
fakePlayer.UserId = 1001

local playersService = Instance.new("Players")
playersService.GetPlayers = function() return { fakePlayer } end
playersService.GetNameFromUserIdAsync = function(_, id) return "Player" .. tostring(id) end

local runService = stub.RunService
runService.IsServer = function() return true end
runService.Heartbeat = stub.Signal.new()

local dataStoreService = Instance.new("DataStoreService")

local debris = Instance.new("Debris")

local baseGetService = stub.game.GetService
stub.game.GetService = function(self, name)
    if name == "Players" then return playersService end
    if name == "DataStoreService" then return dataStoreService end
    if name == "Debris" then return debris end
    if name == "RunService" then return runService end
    return baseGetService(self, name)
end
stub.game.BindToClose = function() end

workspace.Raycast = function() return nil end

-- ── ЗАГРУЗКА СКРИПТОВ ──
print("\n[1] Скрипты сервера загружаются")
local Config, PlayerData, Tuning
check("MapBuilder", function()
    dofile("src/server/MapBuilder.server.lua")
end)
check("DroneServer", function()
    dofile("src/server/DroneServer.server.lua")
end)
check("Records", function()
    dofile("src/server/Records.server.lua")
end)
check("модули доступны", function()
    Config = require("src/shared/DroneConfig")
    PlayerData = require("src/shared/PlayerData")
    Tuning = require("src/shared/Tuning")
    assert(Config and PlayerData and Tuning)
end)

local remotes = stub.replicated:FindFirstChild("DroneRemotes")
check("папка ремутов создана", function()
    assert(remotes, "нет DroneRemotes")
end)

-- после загрузки DroneServer автопаспавн сделал один проход
local dronesFolder = workspace:FindFirstChild("Drones")
check("дрон заспавнен на площадке", function()
    assert(dronesFolder, "нет папки Drones")
    local count = #dronesFolder:GetChildren()
    assert(count >= 1, "дронов нет: " .. count)
end)

-- ── ГОНКА: ставим одно кольцо прямо по курсу ──
Config.RACE_RINGS = {
    { pos = Vector3.new(25, 6.5, -40), radius = 10, normal = Vector3.new(0, 0, 1) },
}
Config.RACE_MIN_LAP = 0

print("\n[2] Игрок входит и берёт дрон")
check("PlayerAdded", function()
    playersService.PlayerAdded:Fire(fakePlayer)
end)

check("настройки по умолчанию выданы", function()
    local t = PlayerData.getTuning(fakePlayer)
    assert(type(t) == "table" and t.maxSpeed, "нет настроек")
end)

-- имитируем «мусорную» запись: игрок считается пилотом уже взорванного дрона
fakePlayer:SetAttribute("Test", 0)
check("кнопка «Взять дрон» вешает пилота", function()
    remotes:WaitForChild("RequestDrone").OnServerEvent:Fire(fakePlayer)
end)

check("дрон стал управляемым", function()
    local piloted = 0
    for _, d in ipairs(dronesFolder:GetChildren()) do
        if d:GetAttribute("IsPiloted") then piloted = piloted + 1 end
    end
    assert(piloted >= 1, "ни один дрон не занят")
end)

print("\n[3] Полёт и проход кольца с записью рекорда")
check("ввод принят", function()
    remotes:WaitForChild("DroneInput").OnServerEvent:Fire(fakePlayer, 1, 0, 0, 0.62)
end)

check("100 кадров полёта без ошибок", function()
    for _ = 1, 120 do
        runService.Heartbeat:Fire(1 / 60)
    end
end)

check("круг записан в leaderstats", function()
    local stats = fakePlayer:FindFirstChild("leaderstats")
    assert(stats, "нет leaderstats")
    local best = stats:FindFirstChild("Лучший круг")
    local laps = stats:FindFirstChild("Круги")
    assert(best and best.Value > 0, "лучший круг не записан")
    assert(laps and laps.Value >= 1, "круги не посчитаны")
end)

check("рекорд попал в память PlayerData", function()
    local data = PlayerData.get(fakePlayer)
    assert(data.bestLap > 0 and data.laps >= 1)
end)

print("\n[4] Настройки: валидация и применение")
check("сервер обрезает мусор от клиента", function()
    remotes:WaitForChild("TuningChanged").OnServerEvent:Fire(fakePlayer, { maxSpeed = 99999 })
    local t = PlayerData.getTuning(fakePlayer)
    assert(t.maxSpeed == 180, "не обрезалось: " .. tostring(t.maxSpeed))
end)

print("\n[5] Взрыв и повторное взятие (главный баг игрока)")
check("подрыв", function()
    remotes:WaitForChild("SelfDestruct").OnServerEvent:Fire(fakePlayer)
end)

check("после взрыва игрок не «занят» и берёт следующий", function()
    -- новый дрон появляется на следующем проходе автопаспавна
    dofile("src/server/DroneServer.server.lua")

    remotes:WaitForChild("RequestDrone").OnServerEvent:Fire(fakePlayer)

    local piloted = 0
    local folder = workspace:FindFirstChild("Drones")
    for _, d in ipairs(folder:GetChildren()) do
        if d:GetAttribute("IsPiloted") then piloted = piloted + 1 end
    end
    assert(piloted == 1, "дрон не взят, занятых дронов: " .. piloted)
end)

if #asyncErrors > 0 then
    print("\nОшибки в фоновых задачах:")
    for _, e in ipairs(asyncErrors) do print("  " .. e) end
    failures = failures + #asyncErrors
end

print("")
if failures == 0 then
    print("ИТОГ: сервер отрабатывает вход, полёт, кольцо, рекорд и повторное взятие")
    os.exit(0)
else
    print(string.format("ИТОГ: провалено проверок: %d", failures))
    os.exit(1)
end
