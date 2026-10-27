--[[
    DroneClient — FPV Quadcopter Controller v4
    Физика: VectorForce (тяга) + BodyGyro (ориентация)
    БЕЗ BodyVelocity — чистая физика Roblox
    Управление: левый стик = газ/рыскание, правый = тангаж/крен
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
local droneReadyRemote   = remotes:WaitForChild("DroneReady")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- ============================================================
--  СОСТОЯНИЕ ПОЛЁТА
-- ============================================================
local mounted      = false
local droneModel   = nil
local droneBody    = nil
local bodyGyro     = nil
local thrustForce  = nil   -- VectorForce
local motorSound   = nil
local windSound    = nil

-- Углы ориентации
local currentYaw   = 0
local currentPitch = 0
local currentRoll  = 0

-- Ввод (-1 до 1)
local pitchIn    = 0
local rollIn     = 0
local yawIn      = 0
local throttleIn = 0   -- 0 = нет газа, 1 = полный газ

local keysDown = {}
local collisionLock    = false
local outOfBoundsTimer = 0

local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- Константы физики
local GRAVITY        = workspace.Gravity          -- обычно 196.2
local DRONE_MASS     = 5                          -- кг (stub, пересчитываем при маунте)
local HOVER_MULT     = 1.05                       -- 1.05× вес = парение
local MAX_THRUST_MULT= 3.2                        -- полный газ = 3.2× вес

-- ============================================================
--  ЗВУКИ
-- ============================================================
local function setupAudio()
    if not windSound then
        windSound = Instance.new("Sound")
        windSound.Name = "DroneWindSFX"
        windSound.SoundId = "rbxasset://sounds/action_falling.mp3"
        windSound.Looped = true
        windSound.Volume = 0
        windSound.Parent = camera
    end
end
setupAudio()

-- ============================================================
--  HUD / FPV OSD
-- ============================================================
local hudGui, horizonBar, warningLabel, staticFrame

local function createHUD()
    if hudGui then hudGui:Destroy() end
    hudGui = Instance.new("ScreenGui")
    hudGui.Name = "DroneHUD"
    hudGui.ResetOnSpawn = false
    hudGui.Enabled = false
    hudGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    hudGui.Parent = player:WaitForChild("PlayerGui")

    staticFrame = Instance.new("Frame")
    staticFrame.Size = UDim2.new(1, 0, 1, 0)
    staticFrame.BackgroundColor3 = Color3.fromRGB(255,255,255)
    staticFrame.BackgroundTransparency = 1
    staticFrame.BorderSizePixel = 0
    staticFrame.Parent = hudGui

    -- Виньетка
    local vig = Instance.new("ImageLabel")
    vig.Size = UDim2.new(1, 0, 1, 0)
    vig.BackgroundTransparency = 1
    vig.Image = "rbxassetid://4576475446"
    vig.ImageColor3 = Color3.fromRGB(0,0,0)
    vig.ImageTransparency = 0.55
    vig.Parent = hudGui

    -- Прицел
    local chV = Instance.new("Frame")
    chV.Size = UDim2.new(0, 2, 0, 22)
    chV.AnchorPoint = Vector2.new(0.5, 0.5)
    chV.Position = UDim2.new(0.5, 0, 0.5, 0)
    chV.BackgroundColor3 = Color3.fromRGB(0,255,120)
    chV.BackgroundTransparency = 0.2
    chV.BorderSizePixel = 0
    chV.Parent = hudGui

    local chH = Instance.new("Frame")
    chH.Size = UDim2.new(0, 22, 0, 2)
    chH.AnchorPoint = Vector2.new(0.5, 0.5)
    chH.Position = UDim2.new(0.5, 0, 0.5, 0)
    chH.BackgroundColor3 = Color3.fromRGB(0,255,120)
    chH.BackgroundTransparency = 0.2
    chH.BorderSizePixel = 0
    chH.Parent = hudGui

    -- Искусственный горизонт
    horizonBar = Instance.new("Frame")
    horizonBar.Size = UDim2.new(0, 90, 0, 2)
    horizonBar.AnchorPoint = Vector2.new(0.5, 0.5)
    horizonBar.Position = UDim2.new(0.5, 0, 0.5, 20)
    horizonBar.BackgroundColor3 = Color3.fromRGB(0,255,120)
    horizonBar.BackgroundTransparency = 0.4
    horizonBar.BorderSizePixel = 0
    horizonBar.Parent = hudGui

    -- Инфо-панель
    local panel = Instance.new("Frame")
    panel.Name = "InfoPanel"
    panel.Size = UDim2.new(0, 155, 0, 110)
    panel.Position = UDim2.new(0, 12, 0, 12)
    panel.BackgroundColor3 = Color3.fromRGB(10,15,10)
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
        l.TextColor3 = Color3.fromRGB(0,255,120)
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

    -- REC (верхний правый угол)
    local topR = Instance.new("TextLabel")
    topR.Name = "TopRightOSD"
    topR.Size = UDim2.new(0, 130, 0, 26)
    topR.Position = UDim2.new(1, -140, 0, 12)
    topR.BackgroundTransparency = 1
    topR.TextColor3 = Color3.fromRGB(255,70,70)
    topR.Font = Enum.Font.Code
    topR.TextSize = 15
    topR.Text = "● REC  15.8V"
    topR.Parent = hudGui

    -- Предупреждение
    warningLabel = Instance.new("TextLabel")
    warningLabel.Size = UDim2.new(0, 360, 0, 40)
    warningLabel.AnchorPoint = Vector2.new(0.5, 0.5)
    warningLabel.Position = UDim2.new(0.5, 0, 0.25, 0)
    warningLabel.BackgroundColor3 = Color3.fromRGB(200,20,20)
    warningLabel.BackgroundTransparency = 0.25
    warningLabel.TextColor3 = Color3.fromRGB(255,255,255)
    warningLabel.Font = Enum.Font.GothamBold
    warningLabel.TextSize = 15
    warningLabel.Text = "⚠️ OUT OF BOUNDS"
    warningLabel.Visible = false
    warningLabel.Parent = hudGui
    Instance.new("UICorner", warningLabel).CornerRadius = UDim.new(0, 8)

    if not isMobile then
        local hint = Instance.new("TextLabel")
        hint.Size = UDim2.new(0, 480, 0, 36)
        hint.AnchorPoint = Vector2.new(0.5, 1)
        hint.Position = UDim2.new(0.5, 0, 1, -10)
        hint.BackgroundColor3 = Color3.fromRGB(0,0,0)
        hint.BackgroundTransparency = 0.5
        hint.TextColor3 = Color3.fromRGB(210,210,210)
        hint.Font = Enum.Font.Code
        hint.TextSize = 13
        hint.Text = "W/S: Тангаж | A/D: Крен | Q/E: Рыскание | Space/Shift: Газ | R: Сброс | F: Выход"
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
    if mLbl then mLbl.Text = "MODE [FPV]" end

    if horizonBar then
        horizonBar.Rotation = math.deg(-currentRoll)
        horizonBar.Position = UDim2.new(0.5, 0, 0.5,
            math.clamp(math.deg(currentPitch) * 1.2, -60, 60))
    end
end

-- ============================================================
--  МОБИЛЬНЫЕ ДЖОЙСТИКИ
-- ============================================================
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
        base.Position = UDim2.new(xPos, 0, 1, -30)
        base.BackgroundColor3 = Color3.fromRGB(255,255,255)
        base.BackgroundTransparency = 0.82
        base.BorderSizePixel = 0
        base.Parent = mobileGui
        Instance.new("UICorner", base).CornerRadius = UDim.new(1, 0)

        local thumb = Instance.new("Frame")
        thumb.Name = "Thumb"
        thumb.Size = UDim2.new(0, 54, 0, 54)
        thumb.AnchorPoint = Vector2.new(0.5, 0.5)
        thumb.Position = UDim2.new(0.5, 0, 0.5, 0)
        thumb.BackgroundColor3 = Color3.fromRGB(0,200,255)
        thumb.BackgroundTransparency = 0.3
        thumb.BorderSizePixel = 0
        thumb.Parent = base
        Instance.new("UICorner", thumb).CornerRadius = UDim.new(1, 0)

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, 0, 0, 18)
        lbl.Position = UDim2.new(0, 0, 0, -24)
        lbl.BackgroundTransparency = 1
        lbl.TextColor3 = Color3.fromRGB(220,220,220)
        lbl.Font = Enum.Font.GothamBold
        lbl.TextSize = 12
        lbl.Text = labelTxt
        lbl.Parent = base

        return base, thumb
    end

    local leftBase, lThumb  = createStick("LeftStick",  0, 0.04, "↑ ГАЗ / ← ЮЗ →")
    local rightBase, rThumb = createStick("RightStick", 1, 0.96, "↑ ТАНГАЖ / КРЕН →")
    leftThumb  = lThumb
    rightThumb = rThumb

    -- Кнопки сверху
    local topBar = Instance.new("Frame")
    topBar.Size = UDim2.new(0, 190, 0, 42)
    topBar.AnchorPoint = Vector2.new(0.5, 0)
    topBar.Position = UDim2.new(0.5, 0, 0, 10)
    topBar.BackgroundTransparency = 1
    topBar.Parent = mobileGui

    local function makeBtn(name, xOff, text, bgCol, onClick)
        local b = Instance.new("TextButton")
        b.Name = name
        b.Size = UDim2.new(0, 88, 0, 36)
        b.Position = UDim2.new(0, xOff, 0, 0)
        b.BackgroundColor3 = bgCol
        b.BackgroundTransparency = 0.25
        b.BorderSizePixel = 0
        b.TextColor3 = Color3.new(1,1,1)
        b.Font = Enum.Font.GothamBold
        b.TextSize = 13
        b.Text = text
        b.Parent = topBar
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
        b.MouseButton1Click:Connect(onClick)
        return b
    end

    makeBtn("ExitBtn",  0,  "🚪 ВЫХОД",  Color3.fromRGB(180,40,40), function()
        if mounted then unmountDrone() end
    end)
    makeBtn("ResetBtn", 100, "💥 СБРОС",  Color3.fromRGB(210,120,20), function()
        if mounted then
            selfDestructRemote:FireServer()
            unmountDrone()
        end
    end)
end

-- ============================================================
--  ОБРАБОТКА КАСАНИЙ
-- ============================================================
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
        local dz = 0.08

        if input == leftTouchId and leftJoyCenter then
            local delta = Vector2.new(input.Position.X, input.Position.Y) - leftJoyCenter
            local norm = delta / JOY_RADIUS
            if norm.Magnitude > 1 then norm = norm.Unit end
            local rawX = (math.abs(norm.X) > dz) and norm.X or 0
            local rawY = (math.abs(norm.Y) > dz) and norm.Y or 0
            yawIn = rawX * math.abs(rawX)
            -- вверх по стику = увеличение газа (0..1)
            throttleIn = math.clamp((-rawY + 1) / 2, 0, 1)
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
            pitchIn = -rawY * math.abs(rawY)
            if rightThumb then
                rightThumb.Position = UDim2.new(0.5 + norm.X * 0.4, 0, 0.5 + norm.Y * 0.4, 0)
            end
        end
    end)

    local function resetLeft()
        leftTouchId = nil; leftJoyCenter = nil
        yawIn = 0; throttleIn = 0
        if leftThumb then leftThumb.Position = UDim2.new(0.5, 0, 0.5, 0) end
    end
    local function resetRight()
        rightTouchId = nil; rightJoyCenter = nil
        rollIn = 0; pitchIn = 0
        if rightThumb then rightThumb.Position = UDim2.new(0.5, 0, 0.5, 0) end
    end
    UserInputService.InputEnded:Connect(function(input)
        if input == leftTouchId  then resetLeft()  end
        if input == rightTouchId then resetRight() end
    end)
end

-- ============================================================
--  КЛАВИАТУРА
-- ============================================================
UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.UserInputType == Enum.UserInputType.Keyboard then
        keysDown[input.KeyCode] = true
        if input.KeyCode == Enum.KeyCode.F and mounted then unmountDrone()
        elseif input.KeyCode == Enum.KeyCode.R and mounted then
            selfDestructRemote:FireServer()
            unmountDrone()
        end
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Keyboard then
        keysDown[input.KeyCode] = false
    end
end)

local function readKeyboard()
    pitchIn = 0; rollIn = 0; yawIn = 0

    if keysDown[Enum.KeyCode.W] then pitchIn =  1 end
    if keysDown[Enum.KeyCode.S] then pitchIn = -1 end
    if keysDown[Enum.KeyCode.A] then rollIn  = -1 end
    if keysDown[Enum.KeyCode.D] then rollIn  =  1 end
    if keysDown[Enum.KeyCode.Q] then yawIn   = -1 end
    if keysDown[Enum.KeyCode.E] then yawIn   =  1 end

    -- Газ: Space = полный, Shift = убрать газ, иначе держим предыдущее значение
    if keysDown[Enum.KeyCode.Space] then
        throttleIn = math.min(throttleIn + 0.04, 1)
    elseif keysDown[Enum.KeyCode.LeftShift] then
        throttleIn = math.max(throttleIn - 0.04, 0)
    else
        -- Без нажатия газ медленно падает до 0.5 (парение)
        if throttleIn > 0.52 then
            throttleIn = throttleIn - 0.015
        elseif throttleIn < 0.48 then
            throttleIn = throttleIn + 0.015
        end
    end
    throttleIn = math.clamp(throttleIn, 0, 1)
end

-- ============================================================
--  ВИДИМОСТЬ ПЕРСОНАЖА
-- ============================================================
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

-- ============================================================
--  ПРОПВОШ
-- ============================================================
local function setPropWash(enabled)
    if not droneModel then return end
    for _, p in droneModel:GetDescendants() do
        if p:IsA("ParticleEmitter") and p.Name == "Wash" then
            p.Enabled = enabled
        end
    end
end

-- ============================================================
--  МАУНТ / АНМАУНТ
-- ============================================================
function mountDrone(drone)
    if mounted then return end
    droneModel = drone
    droneBody  = drone and drone.PrimaryPart
    if not droneBody then return end

    bodyGyro    = droneBody:FindFirstChild("DroneGyro")
    thrustForce = droneBody:FindFirstChild("Thrust")
    motorSound  = droneBody:FindFirstChild("MotorSound")

    if not bodyGyro or not thrustForce then return end

    mounted = true
    collisionLock = false
    outOfBoundsTimer = 0

    -- Считаем массу тела (все части модели)
    DRONE_MASS = 0
    for _, p in droneModel:GetDescendants() do
        if p:IsA("BasePart") then
            DRONE_MASS = DRONE_MASS + p:GetMass()
        end
    end
    if DRONE_MASS < 0.1 then DRONE_MASS = 5 end

    -- Начальные углы
    local _, ry, _ = droneBody.CFrame:ToOrientation()
    currentYaw   = ry
    currentPitch = 0
    currentRoll  = 0
    throttleIn   = 0.5  -- стартуем с режима парения

    -- Камера
    camera.CameraType = Enum.CameraType.Scriptable

    -- Звук
    if motorSound then
        motorSound.Volume = 0.5
        motorSound.PlaybackSpeed = 0.9
        motorSound:Play()
    end
    if windSound then windSound.Volume = 0; windSound:Play() end

    setPropWash(true)
    setCharVisible(false)
    if hudGui then hudGui.Enabled = true end
    if mobileGui then mobileGui.Enabled = true end
    if warningLabel then warningLabel.Visible = false end

    -- Коллизия
    droneBody.Touched:Connect(function(hit)
        if not mounted or collisionLock then return end
        if hit:IsDescendantOf(droneModel) then return end
        if hit.Parent and hit.Parent:FindFirstChildOfClass("Humanoid") then return end
        local spd = droneBody.AssemblyLinearVelocity.Magnitude
        if spd >= Config.MIN_COLLISION_SPEED then
            collisionLock = true
            explodeDrone()
        end
    end)
end

function unmountDrone()
    if not mounted then return end
    mounted = false

    -- Убрать тягу
    if thrustForce then thrustForce.Force = Vector3.new(0, 0, 0) end
    if motorSound then motorSound:Stop() end
    if windSound  then windSound:Stop()  end
    setPropWash(false)

    camera.CameraType = Enum.CameraType.Custom
    if hudGui    then hudGui.Enabled    = false end
    if mobileGui then mobileGui.Enabled = false end
    setCharVisible(true)
    unmountRemote:FireServer()

    droneModel  = nil
    droneBody   = nil
    bodyGyro    = nil
    thrustForce = nil
end

function explodeDrone()
    if not droneBody then return end
    local pos = droneBody.Position
    mounted = false

    if thrustForce then thrustForce.Force = Vector3.new(0, 0, 0) end
    if motorSound then motorSound:Stop() end
    if windSound  then windSound:Stop()  end

    -- Экранный стат
    if staticFrame then
        staticFrame.BackgroundTransparency = 0.2
        task.delay(0.2, function()
            TweenService:Create(staticFrame, TweenInfo.new(0.6),
                {BackgroundTransparency = 1}):Play()
        end)
    end

    camera.CameraType = Enum.CameraType.Custom
    if hudGui    then hudGui.Enabled    = false end
    if mobileGui then mobileGui.Enabled = false end
    setCharVisible(true)
    explodeRemote:FireServer(pos)

    droneModel  = nil
    droneBody   = nil
    bodyGyro    = nil
    thrustForce = nil
end

-- ============================================================
--  ПОЛЁТНЫЙ ЦИКЛ (RenderStepped)
-- ============================================================
local CAM_TILT = math.rad(Config.CAM_TILT)

RunService.RenderStepped:Connect(function(dt)
    if not mounted or not droneBody or not bodyGyro or not thrustForce then return end

    -- 1. Ввод
    if not isMobile then readKeyboard() end

    -- 2. Рыскание
    currentYaw = currentYaw - (yawIn * Config.YAW_SPEED * dt)

    -- 3. Тангаж и крен (Stabilized mode)
    local maxTilt = math.rad(Config.MAX_TILT_DEG)
    local desiredPitch = pitchIn * maxTilt
    local desiredRoll  = rollIn  * maxTilt

    local lerpK = math.clamp(Config.TILT_LERP_SPEED * dt, 0, 1)
    currentPitch = currentPitch + (desiredPitch - currentPitch) * lerpK
    currentRoll  = currentRoll  + (desiredRoll  - currentRoll)  * lerpK

    -- Целевая ориентация
    local targetCF = CFrame.Angles(0, currentYaw, 0)
        * CFrame.Angles(currentPitch, 0, 0)
        * CFrame.Angles(0, 0, -currentRoll)
    bodyGyro.CFrame = targetCF

    -- 4. ТЯГА (VectorForce) — главное исправление!
    --    Тяга = throttleIn (0..1) маппируется:
    --      0.0 → 0 (дрон падает)
    --      0.5 → hover (компенсация гравитации)
    --      1.0 → MAX_THRUST_MULT × вес
    local hoverForce = DRONE_MASS * GRAVITY * HOVER_MULT
    local maxForce   = DRONE_MASS * GRAVITY * MAX_THRUST_MULT
    local thrustMag  = hoverForce + (throttleIn - 0.5) * 2 * (maxForce - hoverForce)
    thrustMag = math.clamp(thrustMag, 0, maxForce)

    -- VectorForce в локальных координатах Attachment (вверх = +Y локально)
    thrustForce.Force = Vector3.new(0, thrustMag, 0)

    -- 5. Звук
    if motorSound then
        motorSound.PlaybackSpeed = 0.8 + throttleIn * 0.7
        motorSound.Volume = 0.3 + throttleIn * 0.5
    end
    local spd = droneBody.AssemblyLinearVelocity.Magnitude
    if windSound then
        windSound.Volume = math.clamp(spd / Config.MAX_SPEED * 0.8, 0, 0.8)
    end

    -- 6. FPV камера
    camera.CFrame = droneBody.CFrame
        * CFrame.new(0, 0.5, -1.5)
        * CFrame.Angles(-CAM_TILT, 0, 0)

    -- 7. Границы
    local dpos = droneBody.Position
    local horiz = Vector2.new(dpos.X, dpos.Z).Magnitude
    local isOut = (horiz > Config.BOUNDS_RADIUS)
        or (dpos.Y < Config.BOUNDS_MIN_Y)
        or (dpos.Y > Config.BOUNDS_MAX_Y)

    if isOut then
        outOfBoundsTimer = outOfBoundsTimer + dt
        if warningLabel then
            warningLabel.Visible = true
            warningLabel.Text = string.format(
                "⚠️ СИГНАЛ ПОТЕРЯН — ПОДРЫВ ЧЕРЕЗ %.1f с",
                math.max(0, Config.OUT_OF_BOUNDS_TIME - outOfBoundsTimer))
        end
        if outOfBoundsTimer >= Config.OUT_OF_BOUNDS_TIME then
            collisionLock = true
            explodeDrone()
        end
    else
        outOfBoundsTimer = 0
        if warningLabel then warningLabel.Visible = false end
    end

    updateHUD()
end)

-- ============================================================
--  REMOTE HANDLERS
-- ============================================================
mountRemote.OnClientEvent:Connect(function(drone)
    mountDrone(drone)
end)

droneReadyRemote.OnClientEvent:Connect(function()
    collisionLock = false
end)

player.CharacterAdded:Connect(function()
    if mounted then unmountDrone() end
end)

-- ============================================================
--  ИНИЦИАЛИЗАЦИЯ GUI
-- ============================================================
createHUD()
createMobileUI()
