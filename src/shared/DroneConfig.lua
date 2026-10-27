local DroneConfig = {}

-- ── ТОЧКА СПАВНА ДРОНА (на посадочной площадке) ──
DroneConfig.DRONE_SPAWN = Vector3.new(25, 1.6, 0)

-- ── АВТОСПАВН ──
DroneConfig.RESPAWN_INTERVAL = 3    -- каждые 3 секунды проверяем площадку и спавним новый дрон

-- ── ФИЗИКА ПОЛЁТА ──
DroneConfig.MAX_TILT_DEG    = 45    -- максимальный наклон (градусы)
DroneConfig.TILT_LERP_SPEED = 9.0   -- скорость возврата/наклона
DroneConfig.YAW_SPEED       = 3.2   -- скорость разворота (360 градусов)
DroneConfig.HOVER_THRUST    = 196.2 -- компенсация гравитации Roblox
DroneConfig.MAX_THRUST_MULT = 2.8   -- ускорение при 100% газе (2.8× веса)
DroneConfig.HORIZONTAL_DRAG = 0.85  -- сопротивление воздуха (реалистичный накат)
DroneConfig.MAX_SPEED       = 110   -- макс скорость для HUD (стад/с)

-- ── КАМЕРА ──
DroneConfig.CAM_TILT = 20           -- угол камеры FPV вверх (градусы)

-- ── ВЗРЫВ И СТОЛКНОВЕНИЯ ──
DroneConfig.EXPLOSION_RADIUS    = 28
DroneConfig.EXPLOSION_POWER     = 380
DroneConfig.MIN_COLLISION_SPEED = 18 -- скорость для срабатывания взрыва при ударе

-- ── ГРАНИЦЫ КАРТЫ ──
DroneConfig.BOUNDS_RADIUS      = 400
DroneConfig.BOUNDS_MIN_Y       = -15
DroneConfig.BOUNDS_MAX_Y       = 320
DroneConfig.OUT_OF_BOUNDS_TIME = 2.0 -- секунды до автоподрыва за картой

-- ── ЗВУКИ ──
DroneConfig.SOUND_MOTOR     = "rbxassetid://686885384"
DroneConfig.SOUND_EXPLOSION = "rbxassetid://3802269741"
DroneConfig.SOUND_BEEP      = "rbxasset://sounds/electronicpingshort.wav"

return DroneConfig
