--[[
	PropFactory - builds small placeholder props (egg, jar, coin) out of simple Parts.
	Used for the little 3D pictures in the screen UI and for decoration on the map.
]]

local PropFactory = {}

local WHITE = Color3.fromRGB(255, 255, 255)
local JAR = Color3.fromRGB(255, 170, 30)
local LID = Color3.fromRGB(250, 242, 225)
local GOLD = Color3.fromRGB(255, 205, 50)
local GOLD_DARK = Color3.fromRGB(235, 160, 20)

local function part(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): Part
	local newPart = Instance.new("Part")
	newPart.Name = name
	newPart.Size = size
	newPart.CFrame = cframe
	newPart.Color = color
	newPart.Material = Enum.Material.SmoothPlastic
	newPart.Anchored = true
	newPart.CanCollide = false
	newPart.CanTouch = false
	newPart.CanQuery = false
	newPart.CastShadow = false
	newPart.TopSurface = Enum.SurfaceType.Smooth
	newPart.BottomSurface = Enum.SurfaceType.Smooth
	newPart.Parent = parent
	return newPart
end

local function roundMesh(target: Part)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = target
end

-- An egg with a few lighter spots.
function PropFactory.Egg(color: Color3): Model
	local model = Instance.new("Model")
	model.Name = "Egg"
	local shell = part("Shell", Vector3.new(2.3, 3, 2.3), CFrame.new(), color, model)
	roundMesh(shell)
	model.PrimaryPart = shell

	local spotColor = color:Lerp(WHITE, 0.55)
	local spots = {
		{ Vector3.new(0.55, 0.5, -0.92), 0.6 },
		{ Vector3.new(-0.5, -0.35, -1.0), 0.75 },
		{ Vector3.new(0.15, -0.95, -0.82), 0.5 },
		{ Vector3.new(-0.35, 0.95, -0.72), 0.45 },
	}
	for _, spot in spots do
		local dot = part("Spot", Vector3.new(spot[2], spot[2], 0.25), CFrame.lookAt(spot[1], spot[1] * 2), spotColor, model)
		roundMesh(dot)
	end
	return model
end

-- A honey jar with a lid.
function PropFactory.Jar(): Model
	local model = Instance.new("Model")
	model.Name = "Jar"
	local upright = CFrame.Angles(0, 0, math.rad(90))
	local glass = part("Glass", Vector3.new(1.6, 1.5, 1.5), upright, JAR, model)
	glass.Shape = Enum.PartType.Cylinder
	model.PrimaryPart = glass
	local lid = part("Lid", Vector3.new(0.3, 1.65, 1.65), CFrame.new(0, 0.95, 0) * upright, LID, model)
	lid.Shape = Enum.PartType.Cylinder
	local label = part("Label", Vector3.new(0.7, 0.75, 0.1), CFrame.new(0, -0.05, -0.74), LID, model)
	label.Name = "Label"
	return model
end

-- A gold coin facing -Z.
function PropFactory.Coin(): Model
	local model = Instance.new("Model")
	model.Name = "Coin"
	local facing = CFrame.Angles(0, math.rad(90), 0)
	local disc = part("Disc", Vector3.new(0.35, 2, 2), facing, GOLD, model)
	disc.Shape = Enum.PartType.Cylinder
	model.PrimaryPart = disc
	local inner = part("Inner", Vector3.new(0.4, 1.45, 1.45), facing, GOLD_DARK, model)
	inner.Shape = Enum.PartType.Cylinder
	return model
end

return PropFactory
