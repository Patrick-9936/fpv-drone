--[[
    DroneClient v10 — клиент только управляет и снимает.

    Что изменилось:
      * Клиент больше НЕ трогает физику (никаких BodyGyro / AssemblyLinearVelocity).
        Он читает стики 30 раз в секунду и отправляет их на сервер (DroneInput).
      * Сервер двигает дрон через FlightModel и присылает готовую ориентацию, поэтому
        дрон больше не «проваливается» сквозь площадку и не теряет высоту при наклоне.
      * FPV-камера сглаживается по CFrame дрона (lerp), чтобы репликация не выглядела
        дёрганой.
      * Сервер сам сообщает о потере дрона (DroneLost) — клиент корректно выходит из
        режима пилота, а не остаётся в мёртвой камере.
]]

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local Config  = require(ReplicatedStorage:WaitForChild("DroneConfig"))
local remotes = ReplicatedStorage:WaitForChild("DroneRemotes")

local mountRemote        = remotes:WaitForChild("MountDrone")
local lostRemote         = remotes:WaitForChild("DroneLost")
local inputRemote        = remotes:WaitForChild("DroneInput")
local unmountRemote      = remotes:WaitForChild("UnmountDrone")
local selfDestructRemote = remotes:WaitForChild("SelfDestruct")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- ────────────────────── СОСТОЯНИЕ ──────────────────────────
local mounted    = false
local droneModel = nil
local droneBody  = nil
local motorSound = nil
local windSound  = nil

local pitchIn    = 0     -- +1 = вперёд
local rollIn     = 0     -- +1 = вправо
local yawIn      = 0     -- +1 = вправо
local throttleIn = 0.5   -- 0.5 = удержание высоты

local keysDown   = {}
local isMobile   = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local inputAccum = 0

local smoothCF   = nil
local lastPos    = nil
local smoothSpeed = 0

-- forward declarations (используются в кнопках HUD)
local unmountDrone
local manualDetonate
local localUnmount

-- ────────────────────── ЗВУК ВЕТРА ─────────────────────────
windSound = Instance.new("Sound")
windSound.Name = "DroneWindSFX"
windSound.SoundId = "rbxasset://sounds/action_falling.mp3"
windSound.Looped = true
windSound.Volume = 0
windSound.Parent = camera

-- ────────────────────── HUD И OSD ──────────────────────────
local hudGui, horizonBar, warningLabel, flashFrame, statusLabel

local function createHUD()
    if hudGui then hudGui:Destroy() end

    hudGui = Instance.new("ScreenGui")
    hudGui.Name = "DroneHUD"
    hudGui.ResetOnSpawn = false
    hudGui.Enabled = false
    hudGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    hudGui.Parent = player:WaitForChild("PlayerGui")

    -- Вспышка (детонация / попадание)
    flashFrame = Instance.new("Frame")
    flashFrame.Name = "Flash"
    flashFrame.Size = UDim2.new(1, 0, 1, 0)
    flashFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    flashFrame.BackgroundTransparency = 1
    flashFrame.BorderSizePixel = 0
    flashFrame.ZIndex = 5
    flashFrame.Parent = hudGui

    -- Виньетка
    local vig = Instance.new("ImageLabel")
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

    local topR = Instance.new("TextLabel")
    topR.Size = UDim2.new(0, 140, 0, 26)
    topR.Position = UDim2.new(1, -150, 0, 14)
    topR.BackgroundTransparency = 1
    topR.TextColor3 = Color3.fromRGB(255, 60, 60)
    topR.Font = Enum.Font.Code
    topR.TextSize = 15
    topR.Text = "● REC  FPV"
    topR.Parent = hudGui

    -- Баннер предупреждения / статуса
    warningLabel = Instance.new("TextLabel")
    warningLabel.Name = "WarningBanner"
    warningLabel.Size = UDim2.new(0, 380, 0, 38)
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

    local statusLabel = Instance.new("TextLabel")
    statusLabel.Name = "StatusBanner"
    statusLabel.Size = UDim2.new(0, 380, 0, 54)
    statusLabel.AnchorPoint = Vector2.new(0.5, 0.5)
    statusLabel.Position = UDim2.new(0.5, 0, 0.42, 0)
    statusLabel.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
    statusLabel.BackgroundTransparency = 0.35
    statusLabel.TextColor3 = Color3.fromRGB(255, 120, 120)
    statusLabel.Font = Enum.Font.GothamBlack
    statusLabel.TextSize = 20
    statusLabel.Text = ""
    statusLabel.Visible = false
    statusLabel.Parent = hudGui
    Instance.new("UICorner", statusLabel).CornerRadius = UDim.new(0, 8)

    -- Кнопки
    local topControls = Instance.new("Frame")
    topControls.Name = "TopControls"
    topControls.Size = UDim2.new(0, 270, 0, 42)
    topControls.AnchorPoint = Vector2.new(0.5, 0)
    topControls.Position = UDim2.new(0.5, 0, 0, 12)
    topControls.BackgroundTransparency = 1
    topControls.Parent = hudGui

    local boomBtn = Instance.new("TextButton")
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

    local exitBtn = Instance.new("TextButton")
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
        hint.Size = UDim2.new(0, 560, 0, 34)
        hint.AnchorPoint = Vector2.new(0.5, 1)
        hint.Position = UDim2.new(0.5, 0, 1, -12)
        hint.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        hint.BackgroundTransparency = 0.55
        hint.TextColor3 = Color3.fromRGB(220, 220, 220)
        hint.Font = Enum.Font.Code
        hint.TextSize = 13
        hint.Text = "W/S: вперёд-назад | A/D: крен | Q/E: курс | Space/Shift: газ | R: подрыв | F: выход"
        hint.Parent = hudGui
        Instance.new("UICorner", hint).CornerRadius = UDim.new(0, 6)
    end
end

local function updateHUD()
    if not hudGui or not hudGui.Enabled or not droneBody then return end
    local panel = hudGui:FindFirstChild("InfoPanel")
    if not panel then return end

    local sLbl = panel:FindFirstChild("Speed")
    if sLbl then sLbl.Text = string.format("SPD  %d st/s", math.floor(smoothSpeed + 0.5)) end

    local aLbl = panel:FindFirstChild("Alt")
    if aLbl then aLbl.Text = string.format("ALT  %d st", math.floor(droneBody.Position.Y + 0.5)) end

    local tLbl = panel:FindFirstChild("Thr")
    if tLbl then tLbl.Text = string.format("THR  %d %%", math.floor(throttleIn * 100 + 0.5)) end

    local mLbl = panel:FindFirstChild("Mode")
    if mLbl then mLbl.Text = "MODE [HOLD]" end

    if horizonBar then
        local _, _, roll = droneBody.CFrame:ToOrientation()
        local pitch = math.asin(math.clamp(droneBody.CFrame.LookVector.Y, -1, 1))
        horizonBar.Rotation = math.deg(roll)
        horizonBar.Position = UDim2.new(0.5, 0, 0.5, -math.clamp(math.deg(pitch) * 1.2, -60, 60))
    end
end

-- ────────────────────── СТИКИ (МОБИЛА) ─────────────────────
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

    local _, lThumb  = createStick("LeftStick",  0, 0.04, "↑ ГАЗ / ← КУРС →")
    local _, rThumb  = createStick("RightStick", 1, 0.96, "↑ ВПЕРЁД / ← КРЕН →")
    leftThumb  = lThumb
    rightThumb = rThumb
end

local function resetInputs()
    leftTouchId = nil
    rightTouchId = nil
    leftJoyCenter = nil
    rightJoyCenter = nil
    pitchIn = 0
    rollIn = 0
    yawIn = 0
    throttleIn = 0.5
    keysDown = {}
    if leftThumb then leftThumb.Position = UDim2.new(0.5, 0, 0.5, 0) end
    if rightThumb then rightThumb.Position = UDim2.new(0.5, 0, 0.5, 0) end
end

-- ────────────────────── ВВОД ──────────────────────────────
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

        if input == leftTouchId and leftJoyCenter then
            local delta = Vector2.new(input.Position.X, input.Position.Y) - leftJoyCenter
            local norm = delta / JOY_RADIUS
            if norm.Magnitude > 1 then norm = norm.Unit end

            local rawX = (math.abs(norm.X) > dz) and norm.X or 0
            local rawY = (math.abs(norm.Y) > dz) and norm.Y or 0

            yawIn = rawX * math.abs(rawX)
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
            pitchIn = -rawY * math.abs(rawY)   -- палец вверх = полёт вперёд

            if rightThumb then
                rightThumb.Position = UDim2.new(0.5 + norm.X * 0.4, 0, 0.5 + norm.Y * 0.4, 0)
            end
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input == leftTouchId then
            leftTouchId = nil
            leftJoyCenter = nil
            yawIn = 0
            throttleIn = 0.5
            if leftThumb then leftThumb.Position = UDim2.new(0.5, 0, 0.5, 0) end
        end
        if input == rightTouchId then
            rightTouchId = nil
            rightJoyCenter = nil
            rollIn = 0
            pitchIn = 0
            if rightThumb then rightThumb.Position = UDim2.new(0.5, 0, 0.5, 0) end
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
        -- плавный возврат к удержанию высоты
        if throttleIn > 0.52 then
            throttleIn = throttleIn - 0.015
        elseif throttleIn < 0.48 then
            throttleIn = throttleIn + 0.015
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

-- Свой дрон в FPV-режиме не должен быть виден: иначе при крене/тангаже в кадр
-- лезут рама, лучи и пропеллеры. Прячем только локально (у других он виден).
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

local function flash(color, transparency)
    if not flashFrame then return end
    flashFrame.BackgroundColor3 = color or Color3.fromRGB(255, 255, 255)
    flashFrame.BackgroundTransparency = transparency or 0.1
    TweenService:Create(flashFrame, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
end

local function showStatus(text)
    if not hudGui then return end
    local lbl = hudGui:FindFirstChild("StatusBanner")
    if not lbl then return end
    lbl.Text = text
    lbl.Visible = true
    task.delay(2.5, function()
        if lbl then lbl.Visible = false end
    end)
end

-- Аварийный выход: работает даже если клиент потерял своё состояние,
-- иначе игрок остаётся в мёртвой FPV-камере и не может взять новый дрон
local function forceExit(text)
    localUnmount(false, nil)
    camera.CameraType = Enum.CameraType.Custom
    if hudGui    then hudGui.Enabled    = false end
    if mobileGui then mobileGui.Enabled = false end
    setCharVisible(true)
    if text then showStatus(text) end
end

-- ────────────────────── ВЫХОД (ЛОКАЛЬНЫЙ) ──────────────────
localUnmount = function(notifyServer, lostReason)
    if not mounted then return end
    mounted = false

    resetInputs()

    setOwnModelVisible(true)

    if motorSound then motorSound:Stop() end
    if windSound  then windSound:Stop()  end
    setPropWash(false)

    camera.CameraType = Enum.CameraType.Custom
    if hudGui    then hudGui.Enabled    = false end
    if mobileGui then mobileGui.Enabled = false end
    setCharVisible(true)
    if warningLabel then warningLabel.Visible = false end

    droneModel = nil
    droneBody  = nil
    motorSound = nil
    smoothCF   = nil
    lastPos    = nil
    smoothSpeed = 0

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
    -- без локальной вспышки: единственный эффект пришлёт сервер (DroneLost),
    -- иначе взрыв визуально двоится
    localUnmount(false, nil)
    selfDestructRemote:FireServer()
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
    setOwnModelVisible(false)   -- свой корпус в кадре не нужен

    if hudGui    then hudGui.Enabled    = true end
    if mobileGui then mobileGui.Enabled = true end
    if warningLabel then warningLabel.Visible = false end

    -- сразу отправляем нейтральный ввод, чтобы сервер не держал старое значение
    inputRemote:FireServer(0, 0, 0, 0.5)
end

-- ────────────────────── ГЛАВНЫЙ ЦИКЛ ───────────────────────
local CAM_TILT_RAD = math.rad(Config.CAM_TILT)

RunService.RenderStepped:Connect(function(dt)
    if not mounted then return end

    -- Дрон исчез (взорван сервером / удалён) — выходим из режима пилота
    if not droneBody or not droneBody.Parent then
        forceExit("ДРОН ПОТЕРЯН")
        return
    end

    if not isMobile then
        readKeyboard()
    end

    -- 1. Отправляем стики на сервер ~30 раз в секунду
    inputAccum = inputAccum + dt
    if inputAccum >= (1 / 30) then
        inputAccum = 0
        inputRemote:FireServer(pitchIn, rollIn, yawIn, throttleIn)
    end

    -- 2. Плавная камера: догоняем CFrame дрона, чтобы репликация не дёргалась
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
        motorSound.PlaybackSpeed = 0.85 + (throttleIn * 0.45) + math.clamp(smoothSpeed / Config.MAX_SPEED, 0, 1) * 0.25
        motorSound.Volume = 0.35 + (throttleIn * 0.3)
    end
    windSound.Volume = math.clamp(smoothSpeed / Config.MAX_SPEED * 0.7, 0, 0.7)

    -- 5. Предупреждение о границе
    local hDist = Vector2.new(pos.X, pos.Z).Magnitude
    local isOut = hDist > (Config.BOUNDS_RADIUS - 40)
        or pos.Y > (Config.BOUNDS_MAX_Y - 40)
    if warningLabel then
        warningLabel.Visible = isOut and math.floor(tick() * 2) % 2 == 0
    end

    updateHUD()
end)

-- ────────────────────── REMOTE LISTENERS ───────────────────
mountRemote.OnClientEvent:Connect(function(drone)
    mountDrone(drone)
end)

lostRemote.OnClientEvent:Connect(function(reason)
    local text
    if reason == "manual" then
        text = "💥 ДРОН ПОДОРВАН"
    elseif reason == "borders" then
        text = "📡 СИГНАЛ ПОТЕРЯН — ДРОН УЛЕТЕЛ ЗА КАРТУ"
    else
        text = "💥 ДРОН РАЗБИЛСЯ"
    end
    flash(Color3.fromRGB(255, 90, 60), 0.15)
    forceExit(text)   -- всегда, даже если клиент уже потерял своё состояние
end)

player.CharacterAdded:Connect(function()
    if mounted then
        localUnmount(true, nil)
    end
end)

createHUD()
createMobileUI()
