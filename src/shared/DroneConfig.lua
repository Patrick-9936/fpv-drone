local DroneConfig = {}

-- Drone spawn position (on the landing pad)
DroneConfig.DRONE_SPAWN = Vector3.new(25, 2, 0)

-- Flight physics
DroneConfig.MAX_THRUST_MULT = 2.5    -- multiplier over hover force (>1 = can climb)
DroneConfig.PITCH_SPEED = 3.5        -- rad/s
DroneConfig.ROLL_SPEED = 3.5         -- rad/s
DroneConfig.YAW_SPEED = 2.8          -- rad/s
DroneConfig.THROTTLE_ACCEL = 1.8     -- how fast throttle ramps 0→1

-- Explosion
DroneConfig.EXPLOSION_RADIUS = 30
DroneConfig.EXPLOSION_POWER = 600
DroneConfig.MIN_COLLISION_SPEED = 15  -- studs/s to trigger boom

-- Respawn
DroneConfig.RESPAWN_TIME = 3

-- Camera
DroneConfig.CAM_TILT = 20  -- degrees, FPV camera up-tilt

return DroneConfig
