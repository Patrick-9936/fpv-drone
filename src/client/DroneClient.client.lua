--[[
    DroneClient v5 — Реалистичный FPV квадрокоптер
    - Физическая модель тяги: тяга направлена вдоль крыши дрона (CFrame.UpVector)
    - Газ: 50% = парение (hover), 100% = мощный взлёт, 0% = свободное падение
    - Аэродинамика: накат по инерции и естественное сопротивление воздуха
    - Разворот 360° по рысканию, наклон до 45° по тангажу и крену
    - Кнопка ручной детонации (💥 ПОДРЫВ) на экране и клавиша R / X
    - Удобные сенсорные джойстики для телефона и поддержка ПК (WASD)
]]

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local Config  = require(ReplicatedStorage:WaitForChild("DroneConfig"))
local remotes = ReplicatedStorage:WaitForChild("DroneRemotes")

local mountRemote        = remotes:WaitForChild("MountDrone")
local unmountRemote      = remotes:WaitForChild("UnmountDrone")
local explodeRemote      = remotes:WaitForChild("DroneExploded")
local selfDestructRemote = remotes:WaitForChild("SelfDestruct")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- ────────────────────── СОСТОЯНИЕ ──────────────────────────
local mounted     = false
local droneModel  = nil
local droneBody   = nil
local bodyGyro    = nil
local motorSound  = nil
local windSound   = nil

-- Ориентация
local currentYaw   = 0   -- курс (Y)
local currentPitch = 0   -- тангаж (X)
local currentRoll  = 0   -- крен (Z)

-- Ввод (-1 .. 1)
local pitchIn    = 0
local rollIn     = 0
local yawIn      = 0
local throttleIn = 0.5   -- 0.5 = парение, 1 = полный газ, 0 = выключен

local keysDown   = {}
local isMobile   = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local collisionCooldown = false

-- ────────────────────── ЗВУК ВЕТРА ─────────────────────────
local function setupWindAudio()
    if not windSound then
        windSound = Instance.new("Sound")
        windSound.Name = "WindSFX"
        windSound.SoundId = "rbxasset://sounds/action_falling.mp3"
        windSound.Looped = true
        windSound.Volume = 0
        windSound.Parent = camera
    end
end
setupWindAudio()

-- ────────────────────── HUD / FPV OSD ──────────────────────
local hudGui, horizonBar, warningLabel, flashFrame

local function createHUD()
    if hudGui then hudGui:Destroy() end

    hudGui = Instance.new("ScreenGui")
    hudGui.Name = "DroneHUD"
    hudGui.ResetOnSpawn = false
    hudGui.Enabled = false
    hudGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    hudGui.Parent = player:WaitForChild("PlayerGui")

    -- Вспышка при взрыве
    flashFrame = Instance.new("Frame")
    flashFrame.Name = "Flash"
    flashFrame.Size = UDim2.new(1, 0, 1, 0)
    flashFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    flashFrame.BackgroundTransparency = 1
    flashFrame.BorderSizePixel = 0
    flashFrame.Parent = hudGui

    -- Виньетка
    local vig = Instance.new("ImageLabel")
    vig.Name = "Vignette"
    vig.Size = UDim2.new(1, 0, 1, 0)
    vig.BackgroundTransparency = 1
    vig.Image = "rbxassetid://4576475446"
    vig.ImageColor3 = Color3.fromRGB(0, 0, 0)
    vig.ImageTransparency = 0.55
    vig.Parent = hudGui

    -- Прицел (крестик)
    local chV = Instance.new("Frame")
    chV.Size = UDim2.new(0, 2, 0, 22)
    chV.AnchorPoint = Vector2.new(0.5, 0.5)
    chV.Position = UDim2.new(0.5, 0, 0.5, 0)
    chV.BackgroundColor3 = Color3.fromRGB(0, 255, 120)
    chV.BackgroundTransparency = 0.2
    chV.BorderSizePixel = 0
    chV.Parent = hudGui

    local chH = Instance.new("Frame")
    chH.Size = UDim2.new(0, 22, 0, 2)
    chH.AnchorPoint = Vector2.new(0.5, 0.5)
    chH.Position = UDim2.new(0.5, 0, 0.5, 0)
    chH.BackgroundColor3 = Color3.fromRGB(0, 255, 120)
    chH.BackgroundTransparency = 0.2
    chH.BorderSizePixel = 0
    chH.Parent = hudGui

    -- Линия горизонта
    horizonBar = Instance.new("Frame")
    horizonBar.Name = "Horizon"
    horizonBar.Size = UDim2.new(0, 90, 0, 2)
    horizonBar.AnchorPoint = Vector2.new(0.5, 0.5)
    horizonBar.Position = UDim2.new(0.5, 0, 0.5, 20)
    horizonBar.BackgroundColor3 = Color3.fromRGB(0, 255, 120)
    horizonBar.BackgroundTransparency = 0.4
    horizonBar.BorderSizePixel = 0
    horizonBar.Parent = hudGui

    -- Панель OSD (слева сверху)
    local panel = Instance.new("Frame")
    panel.Name = "InfoPanel"
    panel.Size = UDim2.new(0, 155, 0, 105)
    panel.Position = UDim2.new(0, 14, 0, 14)
    panel.BackgroundColor3 = Color3.fromRGB(10, 15, 10)
    panel.BackgroundTransparency = 0.45
    panel.BorderSizePixel = 0
    panel.Parent = hudGui
    Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 8)

    local function makeLabel(name, yPos)
        local l = Instance.new("TextLabel")
        l.Name = name
        l.Size = UDim2.new(1, -16, 0, 20)
        l.Position = UDim2.new(0, 10, 0, yPos)
        l.BackgroundTransparency = 1
        l.TextColor3 = Color3.fromRGB(0, 255, 120)
        l.Font = Enum.Font.Code
        l.TextSize = 14
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.Text = ""
        l.Parent = panel
        return l
    end
    makeLabel("Speed", 8)
    makeLabel("Alt", 30)
    makeLabel("Thr", 52)
    makeLabel("Bat", 74)

    -- REC индикатор
    local topR = Instance.new("TextLabel")
    topR.Name = "TopRightOSD"
    topR.Size = UDim2.new(0, 140, 0, 26)
    topR.Position = UDim2.new(1, -150, 0, 14)
    topR.BackgroundTransparency = 1
    topR.TextColor3 = Color3.fromRGB(255, 60, 60)
    topR.Font = Enum.Font.Code
    topR.TextSize = 15
    topR.Text = "● REC  4S 15.6V"
    topR.Parent = hudGui

    -- Предупреждение о границах
    warningLabel = Instance.new("TextLabel")
    warningLabel.Name = "WarningBanner"
    warningLabel.Size = UDim2.new(0, 360, 0, 38)
    warningLabel.AnchorPoint = Vector2.new(0.5, 0.5)
    warningLabel.Position = UDim2.new(0.5, 0, 0.22, 0)
    warningLabel.BackgroundColor3 = Color3.fromRGB(210, 20, 20)
    warningLabel.BackgroundTransparency = 0.25
    warningLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    warningLabel.Font = Enum.Font.GothamBold
    warningLabel.TextSize = 15
    warningLabel.Text = "⚠️ ВЫХОД ЗА ГРАНИЦЫ"
    warningLabel.Visible = false
    warningLabel.Parent = hudGui
    Instance.new("UICorner", warningLabel).CornerRadius = UDim.new(0, 8)

    -- ВЕРХНЯЯ ПАНЕЛЬ УПРАВЛЕНИЯ (Кнопка ПОДРЫВ и ВЫХОД)
    local topControls = Instance.new("Frame")
    topControls.Name = "TopControls"
    topControls.Size = UDim2.new(0, 260, 0, 42)
    topControls.AnchorPoint = Vector2.new(0.5, 0)
    topControls.Position = UDim2.new(0.5, 0, 0, 12)
    topControls.BackgroundTransparency = 1
    topControls.Parent = hudGui

    -- 💥 КНОПКА РУЧНОЙ ДЕТОНАЦИИ
    local boomBtn = Instance.new("TextButton")
    boomBtn.Name = "BoomBtn"
    boomBtn.Size = UDim2.new(0, 130, 0, 38)
    boomBtn.Position = UDim2.new(0, 0, 0, 0)
    boomBtn.BackgroundColor3 = Color3.fromRGB(220, 35, 35)
    boomBtn.BackgroundTransparency = 0.15
    boomBtn.BorderSizePixel = 0
    boomBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    boomBtn.Font = Enum.Font.GothamBlack
    boomBtn.TextSize = 14
    boomBtn.Text = "💥 ПОДРЫВ"
    boomBtn.Parent = topControls
    Instance.new("UICorner", boomBtn).CornerRadius = UDim.new(0, 8)
    boomBtn.MouseButton1Click:Connect(function()
        if mounted then
            manualDetonate()
        end
    end)

    -- 🚪 КНОПКА ВЫХОДА
    local exitBtn = Instance.new("TextButton")
    exitBtn.Name = "ExitBtn"
    exitBtn.Size = UDim2.new(0, 110, 0, 38)
    exitBtn.Position = UDim2.new(0, 140, 0, 0)
    exitBtn.BackgroundColor3 = Color3.fromRGB(60, 65, 75)
    exitBtn.BackgroundTransparency = 0.25
    exitBtn.BorderSizePixel = 0
    exitBtn.TextColor3 = Color3.fromRGB(230, 230, 230)
    exitBtn.Font = Enum.Font.GothamBold
    exitBtn.TextSize = 13
    exitBtn.Text = "🚪 ВЫХОД"
    exitBtn.Parent = topControls
    Instance.new("UICorner", exitBtn).CornerRadius = UDim.new(0, 8)
    exitBtn.MouseButton1Click:Connect(function()
        if mounted then
            unmountDrone()
        end
    end)

    -- Подсказка для ПК
    if not isMobile then
        local hint = Instance.new("TextLabel")
        hint.Size = UDim2.new(0, 520, 0, 34)
        hint.AnchorPoint = Vector2.new(0.5, 1)
        hint.Position = UDim2.new(0.5, 0, 1, -12)
        hint.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        hint.BackgroundTransparency = 0.55
        hint.TextColor3 = Color3.fromRGB(215, 215, 215)
        hint.Font = Enum.Font.Code
        hint.TextSize = 13
        hint.Text = "W/S: Тангаж | A/D: Крен | Q/E: Рыскание | Space/Shift: Газ | R: ПОДРЫВ | F: Выход"
        hint.Parent = hudGui
        Instance.new("UICorner", hint).CornerRadius = UDim.new(0, 6)
    end
end

local function updateHUD()
    if not hudGui or not hudGui.Enabled or not droneBody then return end
    local panel = hudGui:FindFirstChild("InfoPanel")
    if not panel then return end

    local vel = droneBody.AssemblyLinearVelocity
    local spd = math.floor(vel.Magnitude + 0.5)
    local alt = math.floor(droneBody.Position.Y + 0.5)
    local thrPct = math.floor(math.clamp(throttleIn, 0, 1) * 100 + 0.5)

    local sLbl = panel:FindFirstChild("Speed")
    if sLbl then sLbl.Text = string.format("SPD  %d st/s", spd) end

    local aLbl = panel:FindFirstChild("Alt")
    if aLbl then aLbl.Text = string.format("ALT  %d st", alt) end

    local tLbl = panel:FindFirstChild("Thr")
    if tLbl then tLbl.Text = string.format("THR  %d %%", thrPct) end

    local bLbl = panel:FindFirstChild("Bat")
    if bLbl then bLbl.Text = "BAT  4S 98%" end

    if horizonBar then
        horizonBar.Rotation = math.deg(-currentRoll)
        horizonBar.Position = UDim2.new(0.5, 0, 0.5, math.clamp(math.deg(currentPitch) * 1.2, -60, 60))
    end
end

-- ────────────────────── МОБИЛЬНЫЕ СТИКИ ───────────────────
local mobileGui
local leftJoyCenter, rightJoyCenter
local leftTouchId, rightTouchId
local leftThumb, rightThumb
local JOY_RADIUS = 55

local function createMobileUI()
    if not isMobile then return end
    if mobileGui then mobileGui:Destroy() end

    mobileGui = Instance.new("ScreenGui")
    mobileGui.Name = "MobileControls"
    mobileGui.ResetOnSpawn = false
    mobileGui.Enabled = false
    mobileGui.Parent = player:WaitForChild("PlayerGui")

    local function createStick(name, xAnchor, xPos, labelTxt)
        local base = Instance.new("Frame")
        base.Name = name .. "Base"
        base.Size = UDim2.new(0, 140, 0, 140)
        base.AnchorPoint = Vector2.new(xAnchor, 1)
        base.Position = UDim2.new(xPos, 0, 1, -25)
        base.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        base.BackgroundTransparency = 0.82
        base.BorderSizePixel = 0
        base.Parent = mobileGui
        Instance.new("UICorner", base).CornerRadius = UDim.new(1, 0)

        local thumb = Instance.new("Frame")
        thumb.Name = "Thumb"
        thumb.Size = UDim2.new(0, 55, 0, 55)
        thumb.AnchorPoint = Vector2.new(0.5, 0.5)
        thumb.Position = UDim2.new(0.5, 0, 0.5, 0)
        thumb.BackgroundColor3 = Color3.fromRGB(0, 220, 255)
        thumb.BackgroundTransparency = 0.3
        thumb.BorderSizePixel = 0
        thumb.Parent = base
        Instance.new("UICorner", thumb).CornerRadius = UDim.new(1, 0)

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, 0, 0, 18)
        lbl.Position = UDim2.new(0, 0, 0, -22)
        lbl.BackgroundTransparency = 1
        lbl.TextColor3 = Color3.fromRGB(220, 220, 220)
        lbl.Font = Enum.Font.GothamBold
        lbl.TextSize = 12
        lbl.Text = labelTxt
        lbl.Parent = base

        return base, thumb
    end

    local leftBase, lThumb  = createStick("LeftStick",  0, 0.04, "ГАЗ / РЫСКАНИЕ")
    local rightBase, rThumb = createStick("RightStick", 1, 0.96, "ТАНГАЖ / КРЕН")
    leftThumb  = lThumb
    rightThumb = rThumb
end

if isMobile then
    UserInputService.InputBegan:Connect(function(input, gp)
        if gp or not mounted then return end
        if input.UserInputType ~= Enum.UserInputType.Touch then return end

        local pos = Vector2.new(input.Position.X, input.Position.Y)
        local screenW = camera.ViewportSize.X

        if pos.X < (screenW * 0.45) and not leftTouchId then
            leftTouchId = input
            leftJoyCenter = pos
        elseif pos.X >= (screenW * 0.55) and not rightTouchId then
            rightTouchId = input
            rightJoyCenter = pos
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.Touch then return end
        local dz = 0.07

        if input == leftTouchId and leftJoyCenter then
            local delta = Vector2.new(input.Position.X, input.Position.Y) - leftJoyCenter
            local norm = delta / JOY_RADIUS
            if norm.Magnitude > 1 then norm = norm.Unit end

            local rawX = (math.abs(norm.X) > dz) and norm.X or 0
            local rawY = (math.abs(norm.Y) > dz) and norm.Y or 0

            yawIn = rawX * math.abs(rawX)
            -- Вверх = газ 0.5 .. 1.0; Вниз = 0.5 .. 0.0; Центр = 0.5 (парение)
            throttleIn = math.clamp(0.5 - (rawY * 0.5), 0, 1)

            if leftThumb then
                leftThumb.Position = UDim2.new(0.5 + norm.X * 0.4, 0, 0.5 + norm.Y * 0.4, 0)
            end
        elseif input == rightTouchId and rightJoyCenter then
            local delta = Vector2.new(input.Position.X, input.Position.Y) - rightJoyCenter
            local norm = delta / JOY_RADIUS
            if norm.Magnitude > 1 then norm = norm.Unit end

            local rawX = (math.abs(norm.X) > dz) and norm.X or 0
            local rawY = (math.abs(norm.Y) > dz) and norm.Y or 0

            rollIn  = rawX * math.abs(rawX)
            pitchIn = -rawY * math.abs(rawY) -- вверх = нос вниз (вперёд)

            if rightThumb then
                rightThumb.Position = UDim2.new(0.5 + norm.X * 0.4, 0, 0.5 + norm.Y * 0.4, 0)
            end
        end
    end)

    local function resetLeft()
        leftTouchId = nil
        leftJoyCenter = nil
        yawIn = 0
        throttleIn = 0.5 -- возврат к парению
        if leftThumb then leftThumb.Position = UDim2.new(0.5, 0, 0.5, 0) end
    end

    local function resetRight()
        rightTouchId = nil
        rightJoyCenter = nil
        rollIn = 0
        pitchIn = 0
        if rightThumb then rightThumb.Position = UDim2.new(0.5, 0, 0.5, 0) end
    end

    UserInputService.InputEnded:Connect(function(input)
        if input == leftTouchId  then resetLeft()  end
        if input == rightTouchId then resetRight() end
    end)
end

-- ────────────────────── КЛАВИАТУРА (ПК) ────────────────────
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
    pitchIn = 0
    rollIn  = 0
    yawIn   = 0

    if keysDown[Enum.KeyCode.W] then pitchIn =  1 end
    if keysDown[Enum.KeyCode.S] then pitchIn = -1 end
    if keysDown[Enum.KeyCode.A] then rollIn  = -1 end
    if keysDown[Enum.KeyCode.D] then rollIn  =  1 end
    if keysDown[Enum.KeyCode.Q] then yawIn   = -1 end
    if keysDown[Enum.KeyCode.E] then yawIn   =  1 end

    -- Газ
    if keysDown[Enum.KeyCode.Space] then
        throttleIn = math.min(throttleIn + 0.035, 1)
    elseif keysDown[Enum.KeyCode.LeftShift] then
        throttleIn = math.max(throttleIn - 0.035, 0)
    else
        -- Плавный возврат к 0.5 (парение)
        if throttleIn > 0.52 then
            throttleIn = throttleIn - 0.015
        elseif throttleIn < 0.48 then
            throttleIn = throttleIn + 0.015
        end
    end
end

-- ────────────────────── ВИДИМОСТЬ ПЕРСОНАЖА ────────────────
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

local function setPropWash(enabled)
    if not droneModel then return end
    for _, p in droneModel:GetDescendants() do
        if p:IsA("ParticleEmitter") and p.Name == "Wash" then
            p.Enabled = enabled
        end
    end
end

-- ────────────────────── МАУНТ / АНМАУНТ ────────────────────
function mountDrone(drone)
    if mounted then return end
    droneModel = drone
    droneBody  = drone and drone.PrimaryPart
    if not droneBody then return end

    bodyGyro   = droneBody:FindFirstChild("DroneGyro")
    motorSound = droneBody:FindFirstChild("MotorSound")

    mounted = true
    collisionCooldown = false

    -- Начальные углы из ориентации дрона
    local _, ry, _ = droneBody.CFrame:ToOrientation()
    currentYaw   = ry
    currentPitch = 0
    currentRoll  = 0
    throttleIn   = 0.5

    -- Камера в FPV режим
    camera.CameraType = Enum.CameraType.Scriptable

    -- Звуки
    if motorSound then
        motorSound.Volume = 0.5
        motorSound.PlaybackSpeed = 0.95
        motorSound:Play()
    end
    if windSound then
        windSound.Volume = 0
        windSound:Play()
    end

    setPropWash(true)
    setCharVisible(false)

    if hudGui    then hudGui.Enabled    = true end
    if mobileGui then mobileGui.Enabled = true end
    if warningLabel then warningLabel.Visible = false end

    -- Детектор столкновения
    droneBody.Touched:Connect(function(hit)
        if not mounted or collisionCooldown then return end
        if hit:IsDescendantOf(droneModel) then return end
        if hit.Parent and hit.Parent:FindFirstChildOfClass("Humanoid") then return end

        local spd = droneBody.AssemblyLinearVelocity.Magnitude
        if spd >= Config.MIN_COLLISION_SPEED then
            collisionCooldown = true
            crashExplode()
        end
    end)
end

function unmountDrone()
    if not mounted then return end
    mounted = false

    if motorSound then motorSound:Stop() end
    if windSound  then windSound:Stop()  end
    setPropWash(false)

    camera.CameraType = Enum.CameraType.Custom
    if hudGui    then hudGui.Enabled    = false end
    if mobileGui then mobileGui.Enabled = false end
    setCharVisible(true)

    local targetDrone = droneModel
    droneModel = nil
    droneBody  = nil
    bodyGyro   = nil

    unmountRemote:FireServer(targetDrone)
end

-- 💥 РУЧНАЯ ДЕТОНАЦИЯ
function manualDetonate()
    if not mounted then return end
    mounted = false

    if motorSound then motorSound:Stop() end
    if windSound  then windSound:Stop()  end
    setPropWash(false)

    -- Белая вспышка на экране
    if flashFrame then
        flashFrame.BackgroundTransparency = 0.1
        TweenService:Create(flashFrame, TweenInfo.new(0.5), {BackgroundTransparency = 1}):Play()
    end

    camera.CameraType = Enum.CameraType.Custom
    if hudGui    then hudGui.Enabled    = false end
    if mobileGui then mobileGui.Enabled = false end
    setCharVisible(true)

    local targetDrone = droneModel
    droneModel = nil
    droneBody  = nil
    bodyGyro   = nil

    selfDestructRemote:FireServer(targetDrone)
end

-- ВЗРЫВ ПРИ СТОЛКНОВЕНИИ
function crashExplode()
    if not mounted or not droneBody then return end
    local pos = droneBody.Position
    mounted = false

    if motorSound then motorSound:Stop() end
    if windSound  then windSound:Stop()  end
    setPropWash(false)

    if flashFrame then
        flashFrame.BackgroundTransparency = 0.1
        TweenService:Create(flashFrame, TweenInfo.new(0.5), {BackgroundTransparency = 1}):Play()
    end

    camera.CameraType = Enum.CameraType.Custom
    if hudGui    then hudGui.Enabled    = false end
    if mobileGui then mobileGui.Enabled = false end
    setCharVisible(true)

    local targetDrone = droneModel
    droneModel = nil
    droneBody  = nil
    bodyGyro   = nil

    explodeRemote:FireServer(targetDrone, pos)
end

-- ────────────────────── ФИЗИЧЕСКИЙ ЦИКЛ ПОЛЁТА ─────────────
local CAM_TILT_RAD = math.rad(Config.CAM_TILT)

RunService.RenderStepped:Connect(function(dt)
    if not mounted or not droneBody or not bodyGyro then return end

    -- 1. Чтение ввода
    if not isMobile then
        readKeyboard()
    end

    -- 2. Рыскание (Yaw — поворот курса вокруг вертикальной оси)
    currentYaw = currentYaw - (yawIn * Config.YAW_SPEED * dt)

    -- 3. Тангаж и крен (Pitch & Roll — наклон дрона)
    local maxTiltRad = math.rad(Config.MAX_TILT_DEG)
    local desiredPitch = pitchIn * maxTiltRad
    local desiredRoll  = rollIn  * maxTiltRad

    local lerpK = math.clamp(Config.TILT_LERP_SPEED * dt, 0, 1)
    currentPitch = currentPitch + (desiredPitch - currentPitch) * lerpK
    currentRoll  = currentRoll  + (desiredRoll  - currentRoll)  * lerpK

    -- Устанавливаем ориентацию через BodyGyro
    local targetCF = CFrame.Angles(0, currentYaw, 0)
        * CFrame.Angles(currentPitch, 0, 0)
        * CFrame.Angles(0, 0, -currentRoll)
    bodyGyro.CFrame = targetCF

    -- 4. РЕАЛИСТИЧНАЯ ФИЗИКА ТЯГИ (Thrust Vector Physics)
    -- Тяга всегда направлена строго вверх относительно корпуса дрона (UpVector)!
    -- Когда дрон горизонтален: тяга вверх.
    -- Когда дрон наклонен вперед: тяга тянет вверх и ВПЕРЁД!
    -- Когда накренен: тяга тянет в сторону поворота!
    local currentVel = droneBody.AssemblyLinearVelocity

    local gravity = workspace.Gravity
    -- При throttle = 0.5: тяга ровно компенсирует гравитацию (hover)
    -- При throttle = 1.0: тяга = 2.8 × гравитации (мощный подъем/ускорение)
    -- При throttle = 0.0: тяга = 0 (падение)
    local hoverAccel = gravity
    local maxAccel   = gravity * Config.MAX_THRUST_MULT

    local thrustAccelMag = 0
    if throttleIn >= 0.5 then
        thrustAccelMag = hoverAccel + (throttleIn - 0.5) * 2 * (maxAccel - hoverAccel)
    else
        thrustAccelMag = throttleIn * 2 * hoverAccel
    end

    -- Вектор тяги вдоль крыши дрона
    local thrustAccelVector = targetCF.UpVector * thrustAccelMag

    -- Вектор гравитации (вниз)
    local gravityVector = Vector3.new(0, -gravity, 0)

    -- Сопротивление воздуха (плавный накат и предел скорости)
    local dragVector = -currentVel * Config.HORIZONTAL_DRAG

    -- Обновляем скорость физического тела
    local newVel = currentVel + (thrustAccelVector + gravityVector + dragVector) * dt
    droneBody.AssemblyLinearVelocity = newVel

    -- 5. Динамический звук мотора и ветра
    if motorSound then
        motorSound.PlaybackSpeed = 0.75 + (throttleIn * 0.8)
        motorSound.Volume = 0.35 + (throttleIn * 0.45)
    end
    if windSound then
        local spd = newVel.Magnitude
        windSound.Volume = math.clamp(spd / Config.MAX_SPEED * 0.8, 0, 0.8)
    end

    -- 6. FPV Камера — привязана к корпусу дрона с наклоном
    camera.CFrame = droneBody.CFrame
        * CFrame.new(0, 0.35, -1.3)
        * CFrame.Angles(-CAM_TILT_RAD, 0, 0)

    -- 7. Проверка границ
    local dPos = droneBody.Position
    local hDist = Vector2.new(dPos.X, dPos.Z).Magnitude
    local isOut = (hDist > Config.BOUNDS_RADIUS)
        or (dPos.Y < Config.BOUNDS_MIN_Y)
        or (dPos.Y > Config.BOUNDS_MAX_Y)

    if warningLabel then
        warningLabel.Visible = isOut
    end

    updateHUD()
end)

-- ────────────────────── REMOTE LISTENERS ───────────────────
mountRemote.OnClientEvent:Connect(function(drone)
    mountDrone(drone)
end)

player.CharacterAdded:Connect(function()
    if mounted then
        unmountDrone()
    end
end)

-- Инициализация интерфейсов
createHUD()
createMobileUI()
