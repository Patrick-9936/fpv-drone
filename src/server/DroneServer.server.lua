--[[
    DroneServer - spawns the FPV drone with audio, effects,
    reliable boundary watchdog, explosion, and auto-respawn.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage:WaitForChild("DroneConfig"))

--------------- REMOTE EVENTS ---------------
local remotes = ReplicatedStorage:FindFirstChild("DroneRemotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "DroneRemotes"
	remotes.Parent = ReplicatedStorage
end

local function getOrCreateRemote(name)
	local r = remotes:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = remotes
	end
	return r
end

local mountRemote        = getOrCreateRemote("MountDrone")
local unmountRemote      = getOrCreateRemote("UnmountDrone")
local explodeRemote      = getOrCreateRemote("DroneExploded")
local selfDestructRemote = getOrCreateRemote("SelfDestruct")
local droneReadyRemote   = getOrCreateRemote("DroneReady")

--------------- STATE ---------------
local currentPilot = nil
local droneModel = nil
local isRespawning = false

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

--------------- VISUAL & SOUND FX BUILDERS ---------------
local function addPropWashEmitter(parent)
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "Wash"
	pe.Color = ColorSequence.new(Color3.fromRGB(240, 240, 240), Color3.fromRGB(200, 200, 200))
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.7),
		NumberSequenceKeypoint.new(1, 1),
	})
	pe.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1.2),
	})
	pe.Lifetime = NumberRange.new(0.2, 0.4)
	pe.Rate = 25
	pe.Speed = NumberRange.new(8, 14)
	pe.EmissionDirection = Enum.NormalId.Bottom
	pe.SpreadAngle = Vector2.new(15, 15)
	pe.Enabled = false
	pe.Parent = parent
	return pe
end

local function createExplosionFX(pos)
	-- Visual blast
	local exp = Instance.new("Explosion")
	exp.Position = pos
	exp.BlastRadius = Config.EXPLOSION_RADIUS
	exp.BlastPressure = Config.EXPLOSION_POWER
	exp.DestroyJointRadiusPercent = 0
	exp.Parent = workspace

	-- Explosion Sound Part
	local soundPart = Instance.new("Part")
	soundPart.Name = "ExplosionSoundPart"
	soundPart.Size = Vector3.new(1, 1, 1)
	soundPart.Position = pos
	soundPart.Anchored = true
	soundPart.CanCollide = false
	soundPart.Transparency = 1
	soundPart.Parent = workspace

	local boom = Instance.new("Sound")
	boom.SoundId = Config.SOUND_EXPLOSION
	boom.Volume = 1.0
	boom.RollOffMaxDistance = 500
	boom.Parent = soundPart
	boom:Play()

	-- Fire & debris particle burst
	local peFire = Instance.new("ParticleEmitter")
	peFire.Color = ColorSequence.new({
		NumberSequenceKeypoint.new(0, Color3.fromRGB(255, 230, 100)),
		NumberSequenceKeypoint.new(0.4, Color3.fromRGB(255, 100, 20)),
		NumberSequenceKeypoint.new(1, Color3.fromRGB(50, 50, 50)),
	})
	peFire.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2),
		NumberSequenceKeypoint.new(0.5, 6),
		NumberSequenceKeypoint.new(1, 0.5),
	})
	peFire.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.8, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	peFire.Lifetime = NumberRange.new(0.8, 1.4)
	peFire.Speed = NumberRange.new(25, 60)
	peFire.SpreadAngle = Vector2.new(180, 180)
	peFire.Parent = soundPart
	peFire:Emit(50)

	Debris:AddItem(soundPart, 4)
end

--------------- BUILD DRONE MODEL ---------------
local function buildDrone()
	local model = Instance.new("Model")
	model.Name = "FPV_Drone"

	-- Main Body Frame
	local body = dronePart(model, "Body",
		Vector3.new(2.0, 0.35, 2.4), Vector3.new(0, 0, 0),
		"Dark stone grey", Enum.Material.Metal, true)
	model.PrimaryPart = body

	-- Quad Arms & Motors
	local armData = {
		{ offset = Vector3.new( 1.2, 0, -1.2), angle = 45  },
		{ offset = Vector3.new(-1.2, 0, -1.2), angle = -45 },
		{ offset = Vector3.new( 1.2, 0,  1.2), angle = -45 },
		{ offset = Vector3.new(-1.2, 0,  1.2), angle = 45  },
	}

	for i, arm in ipairs(armData) do
		-- Arm strut
		local a = dronePart(model, "Arm" .. i,
			Vector3.new(1.7, 0.12, 0.25), arm.offset * 0.5,
			"Dark stone grey", Enum.Material.Metal, true)
		a.CFrame = CFrame.new(Config.DRONE_SPAWN + arm.offset * 0.5)
			* CFrame.Angles(0, math.rad(arm.angle), 0)
		weld(body, a)

		-- Motor
		local m = dronePart(model, "Motor" .. i,
			Vector3.new(0.45, 0.25, 0.45), arm.offset,
			"Really black", Enum.Material.Metal, false, Enum.PartType.Cylinder)
		m.CFrame = CFrame.new(Config.DRONE_SPAWN + arm.offset)
			* CFrame.Angles(0, 0, math.rad(90))
		weld(body, m)

		-- Propeller disc
		local pr = dronePart(model, "Prop" .. i,
			Vector3.new(0.05, 1.4, 1.4), arm.offset + Vector3.new(0, 0.18, 0),
			"Institutional white", Enum.Material.SmoothPlastic, false,
			Enum.PartType.Cylinder, 0.5)
		pr.CFrame = CFrame.new(Config.DRONE_SPAWN + arm.offset + Vector3.new(0, 0.18, 0))
			* CFrame.Angles(0, 0, math.rad(90))
		weld(body, pr)

		-- Prop wash particle emitter under each motor
		addPropWashEmitter(m)
	end

	-- Camera (Front)
	local cam = dronePart(model, "DroneCam",
		Vector3.new(0.35, 0.3, 0.35), Vector3.new(0, 0.05, -1.35),
		"Really red", Enum.Material.Neon, false)
	weld(body, cam)

	-- Warhead / Explosive charge (underneath)
	local payload = dronePart(model, "Payload",
		Vector3.new(0.7, 0.45, 1.1), Vector3.new(0, -0.42, 0.1),
		"Olive", Enum.Material.Metal, true)
	weld(body, payload)

	-- Tail LED (Blinking / Neon)
	local led = dronePart(model, "LED",
		Vector3.new(0.15, 0.15, 0.15), Vector3.new(0, 0.15, 1.25),
		"Bright red", Enum.Material.Neon, false)
	weld(body, led)

	-- VTX Antenna
	local ant = dronePart(model, "Antenna",
		Vector3.new(0.06, 0.6, 0.06), Vector3.new(0.35, 0.45, 0.9),
		"Really black", Enum.Material.Metal, false)
	weld(body, ant)

	-- ===== AUDIO =====
	local motorSound = Instance.new("Sound")
	motorSound.Name = "MotorSound"
	motorSound.SoundId = Config.SOUND_MOTOR
	motorSound.Looped = true
	motorSound.Volume = 0.5
	motorSound.PlaybackSpeed = 0.9
	motorSound.RollOffMaxDistance = 300
	motorSound.Parent = body

	local beepSound = Instance.new("Sound")
	beepSound.Name = "BeepSound"
	beepSound.SoundId = Config.SOUND_BEEP
	beepSound.Volume = 0.7
	beepSound.Parent = body

	-- ===== PHYSICS CONSTRAINTS =====

	-- BodyGyro (Smooth orientation tracking)
	local gyro = Instance.new("BodyGyro")
	gyro.Name = "DroneGyro"
	gyro.MaxTorque = Vector3.new(4e5, 4e5, 4e5)
	gyro.P = 12000
	gyro.D = 800
	gyro.CFrame = CFrame.new()
	gyro.Parent = body

	-- BodyVelocity for stabilized arcade hover and flight
	local bv = Instance.new("BodyVelocity")
	bv.Name = "DroneVelocity"
	bv.MaxForce = Vector3.new(0, 0, 0) -- managed by client during flight
	bv.Velocity = Vector3.new(0, 0, 0)
	bv.Parent = body

	-- VectorForce backup
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

	-- Click Detector
	local click = Instance.new("ClickDetector")
	click.Name = "DroneClick"
	click.MaxActivationDistance = 25
	click.Parent = body

	-- Highlight
	local hl = Instance.new("Highlight")
	hl.Name = "DroneHL"
	hl.FillColor = Color3.fromRGB(0, 200, 255)
	hl.FillTransparency = 0.85
	hl.OutlineColor = Color3.fromRGB(0, 220, 255)
	hl.OutlineTransparency = 0.2
	hl.Enabled = true
	hl.Parent = model

	model.Parent = workspace
	return model
end

--------------- RESPAWN & LIFECYCLE ---------------
local function spawnDrone()
	if isRespawning then return end

	if droneModel then
		pcall(function() droneModel:Destroy() end)
		droneModel = nil
	end

	currentPilot = nil
	droneModel = buildDrone()

	local body = droneModel.PrimaryPart

	-- Ensure if model is ever destroyed (void, Roblox cleanup), it auto-respawns
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

	-- Click to fly
	body.DroneClick.MouseClick:Connect(function(player)
		if currentPilot ~= nil then return end
		currentPilot = player

		pcall(function()
			body:SetNetworkOwner(player)
		end)

		droneModel.DroneHL.Enabled = false

		-- Play arming beep
		local beep = body:FindFirstChild("BeepSound")
		if beep then beep:Play() end

		mountRemote:FireClient(player, droneModel)
	end)

	droneReadyRemote:FireAllClients()
	print("[DroneServer] Drone ready on landing pad")
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

--------------- REMOTE HANDLERS ---------------

unmountRemote.OnServerEvent:Connect(function(player)
	if player ~= currentPilot then return end
	currentPilot = nil
	if droneModel and droneModel.PrimaryPart then
		pcall(function()
			droneModel.PrimaryPart:SetNetworkOwnershipAuto()
		end)
		if droneModel:FindFirstChild("DroneHL") then
			droneModel.DroneHL.Enabled = true
		end
		local ms = droneModel.PrimaryPart:FindFirstChild("MotorSound")
		if ms then ms:Stop() end
	end
end)

explodeRemote.OnServerEvent:Connect(function(player, pos)
	if player ~= currentPilot then return end
	triggerExplosion(pos)
end)

selfDestructRemote.OnServerEvent:Connect(function(player)
	if player ~= currentPilot then return end
	local pos = (droneModel and droneModel.PrimaryPart) and droneModel.PrimaryPart.Position or Config.DRONE_SPAWN
	triggerExplosion(pos)
end)

Players.PlayerRemoving:Connect(function(player)
	if player ~= currentPilot then return end
	currentPilot = nil
	if droneModel and droneModel.PrimaryPart then
		pcall(function()
			droneModel.PrimaryPart:SetNetworkOwnershipAuto()
		end)
		if droneModel:FindFirstChild("DroneHL") then
			droneModel.DroneHL.Enabled = true
		end
	end
end)

--------------- BOUNDARY WATCHDOG (runs every frame) ---------------
RunService.Heartbeat:Connect(function()
	if droneModel and droneModel.PrimaryPart and not isRespawning then
		local pos = droneModel.PrimaryPart.Position
		local horizDist = Vector2.new(pos.X, pos.Z).Magnitude

		if horizDist > (Config.BOUNDS_RADIUS + 30) or pos.Y < Config.BOUNDS_MIN_Y or pos.Y > (Config.BOUNDS_MAX_Y + 40) then
			-- Drone escaped safe area -> auto-detonate & respawn immediately!
			triggerExplosion(pos)
		end
	end
end)

--------------- START ---------------
spawnDrone()
