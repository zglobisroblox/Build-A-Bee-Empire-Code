--[[
	HiveModelFactory - builds a beehive, one look per level.

	The five hives were modelled in Blender (chunky toy style) and live in
	ReplicatedStorage.BeeEmpire.HiveMeshes: Hive1 .. Hive5, HiveWindowFrame and
	HiveWindowPane. Level 1 is a little taller than a player and stands on a tree stump;
	each level is taller and wider, and the later ones get extras: honey drips, coloured
	bands, little side hives, flowers and a crown.

	BEE WINDOWS: every bee spot in the hive has a six-sided window on the front. A window is
	dark while its spot is empty and glows in a bee's colour while that bee lives there
	(HiveModelFactory.SetWindow). Bees fly out of, and home to, their own window.

	The hive is built standing on the ground at the origin with its door facing -Z.
	Move it with model:PivotTo(cframe): the pivot is the middle of its base.

	The attributes at the bottom of Create() (Height, Radius, BodyRadius, BodyBase,
	BodyHeight) are used by the game to place the bees and the sign.

	If the Blender pieces are ever missing, a simpler hive of plain blocks is built instead
	(the second half of this file), so the game always works.
]]

local GameConfig = require(script.Parent.GameConfig)
local Studs = require(script.Parent.Studs)

local HiveModelFactory = {}

local HONEY_LIGHT = Color3.fromRGB(255, 208, 76)
local HONEY_DARK = Color3.fromRGB(242, 162, 44)
local DOOR = Color3.fromRGB(70, 40, 15)
local WOOD = Color3.fromRGB(150, 100, 60)
local WOOD_LIGHT = Color3.fromRGB(205, 160, 105)
local STONE = Color3.fromRGB(205, 205, 215)
local GOLD = Color3.fromRGB(255, 215, 60)
local ROYAL = Color3.fromRGB(150, 95, 225)
local ROYAL_LIGHT = Color3.fromRGB(196, 150, 255)
local DRIP = Color3.fromRGB(255, 176, 28)
local GLOW = Color3.fromRGB(255, 196, 80)
local GEM = Color3.fromRGB(255, 70, 110)
local WHITE = Color3.fromRGB(255, 255, 255)
local CREAM = Color3.fromRGB(255, 246, 210)

-- A square layer this much of the listed width looks about as big as the old round one.
local SQUARE = 0.9

-- Profile = how wide each layer is (1 = full width), from bottom to top.
local SHAPES = {
	{ Width = 1.6, Height = 2.4, Profile = { 0.85, 1, 0.72 }, StandWidth = 2.3, StandHeight = 1.6, StandColor = WOOD, StandWood = true },
	{ Width = 3.6, Height = 4.4, Profile = { 0.85, 1, 0.88, 0.62 }, StandWidth = 4.8, StandHeight = 1.2, StandColor = WOOD, StandWood = true, Drips = 2 },
	{ Width = 6, Height = 7.2, Profile = { 0.82, 1, 0.95, 0.8, 0.55 }, StandWidth = 8.2, StandHeight = 0.9, StandColor = WOOD_LIGHT, StandWood = true, Drips = 3, Flowers = true },
	{ Width = 8.6, Height = 10.5, Profile = { 0.8, 0.97, 1, 0.9, 0.74, 0.5 }, StandWidth = 12, StandHeight = 1, StandColor = STONE, Drips = 4, Bands = CREAM, SideHives = true, Flowers = true },
	{ Width = 11, Height = 14, Profile = { 0.78, 0.95, 1, 0.95, 0.84, 0.68, 0.46 }, StandWidth = 15.5, StandHeight = 1.2, StandColor = ROYAL, Drips = 5, Bands = ROYAL, SideHives = true, Windows = true, Crown = true, Sparkles = true },
}

HiveModelFactory.MaxLevel = #SHAPES

-- PART HELPERS ------------------------------------------------------------------

local function newPart(name: string, size: Vector3, position: Vector3, color: Color3, parent: Instance, solid: boolean?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = CFrame.new(position)
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = solid == true
	part.CanTouch = false
	part.CanQuery = solid == true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- A square slab whose middle is at position.
local function layer(name: string, width: number, height: number, position: Vector3, color: Color3, parent: Instance, solid: boolean?): Part
	return newPart(name, Vector3.new(width, height, width), position, color, parent, solid)
end

-- The four sides of a square layer, in turn: right, left, back, (front is the door side).
local SIDES = { Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis }

-- A small block stuck on the outside of a layer. along = how far across the side (-0.5 .. 0.5).
local function onSide(name: string, sideIndex: number, layerWidth: number, along: number, y: number, size: Vector3, color: Color3, parent: Instance): Part
	local side = SIDES[(sideIndex - 1) % #SIDES + 1]
	local across = side:Cross(Vector3.yAxis)
	local position = side * (layerWidth / 2) + across * (along * layerWidth) + Vector3.new(0, y, 0)
	-- size is given as (across the side, up, out from the side)
	local partSize = if side.X ~= 0 then Vector3.new(size.Z, size.Y, size.X) else size
	return newPart(name, partSize, position, color, parent)
end

-- The honey-coloured body: stacked square layers, a cap and a dark doorway.
-- Returns the height of the very top.
local function buildBody(parent: Instance, width: number, height: number, profile: { number }, baseY: number, center: Vector3, namePrefix: string, solid: boolean): number
	local layerHeight = height / (#profile + 0.4)
	local y = baseY
	for index, factor in profile do
		layer(
			namePrefix .. "Ring" .. index,
			width * factor * SQUARE,
			layerHeight,
			center + Vector3.new(0, y + layerHeight / 2, 0),
			if index % 2 == 1 then HONEY_LIGHT else HONEY_DARK,
			parent,
			solid
		)
		y += layerHeight
	end

	local topWidth = width * profile[#profile] * SQUARE
	layer(
		namePrefix .. "Top",
		topWidth * 0.6,
		layerHeight * 0.45,
		center + Vector3.new(0, y + layerHeight * 0.22, 0),
		if #profile % 2 == 0 then HONEY_LIGHT else HONEY_DARK,
		parent
	)

	-- doorway on the front (-Z)
	local frontZ = -(width * profile[1] * SQUARE / 2)
	newPart(
		namePrefix .. "Door",
		Vector3.new(width * 0.28, layerHeight * 0.72, width * 0.08),
		center + Vector3.new(0, baseY + layerHeight * 0.36, frontZ),
		DOOR,
		parent
	)
	return y + layerHeight * 0.45
end

-- THE HIVE OF PLAIN BLOCKS (only used if the Blender pieces are missing) ---------------

local function createFromBlocks(level: number): Model
	local shape = SHAPES[math.clamp(math.floor(level), 1, #SHAPES)]
	local width, height = shape.Width, shape.Height
	local layerHeight = height / (#shape.Profile + 0.4)

	local model = Instance.new("Model")
	model.Name = "Hive"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	-- what the hive stands on
	local standWidth = shape.StandWidth * SQUARE
	local stand = layer("Stand", standWidth, shape.StandHeight, Vector3.new(0, shape.StandHeight / 2, 0), shape.StandColor, model, true)
	if shape.StandWood then
		layer("StandTop", standWidth * 0.82, 0.08, Vector3.new(0, shape.StandHeight + 0.04, 0), WOOD_LIGHT, model)
	elseif shape.StandColor == ROYAL then
		layer("StandTop", standWidth * 0.86, 0.3, Vector3.new(0, shape.StandHeight + 0.15, 0), ROYAL_LIGHT, model)
	end
	model.PrimaryPart = stand
	-- make the model's pivot the middle of its base, standing upright
	stand.PivotOffset = stand.CFrame:ToObjectSpace(CFrame.new())

	local bodyBase = shape.StandHeight
	local top = buildBody(model, width, height, shape.Profile, bodyBase, Vector3.zero, "", true)

	-- a little landing board under the door
	local frontZ = -(width * shape.Profile[1] * SQUARE / 2)
	newPart(
		"LandingBoard",
		Vector3.new(width * 0.42, math.max(0.08, width * 0.03), width * 0.22),
		Vector3.new(0, bodyBase + layerHeight * 0.06, frontZ - width * 0.08),
		WOOD_LIGHT,
		model
	)

	-- honey dripping down the sides
	for index = 1, shape.Drips or 0 do
		local layerIndex = math.min(#shape.Profile, 2 + (index % (#shape.Profile - 1)))
		local layerWidth = width * shape.Profile[layerIndex] * SQUARE
		local along = ((index * 37) % 50 - 25) / 100
		onSide(
			"Drip" .. index,
			index,
			layerWidth,
			along,
			bodyBase + layerHeight * (layerIndex - 0.4),
			Vector3.new(width * 0.1, layerHeight * 0.75, width * 0.06),
			DRIP,
			model
		)
	end

	-- coloured bands between some of the layers
	if shape.Bands then
		for _, layerIndex in { 2, 4 } do
			if layerIndex < #shape.Profile then
				local widest = math.max(shape.Profile[layerIndex], shape.Profile[layerIndex + 1])
				layer("Band" .. layerIndex, width * widest * SQUARE + 0.3, layerHeight * 0.16, Vector3.new(0, bodyBase + layerHeight * layerIndex, 0), shape.Bands, model)
			end
		end
	end

	-- glowing windows around the middle (not on the front, where the door is)
	if shape.Windows then
		local layerIndex = 3
		local layerWidth = width * shape.Profile[layerIndex] * SQUARE
		local spots = { { 1, -0.22 }, { 1, 0.22 }, { 2, -0.22 }, { 2, 0.22 }, { 3, 0 } }
		for step, spot in spots do
			local window = onSide(
				"Window" .. step,
				spot[1],
				layerWidth,
				spot[2],
				bodyBase + layerHeight * (layerIndex - 0.5),
				Vector3.new(width * 0.1, layerHeight * 0.55, width * 0.04),
				GLOW,
				model
			)
			window.Material = Enum.Material.Neon
		end
	end

	-- two baby hives on the stand
	if shape.SideHives then
		local offset = standWidth / 2 - width * 0.13
		for side = -1, 1, 2 do
			buildBody(model, width * 0.24, height * 0.24, { 0.85, 1, 0.72 }, bodyBase, Vector3.new(side * offset, 0, -width * 0.12), "Side" .. (if side < 0 then "Left" else "Right"), false)
		end
	end

	-- block flowers at the corners of the base
	if shape.Flowers then
		local flowerColors = { Color3.fromRGB(255, 120, 170), WHITE, Color3.fromRGB(190, 120, 255), Color3.fromRGB(110, 180, 255) }
		local reach = standWidth / 2 - 0.5
		for step, corner in { Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(1, 1) } do
			local spot = Vector3.new(corner.X * reach, bodyBase, corner.Y * reach)
			newPart("FlowerStem", Vector3.new(0.14, 0.8, 0.14), spot + Vector3.new(0, 0.4, 0), Color3.fromRGB(70, 170, 70), model)
			newPart("FlowerHead", Vector3.new(0.6, 0.5, 0.6), spot + Vector3.new(0, 0.95, 0), flowerColors[step], model)
			newPart("FlowerMiddle", Vector3.new(0.28, 0.2, 0.28), spot + Vector3.new(0, 1.28, 0), GOLD, model)
		end
	end

	-- the top: a knob, or a crown for the Royal Hive
	local topWidth = width * shape.Profile[#shape.Profile] * SQUARE
	if shape.Crown then
		local crownWidth = topWidth * 0.7
		layer("Crown", crownWidth, layerHeight * 0.4, Vector3.new(0, top + layerHeight * 0.2, 0), GOLD, model)
		for _, corner in { Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(1, 1) } do
			newPart(
				"CrownPoint",
				Vector3.new(crownWidth * 0.26, layerHeight * 0.5, crownWidth * 0.26),
				Vector3.new(corner.X * crownWidth * 0.37, top + layerHeight * 0.62, corner.Y * crownWidth * 0.37),
				GOLD,
				model
			)
		end
		newPart("CrownGem", Vector3.new(crownWidth * 0.28, crownWidth * 0.28, crownWidth * 0.12), Vector3.new(0, top + layerHeight * 0.2, -crownWidth * 0.52), GEM, model)
		top += layerHeight * 0.85
	else
		newPart("Knob", Vector3.new(topWidth * 0.26, topWidth * 0.26, topWidth * 0.26), Vector3.new(0, top + topWidth * 0.13, 0), HONEY_DARK, model)
		top += topWidth * 0.26
	end

	if shape.Sparkles then
		local sparkles = Instance.new("ParticleEmitter")
		sparkles.Name = "Sparkles"
		sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkles.Color = ColorSequence.new(GOLD, WHITE)
		sparkles.LightEmission = 1
		sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0) })
		sparkles.Lifetime = NumberRange.new(1.2, 2)
		sparkles.Rate = 6
		sparkles.Speed = NumberRange.new(2, 4)
		sparkles.SpreadAngle = Vector2.new(180, 180)
		sparkles.Parent = stand

		local glow = Instance.new("PointLight")
		glow.Name = "Glow"
		glow.Color = GLOW
		glow.Range = 18
		glow.Brightness = 0.35 -- gentle, so the honey colours do not wash out
		glow.Parent = stand
	end

	-- the stud pattern: small bumps on small hives, full-size bumps on big ones
	local bump = math.clamp(width / 5, 0.4, Studs.Size)
	for _, part in model:GetChildren() do
		if part:IsA("Part") and part.Material ~= Enum.Material.Neon then
			Studs.Add(part, bump)
		end
	end

	-- measurements the game uses to place bees and the sign
	model:SetAttribute("Level", math.clamp(math.floor(level), 1, #SHAPES))
	model:SetAttribute("Height", top)
	model:SetAttribute("Radius", math.max(shape.StandWidth, width) / 2)
	model:SetAttribute("BodyRadius", width / 2)
	model:SetAttribute("BodyBase", bodyBase)
	model:SetAttribute("BodyHeight", height)
	return model
end

-- THE BLENDER HIVES ------------------------------------------------------------------
-- A hive is a stack of square rings with rounded corners. These numbers describe each
-- one, so the game can stand a bee window on its front for every bee spot:
--   Height = its very top, BodyBase = where the honey-coloured body starts,
--   Rings = for each ring, bottom to top: { how high its middle is, how wide it is }
-- (made by blender/hives.py together with the pieces: do not edit by hand)
local BLENDER_SHAPES = {
	{ Mesh = "Hive1", Height = 7.18, StandWidth = 5.40, BodyWidth = 4.20, BodyBase = 1.40, BodyHeight = 4.90, WindowSize = 1.15, Rings = { { 2.121, 3.570 }, { 3.562, 4.200 }, { 5.003, 3.024 } } }, -- Tiny Hive
	{ Mesh = "Hive2", Height = 10.33, StandWidth = 8.00, BodyWidth = 6.20, BodyBase = 1.20, BodyHeight = 8.00, WindowSize = 1.30, Rings = { { 2.109, 5.270 }, { 3.927, 6.200 }, { 5.745, 5.456 }, { 7.564, 3.844 } } }, -- Cozy Hive
	{ Mesh = "Hive3", Height = 13.59, StandWidth = 11.50, BodyWidth = 8.60, BodyBase = 1.20, BodyHeight = 11.00, WindowSize = 1.45, Rings = { { 2.219, 7.052 }, { 4.256, 8.600 }, { 6.293, 8.170 }, { 8.330, 6.880 }, { 10.367, 4.730 } } }, -- Busy Hive
	{ Mesh = "Hive4", Height = 17.41, StandWidth = 15.00, BodyWidth = 11.00, BodyBase = 1.40, BodyHeight = 14.40, WindowSize = 1.50, Rings = { { 2.525, 8.800 }, { 4.775, 10.670 }, { 7.025, 11.000 }, { 9.275, 9.900 }, { 11.525, 8.140 }, { 13.775, 5.500 } } }, -- Grand Hive
	{ Mesh = "Hive5", Height = 21.79, StandWidth = 19.00, BodyWidth = 13.60, BodyBase = 1.60, BodyHeight = 17.60, WindowSize = 1.55, Rings = { { 2.789, 10.608 }, { 5.168, 12.920 }, { 7.546, 13.600 }, { 9.924, 12.920 }, { 12.303, 11.424 }, { 14.681, 9.248 }, { 17.059, 6.256 } }, Sparkles = true }, -- Royal Hive
}
local CORNER = 0.16 -- how much of a ring's width its rounded corner takes
local WINDOW_GAP = 0.24 -- the gap between two bee windows, as a part of a window's width

local EMPTY_WINDOW = Color3.fromRGB(96, 58, 24) -- a window nobody lives behind
local WINDOW_REACH = 1.4 -- how far in front of its window a bee hovers when it leaves or comes home

-- How many bee windows go on each ring: a honeycomb triangle on the rings above the door
-- (the bottom ring has the door, the top ring is too small). Returns the rows, bottom to
-- top, and the rings they go on. Works for any number of bee spots that fits.
local function windowRows(count: number, rings: { { number } }, size: number): ({ number }, { { number } })
	local usable = {}
	for index = 2, #rings - 1 do
		table.insert(usable, rings[index])
	end
	if #usable == 0 then
		usable = { rings[math.min(2, #rings)] }
	end
	local pitch = size * (1 + WINDOW_GAP)
	local function fits(ring: { number }): number
		local flat = ring[2] * (1 - 2 * CORNER) + ring[2] * CORNER * 0.6
		return math.max(1, math.floor((flat - size) / pitch) + 1)
	end
	local rows = {}
	for baseRow = 1, 20 do
		rows = {}
		local left = count
		for index, ring in usable do
			local want = math.min(baseRow - (index - 1), fits(ring), left)
			if want <= 0 then
				break
			end
			table.insert(rows, want)
			left -= want
		end
		if left <= 0 then
			break
		end
	end
	return rows, usable
end

-- Puts one Blender piece into a hive. where = its spot in the hive's own space,
-- size = how big (1 = as modelled). It is only for looks: nothing bumps into it.
local function addPiece(template: MeshPart, name: string, where: CFrame, size: number, parent: Instance): MeshPart
	local part = template:Clone()
	local own = template:GetAttribute("Place")
	local place: CFrame = if typeof(own) == "CFrame" then own else CFrame.identity
	part.Name = name
	part.Size = template.Size * size
	part.CFrame = where * CFrame.new(place.Position * size) * place.Rotation
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Parent = parent
	return part
end

local function createFromBlender(levelNumber: number, meshes: Instance): Model?
	local shape = BLENDER_SHAPES[levelNumber]
	local template = shape and meshes:FindFirstChild(shape.Mesh)
	if not shape or not (template and template:IsA("MeshPart")) then
		return nil
	end

	local model = Instance.new("Model")
	model.Name = "Hive"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	-- what players bump into: two unseen blocks, the stand and the body
	local stand = newPart("Stand", Vector3.new(shape.StandWidth, shape.BodyBase, shape.StandWidth), Vector3.new(0, shape.BodyBase / 2, 0), WOOD, model, true)
	stand.Transparency = 1
	model.PrimaryPart = stand
	-- make the model's pivot the middle of its base, standing upright
	stand.PivotOffset = stand.CFrame:ToObjectSpace(CFrame.new())
	local solidWidth = shape.BodyWidth * 0.9
	newPart("BodySolid", Vector3.new(solidWidth, shape.BodyHeight, solidWidth), Vector3.new(0, shape.BodyBase + shape.BodyHeight / 2, 0), HONEY_LIGHT, model, true).Transparency = 1

	-- the hive itself, with the toy-brick stud pattern on its top and sides
	-- (small bumps on small hives, full-size bumps on big ones)
	local looks = addPiece(template, "Looks", CFrame.identity, 1, model)
	looks.Color = WHITE
	local bump = math.clamp(shape.BodyWidth / 5, 0.4, Studs.Size)
	for _, face in { Enum.NormalId.Top, Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right } do
		Studs.Face(looks, face, bump)
	end

	-- one bee window for every bee spot this hive has
	local windows = Instance.new("Folder")
	windows.Name = "Windows"
	windows.Parent = model
	local frameTemplate = meshes:FindFirstChild("HiveWindowFrame")
	local paneTemplate = meshes:FindFirstChild("HiveWindowPane")
	if frameTemplate and frameTemplate:IsA("MeshPart") and paneTemplate and paneTemplate:IsA("MeshPart") then
		local capacity = GameConfig.GetHive(levelNumber).Capacity
		local rows, usable = windowRows(capacity, shape.Rings, shape.WindowSize)
		local pitch = shape.WindowSize * (1 + WINDOW_GAP)
		local number = 0
		for rowIndex, count in rows do
			local ring = usable[rowIndex]
			for index = 1, count do
				number += 1
				-- on the front (-Z) face of its ring
				local where = CFrame.new((index - (count + 1) / 2) * pitch, ring[1], -ring[2] / 2)
				addPiece(frameTemplate, "Frame" .. number, where, shape.WindowSize, windows).Color = WHITE
				local pane = addPiece(paneTemplate, "Pane" .. number, where, shape.WindowSize, windows)
				pane.Color = EMPTY_WINDOW
				pane.Material = Enum.Material.SmoothPlastic
			end
		end
	end

	if shape.Sparkles then
		local sparkles = Instance.new("ParticleEmitter")
		sparkles.Name = "Sparkles"
		sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkles.Color = ColorSequence.new(GOLD, WHITE)
		sparkles.LightEmission = 1
		sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0) })
		sparkles.Lifetime = NumberRange.new(1.2, 2)
		sparkles.Rate = 6
		sparkles.Speed = NumberRange.new(2, 4)
		sparkles.SpreadAngle = Vector2.new(180, 180)
		sparkles.Parent = stand

		local glow = Instance.new("PointLight")
		glow.Name = "Glow"
		glow.Color = GLOW
		glow.Range = 18
		glow.Brightness = 0.35 -- gentle, so the honey colours do not wash out
		glow.Parent = stand
	end

	-- measurements the game uses to place bees and the sign
	model:SetAttribute("Level", levelNumber)
	model:SetAttribute("Height", shape.Height)
	model:SetAttribute("Radius", math.max(shape.StandWidth, shape.BodyWidth) / 2)
	model:SetAttribute("BodyRadius", shape.BodyWidth / 2)
	model:SetAttribute("BodyBase", shape.BodyBase)
	model:SetAttribute("BodyHeight", shape.BodyHeight)
	return model
end

-- BUILD ---------------------------------------------------------------------------

function HiveModelFactory.Create(level: number): Model
	local levelNumber = math.clamp(math.floor(level), 1, HiveModelFactory.MaxLevel)
	local meshes = script.Parent:FindFirstChild("HiveMeshes")
	local hive = if meshes then createFromBlender(levelNumber, meshes) else nil
	return hive or createFromBlocks(levelNumber)
end

-- Lights a bee window in a bee's colour, or (color = nil) makes it an empty window again.
-- Window 1 belongs to bee spot 1, and so on. Does nothing if the hive has no such window.
function HiveModelFactory.SetWindow(hive: Instance, index: number, color: Color3?)
	local windows = hive:FindFirstChild("Windows")
	local pane = windows and windows:FindFirstChild("Pane" .. index)
	if pane and pane:IsA("BasePart") then
		pane.Color = color or EMPTY_WINDOW
		pane.Material = if color then Enum.Material.Neon else Enum.Material.SmoothPlastic
	end
end

-- The point in the air just in front of a bee window (where that bee leaves and comes
-- home), or nil if the hive has no such window.
function HiveModelFactory.WindowPoint(hive: Model, index: number): Vector3?
	local windows = hive:FindFirstChild("Windows")
	local pane = windows and windows:FindFirstChild("Pane" .. index)
	if pane and pane:IsA("BasePart") then
		return pane.Position + hive:GetPivot().LookVector * WINDOW_REACH
	end
	return nil
end

return HiveModelFactory
