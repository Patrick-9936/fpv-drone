--[[
    Records — сохранение рекордов и настроек + таблица лучших кругов.

    Игровая логика сюда не лезет: скрипт только поднимает хранилище
    (PlayerData.attach) и отдаёт клиенту глобальный топ по запросу.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerData = require(ReplicatedStorage:WaitForChild("PlayerData"))

-- Ремуты живут в той же папке, что и остальные (её создаёт DroneServer,
-- поэтому на всякий случай создаём сами — порядок запуска скриптов не гарантирован).
local remotes = ReplicatedStorage:FindFirstChild("DroneRemotes")
if not remotes then
    remotes = Instance.new("Folder")
    remotes.Name = "DroneRemotes"
    remotes.Parent = ReplicatedStorage
end

local getTop = remotes:FindFirstChild("GetTopRecords")
if not getTop then
    getTop = Instance.new("RemoteFunction")
    getTop.Name = "GetTopRecords"
    getTop.Parent = remotes
end

getTop.OnServerInvoke = function(player)
    return PlayerData.getTop(10)
end

PlayerData.attach()

print("[Records] Рекорды и настройки сохраняются в DataStore")
