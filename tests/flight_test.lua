--[[
    Локальный тест модели полёта: обычный Lua, без Roblox.
    Запуск:  lua fpv-drone/tests/flight_test.lua
    Проверяет именно те баги, из-за которых дрон «не летал»:
    проседание на висении, потеря высоты при наклоне, разгон/торможение, курс.
]]

local scriptDir = arg and arg[0] and arg[0]:match("^(.*)/[^/]*$") or "."
package.path = scriptDir .. "/../src/shared/?.lua;" .. package.path

math.clamp = function(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi else return v end
end

local FlightModel = require("FlightModel")

-- Те же числа, что в DroneConfig
local CFG = {
    MAX_TILT_DEG     = 32,
    TILT_LERP_SPEED  = 7,
    YAW_SPEED        = 2.4,
    MAX_CLIMB_SPEED  = 26,
    MAX_FALL_SPEED   = 30,
    VERT_ACCEL       = 7,
    MAX_SPEED        = 70,
    HORIZONTAL_ACCEL = 3.2,
}

local DT = 1 / 60
local failures = 0

local function check(name, cond, detail)
    if cond then
        print(string.format("  PASS  %s", name))
    else
        failures = failures + 1
        print(string.format("  FAIL  %s   %s", name, detail or ""))
    end
end

local function run(s, seconds, input)
    local steps = math.floor(seconds / DT)
    for _ = 1, steps do
        FlightModel.step(s, DT, input)
    end
    return steps * DT
end

local NEUTRAL = { pitch = 0, roll = 0, yaw = 0, throttle = 0.5 }

-- ──────────────────────────────────────────────
print("\n[1] Висение: стики в центре не должны ронять дрон")
local s = FlightModel.new(CFG, 25, 6.5, 0, 0)
local y0 = s.y
run(s, 10, NEUTRAL)
check("высота не изменилась за 10 секунд",
    math.abs(s.y - y0) < 0.01, string.format("dy=%.4f", s.y - y0))
check("нет паразитной скорости",
    FlightModel.speed(s) < 0.01, string.format("v=%.4f", FlightModel.speed(s)))

-- ──────────────────────────────────────────────
print("\n[2] Газ вверх: скорость набора выходит на предел")
s = FlightModel.new(CFG, 25, 6.5, 0, 0)
run(s, 4, { pitch = 0, roll = 0, yaw = 0, throttle = 1 })
check("летит вверх", s.y > y0 + 60, string.format("dy=%.1f", s.y - y0))
check("скорость ≈ MAX_CLIMB_SPEED",
    math.abs(s.vy - CFG.MAX_CLIMB_SPEED) < 0.5, string.format("vy=%.2f", s.vy))

-- ──────────────────────────────────────────────
print("\n[3] Наклон вперёд не должен ронять высоту")
s = FlightModel.new(CFG, 0, 50, 0, 0)
local yBefore = s.y
run(s, 3, { pitch = 1, roll = 0, yaw = 0, throttle = 0.5 })
check("высота та же", math.abs(s.y - yBefore) < 0.01, string.format("dy=%.4f", s.y - yBefore))
check("летит вперёд (-Z)", s.z < -100, string.format("z=%.1f", s.z))
check("разогнался до ~MAX_SPEED",
    math.abs(FlightModel.horizontalSpeed(s) - CFG.MAX_SPEED) < 0.5,
    string.format("v=%.2f", FlightModel.horizontalSpeed(s)))

-- ──────────────────────────────────────────────
print("\n[4] Курс: стик вправо поворачивает вправо, влево — влево")
-- 0.25 с поворота ≈ 0.6 рад (34°): нос уходит из -Z в сторону +X
s = FlightModel.new(CFG, 0, 50, 0, 0)
run(s, 0.25, { pitch = 0, roll = 0, yaw = 1, throttle = 0.5 })
check("yaw ушёл примерно на YAW_SPEED * t",
    math.abs((0 - s.yaw) - CFG.YAW_SPEED * 0.25) < 0.05, string.format("yaw=%.3f", s.yaw))
check("нос смотрит вправо (+X)", -math.sin(s.yaw) > 0.3,
    string.format("forward.x=%.2f", -math.sin(s.yaw)))

local sx = FlightModel.new(CFG, 0, 50, 0, 0)
run(sx, 0.25, { pitch = 0, roll = 0, yaw = -1, throttle = 0.5 })
check("стик влево уводит нос в -X", -math.sin(sx.yaw) < -0.3,
    string.format("forward.x=%.2f", -math.sin(sx.yaw)))

-- ──────────────────────────────────────────────
print("\n[5] Отпустил стик — дрон тормозит плавно, а не колом")
s = FlightModel.new(CFG, 0, 50, 0, 0)
run(s, 3, { pitch = 1, roll = 0, yaw = 0, throttle = 0.5 })
local vMax = FlightModel.horizontalSpeed(s)
run(s, 0.1, NEUTRAL)
local vAfter = FlightModel.horizontalSpeed(s)
check("через 0.1 с скорость ещё почти прежняя (>85%)", vAfter / vMax > 0.85,
    string.format("%.2f", vAfter / vMax))
run(s, 3, NEUTRAL)
check("через 3 с почти остановился", FlightModel.horizontalSpeed(s) < 1,
    string.format("v=%.3f", FlightModel.horizontalSpeed(s)))

-- ──────────────────────────────────────────────
print("\n[6] Снижение: скорость падения ограничена")
s = FlightModel.new(CFG, 0, 100, 0, 0)
run(s, 4, { pitch = 0, roll = 0, yaw = 0, throttle = 0 })
check("падение ограничено MAX_FALL_SPEED",
    math.abs(s.vy + CFG.MAX_FALL_SPEED) < 0.5, string.format("vy=%.2f", s.vy))
-- 4 с снижения, первые ~0.4 с уходят на разгон
local expected = 4 * CFG.MAX_FALL_SPEED - 10
check("снизился примерно на 4 с * MAX_FALL_SPEED",
    math.abs((100 - s.y) - expected) < 12,
    string.format("спуск=%.1f, ожидали ~%.1f", 100 - s.y, expected))

-- ──────────────────────────────────────────────
print("\n[7] Крен уводит вправо и держит высоту")
s = FlightModel.new(CFG, 0, 80, 0, 0)
local yb = s.y
run(s, 2, { pitch = 0, roll = 1, yaw = 0, throttle = 0.5 })
check("сместился вправо (+X)", s.x > 50, string.format("x=%.1f", s.x))
check("высота та же", math.abs(s.y - yb) < 0.01, string.format("dy=%.4f", s.y - yb))

-- ──────────────────────────────────────────────
print("\n[8] Защита от лагов: огромный dt не телепортирует дрон")
s = FlightModel.new(CFG, 0, 50, 0, 0)
FlightModel.step(s, 5.0, { pitch = 1, roll = 0, yaw = 0, throttle = 0.5 })
check("один шаг при dt=5 сдвигает не больше чем на ~7 стад",
    math.abs(s.z) < 7, string.format("dz=%.2f", s.z))

print("")
if failures == 0 then
    print("ИТОГ: все тесты прошли")
    os.exit(0)
else
    print(string.format("ИТОГ: провалено тестов: %d", failures))
    os.exit(1)
end
