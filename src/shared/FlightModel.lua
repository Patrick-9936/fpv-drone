--[[
    FlightModel — детерминированная модель полёта квадрокоптера.

    Чистая математика: не использует ни одного класса Roblox (ни Vector3, ни CFrame),
    поэтому её можно прогонять в обычном Lua и проверять тестами (tests/flight_test.lua).

    Логика:
      * Курс (yaw) крутится стиком.
      * Тангаж/крен плавно тянутся к целевому углу и задают вектор горизонтальной скорости.
      * Газ (throttle) задаёт вертикальную скорость: 0.5 = удержание высоты, 1 = вверх, 0 = вниз.
      * Скорости меняются через ускорение, а не мгновенно — поэтому дрон «тяжёлый», но управляемый.

    Важно: гравитации здесь нет намеренно. Дрон не «борется» с физическим движком,
    поэтому он не проседает на площадку и не теряет высоту при наклоне носа.
]]

local FlightModel = {}

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function lerp(current, target, k)
    return current + (target - current) * k
end

-- Создаёт состояние полёта в мировых координатах.
function FlightModel.new(cfg, x, y, z, yaw)
    return {
        cfg      = cfg,
        x        = x,
        y        = y,
        z        = z,
        yaw      = yaw or 0,   -- +yaw = поворот влево (как в Roblox)
        pitch    = 0,          -- >0 = нос опущен, полёт вперёд
        roll     = 0,          -- >0 = крен вправо
        vx       = 0,
        vy       = 0,
        vz       = 0,
        throttle = 0.5,
    }
end

-- Один шаг интеграции. input = { pitch, roll, yaw, throttle }, все в [-1..1] / [0..1].
function FlightModel.step(s, dt, input)
    local cfg = s.cfg

    -- Защита от фризов и подозрительно больших dt
    if dt <= 0 then return s end
    if dt > 0.1 then dt = 0.1 end

    local inPitch    = clamp(input.pitch or 0, -1, 1)
    local inRoll     = clamp(input.roll or 0, -1, 1)
    local inYaw      = clamp(input.yaw or 0, -1, 1)
    local inThrottle = clamp(input.throttle or 0.5, 0, 1)

    -- 1. Курс: стик вправо (+1) должен поворачивать вправо, а +yaw в Roblox — это влево
    s.yaw = s.yaw - inYaw * cfg.YAW_SPEED * dt

    -- 2. Наклон: плавно тянемся к целевому углу (никаких мгновенных рывков)
    local maxTilt = math.rad(cfg.MAX_TILT_DEG)
    local kTilt   = clamp(cfg.TILT_LERP_SPEED * dt, 0, 1)
    s.pitch = lerp(s.pitch, inPitch * maxTilt, kTilt)
    s.roll  = lerp(s.roll,  inRoll  * maxTilt, kTilt)
    s.throttle = inThrottle

    -- 3. Вертикаль: центр стика = удержание высоты, отклонение = набор/спуск
    local targetVy
    if inThrottle > 0.54 then
        targetVy = ((inThrottle - 0.5) / 0.5) * cfg.MAX_CLIMB_SPEED
    elseif inThrottle < 0.46 then
        targetVy = ((inThrottle - 0.5) / 0.5) * cfg.MAX_FALL_SPEED
    else
        targetVy = 0
    end
    s.vy = lerp(s.vy, targetVy, clamp(cfg.VERT_ACCEL * dt, 0, 1))

    -- 4. Горизонталь: направление зависит только от курса, величина — от наклона
    local sinY, cosY = math.sin(s.yaw), math.cos(s.yaw)
    local fwdX, fwdZ = -sinY, -cosY   -- LookVector в плоскости XZ
    local rgtX, rgtZ =  cosY, -sinY   -- RightVector в плоскости XZ

    local fwdRatio = s.pitch / maxTilt
    local rgtRatio = s.roll  / maxTilt

    local targetVx = (fwdX * fwdRatio + rgtX * rgtRatio) * cfg.MAX_SPEED
    local targetVz = (fwdZ * fwdRatio + rgtZ * rgtRatio) * cfg.MAX_SPEED

    local kH = clamp(cfg.HORIZONTAL_ACCEL * dt, 0, 1)
    s.vx = lerp(s.vx, targetVx, kH)
    s.vz = lerp(s.vz, targetVz, kH)

    -- 5. Интегрируем позицию
    s.x = s.x + s.vx * dt
    s.y = s.y + s.vy * dt
    s.z = s.z + s.vz * dt

    return s
end

function FlightModel.horizontalSpeed(s)
    return math.sqrt(s.vx * s.vx + s.vz * s.vz)
end

function FlightModel.speed(s)
    return math.sqrt(s.vx * s.vx + s.vy * s.vy + s.vz * s.vz)
end

-- Гасит скорость в направлении нормали (скольжение вдоль стены вместо залипания)
function FlightModel.cancelAlongNormal(s, nx, nz)
    local vn = s.vx * nx + s.vz * nz
    if vn < 0 then
        s.vx = s.vx - vn * nx
        s.vz = s.vz - vn * nz
    end
end

return FlightModel
