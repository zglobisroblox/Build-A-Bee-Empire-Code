--[[
	HiveService - each player's beehive in the world, and the bees that work in it.

	- Builds the hive model for the player's hive level on their plot, and lights each
	  bee window on it in the colour of the bee that lives there.
	- Sends each working bee on trips: hive -> a flower in the Flower Garden -> back home.
	  Every finished trip brings honey home. The SERVER keeps the trip clock, so honey
	  arrives on time no matter what a player's device shows.
	- Runs the worker bees. Honey that comes home waits inside the hive until a worker bee
	  carries it to the plot's Honey Jars. Workers are free: one for every two bees working
	  in the hive (GameConfig.WorkersPerBee), always at least one.
	- Handles upgrading the hive (costs Honey Coins, checked on the server).

	The numbers for each level (cost, how many bees it holds...) are in GameConfig.HiveLevels.
	The look of each level is in HiveModelFactory.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedFolder = ReplicatedStorage.BeeEmpire
local GameConfig = require(sharedFolder.GameConfig)
local NumberFormat = require(sharedFolder.NumberFormat)
local BeeModelFactory = require(sharedFolder.BeeModelFactory)
local HiveModelFactory = require(sharedFolder.HiveModelFactory)
local DataService = require(script.Parent.DataService)
local Notifier = require(script.Parent.Notifier)
local PlotService = require(script.Parent.PlotService)

local HiveService = {}

local BEE_SCALE = 1 -- size of the working bees
local FORAGER_TAG = "BeeForager" -- the player's screen makes tagged bees fly their trips
local WORKER_SCALE = 0.85 -- worker bees are a little smaller
local WORKER_COLOR = Color3.fromRGB(235, 140, 50)
local WORKER_TAG = "BeeWorker" -- the player's screen makes tagged workers fly hive <-> jars
-- Keeping workers apart, so two of them never look like one double bee. A worker is about
-- 2.9 studs wide, 2.9 tall and 4.2 long.
local WORKER_GAP = 3.5 -- studs between two workers flying side by side
local WORKER_ROW = 3 -- this many fly side by side; any more fly in a second row above them
local WORKER_RISE = 3.3 -- how much higher each further row flies
local WORKER_LOOP_OUT = 4 -- how far outside the hive's wall the waiting workers circle
local WORKER_LOOP_HEIGHT = 0.45 -- how high up the hive's body they circle (0 = its foot, 1 = its top); the door is at 0.75

-- [plot] = { [slot number as text] = { Bee = the bee, Start = when its trips began, Delivered = trips already paid out } }
local trips = {}
-- [plot] = how many seconds one trip takes for that plot's bees (shorter with the Bee Speed upgrade)
local tripSeconds = {}
-- [plot] = honey (counted in jars) waiting inside the hive for a worker bee to carry it
local waiting = {}
-- [plot] = the plot's worker bees, each one:
--   { Model = the bee, State = "Idle" | "Carry" | "Return", LegEnd = when this flight ends, Amount = jars it is carrying }
local workers = {}

-- HELPERS -----------------------------------------------------------------------

local function getParts(plot: Model)
	local anchor = plot:FindFirstChild("HiveAnchor")
	local spot = plot:FindFirstChild("HiveSpot")
	local info = anchor and anchor:FindFirstChild("HiveInfo")
	return anchor, spot, info
end

local function countBees(data): number
	local count = 0
	for _ in data.Cells do
		count += 1
	end
	return count
end

-- Every flower in the garden a bee can visit (the spot just above each flower).
local flowerSpots: { Vector3 }? = nil
local function getFlowerSpots(): { Vector3 }
	if flowerSpots then
		return flowerSpots
	end
	local spots = {}
	local garden = workspace:FindFirstChild("FlowerGarden")
	local flowers = garden and garden:FindFirstChild("Flowers")
	if flowers then
		local list = flowers:GetChildren()
		table.sort(list, function(a, b)
			return a.Name < b.Name
		end)
		for _, flower in list do
			local spot = flower:GetAttribute("BeeSpot")
			if typeof(spot) == "Vector3" then
				table.insert(spots, spot)
			end
		end
	end
	if #spots == 0 then
		table.insert(spots, Vector3.new(0, 12, 0)) -- safety net if the garden is missing
	end
	flowerSpots = spots
	return spots
end

-- THE HIVE MODEL ------------------------------------------------------------------

-- Builds (or rebuilds) the hive for this level on the plot. ownerName = nil for an empty plot.
function HiveService.BuildHive(plot: Model, level: number, ownerName: string?)
	local anchor, spot, info = getParts(plot)
	if not anchor then
		return
	end

	local old = plot:FindFirstChild("Hive")
	if old then
		old:Destroy()
	end

	local hive = HiveModelFactory.Create(level)
	hive:PivotTo(anchor.CFrame)
	local bees = Instance.new("Folder")
	bees.Name = "Bees"
	bees.Parent = hive
	hive.Parent = plot

	-- keep the "Open Hive" button just in front of the hive, however big it is
	if spot then
		spot.CFrame = anchor.CFrame * CFrame.new(0, 2.2, -(hive:GetAttribute("Radius") + 1.5))
	end

	if info then
		info.Enabled = ownerName ~= nil
		info.StudsOffsetWorldSpace = Vector3.new(0, hive:GetAttribute("Height") + 3, 0)
		info.Title.Text = GameConfig.GetHive(level).Name .. "  (Lv " .. level .. ")"
	end
end

-- THE WORKER BEES ---------------------------------------------------------------------
-- A worker flies loops round the hive while it waits ("Idle"), flies honey to the jars
-- ("Carry") and flies back ("Return"). The server decides when each flight starts and ends; the player's
-- screen only draws the bee moving between the two points for that long.

-- How many workers a hive with this many working bees gets.
local function workerCountFor(working: number): number
	if working <= 0 then
		return 0
	end
	return math.max(1, math.ceil(working * GameConfig.WorkersPerBee))
end

-- Where workers pick honey up (just outside the hive door), where they drop it (above the
-- jars), which way "along the front of the hive" is, and the middle and width of the hive
-- (waiting workers fly loops around it).
local function workerPoints(plot: Model): (Vector3?, Vector3?, Vector3?, Vector3?, number?)
	local anchor = plot:FindFirstChild("HiveAnchor")
	local hive = plot:FindFirstChild("Hive")
	local station = plot:FindFirstChild("CollectStation")
	local drop = station and (station:FindFirstChild("DropSpot") or station:FindFirstChild("Table"))
	if not anchor or not anchor:IsA("BasePart") or not hive or not drop or not drop:IsA("BasePart") then
		return nil, nil, nil, nil, nil
	end
	local bodyRadius = hive:GetAttribute("BodyRadius") or 1
	local bodyBase = hive:GetAttribute("BodyBase") or 1
	local bodyHeight = hive:GetAttribute("BodyHeight") or 2
	local door = anchor.CFrame:PointToWorldSpace(Vector3.new(0, bodyBase + bodyHeight * 0.75 + 1, -(bodyRadius + 1.6)))
	local jarPoint = if drop.Name == "DropSpot" then drop.Position else drop.Position + Vector3.new(0, 4, 0)
	local middle = anchor.Position + Vector3.new(0, bodyBase + bodyHeight * WORKER_LOOP_HEIGHT, 0)
	return door, jarPoint, anchor.CFrame.RightVector, middle, bodyRadius
end

-- Starts a worker's next flight (or sends it back to waiting) and tells the players' screens.
local function setWorkerState(worker, state: string, seconds: number, amount: number, now: number)
	worker.State = state
	worker.Amount = amount
	worker.LegEnd = now + seconds
	local model = worker.Model
	model:SetAttribute("Amount", amount)
	model:SetAttribute("LegStart", now)
	model:SetAttribute("LegSeconds", seconds)
	model:SetAttribute("State", state) -- set last: the screen reads the other three when this changes
end

local function clearWorkers(plot: Model)
	workers[plot] = nil
	local folder = plot:FindFirstChild("Workers")
	if folder then
		folder:Destroy()
	end
end

-- Makes sure the plot has the right number of worker bees for the bees working in its hive,
-- and tells each one where the hive door and the jars are (the door moves when the hive grows).
local function refreshWorkers(plot: Model, working: number)
	local list = workers[plot]
	if not list then
		list = {}
		workers[plot] = list
	end

	local wanted = workerCountFor(working)
	if wanted == 0 then
		-- an empty hive keeps one worker until the honey already made has been carried over
		local honeyLeft = (waiting[plot] or 0) >= 1
		for _, worker in list do
			if worker.State == "Carry" then
				honeyLeft = true
			end
		end
		if honeyLeft then
			wanted = 1
		end
	end
	local hivePoint, jarPoint, doorSide, hiveMiddle, hiveRadius = workerPoints(plot)
	if not hivePoint or not jarPoint or not doorSide or not hiveMiddle or not hiveRadius then
		wanted = 0
	end

	-- too many: send idle ones away first. A worker that was carrying honey puts it back in the hive.
	while #list > wanted do
		local index = #list
		for candidate = #list, 1, -1 do
			if list[candidate].State ~= "Carry" then
				index = candidate
				break
			end
		end
		local worker = table.remove(list, index)
		if worker.State == "Carry" then
			waiting[plot] = (waiting[plot] or 0) + worker.Amount
		end
		worker.Model:Destroy()
	end

	if wanted == 0 or not hivePoint or not jarPoint or not doorSide or not hiveMiddle or not hiveRadius then
		return
	end

	local folder = plot:FindFirstChild("Workers")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Workers"
		folder.Parent = plot
	end

	-- too few: new workers start out waiting at the hive
	local now = workspace:GetServerTimeNow()
	while #list < wanted do
		local model = BeeModelFactory.Create(WORKER_COLOR, { Scale = WORKER_SCALE, Cargo = true })
		model.Name = "Worker"
		local worker = { Model = model, State = "Idle", LegEnd = now, Amount = 0 }
		setWorkerState(worker, "Idle", 0, 0, now)
		table.insert(list, worker)
	end

	-- Spread them out so they never fly inside each other. Every worker has its own lane:
	-- its own spot in a row across the hive door, and its own spot in a row above the jars.
	-- The gaps are wider than a bee, and a fourth worker starts a second row above the first.
	local sideways = (jarPoint - hivePoint):Cross(Vector3.yAxis)
	sideways = if sideways.Magnitude > 0.01 then sideways.Unit else Vector3.xAxis
	-- (keep the two rows in the same left-to-right order, so two lanes never cross on the way)
	if doorSide:Dot(sideways) < 0 then
		sideways = -sideways
	end
	for index, worker in list do
		local row = math.floor((index - 1) / WORKER_ROW)
		local inThisRow = math.min(WORKER_ROW, #list - row * WORKER_ROW)
		local offset = ((index - 1) % WORKER_ROW - (inThisRow - 1) / 2) * WORKER_GAP
		local higher = Vector3.new(0, row * WORKER_RISE, 0)
		local model = worker.Model
		local waitingSpot = hivePoint + doorSide * offset + higher
		model:SetAttribute("HivePoint", waitingSpot)
		model:SetAttribute("JarPoint", jarPoint + sideways * offset + higher)
		-- While they wait, the workers circle the hive one behind the other, all the same way
		-- round (the player's screen keeps them apart: see WorldFX). LoopSlot is the number
		-- of this worker's lane.
		model:SetAttribute("HiveMiddle", hiveMiddle)
		model:SetAttribute("LoopRadius", hiveRadius + WORKER_LOOP_OUT)
		model:SetAttribute("LoopSlot", index)
		if model.Parent ~= folder then
			model:PivotTo(CFrame.new(waitingSpot))
			CollectionService:AddTag(model, WORKER_TAG)
			model.Parent = folder
		end
	end
end

-- THE WORKING BEES --------------------------------------------------------------------

-- Call this whenever the bees in the hive change. Bees that were already working keep
-- their trip clock, so nothing is lost; new bees start a fresh trip.
function HiveService.RefreshBees(plot: Model, data)
	local anchor, _, info = getParts(plot)
	local hive = plot:FindFirstChild("Hive")
	local folder = hive and hive:FindFirstChild("Bees")
	if not anchor or not hive or not folder then
		return
	end
	folder:ClearAllChildren()

	-- honey from trips that finished a moment ago goes into the hive first, so changing the
	-- bees (or their speed) never throws away honey that was already earned
	waiting[plot] = (waiting[plot] or 0) + HiveService.CollectDeliveries(plot)

	local plotTrips = trips[plot]
	if not plotTrips then
		plotTrips = {}
		trips[plot] = plotTrips
	end
	-- Bee Speed upgrade: faster bees finish a trip sooner. If the speed just changed,
	-- every bee starts a fresh trip at the new speed.
	local seconds = GameConfig.TripSeconds / DataService.UpgradeValue(data, "BeeSpeed")
	if tripSeconds[plot] ~= seconds then
		tripSeconds[plot] = seconds
		table.clear(plotTrips)
	end
	-- forget trips for spots that are now empty or hold a different bee
	for key, trip in plotTrips do
		if data.Cells[key] ~= trip.Bee then
			plotTrips[key] = nil
		end
	end

	local capacity = GameConfig.GetHive(data.HiveLevel).Capacity
	local bodyRadius = hive:GetAttribute("BodyRadius")
	local bodyBase = hive:GetAttribute("BodyBase")
	local bodyHeight = hive:GetAttribute("BodyHeight")
	local spots = getFlowerSpots()
	local plotIndex = plot:GetAttribute("PlotIndex") or 1
	local now = workspace:GetServerTimeNow()
	local working = 0

	for index = 1, capacity do
		local key = tostring(index)
		local bee = data.Cells[key]
		if bee then
			working += 1
			local trip = plotTrips[key]
			if not trip then
				-- a short, different wait for each spot so the bees do not all leave together
				trip = { Bee = bee, Start = now + ((index - 1) % 6) * 0.6, Delivered = 0 }
				plotTrips[key] = trip
			end

			local rarity = GameConfig.Bees[bee.Rarity]
			local model = BeeModelFactory.Create(rarity.Color, { Scale = BEE_SCALE, Sparkles = rarity.Sparkles, Trail = rarity.Trail, Pollen = true })

			-- where this bee leaves the hive (in front of its own window; just outside the door
			-- if the hive has no windows), and which flower it visits
			local doorOffset = Vector3.new(((index % 3) - 1) * 0.9, bodyBase + bodyHeight * 0.3 + (index % 2) * 0.7, -(bodyRadius + 1.3))
			local hivePoint = HiveModelFactory.WindowPoint(hive, index) or anchor.CFrame:PointToWorldSpace(doorOffset)
			local flower = spots[((plotIndex * 7 + index * 5) % #spots) + 1]
			local flowerPoint = flower + Vector3.new(((index * 37) % 10 - 5) / 10, ((index * 13) % 6) / 10, ((index * 53) % 10 - 5) / 10)

			model:SetAttribute("HivePoint", hivePoint)
			model:SetAttribute("FlowerPoint", flowerPoint)
			model:SetAttribute("TripStart", trip.Start)
			model:SetAttribute("TripSeconds", seconds)
			model:SetAttribute("JarsPerTrip", rarity.NectarPerSecond * GameConfig.TripSeconds)
			model:PivotTo(CFrame.new(hivePoint))
			CollectionService:AddTag(model, FORAGER_TAG)
			model.Parent = folder
		end
	end

	-- every bee window glows in the colour of its bee's rarity; empty spots are dark
	for index = 1, capacity do
		local bee = data.Cells[tostring(index)]
		HiveModelFactory.SetWindow(hive, index, if bee then GameConfig.Bees[bee.Rarity].RarityColor else nil)
	end

	if info then
		info.Sub.Text = working .. " / " .. capacity .. " bees"
	end

	refreshWorkers(plot, working)
end

-- How many jars of honey the plot's bees have brought home since the last time this was called.
function HiveService.CollectDeliveries(plot: Model): number
	local plotTrips = trips[plot]
	if not plotTrips then
		return 0
	end
	local now = workspace:GetServerTimeNow()
	local seconds = tripSeconds[plot] or GameConfig.TripSeconds
	local jars = 0
	for _, trip in plotTrips do
		local finished = math.floor((now - trip.Start) / seconds)
		if finished > trip.Delivered then
			local rate = GameConfig.Bees[trip.Bee.Rarity].NectarPerSecond
			jars += (finished - trip.Delivered) * rate * GameConfig.TripSeconds
			trip.Delivered = finished
		end
	end
	return jars
end

-- Called a few times a second for every plot with an owner. Moves the honey along:
--   1. workers that reached the jars drop their honey off (that is what this returns)
--   2. bees that came home from the flowers add their honey to the hive
--   3. waiting workers pick up the honey in the hive and set off for the jars
-- There is no limit on how much honey the Honey Jars can hold, so no honey is ever wasted.
function HiveService.StepHoney(plot: Model): number
	local list = workers[plot]
	if not list then
		return 0
	end
	local now = workspace:GetServerTimeNow()

	local arrived = 0
	for _, worker in list do
		if worker.State == "Carry" then
			if now >= worker.LegEnd then
				arrived += worker.Amount
				setWorkerState(worker, "Return", GameConfig.WorkerReturnSeconds, 0, now)
			end
		elseif worker.State == "Return" and now >= worker.LegEnd then
			setWorkerState(worker, "Idle", 0, 0, now)
		end
	end

	local stock = (waiting[plot] or 0) + HiveService.CollectDeliveries(plot)

	-- the waiting workers share out the whole jars
	local idle = {}
	for _, worker in list do
		if worker.State == "Idle" then
			table.insert(idle, worker)
		end
	end
	local whole = math.floor(stock)
	for index, worker in idle do
		if whole <= 0 then
			break
		end
		local load = math.ceil(whole / (#idle - index + 1))
		whole -= load
		stock -= load
		setWorkerState(worker, "Carry", GameConfig.WorkerCarrySeconds, load, now)
	end

	waiting[plot] = stock
	return arrived
end

-- UPGRADING ---------------------------------------------------------------------------

-- Returns true if the hive was upgraded.
function HiveService.Upgrade(player: Player): boolean
	local data = DataService.Get(player)
	local plot = PlotService.GetPlot(player)
	if not data or not plot then
		return false
	end

	local nextLevel = data.HiveLevel + 1
	local nextHive = GameConfig.HiveLevels[nextLevel]
	if not nextHive then
		Notifier.Send(player, "Your hive is already the biggest!", "info")
		return false
	end
	if data.Coins < nextHive.Cost then
		Notifier.Send(player, "You need " .. NumberFormat.Short(nextHive.Cost - data.Coins) .. " more Honey Coins!", "bad")
		return false
	end

	data.Coins -= nextHive.Cost
	data.HiveLevel = nextLevel

	HiveService.BuildHive(plot, nextLevel, player.DisplayName)
	HiveService.RefreshBees(plot, data)

	-- a burst of sparkles everyone can see
	local hive = plot:FindFirstChild("Hive")
	local stand = hive and hive.PrimaryPart
	if stand then
		local burst = Instance.new("ParticleEmitter")
		burst.Name = "UpgradeBurst"
		burst.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		burst.Color = ColorSequence.new(Color3.fromRGB(255, 215, 60), Color3.fromRGB(255, 255, 255))
		burst.LightEmission = 1
		burst.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 0) })
		burst.Lifetime = NumberRange.new(1, 1.8)
		burst.Speed = NumberRange.new(10, 22)
		burst.SpreadAngle = Vector2.new(180, 180)
		burst.Rate = 0
		burst.Parent = stand
		burst:Emit(60)
		task.delay(3, function()
			burst:Destroy()
		end)
	end

	Notifier.Effect(player, "HiveUpgraded", nextLevel)
	DataService.Replicate(player)
	return true
end

-- JOINING AND LEAVING ------------------------------------------------------------------

function HiveService.SetupPlayer(player: Player)
	local data = DataService.Get(player)
	local plot = PlotService.GetPlot(player)
	if not data or not plot then
		return
	end
	trips[plot] = {}
	tripSeconds[plot] = nil
	waiting[plot] = 0
	clearWorkers(plot)
	HiveService.BuildHive(plot, data.HiveLevel, player.DisplayName)
	HiveService.RefreshBees(plot, data)
end

-- An empty plot shows a quiet little starter hive.
function HiveService.ResetPlot(plot: Model)
	trips[plot] = nil
	tripSeconds[plot] = nil
	waiting[plot] = nil
	clearWorkers(plot)
	HiveService.BuildHive(plot, 1, nil)
end

HiveService.CountBees = countBees

return HiveService
