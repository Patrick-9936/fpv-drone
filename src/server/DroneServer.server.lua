--[[
    DroneServer v4
    - Детальная модель квадрокоптера (рама X, 4 мотора, камера GoPro, антенна)
    - Физика: VectorForce (тяга) + BodyGyro (ориентация) — NO BodyVelocity
    - Авто-спавн: новый дрон появляется каждые 3 сек после взрыва
    - Сервер-Heartbeat следит за выходом за карту
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
local droneReadyRemote   = getOrMakeRemote("DroneReady")

-- ────────────────────── СОСТОЯНИЕ ──────────────────────────
local currentPilot = nil
local droneModel   = nil
local isRespawning = false

-- ────────────────────── ВСПОМОГАТЕЛЬНЫЕ ────────────────────
local function weld(part0, part1)
    local w = Instance.new("WeldConstraint")
    w.Part0 = part0
    w.Part1 = part1
    w.Parent = part0
end

-- Создаём Part относительно DRONE_SPAWN
local SPAWN = Config.DRONE_SPAWN
local function makePart(parent, name, size, localOffset, color, mat, canCollide, shape, transp)
    local p = Instance.new("Part")
    p.Name = name
    p.Size = size
    p.CFrame = CFrame.new(SPAWN + localOffset)
    p.BrickColor = BrickColor.new(color)
    p.Material = mat or Enum.Material.SmoothPlastic
    p.CanCollide = (canCollide == true)
    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    if shape then p.Shape = shape end
    if transp then p.Transparency = transp end
    p.CastShadow = false
    p.Parent = parent
    return p
end

local function makeNeon(parent, name, size, localOffset, color)
    local p = makePart(parent, name, size, localOffset, color, Enum.Material.Neon, false)
    return p
end

-- ────────────────────── ЭФФЕКТЫ ────────────────────────────
local function addPropWash(part)
    local pe = Instance.new("ParticleEmitter")
    pe.Name = "Wash"
    pe.Color = ColorSequence.new(Color3.fromRGB(200,235,255), Color3.fromRGB(180,220,255))
    pe.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.6),
        NumberSequenceKeypoint.new(1, 1),
    })
    pe.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.25),
        NumberSequenceKeypoint.new(1, 1.0),
    })
    pe.Lifetime  = NumberRange.new(0.15, 0.3)
    pe.Rate      = 30
    pe.Speed     = NumberRange.new(6, 12)
    pe.EmissionDirection = Enum.NormalId.Bottom
    pe.SpreadAngle = Vector2.new(20, 20)
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
    sp.Size = Vector3.new(1,1,1)
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
        NumberSequenceKeypoint.new(0,   Color3.fromRGB(255,230,100)),
        NumberSequenceKeypoint.new(0.4, Color3.fromRGB(255,100,20)),
        NumberSequenceKeypoint.new(1,   Color3.fromRGB(50,50,50)),
    })
    peFire.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0,   2),
        NumberSequenceKeypoint.new(0.5, 6),
        NumberSequenceKeypoint.new(1,   0.5),
    })
    peFire.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0,   0),
        NumberSequenceKeypoint.new(0.8, 0.3),
        NumberSequenceKeypoint.new(1,   1),
    })
    peFire.Lifetime = NumberRange.new(0.8, 1.4)
    peFire.Speed    = NumberRange.new(25, 60)
    peFire.SpreadAngle = Vector2.new(180, 180)
    peFire.Parent = sp
    peFire:Emit(60)

    Debris:AddItem(sp, 5)
end

-- ────────────────────── ПОСТРОЙКА ДРОНА ────────────────────
--[[
    Модель: Racing FPV Quad (X-frame)
    Рама ~20cm, 4 мотора по углам, камера спереди под углом,
    LED-огни, антенна VTX, крышка FC, резиновые заглушки
]]
local function buildDrone()
    local model = Instance.new("Model")
    model.Name  = "FPV_Drone"

    -- ── ЦЕНТРАЛЬНАЯ РАМА (carbon fiber look) ──
    -- Горизонтальные пластины
    local body = makePart(model, "Body",
        Vector3.new(1.8, 0.12, 1.8), Vector3.new(0,0,0),
        "Dark stone grey", Enum.Material.Metal, true)
    model.PrimaryPart = body

    -- Верхняя накладка FC / ESC
    local topPlate = makePart(model, "TopPlate",
        Vector3.new(1.1, 0.08, 1.1), Vector3.new(0, 0.1, 0),
        "Really black", Enum.Material.SmoothPlastic, false)
    weld(body, topPlate)

    -- Стек FC (коробочка электроники)
    local fcStack = makePart(model, "FCStack",
        Vector3.new(0.65, 0.28, 0.65), Vector3.new(0, 0.24, 0),
        "Medium stone grey", Enum.Material.SmoothPlastic, false)
    weld(body, fcStack)

    -- ── ARMS (4 луча X-frame) ──
    -- Луч: диагональный, в углы по 45°
    local armDefs = {
        { dir = Vector3.new( 1, 0, -1), angle =  45 },
        { dir = Vector3.new(-1, 0, -1), angle = -45 },
        { dir = Vector3.new( 1, 0,  1), angle = -45 },
        { dir = Vector3.new(-1, 0,  1), angle =  45 },
    }

    for i, a in ipairs(armDefs) do
        local armMid = a.dir.Unit * 0.75
        local arm = makePart(model, "Arm"..i,
            Vector3.new(0.18, 0.09, 1.45), armMid,
            "Dark stone grey", Enum.Material.Metal, false)
        arm.CFrame = CFrame.new(SPAWN + armMid) * CFrame.Angles(0, math.rad(a.angle), 0)
        weld(body, arm)

        -- Мотор (чёрный цилиндр)
        local motorPos = a.dir.Unit * 1.32
        local motor = makePart(model, "Motor"..i,
            Vector3.new(0.38, 0.22, 0.38), motorPos,
            "Really black", Enum.Material.Metal, false, Enum.PartType.Cylinder)
        motor.CFrame = CFrame.new(SPAWN + motorPos) * CFrame.Angles(0, 0, math.rad(90))
        weld(body, motor)

        -- Пропеллер (прозрачный диск)
        local propPos = a.dir.Unit * 1.32 + Vector3.new(0, 0.15, 0)
        local prop = makePart(model, "Prop"..i,
            Vector3.new(0.04, 1.3, 1.3), propPos,
            "Institutional white", Enum.Material.SmoothPlastic, false,
            Enum.PartType.Cylinder, 0.45)
        prop.CFrame = CFrame.new(SPAWN + propPos) * CFrame.Angles(0, 0, math.rad(90))
        weld(body, prop)

        -- Колпачок мотора (цветной акцент)
        local capColors = {"Bright red","Bright blue","Lime green","Bright yellow"}
        local cap = makePart(model, "MotorCap"..i,
            Vector3.new(0.28, 0.10, 0.28),
            a.dir.Unit * 1.32 + Vector3.new(0, 0.13, 0),
            capColors[i], Enum.Material.SmoothPlastic, false, Enum.PartType.Cylinder)
        cap.CFrame = CFrame.new(SPAWN + a.dir.Unit*1.32 + Vector3.new(0,0.13,0))
            * CFrame.Angles(0, 0, math.rad(90))
        weld(body, cap)

        -- Пропвош эмиттер под мотором
        addPropWash(motor)
    end

    -- ── КАМЕРА (GoPro-mount style) ──
    -- Крепёж камеры
    local camMount = makePart(model, "CamMount",
        Vector3.new(0.5, 0.35, 0.12), Vector3.new(0, 0.05, -1.05),
        "Really black", Enum.Material.SmoothPlastic, false)
    weld(body, camMount)

    -- Корпус камеры (чуть наклонён вперёд-вверх)
    local camBody = makePart(model, "CamBody",
        Vector3.new(0.42, 0.34, 0.42), Vector3.new(0, 0.16, -1.2),
        "Really black", Enum.Material.SmoothPlastic, false)
    camBody.CFrame = CFrame.new(SPAWN + Vector3.new(0, 0.16, -1.2))
        * CFrame.Angles(math.rad(-25), 0, 0)
    weld(body, camBody)

    -- Линза (Neon синяя — индикатор камеры)
    local lens = makeNeon(model, "Lens",
        Vector3.new(0.22, 0.22, 0.12), Vector3.new(0, 0.16, -1.43),
        "Bright blue")
    lens.CFrame = CFrame.new(SPAWN + Vector3.new(0, 0.16, -1.43))
        * CFrame.Angles(math.rad(-25), 0, 0)
    weld(body, lens)

    -- ── LED ОГНИ ──
    -- Передние (зелёные)
    local ledFL = makeNeon(model, "LED_FL",
        Vector3.new(0.12, 0.08, 0.12), Vector3.new( 0.6, -0.05, -0.85),
        "Lime green")
    weld(body, ledFL)
    local ledFR = makeNeon(model, "LED_FR",
        Vector3.new(0.12, 0.08, 0.12), Vector3.new(-0.6, -0.05, -0.85),
        "Lime green")
    weld(body, ledFR)

    -- Задние (красные)
    local ledRL = makeNeon(model, "LED_RL",
        Vector3.new(0.12, 0.08, 0.12), Vector3.new( 0.6, -0.05,  0.85),
        "Bright red")
    weld(body, ledRL)
    local ledRR = makeNeon(model, "LED_RR",
        Vector3.new(0.12, 0.08, 0.12), Vector3.new(-0.6, -0.05,  0.85),
        "Bright red")
    weld(body, ledRR)

    -- ── VTX АНТЕННА ──
    local vtxBase = makePart(model, "VTXBase",
        Vector3.new(0.10, 0.10, 0.10), Vector3.new(0.3, 0.55, 0.5),
        "Really black", Enum.Material.SmoothPlastic, false)
    weld(body, vtxBase)

    local vtxAnt = makePart(model, "VTXAnt",
        Vector3.new(0.05, 0.55, 0.05), Vector3.new(0.3, 1.0, 0.5),
        "Bright orange", Enum.Material.SmoothPlastic, false)
    weld(body, vtxAnt)

    local vtxTip = makeNeon(model, "VTXTip",
        Vector3.new(0.09, 0.09, 0.09), Vector3.new(0.3, 1.30, 0.5),
        "Bright orange")
    weld(body, vtxTip)

    -- ── ПОСАДОЧНЫЕ НОГИ (4 штуки) ──
    local legOffsets = {
        Vector3.new( 0.7, -0.2,  0.7),
        Vector3.new(-0.7, -0.2,  0.7),
        Vector3.new( 0.7, -0.2, -0.7),
        Vector3.new(-0.7, -0.2, -0.7),
    }
    for _, lo in ipairs(legOffsets) do
        local leg = makePart(model, "Leg",
            Vector3.new(0.08, 0.25, 0.08), lo,
            "Really black", Enum.Material.SmoothPlastic, false)
        weld(body, leg)
    end

    -- ── ЗВУК МОТОРА ──
    local motorSnd = Instance.new("Sound")
    motorSnd.Name = "MotorSound"
    motorSnd.SoundId = Config.SOUND_MOTOR
    motorSnd.Looped  = true
    motorSnd.Volume  = 0.5
    motorSnd.PlaybackSpeed = 0.9
    motorSnd.RollOffMaxDistance = 350
    motorSnd.Parent = body

    local beepSnd = Instance.new("Sound")
    beepSnd.Name = "BeepSound"
    beepSnd.SoundId = Config.SOUND_BEEP
    beepSnd.Volume  = 0.7
    beepSnd.Parent  = body

    -- ── ФИЗИКА ──

    -- BodyGyro — контролирует ориентацию
    local gyro = Instance.new("BodyGyro")
    gyro.Name = "DroneGyro"
    gyro.MaxTorque = Vector3.new(5e5, 5e5, 5e5)
    gyro.P = 15000
    gyro.D = 1200
    gyro.CFrame = CFrame.new()
    gyro.Parent = body

    -- Attachment для VectorForce (направлен строго вверх в локальных координатах)
    local att = Instance.new("Attachment")
    att.Name = "ThrustAttach"
    -- Не поворачиваем attachment — VectorForce будет в мировом пространстве
    att.CFrame = CFrame.new(0, 0, 0)
    att.Parent = body

    -- VectorForce — тяга (заменяет BodyVelocity)
    -- RelativeTo = World — сила всегда вверх в мировых координатах
    local vf = Instance.new("VectorForce")
    vf.Name = "Thrust"
    vf.Attachment0 = att
    vf.ApplyAtCenterOfMass = true
    vf.RelativeTo = Enum.ActuatorRelativeTo.World
    vf.Force = Vector3.new(0, 0, 0)
    vf.Parent = body

    -- ── ИНТЕРАКТИВНОСТЬ ──
    local click = Instance.new("ClickDetector")
    click.Name = "DroneClick"
    click.MaxActivationDistance = 30
    click.Parent = body

    -- Подсветка при наведении
    local hl = Instance.new("Highlight")
    hl.Name = "DroneHL"
    hl.FillColor = Color3.fromRGB(0,200,255)
    hl.FillTransparency = 0.85
    hl.OutlineColor = Color3.fromRGB(0,220,255)
    hl.OutlineTransparency = 0.2
    hl.Enabled = true
    hl.Parent = model

    -- Billboard подсказка
    local billboard = Instance.new("BillboardGui")
    billboard.Name  = "ClickHint"
    billboard.Size  = UDim2.new(0, 180, 0, 36)
    billboard.StudsOffset = Vector3.new(0, 2.5, 0)
    billboard.AlwaysOnTop = false
    billboard.Parent = body
    local hintLabel = Instance.new("TextLabel")
    hintLabel.Size = UDim2.new(1,0,1,0)
    hintLabel.BackgroundColor3 = Color3.fromRGB(0,0,0)
    hintLabel.BackgroundTransparency = 0.5
    hintLabel.TextColor3 = Color3.fromRGB(0,255,150)
    hintLabel.Font = Enum.Font.GothamBold
    hintLabel.TextSize = 14
    hintLabel.Text = "🚁 Нажми чтобы пилотировать"
    hintLabel.Parent = billboard
    Instance.new("UICorner", hintLabel).CornerRadius = UDim.new(0, 6)

    model.Parent = workspace
    return model
end

-- ────────────────────── СПАВН / РЕСТАРТ ───────────────────
local function spawnDrone()
    if isRespawning then return end

    -- Удалить старый дрон если есть
    if droneModel then
        pcall(function() droneModel:Destroy() end)
        droneModel = nil
    end

    currentPilot = nil
    droneModel   = buildDrone()
    local body   = droneModel.PrimaryPart

    -- Если модель уничтожена снаружи — авто-рестарт
    droneModel.Destroying:Connect(function()
        if not isRespawning then
            isRespawning = true
            currentPilot = nil
            task.delay(Config.RESPAWN_TIME, function()
                isRespawning = false
                spawnDrone()
            end)
        end
    end)

    -- Клик для посадки
    body.DroneClick.MouseClick:Connect(function(plr)
        if currentPilot ~= nil then return end
        currentPilot = plr

        pcall(function() body:SetNetworkOwner(plr) end)

        -- Скрыть подсказку и подсветку
        local hint = body:FindFirstChild("ClickHint")
        if hint then hint.Enabled = false end
        if droneModel:FindFirstChild("DroneHL") then
            droneModel.DroneHL.Enabled = false
        end

        local beep = body:FindFirstChild("BeepSound")
        if beep then beep:Play() end

        mountRemote:FireClient(plr, droneModel)
    end)

    droneReadyRemote:FireAllClients()
    print("[DroneServer] Дрон готов на площадке")
end

local function triggerExplosion(pos)
    if isRespawning then return end
    isRespawning = true
    currentPilot = nil

    if pos and typeof(pos) == "Vector3" then
        createExplosionFX(pos)
    end

    if droneModel then
        pcall(function() droneModel:Destroy() end)
        droneModel = nil
    end

    task.delay(Config.RESPAWN_TIME, function()
        isRespawning = false
        spawnDrone()
    end)
end

-- ────────────────────── REMOTE HANDLERS ────────────────────
unmountRemote.OnServerEvent:Connect(function(plr)
    if plr ~= currentPilot then return end
    currentPilot = nil
    if droneModel and droneModel.PrimaryPart then
        pcall(function() droneModel.PrimaryPart:SetNetworkOwnershipAuto() end)
        if droneModel:FindFirstChild("DroneHL") then
            droneModel.DroneHL.Enabled = true
        end
        -- Показать подсказку снова
        local hint = droneModel.PrimaryPart:FindFirstChild("ClickHint")
        if hint then hint.Enabled = true end
        local ms = droneModel.PrimaryPart:FindFirstChild("MotorSound")
        if ms then ms:Stop() end
    end
end)

explodeRemote.OnServerEvent:Connect(function(plr, pos)
    if plr ~= currentPilot then return end
    triggerExplosion(pos)
end)

selfDestructRemote.OnServerEvent:Connect(function(plr)
    if plr ~= currentPilot then return end
    local pos = (droneModel and droneModel.PrimaryPart)
        and droneModel.PrimaryPart.Position
        or Config.DRONE_SPAWN
    triggerExplosion(pos)
end)

Players.PlayerRemoving:Connect(function(plr)
    if plr ~= currentPilot then return end
    currentPilot = nil
    if droneModel and droneModel.PrimaryPart then
        pcall(function() droneModel.PrimaryPart:SetNetworkOwnershipAuto() end)
    end
end)

-- ────────────────────── WATCHDOG (сервер) ──────────────────
RunService.Heartbeat:Connect(function()
    if droneModel and droneModel.PrimaryPart and not isRespawning then
        local pos = droneModel.PrimaryPart.Position
        local h   = Vector2.new(pos.X, pos.Z).Magnitude
        if h > (Config.BOUNDS_RADIUS + 30)
            or pos.Y < Config.BOUNDS_MIN_Y
            or pos.Y > (Config.BOUNDS_MAX_Y + 40)
        then
            triggerExplosion(pos)
        end
    end
end)

-- ────────────────────── СТАРТ ──────────────────────────────
spawnDrone()
