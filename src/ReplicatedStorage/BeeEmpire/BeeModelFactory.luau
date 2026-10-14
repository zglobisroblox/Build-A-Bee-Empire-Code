--[[
	BeeModelFactory - puts a bee together from the pieces that were modelled in Blender.

	The pieces live in ReplicatedStorage.BeeEmpire.BeeMeshes:
		Body      takes the bee's colour
		Details   stripes, face, fluffy collar, legs, antennae and stinger (painted on the mesh)
		Wing      used twice
		ScoutGear, GuardGear, RoyalGear, EmperorGear, Crown,
		BuilderGear, ExplorerGear, KnightGear, WizardGear, GalaxyGear   the outfits
		GalaxyGlow   the Galaxy Bee's ring and stars (white: it is made to glow)
	Which outfit a bee wears is set in GameConfig (Bees[...].Outfit, and Glow for glowing pieces).
	(BeeMeshes also holds Egg, the mystery egg of the roll show. WorldFX uses that one.)

	Nothing else needs to change as long as Create() still returns a Model with a PrimaryPart
	whose pivot is the middle of the bee's body, facing -Z (Roblox's "forward").
]]

local GameConfig = require(script.Parent.GameConfig)

local BeeModelFactory = {}

local pieces = script.Parent:WaitForChild("BeeMeshes")

local BLACK = Color3.fromRGB(35, 30, 30)
local WHITE = Color3.fromRGB(255, 255, 255)

-- Everything is measured in "bee space": x = the bee's right, y = up, z = towards its tail.
local BODY_MIDDLE = CFrame.new(0, 0, 0.3) -- the point the game moves a bee by
local WING_PLACES = {
	CFrame.new(0.95, 1.02, 0.25) * CFrame.Angles(0, 0, math.rad(25)),
	CFrame.new(-0.95, 1.02, 0.25) * CFrame.Angles(0, 0, math.rad(-25)),
}
local WING_SEE_THROUGH = 0.3

local function quiet(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
end

local function box(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	quiet(part)
	part.Parent = parent
	return part
end

-- Adds one Blender piece to the bee. "place" moves it (the wings use this); pieces painted
-- on the mesh keep their own colours when the part itself is white.
local function piece(model: Model, name: string, color: Color3, place: CFrame?): MeshPart?
	local template = pieces:FindFirstChild(name)
	if not (template and template:IsA("MeshPart")) then
		return nil
	end
	local part = template:Clone()
	local own = template:GetAttribute("Place")
	part.CFrame = (place or CFrame.identity) * (if typeof(own) == "CFrame" then own else CFrame.identity)
	part.Color = color
	quiet(part)
	part.Parent = model
	return part
end

-- What a bee of this colour wears and how big it is (from GameConfig). A colour that is not
-- one of the kinds (a shadow, a carrier bee, a shopkeeper) is a plain bee.
local function lookFor(bodyColor: Color3): ({ string }, number, { [string]: Color3 }?)
	for _, name in GameConfig.BeeOrder do
		local bee = GameConfig.Bees[name]
		if bee.Color == bodyColor then
			return bee.Outfit or {}, bee.Size or 1, bee.Glow
		end
	end
	return {}, 1, nil
end

-- red, orange, yellow, green, blue, purple
local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 70, 70)),
	ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 170, 40)),
	ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 240, 60)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(80, 230, 110)),
	ColorSequenceKeypoint.new(0.8, Color3.fromRGB(70, 160, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 100, 255)),
})

export type BeeOptions = {
	Scale: number?,
	Outfit: { string }?, -- wear these pieces instead of what the colour says (the Queen does)
	Crown: boolean?,
	Sparkles: boolean?,
	Trail: boolean?, -- a rainbow ribbon and rainbow sparkles that stay behind while the bee flies
	Pollen: boolean?, -- adds a hidden block of pollen under the bee (shown while it flies home)
	Cargo: boolean?, -- adds a hidden honey jar under the bee (carrier bees show it while they carry honey)
}

-- The bee is built at the origin facing -Z (Roblox's "forward"). Move it with model:PivotTo().
function BeeModelFactory.Create(bodyColor: Color3, options: BeeOptions?): Model
	local beeOptions: BeeOptions = options or {}

	local model = Instance.new("Model")
	model.Name = "Bee"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	-- (if the Blender pieces ever go missing, a plain block keeps the game working)
	local body: BasePart = piece(model, "Body", bodyColor) or box("Body", Vector3.new(1.9, 1.8, 2.6), BODY_MIDDLE, bodyColor, model)
	body.PivotOffset = body.CFrame:ToObjectSpace(BODY_MIDDLE)
	model.PrimaryPart = body

	piece(model, "Details", WHITE)
	for _, place in WING_PLACES do
		local wing = piece(model, "Wing", WHITE, place)
		if wing then
			wing.Transparency = WING_SEE_THROUGH
		end
	end

	local outfit, size, glow = lookFor(bodyColor)
	for _, name in beeOptions.Outfit or outfit do
		piece(model, name, WHITE)
	end
	if glow and not beeOptions.Outfit then
		-- pieces that shine by themselves (the Galaxy Bee's ring and stars)
		for name, color in glow do
			local shining = piece(model, name, color)
			if shining then
				shining.Material = Enum.Material.Neon
			end
		end
	end
	if beeOptions.Crown and not model:FindFirstChild("Crown") then
		piece(model, "Crown", WHITE)
	end

	if beeOptions.Pollen then
		local pollen = box("Pollen", Vector3.new(0.8, 0.8, 0.8), CFrame.new(0, -1.2, 0.2), Color3.fromRGB(255, 225, 90), model)
		pollen.Material = Enum.Material.Neon
		pollen.Transparency = 1
	end

	if beeOptions.Cargo then
		local jar = box("Cargo", Vector3.new(1, 0.9, 1), CFrame.new(0, -1.5, 0.2), Color3.fromRGB(255, 170, 30), model)
		jar.Transparency = 1
		local lid = box("CargoLid", Vector3.new(1.15, 0.22, 1.15), CFrame.new(0, -0.94, 0.2), Color3.fromRGB(250, 242, 225), model)
		lid.Transparency = 1
		-- two little straps so it looks held, not floating
		for _, side in { -1, 1 } do
			local strap = box("CargoStrap", Vector3.new(0.08, 0.5, 0.08), CFrame.new(0.3 * side, -0.9, 0.2), BLACK, model)
			strap.Transparency = 1
		end
	end

	if beeOptions.Sparkles then
		local sparkles = Instance.new("ParticleEmitter")
		sparkles.Name = "Sparkles"
		sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkles.Color = ColorSequence.new(bodyColor, WHITE)
		sparkles.LightEmission = 1
		sparkles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
		sparkles.Lifetime = NumberRange.new(0.8, 1.3)
		sparkles.Rate = 7
		sparkles.Speed = NumberRange.new(1, 2)
		sparkles.SpreadAngle = Vector2.new(180, 180)
		sparkles.Parent = body

		local glow = Instance.new("PointLight")
		glow.Name = "Glow"
		glow.Color = bodyColor
		glow.Range = 10
		glow.Brightness = 1.2
		glow.Parent = body
	end

	if beeOptions.Trail then
		-- a rainbow ribbon behind the bee...
		local top = Instance.new("Attachment")
		top.Name = "TrailTop"
		top.Position = Vector3.new(0, 1, 1.3)
		top.Parent = body
		local bottom = Instance.new("Attachment")
		bottom.Name = "TrailBottom"
		bottom.Position = Vector3.new(0, -1, 1.3)
		bottom.Parent = body
		local ribbon = Instance.new("Trail")
		ribbon.Name = "RainbowTrail"
		ribbon.Attachment0 = top
		ribbon.Attachment1 = bottom
		ribbon.Color = RAINBOW
		ribbon.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.05),
			NumberSequenceKeypoint.new(0.7, 0.3),
			NumberSequenceKeypoint.new(1, 1),
		})
		ribbon.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.15) })
		ribbon.Lifetime = 0.8
		ribbon.MinLength = 0.05
		-- (a solid ribbon, not a glowing one: a glow hardly shows against the bright ground)
		ribbon.LightEmission = 0
		ribbon.LightInfluence = 0
		ribbon.FaceCamera = true
		ribbon.Parent = body

		-- ...and rainbow sparkles that are left hanging in the air
		local stars = Instance.new("ParticleEmitter")
		stars.Name = "RainbowSparkles"
		stars.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		stars.Color = RAINBOW
		stars.LightEmission = 0.2
		stars.LightInfluence = 0
		stars.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.3), NumberSequenceKeypoint.new(1, 0) })
		stars.Lifetime = NumberRange.new(0.8, 1.4)
		stars.Rate = 22
		stars.Speed = NumberRange.new(0, 1)
		stars.SpreadAngle = Vector2.new(180, 180)
		stars.Parent = body
	end

	local scale = (beeOptions.Scale or 1) * size
	if scale ~= 1 then
		model:ScaleTo(scale)
	end

	return model
end

return BeeModelFactory
