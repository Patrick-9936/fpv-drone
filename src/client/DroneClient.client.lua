--[[
    DroneClient v8 — Ultra-Smooth & Stable FPV Drone
    - ИСПРАВЛЕНА ФИЗИКА (полная стабилизация высоты):
      * При наклоне вперёд дрон НЕ падает на землю, а ровно летит вперёд!
      * Газ не улетает в космос: плавный управляемый подъем (до 32 стад/с)
      * Центр стика = идеальное зависание на месте (Altitude Hold)
      * Скорость ограничена до комфортных 75 стад/с
    - ИСПРАВЛЕНЫ ВЗРЫВЫ:
      * Дрон НЕ взрывается при касании земли, травы или посадочной площадки
      * Взрыв происходит ТОЛЬКО при сильном лобовом ударе о стены/башни (> 45 стад/с)
        или по кнопке "💥 ПОДРЫВ"
    - Полный сброс ввода при каждом взятии дрона (никаких остаточных нажатий)
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
local currentPitch = 0   -- тангаж (>0 = нос опущен, полёт вперёд)
local currentRoll  = 0   -- крен (>0 = крен вправо)

-- Оси ввода
local pitchIn    = 0     -- +1 = вперёд (W), -1 = назад (S)
local rollIn     = 0     -- +1 = вправо (D), -1 = влево (A)
local yawIn      = 0     -- +1 = вправо (E), -1 = влево (Q)
local throttleIn = 0.5   -- 0.5 = hover, 1.0 = подъем, 0.0 = спуск

local keysDown   = {}
local isMobile   = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local takeoffGraceUntil = 0
local collisionLock = false

-- ────────────────────── ЗВУК ВЕТРА ─────────────────────────
local function setupWindAudio()
    if not windSound then
        windSound = Instance.new("Sound")
        windSound.Name = "DroneWindSFX"
        windSound.SoundId = "rbxasset://sounds/action_falling.mp3"
        windSound.Looped = true
        windSound.Volume = 0
        windSound.Parent = camera
    end
end
setupWindAudio()

-- ────────────────────── HUD И OSD ──────────────────────────
local hudGui, horizonBar, warningLabel, flashFrame

local function createHUD()
    if hudGui then hudGui:Destroy() end

    hudGui = Instance.new("ScreenGui")
    hudGui.Name = "DroneHUD"
    hudGui.ResetOnSpawn = false
    hudGui.Enabled = false
    hudGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    hudGui.Parent = player:WaitForChild("PlayerGui")

    -- Вспышка детонации
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

    -- Прицел
    local chV = Instance.new("Frame")
    chV.Size = UDim2.new(0, 2, 0, 24)
    chV.AnchorPoint = Vector2.new(0.5, 0.5)
    chV.Position = UDim2.new(0.5, 0, 0.5, 0)
    chV.BackgroundColor3 = Color3.fromRGB(0, 255, 120)
    chV.BackgroundTransparency = 0.2
    chV.BorderSizePixel = 0
    chV.Parent = hudGui

    local chH = Instance.new("Frame")
    chH.Size = UDim2.new(0, 24, 0, 2)
    chH.AnchorPoint = Vector2.new(0.5, 0.5)
    chH.Position = UDim2.new(0.5, 0, 0.5, 0)
    chH.BackgroundColor3 = Color3.fromRGB(0, 255, 120)
    chH.BackgroundTransparency = 0.2
    chH.BorderSizePixel = 0
    chH.Parent = hudGui

    -- Авиагоризонт
    horizonBar = Instance.new("Frame")
    horizonBar.Name = "Horizon"
    horizonBar.Size = UDim2.new(0, 100, 0, 2)
    horizonBar.AnchorPoint = Vector2.new(0.5, 0.5)
    horizonBar.Position = UDim2.new(0.5, 0, 0.5, 20)
    horizonBar.BackgroundColor3 = Color3.fromRGB(0, 255, 120)
    horizonBar.BackgroundTransparency = 0.4
    horizonBar.BorderSizePixel = 0
    horizonBar.Parent = hudGui

    -- Панель телеметрии
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
    makeLabel("Mode", 74)

    -- REC индикатор
    local topR = Instance.new("TextLabel")
    topR.Name = "TopRightOSD"
    topR.Size = UDim2.new(0, 140, 0, 26)
    topR.Position = UDim2.new(1, -150, 0, 14)
    topR.BackgroundTransparency = 1
    topR.TextColor3 = Color3.fromRGB(255, 60, 60)
    topR.Font = Enum.Font.Code
    topR.TextSize = 15
    topR.Text = "● REC  FPV STAB"
    topR.Parent = hudGui

    -- Предупреждение границы
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
    warningLabel.Text = "⚠️ СИГНАЛ ТЕРЯЕТСЯ — ВЫХОД ЗА КАРТУ"
    warningLabel.Visible = false
    warningLabel.Parent = hudGui
    Instance.new("UICorner", warningLabel).CornerRadius = UDim.new(0, 8)

    -- ВЕРХНИЕ КНОПКИ (ПОДРЫВ И ВЫХОД)
    local topControls = Instance.new("Frame")
    topControls.Name = "TopControls"
    topControls.Size = UDim2.new(0, 270, 0, 42)
    topControls.AnchorPoint = Vector2.new(0.5, 0)
    topControls.Position = UDim2.new(0.5, 0, 0, 12)
    topControls.BackgroundTransparency = 1
    topControls.Parent = hudGui

    -- 💥 КНОПКА РУЧНОЙ ДЕТОНАЦИИ
    local boomBtn = Instance.new("TextButton")
    boomBtn.Name = "BoomBtn"
    boomBtn.Size = UDim2.new(0, 135, 0, 38)
    boomBtn.Position = UDim2.new(0, 0, 0, 0)
    boomBtn.BackgroundColor3 = Color3.fromRGB(225, 30, 30)
    boomBtn.BackgroundTransparency = 0.15
    boomBtn.BorderSizePixel = 0
    boomBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    boomBtn.Font = Enum.Font.GothamBlack
    boomBtn.TextSize = 14
    boomBtn.Text = "💥 ПОДРЫВ"
    boomBtn.Parent = topControls
    Instance.new("UICorner", boomBtn).CornerRadius = UDim.new(0, 8)
    boomBtn.MouseButton1Click:Connect(function()
        if mounted then manualDetonate() end
    end)

    -- 🚪 ВЫХОД
    local exitBtn = Instance.new("TextButton")
    exitBtn.Name = "ExitBtn"
    exitBtn.Size = UDim2.new(0, 115, 0, 38)
    exitBtn.Position = UDim2.new(0, 145, 0, 0)
    exitBtn.BackgroundColor3 = Color3.fromRGB(55, 60, 70)
    exitBtn.BackgroundTransparency = 0.25
    exitBtn.BorderSizePixel = 0
    exitBtn.TextColor3 = Color3.fromRGB(235, 235, 235)
    exitBtn.Font = Enum.Font.GothamBold
    exitBtn.TextSize = 13
    exitBtn.Text = "🚪 ВЫХОД"
    exitBtn.Parent = topControls
    Instance.new("UICorner", exitBtn).CornerRadius = UDim.new(0, 8)
    exitBtn.MouseButton1Click:Connect(function()
        if mounted then unmountDrone() end
    end)

    if not isMobile then
        local hint = Instance.new("TextLabel")
        hint.Size = UDim2.new(0, 530, 0, 34)
        hint.AnchorPoint = Vector2.new(0.5, 1)
        hint.Position = UDim2.new(0.5, 0, 1, -12)
        hint.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        hint.BackgroundTransparency = 0.55
        hint.TextColor3 = Color3.fromRGB(220, 220, 220)
        hint.Font = Enum.Font.Code
        hint.TextSize = 13
        hint.Text = "W: Вперёд | S: Назад | A: Влево | D: Вправо | Q/E: Курс | Space/Shift: Газ | R: ПОДРЫВ"
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

    local mLbl = panel:FindFirstChild("Mode")
    if mLbl then mLbl.Text = "MODE [HOLD]" end

    if horizonBar then
        horizonBar.Rotation = math.deg(-currentRoll)
        horizonBar.Position = UDim2.new(0.5, 0, 0.5, -math.clamp(math.deg(currentPitch) * 1.2, -60, 60))
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

    local leftBase, lThumb  = createStick("LeftStick",  0, 0.04, "↑ ГАЗ / ← КУРС →")
    local rightBase, rThumb = createStick("RightStick", 1, 0.96, "↑ ВПЕРЁД / ← КРЕН →")
    leftThumb  = lThumb
    rightThumb = rThumb
end

-- Сброс сенсорных пальцев
local function clearAllTouches()
    leftTouchId = nil
    rightTouchId = nil
    leftJoyCenter = nil
    rightJoyCenter = nil
    pitchIn = 0
    rollIn = 0
    yawIn = 0
    throttleIn = 0.5
    if leftThumb then leftThumb.Position = UDim2.new(0.5, 0, 0.5, 0) end
    if rightThumb then rightThumb.Position = UDim2.new(0.5, 0, 0.5, 0) end
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
        local dz = 0.06

        -- ЛЕВЫЙ СТИК: Газ (Y) и Рыскание (X)
        if input == leftTouchId and leftJoyCenter then
            local delta = Vector2.new(input.Position.X, input.Position.Y) - leftJoyCenter
            local norm = delta / JOY_RADIUS
            if norm.Magnitude > 1 then norm = norm.Unit end

            local rawX = (math.abs(norm.X) > dz) and norm.X or 0
            local rawY = (math.abs(norm.Y) > dz) and norm.Y or 0

            yawIn = rawX * math.abs(rawX)
            -- Мягкий газ: 0.5 = hover, вверх до 1.0, вниз до 0.0
            throttleIn = math.clamp(0.5 - (rawY * 0.5), 0, 1)

            if leftThumb then
                leftThumb.Position = UDim2.new(0.5 + norm.X * 0.4, 0, 0.5 + norm.Y * 0.4, 0)
            end

        -- ПРАВЫЙ СТИК: Тангаж (Y) и Крен (X)
        elseif input == rightTouchId and rightJoyCenter then
            local delta = Vector2.new(input.Position.X, input.Position.Y) - rightJoyCenter
            local norm = delta / JOY_RADIUS
            if norm.Magnitude > 1 then norm = norm.Unit end

            local rawX = (math.abs(norm.X) > dz) and norm.X or 0
            local rawY = (math.abs(norm.Y) > dz) and norm.Y or 0

            rollIn  = rawX * math.abs(rawX)
            pitchIn = -rawY * math.abs(rawY) -- палец вверх = полёт ВПЕРЁД

            if rightThumb then
                rightThumb.Position = UDim2.new(0.5 + norm.X * 0.4, 0, 0.5 + norm.Y * 0.4, 0)
            end
        end
    end)

    local function resetLeft()
        leftTouchId = nil
        leftJoyCenter = nil
        yawIn = 0
        throttleIn = 0.5
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
    if keysDown[Enum.KeyCode.D] then rollIn  =  1 end
    if keysDown[Enum.KeyCode.A] then rollIn  = -1 end
    if keysDown[Enum.KeyCode.E] then yawIn   =  1 end
    if keysDown[Enum.KeyCode.Q] then yawIn   = -1 end

    if keysDown[Enum.KeyCode.Space] then
        throttleIn = math.min(throttleIn + 0.03, 1)
    elseif keysDown[Enum.KeyCode.LeftShift] then
        throttleIn = math.max(throttleIn - 0.03, 0)
    else
        if throttleIn > 0.52 then
            throttleIn = throttleIn - 0.015
        elseif throttleIn < 0.48 then
            throttleIn = throttleIn + 0.015
        end
    end
end

-- ────────────────────── ПЕРСОНАЖ И ВИДИМОСТЬ ───────────────
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

    -- Полный сброс всех осей ввода
    clearAllTouches()

    mounted = true
    collisionLock = false
    takeoffGraceUntil = tick() + Config.TAKEOFF_GRACE_TIME

    local _, ry, _ = droneBody.CFrame:ToOrientation()
    currentYaw   = ry
    currentPitch = 0
    currentRoll  = 0
    throttleIn   = 0.5

    -- Сбрасываем скорость дрона при старте чтобы он плавно взлетал
    pcall(function()
        droneBody.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        droneBody.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
    end)

    camera.CameraType = Enum.CameraType.Scriptable

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
        if not mounted or collisionLock then return end

        -- 5 секунд защиты при взлёте
        if tick() < takeoffGraceUntil then return end

        if hit:IsDescendantOf(droneModel) then return end
        if hit.Parent and hit.Parent:FindFirstChildOfClass("Humanoid") then return end

        -- Земля, трава и площадка НИКОГДА не взрывают дрон (позволяет мягко садиться/скользить!)
        local hName = hit.Name:lower()
        if hName:find("ground") or hName:find("pad") or hName:find("grass") or hName:find("floor") then
            return
        end
        if hit.Parent and hit.Parent.Name:lower():find("pad") then
            return
        end

        -- Взрыв ТОЛЬКО при реальном лобовом ударе о стены/башни/препятствия на высокой скорости
        local spd = droneBody.AssemblyLinearVelocity.Magnitude
        if spd >= Config.MIN_COLLISION_SPEED then
            collisionLock = true
            crashExplode()
        end
    end)
end

function unmountDrone()
    if not mounted then return end
    mounted = false

    clearAllTouches()

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

    clearAllTouches()

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

    selfDestructRemote:FireServer(targetDrone)
end

-- ВЗРЫВ ПРИ СТОЛКНОВЕНИИ
function crashExplode()
    if not mounted then return end
    mounted = false

    clearAllTouches()

    local pos = droneBody and droneBody.Position

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

-- ────────────────────── СТАБИЛЬНЫЙ ФИЗИЧЕСКИЙ ЦИКЛ ──────────
local CAM_TILT_RAD = math.rad(Config.CAM_TILT)

RunService.RenderStepped:Connect(function(dt)
    if not mounted or not droneBody or not bodyGyro then return end

    if not isMobile then
        readKeyboard()
    end

    -- 1. Рыскание (поворот курса 360°)
    currentYaw = currentYaw - (yawIn * Config.YAW_SPEED * dt)

    -- 2. Тангаж и Крен (плавный отклик)
    local maxTiltRad = math.rad(Config.MAX_TILT_DEG)
    local desiredPitch = pitchIn * maxTiltRad
    local desiredRoll  = rollIn  * maxTiltRad

    local lerpK = math.clamp(Config.TILT_LERP_SPEED * dt, 0, 1)
    currentPitch = currentPitch + (desiredPitch - currentPitch) * lerpK
    currentRoll  = currentRoll  + (desiredRoll  - currentRoll)  * lerpK

    local targetCF = CFrame.Angles(0, currentYaw, 0)
        * CFrame.Angles(-currentPitch, 0, 0)
        * CFrame.Angles(0, 0, -currentRoll)

    bodyGyro.CFrame = targetCF

    -- 3. ПОЛНАЯ СТАБИЛИЗАЦИЯ ВЫСОТЫ И СКОРОСТИ (Altitude Hold + Velocity Director)
    local currentVel = droneBody.AssemblyLinearVelocity

    -- Вертикальная скорость:
    -- throttle = 0.5 => targetVy = 0 (стабильное парение на высоте, дрон НЕ падает!)
    -- throttle > 0.5 => плавный подъем до +32 стад/с
    -- throttle < 0.5 => плавный спуск до -24 стад/с
    local targetVy = 0
    if throttleIn > 0.54 then
        targetVy = (throttleIn - 0.5) * 2 * Config.MAX_CLIMB_SPEED
    elseif throttleIn < 0.46 then
        targetVy = (throttleIn - 0.5) * 2 * Config.MAX_FALL_SPEED
    else
        targetVy = 0
    end

    -- Горизонтальная скорость:
    -- Наклон носа вниз (currentPitch > 0) плавно направляет дрон ВПЕРЁД
    -- Крен вправо (currentRoll > 0) плавно направляет дрон ВПРАВО
    local lookFlat = Vector3.new(targetCF.LookVector.X, 0, targetCF.LookVector.Z)
    if lookFlat.Magnitude > 0.01 then lookFlat = lookFlat.Unit else lookFlat = Vector3.new(0, 0, -1) end

    local rightFlat = Vector3.new(targetCF.RightVector.X, 0, targetCF.RightVector.Z)
    if rightFlat.Magnitude > 0.01 then rightFlat = rightFlat.Unit else rightFlat = Vector3.new(1, 0, 0) end

    local forwardRatio = currentPitch / maxTiltRad
    local rightRatio   = currentRoll  / maxTiltRad

    local targetHVel = (lookFlat * forwardRatio * Config.MAX_SPEED)
                     + (rightFlat * rightRatio * Config.MAX_SPEED)

    -- Плавная интерполяция к целевой скорости (без рывков и без падений)
    local lerpVy = currentVel.Y + (targetVy - currentVel.Y) * math.clamp(7 * dt, 0, 1)
    local lerpVx = currentVel.X + (targetHVel.X - currentVel.X) * math.clamp(5 * dt, 0, 1)
    local lerpVz = currentVel.Z + (targetHVel.Z - currentVel.Z) * math.clamp(5 * dt, 0, 1)

    droneBody.AssemblyLinearVelocity = Vector3.new(lerpVx, lerpVy, lerpVz)

    -- 4. Звуки
    if motorSound then
        local spdRatio = math.clamp(droneBody.AssemblyLinearVelocity.Magnitude / Config.MAX_SPEED, 0, 1)
        motorSound.PlaybackSpeed = 0.85 + (throttleIn * 0.4) + (spdRatio * 0.3)
        motorSound.Volume = 0.4 + (throttleIn * 0.3)
    end
    if windSound then
        local spd = droneBody.AssemblyLinearVelocity.Magnitude
        windSound.Volume = math.clamp(spd / Config.MAX_SPEED * 0.7, 0, 0.7)
    end

    -- 5. Камера FPV
    camera.CFrame = droneBody.CFrame
        * CFrame.new(0, 0.35, -1.3)
        * CFrame.Angles(-CAM_TILT_RAD, 0, 0)

    -- 6. Границы
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

createHUD()
createMobileUI()
