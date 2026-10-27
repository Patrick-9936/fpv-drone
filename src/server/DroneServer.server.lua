--[[
    DroneServer v7
    - ИСПРАВЛЕН ВЗЯТИЕ ДРОНА: большой невидимый Hitbox (4.5x2.5x4.5) с ClickDetector и ProximityPrompt
      Теперь дрон берётся мгновенно с любого клика или нажатия на телефоне/ПК!
    - ИСПРАВЛЕН САМОВОЛЬНЫЙ ВЗРЫВ: убран сырой Touched на сервере, взрыв безопасен для пилота
      (BlastRadius = 0, не убивает стоящего рядом игрока)
    - Автоспавн каждые 3 секунды: если дрон взят, на площадке сразу появляется новый!
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

-- ────────────────────── ПАПКА ДРОНОВ ────────────────────────
local dronesFolder = workspace:FindFirstChild("Drones")
if not dronesFolder then
    dronesFolder = Instance.new("Folder")
    dronesFolder.Name = "Drones"
    dronesFolder.Parent = workspace
end

local playerDrones = {}

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

-- ────────────────────── ВЗРЫВ (БЕЗОПАСНЫЙ ДЛЯ ПИЛОТА) ───────
local function createExplosionFX(pos)
    -- BlastRadius = 0 и BlastPressure = 0 гарантируют, что взрыв
    -- воспроизводит громкий звук и вспышку, но НЕ убивает стоящего на земле игрока!
    local exp = Instance.new("Explosion")
    exp.Position = pos
    exp.BlastRadius = 0
    exp.BlastPressure = 0
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

local function destroyDrone(drone, pos)
    if not drone then return end

    local explodePos = pos
    if not explodePos and drone.PrimaryPart then
        explodePos = drone.PrimaryPart.Position
    end
    explodePos = explodePos or Config.DRONE_SPAWN

    createExplosionFX(explodePos)

    for plr, d in pairs(playerDrones) do
        if d == drone then
            playerDrones[plr] = nil
        end
    end

    pcall(function()
        drone:Destroy()
    end)
end

-- ────────────────────── СБОРКА МОДЕЛИ ДРОНА ────────────────
local droneCounter = 0

local function buildDroneAt(spawnPos)
    droneCounter = droneCounter + 1
    local model = Instance.new("Model")
    model.Name = "FPV_Drone_" .. droneCounter

    model:SetAttribute("IsPiloted", false)
    model:SetAttribute("PilotUserId", 0)

    local baseCF = CFrame.new(spawnPos)

    -- 1. Центральная рама (Body)
    local body = makePart(model, "Body",
        Vector3.new(2.2, 0.25, 2.2), baseCF,
        "Dark stone grey", Enum.Material.DiamondPlate, true)
    body.Anchored = true  -- надежно стоит на площадке
    model.PrimaryPart = body

    -- 2. Верхняя пластина
    local topPlate = makePart(model, "TopPlate",
        Vector3.new(1.3, 0.1, 1.3), baseCF * CFrame.new(0, 0.17, 0),
        "Really black", Enum.Material.SmoothPlastic, false)
    topPlate.Massless = true
    weld(body, topPlate)

    -- 3. Аккумулятор
    local battery = makePart(model, "LiPoBattery",
        Vector3.new(0.75, 0.45, 1.15), baseCF * CFrame.new(0, 0.42, 0.05),
        "Bright yellow", Enum.Material.SmoothPlastic, false)
    battery.Massless = true
    weld(body, battery)

    -- 4. 4 диагональных луча и моторы (X-frame)
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

        -- Пропеллер
        local pCF = baseCF * CFrame.new(uDir * 1.55 + Vector3.new(0, 0.18, 0)) * CFrame.Angles(0, 0, math.rad(90))
        local prop = makePart(model, "Prop" .. i,
            Vector3.new(0.04, 1.5, 1.5), pCF,
            "Institutional white", Enum.Material.SmoothPlastic, false,
            Enum.PartType.Cylinder, 0.45)
        prop.Massless = true
        weld(body, prop)

        -- Колпачок
        local capCF = baseCF * CFrame.new(uDir * 1.55 + Vector3.new(0, 0.16, 0)) * CFrame.Angles(0, 0, math.rad(90))
        local cap = makePart(model, "Cap" .. i,
            Vector3.new(0.3, 0.12, 0.3), capCF,
            cfg.color, Enum.Material.SmoothPlastic, false, Enum.PartType.Cylinder)
        cap.Massless = true
        weld(body, cap)

        -- Пропвош
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
        pe.Parent    = motor
    end

    -- 5. Камера
    local camCF = baseCF * CFrame.new(0, 0.22, -1.25) * CFrame.Angles(math.rad(-Config.CAM_TILT), 0, 0)
    local camBody = makePart(model, "CamBody",
        Vector3.new(0.45, 0.35, 0.45), camCF,
        "Really black", Enum.Material.SmoothPlastic, false)
    camBody.Massless = true
    weld(body, camBody)

    local lens = makePart(model, "CamLens",
        Vector3.new(0.24, 0.24, 0.08), camCF * CFrame.new(0, 0, -0.24),
        "Bright blue", Enum.Material.Neon, false)
    lens.Massless = true
    weld(body, lens)

    -- 6. Огни
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

    -- 7. Ножки
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

    -- 8. Звуки
    local motorSnd = Instance.new("Sound")
    motorSnd.Name = "MotorSound"
    motorSnd.SoundId = Config.SOUND_MOTOR
    motorSnd.Looped = true
    motorSnd.Volume = 0.5
    motorSnd.PlaybackSpeed = 0.95
    motorSnd.RollOffMaxDistance = 400
    motorSnd.Parent = body

    local beepSnd = Instance.new("Sound")
    beepSnd.Name = "BeepSound"
    beepSnd.SoundId = Config.SOUND_BEEP
    beepSnd.Volume = 0.75
    beepSnd.Parent = body

    -- 9. BodyGyro
    local gyro = Instance.new("BodyGyro")
    gyro.Name = "DroneGyro"
    gyro.MaxTorque = Vector3.new(4e5, 4e5, 4e5)
    gyro.P = 12000
    gyro.D = 900
    gyro.CFrame = baseCF
    gyro.Parent = body

    -- 10. Подсветка
    local hl = Instance.new("Highlight")
    hl.Name = "DroneHL"
    hl.FillColor = Color3.fromRGB(0, 220, 255)
    hl.FillTransparency = 0.85
    hl.OutlineColor = Color3.fromRGB(0, 240, 255)
    hl.OutlineTransparency = 0.15
    hl.Enabled = true
    hl.Parent = model

    -- 11. ФУНКЦИЯ ЗАХВАТА ДРОНА (Мгновенно)
    local function claimDrone(player)
        if model:GetAttribute("IsPiloted") == true then return end
        model:SetAttribute("IsPiloted", true)
        model:SetAttribute("PilotUserId", player.UserId)

        if playerDrones[player] and playerDrones[player] ~= model then
            destroyDrone(playerDrones[player])
        end
        playerDrones[player] = model

        hl.Enabled = false

        -- Отключаем клики и промпты
        local hb = model:FindFirstChild("Hitbox")
        if hb then
            local p = hb:FindFirstChildOfClass("ProximityPrompt")
            if p then p.Enabled = false end
            local c = hb:FindFirstChildOfClass("ClickDetector")
            if c then c.MaxActivationDistance = 0 end
        end

        -- Включаем физику и передаем Network Ownership клиенту
        body.Anchored = false
        pcall(function()
            body:SetNetworkOwner(player)
        end)

        beepSnd:Play()

        -- Уведомляем клиента
        mountRemote:FireClient(player, model)
        print(string.format("[DroneServer] %s мгновенно взял дрон %s", player.Name, model.Name))
    end

    -- 12. БОЛЬШОЙ НЕВИДИМЫЙ HITBOX ДЛЯ 100% УДОБНОГО ВЗЯТИЯ
    -- Охватывает весь дрон (4.5 x 2.5 x 4.5 studs)
    local hitbox = makePart(model, "Hitbox",
        Vector3.new(4.5, 2.5, 4.5), baseCF * CFrame.new(0, 0.5, 0),
        "Really black", Enum.Material.SmoothPlastic, false, nil, 1)
    hitbox.Massless = true
    hitbox.CanQuery = true
    hitbox.CanTouch = true
    weld(body, hitbox)

    -- ClickDetector на Hitbox (нажимается в ЛЮБУЮ точку дрона!)
    local click = Instance.new("ClickDetector")
    click.Name = "DroneClick"
    click.MaxActivationDistance = 35
    click.Parent = hitbox
    click.MouseClick:Connect(claimDrone)

    -- ClickDetector на Body (дополнительно)
    local bodyClick = Instance.new("ClickDetector")
    bodyClick.Name = "BodyClick"
    bodyClick.MaxActivationDistance = 35
    bodyClick.Parent = body
    bodyClick.MouseClick:Connect(claimDrone)

    -- Мгновенный ProximityPrompt (0 сек удержания)
    local prompt = Instance.new("ProximityPrompt")
    prompt.ActionText = "Взлететь"
    prompt.ObjectText = "FPV Дрон"
    prompt.HoldDuration = 0
    prompt.MaxActivationDistance = 18
    prompt.KeyboardKeyCode = Enum.KeyCode.E
    prompt.RequiresLineOfSight = false
    prompt.Parent = hitbox
    prompt.Triggered:Connect(claimDrone)

    model.Parent = dronesFolder
    return model
end

-- ────────────────────── REMOTE HANDLERS ────────────────────

-- 💥 РУЧНАЯ ДЕТОНАЦИЯ
selfDestructRemote.OnServerEvent:Connect(function(player, clientDrone)
    local target = playerDrones[player] or clientDrone
    if target and target.Parent then
        destroyDrone(target)
    end
end)

-- ВЗРЫВ ПРИ СТОЛКНОВЕНИИ
explodeRemote.OnServerEvent:Connect(function(player, clientDrone, pos)
    local target = playerDrones[player] or clientDrone
    if target and target.Parent then
        destroyDrone(target, pos)
    end
end)

-- ВЫХОД ИЗ ДРОНА
unmountRemote.OnServerEvent:Connect(function(player, clientDrone)
    local target = playerDrones[player] or clientDrone
    playerDrones[player] = nil
    if target and target.Parent then
        target:SetAttribute("IsPiloted", false)
        target:SetAttribute("PilotUserId", 0)
        pcall(function()
            target.PrimaryPart:SetNetworkOwnershipAuto()
        end)
        task.delay(3, function()
            if target and target.Parent and target:GetAttribute("IsPiloted") == false then
                destroyDrone(target)
            end
        end)
    end
end)

-- ИГРОК ВЫШЕЛ
Players.PlayerRemoving:Connect(function(player)
    local target = playerDrones[player]
    playerDrones[player] = nil
    if target and target.Parent then
        destroyDrone(target)
    end
end)

-- ────────────────────── АВТОСПАВНЕР (КАЖДЫЕ 3 СЕК) ──────────
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
            print("[DroneServer] Новый дрон готов на площадке")
        end

        task.wait(Config.RESPAWN_INTERVAL)
    end
end)

-- ────────────────────── WATCHDOG ГРАНИЦ КАРТЫ ──────────────
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

print("[DroneServer] Сервер дронов v7 активен!")
