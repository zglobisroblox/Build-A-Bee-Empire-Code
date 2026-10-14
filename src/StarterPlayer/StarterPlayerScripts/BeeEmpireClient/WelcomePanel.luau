--[[
	WelcomePanel - the "Welcome Back!" window.

	Bees keep working while their owner is away (see OfflineService on the server). When a
	player comes back and honey is waiting for them, this window opens by itself. It says how
	long they were away and how many jars the bees made, and has one Collect button.
	Closing the window with the red X collects too, so nobody can lose their honey.

	The numbers come from the server (through State). The button only sends a request.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage:WaitForChild("BeeEmpire")
local GameConfig = require(sharedFolder:WaitForChild("GameConfig"))
local NumberFormat = require(sharedFolder:WaitForChild("NumberFormat"))
local remotes = sharedFolder:WaitForChild("Remotes")

local Kit = require(script.Parent.UIKit)
local State = require(script.Parent.State)

local WelcomePanel = {}

local WIDTH = 640
local HEIGHT = 456
local HEADER_COLOR = Color3.fromRGB(52, 208, 150) -- mint
local NOTE_COLOR = Color3.fromRGB(214, 218, 232)
local OPEN_AFTER = 1.5 -- seconds after joining before the window pops up, so the player sees their hive first

local panel
local awayText: TextLabel
local amountText: TextLabel
local offered = false -- the window opens by itself only once per visit

local function centred(icon: GuiObject)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
end

-- "3 h 12 min" or "25 min". At the longest time that counts: "4 hours or more".
local function awayWords(seconds: number): string
	if seconds >= GameConfig.OfflineMaxHours * 3600 then
		return string.format("%g hours or more", GameConfig.OfflineMaxHours)
	end
	local minutes = math.max(1, math.floor(seconds / 60))
	local hours = minutes // 60
	if hours > 0 then
		return string.format("%d h %02d min", hours, minutes % 60)
	end
	return minutes .. " min"
end

-- "half speed", or "25% speed"
local function speedWords(): string
	local speed = GameConfig.OfflineSpeed
	if speed == 0.5 then
		return "half speed"
	elseif speed == 1 then
		return "full speed"
	end
	return string.format("%d%% speed", math.floor(speed * 100 + 0.5))
end

local function refresh()
	local jars = State.Number("OfflineJars")
	if jars <= 0 then
		return -- nothing waiting (or just collected: leave the numbers alone while the window closes)
	end
	awayText.Text = "You were away for " .. awayWords(State.Number("OfflineSeconds"))
	amountText.Text = "+" .. NumberFormat.Short(jars) .. (if jars == 1 then " jar" else " jars")

	if State.IsLoaded() and not State.LoadingScreenUp() and not offered then
		offered = true
		task.delay(OPEN_AFTER, function()
			if State.Number("OfflineJars") > 0 then
				panel.Open()
			end
		end)
	end
end

function WelcomePanel.Init(gui: ScreenGui)
	panel = Kit.Panel({
		Parent = gui,
		Name = "WelcomePanel",
		Title = "Offline Honey",
		Size = Vector2.new(WIDTH, HEIGHT),
		HeaderColor = HEADER_COLOR,
		Icon = function(holder)
			centred(Kit.JarIcon(holder, 84))
		end,
	})
	local content = panel.Content

	Kit.Label({
		Parent = content,
		Name = "Headline",
		Text = "Welcome Back!",
		TextSize = 60,
		Color = Kit.Colors.Select,
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(1, 0, 0, 70),
		Stroke = 5,
		Fit = true,
	})
	awayText = Kit.Label({
		Parent = content,
		Name = "Away",
		Text = "",
		TextSize = 27,
		Color = Kit.Colors.Cream,
		Position = UDim2.fromOffset(0, 72),
		Size = UDim2.new(1, 0, 0, 32),
		Fit = true,
	})

	-- what the bees made: a jar and the number
	local box = Kit.Box(content, UDim2.new(0.5, -230, 0, 114), UDim2.fromOffset(460, 112), nil, "Made")
	local jarArea = Kit.Create("Frame", {
		Name = "Jar",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(18, 14),
		Size = UDim2.fromOffset(84, 84),
		Parent = box,
	})
	centred(Kit.JarIcon(jarArea, 80))
	Kit.Label({
		Parent = box,
		Name = "Caption",
		Text = "Your bees made",
		TextSize = 23,
		XAlign = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(116, 12),
		Size = UDim2.new(1, -132, 0, 28),
		Fit = true,
	})
	amountText = Kit.Label({
		Parent = box,
		Name = "Amount",
		Text = "",
		TextSize = 52,
		Color = Kit.Colors.Honey,
		XAlign = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(116, 40),
		Size = UDim2.new(1, -132, 0, 60),
		Stroke = 5,
		Fit = true,
	})

	Kit.Label({
		Parent = content,
		Name = "Note",
		-- (kept short and fairly big: on a small phone the whole window is shown at about half size)
		Text = string.format("Away, your bees work at %s for up to %g hours.", speedWords(), GameConfig.OfflineMaxHours),
		TextSize = 25,
		Color = NOTE_COLOR,
		Position = UDim2.fromOffset(0, 230),
		Size = UDim2.new(1, 0, 0, 34),
		Fit = true,
	})

	Kit.Button({
		Parent = content,
		Name = "Collect",
		Text = "Collect",
		TextSize = 36,
		Color = Kit.Colors.Green,
		Size = UDim2.fromOffset(290, 70),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -2),
		OnClick = function()
			panel.Close()
		end,
	})

	-- however the window closes (Collect, the red X, another window opening), the honey is collected
	panel.OnClose = function()
		if State.Number("OfflineJars") > 0 then
			remotes.ClaimOffline:FireServer() -- only a request: the server knows how much is waiting
		end
	end

	State.Changed:Connect(refresh)
	refresh()
end

return WelcomePanel
