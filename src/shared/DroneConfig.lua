local DroneConfig = {}

-- Точка спавна дрона (на посадочной площадке)
DroneConfig.DRONE_SPAWN = Vector3.new(25, 2.5, 0)

-- ── ФИЗИКА ПОЛЁТА ──
-- (VectorForce + BodyGyro — без BodyVelocity)
DroneConfig.MAX_TILT_DEG    = 45      -- макс наклон в Stabilized mode (градусы)
DroneConfig.TILT_LERP_SPEED = 8.0    -- скорость отклика на стики
DroneConfig.YAW_SPEED       = 2.8    -- рад/с рыскания
DroneConfig.MAX_SPEED       = 80     -- макс скорость (стад/с) — для HUD

-- ── КАМЕРА ──
DroneConfig.CAM_TILT = 20            -- наклон FPV-камеры вверх (градусы)

-- ── ВЗРЫВ ──
DroneConfig.EXPLOSION_RADIUS    = 25
DroneConfig.EXPLOSION_POWER     = 350
DroneConfig.MIN_COLLISION_SPEED = 12 -- стад/с для триггера взрыва

-- ── ГРАНИЦЫ КАРТЫ ──
DroneConfig.BOUNDS_RADIUS      = 380
DroneConfig.BOUNDS_MIN_Y       = -8
DroneConfig.BOUNDS_MAX_Y       = 300
DroneConfig.OUT_OF_BOUNDS_TIME = 2.5 -- сек до подрыва

-- ── РЕСТАРТ ──
DroneConfig.RESPAWN_TIME = 3         -- сек после взрыва до нового дрона

-- ── ЗВУКИ ──
DroneConfig.SOUND_MOTOR     = "rbxassetid://686885384"
DroneConfig.SOUND_EXPLOSION = "rbxassetid://3802269741"
DroneConfig.SOUND_BEEP      = "rbxasset://sounds/electronicpingshort.wav"

return DroneConfig
