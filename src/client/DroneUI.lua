--[[
    DroneUI — весь интерфейс игры в одном месте.

    Сделано как обычный интерфейс, а не «набор светящихся надписей»:
      * один тёмный нейтральный фон, один акцентный цвет, красный — только для
        опасных действий;
      * шрифты Gotham, числа крупные, подписи мелкие и приглушённые;
      * всё выровнено по сетке, скругления 8–12, тонкая обводка вместо свечения;
      * меню — модальное окно с двумя вкладками (полёт / рекорды), слайдеры
        тянутся мышью и пальцем, значения обновляются сразу.

    Модуль не знает про дронов: он рисует то, что ему передают, и зовёт колбэки.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")

local Tuning = require(ReplicatedStorage:WaitForChild("Tuning"))

local DroneUI = {}

-- ── ПАЛИТРА И ТИПОГРАФИКА ─────────────────────────────────
local C = {
    text   = Color3.fromRGB(236, 239, 244),
    sub    = Color3.fromRGB(154, 162, 176),
    dim    = Color3.fromRGB(108, 116, 130),
    bg     = Color3.fromRGB(18, 21, 27),
    panel  = Color3.fromRGB(24, 28, 35),
    btn    = Color3.fromRGB(38, 43, 52),
    btnHi  = Color3.fromRGB(48, 54, 65),
    line   = Color3.fromRGB(54, 60, 72),
    accent = Color3.fromRGB(76, 141, 255),
    danger = Color3.fromRGB(226, 86, 86),
    good   = Color3.fromRGB(88, 192, 132),
    warn   = Color3.fromRGB(232, 172, 74),
}

local F       = Enum.Font.Gotham
local F_MED   = Enum.Font.GothamMedium
local F_BOLD  = Enum.Font.GothamBold

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- ── ПРИМИТИВЫ ─────────────────────────────────────────────
local function corner(inst, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 10)
    c.Parent = inst
    return c
end

local function stroke(inst, color, transparency, thickness)
    local s = Instance.new("UIStroke")
    s.Color = color or C.line
    s.Transparency = transparency or 0.55
    s.Thickness = thickness or 1
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = inst
    return s
end

local function padding(inst, all)
    local p = Instance.new("UIPadding")
    p.PaddingLeft = UDim.new(0, all)
    p.PaddingRight = UDim.new(0, all)
    p.PaddingTop = UDim.new(0, all)
    p.PaddingBottom = UDim.new(0, all)
    p.Parent = inst
    return p
end

local function label(parent, text, props)
    props = props or {}
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Text = text or ""
    l.TextColor3 = props.color or C.text
    l.Font = props.font or F_MED
    l.TextSize = props.size or 14
    l.TextXAlignment = props.align or Enum.TextXAlignment.Left
    l.TextYAlignment = props.valign or Enum.TextYAlignment.Center
    l.TextScaled = false
    l.RichText = false
    l.AutoLocalize = false
    l.Size = props.size2 or UDim2.new(1, 0, 1, 0)
    l.Position = props.pos or UDim2.new(0, 0, 0, 0)
    l.Parent = parent
    return l
end

local function frame(parent, props)
    props = props or {}
    local f = Instance.new(props.class or "Frame")
    f.BackgroundColor3 = props.color or C.panel
    f.BackgroundTransparency = props.transparency or 0
    f.BorderSizePixel = 0
    f.Size = props.size or UDim2.new(1, 0, 1, 0)
    f.Position = props.pos or UDim2.new(0, 0, 0, 0)
    f.AnchorPoint = props.anchor or Vector2.new(0, 0)
    f.ZIndex = props.z or 1
    f.Parent = parent
    return f
end

-- Кнопка: обычная, «главная» (акцент) и «опасная» (красная). Наведение и
-- нажатие — через Tween, чтобы интерфейс не дёргался.
local function button(parent, text, props)
    props = props or {}
    local variant = props.variant or "default"
    local bg = C.btn
    local fg = C.text
    local strokeColor = C.line
    local strokeTransparency = 0.6

    if variant == "primary" then
        bg = C.accent
        fg = Color3.fromRGB(255, 255, 255)
        strokeTransparency = 1
    elseif variant == "danger" then
        bg = C.btn
        fg = Color3.fromRGB(240, 145, 145)
        strokeColor = Color3.fromRGB(120, 62, 62)
        strokeTransparency = 0.25
    elseif variant == "ghost" then
        bg = C.panel
        fg = C.sub
    end

    local b = Instance.new("TextButton")
    b.BackgroundColor3 = bg
    b.BorderSizePixel = 0
    b.AutoButtonColor = false
    b.Text = text
    b.TextColor3 = fg
    b.Font = F_BOLD
    b.TextSize = props.size or 14
    b.AutoLocalize = false
    b.Size = props.size2 or UDim2.new(0, 120, 0, 38)
    b.Position = props.pos or UDim2.new(0, 0, 0, 0)
    b.AnchorPoint = props.anchor or Vector2.new(0, 0)
    b.ZIndex = props.z or 2
    b.Parent = parent
    corner(b, props.radius or 8)
    stroke(b, strokeColor, strokeTransparency, 1)

    local baseColor = bg
    local hoverColor = variant == "primary" and Color3.fromRGB(96, 158, 255) or C.btnHi

    b.MouseEnter:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.12), { BackgroundColor3 = hoverColor }):Play()
    end)
    b.MouseLeave:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.12), { BackgroundColor3 = baseColor }):Play()
    end)
    b.MouseButton1Down:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.06), { TextSize = (props.size or 14) - 1 }):Play()
    end)
    b.MouseButton1Up:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.06), { TextSize = props.size or 14 }):Play()
    end)

    return b
end

-- ── СЛАЙДЕР ───────────────────────────────────────────────
local function slider(parent, field, onChange)
    local row = frame(parent, {
        class = "Frame",
        color = C.panel,
        transparency = 1,
        size = UDim2.new(1, 0, 0, 52),
    })

    local title = label(row, field.label, {
        color = C.text, font = F_MED, size = 14,
        pos = UDim2.new(0, 0, 0, 2),
        size2 = UDim2.new(1, -70, 0, 18),
    })

    local valueLabel = label(row, "", {
        color = C.sub, font = F_MED, size = 14,
        align = Enum.TextXAlignment.Right,
        pos = UDim2.new(1, -70, 0, 2),
        size2 = UDim2.new(0, 70, 0, 18),
    })

    local track = frame(row, {
        color = Color3.fromRGB(46, 52, 63),
        size = UDim2.new(1, 0, 0, 6),
        pos = UDim2.new(0, 0, 0, 34),
    })
    corner(track, 3)

    local fill = frame(track, {
        color = C.accent,
        size = UDim2.new(0, 0, 1, 0),
    })
    corner(fill, 3)

    local knob = frame(track, {
        color = Color3.fromRGB(245, 247, 250),
        size = UDim2.new(0, 16, 0, 16),
        anchor = Vector2.new(0.5, 0.5),
        pos = UDim2.new(0, 0, 0.5, 0),
        z = 3,
    })
    corner(knob, 8)

    local hit = frame(row, {
        class = "TextButton",
        color = C.panel,
        transparency = 1,
        size = UDim2.new(1, 12, 0, 26),
        pos = UDim2.new(0, -6, 0, 24),
        z = 4,
    })
    hit.Text = ""
    hit.AutoButtonColor = false

    local state = { value = field.default }

    local function ratio()
        return clamp((state.value - field.min) / (field.max - field.min), 0, 1)
    end

    local function render()
        local r = ratio()
        fill.Size = UDim2.new(r, 0, 1, 0)
        knob.Position = UDim2.new(r, 0, 0.5, 0)
        valueLabel.Text = Tuning.formatField(field.key, state.value)
    end

    local function setFromX(x)
        local width = track.AbsoluteSize.X
        if width <= 0 then return end
        local rel = clamp((x - track.AbsolutePosition.X) / width, 0, 1)
        local raw = field.min + rel * (field.max - field.min)
        local snapped = math.floor((raw - field.min) / field.step + 0.5) * field.step + field.min
        snapped = clamp(snapped, field.min, field.max)
        local dec = field.decimals or 0
        local m = 10 ^ dec
        snapped = math.floor(snapped * m + 0.5) / m
        if snapped == state.value then return end
        state.value = snapped
        render()
        if onChange then onChange(field.key, snapped) end
    end

    hit.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            setFromX(input.Position.X)
        end
    end)

    local dragging = false
    hit.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            setFromX(input.Position.X)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    render()

    return {
        row = row,
        set = function(v)
            state.value = clamp(v, field.min, field.max)
            render()
        end,
        get = function() return state.value end,
    }
end

-- ── ПЕРЕКЛЮЧАТЕЛЬ ────────────────────────────────────────
local function toggle(parent, spec, onChange)
    local row = frame(parent, {
        class = "Frame",
        color = C.panel,
        transparency = 1,
        size = UDim2.new(1, 0, 0, 42),
    })

    label(row, spec.label, {
        color = C.text, font = F_MED, size = 14,
        size2 = UDim2.new(1, -60, 1, 0),
    })

    local pill = frame(row, {
        class = "TextButton",
        color = Color3.fromRGB(52, 58, 70),
        size = UDim2.new(0, 42, 0, 24),
        pos = UDim2.new(1, -42, 0.5, 0),
        anchor = Vector2.new(0, 0.5),
        z = 3,
    })
    pill.Text = ""
    pill.AutoButtonColor = false
    corner(pill, 12)

    local knob = frame(pill, {
        color = Color3.fromRGB(235, 238, 243),
        size = UDim2.new(0, 18, 0, 18),
        pos = UDim2.new(0, 3, 0.5, 0),
        anchor = Vector2.new(0, 0.5),
        z = 4,
    })
    corner(knob, 9)

    local state = { value = spec.default }

    local function render(instant)
        local goalColor = state.value and C.accent or Color3.fromRGB(52, 58, 70)
        local goalPos = state.value and UDim2.new(0, 21, 0.5, 0) or UDim2.new(0, 3, 0.5, 0)
        if instant then
            pill.BackgroundColor3 = goalColor
            knob.Position = goalPos
        else
            TweenService:Create(pill, TweenInfo.new(0.15), { BackgroundColor3 = goalColor }):Play()
            TweenService:Create(knob, TweenInfo.new(0.15), { Position = goalPos }):Play()
        end
    end

    pill.MouseButton1Click:Connect(function()
        state.value = not state.value
        render(false)
        if onChange then onChange(spec.key, state.value) end
    end)

    render(true)

    return {
        row = row,
        set = function(v) state.value = (v == true); render(true) end,
        get = function() return state.value end,
    }
end

-- ── ОКНО ──────────────────────────────────────────────────
local function modalShell(gui, title, subtitle)
    local scrim = frame(gui, {
        class = "Frame",
        color = Color3.fromRGB(0, 0, 0),
        transparency = 0.45,
        size = UDim2.new(1, 0, 1, 0),
        z = 10,
    })

    local panel = frame(gui, {
        color = C.bg,
        size = UDim2.new(0, 500, 0, 470),
        pos = UDim2.new(0.5, 0, 0.5, 0),
        anchor = Vector2.new(0.5, 0.5),
        z = 11,
    })
    corner(panel, 14)
    stroke(panel, C.line, 0.5, 1)

    local scale = Instance.new("UIScale")
    local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
    scale.Scale = clamp(vp.Y / 720, 0.78, 1)
    scale.Parent = panel

    label(panel, title, {
        color = C.text, font = F_BOLD, size = 20,
        pos = UDim2.new(0, 22, 0, 18),
        size2 = UDim2.new(1, -100, 0, 26),
        valign = Enum.TextYAlignment.Top,
    })

    if subtitle then
        label(panel, subtitle, {
            color = C.dim, font = F, size = 13,
            pos = UDim2.new(0, 22, 0, 44),
            size2 = UDim2.new(1, -100, 0, 18),
            valign = Enum.TextYAlignment.Top,
        })
    end

    local close = button(panel, "Закрыть", {
        variant = "ghost",
        size2 = UDim2.new(0, 84, 0, 30),
        pos = UDim2.new(1, -22, 0, 18),
        anchor = Vector2.new(1, 0),
        size = 13,
    })

    local body = frame(panel, {
        class = "Frame",
        color = C.panel,
        transparency = 1,
        size = UDim2.new(1, -44, 1, -104),
        pos = UDim2.new(0, 22, 0, 78),
        z = 12,
    })

    return scrim, panel, body, close
end

-- ── СОЗДАНИЕ ──────────────────────────────────────────────
function DroneUI.new(opts)
    opts = opts or {}
    local player = opts.player or game:GetService("Players").LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")
    local isMobile = opts.isMobile

    local ui = {
        tuning = Tuning.defaults(),
        mounted = false,
        menuOpen = false,
    }

    -- ── HUD ──
    local hud = Instance.new("ScreenGui")
    hud.Name = "DroneHUD"
    hud.ResetOnSpawn = false
    hud.IgnoreGuiInset = true
    hud.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    hud.DisplayOrder = 5
    hud.Enabled = false
    hud.Parent = playerGui

    -- вспышка
    local flash = frame(hud, {
        color = Color3.fromRGB(255, 255, 255),
        transparency = 1,
        size = UDim2.new(1, 0, 1, 0),
        z = 30,
    })

    -- прицел
    local function crosshairPart(size)
        local f = frame(hud, {
            color = C.accent,
            transparency = 0.25,
            size = size,
            pos = UDim2.new(0.5, 0, 0.5, 0),
            anchor = Vector2.new(0.5, 0.5),
            z = 20,
        })
        return f
    end
    crosshairPart(UDim2.new(0, 2, 0, 14))
    crosshairPart(UDim2.new(0, 14, 0, 2))

    -- телеметрия
    local telemetry = frame(hud, {
        color = C.bg,
        transparency = 0.12,
        size = UDim2.new(0, 196, 0, 116),
        pos = UDim2.new(0, 18, 0, 18),
        z = 10,
    })
    corner(telemetry, 12)
    stroke(telemetry, C.line, 0.6, 1)
    padding(telemetry, 14)

    local speedValue = label(telemetry, "0", {
        color = C.text, font = F_BOLD, size = 34,
        size2 = UDim2.new(0, 100, 0, 36),
        valign = Enum.TextYAlignment.Top,
    })
    label(telemetry, "ст/с", {
        color = C.dim, font = F_MED, size = 12,
        pos = UDim2.new(0, 60, 0, 22),
        size2 = UDim2.new(0, 60, 0, 14),
    })

    local altValue = label(telemetry, "Высота 0", {
        color = C.sub, font = F_MED, size = 13,
        pos = UDim2.new(0, 0, 0, 44),
        size2 = UDim2.new(1, 0, 0, 16),
    })

    local throttleTrack = frame(telemetry, {
        color = Color3.fromRGB(44, 50, 61),
        size = UDim2.new(1, 0, 0, 5),
        pos = UDim2.new(0, 0, 0, 74),
    })
    corner(throttleTrack, 3)
    local throttleFill = frame(throttleTrack, {
        color = C.accent,
        size = UDim2.new(0.5, 0, 1, 0),
    })
    corner(throttleFill, 3)
    label(telemetry, "Газ", {
        color = C.dim, font = F_MED, size = 12,
        pos = UDim2.new(0, 0, 0, 82),
        size2 = UDim2.new(1, 0, 0, 14),
    })

    -- гонка
    local race = frame(hud, {
        color = C.bg,
        transparency = 0.12,
        size = UDim2.new(0, 214, 0, 92),
        pos = UDim2.new(0.5, 0, 0, 18),
        anchor = Vector2.new(0.5, 0),
        z = 10,
    })
    corner(race, 12)
    stroke(race, C.line, 0.6, 1)
    padding(race, 14)

    label(race, "КРУГ", {
        color = C.dim, font = F_MED, size = 11,
        size2 = UDim2.new(0, 60, 0, 14),
        valign = Enum.TextYAlignment.Top,
    })

    local lapTime = label(race, "0.00", {
        color = C.text, font = F_BOLD, size = 30,
        pos = UDim2.new(0, 0, 0, 14),
        size2 = UDim2.new(1, 0, 0, 34),
        valign = Enum.TextYAlignment.Top,
    })

    local bestLabel = label(race, "Лучший —", {
        color = C.sub, font = F_MED, size = 12,
        pos = UDim2.new(0, 0, 0, 50),
        size2 = UDim2.new(1, 0, 0, 16),
    })

    local ringLabel = label(race, "Кольцо 1 из 3", {
        color = C.dim, font = F_MED, size = 12,
        pos = UDim2.new(0, 0, 0, 66),
        size2 = UDim2.new(1, 0, 0, 16),
    })

    -- кнопки справа
    local actions = frame(hud, {
        color = C.panel,
        transparency = 1,
        size = UDim2.new(0, 250, 0, 38),
        pos = UDim2.new(1, -18, 0, 18),
        anchor = Vector2.new(1, 0),
        z = 10,
    })

    local settingsBtn = button(actions, "Настройки", {
        variant = "ghost",
        size2 = UDim2.new(0, 104, 0, 36),
        pos = UDim2.new(0, 0, 0, 0),
        size = 13,
    })
    local detonateBtn = button(actions, "Подрыв", {
        variant = "danger",
        size2 = UDim2.new(0, 84, 0, 36),
        pos = UDim2.new(0, 108, 0, 0),
        size = 13,
    })
    local exitBtn = button(actions, "Выход", {
        variant = "ghost",
        size2 = UDim2.new(0, 70, 0, 36),
        pos = UDim2.new(1, -70, 0, 0),
        size = 13,
    })

    -- предупреждение
    local warning = frame(hud, {
        color = Color3.fromRGB(58, 46, 20),
        transparency = 0.05,
        size = UDim2.new(0, 300, 0, 32),
        pos = UDim2.new(0.5, 0, 0, 122),
        anchor = Vector2.new(0.5, 0),
        z = 10,
    })
    corner(warning, 8)
    stroke(warning, Color3.fromRGB(140, 105, 40), 0.3, 1)
    label(warning, "Вы уходите за границу карты", {
        color = C.warn, font = F_MED, size = 13,
        align = Enum.TextXAlignment.Center,
        size2 = UDim2.new(1, 0, 1, 0),
    })
    warning.Visible = false

    -- тост снизу: живёт в отдельном слое, чтобы показываться и на земле,
    -- а не только в режиме пилота
    local toastGui = Instance.new("ScreenGui")
    toastGui.Name = "DroneToast"
    toastGui.ResetOnSpawn = false
    toastGui.IgnoreGuiInset = true
    toastGui.DisplayOrder = 25
    toastGui.Parent = playerGui

    local toast = frame(toastGui, {
        color = C.bg,
        transparency = 0.05,
        size = UDim2.new(0, 340, 0, 34),
        pos = UDim2.new(0.5, 0, 1, -140),
        anchor = Vector2.new(0.5, 1),
        z = 12,
    })
    corner(toast, 8)
    stroke(toast, C.line, 0.5, 1)
    local toastLabel = label(toast, "", {
        color = C.text, font = F_MED, size = 13,
        align = Enum.TextXAlignment.Center,
        size2 = UDim2.new(1, -16, 1, 0),
        pos = UDim2.new(0, 8, 0, 0),
    })
    toast.Visible = false
    local toastToken = 0

    -- подсказка по клавишам
    if not isMobile then
        local hint = label(hud, "W/S — вперёд и назад    A/D — крен    Q/E — поворот    Space/Shift — газ    R — подрыв    F — выход    M — настройки", {
            color = C.dim, font = F, size = 12,
            align = Enum.TextXAlignment.Center,
            pos = UDim2.new(0.5, 0, 1, -18),
            anchor = Vector2.new(0.5, 1),
            size2 = UDim2.new(0, 760, 0, 20),
            z = 12,
        })
        hint.TextTransparency = 0.15
    end

    -- ── ГЛАВНЫЙ ЭКРАН (когда не летаешь) ──
    local main = Instance.new("ScreenGui")
    main.Name = "DroneMain"
    main.ResetOnSpawn = false
    main.DisplayOrder = 4
    main.Parent = playerGui

    local card = frame(main, {
        color = C.bg,
        transparency = 0.06,
        size = UDim2.new(0, 292, 0, 116),
        pos = UDim2.new(0.5, 0, 1, -26),
        anchor = Vector2.new(0.5, 1),
    })
    corner(card, 14)
    stroke(card, C.line, 0.55, 1)
    padding(card, 16)

    label(card, "FPV Drone Sandbox", {
        color = C.text, font = F_BOLD, size = 16,
        size2 = UDim2.new(1, 0, 0, 20),
        valign = Enum.TextYAlignment.Top,
    })
    local takeHint = label(card, "Дрон ждёт на площадке", {
        color = C.dim, font = F, size = 12,
        pos = UDim2.new(0, 0, 0, 22),
        size2 = UDim2.new(1, 0, 0, 18),
        valign = Enum.TextYAlignment.Top,
    })
    local takeBtn = button(card, "Взять дрон", {
        variant = "primary",
        size2 = UDim2.new(1, 0, 0, 40),
        pos = UDim2.new(0, 0, 0, 52),
        size = 15,
    })

    -- ── МЕНЮ ──
    local menu = Instance.new("ScreenGui")
    menu.Name = "DroneMenu"
    menu.ResetOnSpawn = false
    menu.IgnoreGuiInset = true
    menu.DisplayOrder = 20
    menu.Enabled = false
    menu.Parent = playerGui

    local scrim, panel, body, closeBtn = modalShell(menu, "Настройки полёта",
        "Двигай ползунки — изменения применяются сразу и сохраняются")

    -- вкладки
    local tabs = frame(panel, {
        color = C.panel,
        transparency = 1,
        size = UDim2.new(1, -44, 0, 30),
        pos = UDim2.new(0, 22, 0, 70),
        z = 12,
    })

    local tabFlight = button(tabs, "Полёт", {
        variant = "primary", size2 = UDim2.new(0, 96, 0, 28), size = 13,
    })
    local tabRecords = button(tabs, "Рекорды", {
        variant = "ghost", size2 = UDim2.new(0, 96, 0, 28),
        pos = UDim2.new(0, 104, 0, 0), size = 13,
    })

    body.Position = UDim2.new(0, 22, 0, 112)
    body.Size = UDim2.new(1, -44, 1, -160)

    local flightPage = frame(body, {
        class = "ScrollingFrame",
        color = C.panel,
        transparency = 1,
        size = UDim2.new(1, 0, 1, 0),
    })
    flightPage.BorderSizePixel = 0
    flightPage.ScrollBarThickness = 4
    flightPage.ScrollBarImageColor3 = C.line
    flightPage.CanvasSize = UDim2.new(0, 0, 0, 0)
    flightPage.AutomaticCanvasSize = Enum.AutomaticSize.Y
    flightPage.ScrollingDirection = Enum.ScrollingDirection.Y
    flightPage.Parent = body

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 6)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = flightPage

    local sliderRefs = {}
    for i, field in ipairs(Tuning.FIELDS) do
        local s = slider(flightPage, field, function(key, value)
            ui.tuning[key] = value
            ui:_notifyTuning()
        end)
        s.row.LayoutOrder = i
        sliderRefs[field.key] = s
    end

    local toggleRefs = {}
    for i, spec in ipairs(Tuning.TOGGLES) do
        local t = toggle(flightPage, spec, function(key, value)
            ui.tuning[key] = value
            ui:_notifyTuning()
        end)
        t.row.LayoutOrder = 100 + i
        toggleRefs[spec.key] = t
    end

    -- низ меню: сброс и готово
    local footer = frame(panel, {
        color = C.panel,
        transparency = 1,
        size = UDim2.new(1, -44, 0, 38),
        pos = UDim2.new(0, 22, 1, -54),
        z = 12,
    })

    local resetBtn = button(footer, "Сбросить", {
        variant = "ghost", size2 = UDim2.new(0, 110, 0, 38), size = 13,
    })
    local doneBtn = button(footer, "Готово", {
        variant = "primary", size2 = UDim2.new(0, 120, 0, 38),
        pos = UDim2.new(1, -120, 0, 0), size = 14,
    })

    -- страница рекордов
    local recordsPage = frame(body, {
        color = C.panel,
        transparency = 1,
        size = UDim2.new(1, 0, 1, 0),
        z = 12,
    })
    recordsPage.Visible = false

    local myBest = label(recordsPage, "Личный рекорд —", {
        color = C.text, font = F_BOLD, size = 16,
        size2 = UDim2.new(1, 0, 0, 24),
        valign = Enum.TextYAlignment.Top,
    })

    local recordsList = frame(recordsPage, {
        class = "ScrollingFrame",
        color = C.panel,
        transparency = 1,
        size = UDim2.new(1, 0, 1, -56),
        pos = UDim2.new(0, 0, 0, 32),
    })
    recordsList.BorderSizePixel = 0
    recordsList.ScrollBarThickness = 4
    recordsList.ScrollBarImageColor3 = C.line
    recordsList.CanvasSize = UDim2.new(0, 0, 0, 0)
    recordsList.AutomaticCanvasSize = Enum.AutomaticSize.Y
    recordsList.ScrollingDirection = Enum.ScrollingDirection.Y

    local recordsLayout = Instance.new("UIListLayout")
    recordsLayout.Padding = UDim.new(0, 4)
    recordsLayout.SortOrder = Enum.SortOrder.LayoutOrder
    recordsLayout.Parent = recordsList

    local refreshBtn = button(recordsPage, "Обновить", {
        variant = "ghost", size2 = UDim2.new(0, 100, 0, 26),
        pos = UDim2.new(1, -100, 1, -30), size = 12,
    })

    -- ── СТИКИ (МОБИЛА) ──
    local sticksGui, leftThumb, rightThumb, leftBase, rightBase
    if isMobile then
        sticksGui = Instance.new("ScreenGui")
        sticksGui.Name = "DroneSticks"
        sticksGui.ResetOnSpawn = false
        sticksGui.DisplayOrder = 6
        sticksGui.Enabled = false
        sticksGui.Parent = playerGui

        local function makeStick(anchor, pos, caption)
            local base = frame(sticksGui, {
                color = Color3.fromRGB(255, 255, 255),
                transparency = 0.9,
                size = UDim2.new(0, 136, 0, 136),
                pos = pos,
                anchor = anchor,
            })
            corner(base, 68)
            stroke(base, Color3.fromRGB(255, 255, 255), 0.85, 1)

            local thumb = frame(base, {
                color = Color3.fromRGB(255, 255, 255),
                transparency = 0.55,
                size = UDim2.new(0, 54, 0, 54),
                pos = UDim2.new(0.5, 0, 0.5, 0),
                anchor = Vector2.new(0.5, 0.5),
            })
            corner(thumb, 27)

            label(base, caption, {
                color = Color3.fromRGB(255, 255, 255), font = F_MED, size = 11,
                align = Enum.TextXAlignment.Center,
                pos = UDim2.new(0, 0, 0, -18),
                size2 = UDim2.new(1, 0, 0, 14),
            })

            return base, thumb
        end

        leftBase, leftThumb = makeStick(Vector2.new(0, 1), UDim2.new(0, 26, 1, -26), "ГАЗ · ПОВОРОТ")
        rightBase, rightThumb = makeStick(Vector2.new(1, 1), UDim2.new(1, -26, 1, -26), "ВПЕРЁД · КРЕН")
    end

    -- ── ПОВЕДЕНИЕ ─────────────────────────────────────────────
    function ui:_notifyTuning()
        if opts.onTuningChanged then
            opts.onTuningChanged(ui.tuning)
        end
    end

    function ui:setTuning(t)
        ui.tuning = Tuning.sanitize(t)
        for key, ref in pairs(sliderRefs) do
            ref.set(ui.tuning[key])
        end
        for key, ref in pairs(toggleRefs) do
            ref.set(ui.tuning[key])
        end
    end

    function ui:getTuning()
        return ui.tuning
    end

    function ui:isMenuOpen()
        return ui.menuOpen
    end

    function ui:openMenu()
        if ui.menuOpen then return end
        ui.menuOpen = true
        menu.Enabled = true
        if sticksGui then sticksGui.Enabled = false end
    end

    function ui:closeMenu()
        if not ui.menuOpen then return end
        ui.menuOpen = false
        menu.Enabled = false
        if sticksGui and ui.mounted then sticksGui.Enabled = true end
    end

    function ui:toggleMenu()
        if ui.menuOpen then ui:closeMenu() else ui:openMenu() end
    end

    function ui:setMounted(mounted)
        ui.mounted = mounted
        hud.Enabled = mounted
        main.Enabled = not mounted
        if sticksGui then sticksGui.Enabled = mounted and not ui.menuOpen end
        if not mounted and ui.menuOpen then ui:closeMenu() end
    end

    function ui:updateTelemetry(t)
        t = t or {}
        speedValue.Text = tostring(math.floor((t.speed or 0) + 0.5))
        altValue.Text = "Высота  " .. tostring(math.floor((t.alt or 0) + 0.5))
        throttleFill.Size = UDim2.new(clamp(t.throttle or 0, 0, 1), 0, 1, 0)
    end

    function ui:updateRace(r)
        r = r or {}
        lapTime.Text = string.format("%.2f", r.lapTime or 0)
        if r.best and r.best > 0 then
            bestLabel.Text = string.format("Лучший  %.2f", r.best)
        else
            bestLabel.Text = "Лучший  —"
        end
        local total = r.total or 3
        local nextRing = r.nextRing or 1
        if nextRing > total then nextRing = total end
        ringLabel.Text = string.format("Кольцо %d из %d", nextRing, total)
    end

    function ui:setWarning(visible)
        warning.Visible = visible == true
    end

    function ui:toast(text, tone)
        toastToken = toastToken + 1
        local token = toastToken
        toastLabel.Text = text or ""
        toastLabel.TextColor3 = (tone == "ok" and C.good) or (tone == "warn" and C.warn)
            or (tone == "bad" and C.danger) or C.text
        toast.Visible = true
        toast.BackgroundTransparency = 0.05

        task.delay(2.6, function()
            if token ~= toastToken then return end
            local tween = TweenService:Create(toast, TweenInfo.new(0.3), { BackgroundTransparency = 1 })
            tween:Play()
            tween.Completed:Wait()
            if token == toastToken then toast.Visible = false end
        end)
    end

    function ui:flash(color, transparency)
        flash.BackgroundColor3 = color or Color3.fromRGB(255, 255, 255)
        flash.BackgroundTransparency = transparency or 0.2
        TweenService:Create(flash, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
    end

    function ui:setPersonalBest(seconds)
        if seconds and seconds > 0 then
            myBest.Text = string.format("Личный рекорд  %.2f", seconds)
        else
            myBest.Text = "Личный рекорд  —"
        end
    end

    function ui:setRecords(list)
        for _, child in ipairs(recordsList:GetChildren()) do
            if child:IsA("Frame") then child:Destroy() end
        end

        if not list or #list == 0 then
            local empty = label(recordsList, "Пока нет рекордов — пролети круг", {
                color = C.dim, font = F, size = 13,
                size2 = UDim2.new(1, 0, 0, 24),
                valign = Enum.TextYAlignment.Top,
            })
            empty.LayoutOrder = 1
            return
        end

        for i, entry in ipairs(list) do
            local row = frame(recordsList, {
                color = C.panel,
                transparency = 1,
                size = UDim2.new(1, -6, 0, 26),
            })
            row.LayoutOrder = i

            local place = label(row, tostring(i), {
                color = i <= 3 and C.accent or C.dim,
                font = F_MED, size = 13,
                size2 = UDim2.new(0, 24, 1, 0),
            })
            place.TextXAlignment = Enum.TextXAlignment.Center

            label(row, entry.name or "—", {
                color = i <= 3 and C.text or C.sub,
                font = i <= 3 and F_MED or F,
                size = 13,
                pos = UDim2.new(0, 34, 0, 0),
                size2 = UDim2.new(1, -110, 1, 0),
            })

            label(row, string.format("%.2f", entry.seconds or 0), {
                color = i <= 3 and C.text or C.sub,
                font = F_MED, size = 13,
                align = Enum.TextXAlignment.Right,
                pos = UDim2.new(1, -70, 0, 0),
                size2 = UDim2.new(0, 70, 1, 0),
            })
        end
    end

    function ui:setTakeHint(text)
        takeHint.Text = text or ""
    end

    function ui:setStick(side, norm)
        local thumb = (side == "left") and leftThumb or rightThumb
        if not thumb then return end
        if norm then
            thumb.Position = UDim2.new(0.5 + norm.X * 0.36, 0, 0.5 + norm.Y * 0.36, 0)
        else
            thumb.Position = UDim2.new(0.5, 0, 0.5, 0)
        end
    end

    function ui:stickBases()
        return leftBase, rightBase
    end

    -- ── ПОДКЛЮЧЕНИЕ КНОПОК ──
    takeBtn.MouseButton1Click:Connect(function()
        if opts.onTake then opts.onTake() end
    end)

    detonateBtn.MouseButton1Click:Connect(function()
        if opts.onDetonate then opts.onDetonate() end
    end)

    exitBtn.MouseButton1Click:Connect(function()
        if opts.onExit then opts.onExit() end
    end)

    settingsBtn.MouseButton1Click:Connect(function()
        ui:toggleMenu()
    end)

    closeBtn.MouseButton1Click:Connect(function()
        ui:closeMenu()
    end)

    doneBtn.MouseButton1Click:Connect(function()
        ui:closeMenu()
    end)

    resetBtn.MouseButton1Click:Connect(function()
        ui:setTuning(Tuning.defaults())
        ui:_notifyTuning()
    end)

    tabFlight.MouseButton1Click:Connect(function()
        flightPage.Visible = true
        recordsPage.Visible = false
        tabFlight.BackgroundColor3 = C.accent
        tabFlight.TextColor3 = Color3.fromRGB(255, 255, 255)
        tabRecords.BackgroundColor3 = C.btn
        tabRecords.TextColor3 = C.sub
    end)

    local function showRecords()
        flightPage.Visible = false
        recordsPage.Visible = true
        tabFlight.BackgroundColor3 = C.btn
        tabFlight.TextColor3 = C.sub
        tabRecords.BackgroundColor3 = C.accent
        tabRecords.TextColor3 = Color3.fromRGB(255, 255, 255)
        if opts.onRequestRecords then opts.onRequestRecords() end
    end

    tabRecords.MouseButton1Click:Connect(showRecords)
    refreshBtn.MouseButton1Click:Connect(function()
        if opts.onRequestRecords then opts.onRequestRecords() end
    end)

    -- Esc / M — меню (Esc перехватываем только когда меню уже открыто)
    UserInputService.InputBegan:Connect(function(input, processed)
        if processed then return end
        if input.KeyCode == Enum.KeyCode.M then
            ui:toggleMenu()
        elseif input.KeyCode == Enum.KeyCode.Escape and ui.menuOpen then
            ui:closeMenu()
        end
    end)

    return ui
end

return DroneUI
