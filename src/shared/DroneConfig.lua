local DroneConfig = {}

-- ── ТОЧКА СПАВНА ДРОНА (на посадочной площадке) ──
DroneConfig.DRONE_SPAWN = Vector3.new(25, 1.6, 0)

-- ── АВТОСПАВН ──
DroneConfig.RESPAWN_INTERVAL = 3    -- каждые 3 секунды проверяем площадку

-- ── ФИЗИКА ПОЛЁТА ──
DroneConfig.MAX_TILT_DEG    = 42    -- максимальный наклон тангажа и крена (градусы)
DroneConfig.TILT_LERP_SPEED = 10.0  -- быстрый отзывчивый отклик на стики
DroneConfig.YAW_SPEED       = 3.4   -- скорость поворота курса (рад/с)
DroneConfig.MAX_THRUST_MULT = 3.0   -- ускорение при 100% газе (3× веса)
DroneConfig.HORIZONTAL_DRAG = 0.9   -- сопротивление воздуха (реалистичный накат)
DroneConfig.MAX_SPEED       = 110   -- макс скорость для HUD (стад/с)

-- ── КАМЕРА ──
DroneConfig.CAM_TILT = 18           -- наклон FPV камеры вверх (градусы)

-- ── ВЗРЫВ И СТОЛКНОВЕНИЯ ──
DroneConfig.EXPLOSION_RADIUS    = 28
DroneConfig.EXPLOSION_POWER     = 380
DroneConfig.MIN_COLLISION_SPEED = 10 -- взрыв при ударе на скорости от 10 стад/с

-- ── ГРАНИЦЫ КАРТЫ ──
DroneConfig.BOUNDS_RADIUS      = 400
DroneConfig.BOUNDS_MIN_Y       = -15
DroneConfig.BOUNDS_MAX_Y       = 320

-- ── ЗВУКИ ──
DroneConfig.SOUND_MOTOR     = "rbxassetid://686885384"
DroneConfig.SOUND_EXPLOSION = "rbxassetid://3802269741"
DroneConfig.SOUND_BEEP      = "rbxasset://sounds/electronicpingshort.wav"

return DroneConfig
