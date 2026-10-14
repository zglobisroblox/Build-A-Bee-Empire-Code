--[[
	PlotBuilder - DEV TOOL. It is NOT used while the game is running.

	It builds the whole map out of simple blocks in a toy-brick style: flat bright colours,
	square shapes, and a square-stud pattern on every big face.
	- the Flower Garden in the middle (shared by everyone; bees fly here for nectar)
	- 6 hive plots in a ring around it, each with an orange path to the garden
	- patchy grass, block trees and flowers, a fence round the garden, cliffs round the map

	Each home area has: a road up to the beehive spot, and four stations that all FACE the
	middle of the area: on the right the Queen's roll area (the Queen in the middle, the
	honeycomb stand behind her where a rolled bee hatches and is bought, with room for more
	stands, and the Auto Roll sign) with the upgrade board beside it; on the left the Honey Jars stand (where
	worker bees bring the honey) and the Honey Market.

	Run it again any time the layout changes so all 6 plots stay identical:

		require(game.ServerStorage.BeeEmpireDev.PlotBuilder).BuildAll()

	Names the game scripts rely on (keep these if you replace the art):
		Workspace.FlowerGarden.Flowers.FlowerN   (attribute BeeSpot = where a bee hovers)
		Workspace.Plots.PlotN            (attributes: PlotIndex, OwnerUserId)
			Base, Rim, SpawnPad, OwnerSign.Sign.NameTag.Label
			HiveAnchor (where the beehive stands; HiveInfo.Title/Sub sign)
			HiveSpot (Prompt that opens the My Hive window)
			Queen.RollSpot (Prompt that rolls a bee)
			Queen.Stands.Stand1 (tag RollStand, attribute StandIndex; the game writes the
				attributes OfferStart / OfferRarity / OfferPrice / OfferNew on it):
				BeeSpot (where the bee stands), BuySpot (Prompt that buys the bee),
				Screen.Face (Mystery, BeeName, Rarity, Price.Label, Price.Coin), NewTag.Face.Text
				Only stand 1 is built here. When its owner gets more stands (the More Rolls
				upgrade) the game makes them from stand 1 and spreads them all along an arc.
			Queen.Stands (attributes "Spot_<how many stands>_<which stand>" = where each stand
				goes for each number of stands; the game reads them)
			Queen.AutoRoll (the sign that sells Auto Roll; the game takes it away once bought):
				Sign.Face.Price.Label (the price), BuySpot (Prompt)
			Upgrades.UpgradeSpot (Prompt that opens the Upgrades window),
			Upgrades.Board.Face.Panel_<upgrade id> (Title, Value, Price.Label: the upgrade board)
			CollectStation.Table (Prompt), CollectStation.Jars (each jar has the attribute Order),
			CollectStation.DropSpot (where worker bees drop honey),
			CollectStation.Sign.Face (the jar-shaped sign: Amount = the big number,
				Honey = the honey that rises inside it)
			Market.Counter (Prompt, Info.Title/Sub)
			(the Hive model itself is built by HiveService while the game runs)
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.BeeEmpire.GameConfig)
local BeeModelFactory = require(ReplicatedStorage.BeeEmpire.BeeModelFactory)
local Upgrades = require(ReplicatedStorage.BeeEmpire.Upgrades)
local NumberFormat = require(ReplicatedStorage.BeeEmpire.NumberFormat)
local Studs = require(ReplicatedStorage.BeeEmpire.Studs)
local UIImages = require(ReplicatedStorage.BeeEmpire.UIImages)

-- Trees, flowers, grass, the garden fence, bushes, rocks and mushrooms were modelled in Blender
-- (rounded toy pieces), and so were the honeycomb stand (Stall, StallBulbs) and the Queen's
-- pedestal (Pedestal, PedestalGems). They are kept next to this tool. Each has a "Place" attribute: where
-- the piece sits when the prop stands on the origin.
local PropMeshes = game:GetService("ServerStorage").BeeEmpireDev.PropMeshes
local GARDEN_HEAD = 5 -- the garden-flower pieces were modelled for a flower head this many studs wide

local PlotBuilder = {}

local FONT = Enum.Font.FredokaOne
local FLOOR = 0 -- everything stands straight on the grass now (this used to be the height of a plot's floor)
local PLOT_WIDTH = 124 -- a player's home area (open ground now, not a walled floor)
local PLOT_DEPTH = 116
local RING_RADIUS = 180 -- how far each home area's centre is from the middle of the map
local GARDEN_RADIUS = 44
local MAP_SIZE = 530

-- The toy-brick look: a square-stud picture is laid over every big flat face.
-- (The picture itself is set in ReplicatedStorage.BeeEmpire.Studs.)
local STUD_SIZE = Studs.Size -- how many studs wide one bump is
local MIN_STUD_FACE = STUD_SIZE * 0.65 -- faces smaller than this stay plain

local C = {
	Grass = Color3.fromRGB(70, 200, 60),
	GrassDark = Color3.fromRGB(70, 160, 65),
	GrassLight = Color3.fromRGB(170, 225, 110),
	Meadow = Color3.fromRGB(205, 235, 140),
	Soil = Color3.fromRGB(125, 80, 55),
	SoilDark = Color3.fromRGB(95, 60, 45),
	PathEdge = Color3.fromRGB(190, 100, 45), -- the darker rim under a path
	Stone = Color3.fromRGB(150, 150, 185), -- flat stones on the lawn
	StoneDark = Color3.fromRGB(122, 122, 160),
	Cream = Color3.fromRGB(235, 215, 175), -- stepping stones
	Kerb = Color3.fromRGB(80, 220, 50), -- the bright edge round the hive's platform
	PlatformSide = Color3.fromRGB(55, 165, 90),
	Path = Color3.fromRGB(235, 135, 60),
	Base = Color3.fromRGB(250, 215, 75),
	Rim = Color3.fromRGB(235, 150, 45),
	Spawn = Color3.fromRGB(255, 250, 225),
	Purple = Color3.fromRGB(150, 95, 225),
	PurpleLight = Color3.fromRGB(196, 150, 255),
	Gem = Color3.fromRGB(140, 60, 200),
	Pink = Color3.fromRGB(255, 160, 205),
	Lilac = Color3.fromRGB(205, 140, 240),
	BeeYellow = Color3.fromRGB(255, 200, 40),
	CellRim = Color3.fromRGB(225, 130, 25),
	CellFill = Color3.fromRGB(255, 180, 45),
	Door = Color3.fromRGB(70, 40, 15),
	Wood = Color3.fromRGB(195, 135, 80),
	WoodDark = Color3.fromRGB(120, 70, 50),
	Sand = Color3.fromRGB(225, 175, 120),
	Tan = Color3.fromRGB(215, 170, 110),
	TanLight = Color3.fromRGB(235, 200, 145),
	Jar = Color3.fromRGB(255, 170, 30),
	Lid = Color3.fromRGB(250, 242, 225),
	RoofBlue = Color3.fromRGB(90, 195, 255),
	MarketWood = Color3.fromRGB(195, 100, 50),
	Red = Color3.fromRGB(225, 40, 40),
	White = Color3.fromRGB(255, 255, 255),
	Gold = Color3.fromRGB(255, 200, 40),
	Ink = Color3.fromRGB(20, 16, 24), -- text outlines
	Navy = Color3.fromRGB(30, 30, 62),
	Bulb = Color3.fromRGB(255, 230, 40),
	Stem = Color3.fromRGB(60, 160, 65),
	Tuft = Color3.fromRGB(40, 130, 60),
	Trunk = Color3.fromRGB(120, 70, 55),
	Leaf = Color3.fromRGB(45, 120, 55),
	LeafLight = Color3.fromRGB(80, 155, 70),
	FencePost = Color3.fromRGB(90, 60, 45),
	FenceRail = Color3.fromRGB(135, 95, 65),
	Cliff = Color3.fromRGB(150, 140, 185),
	CliffDark = Color3.fromRGB(115, 105, 160),
	CliffCap = Color3.fromRGB(55, 165, 90),
	SunflowerMiddle = Color3.fromRGB(120, 75, 35),
	Avenue = Color3.fromRGB(255, 240, 185),
	Teal = Color3.fromRGB(40, 185, 190),
	TealLight = Color3.fromRGB(150, 232, 228),
	Lamp = Color3.fromRGB(255, 225, 140),
	BuilderBee = Color3.fromRGB(255, 150, 50),
	Lime = Color3.fromRGB(120, 255, 40), -- "2 > 4" text on the upgrade board
	PillGreen = Color3.fromRGB(50, 205, 60),
}

local FLOWER_COLORS = {
	Color3.fromRGB(255, 120, 170),
	Color3.fromRGB(255, 90, 90),
	Color3.fromRGB(190, 120, 255),
	Color3.fromRGB(255, 255, 255),
	Color3.fromRGB(110, 180, 255),
	Color3.fromRGB(255, 165, 60),
}

-- PART HELPERS ----------------------------------------------------------------

local function block(name, size, cframe, color, parent, material)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- An upright cylinder (only used for small round things like jars and coins).
local function cylinder(name, diameter, height, cframe, color, parent, material)
	local part = block(
		name,
		Vector3.new(height, diameter, diameter),
		cframe * CFrame.Angles(0, 0, math.rad(90)),
		color,
		parent,
		material
	)
	part.Shape = Enum.PartType.Cylinder
	return part
end

local function decoration(part)
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	return part
end

local function invisible(part)
	part.Transparency = 1
	part.CanCollide = false
	part.CanTouch = false
	return part
end

-- This part keeps plain faces (used where a sign's writing goes).
local function plain(part)
	part:SetAttribute("NoStuds", true)
	return part
end

-- A glowing block (lamps and sign bulbs).
local function glow(name, size, cframe, color, parent)
	local part = decoration(block(name, size, cframe, color, parent, Enum.Material.Neon))
	return part
end

-- BLENDER PIECES ---------------------------------------------------------------------

-- Puts one Blender piece into the world. cframe = where the prop stands (its ground point),
-- scale = how big (1 = as modelled), color = the tint for pieces that are white (petals).
local function prop(name, cframe, parent, scale, color)
	local template = PropMeshes[name]
	local part = template:Clone()
	local place = template:GetAttribute("Place")
	scale = scale or 1
	part.Size = template.Size * scale
	part.CFrame = cframe * CFrame.new(place.Position * scale) * place.Rotation
	if color then
		part.Color = color
	end
	part.Parent = parent
	return part
end

-- Marks a Blender piece so AddStuds lays the stud pattern over it (trees, bushes, rocks).
local function studded(part)
	part:SetAttribute("Studs", true)
	return part
end

-- Turns and sizes for the Blender props, so no two look quite the same. It has its own
-- fixed seed, so using it never moves anything else on the map.
local look = Random.new(23)

-- STUDS -----------------------------------------------------------------------------

local function studTexture(part, face)
	Studs.Face(part, face, STUD_SIZE)
end

-- Lays the stud pattern over every big flat face of every plain block under root.
function PlotBuilder.AddStuds(root)
	local parts = root:GetDescendants()
	table.insert(parts, root)
	for _, part in parts do
		if part:IsA("MeshPart") and part:GetAttribute("Studs") and not part:FindFirstChildOfClass("Texture") then
			-- a Blender piece that asked for studs: the picture goes on from all six sides
			for _, face in Enum.NormalId:GetEnumItems() do
				studTexture(part, face)
			end
		end
		if
			part:IsA("Part")
			and part.Shape == Enum.PartType.Block
			and part.Transparency < 0.5
			and part.Material ~= Enum.Material.Neon
			and not part:GetAttribute("NoStuds")
			and not part:FindFirstChild("Studs")
			and not part:FindFirstChildOfClass("SpecialMesh")
			and not (part.Parent and part.Parent:GetAttribute("BasePivot")) -- the bees stay smooth
		then
			local size = part.Size
			if size.X >= MIN_STUD_FACE and size.Z >= MIN_STUD_FACE then
				studTexture(part, Enum.NormalId.Top)
			end
			if size.Y >= MIN_STUD_FACE then
				if size.X >= MIN_STUD_FACE then
					studTexture(part, Enum.NormalId.Front)
					studTexture(part, Enum.NormalId.Back)
				end
				if size.Z >= MIN_STUD_FACE then
					studTexture(part, Enum.NormalId.Left)
					studTexture(part, Enum.NormalId.Right)
				end
			end
		end
	end
end

-- SIGNS AND TEXT ------------------------------------------------------------------------

-- A dark outline that grows and shrinks with the text (for floating signs).
local function scaledOutline(label, thickness)
	local stroke = Instance.new("UIStroke")
	stroke.Color = C.Ink
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.StrokeSizingMode = Enum.StrokeSizingMode.ScaledSize
	stroke.Thickness = thickness
	stroke.Parent = label
	return stroke
end

-- A dark outline a fixed number of pixels thick (for writing on boards).
local function outline(guiObject, pixels, color)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or C.Ink
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Thickness = pixels
	if not guiObject:IsA("TextLabel") then
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	end
	stroke.Parent = guiObject
	return stroke
end

-- Floating text above a part. Sizes are in studs so the text shrinks with distance.
-- A line with Gold = true is drawn in the big yellow-to-orange title style.
local function billboard(name, adornee, width, height, offsetY, lines, maxDistance)
	local gui = Instance.new("BillboardGui")
	gui.Name = name
	gui.Size = UDim2.fromScale(width, height)
	gui.StudsOffsetWorldSpace = Vector3.new(0, offsetY, 0)
	gui.MaxDistance = maxDistance or 160
	gui.DistanceLowerLimit = 28 -- stops the text growing huge when you stand right next to it
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false

	local y = 0
	for _, line in lines do
		local label = Instance.new("TextLabel")
		label.Name = line.Name
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromScale(0, y)
		label.Size = UDim2.fromScale(1, line.Height)
		label.Font = FONT
		label.TextScaled = true
		label.Text = line.Text
		label.TextColor3 = line.Color or C.White
		label.Parent = gui
		if line.Gold then
			label.TextColor3 = C.White
			local fade = Instance.new("UIGradient")
			fade.Rotation = 90
			fade.Color = ColorSequence.new(Color3.fromRGB(255, 232, 70), Color3.fromRGB(255, 160, 24))
			fade.Parent = label
		end
		scaledOutline(label, if line.Gold then 0.085 else 0.075)
		y += line.Height
	end

	gui.Parent = adornee
	return gui
end

-- Writing on the face of a board.
local function boardText(parent, name, text, color, position, size, strokePixels)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Position = position
	label.Size = size
	label.Font = FONT
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = color
	label.Parent = parent
	outline(label, strokePixels or 3)
	return label
end

local function surfaceGui(name, part, pixelsPerStud)
	local face = Instance.new("SurfaceGui")
	face.Name = name
	face.Face = Enum.NormalId.Back -- the side that faces the front of the plot
	face.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	face.PixelsPerStud = pixelsPerStud or 40
	face.LightInfluence = 0
	face.Parent = part
	return face
end

local function shape(parent, name, color, position, size, cornerScale)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = position
	frame.Size = size
	frame.Parent = parent
	if cornerScale then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(cornerScale, 0)
		corner.Parent = frame
	end
	return frame
end

-- The "press E / tap" button that appears when a player walks close.
local function prompt(parent, action, objectText, actionText, distance)
	local proximityPrompt = Instance.new("ProximityPrompt")
	proximityPrompt.Name = "Prompt"
	proximityPrompt.ObjectText = objectText
	proximityPrompt.ActionText = actionText
	proximityPrompt.HoldDuration = 0
	proximityPrompt.MaxActivationDistance = distance or GameConfig.InteractDistance
	proximityPrompt.RequiresLineOfSight = false
	proximityPrompt.KeyboardKeyCode = Enum.KeyCode.E
	proximityPrompt:SetAttribute("Action", action)
	proximityPrompt.Parent = parent
	return proximityPrompt
end

-- A small lantern: a glowing cube under a little cap.
local function lantern(cframe, parent)
	glow("Lamp", Vector3.new(1.2, 1.3, 1.2), cframe, C.Lamp, parent)
	decoration(block("LampCap", Vector3.new(1.6, 0.35, 1.6), cframe * CFrame.new(0, 0.8, 0), C.Rim, parent))
end

-- A picture from BeeEmpire.UIImages (the same drawings of our 3D models that the menus use).
local function picture(parent, name, image, position, size)
	local label = Instance.new("ImageLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = position
	label.Size = size
	label.Image = image
	label.ScaleType = Enum.ScaleType.Fit
	label.Parent = parent
	return label
end

-- THE UPGRADE BOARD ------------------------------------------------------------------------
-- One bright panel per upgrade: a picture, the name, "2 > 4" and a price pill.
-- The game fills in Value and Price.Label (see UpgradeService).

local PANEL_STYLES = {
	Hive = { Rotation = 0, Colors = { Color3.fromRGB(255, 90, 190), Color3.fromRGB(175, 90, 255) } },
	Luck = { Rotation = 0, Colors = { Color3.fromRGB(255, 240, 40), Color3.fromRGB(255, 130, 200), Color3.fromRGB(200, 110, 255) } },
	BeeSpeed = { Rotation = 90, Colors = { Color3.fromRGB(255, 190, 140), Color3.fromRGB(255, 50, 50) } },
	Rolls = { Rotation = 0, Colors = { Color3.fromRGB(40, 215, 255), Color3.fromRGB(50, 140, 255) } },
}
local DEFAULT_PANEL_STYLE = { Rotation = 0, Colors = { Color3.fromRGB(120, 200, 255), Color3.fromRGB(80, 120, 255) } }

-- The same pictures the Upgrade Shop window shows.
local PANEL_PICTURES = { Hive = UIImages.Hive(2), Luck = UIImages.Clover, BeeSpeed = UIImages.SpeedBee, Rolls = UIImages.Egg }

local function panelIcon(holder, id)
	picture(holder, "Picture", PANEL_PICTURES[id] or UIImages.Jar, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(1.15, 1.15))
end

local function upgradePanel(face, id, column, row)
	local style = PANEL_STYLES[id] or DEFAULT_PANEL_STYLE
	local panel = Instance.new("Frame")
	panel.Name = "Panel_" .. id
	panel.BackgroundColor3 = C.White
	panel.BorderSizePixel = 0
	panel.Position = UDim2.new(column * 0.5, if column == 0 then 8 else 4, row * 0.5, if row == 0 then 8 else 4)
	panel.Size = UDim2.new(0.5, -12, 0.5, -12)
	panel.Parent = face
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.1, 0)
	corner.Parent = panel
	outline(panel, 4)
	local fade = Instance.new("UIGradient")
	fade.Rotation = style.Rotation
	local points = {}
	for index, color in style.Colors do
		table.insert(points, ColorSequenceKeypoint.new((index - 1) / (#style.Colors - 1), color))
	end
	fade.Color = ColorSequence.new(points)
	fade.Parent = panel

	local title = boardText(panel, "Title", Upgrades.DisplayName(id), C.White, UDim2.fromScale(0.04, 0.05), UDim2.fromScale(0.92, 0.26), 3.5)
	title.Rotation = -3

	local iconHolder = Instance.new("Frame")
	iconHolder.Name = "Icon"
	iconHolder.BackgroundTransparency = 1
	iconHolder.Position = UDim2.fromScale(0.05, 0.36)
	iconHolder.Size = UDim2.fromScale(0.52, 0.56)
	iconHolder.SizeConstraint = Enum.SizeConstraint.RelativeYY -- a square, as tall as 56% of the panel
	iconHolder.Parent = panel
	panelIcon(iconHolder, id)

	local value = boardText(panel, "Value", (Upgrades.DescribeChangeShort or Upgrades.DescribeChange)(id, 1), C.Lime, UDim2.fromScale(0.36, 0.33), UDim2.fromScale(0.61, 0.27), 3.5)
	value.Rotation = -3

	local pill = Instance.new("Frame")
	pill.Name = "Price"
	pill.BackgroundColor3 = C.PillGreen
	pill.BorderSizePixel = 0
	pill.Position = UDim2.fromScale(0.42, 0.65)
	pill.Size = UDim2.fromScale(0.5, 0.27)
	pill.Parent = panel
	local pillCorner = Instance.new("UICorner")
	pillCorner.CornerRadius = UDim.new(0.3, 0)
	pillCorner.Parent = pill
	outline(pill, 3, Color3.fromRGB(20, 90, 30))
	local pillFade = Instance.new("UIGradient") -- paler at the top
	pillFade.Rotation = 90
	pillFade.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 200, 200))
	pillFade.Parent = pill
	pill.Rotation = -2
	boardText(pill, "Label", "", C.White, UDim2.fromScale(0.06, 0.08), UDim2.fromScale(0.88, 0.84), 3)
	return panel
end

-- THE HONEYCOMB STAND -----------------------------------------------------------------
-- A block of honeycomb with a dark screen in a red frame of glowing bulbs. A rolled bee
-- hatches on the six-sided cell on top. Its looks are two Blender pieces (Stall and
-- StallBulbs); the screen, the "New!" tag and the unseen markers are made here. The game
-- fills in the screen and puts the egg / shadow / bee on the stand (see WorldFX and BeeService).

-- The stand's own parts are laid out big and then shrunk to this, so five stands fit in a
-- row. (The Blender pieces were made at this size.)
local STAND_SIZE = 0.75

-- frame = where the stand stands (its floor middle); its front (+Z) is the side with the screen.
local function rollStand(index, frame, parent)
	local stand = Instance.new("Model")
	stand.Name = "Stand" .. index
	stand.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- it reaches a player's device in one piece
	stand:SetAttribute("StandIndex", index)
	CollectionService:AddTag(stand, "RollStand")
	local function s(dx, dy, dz)
		return frame * CFrame.new(dx, dy, dz)
	end

	-- an unseen block the size of the whole stand: it is what players bump into
	local body = plain(block("Body", Vector3.new(8.6, 5.8, 6.2), s(0, 2.9, 0), C.BeeYellow, stand))
	body.Transparency = 1

	-- BeeSpot: where a bee's own middle goes when it stands on the cell (its top is the cell's top)
	local beeSpot = invisible(block("BeeSpot", Vector3.new(1, 0.2, 1), s(0, 6.34, -0.25), C.White, stand))
	beeSpot.CanQuery = false

	-- the screen: dark, set into the red frame
	local screen = plain(block("Screen", Vector3.new(6.2, 2.8, 0.3), s(0, 2.5, 2.95), C.Navy, stand))

	-- what the screen can show (all hidden until a roll; WorldFX shows the right lines)
	local face = surfaceGui("Face", screen, 40)
	boardText(face, "Mystery", "???", C.White, UDim2.fromScale(0.1, 0.18), UDim2.fromScale(0.8, 0.64), 5).Visible = false
	boardText(face, "BeeName", "", C.White, UDim2.fromScale(0.04, 0.05), UDim2.fromScale(0.92, 0.26), 3).Visible = false
	boardText(face, "Rarity", "", C.White, UDim2.fromScale(0.04, 0.3), UDim2.fromScale(0.92, 0.33), 4).Visible = false
	local pill = shape(face, "Price", C.PillGreen, UDim2.fromScale(0.5, 0.81), UDim2.fromScale(0.56, 0.28), 0.3)
	outline(pill, 3, Color3.fromRGB(20, 90, 30))
	pill.Visible = false
	local coin = picture(pill, "Coin", UIImages.Coin, UDim2.fromScale(0.16, 0.5), UDim2.fromScale(0.86, 0.86))
	coin.SizeConstraint = Enum.SizeConstraint.RelativeYY -- a square nearly as tall as the pill
	boardText(pill, "Label", "", C.White, UDim2.fromScale(0.28, 0.06), UDim2.fromScale(0.66, 0.88), 3)

	-- the tilted "New!" tag over the top corner (shown for a kind of bee you do not have yet)
	local newTag = invisible(plain(block("NewTag", Vector3.new(3.4, 1.4, 0.1), s(2.9, 4.6, 3.8) * CFrame.Angles(0, 0, math.rad(-26)), C.White, stand)))
	newTag.CanQuery = false
	boardText(surfaceGui("Face", newTag, 40), "Text", "New!", Color3.fromRGB(7, 249, 251), UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), 4).Visible = false

	-- the Buy button floats above the bee, so it never hides the screen
	local buySpot = invisible(block("BuySpot", Vector3.new(1, 1, 1), s(0, 8.3, 3.2), C.White, stand))
	buySpot.CanQuery = false
	-- (a short reach, so it never overlaps the Queen's Roll button: pressing E to buy must
	-- never roll the bee away instead)
	prompt(buySpot, "BuyBee", "Honeycomb Stand", "Buy Bee", 8)

	-- Shrink the stand about the middle of its floor. The writing keeps its sharpness.
	-- (The stand's pivot is the middle of its floor from now on: the game uses that to put
	-- the stands it copies onto their places.)
	stand.PrimaryPart = body
	body.PivotOffset = body.CFrame:ToObjectSpace(frame)
	local guiSizes = {}
	for _, descendant in stand:GetDescendants() do
		if descendant:IsA("SurfaceGui") then
			guiSizes[descendant] = descendant.PixelsPerStud
		end
	end
	stand:ScaleTo(STAND_SIZE)
	for gui, pixels in guiSizes do
		gui.PixelsPerStud = pixels / STAND_SIZE
	end

	-- THE LOOKS: the Blender honeycomb stand and its glowing bulbs. They were made at the
	-- stand's final size, so they go on after the shrink. (A Blender piece's front faces the
	-- other way, so it is turned half round.)
	local looks = frame * CFrame.Angles(0, math.pi, 0)
	decoration(prop("Stall", looks, stand))
	decoration(prop("StallBulbs", looks, stand)).Name = "Bulbs"

	stand.Parent = parent
	return stand
end

-- THE SIGN THAT SELLS AUTO ROLL: an orange board on a post. frame = where its post stands;
-- its front (+Z) is the side with the writing. The game writes the price on it and takes
-- the whole sign away once its owner has bought Auto Roll (see BeeService).
local function autoRollSign(frame, parent)
	local model = Instance.new("Model")
	model.Name = "AutoRoll"
	local function s(dx, dy, dz)
		return frame * CFrame.new(dx, dy, dz)
	end
	local price = NumberFormat.Short(GameConfig.AutoRollPrice or 1000)
	block("Post", Vector3.new(0.9, 3.4, 0.9), s(0, 1.7, -0.2), C.FencePost, model)
	decoration(block("PostFoot", Vector3.new(2.2, 0.3, 2.2), s(0, 0.15, -0.2), C.Stone, model))
	local boardCFrame = s(0, 4.9, 0) * CFrame.Angles(math.rad(-8), 0, 0)
	decoration(plain(block("SignRim", Vector3.new(7, 4.4, 0.4), boardCFrame * CFrame.new(0, 0, -0.25), Color3.fromRGB(200, 100, 30), model)))
	local sign = plain(block("Sign", Vector3.new(6.4, 3.8, 0.5), boardCFrame, C.Path, model))
	decoration(plain(block("SignTop", Vector3.new(7, 0.35, 0.9), boardCFrame * CFrame.new(0, 2.25, -0.05), Color3.fromRGB(255, 222, 70), model)))

	local face = surfaceGui("Face", sign, 40)
	local title = boardText(face, "Title", "AUTO ROLL", C.White, UDim2.fromScale(0.04, 0.04), UDim2.fromScale(0.92, 0.36), 4)
	title.Rotation = -2
	boardText(face, "Sub", "Your Queen rolls by herself!", Color3.fromRGB(255, 244, 200), UDim2.fromScale(0.05, 0.4), UDim2.fromScale(0.9, 0.2), 3)
	local pill = shape(face, "Price", C.PillGreen, UDim2.fromScale(0.5, 0.79), UDim2.fromScale(0.52, 0.3), 0.3)
	outline(pill, 3, Color3.fromRGB(20, 90, 30))
	local coin = picture(pill, "Coin", UIImages.Coin, UDim2.fromScale(0.17, 0.5), UDim2.fromScale(0.86, 0.86))
	coin.SizeConstraint = Enum.SizeConstraint.RelativeYY -- a square nearly as tall as the pill
	boardText(pill, "Label", price, C.White, UDim2.fromScale(0.3, 0.06), UDim2.fromScale(0.64, 0.88), 3)

	-- the button sits low, so it never hides the writing on the board
	local buySpot = invisible(block("BuySpot", Vector3.new(1, 1, 1), s(0, 0.5, 2.2), C.White, model))
	buySpot.CanQuery = false
	prompt(buySpot, "BuyAutoRoll", price .. " coins  -  you only pay once", "Buy Auto Roll", 6)

	model.PrimaryPart = sign
	model.Parent = parent
	return model
end

-- PATHS -----------------------------------------------------------------------------
-- A path is an orange plate one step above the grass, on a slightly wider dark rim, with
-- edges that step in and out like pixels. cframe = the middle of the path at ground level;
-- the path runs along its own Z. top = how high its surface is (side paths sit a touch lower
-- than the main one, so the two never flicker where they cross).
local function steppedPath(name, cframe, width, length, parent, dice, top)
	top = top or 0.3
	local rim = top - 0.1
	block(name .. "Rim", Vector3.new(width + 2, rim, length + 2), cframe * CFrame.new(0, rim / 2, 0), C.PathEdge, parent)
	block(name, Vector3.new(width, top, length), cframe * CFrame.new(0, top / 2, 0), C.Path, parent)
	for side = -1, 1, 2 do
		local along = -length / 2 + dice:NextInteger(0, 3) * 2
		while along < length / 2 - 2 do
			local stepLength = math.min(dice:NextInteger(1, 3) * 2, length / 2 - along)
			local out = dice:NextInteger(1, 2) * 2
			local middle = cframe * CFrame.new(side * (width / 2 + out / 2), 0, along + stepLength / 2)
			decoration(block("PathStepRim", Vector3.new(out + 2, rim - 0.03, stepLength + 2), middle * CFrame.new(0, (rim - 0.03) / 2, 0), C.PathEdge, parent))
			decoration(block("PathStep", Vector3.new(out, top, stepLength), middle * CFrame.new(0, top / 2, 0), C.Path, parent))
			along += stepLength + dice:NextInteger(1, 4) * 2
		end
	end
end

-- WHERE THE PLOTS GO ------------------------------------------------------------
-- Six plots in a ring. Each plot's local +Z (its FRONT) points at the garden in the middle.

local PLOT_ORIGINS = {}
for index = 1, 6 do
	local angle = math.rad(30 + (index - 1) * 60)
	local position = Vector3.new(math.cos(angle) * RING_RADIUS, 0, math.sin(angle) * RING_RADIUS)
	PLOT_ORIGINS[index] = CFrame.lookAt(position, Vector3.zero) * CFrame.Angles(0, math.pi, 0)
end

-- ONE HIVE PLOT -----------------------------------------------------------------

function PlotBuilder.BuildPlot(index, origin, parent)
	local plot = Instance.new("Model")
	plot.Name = "Plot" .. index
	plot:SetAttribute("PlotIndex", index)
	plot:SetAttribute("OwnerUserId", 0)

	local function at(x, y, z)
		return origin * CFrame.new(x, y, z)
	end

	-- THE HOME AREA is open ground, like a clearing in the lawn. Nothing stands on a platform:
	-- the hive, the stations and the road all lie straight on the grass. One wide road runs
	-- from the garden up to the hive. On one side of it the Queen and the upgrade board stand
	-- together; on the other side the Honey Jars and the Honey Market share one honey yard.
	local dice = Random.new(100 + index) -- this area's own dice (stepped edges, plants, stones)

	-- An unseen part marks the middle and the size of the area.
	local base = invisible(plain(block("Base", Vector3.new(PLOT_WIDTH, 0.2, PLOT_DEPTH), at(0, -0.3, 0), C.Grass, plot)))
	base.CanQuery = false
	plot.PrimaryPart = base

	-- A patch of ground: a thin plate, level with the paths, whose edge steps in and out so
	-- it reads as worn ground and not as a slab. frame = its middle at ground level.
	local function groundPatch(frame, width, depth, top, color, rimColor, parent)
		block("PadRim", Vector3.new(width + 2, top - 0.06, depth + 2), frame * CFrame.new(0, (top - 0.06) / 2, 0), rimColor, parent)
		block("Floor", Vector3.new(width, top, depth), frame * CFrame.new(0, top / 2, 0), color, parent)
		for side = 1, 4 do
			local alongX = side <= 2 -- sides 1 and 2 run along X, sides 3 and 4 along Z
			local length = if alongX then width else depth
			local across = if alongX then depth else width
			local sign = if side % 2 == 1 then 1 else -1
			local along = -length / 2 + dice:NextInteger(0, 2) * 2
			while along < length / 2 - 2 do
				local stepLength = math.min(dice:NextInteger(1, 3) * 2, length / 2 - along)
				local out = dice:NextInteger(1, 2) * 2
				local middle = along + stepLength / 2
				local reach = sign * (across / 2 + out / 2)
				local size = if alongX then Vector3.new(stepLength, top, out) else Vector3.new(out, top, stepLength)
				local where = if alongX then frame * CFrame.new(middle, 0, reach) else frame * CFrame.new(reach, 0, middle)
				decoration(block("PadStepRim", size + Vector3.new(2, -0.09, 2), where * CFrame.new(0, (top - 0.09) / 2, 0), rimColor, parent))
				decoration(block("PadStep", size, where * CFrame.new(0, top / 2, 0), color, parent))
				along += stepLength + dice:NextInteger(1, 3) * 2
			end
		end
	end

	-- Spawn point (unseen): players appear on the road in front of their hive, looking out
	-- over their area.
	local spawnPad = Instance.new("SpawnLocation")
	spawnPad.Name = "SpawnPad"
	spawnPad.Size = Vector3.new(7, 0.4, 7)
	spawnPad.CFrame = at(0, 0.2, -8) * CFrame.Angles(0, math.pi, 0)
	spawnPad.Transparency = 1
	spawnPad.CanCollide = false
	spawnPad.CanQuery = false
	spawnPad.Anchored = true
	spawnPad.Neutral = true
	spawnPad.Duration = 0
	spawnPad.TopSurface = Enum.SurfaceType.Smooth
	spawnPad.Parent = plot

	-- Entrance arch with the owner's name, over the road where it enters the area
	local ownerSign = Instance.new("Model")
	ownerSign.Name = "OwnerSign"
	local archZ = PLOT_DEPTH / 2 - 4
	block("PostLeft", Vector3.new(2, 12, 2), at(-12, 6, archZ), C.Rim, ownerSign)
	block("PostRight", Vector3.new(2, 12, 2), at(12, 6, archZ), C.Rim, ownerSign)
	local sign = block("Sign", Vector3.new(28, 3.4, 2), at(0, 13.7, archZ), C.CellFill, ownerSign)
	billboard("NameTag", sign, 16, 2.4, 3, { { Name = "Label", Text = "Empty Hive", Height = 1 } })
	ownerSign.PrimaryPart = sign
	ownerSign.Parent = plot

	-- THE BEEHIVE'S SPOT: a patch of pale lawn at the end of the road.
	-- The hive itself is built by HiveService when the game runs (it changes with its level).
	local hiveZ = -34
	local HIVE_GROUND = 0.2
	local hiveGround = Instance.new("Model")
	hiveGround.Name = "HiveGround"
	groundPatch(at(0, 0, hiveZ), 30, 30, HIVE_GROUND, C.Meadow, C.GrassLight, hiveGround)
	hiveGround.Parent = plot

	-- THE ROAD from the garden to the hive. It widens a little in front of the hive, and a
	-- few stepping stones lead off it to each station.
	local road = Instance.new("Model")
	road.Name = "HomePath"
	local roadEnd = PLOT_DEPTH / 2
	local roadStart = hiveZ + 17
	steppedPath("Road", at(0, 0, (roadEnd + roadStart) / 2), 18, roadEnd - roadStart, road, dice)
	steppedPath("Forecourt", at(0, 0, roadStart + 6) * CFrame.Angles(0, math.pi / 2, 0), 12, 30, road, dice, 0.27)
	local function steppingStones(points)
		for number, point in points do
			local size = if number % 2 == 0 then Vector3.new(3, 0.24, 2.4) else Vector3.new(2.4, 0.24, 3)
			local turn = CFrame.Angles(0, math.rad(dice:NextInteger(-12, 12)), 0)
			decoration(block("SteppingStone", size, at(point[1], 0.12, point[2]) * turn, if number % 3 == 0 then C.Stone else C.Cream, road))
		end
	end
	steppingStones({ { 13, 4.4 }, { 16.5, 5.6 }, { 20, 6.9 } }) -- to the Queen
	steppingStones({ { 17.5, -13 }, { 21, -15.5 }, { 24.3, -17.6 } }) -- to the upgrade board
	steppingStones({ { -13, -4 }, { -17, -5 }, { -21, -5.5 } }) -- to the Honey Jars
	steppingStones({ { -13, 24 }, { -17, 25 }, { -21, 25.5 } }) -- to the Honey Market
	road.Parent = plot

	-- HiveAnchor: the middle of the hive's base. Its front (-Z) points at the plot entrance.
	local hiveAnchor = block("HiveAnchor", Vector3.new(1, 1, 1), at(0, HIVE_GROUND, hiveZ) * CFrame.Angles(0, math.pi, 0), C.White, plot)
	invisible(hiveAnchor).CanQuery = false
	billboard("HiveInfo", hiveAnchor, 12, 3.2, 7, {
		{ Name = "Title", Text = "Tiny Hive", Height = 0.55, Gold = true },
		{ Name = "Sub", Text = "", Height = 0.45 },
	}, 110)

	-- HiveSpot: the "Open Hive" button, just in front of the hive (HiveService moves it as the hive grows).
	local hiveSpot = invisible(block("HiveSpot", Vector3.new(1, 1, 1), at(0, HIVE_GROUND + 2.2, hiveZ + 4), C.White, plot))
	prompt(hiveSpot, "Hive", "Beehive", "Open Hive", 10)

	-- GROUND DRESSING: two clearings of lighter lawn (the honey yard on one side of the road,
	-- the Queen's corner on the other), darker patches, bare earth, flat stones and plants.
	-- Nothing is put on the road, the hive's lawn or a station.
	local dressing = Instance.new("Model")
	dressing.Name = "Dressing"
	local function clearing(pieces)
		for number, piece in pieces do
			decoration(block("Clearing", Vector3.new(piece[3], 0.05, piece[4]), at(piece[1], 0.025 + number * 0.008, piece[2]), C.GrassLight, dressing))
		end
	end
	clearing({ { -36, 10, 34, 62 }, { -44, 12, 30, 44 }, { -30, -6, 30, 22 }, { -34, 30, 38, 24 } }) -- the honey yard
	clearing({ { 42, 10, 44, 62 }, { 46, 16, 44, 40 }, { 30, -18, 26, 24 } }) -- the Queen's corner
	for number, patch in { { -50, -42, 18, 22 }, { 48, -42, 22, 20 }, { 18, 52, 16, 8 }, { -34, 52, 20, 8 }, { 52, 46, 14, 14 } } do
		decoration(block("Patch", Vector3.new(patch[3], 0.05, patch[4]), at(patch[1], 0.1 + number * 0.008, patch[2]), C.GrassDark, dressing))
		decoration(block("PatchStep", Vector3.new(4, 0.05, math.max(4, patch[4] - 8)), at(patch[1] + (if number % 2 == 0 then 1 else -1) * (patch[3] / 2 + 2), 0.1 + number * 0.008, patch[2]), C.GrassDark, dressing))
	end
	local KEEP_CLEAR = { { 40, 14, 28 }, { 30, -21, 11 }, { -34, -6, 19 }, { -36, 26, 18 }, { 0, -34, 22 } } -- stations and the hive: x, z, how wide
	local function clear(x, z, room)
		if math.abs(x) < 13 + room and z > -19 then
			return false -- the road
		end
		if math.abs(x) < 18 + room and z > -19 - room and z < -3 + room then
			return false -- where the road widens
		end
		for _, spot in KEEP_CLEAR do
			if (Vector2.new(x, z) - Vector2.new(spot[1], spot[2])).Magnitude < spot[3] + room then
				return false
			end
		end
		return true
	end
	local function spots(count, room, place)
		local made, tries = 0, 0
		while made < count and tries < 800 do
			tries += 1
			local x = dice:NextNumber(-PLOT_WIDTH / 2 + 4, PLOT_WIDTH / 2 - 4)
			local z = dice:NextNumber(-PLOT_DEPTH / 2 + 4, PLOT_DEPTH / 2 - 6)
			if clear(x, z, room) then
				made += 1
				place(x, z)
			end
		end
	end
	spots(5, 4, function(x, z) -- bare earth
		local width, depth = dice:NextInteger(2, 4) * 2, dice:NextInteger(2, 4) * 2
		decoration(block("Earth", Vector3.new(width, 0.22, depth), at(x, 0.11, z), C.Soil, dressing))
		decoration(block("Earth", Vector3.new(4, 0.18, 2), at(x + width / 2 + 1, 0.09, z + 1), C.SoilDark, dressing))
	end)
	spots(6, 4, function(x, z) -- flat stones
		local width, depth = dice:NextInteger(2, 3) * 2, dice:NextInteger(2, 3) * 2
		decoration(block("Slab", Vector3.new(width, 0.28, depth), at(x, 0.14, z), C.Stone, dressing))
		decoration(block("Slab", Vector3.new(2, 0.34, 4), at(x - width / 2 - 1, 0.17, z + 1), C.StoneDark, dressing))
	end)
	local function turned(x, z)
		return at(x, 0, z) * CFrame.Angles(0, dice:NextNumber(0, math.pi * 2), 0)
	end
	spots(5, 4, function(x, z)
		studded(decoration(prop("Bush", turned(x, z), dressing, dice:NextNumber(0.9, 1.3))))
	end)
	spots(3, 4, function(x, z)
		studded(decoration(prop("Rock", turned(x, z), dressing, dice:NextNumber(0.75, 1.15))))
	end)
	spots(6, 2, function(x, z)
		decoration(prop("Mushroom", turned(x, z), dressing, dice:NextNumber(0.8, 1.3)))
	end)
	spots(18, 1.5, function(x, z)
		decoration(prop("GrassTuft", turned(x, z), dressing, dice:NextNumber(0.9, 1.4))).Name = "Tuft"
	end)
	spots(16, 1.5, function(x, z)
		local spin = turned(x, z)
		local size = dice:NextNumber(0.95, 1.2)
		decoration(prop("FlowerStem", spin, dressing, size))
		decoration(prop("FlowerBlossom", spin, dressing, size, FLOWER_COLORS[dice:NextInteger(1, #FLOWER_COLORS)]))
	end)
	dressing.Parent = plot

	-- THE STANDS: every station stands on its own patch of earth beside the road and FACES
	-- the middle of the area. Looking from the garden towards the hive: the Honey Market (front)
	-- and the Honey Jars (back) share the left side; the Queen and, right next to her, the
	-- upgrade board are on the right.

	-- A stand's own position and direction: its front (+Z) points at the middle of the plot.
	local function standFrame(x, z)
		local spot = Vector3.new(x, 0, z)
		return origin * CFrame.lookAt(spot, spot + spot)
	end

	-- The ground a stand sits on: a patch of bare earth with a stepped edge, level with the
	-- paths. (edgeColor is not used any more: the old pads had a bright border.)
	local PAD_TOP = 0.2 -- how high that earth is above the grass
	local function standPad(frame, width, depth, _edgeColor, parent)
		groundPatch(frame, width, depth, PAD_TOP, C.Tan, C.Soil, parent)
	end

	-- A little block flower, and a tuft of grass, for dressing up a pad.
	local function tinyFlower(cframe, color, parent)
		decoration(prop("FlowerStem", cframe, parent, 0.62))
		decoration(prop("FlowerBlossom", cframe, parent, 0.62, color)).Name = "FlowerHead"
	end
	local function tuft(cframe, parent)
		decoration(prop("GrassTuft", cframe, parent, 0.5)).Name = "Tuft"
	end

	-- THE QUEEN'S ROLL AREA (right of the road, facing the middle of the area).
	-- The Queen floats over a round pedestal at the front, in the middle. Press E in front of
	-- her to roll (it is free): a bee hatches on every honeycomb stand the owner has (an egg,
	-- then a shadow, then the bee, with its price on the screen). Press E at a stand to buy
	-- its bee, or roll again. A new player has one stand, in the middle behind her. Stands
	-- bought later (the More Rolls upgrade) appear beside it and they all spread out along
	-- an arc; there is room for GameConfig.RollStandSpots. (BeeService decides what was
	-- rolled and puts the stands in place; WorldFX draws the show on each player's screen.)
	-- Beside her stands the sign that sells Auto Roll; it leaves once it has been bought.
	local rollFrame = standFrame(40, 14)
	local function qf(dx, dy, dz)
		return rollFrame * CFrame.new(dx, FLOOR + dy, dz)
	end
	local queen = Instance.new("Model")
	queen.Name = "Queen"
	standPad(rollFrame, 42, 30, C.Purple, queen)

	-- the Queen's pedestal (a Blender piece): a round purple rug, two round wooden steps
	-- with gold knobs round the rim, and a cushion she floats over. The gems between the
	-- knobs are their own glowing piece. An unseen round block is what players bump into.
	local qx, qz = 0, 3 -- she is in the middle of the pad, towards the front
	local pedestalFrame = qf(qx, PAD_TOP, qz)
	local pedestal = decoration(prop("Pedestal", pedestalFrame, queen))
	studTexture(pedestal, Enum.NormalId.Top) -- toy-brick studs on its flat tops only
	decoration(prop("PedestalGems", pedestalFrame, queen)).Name = "Gems"
	cylinder("PodiumSolid", 9.4, 1, qf(qx, PAD_TOP + 0.5, qz), C.Tan, queen).Transparency = 1
	-- Her name floats well above her, clear of the bees on the stands behind. (It hangs on
	-- its own unseen upright block: a sign's height is measured along the part it hangs on,
	-- and the round block above lies on its side.)
	local nameSpot = invisible(block("NameSpot", Vector3.new(1, 1, 1), qf(qx, PAD_TOP + 0.75, qz), C.White, queen))
	nameSpot.CanQuery = false
	billboard("NameTag", nameSpot, 9, 1.6, 10.4, { { Name = "Title", Text = "Queen Bee", Height = 1, Gold = true } }, 90)

	-- (she is kept small and low, so the bee hatching on the stand behind her shows over her head)
	local queenBee = BeeModelFactory.Create(C.BeeYellow, { Scale = 1.6, Outfit = { "RoyalGear", "Crown" } })
	queenBee.Name = "QueenBee"
	local queenPivot = qf(qx, PAD_TOP + 3.3, qz) * CFrame.Angles(0, math.pi, 0)
	queenBee:PivotTo(queenPivot)
	queenBee:SetAttribute("BasePivot", queenPivot)
	CollectionService:AddTag(queenBee, "BeeBob")
	queenBee.Parent = queen

	-- the leaning block sign in front of her pedestal
	local runny = Color3.fromRGB(255, 222, 70)
	local signCFrame = qf(qx, PAD_TOP + 1.35, qz + 5.9) * CFrame.Angles(math.rad(-22), 0, 0)
	decoration(plain(block("RollSignRim", Vector3.new(8.6, 3, 0.4), signCFrame * CFrame.new(0, 0, -0.3), Color3.fromRGB(200, 100, 30), queen)))
	local rollSign = plain(block("RollSign", Vector3.new(8, 2.4, 0.6), signCFrame, C.Path, queen))
	decoration(plain(block("RollSignTop", Vector3.new(8.6, 0.35, 0.9), signCFrame * CFrame.new(0, 1.55, -0.1), runny, queen)))
	for side = -1, 1, 2 do
		decoration(block("RollSignProp", Vector3.new(0.5, 1.5, 1.1), qf(qx + side * 3.6, PAD_TOP + 0.75, qz + 5.15), C.FencePost, queen))
	end
	local rollFace = surfaceGui("Face", rollSign, 40)
	local rollText = boardText(rollFace, "Text", "ROLL A BEE", C.White, UDim2.fromScale(0.04, 0.12), UDim2.fromScale(0.92, 0.76), 5)
	rollText.Font = Enum.Font.Arcade -- chunky pixel letters, like letters built from bricks

	-- (a short reach, so it never overlaps the Buy buttons on the stands behind her)
	local rollSpot = invisible(block("RollSpot", Vector3.new(1, 1, 1), qf(qx, PAD_TOP + 2.4, qz + 7.2), C.White, queen))
	prompt(rollSpot, "Roll", "It is free!", "Roll a Bee", 7)

	-- THE HONEYCOMB STANDS stand in an arc behind her, all turned a little towards her.
	-- Only stand 1 is built here. How the stands share the arc depends on how many there are:
	--   1 = in the middle           2 = one either side of the middle
	--   3 = middle + one each side  5 = the same three + one more at each end
	-- Every place is worked out here and written on the Stands folder as an attribute called
	-- "Spot_<how many stands>_<which stand>". The game reads those (see BeeService).
	local ARC_RADIUS = 49 -- the arc is a piece of a circle this big (a bigger number = a straighter row)
	local ARC_STEP = 9 -- degrees along the arc from one stand to the next
	local ARC_BACK = -10.5 -- how far behind the middle of the pad the middle stand is
	-- place 0 is the middle of the arc; 1 is one stand to the right, -0.5 half a stand left...
	local function arcSpot(place)
		local angle = math.rad(place * ARC_STEP)
		return rollFrame
			* CFrame.new(math.sin(angle) * ARC_RADIUS, FLOOR + PAD_TOP, ARC_BACK + (1 - math.cos(angle)) * ARC_RADIUS)
			* CFrame.Angles(0, -angle, 0)
	end
	-- the place of each stand when there are `count` stands
	local function placeOf(count, which)
		if count % 2 == 1 then
			-- an odd number: stand 1 in the middle, then right, left, right, left
			local steps = math.floor(which / 2)
			return if which % 2 == 0 then steps else -steps
		end
		-- an even number: nobody in the middle, half a place either side of it
		local steps = math.floor((which - 1) / 2) + 0.5
		return if which % 2 == 1 then -steps else steps
	end
	local stands = Instance.new("Folder")
	stands.Name = "Stands"
	for count = 1, math.clamp(GameConfig.RollStandSpots or 1, 1, 5) do
		for which = 1, count do
			stands:SetAttribute(string.format("Spot_%d_%d", count, which), arcSpot(placeOf(count, which)))
		end
	end
	rollStand(1, arcSpot(0), stands)
	stands.Parent = queen

	-- the Auto Roll sign: at the front, to one side of her, turned towards whoever walks up
	autoRollSign(rollFrame * CFrame.new(14.5, FLOOR + PAD_TOP, 9.5) * CFrame.Angles(0, math.rad(-20), 0), queen)

	-- tufts of grass and flowers round the edge
	tuft(qf(-19.4, PAD_TOP, -13.2), queen)
	tuft(qf(19.6, PAD_TOP, -12.4), queen)
	tuft(qf(-11.4, PAD_TOP, -13.8), queen)
	tuft(qf(-19.8, PAD_TOP, 4.6), queen)
	tinyFlower(qf(11.2, PAD_TOP, -14), FLOWER_COLORS[3], queen)
	tinyFlower(qf(-18.8, PAD_TOP, 12.8), FLOWER_COLORS[1], queen)
	tinyFlower(qf(19.4, PAD_TOP, 13.4), FLOWER_COLORS[4], queen)
	tinyFlower(qf(-3.6, PAD_TOP, -14.2), FLOWER_COLORS[5], queen)

	queen.PrimaryPart = rollSpot
	queen.Parent = plot

	-- THE UPGRADE BOARD: it stands right next to the Queen's roll area, on the hive's side,
	-- and faces the road. Press E in front of it to open the Upgrades window. The board shows
	-- one bright panel per upgrade. (It is still a model called Upgrades, with Board and
	-- UpgradeSpot inside, because the scripts look for those.)
	local shopFrame = standFrame(30, -21)
	local function shopAt(x, y, z)
		return shopFrame * CFrame.new(x, y, z)
	end
	local upgrades = Instance.new("Model")
	upgrades.Name = "Upgrades"
	local shopBoard = plain(block("Board", Vector3.new(12.4, 7, 0.5), shopAt(0, 7.6, 0), C.WoodDark, upgrades))
	block("BoardPostLeft", Vector3.new(0.8, 12, 0.8), shopAt(-6.6, 6, 0), C.Sand, upgrades)
	block("BoardPostRight", Vector3.new(0.8, 12, 0.8), shopAt(6.6, 6, 0), C.Sand, upgrades)
	block("BoardBeam", Vector3.new(16, 0.9, 1.2), shopAt(0, 11.55, 0), C.WoodDark, upgrades)
	decoration(plain(block("BoardPlaque", Vector3.new(5, 1.2, 0.8), shopAt(0, 12.6, 0), C.Path, upgrades)))
	for side = -1, 1, 2 do
		decoration(block("PostFoot", Vector3.new(2.4, 0.3, 2.4), shopAt(side * 6.6, 0.15, 0), C.Stone, upgrades))
	end
	local shopFace = surfaceGui("Face", shopBoard, 40)
	-- (an upgrade that needs Auto Roll first, like Roll Speed, is not on the board: it is
	-- only in the Upgrade Shop window, and only once Auto Roll has been bought. Neither is an
	-- upgrade marked WindowOnly, like Walk Speed: the board has room for four.)
	local boardUpgrades = {}
	for _, id in GameConfig.UpgradeOrder do
		local upgrade = GameConfig.Upgrades[id]
		if not (upgrade and (upgrade.NeedsAutoRoll or upgrade.WindowOnly)) then
			table.insert(boardUpgrades, id)
		end
	end
	local upgradeCount = #boardUpgrades
	for order, id in boardUpgrades do
		local column = (order - 1) % 2
		if order == upgradeCount and upgradeCount % 2 == 1 then
			column = 0.5 -- an odd one out sits in the middle of the bottom row
		end
		upgradePanel(shopFace, id, column, math.floor((order - 1) / 2))
	end

	local upgradeSpot = invisible(block("UpgradeSpot", Vector3.new(1, 1, 1), shopAt(0, 2.4, 3.5), C.White, upgrades))
	prompt(upgradeSpot, "Upgrades", "Upgrade Shop", "Upgrades", 8)
	billboard("NameTag", upgradeSpot, 12, 1.9, 12.4, { { Name = "Title", Text = "Upgrade Shop", Height = 1, Gold = true } }, 110)
	upgrades.PrimaryPart = shopBoard
	upgrades.Parent = plot

	-- THE TWO STANDS ON THE LEFT: the Honey Jars (back) and the Honey Market (front).

	-- A wooden crate with a honey-jar picture on the side that faces the plot, darker
	-- posts on its corners and a lighter lid on top.
	local CRATE_LID = 0.3 -- how thick a crate's lid is
	local cratePost = Color3.fromRGB(88, 50, 36)
	local function honeyCrate(cframe, parent)
		local crate = plain(block("Crate", Vector3.new(3, 3, 3), cframe, C.WoodDark, parent))
		local label = surfaceGui("Label", crate, 30)
		local panel = shape(label, "Panel", Color3.fromRGB(160, 100, 62), UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.76, 0.84), 0.06)
		outline(panel, 3)
		local jar = shape(panel, "Jar", C.Jar, UDim2.fromScale(0.5, 0.6), UDim2.fromScale(0.54, 0.52), 0.2)
		outline(jar, 3)
		shape(jar, "Shine", Color3.fromRGB(255, 228, 130), UDim2.fromScale(0.3, 0.42), UDim2.fromScale(0.18, 0.44), 0.5)
		local lid = shape(panel, "Lid", C.Lid, UDim2.fromScale(0.5, 0.27), UDim2.fromScale(0.64, 0.17), 0.3)
		outline(lid, 3)
		for _, corner in { Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(1, 1) } do
			decoration(block("CratePost", Vector3.new(0.4, 3, 0.4), cframe * CFrame.new(corner.X * 1.4, 0, corner.Y * 1.4), cratePost, parent))
		end
		block("CrateLid", Vector3.new(3.2, CRATE_LID, 3.2), cframe * CFrame.new(0, 1.5 + CRATE_LID / 2, 0), C.Wood, parent)
		return crate
	end

	-- HONEY JARS (back left): worker bees carry honey here from the hive. Crates of honey, a
	-- big honey pot, a slab of honeycomb, and a big jar-shaped sign that fills up with honey
	-- and shows how much is waiting (there is no limit). Press E to grab it all.
	-- (It is still called CollectStation in the scripts.)
	local jarsFrame = standFrame(-34, -6)
	local function jf(dx, dy, dz)
		return jarsFrame * CFrame.new(dx, FLOOR + dy, dz)
	end
	local station = Instance.new("Model")
	station.Name = "CollectStation"
	standPad(jarsFrame, 22, 16, Color3.fromRGB(255, 225, 50), station)

	-- a row of four honey crates at the front, with more stacked behind
	local tablePart = block("Table", Vector3.new(13.4, 0.3, 3.8), jf(0, PAD_TOP + 0.15, 2), C.Wood, station)
	for column = 0, 3 do
		honeyCrate(jf(-4.8 + column * 3.2, PAD_TOP + 1.8, 2), station)
	end
	honeyCrate(jf(-3.2, PAD_TOP + 1.5, -1.4), station)
	honeyCrate(jf(0, PAD_TOP + 1.5, -1.4), station)
	honeyCrate(jf(-1.6, PAD_TOP + 4.8, -1.4), station)
	-- chunks of honeycomb on the top crate: { x, z, size, colour }
	local stackTop = PAD_TOP + 6.3 + CRATE_LID
	for index, chunk in { { -2.3, -1.7, 1.3, C.Jar }, { -1, -0.9, 1, C.BeeYellow }, { -1.2, -2.1, 0.8, C.CellFill } } do
		decoration(block("Comb" .. index, Vector3.new(chunk[3], chunk[3], chunk[3]), jf(chunk[1], stackTop + chunk[3] / 2, chunk[2]), chunk[4], station))
	end

	-- blocks of earth with grass on top, behind and beside the crates: { x, z, height }
	for _, mound in { { -8, -4.6, 4 }, { -5, -5.6, 6 }, { 7.6, -4.4, 5 }, { 4.6, -5.4, 3.4 }, { 8.6, -1, 2.4 } } do
		block("Earth", Vector3.new(3.4, mound[3], 3.4), jf(mound[1], PAD_TOP + mound[3] / 2, mound[2]), C.Soil, station)
		block("Turf", Vector3.new(3.7, 0.6, 3.7), jf(mound[1], PAD_TOP + mound[3] + 0.3, mound[2]), C.Grass, station)
	end
	-- little flowers and tufts of grass on the turf: { x, z, height of the earth under it }
	for index, flower in { { -8.7, -3.9, 4 }, { -5.5, -5, 6 }, { 4.9, -4.5, 3.4 } } do
		local top = PAD_TOP + flower[3] + 0.6
		decoration(block("FlowerStem", Vector3.new(0.3, 1.1, 0.3), jf(flower[1], top + 0.55, flower[2]), C.Stem, station))
		decoration(block("FlowerHead", Vector3.new(1.1, 0.45, 1.1), jf(flower[1], top + 1.3, flower[2]), FLOWER_COLORS[({ 1, 4, 3 })[index]], station))
		decoration(block("FlowerMiddle", Vector3.new(0.5, 0.6, 0.5), jf(flower[1], top + 1.35, flower[2]), C.BeeYellow, station))
	end
	for _, tuft in { { -7.1, -5.4, 4 }, { -4.2, -6.3, 6 }, { 8.9, -3.2, 5 }, { 9.8, -0.1, 2.4 } } do
		local top = PAD_TOP + tuft[3] + 0.6
		decoration(block("Tuft", Vector3.new(0.45, 0.9, 0.45), jf(tuft[1], top + 0.45, tuft[2]), C.Tuft, station))
		decoration(block("Tuft", Vector3.new(0.45, 0.6, 0.45), jf(tuft[1] + 0.5, top + 0.3, tuft[2] + 0.3), C.Tuft, station))
	end
	-- blocks of honey on the earth, one of them running down the front
	decoration(block("HoneyBlock", Vector3.new(1.6, 1.2, 1.6), jf(7.6, PAD_TOP + 6.2, -4.4), C.Jar, station))
	decoration(block("HoneyBlock", Vector3.new(1.3, 1, 1.3), jf(8.6, PAD_TOP + 3.5, -1), C.BeeYellow, station))
	decoration(plain(block("HoneyOoze", Vector3.new(1.6, 0.14, 1.3), jf(7.6, PAD_TOP + 5.67, -3.05), C.Jar, station)))
	decoration(plain(block("HoneyDrip", Vector3.new(0.7, 1.9, 0.3), jf(8, PAD_TOP + 4.8, -2.45), C.Jar, station)))
	decoration(plain(block("HoneyDrip", Vector3.new(0.5, 0.9, 0.3), jf(7.2, PAD_TOP + 5.3, -2.45), C.Jar, station)))

	-- a big pot of honey with a dipper in it, and a puddle where it has run over
	local potX, potZ = -8.7, 4
	block("PotFoot", Vector3.new(3, 0.5, 3), jf(potX, PAD_TOP + 0.25, potZ), C.CellRim, station)
	block("PotBody", Vector3.new(3.8, 2.6, 3.8), jf(potX, PAD_TOP + 1.8, potZ), C.Jar, station)
	block("PotNeck", Vector3.new(3, 0.6, 3), jf(potX, PAD_TOP + 3.4, potZ), C.CellRim, station)
	block("PotRim", Vector3.new(3.5, 0.5, 3.5), jf(potX, PAD_TOP + 3.95, potZ), C.Lid, station)
	decoration(plain(block("PotHoney", Vector3.new(2.8, 0.3, 2.8), jf(potX, PAD_TOP + 4.2, potZ), C.BeeYellow, station)))
	decoration(plain(block("PotDrip", Vector3.new(0.7, 1.5, 0.3), jf(potX + 1.35, PAD_TOP + 3.45, potZ + 1.95), C.BeeYellow, station)))
	decoration(plain(block("PotDrip", Vector3.new(0.5, 0.8, 0.3), jf(potX - 1.4, PAD_TOP + 3.8, potZ + 1.95), C.BeeYellow, station)))
	local potLabel = decoration(plain(block("PotLabel", Vector3.new(2.6, 1.3, 0.2), jf(potX, PAD_TOP + 1.8, potZ + 1.95), C.Lid, station)))
	boardText(surfaceGui("Face", potLabel, 40), "Text", "HONEY", Color3.fromRGB(255, 190, 30), UDim2.fromScale(0.06, 0.1), UDim2.fromScale(0.88, 0.8), 3)
	local dipper = jf(potX - 0.3, PAD_TOP + 5.3, potZ - 0.2) * CFrame.Angles(0, 0, math.rad(16))
	decoration(block("DipperStick", Vector3.new(0.35, 3, 0.35), dipper, C.WoodDark, station))
	decoration(block("DipperKnob", Vector3.new(0.8, 0.8, 0.8), dipper * CFrame.new(0, 1.7, 0), C.Wood, station))
	for index, puddle in { { 1.4, 2.9, 3, 1.5 }, { 2.7, 3.2, 1.6, 1.3 }, { 0.2, 3.4, 1.4, 1.1 } } do
		decoration(plain(block("Puddle" .. index, Vector3.new(puddle[3], 0.1, puddle[4]), jf(potX + puddle[1], PAD_TOP + 0.05, potZ + puddle[2]), C.BeeYellow, station)))
	end

	-- a slab of honeycomb leaning on the earth, with loose chunks beside it
	local combFrame = jf(8.8, PAD_TOP + 1.8, 2.3) * CFrame.Angles(math.rad(-12), 0, 0)
	local honeycomb = plain(block("Honeycomb", Vector3.new(4, 3.6, 1.2), combFrame, C.BeeYellow, station))
	local combFace = surfaceGui("Cells", honeycomb, 30)
	local cellNumber = 0
	for row = 0, 2 do
		for column = 0, (if row == 1 then 1 else 2) do
			cellNumber += 1
			local x = (if row == 1 then 0.35 else 0.2) + column * 0.3
			local color = if cellNumber == 6 then C.CellRim elseif cellNumber % 3 == 2 then Color3.fromRGB(255, 228, 100) else C.CellFill
			local cell = shape(combFace, "Cell" .. cellNumber, color, UDim2.fromScale(x, 0.19 + row * 0.31), UDim2.fromScale(0.25, 0.27), 0.5)
			outline(cell, 3, Color3.fromRGB(190, 100, 15))
		end
	end
	decoration(block("CombCap", Vector3.new(4.3, 0.45, 1.5), combFrame * CFrame.new(0, 2, 0), C.CellRim, station))
	decoration(plain(block("CombDrip", Vector3.new(0.7, 1.3, 0.3), combFrame * CFrame.new(1.35, 1.15, 0.7), C.Jar, station)))
	decoration(block("CombChunk", Vector3.new(1.3, 1.3, 1.3), jf(9.6, PAD_TOP + 0.65, 5) * CFrame.Angles(0, math.rad(20), 0), C.Jar, station))
	decoration(block("CombChunk", Vector3.new(1, 1, 1), jf(7.6, PAD_TOP + 0.5, 5.6) * CFrame.Angles(0, math.rad(-25), 0), C.BeeYellow, station))

	-- the big sign: shaped like a honey jar. The honey inside rises as more honey arrives,
	-- and the amount of honey waiting is written across it.
	local signFrame = jf(0, 12.4, -4.2)
	block("SignBase", Vector3.new(2.6, 0.7, 2.6), jf(0, PAD_TOP + 0.35, -4.5), C.FencePost, station)
	block("SignPost", Vector3.new(1.2, 9, 1.2), jf(0, 4.5, -4.5), C.FencePost, station)
	decoration(plain(block("SignEdge", Vector3.new(10.6, 7.6, 0.8), signFrame, C.Jar, station)))
	for _, corner in { Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(1, 1) } do
		-- cut the corners square-step style, like a jar's rounded shoulders
		decoration(plain(block("SignCorner", Vector3.new(1, 1, 0.9), signFrame * CFrame.new(corner.X * 4.8, corner.Y * 3.3, 0), C.Rim, station)))
	end
	local signPart = decoration(plain(block("Sign", Vector3.new(8.8, 5.8, 1), signFrame, Color3.fromRGB(238, 246, 250), station)))
	decoration(block("SignNeck", Vector3.new(7.2, 0.9, 0.8), signFrame * CFrame.new(0, 4.25, 0), C.Jar, station))
	decoration(block("SignLid", Vector3.new(8.6, 1.4, 1), signFrame * CFrame.new(0, 5.4, 0), C.Lid, station))
	decoration(plain(block("SignLidBand", Vector3.new(8.9, 0.4, 1.2), signFrame * CFrame.new(0, 5.4, 0), Color3.fromRGB(226, 208, 176), station)))
	decoration(block("SignLidTop", Vector3.new(5.6, 0.5, 0.9), signFrame * CFrame.new(0, 6.35, 0), C.Lid, station))
	-- honey running out from under the lid and down the front
	local runny = Color3.fromRGB(255, 222, 70)
	decoration(plain(block("SignHoney", Vector3.new(9.4, 0.5, 0.3), signFrame * CFrame.new(0, 3.55, 0.55), runny, station)))
	for _, drip in { { -3.9, 1.7 }, { -2.9, 0.8 }, { 3.2, 1.2 }, { 4.1, 0.6 } } do
		decoration(plain(block("SignDrip", Vector3.new(0.8, drip[2], 0.3), signFrame * CFrame.new(drip[1], 3.3 - drip[2] / 2, 0.55), runny, station)))
	end

	-- the front of the sign: honey (the game makes it taller the more is waiting), a shine,
	-- and the number
	local signFace = surfaceGui("Face", signPart, 40)
	local honey = Instance.new("Frame")
	honey.Name = "Honey"
	honey.AnchorPoint = Vector2.new(0, 1)
	honey.Position = UDim2.fromScale(0, 1)
	honey.Size = UDim2.fromScale(1, 0.14)
	honey.BackgroundColor3 = C.White
	honey.BorderSizePixel = 0
	honey.Parent = signFace
	local honeyFade = Instance.new("UIGradient")
	honeyFade.Rotation = 90
	honeyFade.Color = ColorSequence.new(Color3.fromRGB(255, 205, 60), Color3.fromRGB(255, 150, 20))
	honeyFade.Parent = honey
	local honeyTop = Instance.new("Frame")
	honeyTop.Name = "Surface"
	honeyTop.BackgroundColor3 = Color3.fromRGB(255, 234, 130)
	honeyTop.BorderSizePixel = 0
	honeyTop.Size = UDim2.new(1, 0, 0, 9)
	honeyTop.ZIndex = 2
	honeyTop.Parent = honey
	for _, spot in { { 0.5, 0.44 }, { 0.83, 0.09 } } do
		local shine = shape(signFace, "Shine", C.White, UDim2.fromScale(0.075, spot[1]), UDim2.fromScale(0.04, spot[2]), 0.5)
		shine.BackgroundTransparency = 0.3
		shine.ZIndex = 3
	end
	local amount = boardText(signFace, "Amount", "0", C.White, UDim2.fromScale(0.12, 0.19), UDim2.fromScale(0.76, 0.62), 7)
	amount.ZIndex = 4

	-- twelve chunky jars that appear as honey arrives: six on the crates, six on the floor in front
	local jars = Instance.new("Folder")
	jars.Name = "Jars"
	local onCrates = { -4.8, -2.4, -0.8, 0.8, 2.4, 4.8 }
	local order = 0
	for row = 0, 1 do
		for column = 0, 5 do
			order += 1
			local x = if row == 0 then onCrates[column + 1] else -4.75 + column * 1.9
			local y = if row == 0 then PAD_TOP + 3.3 + CRATE_LID + 0.8 else PAD_TOP + 0.8
			local z = if row == 0 then 2 else 5.6
			local jar = plain(decoration(block("Jar" .. order, Vector3.new(1.4, 1.6, 1.4), jf(x, y, z), C.Jar, jars)))
			jar.Transparency = 1
			jar:SetAttribute("Order", order)
			-- the game shows and hides every part inside a jar together with the jar
			local lid = plain(decoration(block("Lid", Vector3.new(1.6, 0.35, 1.6), jf(x, y + 0.975, z), C.Lid, jar)))
			lid.Transparency = 1
			local label = plain(decoration(block("Label", Vector3.new(1, 0.7, 0.12), jf(x, y - 0.1, z + 0.72), C.Lid, jar)))
			label.Transparency = 1
		end
	end
	jars.Parent = station

	-- where the worker bees drop the honey off
	local dropSpot = invisible(block("DropSpot", Vector3.new(1, 1, 1), jf(0, 8, 2), C.White, station))
	dropSpot.CanQuery = false

	prompt(tablePart, "Collect", "Honey Jars", "Grab Jars", 12)
	station.PrimaryPart = tablePart
	station.Parent = plot

	-- HONEY MARKET (front left): a shopkeeper bee behind a table, with gold, crates and a
	-- shelf of honey. Press E at the table to sell your jars.
	local marketFrame = standFrame(-36, 26)
	local function mf(dx, dy, dz)
		return marketFrame * CFrame.new(dx, FLOOR + dy, dz)
	end
	local market = Instance.new("Model")
	market.Name = "Market"
	standPad(marketFrame, 20, 14, Color3.fromRGB(170, 235, 90), market)

	-- the table (it is the part you press E at, so it is still called Counter)
	local coral = Color3.fromRGB(238, 124, 92)
	for _, leg in { Vector2.new(-3.6, -1.6), Vector2.new(3.6, -1.6), Vector2.new(-3.6, 1.6), Vector2.new(3.6, 1.6) } do
		block("TableLeg", Vector3.new(0.8, 2, 0.8), mf(leg.X, PAD_TOP + 1, 1.5 + leg.Y), coral, market)
	end
	block("TableFrame", Vector3.new(8.8, 0.5, 4.6), mf(0, PAD_TOP + 2.05, 1.5), coral, market)
	local counter = block("Counter", Vector3.new(8.2, 0.4, 4), mf(0, PAD_TOP + 2.5, 1.5), Color3.fromRGB(205, 236, 216), market)
	for index, coin in { Vector2.new(-2.6, 0.4), Vector2.new(-1.7, -0.6), Vector2.new(1.2, 0.7), Vector2.new(2.4, -0.2), Vector2.new(0.2, -0.5) } do
		decoration(block("Gold" .. index, Vector3.new(0.7, 0.3, 0.7), mf(coin.X, PAD_TOP + 2.85, 1.5 + coin.Y), C.Gold, market))
	end

	-- a pile of gold blocks beside the table
	for index, gold in { { 6.2, 0.6, 1.2 }, { 7.6, 0.6, 0.4 }, { 6.8, 0.6, 2.4 }, { 8.2, 0.6, 1.9 }, { 6.9, 1.8, 1.4 }, { 7.9, 1.8, 1 }, { 5.6, 0.45, 3.4 } } do
		local size = if gold[2] > 1 then 1.1 else 1.2
		decoration(block("GoldBlock" .. index, Vector3.new(size, size, size), mf(gold[1], PAD_TOP + gold[2], gold[3]), if index % 2 == 0 then C.BeeYellow else C.Gold, market))
	end

	-- dark crates with orange panels on the other side
	local darkWood = Color3.fromRGB(46, 40, 48)
	for index, crate in { { -7.2, 1.4, 0.4 }, { -7.9, 1.4, -2.6 }, { -7.5, 4.2, -1 } } do
		block("Crate" .. index, Vector3.new(2.8, 2.8, 2.8), mf(crate[1], PAD_TOP + crate[2], crate[3]), darkWood, market)
		decoration(plain(block("CratePanel", Vector3.new(2.1, 2.1, 0.2), mf(crate[1], PAD_TOP + crate[2], crate[3] + 1.45), C.Path, market)))
	end

	-- a shelf of honey behind the table
	local cream = Color3.fromRGB(236, 222, 196)
	block("ShelfBack", Vector3.new(6.4, 5.6, 0.5), mf(4.4, PAD_TOP + 2.8, -5.4), cream, market)
	for _, side in { -3.2, 3.2 } do
		block("ShelfSide", Vector3.new(0.5, 5.6, 1.8), mf(4.4 + side, PAD_TOP + 2.8, -4.5), cream, market)
	end
	for _, height in { 0.25, 2.1, 3.9, 5.5 } do
		block("ShelfPlank", Vector3.new(6.4, 0.4, 1.8), mf(4.4, PAD_TOP + height, -4.5), cream, market)
	end
	for index, jarSpot in { { 2.6, 0.95 }, { 4.4, 0.95 }, { 6.2, 0.95 }, { 3.4, 2.8 }, { 5.4, 2.8 }, { 4.4, 4.6 } } do
		decoration(block("ShelfHoney" .. index, Vector3.new(1.1, 1, 1.1), mf(jarSpot[1], PAD_TOP + jarSpot[2], -4.4), if index % 2 == 0 then C.Jar else C.BeeYellow, market))
	end

	-- the shopkeeper: a bee in a top hat, behind the table, facing the plot
	local shopBee = BeeModelFactory.Create(Color3.fromRGB(255, 190, 60), { Scale = 1.5 })
	shopBee.Name = "ShopBee"
	local hatColor = Color3.fromRGB(44, 38, 50)
	decoration(block("HatBrim", Vector3.new(2.7, 0.22, 2.7), CFrame.new(0, 1.38, -2.25), hatColor, shopBee))
	decoration(block("HatTop", Vector3.new(1.7, 1.1, 1.7), CFrame.new(0, 2.02, -2.25), hatColor, shopBee))
	decoration(block("HatBand", Vector3.new(1.78, 0.28, 1.78), CFrame.new(0, 1.66, -2.25), C.Gold, shopBee))
	local shopPivot = mf(0, PAD_TOP + 3.6, -2.4) * CFrame.Angles(0, math.pi, 0)
	shopBee:PivotTo(shopPivot)
	shopBee:SetAttribute("BasePivot", shopPivot)
	CollectionService:AddTag(shopBee, "BeeBob")
	shopBee.Parent = market

	prompt(counter, "Sell", "Honey Market", "Sell Jars", 12)
	billboard("Info", counter, 12, 3, 8.6, {
		{ Name = "Title", Text = "Honey Market", Height = 0.55, Gold = true },
		{ Name = "Sub", Text = "Sell your jars here!", Height = 0.45 },
	}, 80)
	market.PrimaryPart = counter
	market.Parent = plot

	PlotBuilder.AddStuds(plot)
	plot.Parent = parent
	return plot
end

-- THE FLOWER GARDEN (middle of the map, shared by everyone) ---------------------------

-- A round floor made of straight strips, so its edge is stepped like pixels.
-- centre (optional) = where its middle is; without it, the middle of the map. strip
-- (optional) = how wide each strip is: narrower strips make a smoother circle.
local function steppedDisc(namePrefix, radius, thickness, y, color, parent, centre, strip)
	local middlePart = nil
	strip = strip or 4
	local cx, cz = if centre then centre.X else 0, if centre then centre.Z else 0
	for z = -radius + strip / 2, radius - strip / 2, strip do
		local halfWidth = math.floor(math.sqrt(radius * radius - z * z) / 2 + 0.5) * 2
		if halfWidth >= 2 then
			local part = block(namePrefix, Vector3.new(halfWidth * 2, thickness, strip), CFrame.new(cx, y, cz + z), color, parent)
			if math.abs(z) <= strip / 2 then
				middlePart = part
			end
		end
	end
	return middlePart
end

-- THE FLOWER GARDEN (rebuilt 11 Oct 2026). A giant sunflower on a mound in the middle, beds of
-- flowers that go from knee-high at the fence to giants near the middle, stepping stones from
-- every gate, and a pond with lily pads. Where everything stands is written in GardenLayout
-- (next to this tool), which blender/garden.py makes together with the pieces themselves.

local SWAY_TAG = "GardenSway" -- the player's screen makes everything with this tag sway gently (WorldFX)

-- Marks a model as swaying. foot = the point on the ground it bends from, tall = its height
-- in studs (tall things bend less, so their heads never swing far).
local function sways(model, foot, tall)
	model:SetAttribute("Foot", foot)
	model:SetAttribute("Tall", tall)
	CollectionService:AddTag(model, SWAY_TAG)
end

-- One garden flower. kind = its entry in GardenLayout.Kinds. BeeSpot is where a bee hovers over it.
local function gardenPlant(name, kind, where, scale, color, parent)
	local model = Instance.new("Model")
	model.Name = name
	local tall = kind.Tall * scale
	local giant = tall >= 10 -- the giants get the stud pattern, like the trees
	local body = decoration(prop(kind.Body, where, model, scale))
	body.Name = "Body"
	if giant then
		studded(body)
	end
	if kind.Petals then
		-- the petals are a white piece that takes this flower's colour
		local petals = decoration(prop(kind.Petals, where, model, scale, color))
		petals.Name = "Petals"
		if giant then
			studded(petals)
		end
	end
	model.PrimaryPart = body
	model:SetAttribute("BeeSpot", where:PointToWorldSpace(Vector3.new(kind.Top[1], kind.Top[2], kind.Top[3]) * scale))
	sways(model, where, tall)
	model.Parent = parent
	return model
end

function PlotBuilder.BuildGarden()
	local layout = require(game:GetService("ServerStorage").BeeEmpireDev.GardenLayout)
	for _, name in { "DaisyBody", "TulipPetals", "Sunflower", "SunGiantStem", "SunGiantHeadA", "LilyPad", "Reeds", "Frog" } do
		assert(PropMeshes:FindFirstChild(name), "A garden piece is missing from PropMeshes (import BeeEmpire-garden.fbx first): " .. name)
	end
	for _, oldName in { "QueenPlaza", "FlowerGarden" } do
		local old = workspace:FindFirstChild(oldName)
		if old then
			old:Destroy()
		end
	end

	local GROUND = 0.5 -- the top of the meadow
	local WATER = Color3.fromRGB(80, 170, 255)
	local WATER_DEEP = Color3.fromRGB(60, 140, 235)
	local function turnedAt(x, y, z, degrees)
		return CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(degrees), 0)
	end

	local garden = Instance.new("Model")
	garden.Name = "FlowerGarden"

	steppedDisc("SoilRim", GARDEN_RADIUS + 4, 0.3, 0.15, C.Soil, garden)
	local ground = steppedDisc("Ground", GARDEN_RADIUS, 0.5, 0.25, C.Meadow, garden)
	garden.PrimaryPart = ground

	-- the flower beds: flat patches of soil (no bump to walk over)
	local beds = Instance.new("Model")
	beds.Name = "Beds"
	for _, bed in layout.Beds do
		local x, z, turn, long, wide = table.unpack(bed)
		decoration(block("Bed", Vector3.new(wide, 0.16, long), turnedAt(x, GROUND + 0.08, z, -turn), C.Soil, beds))
	end
	beds.Parent = garden

	-- stepping stones from every gate to the ring round the mound
	local stones = Instance.new("Model")
	stones.Name = "Stones"
	for _, stone in layout.Stones do
		local x, z, turn, size = table.unpack(stone)
		decoration(block("Stone", Vector3.new(size, 0.3, size), turnedAt(x, GROUND + 0.15, z, turn), C.Cream, stones))
	end
	stones.Parent = garden

	-- the mound, and the giant sunflower growing out of it (its four pieces all stand on the same spot)
	steppedDisc("Mound", layout.Mound, 0.7, GROUND + 0.35, C.Soil, garden, nil, 2)
	steppedDisc("MoundTop", layout.Mound - 2.5, 0.6, GROUND + 1.0, C.SoilDark, garden, nil, 2)
	local giantAt = turnedAt(0, GROUND + 1.25, 0, layout.GiantTurn)
	local giant = Instance.new("Model")
	giant.Name = "GiantSunflower"
	for _, name in { "SunGiantStem", "SunGiantHeadA", "SunGiantHeadB", "SunGiantHeadC" } do
		studded(decoration(prop(name, giantAt, giant))).Name = name
	end
	giant.PrimaryPart = giant.SunGiantStem
	sways(giant, giantAt, 36)
	giant.Parent = garden
	-- (the plant itself is only looks; this unseen block is what players bump into)
	local trunk = block("Trunk", Vector3.new(2.8, 14, 2.8), CFrame.new(0.3, GROUND + 8.2, 0), C.White, garden)
	trunk.Transparency = 1
	trunk.CanTouch = false
	trunk.CanQuery = false

	-- the flowers
	local flowers = Instance.new("Folder")
	flowers.Name = "Flowers"
	for index, entry in layout.Flowers do
		local kindName, x, z, scale, turn, r, g, b = table.unpack(entry)
		gardenPlant(string.format("Flower%03d", index), layout.Kinds[kindName], turnedAt(x, GROUND + 0.1, z, turn), scale, Color3.fromRGB(r, g, b), flowers)
	end
	-- (bees also visit the giant sunflower's three faces: these hold only the spots)
	for index, spot in layout.GiantSpots do
		local holder = Instance.new("Model")
		holder.Name = "FlowerGiant" .. index
		holder:SetAttribute("BeeSpot", giantAt:PointToWorldSpace(Vector3.new(spot[1], spot[2], spot[3])))
		holder.Parent = flowers
	end
	flowers.Parent = garden

	-- the pond: smooth blue water (no studs, so it reads as water), a rim of chunky stones,
	-- lily pads, a frog and reeds
	local pond = Instance.new("Model")
	pond.Name = "Pond"
	local px, pz, pondRadius = layout.Pond.X, layout.Pond.Z, layout.Pond.Radius
	local pondMiddle = Vector3.new(px, 0, pz)
	steppedDisc("Water", pondRadius, 0.3, GROUND + 0.15, WATER, pond, pondMiddle, 2)
	steppedDisc("WaterDeep", pondRadius - 4, 0.3, GROUND + 0.17, WATER_DEEP, pond, pondMiddle, 2)
	for _, part in pond:GetChildren() do
		plain(decoration(part))
		part.Transparency = 0.1
	end
	local rimLook = Random.new(5)
	local rimStones = 22
	for step = 1, rimStones do
		local angle = step / rimStones * math.pi * 2 + rimLook:NextNumber(-0.05, 0.05)
		local out = pondRadius + rimLook:NextNumber(0.3, 1.0)
		local size = Vector3.new(rimLook:NextNumber(2.7, 3.7), rimLook:NextNumber(0.7, 1.3), rimLook:NextNumber(1.8, 2.6))
		local at = Vector3.new(px + math.cos(angle) * out, GROUND + size.Y / 2 - 0.05, pz + math.sin(angle) * out)
		-- (the long side of each stone lies along the water's edge)
		local turn = CFrame.Angles(0, -angle - math.pi / 2 + rimLook:NextNumber(-0.2, 0.2), 0)
		block("RimStone", size, CFrame.new(at) * turn, if step % 3 == 0 then C.StoneDark else C.Stone, pond)
	end
	for _, pad in layout.Pads do
		local x, z, scale, turn, bloom, r, g, b = table.unpack(pad)
		local where = turnedAt(x, GROUND + 0.3, z, turn)
		decoration(prop(if bloom then "LilyBloom" else "LilyPad", where, pond, scale)).Name = "LilyPad"
		if bloom then
			decoration(prop("LilyPetals", where, pond, scale, Color3.fromRGB(r, g, b))).Name = "WaterLily"
		end
	end
	local frog = layout.Frog
	decoration(prop("Frog", turnedAt(frog.X, GROUND + 0.3 + 0.35, frog.Z, frog.Turn), pond, frog.Scale)).Name = "Frog"
	for _, reed in layout.Reeds do
		local x, z, scale, turn = table.unpack(reed)
		local where = turnedAt(x, GROUND, z, turn)
		local model = Instance.new("Model")
		model.Name = "Reeds"
		model.PrimaryPart = decoration(prop("Reeds", where, model, scale))
		sways(model, where, 6.6 * scale)
		model.Parent = pond
	end
	pond.Parent = garden

	-- small things between the beds: bushes by the fence, mushrooms, grass and little lawn flowers
	local extras = Instance.new("Model")
	extras.Name = "Extras"
	for _, extra in layout.Extras do
		local kindName, x, z, scale, turn, r, g, b = table.unpack(extra)
		local where = turnedAt(x, GROUND, z, turn)
		if kindName == "LawnFlower" then
			local model = Instance.new("Model")
			model.Name = "LawnFlower"
			model.PrimaryPart = decoration(prop("FlowerStem", where, model, scale))
			decoration(prop("FlowerBlossom", where, model, scale, Color3.fromRGB(r, g, b)))
			sways(model, where, 2.5 * scale)
			model.Parent = extras
		elseif kindName == "Bush" or kindName == "Rock" then
			studded(decoration(prop(kindName, where, extras, scale)))
		else
			decoration(prop(kindName, where, extras, scale))
		end
	end
	extras.Parent = garden

	-- a wooden fence round the garden, with a gap where each path arrives
	local fence = Instance.new("Model")
	fence.Name = "Fence"
	local fenceRadius = GARDEN_RADIUS + 5.5
	local stepDegrees = 12
	local function fencePoint(degrees)
		return Vector3.new(math.cos(math.rad(degrees)) * fenceRadius, 0, math.sin(math.rad(degrees)) * fenceRadius)
	end
	for degrees = 0, 360 - stepDegrees, stepDegrees do
		local here = fencePoint(degrees)
		local nextPoint = fencePoint(degrees + stepDegrees)
		local post = prop("FencePost", CFrame.lookAt(here, Vector3.zero), fence)
		post.Name = "Post"
		post.CanCollide = true
		local middle = degrees + stepDegrees / 2
		local isGate = (middle - 30) % 60 == 0 -- the paths arrive at 30, 90, 150... degrees
		if not isGate then
			local length = (nextPoint - here).Magnitude
			for _, height in { 1.3, 2.4 } do
				-- the rail piece is one stud long: stretch it from post to post
				local rail = decoration(prop(
					"FenceRail",
					CFrame.lookAt((here + nextPoint) / 2 + Vector3.new(0, height, 0), nextPoint + Vector3.new(0, height, 0)),
					fence
				))
				rail.Name = "Rail"
				rail.Size = Vector3.new(0.4, 0.45, length)
			end
		end
	end
	fence.Parent = garden

	-- the name floats above the giant sunflower
	local signPart = invisible(block("SignPart", Vector3.new(1, 1, 1), CFrame.new(0, 44, 0), C.White, garden))
	signPart.CanQuery = false
	billboard("NameTag", signPart, 22, 6.4, 8, {
		{ Name = "Title", Text = "Flower Garden", Height = 0.62, Gold = true },
		{ Name = "Sub", Text = "Bees collect nectar here!", Height = 0.38 },
	}, 260)

	PlotBuilder.AddStuds(garden)
	garden.Parent = workspace
	return garden
end

-- DECORATION ----------------------------------------------------------------------

-- A small flower for the lawns (the blossom piece takes the flower's colour).
local function flower(position, color, parent)
	local model = Instance.new("Model")
	model.Name = "Flower"
	local spin = CFrame.new(position) * CFrame.Angles(0, look:NextNumber(0, math.pi * 2), 0)
	local size = look:NextNumber(0.95, 1.2)
	decoration(prop("FlowerStem", spin, model, size)).Name = "Stem"
	decoration(prop("FlowerBlossom", spin, model, size, color)).Name = "Blossom"
	model.Parent = parent
end

-- A clump of tall grass.
local function tuft(position, random, parent)
	-- (These numbers used to pick the old block sticks. They are still drawn, in the same
	-- order, so everything planted after this clump stays exactly where it was.)
	local sticks = random:NextInteger(2, 4)
	local tallest, drift = 0, Vector3.zero
	for _ = 1, sticks do
		tallest = math.max(tallest, random:NextNumber(1, 2.2))
		drift += Vector3.new(random:NextNumber(-0.6, 0.6), 0, random:NextNumber(-0.6, 0.6))
	end
	local spin = CFrame.new(position + drift / sticks) * CFrame.Angles(0, look:NextNumber(0, math.pi * 2), 0)
	decoration(prop("GrassTuft", spin, parent, 0.55 + tallest * 0.3 + (sticks - 2) * 0.08)).Name = "Tuft"
end

-- A tree. Its leaves and trunk are one studded piece; an invisible block where the trunk is
-- makes players bump into it.
local function tree(position, parent)
	local model = Instance.new("Model")
	model.Name = "Tree"
	local size = look:NextNumber(0.92, 1.12)
	local spin = CFrame.new(position) * CFrame.Angles(0, math.rad(look:NextInteger(0, 3) * 90), 0)
	studded(decoration(prop("Tree", spin, model, size))).Name = "Leaves"
	local trunk = plain(block("Trunk", Vector3.new(3, 10, 3) * size, CFrame.new(position + Vector3.new(0, 5 * size, 0)), C.Trunk, model))
	trunk.Transparency = 1
	trunk.CanQuery = false
	model.Parent = parent
end

-- True if a spot is on the garden, a plot or a path (so we do not plant things there).
local function isBuiltOn(x, z)
	local point = Vector3.new(x, 0, z)
	if point.Magnitude < GARDEN_RADIUS + 19 then -- the garden and the ring road round it
		return true
	end
	for _, origin in PLOT_ORIGINS do
		local localPoint = origin:PointToObjectSpace(point)
		if math.abs(localPoint.X) < PLOT_WIDTH / 2 + 4 and math.abs(localPoint.Z) < PLOT_DEPTH / 2 + 4 then
			return true
		end
		if math.abs(localPoint.X) < 15 and localPoint.Z > PLOT_DEPTH / 2 and localPoint.Z < RING_RADIUS - GARDEN_RADIUS + 2 then
			return true
		end
	end
	return false
end

function PlotBuilder.BuildWorld()
	local half = MAP_SIZE / 2

	-- Ground: bright green and studded
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		for _, child in baseplate:GetChildren() do
			if child:IsA("Texture") or child:IsA("Decal") then
				child:Destroy()
			end
		end
		baseplate.Size = Vector3.new(MAP_SIZE + 150, 16, MAP_SIZE + 150)
		baseplate.CFrame = CFrame.new(0, -8, 0)
		baseplate.Color = C.Grass
		baseplate.Material = Enum.Material.SmoothPlastic
		studTexture(baseplate, Enum.NormalId.Top)
	end

	-- Each plot has its own spawn pad, so the default one is not needed.
	local defaultSpawn = workspace:FindFirstChild("SpawnLocation")
	if defaultSpawn then
		defaultSpawn:Destroy()
	end

	local oldMap = workspace:FindFirstChild("Map")
	if oldMap then
		oldMap:Destroy()
	end
	local map = Instance.new("Folder")
	map.Name = "Map"
	local random = Random.new(7)
	look = Random.new(23)

	-- Patches of lighter and darker grass. Every edge is straight, so the lawn looks like
	-- it was laid out of square tiles. (They are paper-thin and you walk straight over them.)
	local lawn = Instance.new("Folder")
	lawn.Name = "Lawn"
	local made, tries = 0, 0
	while made < 130 and tries < 8000 do
		tries += 1
		local width = random:NextInteger(5, 15) * 2
		local depth = random:NextInteger(5, 15) * 2
		local x = random:NextInteger(-(half - 24) / 2, (half - 24) / 2) * 2
		local z = random:NextInteger(-(half - 24) / 2, (half - 24) / 2) * 2
		local free = not isBuiltOn(x, z)
		for _, corner in { Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(1, 1) } do
			if isBuiltOn(x + corner.X * width / 2, z + corner.Y * depth / 2) then
				free = false
			end
		end
		if free then
			made += 1
			local color = if made % 3 == 0 then C.GrassDark else C.GrassLight
			-- each patch sits a hair higher than the last, so overlapping patches never flicker
			local y = 0.03 + (made % 8) * 0.02
			decoration(block("Patch", Vector3.new(width, 0.06, depth), CFrame.new(x, y, z), color, lawn))
			-- a small square sticking out of one side gives the stepped edge
			local side = if made % 2 == 0 then 1 else -1
			decoration(block("PatchStep", Vector3.new(4, 0.06, math.max(4, depth - 8)), CFrame.new(x + side * (width / 2 + 2), y, z), color, lawn))
		end
	end
	lawn.Parent = map

	-- An orange path from every plot's entrance to the garden, with stepped edges
	local paths = Instance.new("Folder")
	paths.Name = "Paths"
	local pathStart = GARDEN_RADIUS + 3
	local pathEnd = RING_RADIUS - PLOT_DEPTH / 2
	local pathLength = pathEnd - pathStart
	for index, origin in PLOT_ORIGINS do
		local direction = origin.Position.Unit
		local middle = direction * ((pathStart + pathEnd) / 2)
		steppedPath("Path" .. index, CFrame.lookAt(middle, Vector3.zero), 18, pathLength, paths, random)
	end
	-- a ring road round the garden joins all six paths
	steppedDisc("RingRoadRim", GARDEN_RADIUS + 17, 0.18, 0.09, C.PathEdge, paths)
	steppedDisc("RingRoad", GARDEN_RADIUS + 16, 0.26, 0.13, C.Path, paths)
	paths.Parent = map

	-- Cliffs round the map (lilac rock with green tops), plus tall invisible walls so nobody
	-- can leave the map.
	local walls = Instance.new("Folder")
	walls.Name = "Walls"
	local sides = {
		{ Along = Vector3.xAxis, Out = Vector3.new(0, 0, -1), Length = MAP_SIZE + 150 },
		{ Along = Vector3.xAxis, Out = Vector3.new(0, 0, 1), Length = MAP_SIZE + 150 },
		{ Along = Vector3.zAxis, Out = Vector3.new(-1, 0, 0), Length = MAP_SIZE - 4 },
		{ Along = Vector3.zAxis, Out = Vector3.new(1, 0, 0), Length = MAP_SIZE - 4 },
	}
	local tiers = {
		{ Height = 24, Depth = 28, Start = 0, Color = C.Cliff },
		{ Height = 54, Depth = 40, Start = 28, Color = C.CliffDark },
	}
	local function boxSize(side, along, height, depth)
		return if side.Along == Vector3.xAxis then Vector3.new(along, height, depth) else Vector3.new(depth, height, along)
	end
	for _, side in sides do
		for tierIndex, tier in tiers do
			local distance = half - 2 + tier.Start + tier.Depth / 2
			block(
				"Cliff" .. tierIndex,
				boxSize(side, side.Length, tier.Height, tier.Depth),
				CFrame.new(side.Out * distance + Vector3.new(0, tier.Height / 2, 0)),
				tier.Color,
				walls
			)
			-- the grassy cap hangs a little over the edge
			block(
				"CliffCap" .. tierIndex,
				boxSize(side, side.Length, 3, tier.Depth + 2),
				CFrame.new(side.Out * (distance - 1) + Vector3.new(0, tier.Height + 1.5, 0)),
				C.CliffCap,
				walls
			)
		end
		local wall = block(
			"InvisibleWall",
			boxSize(side, MAP_SIZE, 120, 4),
			CFrame.new(side.Out * (half - 4) + Vector3.new(0, 60, 0)),
			C.White,
			walls
		)
		wall.Transparency = 1
		wall.CanQuery = false
	end
	walls.Parent = map

	-- Small flowers and clumps of tall grass (same layout every time thanks to the fixed seed)
	local flowers = Instance.new("Folder")
	flowers.Name = "Flowers"
	local planted = 0
	while planted < 240 do
		local x = random:NextNumber(-(half - 12), half - 12)
		local z = random:NextNumber(-(half - 12), half - 12)
		if not isBuiltOn(x, z) then
			planted += 1
			if planted % 3 == 0 then
				tuft(Vector3.new(x, 0, z), random, flowers)
			else
				flower(Vector3.new(x, 0, z), FLOWER_COLORS[random:NextInteger(1, #FLOWER_COLORS)], flowers)
			end
		end
	end
	flowers.Parent = map

	-- Trees: between the plots and in the corners
	local trees = Instance.new("Folder")
	trees.Name = "Trees"
	local treeSpots = {}
	for step = 0, 5 do
		local between = math.rad(step * 60)
		for _, radius in { 156, 196, 236 } do
			table.insert(treeSpots, Vector3.new(math.cos(between) * radius, 0, math.sin(between) * radius))
		end
	end
	for _, corner in { Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(1, 1) } do
		table.insert(treeSpots, Vector3.new(corner.X * (half - 22), 0, corner.Y * (half - 22)))
	end
	for _, spot in treeSpots do
		tree(spot, trees)
	end
	trees.Parent = map

	-- Bushes, rocks and mushrooms on the lawns. (Their own fixed seed: the same layout every
	-- time, and changing the numbers here never moves the flowers or trees.)
	local nature = Instance.new("Folder")
	nature.Name = "Nature"
	local scatter = Random.new(31)
	local function roomFor(x, z, room)
		for _, step in { Vector2.new(0, 0), Vector2.new(room, 0), Vector2.new(-room, 0), Vector2.new(0, room), Vector2.new(0, -room) } do
			if isBuiltOn(x + step.X, z + step.Y) then
				return false
			end
		end
		for _, spot in treeSpots do
			if (Vector3.new(x, 0, z) - spot).Magnitude < 9 then
				return false
			end
		end
		return true
	end
	local kinds = {
		{ Name = "Bush", Count = 36, Room = 4, Small = 0.85, Big = 1.3, Studs = true },
		{ Name = "Rock", Count = 24, Room = 4, Small = 0.7, Big = 1.25, Studs = true },
		{ Name = "Mushroom", Count = 42, Room = 2, Small = 0.8, Big = 1.3, Studs = false },
	}
	for _, kind in kinds do
		local made, tries = 0, 0
		while made < kind.Count and tries < 3000 do
			tries += 1
			local x = scatter:NextNumber(-(half - 16), half - 16)
			local z = scatter:NextNumber(-(half - 16), half - 16)
			if roomFor(x, z, kind.Room) then
				made += 1
				local spin = CFrame.new(x, 0, z) * CFrame.Angles(0, scatter:NextNumber(0, math.pi * 2), 0)
				local piece = decoration(prop(kind.Name, spin, nature, scatter:NextNumber(kind.Small, kind.Big)))
				if kind.Studs then
					studded(piece)
				end
			end
		end
	end
	-- bare earth and flat stones dotted over the lawns
	local placed, attempts = 0, 0
	while placed < 70 and attempts < 4000 do
		attempts += 1
		local x = scatter:NextNumber(-(half - 16), half - 16)
		local z = scatter:NextNumber(-(half - 16), half - 16)
		if roomFor(x, z, 5) then
			placed += 1
			local width, depth = scatter:NextInteger(2, 4) * 2, scatter:NextInteger(2, 4) * 2
			if placed % 2 == 0 then
				decoration(block("Earth", Vector3.new(width, 0.26, depth), CFrame.new(x, 0.13, z), C.Soil, nature))
				decoration(block("Earth", Vector3.new(4, 0.2, 2), CFrame.new(x + width / 2 + 1, 0.1, z + 1), C.SoilDark, nature))
			else
				decoration(block("Slab", Vector3.new(width, 0.28, depth), CFrame.new(x, 0.14, z), C.Stone, nature))
				decoration(block("Slab", Vector3.new(2, 0.34, 4), CFrame.new(x - width / 2 - 1, 0.17, z + 1), C.StoneDark, nature))
				decoration(block("Slab", Vector3.new(4, 0.22, 2), CFrame.new(x + 1, 0.11, z + depth / 2 + 1), C.Cream, nature))
			end
		end
	end
	nature.Parent = map

	PlotBuilder.AddStuds(map)
	map.Parent = workspace

	-- The sky and the light, and everything on and behind the cliffs, are made by their own
	-- tool (a fresh copy, so it is never an old one Studio remembered).
	local holder = Instance.new("Folder")
	local scenery = game:GetService("ServerStorage").BeeEmpireDev.SceneryBuilder:Clone()
	scenery.Parent = holder
	require(scenery).Build()
	holder:Destroy()
end

function PlotBuilder.BuildPlots()
	local old = workspace:FindFirstChild("Plots")
	if old then
		old:Destroy()
	end
	local plots = Instance.new("Folder")
	plots.Name = "Plots"
	for index, origin in PLOT_ORIGINS do
		PlotBuilder.BuildPlot(index, origin, plots)
	end
	plots.Parent = workspace
	return plots
end

function PlotBuilder.BuildAll()
	PlotBuilder.BuildWorld()
	PlotBuilder.BuildGarden()
	PlotBuilder.BuildPlots()
end

return PlotBuilder
