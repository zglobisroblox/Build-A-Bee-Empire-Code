--[[
	ProductionService - the money loop:
	- bees bring honey home from the Flower Garden, and worker bees carry it from the hive
	  to the plot's Honey Jars (HiveService keeps those clocks)
	- how much the Honey Jars can hold depends on the hive level
	- Collect ("Grab Jars") moves every jar from the Honey Jars into the player's arms: they
	  hold them up in a stack above their head, and can carry as many as they like
	- Sell turns carried jars into Honey Coins, at the Honey Market's price right now
	  (MarketService picks that price: it changes every half minute)

	The server owns every number here. A player's device can never set its own jars or coins.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.BeeEmpire.GameConfig)
local NumberFormat = require(ReplicatedStorage.BeeEmpire.NumberFormat)
local Studs = require(ReplicatedStorage.BeeEmpire.Studs)
local DataService = require(script.Parent.DataService)
local HiveService = require(script.Parent.HiveService)
local MarketService = require(script.Parent.MarketService)
local Notifier = require(script.Parent.Notifier)
local PassService = require(script.Parent.PassService)
local PlotService = require(script.Parent.PlotService)
local TutorialService = require(script.Parent.TutorialService)

local ProductionService = {}

local WHITE = Color3.fromRGB(255, 255, 255)
-- how much of the jar-shaped sign the honey covers when there is none, and when every jar on the stand is showing
local SIGN_HONEY_EMPTY = 0.14
local SIGN_HONEY_FULL = 0.9
local JAR_COLOR = Color3.fromRGB(255, 170, 30)
local LID_COLOR = Color3.fromRGB(250, 242, 225)
local INK = Color3.fromRGB(20, 16, 24)

local shownStored: { [Model]: number } = {} -- how many jars each plot's Honey Jars sign is currently showing

-- THE HONEY JARS ---------------------------------------------------------------------

-- How many of the stand's jars to show for this many waiting jars (GameConfig.JarsShownSteps).
local function jarsShownFor(stored: number): number
	local count = 0
	for _, needed in GameConfig.JarsShownSteps do
		if stored >= needed then
			count += 1
		end
	end
	return count
end

-- There is no limit on how many jars can wait here. The stand just shows more jars, and the
-- honey in the sign rises, the more there are.
local function updateStation(plot: Model, stored: number)
	if shownStored[plot] == stored then
		return
	end
	shownStored[plot] = stored

	local station = plot:FindFirstChild("CollectStation")
	local jars = station and station:FindFirstChild("Jars")
	local shownJars = jarsShownFor(stored)

	-- the big jar-shaped sign: the number, and the honey that rises inside it
	local sign = station and station:FindFirstChild("Sign")
	local signFace = sign and sign:FindFirstChild("Face")
	local amount = signFace and signFace:FindFirstChild("Amount")
	if amount then
		amount.Text = NumberFormat.Short(stored)
	end
	local honey = signFace and signFace:FindFirstChild("Honey")
	if honey then
		local filled = shownJars / math.max(1, #GameConfig.JarsShownSteps)
		honey.Size = UDim2.fromScale(1, SIGN_HONEY_EMPTY + (SIGN_HONEY_FULL - SIGN_HONEY_EMPTY) * filled)
	end

	-- the more honey there is, the more of the jars you can see
	if jars then
		for _, jar in jars:GetChildren() do
			local transparency = if (jar:GetAttribute("Order") or 0) <= shownJars then 0 else 1
			jar.Transparency = transparency
			for _, piece in jar:GetChildren() do -- its lid and label
				if piece:IsA("BasePart") then
					piece.Transparency = transparency
				end
			end
		end
	end
end

-- THE STACK OF JARS A PLAYER HOLDS UP ------------------------------------------------------
-- The server builds the stack (a Model called HoneyStack inside the character). Every
-- player's screen then lifts the arms of anyone who has one (see WorldFX).

-- How many jars tall the stack is for this many carried jars (GameConfig.CarryStackSteps).
local function stackHeightFor(carried: number): number
	local count = 0
	for _, needed in GameConfig.CarryStackSteps do
		if carried >= needed then
			count += 1
		end
	end
	return math.max(1, count)
end

-- Rebuilds the stack of jars above the player's head (or removes it when they carry nothing).
-- The stack is a picture of how much they carry; the sign on top shows the real number.
-- It is fixed to the chest, the same body part the arms hang from, so the stack and the
-- raised arms always move together.
local function updateCarry(player: Player, carried: number)
	local character = player.Character
	if not character then
		return
	end

	for _, name in { "HoneyStack", "HoneyPack" } do
		local existing = character:FindFirstChild(name)
		if existing then
			existing:Destroy()
		end
	end
	if carried <= 0 then
		return
	end

	local head = character:FindFirstChild("Head")
	local chest = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if not head or not head:IsA("BasePart") or not chest or not chest:IsA("BasePart") then
		return
	end

	local stack = Instance.new("Model")
	stack.Name = "HoneyStack"

	-- the stack stands straight above the head, facing the way the chest faces
	local base = CFrame.new(head.Position) * chest.CFrame.Rotation

	local function piece(name: string, size: Vector3, offset: CFrame, color: Color3): Part
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.CFrame = base * offset
		part.Color = color
		part.Material = Enum.Material.SmoothPlastic
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.Massless = true
		part.CastShadow = false
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = chest
		weld.Part1 = part
		weld.Parent = part
		part.Parent = stack
		return part
	end

	local count = stackHeightFor(carried)
	local baseY = head.Size.Y / 2 + 0.5 -- just above the head, resting on the raised hands
	local topJar: Part? = nil
	for index = 1, count do
		local y = baseY + (index - 1) * 1.5
		-- a little zig-zag and a turn, so the pile looks hand-stacked
		local lean = ((index % 2) * 2 - 1) * 0.12
		local turn = CFrame.Angles(0, math.rad((index * 37) % 30 - 15), 0)
		local jar = piece("Jar" .. index, Vector3.new(1.5, 1.2, 1.5), CFrame.new(lean, y + 0.6, 0) * turn, JAR_COLOR)
		Studs.Add(jar, 0.75)
		piece("Lid" .. index, Vector3.new(1.65, 0.3, 1.65), CFrame.new(lean, y + 1.35, 0) * turn, LID_COLOR)
		topJar = jar
	end

	-- a sign above the pile: how many jars
	if topJar then
		local bubble = Instance.new("BillboardGui")
		bubble.Name = "CarrySign"
		bubble.Size = UDim2.fromScale(5, 1.4)
		bubble.StudsOffsetWorldSpace = Vector3.new(0, 2.2, 0)
		bubble.MaxDistance = 70
		bubble.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.FredokaOne
		label.Text = NumberFormat.Short(carried) .. (if carried == 1 then " jar" else " jars")
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(255, 226, 60)
		label.Parent = bubble
		local stroke = Instance.new("UIStroke")
		stroke.Color = INK
		stroke.LineJoinMode = Enum.LineJoinMode.Round
		stroke.StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize
		stroke.Thickness = 0.08
		stroke.Parent = label
		bubble.Parent = topJar
	end

	stack.Parent = character
end

-- PRODUCTION -------------------------------------------------------------------------

-- Jars made per second (on average) by all the bees working in a player's hive.
function ProductionService.GetRate(data): number
	local rate = 0
	for _, bee in data.Cells do
		rate += GameConfig.Bees[bee.Rarity].NectarPerSecond
	end
	return rate
end

-- AUTO SELL (a pass). The honey waiting at the Honey Jars is sold where it stands, at the
-- Honey Market's price right now, once every GameConfig.AutoSellSeconds. The price is the
-- server's own number, exactly as when a player sells by hand.
local nextAutoSellAt: { [Player]: number } = {}
-- VIP (a pass) gives 10% more honey, which can leave part of a jar over. The part is kept
-- here and added to the next delivery, so jars stay whole numbers and nothing is lost.
local partJar: { [Player]: number } = {}

local function autoSell(player: Player, data)
	local now = os.clock()
	if now < (nextAutoSellAt[player] or 0) then
		return
	end
	nextAutoSellAt[player] = now + GameConfig.AutoSellSeconds
	local earned = MarketService.Worth(data.JarsStored)
	if earned <= 0 then
		return -- too little honey to be worth a coin yet: it waits for more
	end
	data.JarsStored = 0
	data.Coins += earned
	DataService.Replicate(player) -- (the coin counter on the player's screen counts up: nothing else is shown)
	TutorialService.Mark(player, "Sold") -- (the tutorial: honey sold)
end

-- Called a few times a second by Main. Moves honey along (bees -> hive -> worker bees -> jars)
-- and adds whatever the workers just dropped off to the player's Honey Jars.
function ProductionService.Step(_deltaTime: number)
	for _, player in Players:GetPlayers() do
		local data = DataService.Get(player)
		local plot = PlotService.GetPlot(player)
		if data and plot then
			local arrived = HiveService.StepHoney(plot)
			if arrived > 0 then
				arrived *= DataService.BoostMultiplier(data, "Honey") -- (a Double Honey boost: every jar counts twice)
				local extra = PassService.HoneyMultiplier(player) -- (the VIP pass: a little more honey, always)
				if extra ~= 1 then
					local exact = arrived * extra + (partJar[player] or 0)
					arrived = math.floor(exact + 1e-6)
					partJar[player] = exact - arrived
				end
				data.JarsStored += arrived -- no limit: every jar the workers bring is kept
				player:SetAttribute("JarsStored", data.JarsStored)
			end
			-- (the Auto Sell pass, unless its owner has switched it off)
			if data.JarsStored > 0 and data.Settings.AutoSell ~= false and PassService.Owns(player, "AutoSell") then
				autoSell(player, data)
			end
			updateStation(plot, data.JarsStored)
		end
	end
end

-- PLAYER ACTIONS (the server has already checked who is asking and where they stand) ------

function ProductionService.Collect(player: Player)
	local data = DataService.Get(player)
	local plot = PlotService.GetPlot(player)
	if not data or not plot then
		return
	end

	if data.JarsStored <= 0 then
		if data.Settings.AutoSell ~= false and PassService.Owns(player, "AutoSell") then
			Notifier.Send(player, "Auto Sell is selling your honey for you!", "info")
		else
			Notifier.Send(player, "No honey here yet. Your carrier bees are bringing it!", "info")
		end
		return
	end

	-- grab everything: there is no limit on how many jars a player can carry
	local amount = data.JarsStored
	data.JarsStored = 0
	data.JarsCarried += amount

	Notifier.Effect(player, "Collected", amount)
	updateStation(plot, 0)
	updateCarry(player, data.JarsCarried)
	DataService.Replicate(player)
end

function ProductionService.Sell(player: Player)
	local data = DataService.Get(player)
	if not data then
		return
	end

	if data.JarsCarried <= 0 then
		Notifier.Send(player, "You have no jars to sell. Grab some from your Honey Jars first!", "info")
		return
	end

	-- the price is the server's own number at this moment: the player's screen has no say
	local jars = data.JarsCarried
	local price = MarketService.Price()
	local earned = MarketService.Worth(jars)
	data.JarsCarried = 0
	data.Coins += earned

	Notifier.Effect(player, "Sold", earned)
	Notifier.Send(
		player,
		string.format("Sold %s %s at x%.1f!", NumberFormat.Short(jars), if jars == 1 then "jar" else "jars", price),
		"coins",
		nil,
		price >= GameConfig.SellPriceHigh -- a great price is written in rainbow
	)
	updateCarry(player, 0)
	DataService.Replicate(player)
	TutorialService.Mark(player, "Sold") -- (the tutorial: first honey sold)
end

-- Takes jars out of the stack a player is carrying (the Halloween Egg is paid in jars).
-- Gives false, and takes nothing, if they carry fewer.
function ProductionService.TakeCarried(player: Player, jars: number): boolean
	local data = DataService.Get(player)
	if not data or jars <= 0 or data.JarsCarried < jars then
		return false
	end
	data.JarsCarried -= jars
	updateCarry(player, data.JarsCarried)
	DataService.Replicate(player)
	return true
end

-- JOINING AND LEAVING ------------------------------------------------------------------

-- Puts the stack of jars back on a character that has just appeared (joining or respawning).
-- It waits until the avatar has finished loading, because Roblox rebuilds the body while it
-- loads and anything attached too early falls off.
local function restoreCarry(player: Player, character: Model)
	local deadline = os.clock() + 10
	while os.clock() < deadline and not (player:HasAppearanceLoaded() and character:IsDescendantOf(workspace)) do
		task.wait(0.25)
		if player.Character ~= character then
			return -- they respawned again; the newer character gets its own call
		end
	end
	task.wait() -- one more moment, so the body has finished being built and sized
	local data = DataService.Get(player)
	if data and player.Character == character then
		updateCarry(player, data.JarsCarried)
	end
end

function ProductionService.SetupPlayer(player: Player)
	local data = DataService.Get(player)
	local plot = PlotService.GetPlot(player)
	if not data or not plot then
		return
	end
	updateStation(plot, data.JarsStored)

	player.CharacterAdded:Connect(function(character)
		restoreCarry(player, character)
	end)
	if player.Character then
		task.spawn(restoreCarry, player, player.Character)
	end
end

-- Redraws the Honey Jars and the stack the player holds (used after an upgrade).
function ProductionService.RefreshPlayer(player: Player)
	local data = DataService.Get(player)
	local plot = PlotService.GetPlot(player)
	if not data or not plot then
		return
	end
	updateStation(plot, data.JarsStored)
	updateCarry(player, data.JarsCarried)
end

function ProductionService.CleanupPlayer(player: Player)
	nextAutoSellAt[player] = nil
	partJar[player] = nil
	local plot = PlotService.GetPlot(player)
	if plot then
		ProductionService.ResetPlot(plot)
	end
end

-- Puts a plot's Honey Jars back to empty, and shows the current jar price on the market sign.
function ProductionService.ResetPlot(plot: Model)
	updateStation(plot, 0)

	local market = plot:FindFirstChild("Market")
	local counter = market and market:FindFirstChild("Counter")
	local info = counter and counter:FindFirstChild("Info")
	if info then
		info.Sub.Text = MarketService.SignText()
	end
end

return ProductionService
