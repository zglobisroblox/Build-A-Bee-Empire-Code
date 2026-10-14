--[[
	IconStudio - makes the UI pictures' models (dev tool, never runs in the game).

	The pictures in the menus (coin, honey jar, bees, hives, padlock...) are drawn from our own
	3D models. Studio cannot save a picture of a model by itself, so this tool writes every
	model out as a short list of its blocks (shape, size, place, colour). A small drawing
	program outside Studio turns that list into the picture files, which are then uploaded.
	The uploaded picture ids live in ReplicatedStorage.BeeEmpire.UIImages.

	How to use (from the command bar or the AI helper):
		local Studio = loadstring(game.ServerStorage.BeeEmpireDev.IconStudio.Source)()
		print(Studio.Export())

	To add a picture: add a line to PICTURES below, export again, draw and upload it.
	Nothing here changes the map, the lighting or the camera.

	THE DRAWING RECIPE (so new pictures match the old ones if the drawing program is ever lost):
	- no perspective (far-away camera); the model is turned by "turn" degrees and seen from
	  "tilt" degrees above; "pre" stands a model up first (Y90: its +X side is the front,
	  Z90: its +X side is the top)
	- light from the upper left front: direction (-0.40, 0.74, 0.54) in screen terms;
	  brightness = 0.60 + 0.46 x how much a side faces the light; glowing blocks are drawn at 1.12;
	  anything above 1 leans towards white
	- 512 x 512 pixels, the model fills 86% of the picture, 3 x 3 samples per pixel
	- a 9 pixel outline in the UI's ink colour (20, 16, 26) round the outside only
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.BeeEmpire
local GameConfig = require(Shared.GameConfig)
local BeeModelFactory = require(Shared.BeeModelFactory)
local HiveModelFactory = require(Shared.HiveModelFactory)
local PropFactory = require(Shared.PropFactory)

local IconStudio = {}

local function block(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, shape: Enum.PartType?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape or Enum.PartType.Block
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.Parent = parent
	return part
end

-- a disc that faces the front of the model (-Z)
local function disc(parent: Instance, name: string, diameter: number, thickness: number, position: Vector3, color: Color3): Part
	return block(parent, name, Vector3.new(thickness, diameter, diameter), CFrame.new(position) * CFrame.Angles(0, math.rad(90), 0), color, Enum.PartType.Cylinder)
end

-- MODELS THAT ONLY EXIST AS PICTURES -----------------------------------------------------------
-- (all are built facing -Z, like the bees and hives)

local function arrowModel(): Model
	local model = Instance.new("Model")
	local green = Color3.fromRGB(63, 203, 63)
	local light = Color3.fromRGB(124, 235, 92)
	block(model, "Shaft", Vector3.new(1.4, 1.5, 1), CFrame.new(0, 0.75, 0), green)
	block(model, "Head1", Vector3.new(3.8, 0.62, 1), CFrame.new(0, 1.81, 0), green)
	block(model, "Head2", Vector3.new(2.85, 0.62, 1), CFrame.new(0, 2.43, 0), green)
	block(model, "Head3", Vector3.new(1.9, 0.62, 1), CFrame.new(0, 3.05, 0), light)
	block(model, "Head4", Vector3.new(0.95, 0.62, 1), CFrame.new(0, 3.67, 0), light)
	block(model, "Shine", Vector3.new(0.3, 0.9, 0.08), CFrame.new(-0.32, 0.8, -0.52), Color3.fromRGB(190, 255, 170))
	return model
end

local function cloverModel(): Model
	local model = Instance.new("Model")
	local green = Color3.fromRGB(70, 200, 82)
	local light = Color3.fromRGB(130, 236, 124)
	local dark = Color3.fromRGB(44, 150, 60)
	block(model, "Stem", Vector3.new(0.34, 1.7, 0.34), CFrame.new(0.3, -1.6, 0.1) * CFrame.Angles(0, 0, math.rad(18)), dark)
	for _, spot in { Vector2.new(-0.78, 0.78), Vector2.new(0.78, 0.78), Vector2.new(-0.78, -0.78), Vector2.new(0.78, -0.78) } do
		disc(model, "Leaf", 1.62, 0.6, Vector3.new(spot.X, spot.Y, 0), green)
		disc(model, "LeafShine", 0.95, 0.12, Vector3.new(spot.X * 1.02, spot.Y * 1.02, -0.32), light)
	end
	disc(model, "Middle", 0.6, 0.7, Vector3.new(0, 0, 0), dark)
	return model
end

local function lockModel(): Model
	local model = Instance.new("Model")
	local gold = Color3.fromRGB(255, 200, 40)
	local deepGold = Color3.fromRGB(236, 160, 22)
	local steel = Color3.fromRGB(205, 210, 222)
	local ink = Color3.fromRGB(20, 16, 26)
	block(model, "Body", Vector3.new(2.5, 1.25, 1.1), CFrame.new(0, 1.325, 0), gold)
	block(model, "BodyBottom", Vector3.new(2.5, 0.7, 1.1), CFrame.new(0, 0.35, 0), deepGold)
	block(model, "PostLeft", Vector3.new(0.42, 1.15, 0.42), CFrame.new(-0.72, 2.5, 0), steel)
	block(model, "PostRight", Vector3.new(0.42, 1.15, 0.42), CFrame.new(0.72, 2.5, 0), steel)
	block(model, "Bar", Vector3.new(1.86, 0.42, 0.42), CFrame.new(0, 3.28, 0), steel)
	disc(model, "Keyhole", 0.56, 0.1, Vector3.new(0, 1.2, -0.56), ink)
	block(model, "KeySlot", Vector3.new(0.24, 0.6, 0.1), CFrame.new(0, 0.82, -0.56), ink)
	return model
end

-- three thin blocks, turned 60 degrees apart, make a six-sided honeycomb cell
local function honeycombCell(model: Model, side: number, thickness: number, center: CFrame, color: Color3)
	for _, angle in { 0, 60, 120 } do
		block(model, "Cell", Vector3.new(side, side * math.sqrt(3), thickness), center * CFrame.Angles(0, 0, math.rad(angle)), color)
	end
end

-- the game's coin, a little thicker and with a honeycomb cell stamped on it
local function coinModel(): Model
	local model = Instance.new("Model")
	disc(model, "Rim", 2.2, 0.5, Vector3.new(0, 0, 0), Color3.fromRGB(255, 205, 50))
	disc(model, "Face", 1.6, 0.56, Vector3.new(0, 0, 0), Color3.fromRGB(235, 160, 20))
	honeycombCell(model, 0.53, 0.06, CFrame.new(0, 0, -0.3), Color3.fromRGB(255, 224, 112))
	return model
end

-- the game's honey jar, with a ring of honey under the lid and a honeycomb cell on the label
local function jarModel(): Model
	local model = PropFactory.Jar()
	local pivot = model:GetPivot() -- the jar is built lying along its own X axis: +X is the lid
	block(model, "HoneyRing", Vector3.new(0.14, 1.58, 1.58), pivot * CFrame.new(0.72, 0, 0), Color3.fromRGB(229, 138, 16), Enum.PartType.Cylinder)
	honeycombCell(model, 0.2, 0.04, pivot * CFrame.new(-0.05, 0, -0.8), Color3.fromRGB(255, 170, 30))
	return model
end

local function bee(rarityName: string): Model
	return BeeModelFactory.Create(GameConfig.Bees[rarityName].Color, {})
end

-- a bee with three white speed lines behind it (the Bee Speed upgrade)
local function speedBee(): Model
	local model = bee(GameConfig.BeeOrder[1])
	local pivot = model:GetPivot()
	local streak = Color3.fromRGB(235, 248, 255)
	for _, line in { { 0.7, 1.9, 1.2 }, { 0.05, 1.9, 1.7 }, { -0.55, 1.9, 1 } } do
		block(model, "Streak", Vector3.new(0.22, 0.22, line[3]), pivot * CFrame.new(0, line[1], line[2] + line[3] / 2), streak)
	end
	return model
end

-- WHAT GETS A PICTURE --------------------------------------------------------------------------

-- { picture name, what makes the model, how the drawing program should stand and turn it }
local PICTURES: { { any } } = {
	{ "Coin", coinModel, "pre=Y90 turn=-30 tilt=12" },
	{ "Jar", jarModel, "pre=Z90 turn=-24 tilt=16" },
	{ "Lock", lockModel, "turn=-24 tilt=12" },
	{ "Arrow", arrowModel, "turn=-22 tilt=10" },
	{ "Clover", cloverModel, "pre=Y90 turn=-18 tilt=8" },
	{ "SpeedBee", speedBee, "turn=-58 tilt=12" },
}
for _, rarityName in GameConfig.BeeOrder do
	table.insert(PICTURES, { "Bee" .. rarityName, function() return bee(rarityName) end, "turn=-42 tilt=16" })
end
for level = 1, HiveModelFactory.MaxLevel do
	table.insert(PICTURES, { "Hive" .. level, function() return HiveModelFactory.Create(level) end, "turn=-30 tilt=16" })
end

local function number(value: number): string
	local text = string.format("%.3f", value)
	text = text:gsub("0+$", ""):gsub("%.$", "")
	if text == "-0" then
		text = "0"
	end
	return text
end

-- One line per model ("M name options"), then one line per block:
--   shape  sizeX sizeY sizeZ  x y z  [R + 9 turn numbers]  colour  [t see-through] [n = glows]
function IconStudio.Export(): string
	local lines = {}
	for _, entry in PICTURES do
		local name, make, options = entry[1], entry[2], entry[3]
		local model = make()
		local pivot = model:GetPivot()
		table.insert(lines, "M " .. name .. " " .. options)
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") and part.Transparency < 0.98 then
				local shape = "B"
				local size = part.Size
				local mesh = part:FindFirstChildWhichIsA("SpecialMesh")
				if mesh then
					shape = if mesh.MeshType == Enum.MeshType.Sphere then "S" else "?" .. mesh.MeshType.Name
					size = size * mesh.Scale
				elseif part:IsA("Part") then
					if part.Shape == Enum.PartType.Cylinder then
						shape = "C"
					elseif part.Shape == Enum.PartType.Ball then
						shape = "S"
					elseif part.Shape ~= Enum.PartType.Block then
						shape = "?" .. part.Shape.Name
					end
				else
					shape = "?" .. part.ClassName
				end
				local relative = pivot:ToObjectSpace(part.CFrame)
				local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = relative:GetComponents()
				local fields = { shape, number(size.X), number(size.Y), number(size.Z), number(x), number(y), number(z) }
				local turned = math.abs(r00 - 1) > 0.001 or math.abs(r11 - 1) > 0.001 or math.abs(r22 - 1) > 0.001
				if turned then
					table.insert(fields, "R")
					for _, value in { r00, r01, r02, r10, r11, r12, r20, r21, r22 } do
						table.insert(fields, number(value))
					end
				end
				table.insert(fields, part.Color:ToHex())
				if part.Transparency > 0 then
					table.insert(fields, "t" .. number(part.Transparency))
				end
				if part.Material == Enum.Material.Neon then
					table.insert(fields, "n")
				end
				table.insert(lines, table.concat(fields, " "))
			end
		end
		model:Destroy()
	end
	return table.concat(lines, "\n")
end

return IconStudio
