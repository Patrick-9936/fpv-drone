local DroneConfig = {}

-- ── ТОЧКА СПАВНА ДРОНА (на посадочной площадке) ──
DroneConfig.DRONE_SPAWN = Vector3.new(25, 1.8, 0)

-- ── АВТОСПАВН ──
DroneConfig.RESPAWN_INTERVAL = 2    -- каждые 2 секунды проверяем площадку

-- ── ФИЗИКА ПОЛЁТА ──
DroneConfig.MAX_TILT_DEG    = 38    -- комфортный угол наклона (градусы)
DroneConfig.TILT_LERP_SPEED = 8.5   -- плавный, стабильный отклик на стики
DroneConfig.YAW_SPEED       = 3.0   -- скорость поворота курса (рад/с)
DroneConfig.MAX_CLIMB_SPEED = 32    -- макс вертикальная скорость подъема (стад/с)
DroneConfig.MAX_FALL_SPEED  = 24    -- макс вертикальная скорость спуска (стад/с)
DroneConfig.MAX_SPEED       = 75    -- макс горизонтальная скорость (стад/с)
DroneConfig.HORIZONTAL_DRAG = 1.2   -- стабильное сопротивление воздуха (дрон не улетает неуправляемо)

-- ── КАМЕРА ──
DroneConfig.CAM_TILT = 16           -- угол наклона FPV камеры вверх

-- ── СТОЛКНОВЕНИЯ И ВЗРЫВЫ ──
DroneConfig.MIN_COLLISION_SPEED = 45 -- взрыв ТОЛЬКО при сильном ударе о стену (от 45 стад/с)
DroneConfig.TAKEOFF_GRACE_TIME  = 5.0 -- 5 секунд защиты при взлёте

-- ── ГРАНИЦЫ КАРТЫ ──
DroneConfig.BOUNDS_RADIUS      = 400
DroneConfig.BOUNDS_MIN_Y       = -15
DroneConfig.BOUNDS_MAX_Y       = 320

-- ── ЗВУКИ ──
DroneConfig.SOUND_MOTOR     = "rbxassetid://686885384"
DroneConfig.SOUND_EXPLOSION = "rbxassetid://3802269741"
DroneConfig.SOUND_BEEP      = "rbxasset://sounds/electronicpingshort.wav"

return DroneConfig
