local DroneConfig = {}

-- ── ТОЧКА СПАВНА ДРОНА (парит над посадочной площадкой) ──
-- PadBase стоит на высоте 0.3, поэтому дрон висит в 6 стадах над ней.
DroneConfig.DRONE_SPAWN = Vector3.new(25, 6.5, 0)
DroneConfig.HOVER_HEIGHT = 6.5

-- ── СПАВН ──
DroneConfig.RESPAWN_INTERVAL = 2     -- проверяем площадку раз в 2 секунды
DroneConfig.MAX_DRONES       = 3     -- больше дронов в мире не держим
DroneConfig.PAD_CLEAR_RADIUS = 10    -- ближе этого к площадке новый дрон не спавним
DroneConfig.IDLE_LIFETIME    = 120   -- забытый ничейный дрон убираем через 2 минуты
DroneConfig.PARK_FALL_SPEED  = 14    -- скорость автоспуска после выхода из дрона

-- ── ФИЗИКА ПОЛЁТА ──
DroneConfig.MAX_TILT_DEG     = 32    -- максимальный угол наклона
DroneConfig.TILT_LERP_SPEED  = 7     -- плавность отклика на стики
DroneConfig.YAW_SPEED        = 2.4   -- скорость поворота курса (рад/с)
DroneConfig.MAX_CLIMB_SPEED  = 26    -- макс. вертикальная скорость вверх (стад/с)
DroneConfig.MAX_FALL_SPEED   = 50    -- макс. вертикальная скорость падения (стад/с)
DroneConfig.VERT_ACCEL       = 8     -- плавность изменения высоты
DroneConfig.HOVER_THROTTLE   = 0.62  -- единственное положение газа, где дрон висит
                                     -- (0.5 = брошенный стик = проседает, 0 = падает)
DroneConfig.MAX_SPEED        = 70    -- макс. горизонтальная скорость (стад/с)
DroneConfig.HORIZONTAL_ACCEL = 3.2   -- разгон/торможение по горизонтали
DroneConfig.INPUT_TIMEOUT    = 0.5   -- если ввод пропал — считаем газ полностью убранным

-- ── КАМЕРА ──
DroneConfig.CAM_TILT = 14            -- наклон FPV-камеры вверх (градусы)

-- ── КОЛЛИЗИИ ──
DroneConfig.CRASH_SPEED  = 55   -- взрыв только при лобовом ударе о стену на такой скорости
DroneConfig.BODY_RADIUS  = 1.3  -- радиус корпуса для проверки стен
DroneConfig.GROUND_OFFSET = 1.15 -- насколько центр дрона выше поверхности при посадке

-- ── ГРАНИЦЫ КАРТЫ ──
DroneConfig.BOUNDS_RADIUS = 400
DroneConfig.BOUNDS_MIN_Y  = -30
DroneConfig.BOUNDS_MAX_Y  = 320

-- ── ЗВУКИ ──
DroneConfig.SOUND_MOTOR     = "rbxassetid://686885384"
DroneConfig.SOUND_EXPLOSION = "rbxassetid://3802269741"
DroneConfig.SOUND_BEEP      = "rbxasset://sounds/electronicpingshort.wav"

return DroneConfig
