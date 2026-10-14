--[[
	ShopService - what the passes DO, and the Shop window's Buy button.

	PassService knows WHO owns which pass. This script acts on it:
	- Starter Pack: hands out what is listed in GameConfig.StarterPack. Once per player: the
	  save remembers that it has been opened.
	- +2 Rolls: the two extra honeycomb stands appear next to the Queen.
	- VIP: the crown and the gold name over the player's head.
	(Lucky Queen, Auto Sell, Infinite Inventory and VIP's extra honey are simply numbers that
	BeeService and ProductionService read from PassService.)

	The Buy button only sends a request. The server checks it, then opens Roblox's own
	purchase window. Roblox handles the Robux; this game never sees or touches them.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.BeeEmpire.GameConfig)
local BeeService = require(script.Parent.BeeService)
local BoostService = require(script.Parent.BoostService)
local DataService = require(script.Parent.DataService)
local Notifier = require(script.Parent.Notifier)
local PassService = require(script.Parent.PassService)
local UpgradeService = require(script.Parent.UpgradeService)

local ShopService = {}

local VIP_CROWN_SCALE = 1.5 -- the crown is the Emperor Bee's, made this many times bigger
local GOLD = Color3.fromRGB(255, 205, 50)
local INK = Color3.fromRGB(20, 16, 26)

local ready: { [Player]: boolean } = {} -- true once a player's save is loaded and their passes are applied

-- THE STARTER PACK ---------------------------------------------------------------------------

local function openStarterPack(player: Player, data)
	if data.StarterPackOpened then
		return
	end
	data.StarterPackOpened = true -- (written down first, so it can never be handed out twice)
	local beeGiven, placed, boosts = nil, false, 0
	for _, item in GameConfig.StarterPack do
		if item.Bee and GameConfig.Bees[item.Bee] then
			-- (true: it always fits, even when the Inventory is full)
			local given, inHive = BeeService.GiveBee(player, item.Bee, true)
			if given then
				beeGiven, placed = item.Bee, inHive
			end
		elseif item.Boost and GameConfig.Boosts[item.Boost] then
			for _ = 1, math.max(1, item.Count or 1) do
				if BoostService.Give(player, item.Boost, item.Minutes or 10) then
					boosts += 1
				end
			end
		end
	end
	Notifier.Effect(player, "StarterPack", { Bee = beeGiven, Placed = placed, Boosts = boosts })
end

-- VIP: THE CROWN AND THE GOLD NAME ---------------------------------------------------------------

local function nameLine(parent: Instance, name: string, text: string, top: number, height: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = GOLD
	label.Position = UDim2.fromScale(0, top)
	label.Size = UDim2.fromScale(1, height)
	local edge = Instance.new("UIStroke")
	edge.Color = INK
	edge.Thickness = 2.5
	edge.Parent = label
	label.Parent = parent
	return label
end

-- Puts the crown and the gold name on a VIP's character. It waits until the avatar has
-- finished loading, because Roblox rebuilds the body while it loads and anything attached
-- too early falls off.
local function dress(player: Player, character: Model)
	local deadline = os.clock() + 10
	while os.clock() < deadline and not (player:HasAppearanceLoaded() and character:IsDescendantOf(workspace)) do
		task.wait(0.25)
		if player.Character ~= character then
			return -- they respawned again; the newer character gets its own call
		end
	end
	task.wait()
	if player.Character ~= character or not PassService.Owns(player, "VIP") then
		return
	end
	local head = character:FindFirstChild("Head")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not head or not head:IsA("BasePart") or not humanoid or character:FindFirstChild("VipCrown") then
		return
	end

	local top = head.Size.Y / 2
	local meshes = ReplicatedStorage.BeeEmpire:FindFirstChild("BeeMeshes")
	local template = meshes and meshes:FindFirstChild("Crown")
	if template and template:IsA("BasePart") then
		local crown = template:Clone()
		crown.Name = "VipCrown"
		crown.Size = template.Size * VIP_CROWN_SCALE
		crown.Anchored = false
		crown.CanCollide = false
		crown.CanQuery = false
		crown.CanTouch = false
		crown.Massless = true
		crown.CFrame = head.CFrame * CFrame.new(0, top + crown.Size.Y / 2 - 0.1, 0)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = head
		weld.Part1 = crown
		weld.Parent = crown
		crown.Parent = character
		top += crown.Size.Y
	end

	-- the gold name takes the place of Roblox's own white one
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	local tag = Instance.new("BillboardGui")
	tag.Name = "VipTag"
	tag.Adornee = head
	tag.Size = UDim2.fromScale(7, 1.9)
	tag.StudsOffsetWorldSpace = Vector3.new(0, top + 1.25, 0)
	tag.MaxDistance = 100
	tag.LightInfluence = 0
	tag.ResetOnSpawn = false
	nameLine(tag, "Vip", "VIP", 0, 0.42)
	nameLine(tag, "PlayerName", player.DisplayName, 0.42, 0.58)
	tag.Parent = head
end

-- ACTING ON A PASS ---------------------------------------------------------------------------------

-- bought = true when the pass was bought just now (false when the player already had it).
local function apply(player: Player, key: string, bought: boolean)
	local data = DataService.Get(player)
	if not data then
		return
	end
	if key == "StarterPack" then
		openStarterPack(player, data)
	elseif key == "Rolls" then
		BeeService.RefreshStands(player) -- the two new stands appear, and the others move over
		UpgradeService.RefreshBoard(player)
	elseif key == "VIP" then
		if player.Character then
			task.spawn(dress, player, player.Character)
		end
	end
	DataService.Replicate(player)
	if bought and key ~= "StarterPack" then
		Notifier.Effect(player, "PassBought", key)
	end
end

-- The Buy button of the Shop window. key is the pass's name in GameConfig.Passes.
function ShopService.Request(player: Player, key: any)
	local allowed, why = PassService.CanBuy(player, key)
	if not allowed then
		if why then
			Notifier.Send(player, why, "info")
		end
		return
	end
	PassService.Prompt(player, key)
end

-- Called once when a player has joined and their save is loaded.
function ShopService.SetupPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		dress(player, character)
	end)
	for _, key in GameConfig.PassOrder do
		if PassService.Owns(player, key) then
			apply(player, key, false)
		end
	end
	ready[player] = true
end

function ShopService.CleanupPlayer(player: Player)
	ready[player] = nil
end

function ShopService.Init()
	-- a pass bought while playing (or one Roblox was slow to tell us about)
	PassService.OnOwned(function(player, key, bought)
		if ready[player] then
			apply(player, key, bought)
		end
	end)
end

return ShopService
