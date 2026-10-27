--[[
    DroneClient — Ultra-Smooth FPV Quadcopter Controller
    Features:
    - Stabilized (Angle Mode) + Acro (360 manual) modes
    - Auto-hover assist with smooth climb/descent
    - Dynamic motor audio (pitch scales with throttle) & wind sound
    - Prop wash particle effects
    - FPV OSD with artificial horizon, speed, altitude, battery
    - Boundary warning with signal loss static & auto-return
    - Exit and Self-Destruct / Respawn buttons
    - Fixed responsive mobile dual-stick touch zones
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
--  FLIGHT STATE
-- ============================================================
local mounted      = false
local flightMode   = "STAB"  -- "STAB" (self-leveling) or "ACRO" (full 360 rate)
local droneModel   = nil
local droneBody    = nil
local bodyGyro     = nil
local bodyVelocity = nil
local motorSound   = nil
local windSound    = nil

-- Orientations & Rotations
local currentYaw   = 0     -- radians (heading around Y)
local currentPitch = 0     -- radians
local currentRoll  = 0     -- radians
local acroRotation = CFrame.new()

-- Input axes (-1 to 1)
local pitchIn   = 0
local rollIn    = 0
local yawIn     = 0
local throttleIn= 0

local keysDown = {}
local collisionLock = false
local outOfBoundsTimer = 0

local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

-- ============================================================
--  WIND AUDIO SETUP
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
--  HUD & FPV OSD
-- ============================================================
local hudGui
local horizonBar
local warningLabel
local staticFrame

local function createHUD()
	if hudGui then hudGui:Destroy() end

	hudGui = Instance.new("ScreenGui")
	hudGui.Name = "DroneHUD"
	hudGui.ResetOnSpawn = false
	hudGui.Enabled = false
	hudGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	hudGui.Parent = player:WaitForChild("PlayerGui")

	-- Static overlay (for out-of-bounds warning / explosion)
	staticFrame = Instance.new("Frame")
	staticFrame.Name = "StaticFX"
	staticFrame.Size = UDim2.new(1, 0, 1, 0)
	staticFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	staticFrame.BackgroundTransparency = 1
	staticFrame.BorderSizePixel = 0
	staticFrame.Parent = hudGui

	-- Vignette corners (subtle dark edges)
	local vig = Instance.new("ImageLabel")
	vig.Name = "Vignette"
	vig.Size = UDim2.new(1, 0, 1, 0)
	vig.BackgroundTransparency = 1
	vig.Image = "rbxassetid://4576475446"
	vig.ImageColor3 = Color3.fromRGB(0, 0, 0)
	vig.ImageTransparency = 0.55
	vig.Parent = hudGui

	-- Crosshair / Reticle
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

	-- Artificial Horizon Line (rotates with roll)
	horizonBar = Instance.new("Frame")
	horizonBar.Name = "Horizon"
	horizonBar.Size = UDim2.new(0, 90, 0, 2)
	horizonBar.AnchorPoint = Vector2.new(0.5, 0.5)
	horizonBar.Position = UDim2.new(0.5, 0, 0.5, 20)
	horizonBar.BackgroundColor3 = Color3.fromRGB(0, 255, 120)
	horizonBar.BackgroundTransparency = 0.4
	horizonBar.BorderSizePixel = 0
	horizonBar.Parent = hudGui

	-- Info Panel (Top Left)
	local panel = Instance.new("Frame")
	panel.Name = "InfoPanel"
	panel.Size = UDim2.new(0, 150, 0, 105)
	panel.Position = UDim2.new(0, 12, 0, 12)
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

	-- Battery / Rec Indicator (Top Right)
	local topR = Instance.new("TextLabel")
	topR.Name = "TopRightOSD"
	topR.Size = UDim2.new(0, 130, 0, 26)
	topR.Position = UDim2.new(1, -140, 0, 12)
	topR.BackgroundTransparency = 1
	topR.TextColor3 = Color3.fromRGB(255, 70, 70)
	topR.Font = Enum.Font.Code
	topR.TextSize = 15
	topR.Text = "● REC  15.8V"
	topR.Parent = hudGui

	-- Warning Banner (Center Screen)
	warningLabel = Instance.new("TextLabel")
	warningLabel.Name = "WarningBanner"
	warningLabel.Size = UDim2.new(0, 360, 0, 40)
	warningLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	warningLabel.Position = UDim2.new(0.5, 0, 0.25, 0)
	warningLabel.BackgroundColor3 = Color3.fromRGB(200, 20, 20)
	warningLabel.BackgroundTransparency = 0.25
	warningLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	warningLabel.Font = Enum.Font.GothamBold
	warningLabel.TextSize = 15
	warningLabel.Text = "⚠️ OUT OF BOUNDS - RETURNING"
	warningLabel.Visible = false
	warningLabel.Parent = hudGui
	Instance.new("UICorner", warningLabel).CornerRadius = UDim.new(0, 8)

	-- Desktop Controls Hint
	if not isMobile then
		local hint = Instance.new("TextLabel")
		hint.Size = UDim2.new(0, 460, 0, 36)
		hint.AnchorPoint = Vector2.new(0.5, 1)
		hint.Position = UDim2.new(0.5, 0, 1, -10)
		hint.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		hint.BackgroundTransparency = 0.5
		hint.TextColor3 = Color3.fromRGB(210, 210, 210)
		hint.Font = Enum.Font.Code
		hint.TextSize = 13
		hint.Text = "W/S: Pitch | A/D: Roll | Q/E: Yaw | Space/Shift: Height | M: Mode | R: Reset | F: Exit"
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
	local thrVal = math.floor(math.clamp((throttleIn + 1) / 2, 0, 1) * 100 + 0.5)

	local sLbl = panel:FindFirstChild("Speed")
	if sLbl then sLbl.Text = string.format("SPD  %d st/s", spd) end

	local aLbl = panel:FindFirstChild("Alt")
	if aLbl then aLbl.Text = string.format("ALT  %d st", alt) end

	local tLbl = panel:FindFirstChild("Thr")
	if tLbl then tLbl.Text = string.format("THR  %d %%", thrVal) end

	local mLbl = panel:FindFirstChild("Mode")
	if mLbl then mLbl.Text = string.format("MODE [%s]", flightMode) end

	-- Artificial horizon rotation
	if horizonBar then
		horizonBar.Rotation = math.deg(-currentRoll)
		horizonBar.Position = UDim2.new(0.5, 0, 0.5, math.clamp(math.deg(currentPitch) * 1.2, -60, 60))
	end
end

-- ============================================================
--  RESPONSIVE MOBILE TOUCH CONTROLS
-- ============================================================
local mobileGui
local leftJoyCenter, rightJoyCenter
local leftTouchId, rightTouchId
local leftThumb, rightThumb
local JOY_RADIUS = 50 -- pixels

local function createMobileUI()
	if not isMobile then return end
	if mobileGui then mobileGui:Destroy() end

	mobileGui = Instance.new("ScreenGui")
	mobileGui.Name = "MobileControls"
	mobileGui.ResetOnSpawn = false
	mobileGui.Enabled = false
	mobileGui.Parent = player:WaitForChild("PlayerGui")

	-- Helper for fixed-zone touch joystick
	local function createStick(name, xAnchor, xPos, labelTxt)
		local base = Instance.new("Frame")
		base.Name = name .. "Base"
		base.Size = UDim2.new(0, 130, 0, 130)
		base.AnchorPoint = Vector2.new(xAnchor, 1)
		base.Position = UDim2.new(xPos, 0, 1, -25)
		base.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		base.BackgroundTransparency = 0.82
		base.BorderSizePixel = 0
		base.Parent = mobileGui
		Instance.new("UICorner", base).CornerRadius = UDim.new(1, 0)

		local thumb = Instance.new("Frame")
		thumb.Name = "Thumb"
		thumb.Size = UDim2.new(0, 50, 0, 50)
		thumb.AnchorPoint = Vector2.new(0.5, 0.5)
		thumb.Position = UDim2.new(0.5, 0, 0.5, 0)
		thumb.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		thumb.BackgroundTransparency = 0.35
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

	local leftBase, lThumb = createStick("LeftStick", 0, 0.04, "CLIMB / YAW")
	local rightBase, rThumb = createStick("RightStick", 1, 0.96, "PITCH / ROLL")
	leftThumb = lThumb
	rightThumb = rThumb

	-- TOP BUTTONS BAR
	local topBar = Instance.new("Frame")
	topBar.Name = "TopButtons"
	topBar.Size = UDim2.new(0, 280, 0, 42)
	topBar.AnchorPoint = Vector2.new(0.5, 0)
	topBar.Position = UDim2.new(0.5, 0, 0, 10)
	topBar.BackgroundTransparency = 1
	topBar.Parent = mobileGui

	local function makeBtn(name, xOrder, text, bgCol, onClick)
		local b = Instance.new("TextButton")
		b.Name = name
		b.Size = UDim2.new(0, 84, 0, 36)
		b.Position = UDim2.new(0, xOrder * 94, 0, 0)
		b.BackgroundColor3 = bgCol
		b.BackgroundTransparency = 0.25
		b.BorderSizePixel = 0
		b.TextColor3 = Color3.new(1, 1, 1)
		b.Font = Enum.Font.GothamBold
		b.TextSize = 13
		b.Text = text
		b.Parent = topBar
		Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
		b.MouseButton1Click:Connect(onClick)
		return b
	end

	makeBtn("ExitBtn", 0, "🚪 EXIT", Color3.fromRGB(180, 40, 40), function()
		if mounted then unmountDrone() end
	end)

	makeBtn("ResetBtn", 1, "💥 RESET", Color3.fromRGB(210, 120, 20), function()
		if mounted then
			selfDestructRemote:FireServer()
			unmountDrone()
		end
	end)

	local modeBtn
	modeBtn = makeBtn("ModeBtn", 2, "STAB", Color3.fromRGB(40, 140, 220), function()
		if flightMode == "STAB" then
			flightMode = "ACRO"
			modeBtn.Text = "ACRO"
			modeBtn.BackgroundColor3 = Color3.fromRGB(200, 40, 200)
		else
			flightMode = "STAB"
			modeBtn.Text = "STAB"
			modeBtn.BackgroundColor3 = Color3.fromRGB(40, 140, 220)
		end
	end)
end

-- ============================================================
--  TOUCH EVENT HANDLING
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

		if input == leftTouchId and leftJoyCenter then
			local delta = Vector2.new(input.Position.X, input.Position.Y) - leftJoyCenter
			local norm = delta / JOY_RADIUS
			if norm.Magnitude > 1 then norm = norm.Unit end

			-- Deadzone
			local dz = 0.08
			local rawX = (math.abs(norm.X) > dz) and norm.X or 0
			local rawY = (math.abs(norm.Y) > dz) and norm.Y or 0

			yawIn = rawX * math.abs(rawX)
			throttleIn = -rawY * math.abs(rawY) -- push up = climb

			if leftThumb then
				leftThumb.Position = UDim2.new(0.5 + norm.X * 0.4, 0, 0.5 + norm.Y * 0.4, 0)
			end
		elseif input == rightTouchId and rightJoyCenter then
			local delta = Vector2.new(input.Position.X, input.Position.Y) - rightJoyCenter
			local norm = delta / JOY_RADIUS
			if norm.Magnitude > 1 then norm = norm.Unit end

			local dz = 0.08
			local rawX = (math.abs(norm.X) > dz) and norm.X or 0
			local rawY = (math.abs(norm.Y) > dz) and norm.Y or 0

			rollIn = rawX * math.abs(rawX)
			pitchIn = -rawY * math.abs(rawY) -- push up = nose down (pitch forward)

			if rightThumb then
				rightThumb.Position = UDim2.new(0.5 + norm.X * 0.4, 0, 0.5 + norm.Y * 0.4, 0)
			end
		end
	end)

	local function resetLeft()
		leftTouchId = nil
		leftJoyCenter = nil
		yawIn = 0
		throttleIn = 0
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
		if input == leftTouchId then resetLeft() end
		if input == rightTouchId then resetRight() end
	end)
end

-- ============================================================
--  KEYBOARD INPUT (PC Support)
-- ============================================================
UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.UserInputType == Enum.UserInputType.Keyboard then
		keysDown[input.KeyCode] = true
		if input.KeyCode == Enum.KeyCode.F and mounted then
			unmountDrone()
		elseif input.KeyCode == Enum.KeyCode.R and mounted then
			selfDestructRemote:FireServer()
			unmountDrone()
		elseif input.KeyCode == Enum.KeyCode.M and mounted then
			flightMode = (flightMode == "STAB") and "ACRO" or "STAB"
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Keyboard then
		keysDown[input.KeyCode] = false
	end
end)

local function readKeyboard()
	pitchIn    = 0
	rollIn     = 0
	yawIn      = 0
	throttleIn = 0

	if keysDown[Enum.KeyCode.W] then pitchIn = 1 end
	if keysDown[Enum.KeyCode.S] then pitchIn = -1 end
	if keysDown[Enum.KeyCode.A] then rollIn = -1 end
	if keysDown[Enum.KeyCode.D] then rollIn = 1 end
	if keysDown[Enum.KeyCode.Q] then yawIn = -1 end
	if keysDown[Enum.KeyCode.E] then yawIn = 1 end
	if keysDown[Enum.KeyCode.Space]     then throttleIn = 1 end
	if keysDown[Enum.KeyCode.LeftShift] then throttleIn = -1 end
end

-- ============================================================
--  CHARACTER VISIBILITY
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
--  PARTICLE & AUDIO CONTROL
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
--  MOUNT / UNMOUNT
-- ============================================================
function mountDrone(drone)
	if mounted then return end

	droneModel = drone
	droneBody = drone and drone.PrimaryPart
	if not droneBody then return end

	bodyGyro = droneBody:FindFirstChild("DroneGyro")
	bodyVelocity = droneBody:FindFirstChild("DroneVelocity")
	motorSound = droneBody:FindFirstChild("MotorSound")

	if not bodyGyro or not bodyVelocity then return end

	mounted = true
	collisionLock = false
	outOfBoundsTimer = 0

	-- Initialize orientation to match current drone facing
	local rx, ry, rz = droneBody.CFrame:ToOrientation()
	currentYaw   = ry
	currentPitch = 0
	currentRoll  = 0
	acroRotation = droneBody.CFrame.Rotation

	-- Activate body velocity
	bodyVelocity.MaxForce = Vector3.new(2e5, 2e5, 2e5)
	bodyVelocity.Velocity = Vector3.new(0, 0, 0)

	-- Switch Camera
	camera.CameraType = Enum.CameraType.Scriptable

	-- Sound
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

	if hudGui then hudGui.Enabled = true end
	if mobileGui then mobileGui.Enabled = true end
	if warningLabel then warningLabel.Visible = false end

	-- Collision Detection
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

	if bodyVelocity then
		bodyVelocity.MaxForce = Vector3.new(0, 0, 0)
		bodyVelocity.Velocity = Vector3.new(0, 0, 0)
	end

	if motorSound then motorSound:Stop() end
	if windSound then windSound:Stop() end
	setPropWash(false)

	camera.CameraType = Enum.CameraType.Custom
	if hudGui then hudGui.Enabled = false end
	if mobileGui then mobileGui.Enabled = false end

	setCharVisible(true)
	unmountRemote:FireServer()

	droneModel = nil
	droneBody = nil
	bodyGyro = nil
	bodyVelocity = nil
end

function explodeDrone()
	if not droneBody then return end
	local pos = droneBody.Position

	mounted = false

	if motorSound then motorSound:Stop() end
	if windSound then windSound:Stop() end

	-- Brief static cut screen
	if staticFrame then
		staticFrame.BackgroundTransparency = 0.2
		task.delay(0.2, function()
			TweenService:Create(staticFrame, TweenInfo.new(0.6), {BackgroundTransparency = 1}):Play()
		end)
	end

	camera.CameraType = Enum.CameraType.Custom
	if hudGui then hudGui.Enabled = false end
	if mobileGui then mobileGui.Enabled = false end

	setCharVisible(true)
	explodeRemote:FireServer(pos)

	droneModel = nil
	droneBody = nil
	bodyGyro = nil
	bodyVelocity = nil
end

-- ============================================================
--  FLIGHT SIMULATION LOOP (RenderStepped)
-- ============================================================
local CAM_TILT = math.rad(Config.CAM_TILT)

RunService.RenderStepped:Connect(function(dt)
	if not mounted or not droneBody or not bodyGyro or not bodyVelocity then return end

	-- 1. Read Inputs
	if isMobile then
		-- values set in TouchChanged
	else
		readKeyboard()
	end

	-- 2. Yaw (Heading turn)
	currentYaw = currentYaw - (yawIn * Config.YAW_SPEED * dt)

	-- 3. Attitude (Pitch / Roll)
	local targetPitch = 0
	local targetRoll  = 0
	local droneRotation = CFrame.new()

	if flightMode == "STAB" then
		-- Stabilized / Angle Mode: Sticks command exact angle, auto-levels on release!
		local maxTiltRad = math.rad(Config.MAX_TILT_DEG)
		local desiredPitch = pitchIn * maxTiltRad
		local desiredRoll  = rollIn  * maxTiltRad

		-- Smooth interpolation
		local lerpFactor = math.clamp(Config.TILT_LERP_SPEED * dt, 0, 1)
		currentPitch = currentPitch + (desiredPitch - currentPitch) * lerpFactor
		currentRoll  = currentRoll  + (desiredRoll  - currentRoll)  * lerpFactor

		droneRotation = CFrame.Angles(0, currentYaw, 0)
			* CFrame.Angles(currentPitch, 0, 0)
			* CFrame.Angles(0, 0, -currentRoll)

		bodyGyro.CFrame = droneRotation
	else
		-- Acro Mode: Sticks command continuous angular rates (360 flips)
		local pRate = pitchIn * Config.ACRO_ROT_SPEED * dt
		local rRate = rollIn  * Config.ACRO_ROT_SPEED * dt
		local yRate = -yawIn  * Config.YAW_SPEED       * dt

		acroRotation = acroRotation
			* CFrame.Angles(0, yRate, 0)
			* CFrame.Angles(pRate, 0, 0)
			* CFrame.Angles(0, 0, -rRate)

		droneRotation = acroRotation
		bodyGyro.CFrame = acroRotation
	end

	-- 4. Velocity & Hover Dynamics
	local currentVel = droneBody.AssemblyLinearVelocity

	-- Vertical velocity: smooth climb / hover / descent
	local targetVerticalSpeed = 0
	if throttleIn > 0.05 then
		targetVerticalSpeed = throttleIn * Config.CLIMB_SPEED
	elseif throttleIn < -0.05 then
		targetVerticalSpeed = throttleIn * Config.DESCENT_SPEED
	else
		targetVerticalSpeed = 0 -- Auto-hover locks altitude!
	end

	-- Horizontal thrust generated from drone tilt
	local forwardDir = droneRotation.LookVector
	local rightDir   = droneRotation.RightVector

	-- Flatten look vector for horizontal movement
	local flatForward = Vector3.new(forwardDir.X, 0, forwardDir.Z)
	if flatForward.Magnitude > 0.01 then
		flatForward = flatForward.Unit
	else
		flatForward = Vector3.new(0, 0, -1)
	end

	local flatRight = Vector3.new(rightDir.X, 0, rightDir.Z)
	if flatRight.Magnitude > 0.01 then
		flatRight = flatRight.Unit
	else
		flatRight = Vector3.new(1, 0, 0)
	end

	-- Tilt angle gives horizontal acceleration
	local pitchRatio = (flightMode == "STAB") and (currentPitch / math.rad(Config.MAX_TILT_DEG)) or pitchIn
	local rollRatio  = (flightMode == "STAB") and (currentRoll  / math.rad(Config.MAX_TILT_DEG)) or rollIn

	local horizPush = (flatForward * pitchRatio * Config.HORIZONTAL_ACCEL)
		+ (flatRight * rollRatio * Config.HORIZONTAL_ACCEL)

	-- Apply horizontal drag to prevent endless drift
	local currentHorizVel = Vector3.new(currentVel.X, 0, currentVel.Z)
	local dragForce = -currentHorizVel * Config.HORIZONTAL_DRAG

	local newHorizVel = currentHorizVel + (horizPush + dragForce) * dt

	-- Cap max speed
	if newHorizVel.Magnitude > Config.MAX_SPEED then
		newHorizVel = newHorizVel.Unit * Config.MAX_SPEED
	end

	-- Vertical smoothing
	local newVertVel = currentVel.Y + (targetVerticalSpeed - currentVel.Y) * math.clamp(8 * dt, 0, 1)

	-- Set BodyVelocity
	bodyVelocity.Velocity = Vector3.new(newHorizVel.X, newVertVel, newHorizVel.Z)

	-- 5. Dynamic Audio
	local totalSpeed = droneBody.AssemblyLinearVelocity.Magnitude
	if motorSound then
		local throttleFactor = math.clamp((throttleIn + 1) / 2, 0, 1)
		motorSound.PlaybackSpeed = 0.85 + (throttleFactor * 0.6) + (totalSpeed / Config.MAX_SPEED * 0.35)
		motorSound.Volume = 0.4 + (throttleFactor * 0.4)
	end
	if windSound then
		windSound.Volume = math.clamp(totalSpeed / Config.MAX_SPEED, 0, 0.7)
	end

	-- 6. FPV Camera
	camera.CFrame = droneBody.CFrame
		* CFrame.new(0, 0.4, -1.35)
		* CFrame.Angles(-CAM_TILT, 0, 0)

	-- 7. Boundary Watchdog & HUD
	local dronePos = droneBody.Position
	local distFromCenter = Vector2.new(dronePos.X, dronePos.Z).Magnitude
	local isOut = (distFromCenter > Config.BOUNDS_RADIUS)
		or (dronePos.Y < Config.BOUNDS_MIN_Y)
		or (dronePos.Y > Config.BOUNDS_MAX_Y)

	if isOut then
		outOfBoundsTimer = outOfBoundsTimer + dt
		if warningLabel then
			warningLabel.Visible = true
			warningLabel.Text = string.format("⚠️ SIGNAL LOST - DETONATING IN %.1fs", math.max(0, Config.OUT_OF_BOUNDS_TIME - outOfBoundsTimer))
		end
		if staticFrame then
			staticFrame.BackgroundTransparency = math.clamp(1 - (outOfBoundsTimer / Config.OUT_OF_BOUNDS_TIME * 0.7), 0.3, 1)
		end

		if outOfBoundsTimer >= Config.OUT_OF_BOUNDS_TIME then
			collisionLock = true
			explodeDrone()
		end
	else
		outOfBoundsTimer = 0
		if warningLabel then warningLabel.Visible = false end
		if staticFrame then staticFrame.BackgroundTransparency = 1 end
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
--  INIT
-- ============================================================
createHUD()
createMobileUI()

print("[DroneClient] Smooth Stabilized Quadcopter Ready!")
