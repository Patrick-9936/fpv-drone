--[[
    DroneClient v13 — управление, камера, интерфейс.

    Клиент по-прежнему НЕ трогает физику: он отправляет стики, сервер считает полёт.
    Что добавилось:
      * личные настройки полёта (скорость, чувствительность, инверсия) — ползунки в
        меню, сервер их проверяет и сохраняет;
      * гонка: кольца по порядку, таймер круга, подсветка следующего кольца;
      * кнопка «Взять дрон» — запрос к серверу, а не клик по невидимому хитбоксу;
      * весь интерфейс вынесен в модуль DroneUI.
]]

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config  = require(ReplicatedStorage:WaitForChild("DroneConfig"))
local Tuning  = require(ReplicatedStorage:WaitForChild("Tuning"))
local DroneUI = require(script.Parent:WaitForChild("DroneUI"))

local remotes = ReplicatedStorage:WaitForChild("DroneRemotes")

local mountRemote        = remotes:WaitForChild("MountDrone")
local lostRemote         = remotes:WaitForChild("DroneLost")
local inputRemote        = remotes:WaitForChild("DroneInput")
local unmountRemote      = remotes:WaitForChild("UnmountDrone")
local selfDestructRemote = remotes:WaitForChild("SelfDestruct")
local requestRemote      = remotes:WaitForChild("RequestDrone")
local tuningRemote       = remotes:WaitForChild("TuningChanged")
local tuningSync         = remotes:WaitForChild("TuningSync")
local tuningRequest      = remotes:WaitForChild("RequestTuning")
local notifyRemote       = remotes:WaitForChild("Notify")
local raceRemote         = remotes:WaitForChild("RaceEvent")
local getTopRecords      = remotes:WaitForChild("GetTopRecords")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- ────────────────────── СОСТОЯНИЕ ──────────────────────────
local mounted    = false
local droneModel = nil
local droneBody  = nil
local motorSound = nil
local windSound  = nil

local rawPitch   = 0     -- +1 = вперёд
local rawRoll    = 0     -- +1 = вправо
local rawYaw     = 0     -- +1 = вправо
local throttleIn = 0.5   -- 0.5 = стик в центре (дрон проседает), 1 = вверх

local keysDown   = {}
local isMobile   = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local inputAccum = 0
local tuningSendToken = 0

local smoothCF   = nil
local lastPos    = nil
local smoothSpeed = 0

-- гонка
local raceIndex  = 1
local lapStart   = 0
local bestLap    = 0
local ringTintIndex = -1

local leftTouchId, rightTouchId
local leftJoyCenter, rightJoyCenter
local JOY_RADIUS = 55

-- forward declarations
local unmountDrone
local manualDetonate
local localUnmount
local forceExit

-- ────────────────────── ЗВУК ВЕТРА ─────────────────────────
windSound = Instance.new("Sound")
windSound.Name = "DroneWindSFX"
windSound.SoundId = "rbxasset://sounds/action_falling.mp3"
windSound.Looped = true
windSound.Volume = 0
windSound.Parent = camera

-- ────────────────────── ИНТЕРФЕЙС ──────────────────────────
local ui = DroneUI.new({
    player = player,
    isMobile = isMobile,

    onTake = function()
        requestRemote:FireServer()
    end,

    onDetonate = function()
        if mounted then manualDetonate() end
    end,

    onExit = function()
        if mounted then unmountDrone() end
    end,

    onTuningChanged = function(t)
        -- Отправляем на сервер с небольшой задержкой: при перетаскивании ползунка
        -- не нужно по 30 пакетов в секунду.
        tuningSendToken = tuningSendToken + 1
        local token = tuningSendToken
        task.delay(0.15, function()
            if token ~= tuningSendToken then return end
            tuningRemote:FireServer(t)
        end)
    end,

    onRequestRecords = function()
        task.spawn(function()
            local ok, list = pcall(function()
                return getTopRecords:InvokeServer()
            end)
            if ok then
                ui:setRecords(list)
            else
                ui:setRecords({})
                ui:toast("Не удалось загрузить таблицу рекордов", "bad")
            end
        end)
    end,
})

ui:setPersonalBest(0)

-- Сообщения сервера, отправленные до подписки, теряются, поэтому просим
-- настройки явно — иначе у игрока будут дефолтные ползунки вместо сохранённых.
task.defer(function()
    tuningRequest:FireServer()
end)

-- ────────────────────── ВВОД ───────────────────────────────
local function resetInputs()
    leftTouchId = nil
    rightTouchId = nil
    leftJoyCenter = nil
    rightJoyCenter = nil
    rawPitch = 0
    rawRoll = 0
    rawYaw = 0
    throttleIn = 0.5
    keysDown = {}
    ui:setStick("left", nil)
    ui:setStick("right", nil)
end

if isMobile then
    UserInputService.InputBegan:Connect(function(input, gp)
        if gp or not mounted or ui:isMenuOpen() then return end
        if input.UserInputType ~= Enum.UserInputType.Touch then return end

        local pos = Vector2.new(input.Position.X, input.Position.Y)
        local screenW = camera.ViewportSize.X

        if pos.X < (screenW * 0.5) and not leftTouchId then
            leftTouchId = input
            leftJoyCenter = pos
        elseif not rightTouchId then
            rightTouchId = input
            rightJoyCenter = pos
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.Touch then return end
        local dz = 0.02

        if input == leftTouchId and leftJoyCenter then
            local delta = Vector2.new(input.Position.X, input.Position.Y) - leftJoyCenter
            local norm = delta / JOY_RADIUS
            if norm.Magnitude > 1 then norm = norm.Unit end

            rawYaw = (math.abs(norm.X) > dz) and norm.X or 0
            throttleIn = math.clamp(0.5 - (norm.Y * 0.5), 0, 1)
            ui:setStick("left", norm)

        elseif input == rightTouchId and rightJoyCenter then
            local delta = Vector2.new(input.Position.X, input.Position.Y) - rightJoyCenter
            local norm = delta / JOY_RADIUS
            if norm.Magnitude > 1 then norm = norm.Unit end

            rawRoll  = (math.abs(norm.X) > dz) and norm.X or 0
            rawPitch = (math.abs(norm.Y) > dz) and -norm.Y or 0      -- палец вверх = вперёд
            ui:setStick("right", norm)
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input == leftTouchId then
            leftTouchId = nil
            leftJoyCenter = nil
            rawYaw = 0
            throttleIn = 0.5
            ui:setStick("left", nil)
        end
        if input == rightTouchId then
            rightTouchId = nil
            rightJoyCenter = nil
            rawRoll = 0
            rawPitch = 0
            ui:setStick("right", nil)
        end
    end)
end

UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.UserInputType == Enum.UserInputType.Keyboard then
        keysDown[input.KeyCode] = true
        if input.KeyCode == Enum.KeyCode.F and mounted then
            unmountDrone()
        elseif (input.KeyCode == Enum.KeyCode.R or input.KeyCode == Enum.KeyCode.X) and mounted then
            manualDetonate()
        end
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Keyboard then
        keysDown[input.KeyCode] = false
    end
end)

local function readKeyboard()
    rawPitch = 0
    rawRoll  = 0
    rawYaw   = 0

    if keysDown[Enum.KeyCode.W] then rawPitch =  1 end
    if keysDown[Enum.KeyCode.S] then rawPitch = -1 end
    if keysDown[Enum.KeyCode.D] then rawRoll  =  1 end
    if keysDown[Enum.KeyCode.A] then rawRoll  = -1 end
    if keysDown[Enum.KeyCode.E] then rawYaw   =  1 end
    if keysDown[Enum.KeyCode.Q] then rawYaw   = -1 end

    if keysDown[Enum.KeyCode.Space] then
        throttleIn = math.min(throttleIn + 0.03, 1)
    elseif keysDown[Enum.KeyCode.LeftShift] or keysDown[Enum.KeyCode.RightShift] then
        throttleIn = math.max(throttleIn - 0.03, 0)
    else
        -- стик отпущен: возвращается в центр, дрон плавно проседает
        if throttleIn > 0.52 then
            throttleIn = math.max(0.5, throttleIn - 0.015)
        elseif throttleIn < 0.48 then
            throttleIn = math.min(0.5, throttleIn + 0.015)
        else
            throttleIn = 0.5
        end
    end
end

-- ────────────────────── ПЕРСОНАЖ И ЭФФЕКТЫ ─────────────────
local function setCharVisible(vis)
    local char = player.Character
    if not char then return end
    local t = vis and 0 or 1
    for _, p in char:GetDescendants() do
        if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
            p.LocalTransparencyModifier = t
        elseif p:IsA("Decal") or p:IsA("Texture") then
            p.Transparency = t
        end
    end
end

local function setOwnModelVisible(vis)
    if not droneModel then return end
    pcall(function()
        for _, p in droneModel:GetDescendants() do
            if p:IsA("BasePart") then
                p.LocalTransparencyModifier = vis and 0 or 1
            end
        end
    end)
end

local function setPropWash(enabled)
    if not droneModel then return end
    for _, p in droneModel:GetDescendants() do
        if p:IsA("ParticleEmitter") and p.Name == "Wash" then
            p.Enabled = enabled
        end
    end
end

local function freezeCharacter(frozen)
    local char = player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    if frozen then
        hum.WalkSpeed = 0
        pcall(function() hum.JumpHeight = 0 end)
        pcall(function() hum.JumpPower = 0 end)
    else
        hum.WalkSpeed = 16
        pcall(function() hum.JumpPower = 50 end)
        pcall(function() hum.JumpHeight = 7.2 end)
    end
end

local function showStatus(text)
    ui:toast(text)
end

-- Аварийный выход: работает, даже если клиент потерял своё состояние,
-- иначе игрок остаётся в мёртвой FPV-камере и не может взять новый дрон
forceExit = function(text)
    localUnmount(false, nil)
    camera.CameraType = Enum.CameraType.Custom
    setCharVisible(true)
    freezeCharacter(false)
    if text then showStatus(text) end
end

-- ────────────────────── ВЫХОД (ЛОКАЛЬНЫЙ) ──────────────────
localUnmount = function(notifyServer, lostReason)
    if not mounted then return end
    mounted = false

    resetInputs()

    setOwnModelVisible(true)

    if motorSound then motorSound:Stop() end
    if windSound  then windSound.Volume = 0 end
    setPropWash(false)

    camera.CameraType = Enum.CameraType.Custom
    ui:setMounted(false)
    ui:setWarning(false)
    setCharVisible(true)
    freezeCharacter(false)

    droneModel = nil
    droneBody  = nil
    motorSound = nil
    smoothCF   = nil
    lastPos    = nil
    smoothSpeed = 0
    raceIndex = 1
    ringTintIndex = -1
    tintRings(0)

    if notifyServer then
        unmountRemote:FireServer()
    end
    if lostReason then
        showStatus(lostReason)
    end
end

unmountDrone = function()
    if not mounted then return end
    -- дрон останется в мире: сервер плавно посадит его, и его снова можно взять
    localUnmount(true, nil)
end

manualDetonate = function()
    if not mounted then return end
    -- без локальной вспышки: единственный эффект пришлёт сервер (DroneLost)
    localUnmount(false, nil)
    selfDestructRemote:FireServer()
end

-- ────────────────────── КОЛЬЦА ─────────────────────────────
-- Подсветка следующего кольца делается локально (клиентский цвет не
-- реплицируется), поэтому у каждого игрока своя картина гонки.
function tintRings(nextIndex)
    if ringTintIndex == nextIndex then return end
    ringTintIndex = nextIndex

    local map = workspace:FindFirstChild("Map")
    local obs = map and map:FindFirstChild("Obstacles")
    local folder = obs and obs:FindFirstChild("RaceRings")
    if not folder then return end

    for _, ring in ipairs(folder:GetChildren()) do
        local index = ring:GetAttribute("RingIndex") or 0
        local isNext = (index == nextIndex)
        local color = isNext and Color3.fromRGB(120, 232, 150) or Color3.fromRGB(96, 104, 118)

        for _, part in ipairs(ring:GetChildren()) do
            if part:IsA("BasePart") and part.Name == "Seg" then
                part.Color = color
            end
        end

        local sign = ring:FindFirstChild("Sign")
        local bill = sign and sign:FindFirstChildOfClass("BillboardGui")
        local label = bill and bill:FindFirstChildOfClass("TextLabel")
        if label then
            label.TextColor3 = isNext and Color3.fromRGB(190, 255, 205) or Color3.fromRGB(170, 176, 188)
        end
    end
end

-- ────────────────────── МАУНТ ──────────────────────────────
local function mountDrone(drone)
    if mounted or not drone then return end

    local body = drone.PrimaryPart
    if not body then return end

    droneModel = drone
    droneBody  = body
    motorSound = body:FindFirstChild("MotorSound")

    resetInputs()
    mounted = true
    smoothCF = body.CFrame
    lastPos = body.Position
    smoothSpeed = 0

    camera.CameraType = Enum.CameraType.Scriptable

    if motorSound then
        motorSound.Volume = 0.5
        motorSound.PlaybackSpeed = 0.95
        motorSound:Play()
    end
    windSound.Volume = 0
    windSound:Play()

    setPropWash(true)
    setCharVisible(false)
    setOwnModelVisible(false)
    freezeCharacter(true)

    ui:setMounted(true)

    -- сразу отправляем нейтральный ввод, чтобы сервер не держал старое значение
    inputRemote:FireServer(0, 0, 0, 0.5)
end

-- ────────────────────── ГЛАВНЫЙ ЦИКЛ ───────────────────────
local CAM_TILT_RAD = math.rad(Config.CAM_TILT)

RunService.RenderStepped:Connect(function(dt)
    if not mounted then
        -- подсказка о ближайшем дроне, пока игрок на земле
        if droneModel == nil then
            local nearest, nearestDist = nil, math.huge
            local drones = workspace:FindFirstChild("Drones")
            local char = player.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            if drones and root then
                for _, d in ipairs(drones:GetChildren()) do
                    local part = d.PrimaryPart
                    if part and (d:GetAttribute("PilotUserId") or 0) == 0 then
                        local dist = (part.Position - root.Position).Magnitude
                        if dist < nearestDist then nearest, nearestDist = d, dist end
                    end
                end
            end

            if nearest then
                ui:setTakeHint(string.format("Ближайший дрон в %d студах", math.floor(nearestDist)))
            else
                ui:setTakeHint("Свободного дрона рядом нет")
            end
        end
        return
    end

    -- Дрон исчез (взорван сервером / удалён) — выходим из режима пилота
    if not droneBody or not droneBody.Parent then
        forceExit("Дрон потерян")
        return
    end

    if not isMobile then
        readKeyboard()
    end

    -- 1. Стики на сервер ~30 раз в секунду.
    --    Пока открыто меню, ввод обнуляем, чтобы дрон не улетел под ползунками.
    local raw = { pitch = rawPitch, roll = rawRoll, yaw = rawYaw, throttle = throttleIn }
    if ui:isMenuOpen() then
        raw = { pitch = 0, roll = 0, yaw = 0, throttle = 0.5 }
    end
    local input = Tuning.envelope(raw, ui:getTuning())

    inputAccum = inputAccum + dt
    if inputAccum >= (1 / 30) then
        inputAccum = 0
        inputRemote:FireServer(input.pitch, input.roll, input.yaw, input.throttle)
    end

    -- 2. Камера
    local targetCF = droneBody.CFrame
    smoothCF = smoothCF:Lerp(targetCF, math.clamp(dt * 22, 0, 1))
    camera.CFrame = smoothCF
        * CFrame.new(0, 0.45, -2.35)
        * CFrame.Angles(-CAM_TILT_RAD, 0, 0)

    -- 3. Скорость для HUD (по фактическому смещению)
    local pos = droneBody.Position
    if lastPos then
        local inst = (pos - lastPos).Magnitude / math.max(dt, 0.001)
        smoothSpeed = smoothSpeed + (inst - smoothSpeed) * 0.2
    end
    lastPos = pos

    -- 4. Звуки
    if motorSound then
        motorSound.PlaybackSpeed = 0.85 + (throttleIn * 0.45)
            + math.clamp(smoothSpeed / ui:getTuning().maxSpeed, 0, 1) * 0.25
        motorSound.Volume = 0.35 + (throttleIn * 0.3)
    end
    windSound.Volume = math.clamp(smoothSpeed / ui:getTuning().maxSpeed * 0.7, 0, 0.7)

    -- 5. Предупреждение о границе
    local hDist = Vector2.new(pos.X, pos.Z).Magnitude
    local isOut = hDist > (Config.BOUNDS_RADIUS - 40) or pos.Y > (Config.BOUNDS_MAX_Y - 40)
    ui:setWarning(isOut)

    -- 6. HUD
    ui:updateTelemetry({ speed = smoothSpeed, alt = pos.Y, throttle = throttleIn })
    ui:updateRace({
        lapTime  = math.max(0, tick() - lapStart),
        best     = bestLap,
        nextRing = raceIndex,
        total    = #Config.RACE_RINGS,
    })
    tintRings(raceIndex)

    -- персонаж не должен ходить: сервер ставит WalkSpeed, но клиент тоже держит
    local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
    if hum and hum.WalkSpeed > 0 then hum.WalkSpeed = 0 end
end)

-- ────────────────────── REMOTE LISTENERS ───────────────────
mountRemote.OnClientEvent:Connect(function(drone)
    mountDrone(drone)
end)

lostRemote.OnClientEvent:Connect(function(reason)
    local text
    if reason == "manual" then
        text = "Дрон подорван"
    elseif reason == "borders" then
        text = "Дрон улетел за карту"
    elseif reason == "timeout" then
        text = "Связь с дроном потеряна"
    else
        text = "Дрон разбился"
    end
    ui:flash(Color3.fromRGB(255, 90, 60), 0.15)
    forceExit(text)
end)

notifyRemote.OnClientEvent:Connect(function(text)
    ui:toast(tostring(text), "warn")
end)

tuningSync.OnClientEvent:Connect(function(t)
    ui:setTuning(t)
end)

raceRemote.OnClientEvent:Connect(function(kind, a, b, c)
    if kind == "start" then
        raceIndex = 1
        lapStart = tick()
        tintRings(1)
    elseif kind == "checkpoint" then
        raceIndex = a or raceIndex
        ui:toast(string.format("Кольцо %d из %d", raceIndex, b or #Config.RACE_RINGS))
    elseif kind == "lap" then
        local seconds = a or 0
        local best = b or 0
        bestLap = best
        raceIndex = 1
        lapStart = tick()
        tintRings(1)
        if c then
            ui:toast(string.format("Круг пройден: %.2f — новый рекорд", seconds), "ok")
        else
            ui:toast(string.format("Круг пройден: %.2f", seconds), "ok")
        end
        ui:setPersonalBest(best)
    elseif kind == "reset" then
        raceIndex = 1
        lapStart = tick()
        tintRings(1)
    end
end)

player.CharacterAdded:Connect(function()
    if mounted then
        localUnmount(true, nil)
    end
    freezeCharacter(false)
end)

-- Личный рекорд подтягиваем из leaderstats (сервер пишет туда сразу после круга).
task.spawn(function()
    local stats = player:WaitForChild("leaderstats", 20)
    if not stats then return end
    local best = stats:WaitForChild("Лучший круг", 20)
    if not best then return end

    local function sync()
        if best.Value and best.Value > 0 then
            bestLap = best.Value
            ui:setPersonalBest(best.Value)
        end
    end

    sync()
    best.Changed:Connect(sync)
end)

ui:setMounted(false)
