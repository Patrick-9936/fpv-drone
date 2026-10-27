--[[
    DroneClient — FPV drone controller
    Handles: mount/unmount, keyboard + mobile touch input,
    drone physics (BodyGyro + VectorForce), FPV camera,
    collision → explosion, HUD overlay
]]

local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local UserInputService   = game:GetService("UserInputService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")

local Config  = require(ReplicatedStorage:WaitForChild("DroneConfig"))
local remotes = ReplicatedStorage:WaitForChild("DroneRemotes")

local mountRemote      = remotes:WaitForChild("MountDrone")
local unmountRemote    = remotes:WaitForChild("UnmountDrone")
local explodeRemote    = remotes:WaitForChild("DroneExploded")
local droneReadyRemote = remotes:WaitForChild("DroneReady")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- ============================================================
--  STATE
-- ============================================================
local mounted   = false
local droneModel, droneBody, bodyGyro, thrust
local currentCFrame = CFrame.new()   -- accumulated world-space rotation
local throttle      = 0              -- 0 → 1

-- raw input axes (-1 … 1)
local pitchInput    = 0
local rollInput     = 0
local yawInput      = 0
local throttleInput = 0

local keysDown = {}
local collisionLock = false

local isMobile = UserInputService.TouchEnabled
	and not UserInputService.KeyboardEnabled

-- mobile joystick state
local leftTouchObj, rightTouchObj
local leftCenter, rightCenter       -- Vector2
local leftJoy  = Vector2.new(0, 0)  -- normalized
local rightJoy = Vector2.new(0, 0)

-- ============================================================
--  HUD  (speed / alt / throttle bar / crosshair)
-- ============================================================
local hudGui

local function createHUD()
	if hudGui then hudGui:Destroy() end

	hudGui = Instance.new("ScreenGui")
	hudGui.Name          = "DroneHUD"
	hudGui.ResetOnSpawn  = false
	hudGui.Enabled       = false
	hudGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	hudGui.Parent        = player:WaitForChild("PlayerGui")

	-- crosshair V
	local cv = Instance.new("Frame")
	cv.Name = "XV"
	cv.Size = UDim2.new(0,2,0,22)
	cv.AnchorPoint = Vector2.new(0.5,0.5)
	cv.Position = UDim2.new(0.5,0,0.5,0)
	cv.BackgroundColor3 = Color3.fromRGB(0,255,0)
	cv.BackgroundTransparency = 0.25
	cv.BorderSizePixel = 0
	cv.Parent = hudGui

	-- crosshair H
	local ch = cv:Clone()
	ch.Name = "XH"
	ch.Size = UDim2.new(0,22,0,2)
	ch.Parent = hudGui

	-- info panel bg
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Size = UDim2.new(0,160,0,100)
	panel.Position = UDim2.new(0,8,0,8)
	panel.BackgroundColor3 = Color3.fromRGB(0,0,0)
	panel.BackgroundTransparency = 0.55
	panel.BorderSizePixel = 0
	panel.Parent = hudGui
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0,6)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0,8)
	pad.PaddingTop  = UDim.new(0,6)
	pad.Parent = panel

	local function infoLabel(name, order)
		local l = Instance.new("TextLabel")
		l.Name = name
		l.Size = UDim2.new(1,0,0,22)
		l.Position = UDim2.new(0,0,0,order*24)
		l.BackgroundTransparency = 1
		l.TextColor3 = Color3.fromRGB(0,255,0)
		l.Font = Enum.Font.Code
		l.TextSize = 15
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.Text = ""
		l.Parent = panel
		return l
	end

	infoLabel("Speed", 0)
	infoLabel("Alt",   1)
	infoLabel("Thr",   2)

	-- REC indicator (top-right, cosmetic)
	local rec = Instance.new("TextLabel")
	rec.Name = "REC"
	rec.Size = UDim2.new(0,70,0,24)
	rec.Position = UDim2.new(1,-78,0,8)
	rec.BackgroundTransparency = 1
	rec.TextColor3 = Color3.fromRGB(255,40,40)
	rec.Font = Enum.Font.Code
	rec.TextSize = 16
	rec.Text = "● REC"
	rec.Parent = hudGui

	-- controls hint (PC)
	if not isMobile then
		local h = Instance.new("TextLabel")
		h.Size = UDim2.new(0,340,0,42)
		h.AnchorPoint = Vector2.new(0.5,1)
		h.Position = UDim2.new(0.5,0,1,-8)
		h.BackgroundColor3 = Color3.fromRGB(0,0,0)
		h.BackgroundTransparency = 0.55
		h.BorderSizePixel = 0
		h.TextColor3 = Color3.fromRGB(190,190,190)
		h.Font = Enum.Font.Code
		h.TextSize = 12
		h.Text = "W/S Pitch  A/D Roll  Q/E Yaw  Space/Shift Throttle  F Exit"
		h.TextWrapped = true
		h.Parent = hudGui
		Instance.new("UICorner", h).CornerRadius = UDim.new(0,6)
	end
end

local function updateHUD()
	if not hudGui or not hudGui.Enabled then return end
	local panel = hudGui:FindFirstChild("Panel")
	if not panel or not droneBody then return end

	local spd = math.floor(droneBody.AssemblyLinearVelocity.Magnitude + 0.5)
	local alt = math.floor(droneBody.Position.Y + 0.5)
	local thr = math.floor(throttle * 100 + 0.5)

	local s = panel:FindFirstChild("Speed")
	if s then s.Text = "SPD  " .. spd .. " st/s" end
	local a = panel:FindFirstChild("Alt")
	if a then a.Text = "ALT  " .. alt .. " st" end
	local t = panel:FindFirstChild("Thr")
	if t then t.Text = "THR  " .. thr .. " %" end
end

-- ============================================================
--  MOBILE JOYSTICKS  (floating, appear at touch point)
-- ============================================================
local mobileGui
local leftOuterFrame, leftInnerFrame
local rightOuterFrame, rightInnerFrame

local function makeJoystickVisual(parent, name)
	local outer = Instance.new("Frame")
	outer.Name = name .. "Outer"
	outer.Size = UDim2.new(0,120,0,120)
	outer.AnchorPoint = Vector2.new(0.5,0.5)
	outer.BackgroundColor3 = Color3.fromRGB(255,255,255)
	outer.BackgroundTransparency = 0.78
	outer.BorderSizePixel = 0
	outer.Visible = false
	outer.Parent = parent
	Instance.new("UICorner", outer).CornerRadius = UDim.new(1,0)

	local inner = Instance.new("Frame")
	inner.Name = "Thumb"
	inner.Size = UDim2.new(0,46,0,46)
	inner.AnchorPoint = Vector2.new(0.5,0.5)
	inner.Position = UDim2.new(0.5,0,0.5,0)
	inner.BackgroundColor3 = Color3.fromRGB(255,255,255)
	inner.BackgroundTransparency = 0.35
	inner.BorderSizePixel = 0
	inner.Parent = outer
	Instance.new("UICorner", inner).CornerRadius = UDim.new(1,0)

	return outer, inner
end

local function createMobileUI()
	if not isMobile then return end
	if mobileGui then mobileGui:Destroy() end

	mobileGui = Instance.new("ScreenGui")
	mobileGui.Name = "MobileControls"
	mobileGui.ResetOnSpawn = false
	mobileGui.Enabled = false
	mobileGui.Parent = player:WaitForChild("PlayerGui")

	leftOuterFrame,  leftInnerFrame  = makeJoystickVisual(mobileGui, "L")
	rightOuterFrame, rightInnerFrame = makeJoystickVisual(mobileGui, "R")

	-- Labels
	local function joyLabel(parent, txt)
		local l = Instance.new("TextLabel")
		l.Size = UDim2.new(1,0,0,16)
		l.Position = UDim2.new(0,0,1,4)
		l.BackgroundTransparency = 1
		l.TextColor3 = Color3.fromRGB(220,220,220)
		l.TextStrokeTransparency = 0.5
		l.Font = Enum.Font.GothamBold
		l.TextSize = 11
		l.Text = txt
		l.Parent = parent
	end
	joyLabel(leftOuterFrame,  "THR / YAW")
	joyLabel(rightOuterFrame, "PITCH / ROLL")

	-- Exit button
	local btn = Instance.new("TextButton")
	btn.Name = "Exit"
	btn.Size = UDim2.new(0,72,0,36)
	btn.Position = UDim2.new(0.5,-36,0,12)
	btn.BackgroundColor3 = Color3.fromRGB(200,40,40)
	btn.BackgroundTransparency = 0.25
	btn.BorderSizePixel = 0
	btn.TextColor3 = Color3.new(1,1,1)
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 16
	btn.Text = "EXIT"
	btn.Parent = mobileGui
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0,8)

	btn.MouseButton1Click:Connect(function()
		if mounted then
			unmountDrone()
		end
	end)
end

-- ============================================================
--  MOBILE TOUCH TRACKING  (via UserInputService)
-- ============================================================
if isMobile then
	local JOY_RADIUS = 55 -- pixels

	UserInputService.InputBegan:Connect(function(input, gp)
		if gp or not mounted then return end
		if input.UserInputType ~= Enum.UserInputType.Touch then return end

		local pos = input.Position
		local half = camera.ViewportSize.X / 2

		if pos.X < half and not leftTouchObj then
			leftTouchObj = input
			leftCenter = Vector2.new(pos.X, pos.Y)
			if leftOuterFrame then
				leftOuterFrame.Position = UDim2.new(0, pos.X, 0, pos.Y)
				leftOuterFrame.Visible = true
				leftInnerFrame.Position = UDim2.new(0.5,0,0.5,0)
			end
		elseif pos.X >= half and not rightTouchObj then
			rightTouchObj = input
			rightCenter = Vector2.new(pos.X, pos.Y)
			if rightOuterFrame then
				rightOuterFrame.Position = UDim2.new(0, pos.X, 0, pos.Y)
				rightOuterFrame.Visible = true
				rightInnerFrame.Position = UDim2.new(0.5,0,0.5,0)
			end
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch then return end

		if input == leftTouchObj and leftCenter then
			local d = Vector2.new(input.Position.X, input.Position.Y) - leftCenter
			local n = d / JOY_RADIUS
			if n.Magnitude > 1 then n = n.Unit end
			leftJoy = n
			if leftInnerFrame then
				leftInnerFrame.Position = UDim2.new(0.5 + n.X*0.35, 0, 0.5 + n.Y*0.35, 0)
			end
		elseif input == rightTouchObj and rightCenter then
			local d = Vector2.new(input.Position.X, input.Position.Y) - rightCenter
			local n = d / JOY_RADIUS
			if n.Magnitude > 1 then n = n.Unit end
			rightJoy = n
			if rightInnerFrame then
				rightInnerFrame.Position = UDim2.new(0.5 + n.X*0.35, 0, 0.5 + n.Y*0.35, 0)
			end
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input == leftTouchObj then
			leftTouchObj = nil
			leftJoy = Vector2.new(0,0)
			if leftOuterFrame then leftOuterFrame.Visible = false end
		elseif input == rightTouchObj then
			rightTouchObj = nil
			rightJoy = Vector2.new(0,0)
			if rightOuterFrame then rightOuterFrame.Visible = false end
		end
	end)
end

-- ============================================================
--  KEYBOARD INPUT
-- ============================================================
UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.UserInputType == Enum.UserInputType.Keyboard then
		keysDown[input.KeyCode] = true
		if input.KeyCode == Enum.KeyCode.F and mounted then
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
	pitchInput    = 0
	rollInput     = 0
	yawInput      = 0
	throttleInput = 0

	-- W = nose down (pitch forward to fly forward)
	if keysDown[Enum.KeyCode.W] then pitchInput    =  1 end
	if keysDown[Enum.KeyCode.S] then pitchInput    = -1 end
	if keysDown[Enum.KeyCode.A] then rollInput     = -1 end
	if keysDown[Enum.KeyCode.D] then rollInput     =  1 end
	if keysDown[Enum.KeyCode.Q] then yawInput      =  1 end
	if keysDown[Enum.KeyCode.E] then yawInput      = -1 end
	if keysDown[Enum.KeyCode.Space]     then throttleInput =  1 end
	if keysDown[Enum.KeyCode.LeftShift] then throttleInput = -1 end
end

local function readMobile()
	-- Left stick: X = yaw, Y = throttle (inverted)
	yawInput      =  leftJoy.X
	throttleInput = -leftJoy.Y      -- push up = throttle up

	-- Right stick: X = roll, Y = pitch
	rollInput     =  rightJoy.X
	pitchInput    =  rightJoy.Y     -- push down = nose down
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
--  MOUNT / UNMOUNT
-- ============================================================
function mountDrone(drone) -- luacheck: ignore (forward ref)
	if mounted then return end

	droneModel = drone
	droneBody  = drone and drone.PrimaryPart
	if not droneBody then return end

	bodyGyro = droneBody:FindFirstChild("DroneGyro")
	thrust   = droneBody:FindFirstChild("Thrust")
	if not bodyGyro or not thrust then return end

	mounted     = true
	collisionLock = false
	throttle    = 0
	currentCFrame = droneBody.CFrame.Rotation

	-- FPV camera
	camera.CameraType = Enum.CameraType.Scriptable

	-- show overlays
	if hudGui   then hudGui.Enabled   = true end
	if mobileGui then mobileGui.Enabled = true end

	setCharVisible(false)

	-- collision wiring (auto-disconnects when Part destroyed)
	droneBody.Touched:Connect(function(hit)
		if not mounted or collisionLock then return end
		if hit:IsDescendantOf(droneModel) then return end
		-- ignore players
		if hit.Parent and hit.Parent:FindFirstChildOfClass("Humanoid") then return end

		local spd = droneBody.AssemblyLinearVelocity.Magnitude
		if spd >= Config.MIN_COLLISION_SPEED then
			collisionLock = true
			explodeDrone()
		end
	end)
end

function unmountDrone() -- luacheck: ignore
	if not mounted then return end
	mounted  = false
	throttle = 0

	if thrust then thrust.Force = Vector3.new(0,0,0) end

	camera.CameraType = Enum.CameraType.Custom
	if hudGui   then hudGui.Enabled   = false end
	if mobileGui then mobileGui.Enabled = false end

	setCharVisible(true)
	unmountRemote:FireServer()

	droneModel, droneBody, bodyGyro, thrust = nil, nil, nil, nil
end

function explodeDrone() -- luacheck: ignore
	if not droneBody then return end

	local pos = droneBody.Position
	mounted  = false
	throttle = 0

	camera.CameraType = Enum.CameraType.Custom
	if hudGui   then hudGui.Enabled   = false end
	if mobileGui then mobileGui.Enabled = false end

	setCharVisible(true)
	explodeRemote:FireServer(pos)

	droneModel, droneBody, bodyGyro, thrust = nil, nil, nil, nil
end

-- ============================================================
--  PHYSICS LOOP  (RenderStepped — runs every frame)
-- ============================================================
local CAM_TILT = math.rad(Config.CAM_TILT)

RunService.RenderStepped:Connect(function(dt)
	if not mounted or not droneBody or not bodyGyro or not thrust then return end

	-- 1) read input
	if isMobile then readMobile() else readKeyboard() end

	-- 2) accumulate rotation (local-space deltas)
	local pDt = pitchInput    * Config.PITCH_SPEED * dt
	local yDt = yawInput      * Config.YAW_SPEED   * dt
	local rDt = rollInput     * Config.ROLL_SPEED   * dt

	currentCFrame = currentCFrame
		* CFrame.Angles(pDt, 0, 0)
		* CFrame.Angles(0, yDt, 0)
		* CFrame.Angles(0, 0, rDt)

	bodyGyro.CFrame = currentCFrame

	-- 3) throttle ramp
	if throttleInput > 0.1 then
		throttle = math.min(throttle + Config.THROTTLE_ACCEL * dt, 1)
	elseif throttleInput < -0.1 then
		throttle = math.max(throttle - Config.THROTTLE_ACCEL * dt, 0)
	end

	-- 4) thrust (local Y = drone's up)
	local mass       = droneBody.AssemblyMass
	local hoverForce = mass * workspace.Gravity
	thrust.Force     = Vector3.new(0, throttle * hoverForce * Config.MAX_THRUST_MULT, 0)

	-- 5) FPV camera
	camera.CFrame = droneBody.CFrame
		* CFrame.new(0, 0.35, -1.3)          -- slightly above + forward
		* CFrame.Angles(-CAM_TILT, 0, 0)     -- tilt up so horizon visible when pitched

	-- 6) HUD
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

-- die while piloting → unmount
player.CharacterAdded:Connect(function()
	if mounted then unmountDrone() end
end)

-- ============================================================
--  INIT
-- ============================================================
createHUD()
createMobileUI()

print("[DroneClient] Ready!  " .. (isMobile and "(mobile)" or "(PC)"))
