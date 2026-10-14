--[[
	HalloweenService - the Halloween Egg, a limited-time event.
	(All its numbers are in GameConfig: THE HALLOWEEN EGG and LIMITED BEES.)

	- While the event is on, a spooky corner with a big pumpkin egg stands next to the Flower
	  Garden. It is kept ready-made in ServerStorage.BeeEmpireEvents.HalloweenCorner and is put
	  into the world when a server starts. A few bushes and stones that stand in the same
	  spot are moved out of the way, and put back afterwards.
	- A player carries honey jars to the egg and presses E. The server checks everything
	  (the event is still on, they stand at the egg, they carry enough jars, a new bee fits),
	  takes the jars, picks a bee with its own dice and gives it. The player's device only asks.
	- When the end day comes the corner vanishes by itself, even on a server that is running.
	  Bees already hatched stay with their owners for ever.

	TESTING, IN ROBLOX STUDIO ONLY: the attribute TestEggEndsIn = seconds on
	ServerStorage.BeeEmpireDev makes the event end that many seconds after the server starts.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local GameConfig = require(ReplicatedStorage.BeeEmpire.GameConfig)
local NumberFormat = require(ReplicatedStorage.BeeEmpire.NumberFormat)
local BeeService = require(script.Parent.BeeService)
local DataService = require(script.Parent.DataService)
local Notifier = require(script.Parent.Notifier)
local PassService = require(script.Parent.PassService)
local ProductionService = require(script.Parent.ProductionService)

local HalloweenService = {}

local EGG = GameConfig.HalloweenEgg
local REACH = 24 -- how far from the egg's middle a player may stand and still feed it (the egg is big)
local CHECK_SECONDS = 15 -- how often a running server looks whether the event is over
local SPARE_ROOM = 1.5 -- map decorations this close to the corner's edge are moved away too

local random = Random.new()
local corner: Model? = nil
local eggSpot: BasePart? = nil
local endsAt = 0
local moved: { [Instance]: Instance } = {} -- map decorations moved out of the way: [thing] = the folder it came from
local busyUntil: { [Player]: number } = {} -- so one press is one roll, and the egg can finish its show

function HalloweenService.IsOn(): boolean
	return corner ~= nil and os.time() < endsAt
end

-- Picks one of the egg's bees with this much luck. (Rarest first, so the dice are fair
-- even for the tiniest chance.) It changes nothing: HalloweenService.Pick(1) is also handy
-- for checking the chances from the command bar.
function HalloweenService.Pick(luck: number): string
	local chances = GameConfig.EggChances(EGG, luck)
	local roll = random:NextNumber() * 100
	for index = #EGG.Bees, 2, -1 do
		local beeName = EGG.Bees[index].Bee
		roll -= chances[beeName]
		if roll < 0 then
			return beeName
		end
	end
	return EGG.Bees[1].Bee
end

-- A player pressed E at the egg.
local function feed(player: Player)
	local data = DataService.Get(player)
	local spot = eggSpot
	if not data or not spot or not HalloweenService.IsOn() then
		return
	end
	local now = os.clock()
	if now < (busyUntil[player] or 0) then
		return -- their last egg is still hatching
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") or (root.Position - spot.Position).Magnitude > REACH then
		return -- not standing at the egg
	end

	local cost = EGG.JarCost
	if data.JarsCarried < cost then
		if data.Settings.AutoSell ~= false and PassService.Owns(player, "AutoSell") then
			Notifier.Send(player, "The egg wants " .. NumberFormat.Short(cost) .. " jars! Switch Auto Sell off in the Shop to save up jars.", "info")
		else
			Notifier.Send(player, "The egg wants " .. NumberFormat.Short(cost) .. " jars! You are carrying " .. NumberFormat.Short(data.JarsCarried) .. ".", "info")
		end
		return
	end
	if not BeeService.HasRoom(player) then
		Notifier.Send(player, "Your Inventory is full! Delete a spare bee first.", "bad")
		return
	end
	if not ProductionService.TakeCarried(player, cost) then
		return
	end
	busyUntil[player] = now + EGG.HatchSeconds + 0.4

	local luck = BeeService.RollLuck(player, data)
	local beeName = HalloweenService.Pick(luck)
	local given, placed = BeeService.GiveBee(player, beeName)
	if not given then
		-- (cannot happen after the room check above, but jars are never taken for nothing)
		data.JarsCarried += cost
		DataService.Replicate(player)
		return
	end
	Notifier.Effect(player, "EggHatched", { Bee = beeName, Placed = placed, Seconds = EGG.HatchSeconds })
end

-- Moves the map's own decorations out of the corner's spot (they come back when it leaves).
local function clearSpot(middle: Vector3, radius: number, holding: Instance)
	local map = workspace:FindFirstChild("Map")
	if not map then
		return
	end
	for _, folder in map:GetChildren() do
		if folder.Name == "Nature" or folder.Name == "Flowers" or folder.Name == "Trees" then
			for _, thing in folder:GetChildren() do
				local position = nil
				if thing:IsA("BasePart") then
					position = thing.Position
				elseif thing:IsA("Model") then
					position = thing:GetPivot().Position
				end
				if position and Vector3.new(position.X - middle.X, 0, position.Z - middle.Z).Magnitude < radius + SPARE_ROOM then
					moved[thing] = folder
					thing.Parent = holding
				end
			end
		end
	end
end

local function remove()
	local model = corner
	corner = nil
	eggSpot = nil
	workspace:SetAttribute("HalloweenEggEndsAt", 0)
	if model then
		model:Destroy()
	end
	for thing, folder in moved do
		if folder.Parent then
			thing.Parent = folder
		end
	end
	table.clear(moved)
end

function HalloweenService.Init()
	endsAt = GameConfig.EggEndsAt(EGG)
	if RunService:IsStudio() then
		local dev = ServerStorage:FindFirstChild("BeeEmpireDev")
		local test = dev and dev:GetAttribute("TestEggEndsIn")
		if typeof(test) == "number" then
			endsAt = os.time() + math.floor(test) -- (testing only: see the top of this file)
		end
	end
	local events = ServerStorage:FindFirstChild("BeeEmpireEvents")
	local template = events and events:FindFirstChild("HalloweenCorner")
	if os.time() >= endsAt or not template or not template:IsA("Model") then
		return -- the event is over (or its corner was never built): nothing to do, ever
	end

	local model = template:Clone()
	local middle = model:GetAttribute("Middle")
	local radius = model:GetAttribute("Radius")
	if typeof(middle) == "Vector3" and typeof(radius) == "number" then
		local holding = Instance.new("Folder")
		holding.Name = "MovedForHalloween"
		holding.Parent = events
		clearSpot(middle, radius, holding)
	end
	model.Parent = workspace
	corner = model
	local spot = model:FindFirstChild("EggSpot")
	eggSpot = if spot and spot:IsA("BasePart") then spot else nil
	local prompt = eggSpot and eggSpot:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.ActionText = "Give " .. NumberFormat.Short(EGG.JarCost) .. " Jars"
		prompt.ObjectText = EGG.Name
		prompt.Triggered:Connect(feed)
	end
	-- every screen reads this: when the egg leaves (0 = it has gone)
	workspace:SetAttribute("HalloweenEggEndsAt", endsAt)

	Players.PlayerRemoving:Connect(function(player)
		busyUntil[player] = nil
	end)
	task.spawn(function()
		while corner do
			task.wait(CHECK_SECONDS)
			if corner and os.time() >= endsAt then
				remove()
			end
		end
	end)
end

return HalloweenService
