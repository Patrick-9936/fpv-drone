--[[
    Дымовой тест UI на заглушке Roblox API.
    Запуск:  lua tests/ui_smoke.lua   (из папки fpv-drone)

    Проверяет, что интерфейс действительно собирается и что его публичные методы
    не падают: опечатки в названиях свойств и nil-индексы всплывают сразу,
    а не в игре.
]]

package.path = "src/shared/?.lua;tests/?.lua;" .. package.path

math.clamp = function(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi else return v end
end

-- Roblox-глобалы, которых нет в обычном Lua
task = {
    spawn = function(fn, ...) if fn then fn(...) end end,
    defer = function(fn) if fn then fn() end end,
    delay = function(_, fn) if fn then fn() end end,
    wait = function() return 0 end,
}
tick = os.clock

-- В Roblox require() принимает Instance модуля; здесь — таблицу модуля.
local realRequire = require
require = function(target)
    if type(target) == "table" then
        return target.module or target
    end
    return realRequire(target)
end

local stub = require("roblox_stub")

-- глобальные имена, которые в Roblox есть всегда
game       = stub.game
Instance   = stub.Instance
Enum       = stub.Enum
UDim2      = stub.UDim2
UDim       = stub.UDim
Vector2    = stub.Vector2
Vector3    = stub.Vector3
Color3     = stub.Color3
CFrame     = stub.CFrame
TweenInfo  = stub.TweenInfo
workspace  = stub.workspace

local failures = 0
local function check(name, fn)
    local ok, err = pcall(fn)
    if ok then
        print(string.format("  PASS  %s", name))
    else
        failures = failures + 1
        print(string.format("  FAIL  %s\n        %s", name, tostring(err)))
    end
end

print("\n[1] Модуль UI загружается и собирает интерфейс")
local DroneUI
check("require DroneUI", function()
    DroneUI = dofile("src/client/DroneUI.lua")
    assert(type(DroneUI) == "table", "модуль должен вернуть таблицу")
    assert(type(DroneUI.new) == "function", "нет DroneUI.new")
end)

local ui
local tuningSent, takeCalls, recordCalls = nil, 0, 0

check("DroneUI.new (мобильная раскладка)", function()
    ui = DroneUI.new({
        player = stub.Player,
        isMobile = true,
        onTake = function() takeCalls = takeCalls + 1 end,
        onDetonate = function() end,
        onExit = function() end,
        onTuningChanged = function(t) tuningSent = t end,
        onRequestRecords = function() recordCalls = recordCalls + 1 end,
    })
    assert(ui, "ui не создан")
end)

print("\n[2] Публичные методы UI")
if ui then
    check("setTuning принимает мусор", function()
        ui:setTuning({ maxSpeed = 10000, invertPitch = true, ["мусор"] = 1 })
        local t = ui:getTuning()
        assert(t.maxSpeed == 180, "clamp не сработал: " .. tostring(t.maxSpeed))
        assert(t.invertPitch == true)
    end)

    check("updateTelemetry/updateRace", function()
        ui:updateTelemetry({ speed = 87.4, alt = 42.6, throttle = 0.7 })
        ui:updateRace({ lapTime = 12.345, best = 10.5, nextRing = 2, total = 3 })
    end)

    check("toast и flash", function()
        ui:toast("Проверка", "ok")
        ui:toast("Проверка", "bad")
        ui:flash(nil, 0.3)
    end)

    check("setRecords с данными", function()
        ui:setRecords({
            { name = "Patrick919481", seconds = 12.34 },
            { name = "Друг", seconds = 14.9 },
            { name = "Кто-то", seconds = 20 },
        })
        ui:setRecords({})
        ui:setRecords(nil)
    end)

    check("setPersonalBest", function()
        ui:setPersonalBest(12.34)
        ui:setPersonalBest(0)
    end)

    check("монтирование/меню", function()
        ui:setMounted(true)
        assert(ui.mounted == true)
        ui:openMenu()
        assert(ui.menuOpen == true)
        ui:closeMenu()
        assert(ui.menuOpen == false)
        ui:toggleMenu()
        ui:toggleMenu()
        ui:setMounted(false)
    end)

    check("стики", function()
        ui:setStick("left", { X = 0.4, Y = -0.2 })
        ui:setStick("left", nil)
        ui:setStick("right", { X = 0, Y = 0 })
        ui:setStick("right", nil)
    end)

    check("подсказка «взять дрон»", function()
        ui:setTakeHint("Ближайший дрон в 30 студах")
    end)
end

print("\n[3] Клиентский скрипт загружается")
check("dofile DroneClient", function()
    local remotes = Instance.new("Folder")
    remotes.Name = "DroneRemotes"
    remotes.Parent = stub.replicated

    -- клиент берёт DroneUI у себя из StarterPlayerScripts
    script = {
        Parent = {
            WaitForChild = function(_, name)
                assert(name == "DroneUI", "клиент ждёт не тот модуль: " .. tostring(name))
                return { module = dofile("src/client/DroneUI.lua") }
            end,
        },
    }

    dofile("src/client/DroneClient.client.lua")
end)

print("\n[4] Кадр в режиме пилота")
check("монтаж дрона и кадр полёта", function()
    local remotes = stub.replicated:FindFirstChild("DroneRemotes")
    assert(remotes, "нет DroneRemotes")

    local body = Instance.new("Part")
    body.Name = "Body"
    body.CFrame = stub.CFrame.new(0, 20, 0)

    local drone = Instance.new("Model")
    drone.Name = "FPV_Drone_1"
    drone.PrimaryPart = body
    body.Parent = drone

    remotes:FindFirstChild("MountDrone").OnClientEvent:Fire(drone)

    for _ = 1, 10 do
        stub.RunService.RenderStepped:Fire(1 / 60)
    end

    remotes:FindFirstChild("DroneLost").OnClientEvent:Fire("crash")
end)

print("")
if failures == 0 then
    print("ИТОГ: UI собирается, методов без ошибок")
    os.exit(0)
else
    print(string.format("ИТОГ: провалено проверок: %d", failures))
    os.exit(1)
end
