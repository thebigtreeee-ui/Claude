-- Ice Beam (client): click while holding the tool to fire toward the mouse.
local Players = game:GetService("Players")

local tool = script.Parent
local remote = tool:WaitForChild("FireBeam")
local mouse = Players.LocalPlayer:GetMouse()

local COOLDOWN = 1.2
local lastFire = 0

tool.Activated:Connect(function()
	local now = os.clock()
	if now - lastFire < COOLDOWN then
		return
	end
	lastFire = now
	remote:FireServer(mouse.Hit.Position)
end)
