--[[
	Studs - the toy-brick look. Lays a square-stud picture over the faces of a block,
	so everything in the game looks like it was built from the same bricks.

	The picture is a free Creator Store image. Change Studs.Texture to swap it everywhere
	(then run the PlotBuilder again so the map picks it up).
]]

local Studs = {}

Studs.Texture = "rbxassetid://7447638591"
Studs.Size = 2 -- how many studs wide one bump is

-- Covers one face of a part. tile = how wide one bump is (default Studs.Size).
function Studs.Face(part: BasePart, face: Enum.NormalId, tile: number?): Texture
	local texture = Instance.new("Texture")
	texture.Name = "Studs"
	texture.Texture = Studs.Texture
	texture.Face = face
	texture.StudsPerTileU = tile or Studs.Size
	texture.StudsPerTileV = tile or Studs.Size
	texture.Parent = part
	return texture
end

-- Covers the top and the four sides of a block, skipping faces too small to fit a bump.
function Studs.Add(part: BasePart, tile: number?)
	local bump = tile or Studs.Size
	local smallest = bump * 0.65
	local size = part.Size
	if size.X >= smallest and size.Z >= smallest then
		Studs.Face(part, Enum.NormalId.Top, bump)
	end
	if size.Y >= smallest then
		if size.X >= smallest then
			Studs.Face(part, Enum.NormalId.Front, bump)
			Studs.Face(part, Enum.NormalId.Back, bump)
		end
		if size.Z >= smallest then
			Studs.Face(part, Enum.NormalId.Left, bump)
			Studs.Face(part, Enum.NormalId.Right, bump)
		end
	end
end

return Studs
