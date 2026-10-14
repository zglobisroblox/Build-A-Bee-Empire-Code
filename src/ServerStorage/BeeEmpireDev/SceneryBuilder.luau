--[[
	SceneryBuilder - a DEV TOOL (it does not run while the game is played).

	It makes the two things that sit round the playable map:
	  SceneryBuilder.Sky()        the sunlight, the haze, the clouds and the screen colours
	  SceneryBuilder.Outskirts()  everything on and behind the cliffs (workspace.Map.Outskirts)
	  SceneryBuilder.Build()      both

	PlotBuilder.BuildWorld() calls Build() when it has remade the map, so a map rebuild keeps them.
	Run it by hand from the command bar with a fresh copy:
	  require(game.ServerStorage.BeeEmpireDev.SceneryBuilder:Clone()).Build()
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Studs = require(ReplicatedStorage.BeeEmpire.Studs)
local PropMeshes = ServerStorage.BeeEmpireDev.PropMeshes -- the Blender trees, bushes, rocks and flowers
local HiveMeshes = ReplicatedStorage.BeeEmpire.HiveMeshes -- the Blender hives and their six-sided windows

local SceneryBuilder = {}

-- THE SKY AND THE LIGHT ---------------------------------------------------------------------

-- All the numbers of the look, in one place.
local LOOK = {
	-- the sun: lower in the sky than noon, so everything throws a real shadow
	ClockTime = 14,
	GeographicLatitude = 22,
	Brightness = 2.6,
	ExposureCompensation = 0.12,
	ShadowSoftness = 0.32,
	SunSize = 15,
	-- sunlit sides are a little warm, shaded sides a little blue
	ColorShift_Top = Color3.fromRGB(255, 232, 196),
	Ambient = Color3.fromRGB(104, 112, 140),
	OutdoorAmbient = Color3.fromRGB(150, 162, 190),
	EnvironmentDiffuseScale = 1,
	EnvironmentSpecularScale = 0.45,
	-- far things fade into a soft blue
	Haze = { Density = 0.3, Offset = 0.12, Color = Color3.fromRGB(206, 230, 255), Decay = Color3.fromRGB(116, 164, 236), Glare = 0.28, Haze = 1.5 },
	-- drifting clouds
	Clouds = { Cover = 0.62, Density = 0.82, Color = Color3.fromRGB(255, 255, 255) },
	-- the screen: a touch more colour and punch, a soft glow on bright things, sun rays
	Color = { Saturation = 0.24, Contrast = 0.1, Brightness = 0.02, TintColor = Color3.fromRGB(255, 251, 242) },
	Bloom = { Intensity = 0.5, Size = 28, Threshold = 1.6 },
	SunRays = { Intensity = 0.07, Spread = 0.7 },
}

function SceneryBuilder.Sky()
	-- one of each, and nothing left over from the starting template (two hazes and two glows
	-- used to sit here; only the first haze counted, and it was grey)
	for _, child in Lighting:GetChildren() do
		if child:IsA("PostEffect") or child:IsA("Atmosphere") then
			child:Destroy()
		end
	end
	for _, name in { "ClockTime", "GeographicLatitude", "Brightness", "ExposureCompensation", "ShadowSoftness", "ColorShift_Top",
		"Ambient", "OutdoorAmbient", "EnvironmentDiffuseScale", "EnvironmentSpecularScale" } do
		Lighting[name] = LOOK[name]
	end
	Lighting.GlobalShadows = true

	local sky = Lighting:FindFirstChildOfClass("Sky")
	if sky then
		sky.SunAngularSize = LOOK.SunSize
		sky.StarCount = 0 -- it is always daytime here
	end

	local haze = Instance.new("Atmosphere")
	haze.Name = "BeeHaze"
	for name, value in LOOK.Haze do
		haze[name] = value
	end
	haze.Parent = Lighting

	local color = Instance.new("ColorCorrectionEffect")
	color.Name = "BeeColor"
	for name, value in LOOK.Color do
		color[name] = value
	end
	color.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Name = "BeeBloom"
	for name, value in LOOK.Bloom do
		bloom[name] = value
	end
	bloom.Parent = Lighting

	local rays = Instance.new("SunRaysEffect")
	rays.Name = "BeeSunRays"
	for name, value in LOOK.SunRays do
		rays[name] = value
	end
	rays.Parent = Lighting

	local terrain = workspace:FindFirstChildOfClass("Terrain")
	if terrain then
		for _, child in terrain:GetChildren() do
			if child:IsA("Clouds") then
				child:Destroy()
			end
		end
		local clouds = Instance.new("Clouds")
		clouds.Name = "BeeClouds"
		for name, value in LOOK.Clouds do
			clouds[name] = value
		end
		clouds.Parent = terrain
	end
end

-- THE OUTSKIRTS ---------------------------------------------------------------------------------
-- The playable map is a square. PlotBuilder.BuildWorld() puts two cliffs round it (a low lilac
-- one, a taller darker one behind it, both with grass on top) and an invisible wall in front.
-- Nobody can get past that wall, so everything made here is only to look at: nothing here can
-- be bumped into, touched or clicked.

local LOW = { Face = 263, Back = 291, Top = 27, Foot = 0 } -- the low cliff: its face, its back, the top of its grass
local HIGH = { Face = 291, Back = 331, Top = 57, Foot = 27 } -- the tall cliff behind it
local SIDES = { -- the four sides of the square (the same as in PlotBuilder)
	{ Out = Vector3.new(0, 0, -1), Along = Vector3.xAxis, Length = 680, Falls = { 0 } },
	{ Out = Vector3.new(0, 0, 1), Along = Vector3.xAxis, Length = 680, Falls = { 0 } },
	{ Out = Vector3.new(-1, 0, 0), Along = Vector3.zAxis, Length = 526, Falls = { -90, 90 } },
	{ Out = Vector3.new(1, 0, 0), Along = Vector3.zAxis, Length = 526, Falls = { -90, 90 } },
}
-- Falls = where a honey fall comes down that side. There are six: one behind every home area.

local C = {
	LowLight = Color3.fromRGB(174, 164, 208),
	LowDark = Color3.fromRGB(128, 118, 172),
	HighLight = Color3.fromRGB(138, 128, 182),
	HighDark = Color3.fromRGB(96, 88, 142),
	Outcrop = Color3.fromRGB(124, 114, 168),
	OutcropDark = Color3.fromRGB(104, 96, 150),
	Cap = Color3.fromRGB(55, 165, 90),
	CapLight = Color3.fromRGB(82, 196, 96),
	FarRock = Color3.fromRGB(146, 142, 202),
	FarRockLight = Color3.fromRGB(170, 168, 220),
	FarCap = Color3.fromRGB(96, 192, 128),
	Honey = Color3.fromRGB(250, 156, 20),
	HoneyLight = Color3.fromRGB(255, 200, 70),
	HoneyDark = Color3.fromRGB(226, 124, 14),
	CellEmpty = Color3.fromRGB(96, 58, 24),
}
local PETALS = {
	Color3.fromRGB(255, 120, 170), Color3.fromRGB(255, 90, 90), Color3.fromRGB(190, 120, 255), Color3.fromRGB(255, 255, 255),
	Color3.fromRGB(110, 180, 255), Color3.fromRGB(255, 165, 60), Color3.fromRGB(255, 214, 70),
}
local FLOWERS = { -- the garden's flowers: the body, and the white piece that takes the colour
	{ Body = "DaisyBody", Petals = "DaisyPetals" },
	{ Body = "TulipBody", Petals = "TulipPetals" },
	{ Body = "PoppyBody", Petals = "PoppyPetals" },
	{ Body = "SpikeBody", Petals = "SpikeBlossoms" },
	{ Body = "Sunflower" },
}

-- A spot on one side of the map: `along` studs along the cliff, `distance` studs out from the
-- middle of the map, `y` studs up. Whatever stands there looks IN, at the players.
local function at(side, along, distance, y, turn)
	local position = side.Out * distance + side.Along * along + Vector3.new(0, y, 0)
	return CFrame.lookAt(position, position - side.Out) * CFrame.Angles(0, math.rad(turn or 0), 0)
end

local function lookOnly(part)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	return part
end

-- A block. Its size is (along the cliff, up, in-and-out).
local function block(name, size, cframe, color, parent)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	lookOnly(part).Parent = parent
	return part
end

-- One Blender piece, standing on cframe (the same sum as PlotBuilder's prop()).
local function prop(template, cframe, parent, scale, color)
	local part = template:Clone()
	local place = template:GetAttribute("Place")
	scale = scale or 1
	part.Size = template.Size * scale
	part.CFrame = cframe * CFrame.new(place.Position * scale) * place.Rotation
	if color then
		part.Color = color
	end
	lookOnly(part).Parent = parent
	return part
end

local function studded(part)
	part:SetAttribute("Studs", true)
	return part
end

local function smooth(part)
	part:SetAttribute("NoStuds", true)
	return part
end

-- The toy-brick bumps: on every block, and on the Blender pieces that asked for them.
local function addStuds(root)
	for _, part in root:GetDescendants() do
		if part:IsA("MeshPart") then
			if part:GetAttribute("Studs") then
				for _, face in Enum.NormalId:GetEnumItems() do
					Studs.Face(part, face)
				end
			end
		elseif part:IsA("Part") and not part:GetAttribute("NoStuds") then
			-- only the faces a player can see: the top, the side that looks in at the map, and
			-- the two ends (not on the thin patches stuck to a cliff's face). Never the back.
			local size = part.Size
			local smallest = Studs.Size * 0.65
			local thin = part.Name == "RockPatch" or part.Name == "GrassHang"
			if size.X >= smallest and size.Z >= smallest then
				Studs.Face(part, Enum.NormalId.Top)
			end
			if size.Y >= smallest then
				if size.X >= smallest then
					Studs.Face(part, Enum.NormalId.Front)
				end
				if size.Z >= smallest and not thin then
					Studs.Face(part, Enum.NormalId.Left)
					Studs.Face(part, Enum.NormalId.Right)
				end
			end
		end
	end
end

local function plant(kind, cframe, scale, parent, dice)
	if kind == "Tree" or kind == "Bush" or kind == "Rock" then
		studded(prop(PropMeshes[kind], cframe, parent, scale)).Name = kind
	elseif kind == "Mushroom" or kind == "GrassTuft" then
		prop(PropMeshes[kind], cframe, parent, scale).Name = kind
	elseif kind == "LawnFlower" then
		prop(PropMeshes.FlowerStem, cframe, parent, scale).Name = "Stem"
		prop(PropMeshes.FlowerBlossom, cframe, parent, scale, PETALS[dice:NextInteger(1, #PETALS)]).Name = "Blossom"
	else -- a big garden flower
		local flower = FLOWERS[dice:NextInteger(1, #FLOWERS)]
		prop(PropMeshes[flower.Body], cframe, parent, scale).Name = "Flower"
		if flower.Petals then
			prop(PropMeshes[flower.Petals], cframe, parent, scale, PETALS[dice:NextInteger(1, #PETALS)]).Name = "Petals"
		end
	end
end

-- True if `along` is inside one of the kept-clear stretches: a list of { middle, half width }.
local function isClear(clear, along, room)
	for _, stretch in clear do
		if math.abs(along - stretch[1]) < stretch[2] + (room or 0) then
			return false
		end
	end
	return true
end

-- Picks one name from { Name = weight, ... } (in a fixed order, so the layout never changes).
local function pick(dice, order, weights)
	local total = 0
	for _, name in order do
		total += weights[name]
	end
	local roll = dice:NextNumber(0, total)
	for _, name in order do
		roll -= weights[name]
		if roll <= 0 then
			return name
		end
	end
	return order[#order]
end

-- Blocks of lighter and darker rock that stick out of a cliff's face, and tongues of grass
-- that hang over its top edge: a long flat wall turns into something built out of bricks.
local function roughFace(side, tier, light, dark, parent, dice, clear)
	local tall = tier.Top - 3 - tier.Foot
	local made, tries = 0, 0
	local wanted = math.floor(side.Length / 42)
	while made < wanted and tries < 400 do
		tries += 1
		local wide = dice:NextInteger(4, 13) * 2
		local high = dice:NextInteger(2, 5) * 2
		local along = dice:NextNumber(-side.Length / 2 + wide, side.Length / 2 - wide)
		local y = tier.Foot + dice:NextNumber(high / 2 + 1, tall - high / 2 - 2)
		if isClear(clear, along, wide / 2 + 14) then
			made += 1
			local out = dice:NextNumber(0.5, 1.5)
			block("RockPatch", Vector3.new(wide, high, 2), at(side, along, tier.Face + 1 - out, y), if made % 3 == 0 then dark else light, parent)
		end
	end
	local hangs = math.floor(side.Length / 48)
	for _ = 1, hangs do
		local wide = dice:NextInteger(2, 6) * 2
		local high = dice:NextInteger(1, 3) * 2
		local along = dice:NextNumber(-side.Length / 2 + wide, side.Length / 2 - wide)
		if isClear(clear, along, wide / 2 + 6) then
			block("GrassHang", Vector3.new(wide, high, 2), at(side, along, tier.Face - 1.6, tier.Top - 3 - high / 2 + 0.2), C.Cap, parent)
			block("GrassHang", Vector3.new(math.max(2, wide - 4), 2, 2), at(side, along + 1, tier.Face - 1.6, tier.Top - 3 - high - 0.8), C.Cap, parent)
		end
	end
end

-- Trees, bushes, rocks, big flowers and giant mushrooms along the top of a cliff.
local function plantTerrace(side, tier, parent, dice, clear, step, order, weights, sizes)
	local along = -side.Length / 2 + dice:NextNumber(3, step)
	while along < side.Length / 2 - 3 do
		local kind = pick(dice, order, weights)
		local size = sizes[kind]
		local scale = dice:NextNumber(size[1], size[2])
		local room = if kind == "Tree" then 9 * scale else 4
		local distance = dice:NextNumber(tier.Face + math.max(4, room * 0.6), tier.Back - 5)
		if isClear(clear, along, room) then
			local turn = if kind == "Flower" then dice:NextNumber(-40, 40) else dice:NextNumber(-180, 180)
			plant(kind, at(side, along, distance, tier.Top, turn), scale, parent, dice)
		end
		along += dice:NextNumber(step * 0.55, step * 1.45)
	end
end

-- Piles of rock on top of the tall cliff, so its top edge is not a straight line.
local function outcrops(side, parent, dice, clear)
	local taken = {}
	local wanted = math.floor(side.Length / 95)
	local made, tries = 0, 0
	while made < wanted and tries < 200 do
		tries += 1
		local wide = dice:NextInteger(11, 22) * 2
		local high = dice:NextInteger(5, 12) * 2
		local deep = dice:NextInteger(9, 13) * 2
		local along = dice:NextNumber(-side.Length / 2 + wide / 2 + 6, side.Length / 2 - wide / 2 - 6)
		if isClear(clear, along, wide / 2 + 10) and isClear(taken, along, wide / 2 + 16) then
			made += 1
			table.insert(taken, { along, wide / 2 })
			local distance = dice:NextNumber(HIGH.Face + deep / 2 + 4, HIGH.Back - deep / 2)
			local base = HIGH.Top - 1
			block("Outcrop", Vector3.new(wide, high, deep), at(side, along, distance, base + high / 2), if made % 2 == 0 then C.Outcrop else C.OutcropDark, parent)
			block("OutcropCap", Vector3.new(wide + 2, 2.4, deep + 2), at(side, along, distance - 0.5, base + high + 1.2), C.Cap, parent)
			local top = base + high + 2.4
			if dice:NextNumber() < 0.6 then -- a second, smaller pile on top
				local wide2, high2, deep2 = math.floor(wide * 0.5 / 2) * 2, dice:NextInteger(3, 7) * 2, math.floor(deep * 0.6 / 2) * 2
				local shift = dice:NextNumber(-wide * 0.2, wide * 0.2)
				block("Outcrop", Vector3.new(wide2, high2, deep2), at(side, along + shift, distance + 2, top - 1 + high2 / 2), C.OutcropDark, parent)
				block("OutcropCap", Vector3.new(wide2 + 2, 2.4, deep2 + 2), at(side, along + shift, distance + 1.5, top - 1 + high2 + 1.2), C.CapLight, parent)
				plant("Bush", at(side, along + shift, distance + 2, top + high2 + 1.4, dice:NextNumber(-180, 180)), dice:NextNumber(1.6, 2.4), parent, dice)
				plant("Tree", at(side, along - shift - wide * 0.22, distance, top, dice:NextNumber(-180, 180)), dice:NextNumber(0.9, 1.2), parent, dice)
			else
				plant("Tree", at(side, along + dice:NextNumber(-4, 4), distance, top, dice:NextNumber(-180, 180)), dice:NextNumber(1.1, 1.5), parent, dice)
			end
		end
	end
	return taken
end

-- A honey fall: a giant wild hive sits on the tall cliff, and its honey runs over both cliffs
-- into a puddle on the lawn. Giant honeycomb cells show in the rock on both sides of it.
local function honeyFall(side, along, parent, dice, number)
	local model = Instance.new("Model")
	model.Name = "HoneyFall" .. number
	local wide = 9
	local function honey(name, size, cframe, color)
		return smooth(block(name, size, cframe, color or C.Honey, model))
	end
	-- the hive (a different one on every other fall)
	local hiveName = if number % 2 == 0 then "Hive3" else "Hive1"
	local hiveScale = if hiveName == "Hive1" then 3.3 else 2.1
	local hiveDistance = HIGH.Face + 22
	studded(prop(HiveMeshes[hiveName], at(side, along, hiveDistance, HIGH.Top - 0.4), model, hiveScale)).Name = "GiantHive"
	-- over the top of the tall cliff, and down its face
	local lip2 = HIGH.Face - 2.6 -- just in front of the grass that hangs over the edge
	honey("Top", Vector3.new(wide, 0.9, hiveDistance - 9 - lip2), at(side, along, (hiveDistance - 9 + lip2) / 2, HIGH.Top + 0.3))
	honey("Fall", Vector3.new(wide, HIGH.Top - LOW.Top + 0.8, 1.4), at(side, along, lip2, (HIGH.Top + LOW.Top) / 2 + 0.3))
	-- across the low cliff's grass, and down its face
	local lip1 = LOW.Face - 2.6
	honey("Top", Vector3.new(wide, 0.9, lip2 - lip1), at(side, along, (lip2 + lip1) / 2, LOW.Top + 0.3))
	honey("Fall", Vector3.new(wide, LOW.Top + 0.5, 1.4), at(side, along, lip1, LOW.Top / 2 + 0.35))
	-- a lighter streak, and shorter runs beside the main one
	for _, tier in { HIGH, LOW } do
		local lip = tier.Face - 2.6
		local drop = tier.Top - tier.Foot
		honey("Shine", Vector3.new(1.6, drop * 0.8, 0.3), at(side, along - 2.2, lip - 0.75, tier.Top - drop * 0.42), C.HoneyLight)
		for _, run in { { -6.2, 0.55 }, { 6.0, 0.38 }, { 8.4, 0.2 } } do
			local long = drop * run[2] + dice:NextNumber(-1, 1)
			honey("Run", Vector3.new(2.4, long, 1.2), at(side, along + run[1], lip + 0.1, tier.Top + 0.3 - long / 2), C.Honey)
			honey("Drop", Vector3.new(2.4, 2.2, 1.2), at(side, along + run[1], lip + 0.1, tier.Top - long - 2.4), C.HoneyDark)
		end
	end
	-- the puddle on the lawn (thin: players wade through it)
	honey("Puddle", Vector3.new(22, 0.36, 9), at(side, along, lip1 - 4, 0.42))
	honey("Puddle", Vector3.new(12, 0.36, 4), at(side, along + 2, lip1 - 10, 0.42))
	honey("Puddle", Vector3.new(6, 0.36, 3), at(side, along - 9, lip1 - 9.5, 0.42))
	honey("PuddleShine", Vector3.new(8, 0.1, 2), at(side, along - 3, lip1 - 5, 0.62), C.HoneyLight)
	-- giant honeycomb cells in the rock: across (from the fall's middle), up, how big, full or empty
	local cells = {
		{ 11.5, 34.5, 7, true }, { 19.2, 34.5, 7, false }, { 15.4, 41.1, 7, true }, { 23.0, 41.1, 7, true }, { 11.5, 47.7, 7, false },
		{ -11.5, 41.1, 7, true }, { -19.2, 41.1, 7, true }, { -15.4, 47.7, 7, false }, { -15.4, 34.5, 7, true }, { -23.0, 47.7, 7, true },
		{ 11.0, 8.5, 5.4, true }, { 16.9, 8.5, 5.4, false }, { 14.0, 13.6, 5.4, true },
		{ -11.0, 13.6, 5.4, false }, { -16.9, 13.6, 5.4, true }, { -14.0, 18.7, 5.4, true },
	}
	for index, cell in cells do
		local tier = if cell[2] > LOW.Top then HIGH else LOW
		local where = at(side, along + cell[1], tier.Face + 0.2, cell[2])
		prop(HiveMeshes.HiveWindowFrame, where, model, cell[3]).Name = "CellFrame"
		local pane = prop(HiveMeshes.HiveWindowPane, where, model, cell[3], if cell[4] then (if index % 2 == 0 then C.Honey else C.HoneyLight) else C.CellEmpty)
		pane.Name = "Cell"
	end
	model.Parent = parent
end

-- Far-off hills behind the cliffs: big stepped blocks with grass on top. From across the map
-- they show over the cliffs as a jagged skyline.
local function farHills(parent, dice)
	local hills = Instance.new("Folder")
	hills.Name = "FarHills"
	local function hill(side, along)
		local wide = dice:NextInteger(40, 68) * 2
		local deep = dice:NextInteger(30, 46) * 2
		local high = dice:NextInteger(24, 44) * 2
		local distance = HIGH.Back + 14 + deep / 2 + dice:NextNumber(0, 70)
		local base = -12
		local rock = if dice:NextNumber() < 0.5 then C.FarRock else C.FarRockLight
		local steps = dice:NextInteger(2, 3)
		local shift = 0
		for step = 1, steps do
			local part = block("Hill", Vector3.new(wide, high, deep), at(side, along + shift, distance, base + high / 2), rock, hills)
			part.CastShadow = false
			local cap = block("HillCap", Vector3.new(wide + 4, 4, deep + 4), at(side, along + shift, distance, base + high + 2), C.FarCap, hills)
			cap.CastShadow = false
			base += high + 3
			shift += dice:NextNumber(-wide * 0.16, wide * 0.16)
			wide = math.floor(wide * dice:NextNumber(0.5, 0.68) / 2) * 2
			deep = math.floor(deep * dice:NextNumber(0.55, 0.7) / 2) * 2
			high = math.floor(high * dice:NextNumber(0.4, 0.62) / 2) * 2
		end
	end
	for _, side in SIDES do
		local along = -side.Length / 2 - 40 + dice:NextNumber(0, 50)
		while along < side.Length / 2 + 40 do
			hill(side, along)
			along += dice:NextNumber(84, 132)
		end
	end
	hills.Parent = parent
end

function SceneryBuilder.Outskirts()
	local map = workspace:FindFirstChild("Map")
	assert(map, "Build the map first (PlotBuilder.BuildWorld)")
	local old = map:FindFirstChild("Outskirts")
	if old then
		old:Destroy()
	end
	local outskirts = Instance.new("Folder")
	outskirts.Name = "Outskirts"

	local faces = Instance.new("Folder")
	faces.Name = "CliffFaces"
	local plants = Instance.new("Folder")
	plants.Name = "CliffPlants"
	local rocks = Instance.new("Folder")
	rocks.Name = "Outcrops"
	local foot = Instance.new("Folder")
	foot.Name = "CliffFoot"
	local falls = Instance.new("Folder")
	falls.Name = "HoneyFalls"

	local number = 0
	for sideIndex, side in SIDES do
		local dice = Random.new(100 + sideIndex)
		local clear = {} -- the stretches the honey falls need
		for _, along in side.Falls do
			number += 1
			table.insert(clear, { along, 13 })
			honeyFall(side, along, falls, dice, number)
		end
		roughFace(side, LOW, C.LowLight, C.LowDark, faces, dice, clear)
		roughFace(side, HIGH, C.HighLight, C.HighDark, faces, dice, clear)
		local piles = outcrops(side, rocks, dice, clear)
		local highClear = table.clone(clear)
		for _, pile in piles do
			table.insert(highClear, { pile[1], pile[2] + 4 })
		end
		-- the low cliff's top: smaller things, close together
		plantTerrace(side, LOW, plants, dice, clear, 17, { "Tree", "Bush", "Rock", "Flower", "Mushroom", "GrassTuft" },
			{ Tree = 26, Bush = 24, Rock = 10, Flower = 24, Mushroom = 8, GrassTuft = 8 },
			{ Tree = { 0.75, 1.05 }, Bush = { 1.5, 2.4 }, Rock = { 1.4, 2.4 }, Flower = { 1.5, 2.3 }, Mushroom = { 2.6, 4.2 }, GrassTuft = { 2, 3.2 } })
		-- the tall cliff's top: bigger trees, further apart
		plantTerrace(side, HIGH, plants, dice, highClear, 30, { "Tree", "Bush", "Rock", "Flower" },
			{ Tree = 55, Bush = 20, Rock = 10, Flower = 15 },
			{ Tree = { 1.1, 1.55 }, Bush = { 2.2, 3.4 }, Rock = { 2.2, 3.6 }, Flower = { 2.4, 3.4 } })
		-- along the foot of the low cliff, on the lawn: bushes, rocks, grass and little flowers
		local along = -263 + dice:NextNumber(2, 10)
		while along < 263 do
			if isClear(clear, along, 2) then
				local kind = pick(dice, { "Bush", "Rock", "GrassTuft", "LawnFlower", "Mushroom" }, { Bush = 30, Rock = 16, GrassTuft = 26, LawnFlower = 20, Mushroom = 8 })
				local sizes = { Bush = { 0.9, 1.5 }, Rock = { 0.8, 1.5 }, GrassTuft = { 1.1, 1.9 }, LawnFlower = { 1, 1.3 }, Mushroom = { 0.9, 1.5 } }
				plant(kind, at(side, along, dice:NextNumber(254.5, 258), 0, dice:NextNumber(-180, 180)), dice:NextNumber(sizes[kind][1], sizes[kind][2]), foot, dice)
			end
			along += dice:NextNumber(11, 25)
		end
	end
	for _, folder in { faces, plants, rocks, foot, falls } do
		folder.Parent = outskirts
	end
	farHills(outskirts, Random.new(77))

	addStuds(outskirts)
	for _, part in outskirts:GetDescendants() do
		if part:IsA("BasePart") then
			part.Locked = true -- so a stray click in Studio cannot drag it away
		end
	end
	outskirts.Parent = map
	return outskirts
end

function SceneryBuilder.Build()
	SceneryBuilder.Sky()
	SceneryBuilder.Outskirts()
end

return SceneryBuilder
