--[[
    Заглушка Roblox API: позволяет прогонять клиентские модули обычным Lua.
    Нужна только для проверки, что UI собирается без ошибок (опечатки в
    названиях свойств/методов, nil-индексы). Не является частью игры.
]]

local Stub = {}

-- ── СИГНАЛЫ ──
local Signal = {}
Signal.__index = Signal
function Signal.new()
    return setmetatable({ handlers = {} }, Signal)
end
function Signal:Connect(fn)
    table.insert(self.handlers, fn)
    return { Disconnect = function() end, Connected = true }
end
function Signal:Once(fn) return self:Connect(fn) end
function Signal:Wait() return 0 end
function Signal:Fire(...)
    for _, fn in ipairs(self.handlers) do fn(...) end
end
Stub.Signal = Signal

-- ── ENUM (любой путь возвращает заглушку) ──
local function enumValue(path)
    return setmetatable({}, {
        __tostring = function() return "Enum." .. path end,
        __index = function(_, key) return enumValue(path .. "." .. tostring(key)) end,
    })
end
Stub.Enum = setmetatable({}, {
    __index = function(_, key) return enumValue(tostring(key)) end,
})

-- ── ТИПЫ ДАННЫХ ──
Stub.Vector2 = {}
Stub.Vector3 = {}
Stub.UDim  = {}
Stub.UDim2 = {}
Stub.Color3 = {}

-- Vector3 с настоящей математикой: серверные скрипты считают на нём позиции.
local V3 = {}
V3.__index = function(t, k)
    if k == "Magnitude" then
        return math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z)
    elseif k == "Unit" then
        local m = math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z)
        if m < 1e-9 then return Stub.Vector3.new(0, 0, 0) end
        return Stub.Vector3.new(t.X / m, t.Y / m, t.Z / m)
    elseif k == "Dot" then
        return function(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
    end
    return nil
end
V3.__add = function(a, b) return Stub.Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V3.__sub = function(a, b) return Stub.Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V3.__mul = function(a, b)
    if type(b) == "number" then return Stub.Vector3.new(a.X * b, a.Y * b, a.Z * b) end
    if type(a) == "number" then return Stub.Vector3.new(b.X * a, b.Y * a, b.Z * a) end
    return Stub.Vector3.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3.__unm = function(a) return Stub.Vector3.new(-a.X, -a.Y, -a.Z) end

local V2 = {}
V2.__index = function(t, k)
    if k == "Magnitude" then return math.sqrt(t.X * t.X + t.Y * t.Y) end
    if k == "Unit" then
        local m = math.sqrt(t.X * t.X + t.Y * t.Y)
        if m < 1e-9 then return Stub.Vector2.new(0, 0) end
        return Stub.Vector2.new(t.X / m, t.Y / m)
    end
    return nil
end
V2.__sub = function(a, b) return Stub.Vector2.new(a.X - b.X, a.Y - b.Y) end
V2.__add = function(a, b) return Stub.Vector2.new(a.X + b.X, a.Y + b.Y) end
V2.__div = function(a, n) return Stub.Vector2.new(a.X / n, a.Y / n) end

function Stub.Vector2.new(x, y)
    return setmetatable({ X = x or 0, Y = y or 0 }, V2)
end
function Stub.UDim.new(scale, offset) return { Scale = scale or 0, Offset = offset or 0 } end
function Stub.UDim2.new(xs, xo, ys, yo)
    return { X = { Scale = xs or 0, Offset = xo or 0 }, Y = { Scale = ys or 0, Offset = yo or 0 } }
end
function Stub.Color3.fromRGB(r, g, b) return { R = r or 0, G = g or 0, B = b or 0 } end
function Stub.Color3.new(r, g, b) return { R = r or 0, G = g or 0, B = b or 0 } end
function Stub.Vector3.new(x, y, z)
    return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3)
end

-- CFrame-заглушка: важна только цепочка умножений и LookVector.
local CF = {}
CF.__index = function(t, k)
    if k == "LookVector" then return Stub.Vector3.new(0, 0, -1) end
    if k == "RightVector" then return Stub.Vector3.new(1, 0, 0) end
    if k == "UpVector" then return Stub.Vector3.new(0, 1, 0) end
    if k == "Position" then return Stub.Vector3.new(t._x, t._y, t._z) end
    if k == "Lerp" then return function(a) return a end end
    if k == "ToOrientation" then return 0, 0, 0 end
    if k == "ToWorldSpace" then return function(a) return a end end
    return nil
end
CF.__mul = function(a, b) return a end

Stub.CFrame = {
    new = function(x, y, z)
        if type(x) == "table" then
            return setmetatable({ _x = x.X, _y = x.Y, _z = x.Z }, CF)
        end
        return setmetatable({ _x = x or 0, _y = y or 0, _z = z or 0 }, CF)
    end,
    Angles = function() return setmetatable({ _x = 0, _y = 0, _z = 0 }, CF) end,
    fromEulerAnglesXYZ = function() return setmetatable({ _x = 0, _y = 0, _z = 0 }, CF) end,
}

Stub.NumberSequenceKeypoint = { new = function() return {} end }
Stub.ColorSequenceKeypoint = { new = function() return {} end }
Stub.ColorSequence = { new = function() return {} end }
Stub.NumberSequence = { new = function() return {} end }
Stub.NumberRange = { new = function() return {} end }
Stub.RaycastParams = { new = function() return {} end }
Stub.BrickColor = { new = function() return {} end }
Stub.Instance_Color3 = Stub.Color3

-- ── INSTANCE ──
local SIGNALS = {
    MouseButton1Click = true, MouseButton1Down = true, MouseButton1Up = true,
    MouseEnter = true, MouseLeave = true, Changed = true, Completed = true,
    InputBegan = true, InputChanged = true, InputEnded = true,
    Triggered = true, MouseClick = true, ChildAdded = true,
    OnClientEvent = true, OnServerEvent = true, RenderStepped = true,
    Heartbeat = true, PlayerAdded = true, PlayerRemoving = true,
    CharacterAdded = true, ChildRemoved = true,
}

local Instance = {}
Instance.__index = function(self, key)
    local raw = rawget(self, key)
    if raw ~= nil then return raw end

    local signals = rawget(self, "_signals")
    if not signals then
        signals = {}
        rawset(self, "_signals", signals)
    end

    if SIGNALS[key] then
        signals[key] = signals[key] or Signal.new()
        return signals[key]
    end

    if key == "CFrame" then return Stub.CFrame.new(0, 0, 0) end
    if key == "Position" then
        local cf = rawget(self, "CFrame")
        if type(cf) == "table" and cf._x then
            return Stub.Vector3.new(cf._x, cf._y, cf._z)
        end
        return Stub.Vector3.new(0, 0, 0)
    end
    if key == "AbsoluteSize" then return { X = 200, Y = 12 } end
    if key == "AbsolutePosition" then return { X = 0, Y = 0 } end
    if key == "ViewportSize" then return { X = 800, Y = 600 } end
    if key == "Children" then return rawget(self, "_children") or {} end

    local methods = {
        Destroy = function(this)
            local parent = rawget(this, "Parent")
            if parent then
                local kids = rawget(parent, "_children") or {}
                for i, child in ipairs(kids) do
                    if child == this then table.remove(kids, i) break end
                end
                rawset(this, "Parent", nil)
            end
        end,
        ClearAllChildren = function() end,
        IsA = function(_, name) return name == "Frame" or name == "GuiObject" end,
        FindFirstChild = function(this, name)
            for _, c in ipairs(rawget(this, "_children") or {}) do
                if c.Name == name then return c end
            end
            return nil
        end,
        FindFirstChildOfClass = function(this, class)
            for _, c in ipairs(rawget(this, "_children") or {}) do
                if c.ClassName == class then return c end
            end
            return nil
        end,
        GetChildren = function(this)
            local copy = {}
            for _, c in ipairs(rawget(this, "_children") or {}) do table.insert(copy, c) end
            return copy
        end,
        -- Luau позволяет обходить таблицу в for-in, обычный Lua — нет,
        -- поэтому отдаём итератор (пустой список наследников достаточен).
        GetDescendants = function() return next, {}, nil end,
        WaitForChild = function(this, name)
            return this:FindFirstChild(name) or this:_makeChild(name)
        end,
        _makeChild = function(this, name)
            local child = Instance.new("Folder")
            child.Name = name
            child.Parent = this
            return child
        end,
        GetAttribute = function(this, name) return (rawget(this, "_attrs") or {})[name] end,
        SetAttribute = function(this, name, value)
            rawset(this, "_attrs", rawget(this, "_attrs") or {})
            rawget(this, "_attrs")[name] = value
        end,
        GetPropertyChangedSignal = function() return Signal.new() end,
        Play = function() end,
        Stop = function() end,
        Emit = function() end,
        IsHovered = function() return false end,
        TweenSize = function() end,
        FireServer = function() end,
        FireClient = function() end,
        InvokeServer = function() return {} end,
        AddItem = function() end,
        GetSortedAsync = function() error("нет DataStore") end,
        GetAsync = function() error("нет DataStore") end,
        SetAsync = function() error("нет DataStore") end,
        UpdateAsync = function() error("нет DataStore") end,
    }
    if methods[key] then return methods[key] end

    return nil
end

Instance.__newindex = function(self, key, value)
    if key == "Parent" then
        rawset(self, "Parent", value)
        if value and value.addChild then value:addChild(self) end
        return
    end
    rawset(self, key, value)
end

function Instance.new(className)
    local inst = setmetatable({
        ClassName = className,
        Name = className,
        _children = {},
        _attrs = {},
        addChild = function(this, child)
            table.insert(rawget(this, "_children"), child)
        end,
    }, Instance)
    return inst
end
Stub.Instance = Instance

-- ── СЕРВИСЫ ──
local services = {}

local function makeService(name)
    if services[name] then return services[name] end
    local svc = Instance.new(name)
    svc.Name = name
    services[name] = svc
    return svc
end

Stub.TweenInfo = { new = function() return {} end }

Stub.TweenService = {
    Create = function()
        return { Play = function() end, Completed = Signal.new(), Cancel = function() end }
    end,
}

local userInput = Instance.new("UserInputService")
userInput.TouchEnabled = true
userInput.KeyboardEnabled = false
Stub.UserInputService = userInput

local runService = Instance.new("RunService")
Stub.RunService = runService

local player = Instance.new("Player")
player.Name = "TestPlayer"
player.UserId = 1
local playerGui = Instance.new("PlayerGui")
playerGui.Name = "PlayerGui"
playerGui.Parent = player
player.WaitForChild = function(_, name)
    if name == "PlayerGui" then return playerGui end
    return Instance.new("Folder")
end
player.Character = nil
Stub.Player = player

local camera = Instance.new("Camera")
camera.ViewportSize = { X = 800, Y = 600 }
Stub.Camera = camera

local replicated = Instance.new("ReplicatedStorage")

local sharedDir = (Stub.sharedDir or "src/shared")
replicated.WaitForChild = function(this, name)
    local existing = this:FindFirstChild(name)
    if existing then return existing end

    if name == "Tuning" or name == "DroneConfig" or name == "FlightModel"
        or name == "PlayerData" then
        return require(sharedDir .. "/" .. name)
    end

    local folder = Instance.new("Folder")
    folder.Name = name
    folder.Parent = this
    return folder
end

Stub.game = {
    GetService = function(_, name)
        if name == "Players" then
            local p = Instance.new("Players")
            p.LocalPlayer = player
            return p
        end
        if name == "UserInputService" then return userInput end
        if name == "RunService" then return runService end
        if name == "ReplicatedStorage" then return replicated end
        if name == "Players" then return Instance.new("Players") end
        if name == "TweenService" then return Stub.TweenService end
        return makeService(name)
    end,
}

local ws = Instance.new("Workspace")
ws.Name = "Workspace"
ws.CurrentCamera = camera
ws.Raycast = function() return nil end
Stub.workspace = ws

Stub.playerGui = playerGui
Stub.replicated = replicated

return Stub
