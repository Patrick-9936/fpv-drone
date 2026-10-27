local DroneConfig = {}

-- Drone spawn position (on the landing pad)
DroneConfig.DRONE_SPAWN = Vector3.new(25, 2, 0)

-- Flight Physics (smooth quadcopter with Angle-mode stabilization)
DroneConfig.CLIMB_SPEED = 35          -- studs/s max upward speed
DroneConfig.DESCENT_SPEED = 28        -- studs/s max downward speed
DroneConfig.MAX_TILT_DEG = 48         -- max pitch/roll angle in Stabilized mode
DroneConfig.TILT_LERP_SPEED = 7.5     -- how snappy rotation follows sticks
DroneConfig.YAW_SPEED = 2.6           -- rad/s (360 turning)
DroneConfig.ACRO_ROT_SPEED = 4.0      -- rad/s for Acro 360 mode
DroneConfig.HORIZONTAL_ACCEL = 70     -- studs/s^2 forward/sideways push
DroneConfig.HORIZONTAL_DRAG = 1.8     -- air resistance to prevent endless drifting
DroneConfig.MAX_SPEED = 85            -- max studs/s speed limit

-- Camera & FPV
DroneConfig.CAM_TILT = 18             -- degrees up-tilt on FPV camera

-- Explosion & Collision
DroneConfig.EXPLOSION_RADIUS = 28
DroneConfig.EXPLOSION_POWER = 400
DroneConfig.MIN_COLLISION_SPEED = 12  -- studs/s to trigger explosion

-- Map Boundaries (prevents flying into void / losing drone)
DroneConfig.BOUNDS_RADIUS = 380       -- max studs from center
DroneConfig.BOUNDS_MIN_Y = -5         -- min altitude
DroneConfig.BOUNDS_MAX_Y = 280        -- max altitude
DroneConfig.OUT_OF_BOUNDS_TIME = 2.5  -- seconds before auto-detonation

-- Respawn
DroneConfig.RESPAWN_TIME = 3          -- seconds after explosion to respawn

-- Sound IDs (Roblox verified public audio)
DroneConfig.SOUND_MOTOR = "rbxassetid://686885384"      -- helicopter/propeller loop
DroneConfig.SOUND_EXPLOSION = "rbxassetid://3802269741"  -- loud explosion
DroneConfig.SOUND_BEEP = "rbxasset://sounds/electronicpingshort.wav"
DroneConfig.SOUND_STATIC = "rbxasset://sounds/button.wav"

return DroneConfig
