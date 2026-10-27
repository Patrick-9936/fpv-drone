--[[
    DroneServer v5
    - Поддержка мульти-дронов: автоматический спавн каждые 3 секунды,
      если посадочная площадка свободна (друзья могут брать свои дроны!)
    - Дроны на площадке стоят с Anchored = true (не падают, не улетают, 100% стабильны)
    - Ручная детонация (💥 ПОДРЫВ) по кнопке
    - Качественная детальная модель гоночного квадрокоптера
    - Серверный watchdog границ и очистка при выходе
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local Debris            = game:GetService("Debris")

local Config = require(ReplicatedStorage:WaitForChild("DroneConfig"))

-- ────────────────────── REMOTE EVENTS ──────────────────────
local remotes = ReplicatedStorage:FindFirstChild("DroneRemotes")
if not remotes then
    remotes = Instance.new("Folder")
    remotes.Name = "DroneRemotes"
    remotes.Parent = ReplicatedStorage
end

local function getOrMakeRemote(name)
    local r = remotes:FindFirstChild(name)
    if not r then
        r = Instance.new("RemoteEvent")
        r.Name = name
        r.Parent = remotes
    end
    return r
end

local mountRemote        = getOrMakeRemote("MountDrone")
local unmountRemote      = getOrMakeRemote("UnmountDrone")
local explodeRemote      = getOrMakeRemote("DroneExploded")
local selfDestructRemote = getOrMakeRemote("SelfDestruct")

-- ────────────────────── ПАПКА ДЛЯ ДРОНОВ ────────────────────
local dronesFolder = workspace:FindFirstChild("Drones")
if not dronesFolder then
    dronesFolder = Instance.new("Folder")
    dronesFolder.Name = "Drones"
    dronesFolder.Parent = workspace
end

-- ────────────────────── ВСПОМОГАТЕЛЬНЫЕ ────────────────────
local function weld(part0, part1)
    local w = Instance.new("WeldConstraint")
    w.Part0 = part0
    w.Part1 = part1
    w.Parent = part0
end

local function makePart(parent, name, size, cf, color, mat, canCollide, shape, transp)
    local p = Instance.new("Part")
    p.Name = name
    p.Size = size
    p.CFrame = cf
    p.BrickColor = BrickColor.new(color)
    p.Material = mat or Enum.Material.SmoothPlastic
    p.CanCollide = (canCollide == true)
    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    p.CastShadow = false
    if shape then p.Shape = shape end
    if transp then p.Transparency = transp end
    p.Parent = parent
    return p
end

-- ────────────────────── ЭФФЕКТЫ И ВЗРЫВЫ ──────────────────
local function addPropWash(part)
    local pe = Instance.new("ParticleEmitter")
    pe.Name = "Wash"
    pe.Color = ColorSequence.new(Color3.fromRGB(220, 240, 255), Color3.fromRGB(180, 210, 240))
    pe.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.5),
        NumberSequenceKeypoint.new(1, 1),
    })
    pe.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.25),
        NumberSequenceKeypoint.new(1, 1.1),
    })
    pe.Lifetime  = NumberRange.new(0.15, 0.35)
    pe.Rate      = 35
    pe.Speed     = NumberRange.new(8, 15)
    pe.EmissionDirection = Enum.NormalId.Bottom
    pe.SpreadAngle = Vector2.new(15, 15)
    pe.Enabled   = false
    pe.Parent    = part
end

local function createExplosionFX(pos)
    local exp = Instance.new("Explosion")
    exp.Position = pos
    exp.BlastRadius = Config.EXPLOSION_RADIUS
    exp.BlastPressure = Config.EXPLOSION_POWER
    exp.DestroyJointRadiusPercent = 0
    exp.Parent = workspace

    local sp = Instance.new("Part")
    sp.Size = Vector3.new(1, 1, 1)
    sp.Position = pos
    sp.Anchored = true
    sp.CanCollide = false
    sp.Transparency = 1
    sp.Parent = workspace

    local boom = Instance.new("Sound")
    boom.SoundId = Config.SOUND_EXPLOSION
    boom.Volume = 1.0
    boom.RollOffMaxDistance = 500
    boom.Parent = sp
    boom:Play()

    local peFire = Instance.new("ParticleEmitter")
    peFire.Color = ColorSequence.new({
        NumberSequenceKeypoint.new(0,   Color3.fromRGB(255, 240, 120)),
        NumberSequenceKeypoint.new(0.3, Color3.fromRGB(255, 120, 20)),
        NumberSequenceKeypoint.new(1,   Color3.fromRGB(40, 40, 40)),
    })
    peFire.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0,   2.5),
        NumberSequenceKeypoint.new(0.5, 7.0),
        NumberSequenceKeypoint.new(1,   0.5),
    })
    peFire.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0,   0),
        NumberSequenceKeypoint.new(0.8, 0.35),
        NumberSequenceKeypoint.new(1,   1),
    })
    peFire.Lifetime = NumberRange.new(0.8, 1.5)
    peFire.Speed    = NumberRange.new(30, 65)
    peFire.SpreadAngle = Vector2.new(180, 180)
    peFire.Parent = sp
    peFire:Emit(60)

    Debris:AddItem(sp, 5)
end

-- ────────────────────── СБОРКА МОДЕЛИ ДРОНА ────────────────
local droneCounter = 0

local function buildDroneAt(spawnPos)
    droneCounter = droneCounter + 1
    local model = Instance.new("Model")
    model.Name = "FPV_Drone_" .. droneCounter

    -- Атрибуты
    model:SetAttribute("IsPiloted", false)
    model:SetAttribute("PilotUserId", 0)

    local baseCF = CFrame.new(spawnPos)

    -- 1. Центральная рама (Body) — единственный тяжелый объект с коллизией
    local body = makePart(model, "Body",
        Vector3.new(2.2, 0.25, 2.2), baseCF,
        "Dark stone grey", Enum.Material.DiamondPlate, true)
    body.Anchored = true  -- ВАЖНО: на площадке стоит зафиксированным!
    model.PrimaryPart = body

    -- 2. Верхняя пластина (TopPlate)
    local topPlate = makePart(model, "TopPlate",
        Vector3.new(1.3, 0.1, 1.3), baseCF * CFrame.new(0, 0.17, 0),
        "Really black", Enum.Material.SmoothPlastic, false)
    topPlate.Massless = true
    weld(body, topPlate)

    -- 3. Аккумулятор LiPo (сверху)
    local battery = makePart(model, "LiPoBattery",
        Vector3.new(0.75, 0.45, 1.15), baseCF * CFrame.new(0, 0.42, 0.05),
        "Bright yellow", Enum.Material.SmoothPlastic, false)
    battery.Massless = true
    weld(body, battery)

    -- Ремень аккумулятора
    local strap = makePart(model, "BatteryStrap",
        Vector3.new(0.8, 0.47, 0.25), baseCF * CFrame.new(0, 0.42, 0.05),
        "Really black", Enum.Material.Fabric, false)
    strap.Massless = true
    weld(body, strap)

    -- 4. Четыре диагональных луча и моторы (X-frame)
    local armConfigs = {
        { dir = Vector3.new( 1, 0, -1), angle =  45, color = "Bright red" },
        { dir = Vector3.new(-1, 0, -1), angle = -45, color = "Bright blue" },
        { dir = Vector3.new( 1, 0,  1), angle = -45, color = "Lime green" },
        { dir = Vector3.new(-1, 0,  1), angle =  45, color = "Bright yellow" },
    }

    for i, cfg in ipairs(armConfigs) do
        local uDir = cfg.dir.Unit
        -- Луч
        local armCF = baseCF * CFrame.new(uDir * 0.9) * CFrame.Angles(0, math.rad(cfg.angle), 0)
        local arm = makePart(model, "Arm" .. i,
            Vector3.new(0.2, 0.12, 1.6), armCF,
            "Dark stone grey", Enum.Material.Metal, false)
        arm.Massless = true
        weld(body, arm)

        -- Мотор
        local mCF = baseCF * CFrame.new(uDir * 1.55) * CFrame.Angles(0, 0, math.rad(90))
        local motor = makePart(model, "Motor" .. i,
            Vector3.new(0.42, 0.25, 0.42), mCF,
            "Really black", Enum.Material.Metal, false, Enum.PartType.Cylinder)
        motor.Massless = true
        weld(body, motor)

        -- Пропеллер (полупрозрачный диск)
        local pCF = baseCF * CFrame.new(uDir * 1.55 + Vector3.new(0, 0.18, 0)) * CFrame.Angles(0, 0, math.rad(90))
        local prop = makePart(model, "Prop" .. i,
            Vector3.new(0.04, 1.5, 1.5), pCF,
            "Institutional white", Enum.Material.SmoothPlastic, false,
            Enum.PartType.Cylinder, 0.45)
        prop.Massless = true
        weld(body, prop)

        -- Колпачок мотора (цветной)
        local capCF = baseCF * CFrame.new(uDir * 1.55 + Vector3.new(0, 0.16, 0)) * CFrame.Angles(0, 0, math.rad(90))
        local cap = makePart(model, "Cap" .. i,
            Vector3.new(0.3, 0.12, 0.3), capCF,
            cfg.color, Enum.Material.SmoothPlastic, false, Enum.PartType.Cylinder)
        cap.Massless = true
        weld(body, cap)

        -- Эмиттер пропвоша
        addPropWash(motor)
    end

    -- 5. FPV Камера спереди (наклон 20 градусов)
    local camCF = baseCF * CFrame.new(0, 0.22, -1.25) * CFrame.Angles(math.rad(-Config.CAM_TILT), 0, 0)
    local camBody = makePart(model, "CamBody",
        Vector3.new(0.45, 0.35, 0.45), camCF,
        "Really black", Enum.Material.SmoothPlastic, false)
    camBody.Massless = true
    weld(body, camBody)

    -- Линза камеры (неоновая)
    local lensCF = camCF * CFrame.new(0, 0, -0.24)
    local lens = makePart(model, "CamLens",
        Vector3.new(0.24, 0.24, 0.08), lensCF,
        "Bright blue", Enum.Material.Neon, false)
    lens.Massless = true
    weld(body, lens)

    -- 6. Светодиоды
    -- Зеленые спереди
    local ledFL = makePart(model, "LED_FL",
        Vector3.new(0.12, 0.08, 0.12), baseCF * CFrame.new( 0.75, -0.05, -0.95),
        "Lime green", Enum.Material.Neon, false)
    ledFL.Massless = true
    weld(body, ledFL)

    local ledFR = makePart(model, "LED_FR",
        Vector3.new(0.12, 0.08, 0.12), baseCF * CFrame.new(-0.75, -0.05, -0.95),
        "Lime green", Enum.Material.Neon, false)
    ledFR.Massless = true
    weld(body, ledFR)

    -- Красные сзади
    local ledRL = makePart(model, "LED_RL",
        Vector3.new(0.12, 0.08, 0.12), baseCF * CFrame.new( 0.75, -0.05, 0.95),
        "Bright red", Enum.Material.Neon, false)
    ledRL.Massless = true
    weld(body, ledRL)

    local ledRR = makePart(model, "LED_RR",
        Vector3.new(0.12, 0.08, 0.12), baseCF * CFrame.new(-0.75, -0.05, 0.95),
        "Bright red", Enum.Material.Neon, false)
    ledRR.Massless = true
    weld(body, ledRR)

    -- 7. VTX Антенна сзади
    local vtxStem = makePart(model, "VTXStem",
        Vector3.new(0.06, 0.65, 0.06), baseCF * CFrame.new(0.35, 0.55, 0.75),
        "Bright orange", Enum.Material.SmoothPlastic, false)
    vtxStem.Massless = true
    weld(body, vtxStem)

    local vtxHead = makePart(model, "VTXHead",
        Vector3.new(0.16, 0.16, 0.16), baseCF * CFrame.new(0.35, 0.92, 0.75),
        "Bright orange", Enum.Material.Neon, false)
    vtxHead.Massless = true
    weld(body, vtxHead)

    -- 8. Посадочные ножки (4 шт)
    local legOffsets = {
        Vector3.new( 0.8, -0.22,  0.8),
        Vector3.new(-0.8, -0.22,  0.8),
        Vector3.new( 0.8, -0.22, -0.8),
        Vector3.new(-0.8, -0.22, -0.8),
    }
    for _, lOff in ipairs(legOffsets) do
        local leg = makePart(model, "Leg",
            Vector3.new(0.1, 0.28, 0.1), baseCF * CFrame.new(lOff),
            "Really black", Enum.Material.SmoothPlastic, false)
        leg.Massless = true
        weld(body, leg)
    end

    -- 9. Звуки
    local motorSnd = Instance.new("Sound")
    motorSnd.Name = "MotorSound"
    motorSnd.SoundId = Config.SOUND_MOTOR
    motorSnd.Looped = true
    motorSnd.Volume = 0.5
    motorSnd.PlaybackSpeed = 0.9
    motorSnd.RollOffMaxDistance = 400
    motorSnd.Parent = body

    local beepSnd = Instance.new("Sound")
    beepSnd.Name = "BeepSound"
    beepSnd.SoundId = Config.SOUND_BEEP
    beepSnd.Volume = 0.75
    beepSnd.Parent = body

    -- 10. Физика: BodyGyro (управляется пилотом)
    local gyro = Instance.new("BodyGyro")
    gyro.Name = "DroneGyro"
    gyro.MaxTorque = Vector3.new(4e5, 4e5, 4e5)
    gyro.P = 12000
    gyro.D = 900
    gyro.CFrame = baseCF
    gyro.Parent = body

    -- 11. Подсветка на площадке
    local hl = Instance.new("Highlight")
    hl.Name = "DroneHL"
    hl.FillColor = Color3.fromRGB(0, 220, 255)
    hl.FillTransparency = 0.85
    hl.OutlineColor = Color3.fromRGB(0, 240, 255)
    hl.OutlineTransparency = 0.15
    hl.Enabled = true
    hl.Parent = model

    -- 12. 3D Подсказка над дроном
    local bb = Instance.new("BillboardGui")
    bb.Name = "DroneHint"
    bb.Size = UDim2.new(0, 220, 0, 40)
    bb.StudsOffset = Vector3.new(0, 2.2, 0)
    bb.AlwaysOnTop = true
    bb.Parent = body

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 1, 0)
    lbl.BackgroundColor3 = Color3.fromRGB(15, 20, 25)
    lbl.BackgroundTransparency = 0.3
    lbl.TextColor3 = Color3.fromRGB(0, 255, 170)
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = 13
    lbl.Text = "🚁 НАЖМИ ЧТОБЫ ВЗЯТЬ ДРОН"
    lbl.Parent = bb
    Instance.new("UICorner", lbl).CornerRadius = UDim.new(0, 8)

    -- 13. Клик-детектор
    local click = Instance.new("ClickDetector")
    click.Name = "DroneClick"
    click.MaxActivationDistance = 25
    click.Parent = body

    -- Обработка клика
    click.MouseClick:Connect(function(player)
        if model:GetAttribute("IsPiloted") == true then return end

        model:SetAttribute("IsPiloted", true)
        model:SetAttribute("PilotUserId", player.UserId)

        -- Скрываем подсказки и подсветку
        hl.Enabled = false
        bb.Enabled = false

        -- Разрешаем физику
        body.Anchored = false
        pcall(function()
            body:SetNetworkOwner(player)
        end)

        beepSnd:Play()

        -- Отправляем клиенту команду занять дрон
        mountRemote:FireClient(player, model)
        print(string.format("[DroneServer] Игрок %s взял дрон %s", player.Name, model.Name))
    end)

    model.Parent = dronesFolder
    return model
end

-- ────────────────────── УНИЧТОЖЕНИЕ ДРОНА ──────────────────
local function destroyDrone(drone, pos)
    if not drone or not drone.Parent then return end
    local pPos = pos or (drone.PrimaryPart and drone.PrimaryPart.Position) or Config.DRONE_SPAWN
    createExplosionFX(pPos)
    pcall(function()
        drone:Destroy()
    end)
end

-- ────────────────────── REMOTE HANDLERS ────────────────────

-- Ручная детонация (💥 ПОДРЫВ)
selfDestructRemote.OnServerEvent:Connect(function(player, clientDrone)
    local targetDrone = clientDrone
    if not targetDrone or not targetDrone.Parent then
        -- Ищем дрон этого игрока
        for _, d in ipairs(dronesFolder:GetChildren()) do
            if d:GetAttribute("PilotUserId") == player.UserId then
                targetDrone = d
                break
            end
        end
    end

    if targetDrone and targetDrone:GetAttribute("PilotUserId") == player.UserId then
        local pos = targetDrone.PrimaryPart and targetDrone.PrimaryPart.Position
        destroyDrone(targetDrone, pos)
    end
end)

-- Взрыв при столкновении на скорости
explodeRemote.OnServerEvent:Connect(function(player, clientDrone, pos)
    if clientDrone and clientDrone.Parent and clientDrone:GetAttribute("PilotUserId") == player.UserId then
        destroyDrone(clientDrone, pos)
    end
end)

-- Выход из дрона
unmountRemote.OnServerEvent:Connect(function(player, clientDrone)
    if clientDrone and clientDrone.Parent and clientDrone:GetAttribute("PilotUserId") == player.UserId then
        -- Если игрок вышел, уничтожаем дрон через 4 секунды если никто не взял
        clientDrone:SetAttribute("IsPiloted", false)
        clientDrone:SetAttribute("PilotUserId", 0)
        pcall(function()
            clientDrone.PrimaryPart:SetNetworkOwnershipAuto()
        end)
        task.delay(4, function()
            if clientDrone and clientDrone.Parent and clientDrone:GetAttribute("IsPiloted") == false then
                destroyDrone(clientDrone)
            end
        end)
    end
end)

-- Игрок вышел из игры
Players.PlayerRemoving:Connect(function(player)
    for _, d in ipairs(dronesFolder:GetChildren()) do
        if d:GetAttribute("PilotUserId") == player.UserId then
            destroyDrone(d)
        end
    end
end)

-- ────────────────────── АВТОСПАВНЕР (КАЖДЫЕ 3 СЕК) ──────────
-- Проверяет, есть ли на посадочной площадке свободный (непилотируемый) дрон.
-- Если нет — спавнит новый! Друзья могут брать каждый по дрону!
task.spawn(function()
    while true do
        local padFree = true
        for _, d in ipairs(dronesFolder:GetChildren()) do
            if d:IsA("Model") and d.PrimaryPart then
                local dist = (d.PrimaryPart.Position - Config.DRONE_SPAWN).Magnitude
                if dist < 6 and d:GetAttribute("IsPiloted") == false then
                    padFree = false
                    break
                end
            end
        end

        if padFree then
            buildDroneAt(Config.DRONE_SPAWN)
            print("[DroneServer] Заспавнен новый дрон на площадке")
        end

        task.wait(Config.RESPAWN_INTERVAL)
    end
end)

-- ────────────────────── WATCHDOG ГРАНИЦ ────────────────────
RunService.Heartbeat:Connect(function()
    for _, d in ipairs(dronesFolder:GetChildren()) do
        if d:IsA("Model") and d.PrimaryPart and d:GetAttribute("IsPiloted") == true then
            local pos = d.PrimaryPart.Position
            local hDist = Vector2.new(pos.X, pos.Z).Magnitude
            if hDist > (Config.BOUNDS_RADIUS + 30)
                or pos.Y < Config.BOUNDS_MIN_Y
                or pos.Y > (Config.BOUNDS_MAX_Y + 40)
            then
                destroyDrone(d, pos)
            end
        end
    end
end)

print("[DroneServer] Сервер дронов v5 запущен!")
