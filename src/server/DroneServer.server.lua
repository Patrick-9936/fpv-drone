--[[
    DroneServer - spawns the FPV drone, handles mount/unmount,
    explosion, and respawn logic.
    The drone model is built entirely from Parts welded together.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage:WaitForChild("DroneConfig"))

--------------- REMOTE EVENTS ---------------
local remotes = Instance.new("Folder")
remotes.Name = "DroneRemotes"
remotes.Parent = ReplicatedStorage

local mountRemote = Instance.new("RemoteEvent")
mountRemote.Name = "MountDrone"
mountRemote.Parent = remotes

local unmountRemote = Instance.new("RemoteEvent")
unmountRemote.Name = "UnmountDrone"
unmountRemote.Parent = remotes

local explodeRemote = Instance.new("RemoteEvent")
explodeRemote.Name = "DroneExploded"
explodeRemote.Parent = remotes

local droneReadyRemote = Instance.new("RemoteEvent")
droneReadyRemote.Name = "DroneReady"
droneReadyRemote.Parent = remotes

--------------- STATE ---------------
local currentPilot = nil
local droneModel = nil

--------------- HELPERS ---------------
local function weld(part0, part1)
	local w = Instance.new("WeldConstraint")
	w.Part0 = part0
	w.Part1 = part1
	w.Parent = part0
end

local function dronePart(parent, name, size, offset, color, mat, canCollide, shape, transparency)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = CFrame.new(Config.DRONE_SPAWN + offset)
	p.BrickColor = BrickColor.new(color)
	p.Material = mat or Enum.Material.SmoothPlastic
	p.CanCollide = (canCollide == true)
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then p.Shape = shape end
	if transparency then p.Transparency = transparency end
	p.Parent = parent
	return p
end

--------------- BUILD DRONE MODEL ---------------
local function buildDrone()
	local model = Instance.new("Model")
	model.Name = "FPV_Drone"

	-- ===== BODY =====
	local body = dronePart(model, "Body",
		Vector3.new(1.8, 0.35, 2.2), Vector3.new(0, 0, 0),
		"Dark stone grey", Enum.Material.Metal, true)
	model.PrimaryPart = body

	-- ===== ARMS (4 diagonal) =====
	local armData = {
		{ offset = Vector3.new( 1.1, 0, -1.1), angle = 45  },
		{ offset = Vector3.new(-1.1, 0, -1.1), angle = -45 },
		{ offset = Vector3.new( 1.1, 0,  1.1), angle = -45 },
		{ offset = Vector3.new(-1.1, 0,  1.1), angle = 45  },
	}

	for i, arm in ipairs(armData) do
		-- Arm beam
		local a = dronePart(model, "Arm" .. i,
			Vector3.new(1.6, 0.12, 0.22), arm.offset * 0.5,
			"Dark stone grey", Enum.Material.Metal, true)
		a.CFrame = CFrame.new(Config.DRONE_SPAWN + arm.offset * 0.5)
			* CFrame.Angles(0, math.rad(arm.angle), 0)
		weld(body, a)

		-- Motor housing
		local m = dronePart(model, "Motor" .. i,
			Vector3.new(0.4, 0.22, 0.4), arm.offset,
			"Really black", Enum.Material.Metal, false, Enum.PartType.Cylinder)
		m.CFrame = CFrame.new(Config.DRONE_SPAWN + arm.offset)
			* CFrame.Angles(0, 0, math.rad(90))
		weld(body, m)

		-- Propeller disc
		local pr = dronePart(model, "Prop" .. i,
			Vector3.new(0.05, 1.3, 1.3), arm.offset + Vector3.new(0, 0.18, 0),
			"Institutional white", Enum.Material.SmoothPlastic, false,
			Enum.PartType.Cylinder, 0.5)
		pr.CFrame = CFrame.new(Config.DRONE_SPAWN + arm.offset + Vector3.new(0, 0.18, 0))
			* CFrame.Angles(0, 0, math.rad(90))
		weld(body, pr)
	end

	-- ===== CAMERA (front, red neon) =====
	local cam = dronePart(model, "DroneCam",
		Vector3.new(0.3, 0.25, 0.3), Vector3.new(0, -0.05, -1.25),
		"Really red", Enum.Material.Neon, false)
	weld(body, cam)

	-- ===== PAYLOAD / WARHEAD (bottom) =====
	local payload = dronePart(model, "Payload",
		Vector3.new(0.6, 0.4, 0.9), Vector3.new(0, -0.4, 0.1),
		"Olive", Enum.Material.Metal, true)
	weld(body, payload)

	-- ===== TAIL LED =====
	local led = dronePart(model, "LED",
		Vector3.new(0.12, 0.12, 0.12), Vector3.new(0, 0.12, 1.15),
		"Bright red", Enum.Material.Neon, false)
	weld(body, led)

	-- ===== ANTENNA =====
	local ant = dronePart(model, "Antenna",
		Vector3.new(0.06, 0.5, 0.06), Vector3.new(0.3, 0.4, 0.8),
		"Really black", Enum.Material.Metal, false)
	weld(body, ant)

	-- ===== PHYSICS CONSTRAINTS =====

	-- BodyGyro — controls orientation
	local gyro = Instance.new("BodyGyro")
	gyro.Name = "DroneGyro"
	gyro.MaxTorque = Vector3.new(5e5, 5e5, 5e5)
	gyro.P = 14000
	gyro.D = 700
	gyro.CFrame = CFrame.new()
	gyro.Parent = body

	-- VectorForce — thrust along drone's local up axis
	local att = Instance.new("Attachment")
	att.Name = "ThrustAttach"
	att.Parent = body

	local vf = Instance.new("VectorForce")
	vf.Name = "Thrust"
	vf.Attachment0 = att
	vf.ApplyAtCenterOfMass = true
	vf.RelativeTo = Enum.ActuatorRelativeTo.Attachment0
	vf.Force = Vector3.new(0, 0, 0)
	vf.Parent = body

	-- ===== CLICK DETECTOR =====
	local click = Instance.new("ClickDetector")
	click.Name = "DroneClick"
	click.MaxActivationDistance = 25
	click.Parent = body

	-- ===== HIGHLIGHT (glow when available) =====
	local hl = Instance.new("Highlight")
	hl.Name = "DroneHL"
	hl.FillColor = Color3.fromRGB(0, 180, 255)
	hl.FillTransparency = 0.85
	hl.OutlineColor = Color3.fromRGB(0, 200, 255)
	hl.OutlineTransparency = 0.2
	hl.Enabled = true
	hl.Parent = model

	model.Parent = workspace
	return model
end

--------------- SPAWN / RESPAWN ---------------
local function spawnDrone()
	if droneModel then
		droneModel:Destroy()
	end
	currentPilot = nil
	droneModel = buildDrone()

	-- Wire up click → mount
	local body = droneModel.PrimaryPart
	body.DroneClick.MouseClick:Connect(function(player)
		if currentPilot ~= nil then return end
		currentPilot = player

		-- Give network ownership to pilot for smooth client-side physics
		pcall(function()
			body:SetNetworkOwner(player)
		end)

		-- Disable highlight
		droneModel.DroneHL.Enabled = false

		-- Tell client to enter FPV
		mountRemote:FireClient(player, droneModel)
	end)

	-- Notify everyone drone is ready
	droneReadyRemote:FireAllClients()
	print("[DroneServer] Drone spawned")
end

--------------- REMOTE HANDLERS ---------------

-- Player voluntarily exits drone
unmountRemote.OnServerEvent:Connect(function(player)
	if player ~= currentPilot then return end
	currentPilot = nil
	if droneModel and droneModel.PrimaryPart then
		pcall(function()
			droneModel.PrimaryPart:SetNetworkOwnershipAuto()
		end)
		droneModel.DroneHL.Enabled = true
	end
end)

-- Drone exploded (client tells us where)
explodeRemote.OnServerEvent:Connect(function(player, position)
	if player ~= currentPilot then return end
	currentPilot = nil

	-- Kaboom!
	if position and typeof(position) == "Vector3" then
		local exp = Instance.new("Explosion")
		exp.Position = position
		exp.BlastRadius = Config.EXPLOSION_RADIUS
		exp.BlastPressure = Config.EXPLOSION_POWER
		exp.DestroyJointRadiusPercent = 0 -- don't dismember characters
		exp.Parent = workspace
	end

	-- Destroy drone
	if droneModel then
		droneModel:Destroy()
		droneModel = nil
	end

	-- Respawn after delay
	task.delay(Config.RESPAWN_TIME, function()
		spawnDrone()
	end)
end)

-- Player left the game while piloting
Players.PlayerRemoving:Connect(function(player)
	if player ~= currentPilot then return end
	currentPilot = nil
	if droneModel and droneModel.PrimaryPart then
		pcall(function()
			droneModel.PrimaryPart:SetNetworkOwnershipAuto()
		end)
		droneModel.DroneHL.Enabled = true
	end
end)

--------------- GO ---------------
spawnDrone()
