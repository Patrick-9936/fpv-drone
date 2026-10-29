--[[
    Tuning — настройки полёта игрока.

    Чистый Lua без типов Roblox (кроме необязательного использования таблиц), поэтому
    модуль гоняется обычными тестами (tests/tuning_test.lua) и одинаково работает
    на клиенте (стики) и на сервере (валидация + параметры полёта).

    Зачем: раньше все числа были зашиты в DroneConfig, и «подогнать под себя» было
    нельзя — приходилось каждый раз менять исходник и публиковать новую версию.
]]

local Tuning = {}

-- ── ОПИСАНИЕ ПОЛЕЙ ────────────────────────────────────────
-- min/max — жёсткие границы: всё, что вне них, обрезается на сервере.
-- step — шаг слайдера и точность сохранения.
Tuning.FIELDS = {
    { key = "maxSpeed",    label = "Максимальная скорость", min = 60,  max = 180, step = 5,    default = 110, decimals = 0 },
    { key = "climbPower",  label = "Тяга по вертикали",     min = 10,  max = 40,  step = 2,    default = 26,  decimals = 0 },
    { key = "yawRate",     label = "Скорость поворота",     min = 1.5, max = 8,   step = 0.5,  default = 4,   decimals = 1 },
    { key = "sensitivity", label = "Отклик наклона",        min = 0.4, max = 1.6, step = 0.05, default = 1,   decimals = 2 },
    { key = "expo",        label = "Плавность стика",       min = 1,   max = 2.2, step = 0.05, default = 1.25, decimals = 2 },
    { key = "deadzone",    label = "Мёртвая зона стика",    min = 0,   max = 0.25, step = 0.01, default = 0.04, decimals = 2 },
    { key = "hover",       label = "Точка висения",         min = 0.4, max = 0.9, step = 0.01, default = 0.62, decimals = 2 },
}

Tuning.TOGGLES = {
    { key = "invertPitch", label = "Инверсия вперёд/назад", default = false },
    { key = "invertYaw",   label = "Инверсия поворота",     default = false },
}

local fieldByKey, toggleByKey = {}, {}
for _, f in ipairs(Tuning.FIELDS) do fieldByKey[f.key] = f end
for _, t in ipairs(Tuning.TOGGLES) do toggleByKey[t.key] = t end

-- ── УТИЛИТЫ ───────────────────────────────────────────────
local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function roundTo(v, step)
    if not step or step <= 0 then return v end
    return math.floor(v / step + 0.5) * step
end

local function roundToDecimals(v, decimals)
    local m = 10 ^ (decimals or 0)
    return math.floor(v * m + 0.5) / m
end

Tuning.clamp = clamp

-- ── ЗНАЧЕНИЯ ПО УМОЛЧАНИЮ ─────────────────────────────────
function Tuning.defaults()
    local t = {}
    for _, f in ipairs(Tuning.FIELDS) do
        t[f.key] = f.default
    end
    for _, tg in ipairs(Tuning.TOGGLES) do
        t[tg.key] = tg.default
    end
    return t
end

-- ── ВАЛИДАЦИЯ ─────────────────────────────────────────────
-- Принимает что угодно (в том числе мусор от клиента) и возвращает полный
-- корректный набор. Неизвестные ключи отбрасываются, значения обрезаются.
function Tuning.sanitize(partial)
    local out = Tuning.defaults()
    if type(partial) ~= "table" then return out end

    for _, f in ipairs(Tuning.FIELDS) do
        local v = partial[f.key]
        if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then
            v = roundTo(clamp(v, f.min, f.max), f.step)
            out[f.key] = roundToDecimals(v, f.decimals)
        end
    end

    for _, tg in ipairs(Tuning.TOGGLES) do
        local v = partial[tg.key]
        if type(v) == "boolean" then
            out[tg.key] = v
        end
    end

    -- Точка висения не должна совпадать с границей: деление в FlightModel
    -- уходит в бесконечность, если hover == 1.
    out.hover = clamp(out.hover, 0.4, 0.9)

    return out
end

-- ── КРИВАЯ СТИКА ──────────────────────────────────────────
-- v в [-1..1]: сначала мёртвая зона (с пересчётом амплитуды, чтобы не было
-- «ступеньки» на выходе из зоны), затем экспонента.
function Tuning.stick(v, expo, deadzone)
    v = clamp(v or 0, -1, 1)
    expo = expo or 1.25
    deadzone = clamp(deadzone or 0, 0, 0.9)

    local a = math.abs(v)
    if a <= deadzone then return 0 end

    local scaled = (a - deadzone) / (1 - deadzone)
    scaled = clamp(scaled, 0, 1)
    if expo ~= 1 then scaled = scaled ^ expo end
    return (v < 0) and -scaled or scaled
end

-- Сырые стики -> готовый ввод для сервера.
-- raw = { pitch, roll, yaw, throttle } (pitch +1 = вперёд, roll +1 = вправо)
function Tuning.envelope(raw, t)
    t = t or Tuning.defaults()

    local pitch = Tuning.stick(raw.pitch or 0, t.expo, t.deadzone)
    local roll  = Tuning.stick(raw.roll  or 0, t.expo, t.deadzone)
    local yaw   = Tuning.stick(raw.yaw   or 0, t.expo, t.deadzone)

    if t.invertPitch then pitch = -pitch end
    if t.invertYaw   then yaw   = -yaw   end

    return {
        pitch    = pitch,
        roll     = roll,
        yaw      = yaw,
        throttle = clamp(raw.throttle or 0.5, 0, 1),
    }
end

-- ── ПАРАМЕТРЫ ПОЛЁТА ──────────────────────────────────────
-- Возвращает копию DroneConfig с подставленными настройками игрока.
function Tuning.applyCfg(config, t)
    t = t or Tuning.defaults()

    local cfg = {}
    for k, v in pairs(config) do cfg[k] = v end

    cfg.MAX_SPEED        = t.maxSpeed
    cfg.MAX_CLIMB_SPEED  = t.climbPower
    cfg.MAX_FALL_SPEED   = clamp(t.climbPower * 1.9, 20, 90)
    cfg.YAW_SPEED        = t.yawRate
    cfg.HOVER_THROTTLE   = t.hover
    cfg.MAX_TILT_DEG     = clamp(48 * t.sensitivity, 20, 66)

    return cfg
end

-- ── ФОРМАТИРОВАНИЕ ДЛЯ UI ─────────────────────────────────
function Tuning.formatField(key, value)
    local f = fieldByKey[key]
    if not f then return tostring(value) end
    local d = f.decimals or 0
    return string.format("%." .. d .. "f", value)
end

function Tuning.fieldFor(key)
    return fieldByKey[key]
end

function Tuning.isDefault(v)
    if type(v) ~= "table" then return false end
    local d = Tuning.defaults()
    for k, dv in pairs(d) do
        if v[k] ~= dv then return false end
    end
    return true
end

return Tuning
