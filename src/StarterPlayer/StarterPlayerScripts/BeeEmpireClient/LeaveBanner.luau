--[[
	LeaveBanner - "Your Bees Earn Offline!" in rainbow letters, at the top and at the bottom
	of the screen, whenever the player opens Roblox's own menu (the one with the Leave button).
	It reminds them, just before they go, that their bees keep working and that coming back
	is worth it.

	Roblox draws its menu on top of everything a game can draw, so the two lines sit behind
	the menu and show through it. Nothing here covers or changes Roblox's menu.
]]

local GuiService = game:GetService("GuiService")

local Kit = require(script.Parent.UIKit)

local LeaveBanner = {}

local TEXT = "Your Bees Earn Offline!"
-- where the middle of each line sits, as a share of the screen's height
local LINES = { Top = 0.075, Bottom = 0.915 }

function LeaveBanner.Init(playerGui: Instance)
	local gui = Kit.Create("ScreenGui", {
		Name = "BeeEmpireLeaveBanner",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 40,
		Enabled = false,
		Parent = playerGui,
	})
	for name, height in LINES do
		local line = Kit.Label({
			Parent = gui,
			Name = name,
			Text = TEXT,
			TextSize = 76,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, height),
			Size = UDim2.fromScale(0.92, 0.11),
			Stroke = 5,
			Fit = true, -- shrinks on small screens
		})
		Kit.SetRainbow(line, true)
	end

	GuiService.MenuOpened:Connect(function()
		gui.Enabled = true
	end)
	GuiService.MenuClosed:Connect(function()
		gui.Enabled = false
	end)
	gui.Enabled = GuiService.MenuIsOpen
end

return LeaveBanner
