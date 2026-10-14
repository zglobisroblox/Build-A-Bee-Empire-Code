--[[
	UIImages - the pictures used in the menus.

	Every picture is a drawing of one of our own 3D models (made with
	ServerStorage.BeeEmpireDev.IconStudio) that was uploaded to Roblox. Roblox gives each
	uploaded picture a number; those numbers are all kept here, in one place.

	To add a new kind of bee: draw and upload its picture, then add a line to UIImages.Bees.
	Until then, a bee without its own picture shows the first bee's picture.
]]

local GameConfig = require(script.Parent.GameConfig)

local UIImages = {}

UIImages.Coin = "rbxassetid://71919404605768"
UIImages.Jar = "rbxassetid://111621484167740" -- a jar of honey
UIImages.Lock = "rbxassetid://99478022938540" -- a hive spot that is still locked
UIImages.Arrow = "rbxassetid://129201309149372" -- the Upgrade Shop
UIImages.Clover = "rbxassetid://84423713163653" -- the Queen's Luck upgrade
UIImages.SpeedBee = "rbxassetid://136672979782644" -- the Bee Speed upgrade
UIImages.Egg = "rbxassetid://102245578720751" -- the More Rolls upgrade (the mystery egg)
UIImages.FastEgg = "rbxassetid://132741246019666" -- the Roll Speed upgrade (the mystery egg with speed lines)
UIImages.WalkSpeed = "rbxassetid://89333949046329" -- the Walk Speed upgrade (a bee-striped sneaker with a wing and speed lines)
UIImages.Gear = "rbxassetid://94885282692628" -- the Settings button and window
UIImages.Music = "rbxassetid://77775659018235" -- the music volume
UIImages.Speaker = "rbxassetid://112444982237747" -- the sound effects volume
UIImages.Calendar = "rbxassetid://137134006746434" -- the Daily Rewards button and window (a calendar with a tick)
UIImages.Backpack = "rbxassetid://111101608052900" -- the Inventory button and window (a honey-coloured backpack)
UIImages.Shop = "rbxassetid://102044391951696" -- the Shop button and window (a market stall with a striped roof)
UIImages.HalloweenEgg = "rbxassetid://80447254874364" -- the Halloween Egg (a limited-time event)

-- white glow pictures for the reveal screens, tinted in the game (drawn by icon-tools\make-fx.ps1)
UIImages.Fx = {
	Rays = "rbxassetid://121656174186329", -- a sunburst of 12 rays that fade out towards the edge
	Glow = "rbxassetid://78079692624152", -- a soft round glow
	Sparkle = "rbxassetid://123529723591210", -- a four-pointed twinkle star
}

-- one picture per pass (the names match GameConfig.Passes)
UIImages.Passes = {
	StarterPack = "rbxassetid://99567876065521", -- a gift box
	Rolls = "rbxassetid://75432882681891", -- two mystery eggs and "+2"
	LuckyQueen = "rbxassetid://116760076108779", -- a clover wearing a crown, and "x2"
	AutoSell = "rbxassetid://91191396465175", -- a honey jar, a coin and "AUTO"
	InfiniteInventory = "rbxassetid://117013237087628", -- the backpack with an infinity sign
	VIP = "rbxassetid://101645654911390", -- a crown over "VIP"
}

-- one picture per bee (the names match GameConfig.Bees)
UIImages.Bees = {
	Common = "rbxassetid://126038686024200", -- Worker Bee
	Uncommon = "rbxassetid://135472858758591", -- Scout Bee
	Rare = "rbxassetid://108059206554074", -- Guard Bee
	Epic = "rbxassetid://109181638264962", -- Royal Bee
	Legendary = "rbxassetid://104310151658817", -- Emperor Bee
	Builder = "rbxassetid://113007330771684", -- Builder Bee
	Explorer = "rbxassetid://127505070904764", -- Explorer Bee
	Knight = "rbxassetid://78704267318403", -- Knight Bee
	Wizard = "rbxassetid://86035814347272", -- Wizard Bee
	Galaxy = "rbxassetid://75490821625417", -- Galaxy Bee
	-- Limited bees (Halloween 2026)
	Bat = "rbxassetid://91799548554906", -- Bat Bee
	Ghost = "rbxassetid://112993378947212", -- Ghost Bee
	PumpkinKing = "rbxassetid://133625872862574", -- Pumpkin King Bee
}

-- one picture per hive level, smallest first
UIImages.Hives = {
	"rbxassetid://105003096405383", -- Tiny Hive
	"rbxassetid://100976451719340", -- Cozy Hive
	"rbxassetid://130073548758972", -- Busy Hive
	"rbxassetid://96258659832508", -- Grand Hive
	"rbxassetid://104657482146946", -- Royal Hive
}

function UIImages.Bee(rarityName: string): string
	return UIImages.Bees[rarityName] or UIImages.Bees[GameConfig.BeeOrder[1]]
end

-- A pass without its own picture shows the Shop's.
function UIImages.Pass(passName: string): string
	return UIImages.Passes[passName] or UIImages.Shop
end

function UIImages.Hive(level: number): string
	return UIImages.Hives[math.clamp(math.floor(level), 1, #UIImages.Hives)]
end

-- Every picture, so the game can fetch them all before the first menu opens.
function UIImages.All(): { string }
	local all = { UIImages.Coin, UIImages.Jar, UIImages.Lock, UIImages.Arrow, UIImages.Clover, UIImages.SpeedBee, UIImages.Egg, UIImages.FastEgg, UIImages.WalkSpeed, UIImages.Gear, UIImages.Music, UIImages.Speaker, UIImages.Calendar, UIImages.Backpack, UIImages.Shop, UIImages.HalloweenEgg }
	for _, image in UIImages.Fx do
		table.insert(all, image)
	end
	for _, image in UIImages.Passes do
		table.insert(all, image)
	end
	for _, image in UIImages.Bees do
		table.insert(all, image)
	end
	for _, image in UIImages.Hives do
		table.insert(all, image)
	end
	return all
end

return UIImages
