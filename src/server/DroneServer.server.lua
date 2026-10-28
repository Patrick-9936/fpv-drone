--[[
    DroneServer v10 — серверная (детерминированная) модель полёта.

    Почему переписано:
      * В v8 полёт держался на «перезаписи скорости» клиентом: AssemblyLinearVelocity
        каждый кадр тянулся к цели лишь на ~11%, а гравитация снимала ~3.3 стад/с каждый
        кадр. Дрон физически не мог выйти на заданную вертикальную скорость — отсюда
        «не взлетает», «зависает на месте», «падает при наклоне».
      * Дрон разанкоривался при взятии и отдавался в network ownership клиенту. Двое
        дронов, оказавшихся в одной точке (спавнер плодил их на площадке), физически
        расталкивали друг друга на огромной скорости — и «второй дрон взрывался сразу».
      * Хитбоксы взорванных/занятых дронов оставались в мире и перехватывали клики —
        из-за этого казалось, что «новые дроны не берутся».

    Теперь:
      * Дрон всегда Anchored. Движением управляет сервер через FlightModel (чистая
        математика), клиент только присылает стики. Никакой борьбы с гравитацией.
      * Коллизии считаются лучами: о землю дрон садится и скользит (никогда не взрывается),
        взрыв — только лобовой удар о стену на скорости > CRASH_SPEED или кнопка «ПОДРЫВ».
      * Дроны не сталкиваются друг с другом вообще (они исключены из лучей), поэтому
        наложение моделей больше не может ничего взорвать.
      * Взял дрон — хитбокс сразу перестаёт ловить клики. Взорвался/вышел — модель
        удаляется целиком, в мире не остаётся «мёртвых» хитбоксов.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local Debris            = game:GetService("Debris")

local Config      = require(ReplicatedStorage:WaitForChild("DroneConfig"))
local FlightModel = require(ReplicatedStorage:WaitForChild("FlightModel"))

-- ────────────────────── REMOTE EVENTS ──────────────────────
local remotes = ReplicatedStorage:FindFirstChild("DroneRemotes")
if not remotes then
    remotes = Instance.new("Folder")
    remotes.Name = "DroneRemotes"
    remotes.Parent = ReplicatedStorage
end

local function getOrMakeRemote(name, className)
    local r = remotes:FindFirstChild(name)
    if not r then
        r = Instance.new(className or "RemoteEvent")
        r.Name = name
        r.Parent = remotes
    end
    return r
end

local mountRemote    = getOrMakeRemote("MountDrone")     -- server -> client
local lostRemote     = getOrMakeRemote("DroneLost")      -- server -> client
local inputRemote    = getOrMakeRemote("DroneInput")     -- client -> server
local unmountRemote  = getOrMakeRemote("UnmountDrone")   -- client -> server
local selfDestructRemote = getOrMakeRemote("SelfDestruct") -- client -> server

-- ────────────────────── СОСТОЯНИЕ ──────────────────────────
local dronesFolder = workspace:FindFirstChild("Drones")
if not dronesFolder then
    dronesFolder = Instance.new("Folder")
    dronesFolder.Name = "Drones"
    dronesFolder.Parent = workspace
end

local drones       = {}   -- [model] = rec
local playerDrones = {}   -- [player] = rec

-- Стики в центре (брошенный стик): газ чуть ниже точки висения → дрон проседает
local NEUTRAL_INPUT = { pitch = 0, roll = 0, yaw = 0, throttle = 0.5 }
-- Ввод пропал совсем (связь, свёрнутое приложение): газ убран, дрон падает
local STALE_INPUT   = { pitch = 0, roll = 0, yaw = 0, throttle = 0 }

local claimDrone   -- forward declaration (используется в ClickDetector/ProximityPrompt)

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

local function buildFilter()
    local list = { dronesFolder }
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr.Character then
            table.insert(list, plr.Character)
        end
    end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = list
    params.IgnoreWater = true
    return params
end

-- ────────────────────── ВЗРЫВ (ЛЁГКИЙ, БЕЗ ПРОВАЛОВ FPS) ──
-- Раньше здесь создавался Instance.new("Explosion") + 60 частиц. На телефоне это
-- и давало просадку и «двойной» взрыв (стандартный эффект Roblox + наши частицы).
local function createExplosionFX(pos)
    local anchor = Instance.new("Part")
    anchor.Name = "ExplosionFX"
    anchor.Size = Vector3.new(1, 1, 1)
    anchor.Position = pos
    anchor.Anchored = true
    anchor.CanCollide = false
    anchor.CanQuery = false
    anchor.CanTouch = false
    anchor.CastShadow = false
    anchor.Transparency = 1
    anchor.Parent = workspace

    local boom = Instance.new("Sound")
    boom.SoundId = Config.SOUND_EXPLOSION
    boom.Volume = 0.9
    boom.RollOffMaxDistance = 350
    boom.Parent = anchor
    boom:Play()

    local fire = Instance.new("ParticleEmitter")
    fire.Color = ColorSequence.new({
        NumberSequenceKeypoint.new(0,   Color3.fromRGB(255, 235, 120)),
        NumberSequenceKeypoint.new(0.35, Color3.fromRGB(255, 120, 20)),
        NumberSequenceKeypoint.new(1,   Color3.fromRGB(45, 45, 45)),
    })
    fire.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0,   1.5),
        NumberSequenceKeypoint.new(0.4, 5.0),
        NumberSequenceKeypoint.new(1,   0.5),
    })
    fire.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(1, 1),
    })
    fire.Lifetime = NumberRange.new(0.4, 0.8)
    fire.Speed    = NumberRange.new(20, 40)
    fire.Rate     = 0
    fire.SpreadAngle = Vector2.new(160, 160)
    fire.Parent = anchor
    fire:Emit(16)

    local smoke = Instance.new("ParticleEmitter")
    smoke.Color = ColorSequence.new(Color3.fromRGB(60, 60, 60), Color3.fromRGB(25, 25, 25))
    smoke.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 2),
        NumberSequenceKeypoint.new(1, 8),
    })
    smoke.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.4),
        NumberSequenceKeypoint.new(1, 1),
    })
    smoke.Lifetime = NumberRange.new(0.8, 1.4)
    smoke.Speed    = NumberRange.new(6, 14)
    smoke.Rate     = 0
    smoke.Parent = anchor
    smoke:Emit(8)

    local light = Instance.new("PointLight")
    light.Color = Color3.fromRGB(255, 170, 70)
    light.Brightness = 5
    light.Range = 22
    light.Parent = anchor
    task.delay(0.3, function()
        if light and light.Parent then light.Enabled = false end
    end)

    Debris:AddItem(anchor, 2.5)
end

-- ────────────────────── МОДЕЛЬ ДРОНА ───────────────────────
local droneCounter = 0

local function buildDrone(pos, yaw)
    droneCounter = droneCounter + 1
    local model = Instance.new("Model")
    model.Name = "FPV_Drone_" .. droneCounter
    model:SetAttribute("DroneId", droneCounter)
    model:SetAttribute("IsPiloted", false)
    model:SetAttribute("PilotUserId", 0)

    local baseCF = CFrame.new(pos) * CFrame.Angles(0, yaw or 0, 0)

    -- 1. Центральная рама (корень ассембли, всегда Anchored)
    local body = makePart(model, "Body",
        Vector3.new(2.2, 0.25, 2.2), baseCF,
        "Dark stone grey", Enum.Material.DiamondPlate, true)
    body.Anchored = true
    model.PrimaryPart = body

    local function attach(name, size, offsetCF, color, mat, shape, transp)
        local p = makePart(model, name, size, baseCF * offsetCF, color, mat, false, shape, transp)
        p.Massless = true
        weld(body, p)
        return p
    end

    -- 2. Верхняя пластина и аккумулятор
    attach("TopPlate", Vector3.new(1.3, 0.1, 1.3),
        CFrame.new(0, 0.17, 0), "Really black", Enum.Material.SmoothPlastic)
    attach("LiPoBattery", Vector3.new(0.75, 0.45, 1.15),
        CFrame.new(0, 0.42, 0.05), "Bright yellow", Enum.Material.SmoothPlastic)

    -- 3. X-рама: 4 луча, 4 мотора, 4 пропеллера, 4 колпачка
    local armConfigs = {
        { dir = Vector3.new( 1, 0, -1), angle =  45, color = "Bright red" },
        { dir = Vector3.new(-1, 0, -1), angle = -45, color = "Bright blue" },
        { dir = Vector3.new( 1, 0,  1), angle = -45, color = "Lime green" },
        { dir = Vector3.new(-1, 0,  1), angle =  45, color = "Bright yellow" },
    }

    for i, cfg in ipairs(armConfigs) do
        local uDir = cfg.dir.Unit
        attach("Arm" .. i, Vector3.new(0.2, 0.12, 1.6),
            CFrame.new(uDir * 0.9) * CFrame.Angles(0, math.rad(cfg.angle), 0),
            "Dark stone grey", Enum.Material.Metal)

        local motor = attach("Motor" .. i, Vector3.new(0.42, 0.25, 0.42),
            CFrame.new(uDir * 1.55) * CFrame.Angles(0, 0, math.rad(90)),
            "Really black", Enum.Material.Metal, Enum.PartType.Cylinder)

        attach("Prop" .. i, Vector3.new(0.04, 1.5, 1.5),
            CFrame.new(uDir * 1.55 + Vector3.new(0, 0.18, 0)) * CFrame.Angles(0, 0, math.rad(90)),
            "Institutional white", Enum.Material.SmoothPlastic, Enum.PartType.Cylinder, 0.45)

        attach("Cap" .. i, Vector3.new(0.3, 0.12, 0.3),
            CFrame.new(uDir * 1.55 + Vector3.new(0, 0.16, 0)) * CFrame.Angles(0, 0, math.rad(90)),
            cfg.color, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)

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

    -- 4. Камера
    local camCF = CFrame.new(0, 0.22, -1.25) * CFrame.Angles(math.rad(-Config.CAM_TILT), 0, 0)
    attach("CamBody", Vector3.new(0.45, 0.35, 0.45),
        camCF, "Really black", Enum.Material.SmoothPlastic)
    attach("CamLens", Vector3.new(0.24, 0.24, 0.08),
        camCF * CFrame.new(0, 0, -0.24), "Bright blue", Enum.Material.Neon)

    -- 5. Огни и ножки
    attach("LED_FL", Vector3.new(0.12, 0.08, 0.12), CFrame.new( 0.75, -0.05, -0.95),
        "Lime green", Enum.Material.Neon)
    attach("LED_FR", Vector3.new(0.12, 0.08, 0.12), CFrame.new(-0.75, -0.05, -0.95),
        "Lime green", Enum.Material.Neon)
    attach("LED_RL", Vector3.new(0.12, 0.08, 0.12), CFrame.new( 0.75, -0.05, 0.95),
        "Bright red", Enum.Material.Neon)
    attach("LED_RR", Vector3.new(0.12, 0.08, 0.12), CFrame.new(-0.75, -0.05, 0.95),
        "Bright red", Enum.Material.Neon)

    for _, lOff in ipairs({
        Vector3.new( 0.8, -0.22,  0.8),
        Vector3.new(-0.8, -0.22,  0.8),
        Vector3.new( 0.8, -0.22, -0.8),
        Vector3.new(-0.8, -0.22, -0.8),
    }) do
        attach("Leg", Vector3.new(0.1, 0.28, 0.1), CFrame.new(lOff),
            "Really black", Enum.Material.SmoothPlastic)
    end

    -- 6. Звуки
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

    -- 7. Подсветка (видно свободный дрон)
    local hl = Instance.new("Highlight")
    hl.Name = "DroneHL"
    hl.FillColor = Color3.fromRGB(0, 220, 255)
    hl.FillTransparency = 0.85
    hl.OutlineColor = Color3.fromRGB(0, 240, 255)
    hl.OutlineTransparency = 0.15
    hl.Enabled = true
    hl.Parent = model

    -- 8. Хитбокс для взятия (CanCollide=false, но ловит клик и промпт)
    local hitbox = makePart(model, "Hitbox",
        Vector3.new(4.5, 2.6, 4.5), baseCF,
        "Really black", Enum.Material.SmoothPlastic, false, nil, 1)
    hitbox.Massless = true
    hitbox.CanQuery = true
    hitbox.CanTouch = true
    weld(body, hitbox)

    model.Parent = dronesFolder

    local rec = {
        model  = model,
        body   = body,
        hitbox = hitbox,
        hl     = hl,
        beepSnd = beepSnd,
        mode   = "idle",              -- "idle" | "piloted" | "parking"
        pilot  = nil,
        state  = FlightModel.new(Config, pos.X, pos.Y, pos.Z, yaw or 0),
        input  = NEUTRAL_INPUT,
        inputAt = 0,
        idleSince = os.clock(),
        exploded = false,
    }
    drones[model] = rec

    -- Клик по дрону
    local click = Instance.new("ClickDetector")
    click.Name = "DroneClick"
    click.MaxActivationDistance = 40
    click.Parent = hitbox
    click.MouseClick:Connect(function(player)
        claimDrone(rec, player)
    end)

    -- Промпт «Взлететь»
    local prompt = Instance.new("ProximityPrompt")
    prompt.Name = "TakePrompt"
    prompt.ActionText = "Взлететь"
    prompt.ObjectText = "FPV Дрон"
    prompt.HoldDuration = 0
    prompt.MaxActivationDistance = 24
    prompt.KeyboardKeyCode = Enum.KeyCode.E
    prompt.RequiresLineOfSight = false
    prompt.Parent = hitbox
    prompt.Triggered:Connect(function(player)
        claimDrone(rec, player)
    end)

    return rec
end

-- ────────────────────── ВЗЯТИЕ / ОСВОБОЖДЕНИЕ ─────────────
local function setPickupEnabled(rec, enabled)
    rec.hitbox.CanQuery = enabled
    rec.hitbox.CanTouch = enabled

    local prompt = rec.hitbox:FindFirstChild("TakePrompt")
    if prompt then prompt.Enabled = enabled end

    local click = rec.hitbox:FindFirstChild("DroneClick")
    if click then click.MaxActivationDistance = enabled and 40 or 0 end

    rec.hl.Enabled = enabled
    rec.model:SetAttribute("IsPiloted", not enabled)
    if not enabled and rec.pilot then
        rec.model:SetAttribute("PilotUserId", rec.pilot.UserId)
    elseif enabled then
        rec.model:SetAttribute("PilotUserId", 0)
    end
end

local function placeBody(rec)
    local s = rec.state
    rec.body.CFrame = CFrame.new(s.x, s.y, s.z)
        * CFrame.Angles(0, s.yaw, 0)
        * CFrame.Angles(-s.pitch, 0, 0)
        * CFrame.Angles(0, 0, -s.roll)
end

local function removeDrone(rec)
    drones[rec.model] = nil
    if rec.pilot and playerDrones[rec.pilot] == rec then
        playerDrones[rec.pilot] = nil
    end
    pcall(function()
        rec.model:Destroy()
    end)
end

local function loseDrone(rec, reason)
    if not drones[rec.model] then return end
    if rec.exploded then return end          -- эффект строго один на дрон
    rec.exploded = true

    local pos = Vector3.new(rec.state.x, rec.state.y, rec.state.z)

    createExplosionFX(pos)

    local pilot = rec.pilot
    if pilot then
        playerDrones[pilot] = nil            -- пилот сразу свободен и может взять новый
        rec.pilot = nil
        lostRemote:FireClient(pilot, reason or "crash")
    end
    removeDrone(rec)
end

-- Дрон выходит из-под управления: плавно садится и снова становится доступным
local function parkDrone(rec)
    if not drones[rec.model] then return end
    if rec.pilot then
        if playerDrones[rec.pilot] == rec then
            playerDrones[rec.pilot] = nil
        end
        rec.pilot = nil
    end
    rec.mode = "parking"
    rec.input = NEUTRAL_INPUT
    rec.state.vy = 0
    rec.state.vx = 0
    rec.state.vz = 0
    setPickupEnabled(rec, true)
end

claimDrone = function(rec, player)
    if not rec or not drones[rec.model] or rec.mode ~= "idle" then return end

    -- Один дрон на игрока, но устаревшую запись (дрон уже удалён/не летает)
    -- чистим, иначе игрок навсегда остаётся «занятым» и новые дроны не берутся
    local existing = playerDrones[player]
    if existing then
        if existing == rec then return end
        if drones[existing.model] and existing.mode == "piloted" then return end
        playerDrones[player] = nil
    end

    rec.mode  = "piloted"
    rec.pilot = player
    playerDrones[player] = rec

    -- Сброс состояния: полный покой, стики в центре, газ = удержание высоты
    rec.state.vx, rec.state.vy, rec.state.vz = 0, 0, 0
    rec.state.pitch, rec.state.roll = 0, 0
    rec.input = NEUTRAL_INPUT
    rec.inputAt = os.clock()

    setPickupEnabled(rec, false)

    if rec.beepSnd then rec.beepSnd:Play() end

    mountRemote:FireClient(player, rec.model)
    print(string.format("[DroneServer] %s взял %s", player.Name, rec.model.Name))
end

-- ────────────────────── СТОЛКНОВЕНИЯ И ДВИЖЕНИЕ ───────────
local function movePiloted(rec, dt, params)
    local s = rec.state
    local oldX, oldZ = s.x, s.z

    local input = rec.input
    if (os.clock() - rec.inputAt) > Config.INPUT_TIMEOUT then
        -- ввод пропал — не висим в воздухе, а падаем как настоящий FPV
        input = STALE_INPUT
    end
    FlightModel.step(s, dt, input)

    -- Границы карты: улетел за карту — взрыв и респавн нового дрона
    local hDist = math.sqrt(s.x * s.x + s.z * s.z)
    if hDist > Config.BOUNDS_RADIUS or s.y < Config.BOUNDS_MIN_Y or s.y > Config.BOUNDS_MAX_Y then
        loseDrone(rec, "borders")
        return
    end

    -- Стены: луч по направлению движения на длину шага + радиус корпуса
    local dx, dz = s.x - oldX, s.z - oldZ
    local flatDist = math.sqrt(dx * dx + dz * dz)
    if flatDist > 1e-5 then
        local ux, uz = dx / flatDist, dz / flatDist
        local origin = Vector3.new(oldX, s.y, oldZ)
        local reach  = flatDist + Config.BODY_RADIUS
        local hit = workspace:Raycast(origin, Vector3.new(ux * reach, 0, uz * reach), params)

        if hit and math.abs(hit.Normal.Y) <= 0.6 then          -- именно стена, а не пол/потолок
            local impactSpeed = FlightModel.horizontalSpeed(s)
            if impactSpeed >= Config.CRASH_SPEED then
                s.x, s.z = hit.Position.X, hit.Position.Z
                loseDrone(rec, "crash")
                return
            end
            -- медленное касание: отодвигаем от стены и скользим вдоль неё
            local back = math.max(hit.Distance - Config.BODY_RADIUS, 0)
            s.x = oldX + ux * back
            s.z = oldZ + uz * back
            FlightModel.cancelAlongNormal(s, hit.Normal.X, hit.Normal.Z)
        end
    end

    -- Земля: садимся и скользим, взрыва НЕТ никогда
    local gHit = workspace:Raycast(
        Vector3.new(s.x, s.y, s.z),
        Vector3.new(0, -(Config.GROUND_OFFSET + 0.4), 0),
        params)
    if gHit and gHit.Normal.Y > 0.5 then
        local floorY = gHit.Position.Y + Config.GROUND_OFFSET
        if s.y <= floorY then
            s.y = floorY
            if s.vy < 0 then s.vy = 0 end
        end
    end

    placeBody(rec)
end

local function updateParking(rec, dt, params)
    local s = rec.state

    local relax = math.clamp(4 * dt, 0, 1)
    s.pitch = s.pitch + (0 - s.pitch) * relax
    s.roll  = s.roll  + (0 - s.roll)  * relax

    local hit = workspace:Raycast(Vector3.new(s.x, s.y, s.z), Vector3.new(0, -400, 0), params)
    local floorY = (hit and hit.Position.Y or (s.y - 1)) + Config.GROUND_OFFSET

    if s.y > floorY + 0.05 then
        s.y = math.max(floorY, s.y - Config.PARK_FALL_SPEED * dt)
        s.vy = -Config.PARK_FALL_SPEED
    else
        s.y = floorY
        s.vy = 0
        rec.mode = "idle"
        rec.idleSince = os.clock()
    end

    placeBody(rec)
end

-- ────────────────────── REMOTE HANDLERS ────────────────────
inputRemote.OnServerEvent:Connect(function(player, pitch, roll, yaw, throttle)
    local rec = playerDrones[player]
    if not rec or rec.mode ~= "piloted" then return end
    if type(pitch) ~= "number" or type(roll) ~= "number"
        or type(yaw) ~= "number" or type(throttle) ~= "number" then
        return
    end
    rec.input = {
        pitch    = math.clamp(pitch, -1, 1),
        roll     = math.clamp(roll, -1, 1),
        yaw      = math.clamp(yaw, -1, 1),
        throttle = math.clamp(throttle, 0, 1),
    }
    rec.inputAt = os.clock()
end)

-- 💥 Ручная детонация
selfDestructRemote.OnServerEvent:Connect(function(player)
    local rec = playerDrones[player]
    if rec then loseDrone(rec, "manual") end
end)

-- 🚪 Выход из дрона
unmountRemote.OnServerEvent:Connect(function(player)
    local rec = playerDrones[player]
    if rec then parkDrone(rec) end
end)

Players.PlayerRemoving:Connect(function(player)
    local rec = playerDrones[player]
    playerDrones[player] = nil
    if rec and drones[rec.model] then
        removeDrone(rec)
    end
end)

-- ────────────────────── ГЛАВНЫЙ ЦИКЛ ───────────────────────
RunService.Heartbeat:Connect(function(dt)
    if next(drones) == nil then return end

    local params = buildFilter()
    local now = os.clock()

    local snapshot = {}
    for model, rec in pairs(drones) do
        if model.Parent then table.insert(snapshot, rec) end
    end

    for _, rec in ipairs(snapshot) do
        if drones[rec.model] then
            if rec.mode == "piloted" then
                movePiloted(rec, dt, params)
            elseif rec.mode == "parking" then
                updateParking(rec, dt, params)
            elseif rec.mode == "idle" and (now - rec.idleSince) > Config.IDLE_LIFETIME then
                -- забытый ничейный дрон (и не тот, что на площадке) убираем
                local distToPad = (Vector3.new(rec.state.x, rec.state.y, rec.state.z)
                    - Config.DRONE_SPAWN).Magnitude
                if distToPad > Config.PAD_CLEAR_RADIUS then
                    removeDrone(rec)
                else
                    rec.idleSince = now
                end
            end
        end
    end
end)

-- ────────────────────── АВТОСПАВН ──────────────────────────
task.spawn(function()
    while true do
        local total = 0
        local padFree = true

        for model, rec in pairs(drones) do
            if model.Parent then
                total = total + 1
                local dist = (Vector3.new(rec.state.x, rec.state.y, rec.state.z)
                    - Config.DRONE_SPAWN).Magnitude
                if rec.mode ~= "piloted" and dist < Config.PAD_CLEAR_RADIUS then
                    -- на площадке уже стоит свободный дрон — плодить второй в той же точке нельзя
                    padFree = false
                end
            end
        end

        if total < Config.MAX_DRONES and padFree then
            buildDrone(Config.DRONE_SPAWN, 0)
            print("[DroneServer] Новый дрон готов на площадке")
        end

        task.wait(Config.RESPAWN_INTERVAL)
    end
end)

print("[DroneServer] Сервер дронов v10 активен!")
