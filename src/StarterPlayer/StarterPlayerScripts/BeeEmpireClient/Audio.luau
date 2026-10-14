--[[
	Audio - the background song, and how loud everything is.

	The Music and Sounds sliders in the Settings window are saved by the server and come back
	as two numbers on the player (see State). This module turns those numbers into loudness.
	While a slider is being dragged, the window calls Preview so the change is heard at once.

	Which song plays, and how loud "100%" is, are in GameConfig (MusicId, MusicLoudness).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local GameConfig = require(ReplicatedStorage:WaitForChild("BeeEmpire"):WaitForChild("GameConfig"))

local Kit = require(script.Parent.UIKit)
local State = require(script.Parent.State)

local Audio = {}

local song: Sound? = nil
-- a volume being tried out on a slider right now: { Music = 40 }
local previews: { [string]: number } = {}

local function apply()
	local music = previews.Music or State.MusicVolume()
	Kit.SetSoundVolume(previews.Sounds or State.SoundVolume())
	if song then
		song.Volume = GameConfig.MusicLoudness * math.clamp(music, 0, 100) / 100
		-- the song starts once the player's own volume is known, and rests while it is at zero
		local shouldPlay = music > 0 and State.IsLoaded()
		if song.Playing ~= shouldPlay then
			song.Playing = shouldPlay
		end
	end
end

-- Try out a volume (name is "Music" or "Sounds", percent is 0 to 100).
-- percent = nil goes back to the saved volume.
function Audio.Preview(name: string, percent: number?)
	previews[name] = percent
	apply()
end

function Audio.Init()
	if typeof(GameConfig.MusicId) == "string" and GameConfig.MusicId ~= "" then
		song = Kit.Create("Sound", {
			Name = "BeeEmpireMusic",
			SoundId = GameConfig.MusicId,
			Looped = true,
			Volume = 0,
			Parent = SoundService,
		})
	end
	State.Changed:Connect(apply)
	apply()
end

return Audio
