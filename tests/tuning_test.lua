--[[
    Тест настроек: обычный Lua, без Roblox.
    Запуск:  lua fpv-drone/tests/tuning_test.lua

    Проверяет то, что сервер обязан гарантировать:
      * значения всегда в допустимых границах, что бы клиент ни прислал;
      * мёртвая зона и экспонента стика не дают ступенек и перекоса;
      * настройки реально меняют полёт (скорость, тяга, наклон).
]]

local scriptDir = arg and arg[0] and arg[0]:match("^(.*)/[^/]*$") or "."
package.path = scriptDir .. "/../src/shared/?.lua;" .. package.path

math.clamp = function(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi else return v end
end

local Tuning = require("Tuning")
local FlightModel = require("FlightModel")

local failures = 0
local function check(name, cond, detail)
    if cond then
        print(string.format("  PASS  %s", name))
    else
        failures = failures + 1
        print(string.format("  FAIL  %s   %s", name, detail or ""))
    end
end

-- ──────────────────────────────────────────────
print("\n[1] Значения по умолчанию полные и в границах")
local d = Tuning.defaults()
check("все ползунки заполнены", (function()
    for _, f in ipairs(Tuning.FIELDS) do
        if type(d[f.key]) ~= "number" then return false end
    end
    return true
end)())
check("все переключатели заполнены", d.invertPitch == false and d.invertYaw == false)
check("по умолчанию настройки считаются дефолтными", Tuning.isDefault(d))

-- ──────────────────────────────────────────────
print("\n[2] Валидация: мусор не ломает полёт")
local dirty = Tuning.sanitize({
    maxSpeed = 10000,
    climbPower = -500,
    yawRate = 0 / 0,          -- NaN
    sensitivity = "быстро",
    expo = nil,
    deadzone = 0.9,
    hover = 0.99,
    invertPitch = true,
    invertYaw = "да",
    hackField = 123,
})
check("maxSpeed обрезан сверху", dirty.maxSpeed == 180, tostring(dirty.maxSpeed))
check("climbPower обрезан снизу", dirty.climbPower == 10, tostring(dirty.climbPower))
check("NaN не проходит", dirty.yawRate == Tuning.defaults().yawRate, tostring(dirty.yawRate))
check("строка вместо числа игнорируется", dirty.sensitivity == 1, tostring(dirty.sensitivity))
check("deadzone обрезана", dirty.deadzone == 0.25, tostring(dirty.deadzone))
check("hover не равен 1", dirty.hover <= 0.9, tostring(dirty.hover))
check("булев переключатель принят", dirty.invertPitch == true)
check("строка вместо bool игнорируется", dirty.invertYaw == false)
check("неизвестный ключ выброшен", dirty.hackField == nil)
check("полный набор ключей на выходе", (function()
    for _, f in ipairs(Tuning.FIELDS) do
        if dirty[f.key] == nil then return false end
    end
    return true
end)())

check("nil вместо таблицы не падает", type(Tuning.sanitize(nil)) == "table")

-- ──────────────────────────────────────────────
print("\n[3] Кривая стика")
check("центр — ровно ноль", Tuning.stick(0, 1.25, 0.04) == 0)
check("мёртвая зона даёт ноль", Tuning.stick(0.03, 1.25, 0.04) == 0)
check("вне зоны значение положительное", Tuning.stick(0.1, 1.25, 0.04) > 0)
check("край — ровно 1", math.abs(Tuning.stick(1, 1.25, 0.04) - 1) < 1e-9)
check("минус симметричен", math.abs(Tuning.stick(-1, 1.25, 0.04) + 1) < 1e-9)
check("половина отклонения даёт больше 35% отклика",
    Tuning.stick(0.5, 1.25, 0.04) > 0.35 and Tuning.stick(0.5, 1.25, 0.04) < 0.5,
    tostring(Tuning.stick(0.5, 1.25, 0.04)))
check("функция монотонна", (function()
    local prev = -1
    for i = 0, 100 do
        local v = Tuning.stick(i / 100, 1.25, 0.04)
        if v < prev - 1e-9 then return false end
        prev = v
    end
    return true
end)())

-- ──────────────────────────────────────────────
print("\n[4] Инверсия осей")
local inv = Tuning.sanitize({ invertPitch = true, invertYaw = true })
local out = Tuning.envelope({ pitch = 1, roll = 0, yaw = 1, throttle = 0.5 }, inv)
check("тангаж инвертирован", out.pitch < 0, tostring(out.pitch))
check("курс инвертирован", out.yaw < 0, tostring(out.yaw))
check("газ не тронут", out.throttle == 0.5)

local norm = Tuning.envelope({ pitch = 1, roll = -1, yaw = 0, throttle = 2 }, d)
check("полный стик остаётся полным", math.abs(norm.pitch - 1) < 1e-9, tostring(norm.pitch))
check("газ обрезан до 1", norm.throttle == 1)

-- ──────────────────────────────────────────────
print("\n[5] Настройки меняют полёт")
local BASE = {
    MAX_TILT_DEG = 48, TILT_LERP_SPEED = 12, YAW_SPEED = 4.0,
    MAX_CLIMB_SPEED = 26, MAX_FALL_SPEED = 50, VERT_ACCEL = 8,
    HOVER_THROTTLE = 0.62, MAX_SPEED = 100, HORIZONTAL_ACCEL = 6.0, FORWARD_LIFT = 10,
}

local fast = Tuning.sanitize({ maxSpeed = 180, climbPower = 40, sensitivity = 1.6 })
local cfgFast = Tuning.applyCfg(BASE, fast)
check("скорость подставлена", cfgFast.MAX_SPEED == 180)
check("тяга подставлена", cfgFast.MAX_CLIMB_SPEED == 40)
check("базовая таблица не испорчена", BASE.MAX_SPEED == 100 and BASE.MAX_CLIMB_SPEED == 26)

local DT = 1 / 60
local function run(state, seconds, input)
    for _ = 1, math.floor(seconds / DT) do
        FlightModel.step(state, DT, input)
    end
end

local sFast = FlightModel.new(cfgFast, 0, 60, 0, 0)
run(sFast, 4, { pitch = 1, roll = 0, yaw = 0, throttle = cfgFast.HOVER_THROTTLE })
check("на быстрых настройках реально летит быстрее 150",
    FlightModel.horizontalSpeed(sFast) > 150,
    string.format("v=%.1f", FlightModel.horizontalSpeed(sFast)))

local slow = Tuning.sanitize({ maxSpeed = 60 })
local cfgSlow = Tuning.applyCfg(BASE, slow)
local sSlow = FlightModel.new(cfgSlow, 0, 60, 0, 0)
run(sSlow, 4, { pitch = 1, roll = 0, yaw = 0, throttle = cfgSlow.HOVER_THROTTLE })
check("на медленных не превышает 60",
    FlightModel.horizontalSpeed(sSlow) <= 60.5,
    string.format("v=%.1f", FlightModel.horizontalSpeed(sSlow)))

local turny = Tuning.sanitize({ yawRate = 8 })
local cfgTurn = Tuning.applyCfg(BASE, turny)
local sTurn = FlightModel.new(cfgTurn, 0, 60, 0, 0)
run(sTurn, 0.5, { pitch = 0, roll = 0, yaw = 1, throttle = 0.5 })
check("быстрый поворот крутит вдвое быстрее",
    math.abs((0 - sTurn.yaw) - 8 * 0.5) < 0.05, string.format("yaw=%.2f", sTurn.yaw))

local softTilt = Tuning.sanitize({ sensitivity = 0.4 })
check("низкая чувствительность уменьшает макс. наклон",
    Tuning.applyCfg(BASE, softTilt).MAX_TILT_DEG < 25,
    tostring(Tuning.applyCfg(BASE, softTilt).MAX_TILT_DEG))

-- ──────────────────────────────────────────────
print("\n[6] Форматирование значений для UI")
check("целое поле без дробей", Tuning.formatField("maxSpeed", 110) == "110")
check("дробное поле с двумя знаками", Tuning.formatField("sensitivity", 1.05) == "1.05")
check("неизвестное поле не падает", type(Tuning.formatField("nope", 1)) == "string")

print("")
if failures == 0 then
    print("ИТОГ: все тесты настроек прошли")
    os.exit(0)
else
    print(string.format("ИТОГ: провалено тестов: %d", failures))
    os.exit(1)
end
