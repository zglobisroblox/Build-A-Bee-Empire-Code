-- SoundLab (dev only): measures sounds from Roblox's library without playing them out loud.
-- Look(id, buckets) -> a text line: length, peak, loudness, and a little loudness-over-time bar.
local SoundLab = {}

local BARS = { " ", ".", ":", "-", "=", "+", "*", "#", "%", "@" }

function SoundLab.Measure(id: string, buckets: number?, from: number?, to: number?)
	local player = Instance.new("AudioPlayer")
	player.Asset = id
	player.Parent = game:GetService("ServerStorage")
	local t0 = os.clock()
	while not player.IsReady and os.clock() - t0 < 12 do
		task.wait(0.05)
	end
	if not player.IsReady then
		player:Destroy()
		return nil
	end
	local length = player.TimeLength
	local a, b = from or 0, math.min(to or length, length)
	local count = buckets or 24
	local per = 120
	local ok, wave = pcall(function()
		return player:GetWaveformAsync(NumberRange.new(a, b), count * per)
	end)
	player:Destroy()
	if not ok or not wave then
		return nil
	end
	local env, peak, sum, n = {}, 0, 0, 0
	for i = 1, count do
		local top = 0
		for j = (i - 1) * per + 1, math.min(i * per, #wave) do
			local v = math.abs(wave[j])
			if v > top then top = v end
			sum += wave[j] * wave[j]
			n += 1
		end
		env[i] = top
		if top > peak then peak = top end
	end
	return { Length = length, Peak = peak, Rms = math.sqrt(sum / math.max(n, 1)), Env = env, From = a, To = b }
end

function SoundLab.Look(id: string, buckets: number?, from: number?, to: number?): string
	local r = SoundLab.Measure(id, buckets, from, to)
	if not r then
		return id .. "  (could not load)"
	end
	local bar = {}
	for i, v in ipairs(r.Env) do
		local k = math.clamp(math.floor(v / math.max(r.Peak, 0.001) * 9 + 0.5), 0, 9)
		bar[i] = BARS[k + 1]
	end
	return string.format("%s  len %.2f  peak %.2f  rms %.3f  [%s]  (%.2f-%.2fs)", id, r.Length, r.Peak, r.Rms, table.concat(bar), r.From, r.To)
end

return SoundLab
