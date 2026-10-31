local DroneConfig = {}

-- ── ТОЧКА СПАВНА ДРОНА (парит над посадочной площадкой) ──
-- PadBase стоит на высоте 0.3, поэтому дрон висит в 6 стадах над ней.
DroneConfig.DRONE_SPAWN = Vector3.new(25, 6.5, 0)
DroneConfig.HOVER_HEIGHT = 6.5

-- ── СПАВН ──
DroneConfig.RESPAWN_INTERVAL = 2     -- проверяем площадку раз в 2 секунды
DroneConfig.MAX_DRONES       = 4     -- больше дронов в мире не держим
DroneConfig.TAKE_RADIUS      = 90    -- с какого расстояния сервер даёт взять дрон
DroneConfig.PAD_CLEAR_RADIUS = 10    -- ближе этого к площадке новый дрон не спавним
DroneConfig.IDLE_LIFETIME    = 120   -- забытый ничейный дрон убираем через 2 минуты
DroneConfig.PARK_FALL_SPEED  = 14    -- скорость автоспуска после выхода из дрона

-- ── ФИЗИКА ПОЛЁТА ──
DroneConfig.MAX_TILT_DEG     = 48    -- максимальный угол наклона
DroneConfig.TILT_LERP_SPEED  = 12    -- насколько резво дрон ложится в наклон
DroneConfig.YAW_SPEED        = 4.0   -- скорость поворота курса (рад/с)
DroneConfig.MAX_CLIMB_SPEED  = 26    -- макс. вертикальная скорость вверх (стад/с)
DroneConfig.MAX_FALL_SPEED   = 50    -- макс. вертикальная скорость падения (стад/с)
DroneConfig.VERT_ACCEL       = 8     -- плавность изменения высоты
DroneConfig.HOVER_THROTTLE   = 0.62  -- единственное положение газа, где дрон висит
                                     -- (0.5 = брошенный стик = проседает, 0 = падает)
DroneConfig.MAX_SPEED        = 100   -- макс. горизонтальная скорость (стад/с)
DroneConfig.HORIZONTAL_ACCEL = 6.0   -- разгон/торможение по горизонтали
DroneConfig.FORWARD_LIFT     = 10    -- наклон вперёд даёт +10 стад/с высоты
DroneConfig.INPUT_TIMEOUT    = 0.5   -- если ввод пропал — считаем газ полностью убранным
DroneConfig.RELEASE_AFTER    = 2.5   -- столько секунд без ввода — дрон освобождается сам
                                     -- (иначе игрок навсегда занят и новый взять не может)

-- ── КАМЕРА ──
DroneConfig.CAM_TILT = 14            -- наклон FPV-камеры вверх (градусы)

-- ── КОЛЛИЗИИ ──
DroneConfig.CRASH_SPEED  = 26   -- взрыв, если в стену влетаем на такой скорости (нормальная
                               -- составляющая, то есть скольжение вдоль стены не считается)
DroneConfig.GROUND_CRASH_SPEED = 34 -- вертикальный удар о землю на такой скорости — взрыв
DroneConfig.RING_THICKNESS = 4      -- толщина «плоскости» кольца для зачёта прохода
DroneConfig.BODY_RADIUS  = 1.3  -- радиус корпуса для проверки стен
DroneConfig.GROUND_OFFSET = 1.15 -- насколько центр дрона выше поверхности при посадке

-- ── ГОНКА ──
-- Кольца проходятся строго по порядку: 1 -> 2 -> 3 -> финиш круга.
-- normal — ось, вдоль которой «протыкается» кольцо (здесь все кольца смотрят в Z).
DroneConfig.RACE_RINGS = {
    { pos = Vector3.new(35, 14, -40),  radius = 9,  normal = Vector3.new(0, 0, 1) },
    { pos = Vector3.new(35, 18, -90),  radius = 11, normal = Vector3.new(0, 0, 1) },
    { pos = Vector3.new(80, 20, -90),  radius = 12, normal = Vector3.new(0, 0, 1) },
}
DroneConfig.RACE_MIN_LAP = 5        -- круги короче этого не засчитываем (античит на телепорт)

-- ── ХРАНИЛИЩЕ РЕКОРДОВ ──
DroneConfig.RECORD_STORE         = "FPV_Drone_Records_v1"
DroneConfig.RECORD_ORDERED_STORE = "FPV_Drone_BestLap_v1"
DroneConfig.RECORD_AUTOSAVE      = 30   -- секунд между сохранениями (без спама DataStore)

-- ── ГРАНИЦЫ КАРТЫ ──
DroneConfig.BOUNDS_RADIUS = 400
DroneConfig.BOUNDS_MIN_Y  = -30
DroneConfig.BOUNDS_MAX_Y  = 320

-- ── ЗВУКИ ──
DroneConfig.SOUND_MOTOR     = "rbxassetid://686885384"
DroneConfig.SOUND_EXPLOSION = "rbxassetid://3802269741"
DroneConfig.SOUND_BEEP      = "rbxasset://sounds/electronicpingshort.wav"

-- ── МУЗЫКА ──
-- Только лицензированные треки из Creator Store (официальные библиотеки
-- APM Music и DistroKid): они бесплатны и разрешены к использованию в любом
-- опыте. Заливать чужой mp3 (альбом/радио) нельзя — модерация Roblox такой
-- ассет отклоняет, а аккаунт получает страйк.
DroneConfig.MUSIC_MENU          = "rbxassetid://138352099798766"  -- Neon Chase (Cyberpunk Racing)
DroneConfig.MUSIC_RACE          = "rbxassetid://134324160901088"  -- Fast Drum & Bass Action Soundtrack
DroneConfig.MUSIC_VOLUME_MENU   = 0.35
DroneConfig.MUSIC_VOLUME_RACE   = 0.22

return DroneConfig
