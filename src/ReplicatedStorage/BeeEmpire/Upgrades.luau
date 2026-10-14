--[[
	Upgrades - small helpers for reading upgrade levels.

	The prices and effects live in GameConfig (GameConfig.Upgrades and GameConfig.HiveLevels).
	This file only answers questions like "what level is this?" and "what does the next
	level cost?", so the server and the screen UI always agree.

	An upgrade id is "Hive", "Luck", "BeeSpeed", "Rolls", "WalkSpeed" or "RollSpeed" (see GameConfig.UpgradeOrder).
	"levels" is a table like { Hive = 2, Luck = 3, BeeSpeed = 1, Rolls = 1 }.

	"Rolls" (More Rolls) is a little special: its levels in GameConfig are the stands that can
	be bought with coins. A player with the "+2 Rolls" pass has GameConfig.GamePassRollStands
	more. The describing functions below take those as "bonus", so their words say what the
	player really gets ("5 bees per roll"). The levels and prices are not changed by the pass.

	"Luck" (Queen's Luck) is ENDLESS: it has no list of levels. GameConfig gives a rule
	instead (Step, FirstCost, Growth) and this file works out any level's luck and price from it.

	"WalkSpeed" is STEPPED: the same kind of rule, but with a top (Steps = { Step, Top, FirstCost,
	Growth }): 1% faster per level, up to x1.5. Level 1 is "nothing bought yet", so x1.5 is level 51.
]]

local GameConfig = require(script.Parent.GameConfig)
local NumberFormat = require(script.Parent.NumberFormat)

local Upgrades = {}

-- An endless upgrade can be bought for ever. This number is NOT a top level for players: it
-- only keeps a broken save from holding a silly level (nobody could ever pay for this many).
local ENDLESS_SAFETY_LEVELS = 2000

-- The list of levels for an upgrade, or nil if it has none (no such upgrade, or an endless one).
function Upgrades.LevelList(id: string)
	if id == "Hive" then
		return GameConfig.HiveLevels
	end
	local upgrade = GameConfig.Upgrades[id]
	return if upgrade then upgrade.Levels else nil
end

-- The rule of an endless upgrade ({ Step, FirstCost, Growth }), or nil for an ordinary one.
local function endlessRule(id: string)
	local upgrade = GameConfig.Upgrades[id]
	return if upgrade then upgrade.Endless else nil
end

-- The rule of a stepped upgrade ({ Step, Top, FirstCost, Growth }), or nil.
local function steppedRule(id: string)
	local upgrade = GameConfig.Upgrades[id]
	return if upgrade then upgrade.Steps else nil
end

-- The step rule of an endless OR a stepped upgrade: they share how values and prices grow.
local function stepRule(id: string)
	return endlessRule(id) or steppedRule(id)
end

-- True for an upgrade with no top level (Queen's Luck).
function Upgrades.IsEndless(id: string): boolean
	return endlessRule(id) ~= nil
end

-- True for an upgrade bought in many small, cheap steps (Queen's Luck, Walk Speed).
function Upgrades.IsStepped(id: string): boolean
	return stepRule(id) ~= nil
end

-- True for an upgrade that is only in the Upgrade Shop window, not on the board in the yard.
function Upgrades.WindowOnly(id: string): boolean
	local upgrade = GameConfig.Upgrades[id]
	return upgrade ~= nil and upgrade.WindowOnly == true
end

-- True for an upgrade that only exists once Auto Roll has been bought (Roll Speed).
function Upgrades.NeedsAutoRoll(id: string): boolean
	local upgrade = GameConfig.Upgrades[id]
	return upgrade ~= nil and upgrade.NeedsAutoRoll == true
end

-- Rounds a price to two digits so it looks tidy: 114 -> 110, 1067 -> 1100.
local function tidyPrice(price: number): number
	if price < 100 then
		return math.floor(price + 0.5)
	end
	local unit = 10 ^ (math.floor(math.log10(price)) - 1)
	return math.floor(price / unit + 0.5) * unit
end

function Upgrades.Exists(id: any): boolean
	return typeof(id) == "string" and (Upgrades.LevelList(id) ~= nil or stepRule(id) ~= nil)
end

function Upgrades.DisplayName(id: string): string
	if id == "Hive" then
		return "Beehive"
	end
	local upgrade = GameConfig.Upgrades[id]
	return if upgrade then upgrade.Name else id
end

function Upgrades.MaxLevel(id: string): number
	if endlessRule(id) then
		return ENDLESS_SAFETY_LEVELS
	end
	local stepped = steppedRule(id)
	if stepped then
		return 1 + math.floor((stepped.Top - 1) / stepped.Step + 0.5) -- x1 to x1.5 in 0.01 steps: 51 levels
	end
	local list = Upgrades.LevelList(id)
	return if list then #list else 1
end

-- "Level 2 / 3", or just "Level 7" for an upgrade that never ends.
function Upgrades.LevelText(id: string, level: number): string
	if endlessRule(id) then
		return "Level " .. level
	end
	if steppedRule(id) then
		return string.format("%d / %d bought", level - 1, Upgrades.MaxLevel(id) - 1) -- "7 / 50 bought"
	end
	return "Level " .. level .. " / " .. Upgrades.MaxLevel(id)
end

-- What the price button says once nothing more can be bought.
function Upgrades.TopLabel(_id: string): string
	return "MAX"
end

-- What to SHOW as an upgrade's value: for More Rolls, the stands a pass adds are counted too.
local function shownValue(id: string, level: number, bonus: number?): number
	return Upgrades.ValueAt(id, level) + (if id == "Rolls" then bonus or 0 else 0)
end

-- A level number that is always valid (1 .. max).
function Upgrades.CleanLevel(id: string, level: any): number
	if typeof(level) ~= "number" or level ~= level then
		return 1
	end
	return math.clamp(math.floor(level), 1, Upgrades.MaxLevel(id))
end

-- What the upgrade does at a level: luck multiplier, speed multiplier,
-- or (for the hive) how many bees it holds.
function Upgrades.ValueAt(id: string, level: number): number
	local rule = stepRule(id)
	if rule then
		-- level 1 is x1, and every level after it adds one Step (kept to tidy decimals)
		local value = 1 + (Upgrades.CleanLevel(id, level) - 1) * rule.Step
		return math.floor(value * 1000 + 0.5) / 1000
	end
	local list = Upgrades.LevelList(id)
	local entry = list and list[Upgrades.CleanLevel(id, level)]
	if not entry then
		return 1
	end
	return if id == "Hive" then entry.Capacity else entry.Value
end

-- The price of the NEXT level, or nil when the upgrade is already at its maximum.
function Upgrades.NextCost(id: string, level: number): number?
	local rule = stepRule(id)
	if rule then
		local clean = Upgrades.CleanLevel(id, level)
		if clean >= Upgrades.MaxLevel(id) then
			return nil
		end
		-- the first upgrade costs FirstCost, and each one after it Growth times the one before
		return tidyPrice(rule.FirstCost * rule.Growth ^ (clean - 1))
	end
	local list = Upgrades.LevelList(id)
	local nextEntry = list and list[Upgrades.CleanLevel(id, level) + 1]
	return if nextEntry then nextEntry.Cost else nil
end

-- A short description of what a level gives, e.g. "x2 luck".
-- (bonus: extra stands from the "+2 Rolls" pass. It only matters for More Rolls.)
function Upgrades.Describe(id: string, level: number, bonus: number?): string
	local value = shownValue(id, level, bonus)
	if id == "Hive" then
		return "Holds " .. value .. " bees"
	elseif id == "Luck" then
		return string.format("x%g luck", value)
	elseif id == "BeeSpeed" then
		return string.format("x%g speed", value)
	elseif id == "Rolls" then
		return if value == 1 then "1 bee per roll" else string.format("%d bees per roll", value)
	elseif id == "RollSpeed" then
		return string.format("Auto Roll every %g sec", value)
	elseif id == "WalkSpeed" then
		return string.format("x%.2f walk speed", value)
	end
	return tostring(value)
end

-- What to say about an upgrade that is at its top level.
function Upgrades.DescribeTop(id: string, level: number, bonus: number?): string
	return Upgrades.Describe(id, level, bonus) .. "  (the best!)"
end

-- What buying the next level changes, e.g. "Holds 2 > 4 bees". At the top level it just
-- describes what you have.
function Upgrades.DescribeChange(id: string, level: number, bonus: number?): string
	if not Upgrades.NextCost(id, level) then
		return Upgrades.Describe(id, level, bonus)
	end
	local now = shownValue(id, level, bonus)
	local after = shownValue(id, level + 1, bonus)
	if id == "Hive" then
		return string.format("Holds %d > %d bees", now, after)
	elseif id == "Luck" then
		return string.format("x%g > x%g luck", now, after)
	elseif id == "BeeSpeed" then
		return string.format("x%g > x%g speed", now, after)
	elseif id == "Rolls" then
		return string.format("%d > %d bees per roll", now, after)
	elseif id == "RollSpeed" then
		return string.format("Auto Roll every %g > %g sec", now, after)
	elseif id == "WalkSpeed" then
		return string.format("x%.2f > x%.2f walk speed", now, after)
	end
	return Upgrades.Describe(id, level + 1, bonus)
end

-- The same thing, as short as possible (for the board above the Upgrade Shop): "2 > 4 bees".
function Upgrades.DescribeChangeShort(id: string, level: number, bonus: number?): string
	local now = shownValue(id, level, bonus)
	local multiplier = id == "Luck" or id == "BeeSpeed" or id == "WalkSpeed"
	if not Upgrades.NextCost(id, level) then
		if id == "RollSpeed" then
			return string.format("%gs", now)
		end
		return if multiplier then string.format("x%g", now) else NumberFormat.Short(now)
	end
	local after = shownValue(id, level + 1, bonus)
	if id == "Hive" then
		return string.format("%d > %d bees", now, after)
	elseif id == "RollSpeed" then
		return string.format("%gs > %gs", now, after)
	elseif multiplier then
		return string.format("x%g > x%g", now, after)
	end
	return NumberFormat.Short(now) .. " > " .. NumberFormat.Short(after)
end

return Upgrades
