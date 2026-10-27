--[[
    MapBuilder - creates the game world:
    ground, house, landing pad, obstacles, spawn
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

------------ GROUND ------------
makePart(map, "Ground", Vector3.new(0, -0.5, 0), Vector3.new(500, 1, 500),
	"Bright green", Enum.Material.Grass)

------------ HOUSE ------------
local house = Instance.new("Folder")
house.Name = "House"
house.Parent = map

local H = Vector3.new(0, 0, 0) -- house origin
local WC = "Brick yellow"
local WM = Enum.Material.Brick

-- Floor
makePart(house, "Floor", H + Vector3.new(0, 0.25, 0),
	Vector3.new(20, 0.5, 20), "Reddish brown", Enum.Material.Wood)

-- Front wall (with door opening in the middle)
makePart(house, "FrontL", H + Vector3.new(-6, 6, -10),
	Vector3.new(8, 12, 0.5), WC, WM)
makePart(house, "FrontR", H + Vector3.new(7, 6, -10),
	Vector3.new(6, 12, 0.5), WC, WM)
makePart(house, "FrontTop", H + Vector3.new(1, 10.5, -10),
	Vector3.new(6, 3, 0.5), WC, WM)

-- Back wall
makePart(house, "Back", H + Vector3.new(0, 6, 10),
	Vector3.new(20, 12, 0.5), WC, WM)

-- Left wall
makePart(house, "Left", H + Vector3.new(-10, 6, 0),
	Vector3.new(0.5, 12, 20), WC, WM)

-- Right wall (with window gap)
makePart(house, "RightBot", H + Vector3.new(10, 2.5, 0),
	Vector3.new(0.5, 5, 20), WC, WM)
makePart(house, "RightTop", H + Vector3.new(10, 10, 0),
	Vector3.new(0.5, 4, 20), WC, WM)
makePart(house, "RightWinL", H + Vector3.new(10, 6.5, -7),
	Vector3.new(0.5, 3, 6), WC, WM)
makePart(house, "RightWinR", H + Vector3.new(10, 6.5, 7),
	Vector3.new(0.5, 3, 6), WC, WM)

-- Roof
makePart(house, "Roof", H + Vector3.new(0, 12.25, 0),
	Vector3.new(22, 0.5, 22), "Dark red", Enum.Material.Slate)

-- Table inside
makePart(house, "TableTop", H + Vector3.new(-2, 3.5, 2),
	Vector3.new(4, 0.3, 3), "Reddish brown", Enum.Material.Wood)
makePart(house, "TableLeg1", H + Vector3.new(-3.5, 1.7, 0.8),
	Vector3.new(0.3, 3, 0.3), "Reddish brown", Enum.Material.Wood)
makePart(house, "TableLeg2", H + Vector3.new(-0.5, 1.7, 0.8),
	Vector3.new(0.3, 3, 0.3), "Reddish brown", Enum.Material.Wood)
makePart(house, "TableLeg3", H + Vector3.new(-3.5, 1.7, 3.2),
	Vector3.new(0.3, 3, 0.3), "Reddish brown", Enum.Material.Wood)
makePart(house, "TableLeg4", H + Vector3.new(-0.5, 1.7, 3.2),
	Vector3.new(0.3, 3, 0.3), "Reddish brown", Enum.Material.Wood)

------------ LANDING PAD ------------
local pad = Instance.new("Folder")
pad.Name = "LandingPad"
pad.Parent = map

makePart(pad, "PadBase", Vector3.new(25, 0.1, 0),
	Vector3.new(8, 0.2, 8), "Medium stone grey", Enum.Material.Concrete)

-- H marking
makePart(pad, "HL", Vector3.new(24, 0.22, 0),
	Vector3.new(0.3, 0.05, 4), "Bright red", Enum.Material.Neon)
makePart(pad, "HR", Vector3.new(26, 0.22, 0),
	Vector3.new(0.3, 0.05, 4), "Bright red", Enum.Material.Neon)
makePart(pad, "HM", Vector3.new(25, 0.22, 0),
	Vector3.new(2, 0.05, 0.3), "Bright red", Enum.Material.Neon)

------------ SPAWN ------------
local spawn = Instance.new("SpawnLocation")
spawn.Name = "Spawn"
spawn.Position = Vector3.new(0, 1, -18)
spawn.Size = Vector3.new(6, 1, 6)
spawn.BrickColor = BrickColor.new("Medium stone grey")
spawn.Material = Enum.Material.SmoothPlastic
spawn.Anchored = true
spawn.TopSurface = Enum.SurfaceType.Smooth
spawn.BottomSurface = Enum.SurfaceType.Smooth
spawn.Parent = workspace

------------ OBSTACLES TO FLY AROUND ------------
local obs = Instance.new("Folder")
obs.Name = "Obstacles"
obs.Parent = map

-- Tower
makePart(obs, "Tower", Vector3.new(60, 20, 40),
	Vector3.new(6, 40, 6), "Dark stone grey", Enum.Material.Concrete)

-- Crates
makePart(obs, "Crate1", Vector3.new(-30, 3, 25),
	Vector3.new(6, 6, 6), "Brown", Enum.Material.Wood)
makePart(obs, "Crate2", Vector3.new(-28, 9, 25),
	Vector3.new(5, 6, 5), "Brown", Enum.Material.Wood)

-- Arch (fly through it!)
makePart(obs, "ArchL", Vector3.new(40, 8, -30),
	Vector3.new(3, 16, 3), "Medium stone grey", Enum.Material.Concrete)
makePart(obs, "ArchR", Vector3.new(52, 8, -30),
	Vector3.new(3, 16, 3), "Medium stone grey", Enum.Material.Concrete)
makePart(obs, "ArchTop", Vector3.new(46, 17, -30),
	Vector3.new(15, 2, 4), "Medium stone grey", Enum.Material.Concrete)

-- Bridge
makePart(obs, "BridgeL", Vector3.new(-50, 5, -40),
	Vector3.new(3, 10, 3), "Dark stone grey", Enum.Material.Concrete)
makePart(obs, "BridgeR", Vector3.new(-50, 5, -52),
	Vector3.new(3, 10, 3), "Dark stone grey", Enum.Material.Concrete)
makePart(obs, "BridgeDeck", Vector3.new(-50, 10.5, -46),
	Vector3.new(5, 1, 15), "Dark stone grey", Enum.Material.Concrete)

-- Walls (target practice)
makePart(obs, "Wall1", Vector3.new(80, 5, 0),
	Vector3.new(1, 10, 16), "Nougat", Enum.Material.Brick)
makePart(obs, "Wall2", Vector3.new(80, 5, 25),
	Vector3.new(1, 10, 16), "Nougat", Enum.Material.Brick)

-- Trees
local function makeTree(pos)
	makePart(obs, "Trunk", pos + Vector3.new(0, 4, 0),
		Vector3.new(2, 8, 2), "Reddish brown", Enum.Material.Wood)
	local leaves = makePart(obs, "Leaves", pos + Vector3.new(0, 11, 0),
		Vector3.new(8, 7, 8), "Forest green", Enum.Material.Grass)
	leaves.Shape = Enum.PartType.Ball
end

makeTree(Vector3.new(-20, 0, -35))
makeTree(Vector3.new(15, 0, 40))
makeTree(Vector3.new(-45, 0, 10))
makeTree(Vector3.new(55, 0, -10))
makeTree(Vector3.new(35, 0, 55))

print("[MapBuilder] Map built!")
