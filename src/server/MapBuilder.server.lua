--[[
    MapBuilder - creates the game world:
    ground, house, landing pad, obstacles, target dummies
]]

local function makePart(parent, name, pos, size, color, material, anchored)
	local p = Instance.new("Part")
	p.Name = name
	p.Position = pos
	p.Size = size
	p.BrickColor = BrickColor.new(color)
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = (anchored ~= false)
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local map = Instance.new("Folder")
map.Name = "Map"
map.Parent = workspace

------------ GROUND (LARGE 900x900) ------------
makePart(map, "Ground", Vector3.new(0, -0.5, 0), Vector3.new(900, 1, 900),
	"Bright green", Enum.Material.Grass)

------------ HOUSE ------------
local house = Instance.new("Folder")
house.Name = "House"
house.Parent = map

local H = Vector3.new(0, 0, 0)
local WC = "Brick yellow"
local WM = Enum.Material.Brick

-- Floor
makePart(house, "Floor", H + Vector3.new(0, 0.25, 0),
	Vector3.new(22, 0.5, 22), "Reddish brown", Enum.Material.Wood)

-- Front wall (with door)
makePart(house, "FrontL", H + Vector3.new(-6.5, 6, -11),
	Vector3.new(9, 12, 0.6), WC, WM)
makePart(house, "FrontR", H + Vector3.new(7.5, 6, -11),
	Vector3.new(7, 12, 0.6), WC, WM)
makePart(house, "FrontTop", H + Vector3.new(0.5, 10.5, -11),
	Vector3.new(7, 3, 0.6), WC, WM)

-- Back wall
makePart(house, "Back", H + Vector3.new(0, 6, 11),
	Vector3.new(22, 12, 0.6), WC, WM)

-- Left wall
makePart(house, "Left", H + Vector3.new(-11, 6, 0),
	Vector3.new(0.6, 12, 22), WC, WM)

-- Right wall with window
makePart(house, "RightBot", H + Vector3.new(11, 2.5, 0),
	Vector3.new(0.6, 5, 22), WC, WM)
makePart(house, "RightTop", H + Vector3.new(11, 10, 0),
	Vector3.new(0.6, 4, 22), WC, WM)
makePart(house, "RightWinL", H + Vector3.new(11, 6.5, -7.5),
	Vector3.new(0.6, 3, 7), WC, WM)
makePart(house, "RightWinR", H + Vector3.new(11, 6.5, 7.5),
	Vector3.new(0.6, 3, 7), WC, WM)

-- Roof
makePart(house, "Roof", H + Vector3.new(0, 12.3, 0),
	Vector3.new(24, 0.6, 24), "Dark red", Enum.Material.Slate)

-- Furniture inside
makePart(house, "Table", H + Vector3.new(-2, 3, 2),
	Vector3.new(5, 0.4, 4), "Reddish brown", Enum.Material.Wood)

------------ LANDING PAD ------------
local pad = Instance.new("Folder")
pad.Name = "LandingPad"
pad.Parent = map

makePart(pad, "PadBase", Vector3.new(25, 0.15, 0),
	Vector3.new(10, 0.3, 10), "Medium stone grey", Enum.Material.Concrete)

-- H Markings (Neon)
makePart(pad, "HL", Vector3.new(23.8, 0.32, 0),
	Vector3.new(0.4, 0.05, 5), "Bright red", Enum.Material.Neon)
makePart(pad, "HR", Vector3.new(26.2, 0.32, 0),
	Vector3.new(0.4, 0.05, 5), "Bright red", Enum.Material.Neon)
makePart(pad, "HM", Vector3.new(25, 0.32, 0),
	Vector3.new(2.4, 0.05, 0.4), "Bright red", Enum.Material.Neon)

------------ SPAWN LOCATION ------------
local spawn = Instance.new("SpawnLocation")
spawn.Name = "Spawn"
spawn.Position = Vector3.new(0, 1, -22)
spawn.Size = Vector3.new(8, 1, 8)
spawn.BrickColor = BrickColor.new("Medium stone grey")
spawn.Material = Enum.Material.SmoothPlastic
spawn.Anchored = true
spawn.TopSurface = Enum.SurfaceType.Smooth
spawn.BottomSurface = Enum.SurfaceType.Smooth
spawn.Parent = workspace

------------ OBSTACLES & TARGETS ------------
local obs = Instance.new("Folder")
obs.Name = "Obstacles"
obs.Parent = map

-- Flight ring 1
local function makeRing(pos, radius)
	local segments = 12
	for i = 1, segments do
		local a1 = (i - 1) * (math.pi * 2 / segments)
		local a2 = i * (math.pi * 2 / segments)
		local midA = (a1 + a2) / 2
		local p = makePart(obs, "RingSeg",
			pos + Vector3.new(math.cos(midA) * radius, math.sin(midA) * radius, 0),
			Vector3.new(radius * 0.55, 0.6, 0.6), "Bright yellow", Enum.Material.Neon)
		p.CFrame = CFrame.new(p.Position) * CFrame.Angles(0, 0, midA + math.pi/2)
	end
end

makeRing(Vector3.new(35, 14, -40), 9)
makeRing(Vector3.new(35, 18, -90), 11)
makeRing(Vector3.new(80, 20, -90), 12)

-- Tower
makePart(obs, "Tower", Vector3.new(90, 25, 50),
	Vector3.new(8, 50, 8), "Dark stone grey", Enum.Material.Concrete)

-- Tunnel
makePart(obs, "TunnelRoof", Vector3.new(-60, 10, -50),
	Vector3.new(16, 1, 40), "Medium stone grey", Enum.Material.Concrete)
makePart(obs, "TunnelL", Vector3.new(-68, 5, -50),
	Vector3.new(1, 10, 40), "Medium stone grey", Enum.Material.Concrete)
makePart(obs, "TunnelR", Vector3.new(-52, 5, -50),
	Vector3.new(1, 10, 40), "Medium stone grey", Enum.Material.Concrete)

-- Explosive Target Bunker
local bunker = makePart(obs, "TargetBunker", Vector3.new(120, 5, -30),
	Vector3.new(20, 10, 20), "Really black", Enum.Material.Metal)
local bLabel = makePart(obs, "TargetLabel", Vector3.new(120, 8, -40.5),
	Vector3.new(12, 3, 0.2), "Bright red", Enum.Material.Neon)

-- Perimeter boundary pillars (visual boundary)
local RADIUS = 360
for deg = 0, 350, 30 do
	local rad = math.rad(deg)
	local px = math.cos(rad) * RADIUS
	local pz = math.sin(rad) * RADIUS
	local pillar = makePart(obs, "BoundaryPillar", Vector3.new(px, 15, pz),
		Vector3.new(2, 30, 2), "Bright orange", Enum.Material.Neon)
end

print("[MapBuilder] Map with large arena, rings & boundary pillars built!")
