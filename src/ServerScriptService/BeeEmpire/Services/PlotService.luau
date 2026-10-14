--[[
	PlotService - gives every player their own hive plot and frees it when they leave.
]]

local PlotService = {}

local plotsFolder = workspace:WaitForChild("Plots")

local plotByPlayer: { [Player]: Model } = {}
local sortedPlots: { Model } = {}

local function setSign(plot: Model, text: string)
	local ownerSign = plot:FindFirstChild("OwnerSign")
	local sign = ownerSign and ownerSign:FindFirstChild("Sign")
	local nameTag = sign and sign:FindFirstChild("NameTag")
	local label = nameTag and nameTag:FindFirstChild("Label")
	if label then
		label.Text = text
	end
end

function PlotService.Init()
	for _, child in plotsFolder:GetChildren() do
		if child:IsA("Model") then
			table.insert(sortedPlots, child)
		end
	end
	table.sort(sortedPlots, function(a, b)
		return (a:GetAttribute("PlotIndex") or 0) < (b:GetAttribute("PlotIndex") or 0)
	end)
	for _, plot in sortedPlots do
		plot:SetAttribute("OwnerUserId", 0)
		setSign(plot, "Empty Hive")
	end
end

function PlotService.GetAllPlots(): { Model }
	return sortedPlots
end

function PlotService.GetPlot(player: Player): Model?
	return plotByPlayer[player]
end

-- Moves the player's character onto their own spawn pad.
function PlotService.SendHome(player: Player)
	local plot = plotByPlayer[player]
	local character = player.Character
	if plot and character and character.Parent then
		local spawnPad = plot:FindFirstChild("SpawnPad")
		if spawnPad then
			character:PivotTo(spawnPad.CFrame * CFrame.new(0, 4, 0))
		end
	end
end

-- Gives the player the first free plot. Returns nil if every plot is taken.
function PlotService.Assign(player: Player): Model?
	if plotByPlayer[player] then
		return plotByPlayer[player]
	end

	for _, plot in sortedPlots do
		if plot:GetAttribute("OwnerUserId") == 0 then
			plot:SetAttribute("OwnerUserId", player.UserId)
			plotByPlayer[player] = plot
			setSign(plot, player.DisplayName .. "'s Hive")

			local spawnPad = plot:FindFirstChild("SpawnPad")
			if spawnPad and spawnPad:IsA("SpawnLocation") then
				player.RespawnLocation = spawnPad
			end
			-- If their character appeared before the plot was ready, move it home.
			if player.Character then
				task.defer(PlotService.SendHome, player)
			end
			-- Safety net: if a new character ever appears away from its own hive, move it home.
			player.CharacterAdded:Connect(function(character)
				local root = character:WaitForChild("HumanoidRootPart", 5)
				task.wait()
				if root and spawnPad and plotByPlayer[player] == plot then
					if (root.Position - spawnPad.Position).Magnitude > 25 then
						PlotService.SendHome(player)
					end
				end
			end)
			return plot
		end
	end
	return nil
end

function PlotService.Release(player: Player)
	local plot = plotByPlayer[player]
	if plot then
		plotByPlayer[player] = nil
		plot:SetAttribute("OwnerUserId", 0)
		setSign(plot, "Empty Hive")
	end
end

-- True when the player's character is alive and standing close enough to the part.
function PlotService.IsNear(player: Player, part: BasePart, maxDistance: number): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return false
	end
	return (root.Position - part.Position).Magnitude <= maxDistance
end

return PlotService
