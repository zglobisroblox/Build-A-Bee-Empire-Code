--[[
	BEE EMPIRE - GAME CONFIG

	Every balance number in the game lives in this one file.
	Change a number here, press Play, and the whole game uses the new value.
	You never need to touch the other scripts to re-balance the game.
]]

local GameConfig = {}

-- MONEY ---------------------------------------------------------------------
GameConfig.StartingCoins = 50 -- Honey Coins a brand-new player starts with
GameConfig.JarValue = 2 -- Honey Coins for each jar sold at the Honey Market, before the price multiplier below

-- THE HONEY MARKET'S PRICE -------------------------------------------------------
-- The Honey Market pays JarValue x a PRICE MULTIPLIER for every jar. The multiplier is the
-- same for everyone in the server, and every SellPriceSeconds it jumps to a new random number.
-- Each line below is one band: the new price is picked from Min to Max, and Chance says how
-- often that band comes up. (The chances add up to 100, so each one is a percentage.)
-- With these numbers the price is 2x to 3x most of the time and about 2.5x on average.
GameConfig.SellPriceSeconds = 30 -- how long a price lasts
GameConfig.SellPriceBands = {
	{ Min = 1.0, Max = 1.4, Chance = 5 }, -- a poor price: rare, and never worse than 1x
	{ Min = 1.5, Max = 1.9, Chance = 20 },
	{ Min = 2.0, Max = 3.0, Chance = 55 }, -- the usual price
	{ Min = 3.1, Max = 4.0, Chance = 15 },
	{ Min = 4.1, Max = 5.0, Chance = 5 }, -- a great price: about once every 10 minutes
}
GameConfig.SellPriceStep = 0.1 -- prices come in tenths: 2.3x, never 2.37x
GameConfig.SellPriceHigh = 4 -- from this price up the game makes a fuss: rainbow number, "sell now!" message

-- THE BEEHIVE ---------------------------------------------------------------
-- Every player has one beehive. It starts tiny and is upgraded at the Upgrade Shop.
-- Each level is physically bigger and holds more bees.
--   Name:           what the hive is called
--   Cost:           Honey Coins to upgrade TO this level (level 1 is free)
--   Capacity:       how many bees can work in the hive
-- You can add or remove levels; the hive's look for each level is in HiveModelFactory.
GameConfig.HiveLevels = {
	{ Name = "Tiny Hive", Cost = 0, Capacity = 2 },
	{ Name = "Cozy Hive", Cost = 100, Capacity = 4 },
	{ Name = "Busy Hive", Cost = 1000, Capacity = 6 },
	{ Name = "Grand Hive", Cost = 8000, Capacity = 9 },
	{ Name = "Royal Hive", Cost = 40000, Capacity = 12 },
}

-- THE UPGRADE SHOP ------------------------------------------------------------
-- Everything sold at the Upgrade Shop on each plot (the Beehive above is sold there too).
-- Every upgrade has levels. Level 1 is what a new player starts with (Cost = 0).
--   Cost:  Honey Coins to upgrade TO that level
--   Value: what the upgrade does at that level (see each one below)
-- To add a level, add a line. To change a price, change a number.
GameConfig.Upgrades = {
	-- QUEEN'S LUCK HAS NO TOP LEVEL: it can be bought again and again, for ever.
	-- Every level adds a little luck, and costs a bit more than the one before.
	-- Luck multiplies the chance of every rarity except the most common one, so x2 luck
	-- means twice as many Legendary bees (see THE FIVE RARITIES further down).
	--   Step:      luck added by each level (0.1 = level 1 is x1, level 2 is x1.1, level 3 is x1.2...)
	--   FirstCost: Honey Coins for the very first upgrade
	--   Growth:    each upgrade costs this many times the one before (1.15 = 15% more each time)
	-- With these numbers: x1.5 luck costs 500 coins in all, x2 about 1,500, x3 about 7,700,
	-- x4 about 33,000, x5 about 130,000, x6 about 540,000 and x7 about 2.2 million.
	-- (Prices are rounded to two digits so they look tidy: 75, 86, 99, 110, 130...)
	Luck = {
		Name = "Queen's Luck",
		Endless = { Step = 0.1, FirstCost = 75, Growth = 1.15 },
	},
	-- Value = speed multiplier. Bees finish their flower trips this many times faster,
	-- so jars arrive more often (x1.5 speed = 50% more jars per minute).
	BeeSpeed = {
		Name = "Bee Speed",
		Levels = {
			{ Cost = 0, Value = 1 },
			{ Cost = 250, Value = 1.2 },
			{ Cost = 2000, Value = 1.4 },
			{ Cost = 8000, Value = 1.7 },
			{ Cost = 30000, Value = 2 },
		},
	},
	-- Value = how many honeycomb stands you have. One roll puts a bee on EVERY stand you
	-- own, so 2 = two bees to choose from each time you roll. These are the stands anyone
	-- can buy with Honey Coins. A new stand appears next to the Queen the moment it is bought.
	-- (Every home area has room for more: see RollStandSpots below.)
	Rolls = {
		Name = "More Rolls",
		Levels = {
			{ Cost = 0, Value = 1 },
			{ Cost = 400, Value = 2 },
			{ Cost = 6000, Value = 3 },
		},
	},
	-- Value = how many seconds the Queen waits between her own rolls while Auto Roll is
	-- switched on. Smaller = faster. (Rolling by hand is not changed by this.)
	-- NeedsAutoRoll = true: this upgrade only shows in the Upgrade Shop once Auto Roll has
	-- been bought at the sign next to the Queen.
	-- A bee takes 2 seconds to hatch (RollEggSeconds + RollShadowSeconds below), so 2 is the
	-- fastest that makes sense: at 2 the next egg appears the moment a bee has hatched.
	RollSpeed = {
		Name = "Roll Speed",
		NeedsAutoRoll = true,
		Levels = {
			{ Cost = 0, Value = 8 },
			{ Cost = 500, Value = 7 },
			{ Cost = 1500, Value = 6 },
			{ Cost = 5000, Value = 5 },
			{ Cost = 15000, Value = 4 },
			{ Cost = 50000, Value = 3 },
			{ Cost = 150000, Value = 2 },
		},
	},
	-- Value = how fast you walk, times GameConfig.WalkSpeed (x1.5 = half as fast again).
	-- It goes up in small steps: every upgrade adds Step (0.01 = 1% faster), up to Top. With
	-- Step 0.01 and Top 1.5 that is 50 upgrades to buy. The prices follow the same rule as
	-- Queen's Luck: the first costs FirstCost, and each one after it Growth times the one before.
	-- With these numbers: x1.1 costs about 3,100 coins in all, x1.25 about 32,000, and all the way
	-- to x1.5 about 1,100,000 (the last upgrade alone about 140,000).
	-- WindowOnly = true: it is in the Upgrade Shop window, not on the board in the yard
	-- (the board has room for four).
	WalkSpeed = {
		Name = "Walk Speed",
		WindowOnly = true,
		Steps = { Step = 0.01, Top = 1.5, FirstCost = 150, Growth = 1.15 },
	},
}

-- The order the upgrades are listed in at the shop. "Hive" is the beehive (GameConfig.HiveLevels).
GameConfig.UpgradeOrder = { "Hive", "Luck", "BeeSpeed", "Rolls", "WalkSpeed", "RollSpeed" }

-- THE TUTORIAL (the yellow hint and the bouncing arrow) ----------------------------------
-- A new player gets a yellow hint at the top of the screen, and an arrow that shows where to
-- go. Together they are the tutorial. They stay until the player has done each of these
-- three things once:
--   1. sold honey at the Honey Market
--   2. bought an upgrade at the Upgrade Shop (a bigger hive counts)
--   3. swapped a better bee into a full hive
-- Then the hint and the arrow go away for good. (This is saved with the player's progress,
-- so the tutorial never comes back.)
--
-- Until the player has bought their first upgrade, the hint says "You can afford an upgrade!"
-- when they can. Queen's Luck is cheap and never runs out, so while a bigger hive is still on
-- sale it only counts when its price is at most this share of that hive's price. 0.1 = a
-- tenth. That way new players save for the hive first. (They can buy luck whenever they like.)
GameConfig.EndlessHintShare = 0.1
-- The last lesson is "roll for a better bee". If a better bee is waiting on a stand and the
-- player cannot pay for it yet, the hint says "save up for it" when their bees can earn the
-- missing coins within this many seconds. If it would take longer, it says "roll again".
GameConfig.SaveForBeeSeconds = 45

GameConfig.MaxBeesInBag = 20 -- spare bees a player's Inventory can hold (bees that are not working in the hive)
-- (A player with the Infinite Inventory pass has no such limit: see THE SHOP further down.)

-- QUEEN BEE (rolling for bees) ------------------------------------------------
-- Each player has a Queen in their home area. Pressing E at her "rolls": a random bee
-- hatches on every honeycomb stand the player owns (a mystery egg, then a black shadow,
-- then the bee) and each stand shows its bee's price. The player then chooses: buy a bee,
-- or roll again for different ones. Rolling is FREE.
-- What each bee costs is in THE BEES list further down (Price).
-- How many stands a player owns is the "More Rolls" upgrade above.
GameConfig.RollStandSpots = 5 -- the most stands anyone can ever have (a home area has room for 5)
GameConfig.GamePassRollStands = 2 -- 2 of those 5 come with the "+2 Rolls" pass (see THE SHOP further down), so 3 can be bought with coins
GameConfig.RollCooldown = 2 -- seconds the Queen needs between rolls
GameConfig.RollEggSeconds = 1.1 -- how long the mystery egg shows
GameConfig.RollShadowSeconds = 0.9 -- how long the black shadow shows before the bee is revealed
GameConfig.FirstBeeFree = true -- a player with no bees at all is always offered a free starter bee, so nobody gets stuck
-- The bees waiting on a player's stands are SAVED. If they leave and come back later, the same
-- bees are still on their stands (a bee they could not afford yet is not lost).
-- The egg, pop and hatch sounds of a roll are only heard near the stands:
GameConfig.RollSoundRange = 30 -- within this many studs of a stand its roll sounds play at full volume
GameConfig.RollSoundFade = 10 -- over this many studs further out they fade away to nothing

-- AUTO ROLL -------------------------------------------------------------------
-- A sign next to the Queen sells Auto Roll. It is bought ONCE (the sign then disappears
-- for good) and it is saved. With Auto Roll switched on, the Queen rolls by herself while
-- her owner is in the roll area. A button on the screen switches it on and off.
GameConfig.AutoRollPrice = 1000 -- Honey Coins, paid once
-- (How often the Queen rolls by herself is the Roll Speed upgrade: see GameConfig.Upgrades.RollSpeed.)
GameConfig.AutoRollRange = 45 -- she only rolls by herself while her owner is within this many studs of her
GameConfig.AutoRollBuyPause = 3 -- seconds she waits after you buy a bee, so you can look at the other stands
GameConfig.AutoRollJoinWait = 10 -- seconds she waits after you join, so you can look at the bees saved on your stands
-- Auto Roll WAITS when the Queen rolls a kind of bee the player wants (they tick the kinds in
-- Settings). She carries on once that bee is bought, or when the player taps Keep Rolling.
-- These are the kinds she waits for until a player has chosen for themselves:
GameConfig.AutoRollStopDefault = { "Epic", "Legendary" }

-- SETTINGS (the gear button at the top of the screen) ----------------------------
-- The song comes from Roblox's own free music library ("Playtime", courtesy of APM Music),
-- which every Roblox game is allowed to use. To change the song, change the number.
GameConfig.MusicId = "rbxassetid://1839857481"
GameConfig.MusicLoudness = 0.5 -- how loud the song is with the Music slider at 100% (0 = silent, 1 = full)
GameConfig.DefaultMusicVolume = 50 -- where the Music slider starts for a new player (0 to 100)
GameConfig.DefaultSoundVolume = 100 -- where the Sounds slider starts for a new player (0 to 100)

-- SOUND EFFECTS ---------------------------------------------------------------
-- Every sound effect comes from Roblox's own free library (recorded by Pro Sound Effects),
-- which every Roblox game is allowed to use. The style is bubbly and cartoony: pops,
-- xylophone dings, a little triangle, twinkles and a shop bell.
-- Id = the sound. Volume = how loud (they were measured, so they all sound about as loud as
-- each other and as the old sounds did next to the music). From / To = play only that part of
-- the recording, in seconds. Speed = its normal pitch. Vary = how much the pitch changes a
-- little every time (0.05 = up to 5%), so sounds heard a lot never sound exactly the same.
GameConfig.Sounds = {
	Pop = { Id = "rbxassetid://9117840021", Volume = 0.4, Vary = 0.05 }, -- a hollow, airy pop
	Chime = { Id = "rbxassetid://9114132512", Volume = 0.42, To = 2 }, -- one xylophone ding: the notes of every jingle below
	Ting = { Id = "rbxassetid://9116224467", Volume = 0.36, Vary = 0.03 }, -- a little triangle
	Bell = { Id = "rbxassetid://9114059123", Volume = 1, To = 0.6 }, -- a shop's desk bell: ding!
	Whoosh = { Id = "rbxassetid://9117173914", Volume = 1.8, Vary = 0.06 }, -- a puff of air
	Rise = { Id = "rbxassetid://9125807267", Volume = 0.5 }, -- a whoosh that rises into a big moment
	Shake = { Id = "rbxassetid://9119034593", Volume = 0.5, From = 0.35, Vary = 0.04 }, -- a wooden shaker: an egg wobbling
	Twinkle = { Id = "rbxassetid://9116396072", Volume = 0.75, From = 0.6, To = 3 }, -- pixie-dust twinkles
	Sparkle = { Id = "rbxassetid://9116397496", Volume = 0.5, From = 2.8, To = 5.4 }, -- a magic flying insect with twinkles
	Burst = { Id = "rbxassetid://9116384485", Volume = 0.3 }, -- a big magic burst
	Buzz = { Id = "rbxassetid://9112881890", Volume = 0.5, Speed = 1.08 }, -- a swarm of bees (it loops; heard near every hive)
}

-- THE JINGLES: what plays at each moment, made from the sounds above. Each line is
-- { sound, start time in seconds, pitch, loudness } (pitch 1 = normal and 2 = one octave
-- higher; loudness 1 = normal). The Chime pitches 1, 1.26, 1.5 and 2 are the notes of a
-- happy chord, so the jingles sound like music. The rarer the bee, the bigger its jingle.
GameConfig.SoundTunes = {
	-- buttons and windows
	Click = { { "Pop", 0, 1.3, 0.8 } }, -- any button
	Open = { { "Whoosh", 0, 1.1, 0.8 }, { "Pop", 0.05, 1.5, 0.6 } }, -- a window opens
	Delete = { { "Pop", 0, 0.75 }, { "Whoosh", 0.03, 0.8, 0.6 } }, -- a bee is deleted
	-- money and honey
	Sell = { { "Bell", 0 }, { "Chime", 0.06, 2, 0.5 } }, -- coins arrive (selling honey, coins from Daily Rewards)
	Coin = { { "Chime", 0, 1.5, 0.45 } }, -- each coin landing on the counter (they climb a scale: SoundScale)
	Jar = { { "Pop", 0, 0.8 }, { "Pop", 0.08, 1.05, 0.8 } }, -- honey jars arrive: bloop-bloop
	JarLand = { { "Pop", 0, 1, 0.5 } }, -- each jar landing on the counter (they climb a scale too)
	Alert = { { "Bell", 0 }, { "Bell", 0.16, 1.12, 0.9 } }, -- the Honey Market's price is great: ding-ding!
	Reward = { { "Twinkle", 0, 1.1, 0.8 }, { "Chime", 0.03, 1.5, 0.8 }, { "Chime", 0.12, 2, 0.8 } }, -- a boost, honey made while away, the Starter Pack
	Buy = { { "Pop", 0, 1.2 }, { "Chime", 0.04, 1.5, 0.8 }, { "Chime", 0.12, 2, 0.8 }, { "Whoosh", 0.18, 1, 0.7 } }, -- a bee is bought and flies off
	Upgrade = { { "Chime", 0, 1 }, { "Chime", 0.07, 1.26 }, { "Chime", 0.14, 1.5 }, { "Chime", 0.21, 2 }, { "Ting", 0.26, 2, 0.6 } }, -- an upgrade is bought
	Celebrate = { { "Pop", 0, 1 }, { "Chime", 0.04, 1 }, { "Chime", 0.11, 1.26 }, { "Chime", 0.18, 1.5 }, { "Chime", 0.25, 2 }, { "Twinkle", 0.1, 1 }, { "Ting", 0.32, 2, 0.7 } }, -- a bigger hive, a pass, a top bee bought
	-- rolling bees
	Shake = { { "Shake", 0, 1 } }, -- a mystery egg appears and wobbles
	GoldEgg = { { "Shake", 0, 1 }, { "Ting", 0.25, 1.5, 0.6 }, { "Shake", 0.9, 1.12 }, { "Ting", 1.15, 1.68, 0.6 }, { "Shake", 1.6, 1.25 }, { "Ting", 1.85, 2, 0.6 } }, -- the golden egg: it climbs (and a Rise whoosh ends on the reveal)
	Shadow = { { "Pop", 0, 0.95, 0.8 } }, -- the egg turns into a shadow
	Reveal1 = { { "Pop", 0, 1 } }, -- a Common bee
	Reveal2 = { { "Pop", 0, 1.05 }, { "Chime", 0.03, 1 } }, -- Uncommon: one note
	Reveal3 = { { "Pop", 0, 1.05 }, { "Chime", 0.03, 1 }, { "Chime", 0.13, 1.5 } }, -- Rare (and the Halloween bees): two notes
	Reveal4 = { { "Pop", 0, 1.05 }, { "Chime", 0.03, 1 }, { "Chime", 0.11, 1.26 }, { "Chime", 0.19, 1.5 }, { "Chime", 0.27, 2 }, { "Twinkle", 0.1, 1, 0.8 } }, -- Epic: four notes and twinkles
	BigReveal = { { "Burst", 0, 1 }, { "Chime", 0.08, 1 }, { "Chime", 0.16, 1.26 }, { "Chime", 0.24, 1.5 }, { "Chime", 0.32, 2 }, { "Chime", 0.4, 2.52 }, { "Chime", 0.48, 3 }, { "Sparkle", 0.2, 1 }, { "Ting", 0.55, 2, 0.7 } }, -- Legendary and the secret bee: the big show
}
GameConfig.SoundScale = { 1, 1.12, 1.26, 1.33, 1.5, 1.68, 1.89, 2 } -- the notes coins and jars climb as they land, one after another
GameConfig.RiseLead = 1.15 -- the Rise whoosh is at its loudest this many seconds after it starts (so it can end right on a reveal)
GameConfig.BuzzNear = 8 -- the bees' buzz at a hive is at full loudness within this many studs...
GameConfig.BuzzFar = 40 -- ...and fades away to nothing by this many studs

-- FLOWER TRIPS ----------------------------------------------------------------
-- Bees fly from the hive to the Flower Garden in the middle of the map, pollinate a
-- flower, and fly home with nectar. One full trip takes this many seconds (before any
-- Bee Speed upgrade). A bee brings back (NectarPerSecond x TripSeconds) jars per trip,
-- so changing this number changes how often jars arrive, not how many you earn per minute.
GameConfig.TripSeconds = 16

-- WORKER BEES -----------------------------------------------------------------
-- When a bee comes home, its honey waits inside the hive. Worker bees carry it from the
-- hive to your Honey Jars, and that is where you grab it. Workers are free: you get one
-- for every two bees working in your hive (always at least one).
GameConfig.WorkersPerBee = 0.5 -- 0.5 = half as many workers as bees
GameConfig.WorkerCarrySeconds = 4 -- how long a worker takes to fly honey from the hive to the jars
GameConfig.WorkerReturnSeconds = 3 -- how long it takes to fly back for more

-- THE HONEY JARS STAND ----------------------------------------------------------
-- There is NO limit on how much honey can wait at your Honey Jars: nothing is ever wasted.
-- The jars on the stand and the honey inside the big sign are only a picture of how much
-- is waiting: each number below is how many jars must be waiting for one more jar to
-- appear on the stand (12 numbers = 12 jars; the sign is brim-full at the last number).
GameConfig.JarsShownSteps = { 1, 10, 25, 50, 100, 200, 350, 500, 750, 1000, 1500, 2500 }

-- OFFLINE HONEY ("Your Bees Earn Offline!") -----------------------------------------
-- Bees keep working while their owner is away from the game. When the player comes back, a
-- "Welcome Back!" window says how long they were away and how many jars the bees made.
-- The jars go to the Honey Jars stand, so the player still grabs them and sells them.
GameConfig.OfflineMaxHours = 4 -- the longest time away that counts (staying away longer earns nothing extra)
GameConfig.OfflineSpeed = 0.5 -- how fast bees work while their owner is away (0.5 = half speed)
GameConfig.OfflineMinSeconds = 60 -- a shorter time away than this gives nothing (no window after a quick rejoin)

-- BOOSTS -----------------------------------------------------------------------------
-- A boost makes something better for a few minutes. Boosts come from Daily Rewards and from the
-- Starter Pack (see THE SHOP further down).
-- A boost that is won goes into the player's Inventory and waits there. It starts when the
-- player presses Use. Using another one of the same kind adds its minutes on top.
-- The minutes only run down while the player is in the game (and a boost does nothing for
-- offline honey).
--   Name:       what players see
--   Multiplier: Honey = every jar the bees bring to the Honey Jars counts this many times
--               Luck  = Queen's Luck is multiplied by this for every roll
GameConfig.Boosts = {
	Honey = { Name = "Double Honey", Multiplier = 2 },
	Luck = { Name = "Double Luck", Multiplier = 2 },
}
GameConfig.BoostOrder = { "Honey", "Luck" } -- the order they are listed in on the screen
GameConfig.BoostMaxMinutes = 120 -- the most minutes of one boost that can be running (Use is refused past this)

-- DAILY REWARDS ------------------------------------------------------------------------
-- One reward a day, seven in a row, then it starts again at day 1. A player who misses a day
-- keeps their place: the next reward simply waits for them.
-- Each line is one day. Give a day exactly ONE of these:
--   Coins = 500                         Honey Coins
--   Bee = "Rare"                        one bee (a name from the left side of THE BEES list)
--   Boost = "Honey", Minutes = 10       a boost (a name from BOOSTS above) for that many minutes
-- The LAST line is the big prize: its card in the window is the tall one.
GameConfig.DailyRewards = {
	{ Coins = 500 }, -- day 1
	{ Boost = "Honey", Minutes = 10 }, -- day 2: Double Honey
	{ Bee = "Rare" }, -- day 3: a Guard Bee
	{ Boost = "Luck", Minutes = 15 }, -- day 4: Double Luck
	{ Coins = 5000 }, -- day 5
	{ Bee = "Epic" }, -- day 6: a Royal Bee
	{ Bee = "Legendary" }, -- day 7: an Emperor Bee
}
-- Hours from collecting one reward until the next can be collected. (20, not 24, so a player
-- who plays at the same time every day never has to wait because they were a bit late yesterday.)
GameConfig.DailyRewardHours = 20

-- THE SHOP (things bought with Robux) ----------------------------------------------------
-- A PASS is bought once, with Robux, and lasts for ever. Every pass is first made on the Roblox
-- website (Creator Hub > this game > Monetization > Passes). The website gives each pass a
-- number: that number goes in Id below. The PRICE is set on the website too. The Shop window
-- reads it from there, so a price is never written in this file.
-- While an Id is 0 the pass is not on sale, and its card is not shown in the real game.
--   Name, Text:  what the Shop window says about it
--   Random:      true for a pass that changes what the Queen's rolls give. Roblox has two rules
--                for those: every bee's chance must be shown before the pass is bought (the
--                Shop's "Bee Chances" button does that), and in a few countries they may not be
--                sold at all (the Shop then says "Not available" on them).
GameConfig.Passes = {
	StarterPack = { Id = 2031986278, Name = "Starter Pack", Text = "A Royal Bee and 4 boosts!", Random = true }, -- (its Double Luck boosts change rolls)
	Rolls = { Id = 2030036311, Name = "+2 Rolls", Text = "2 more bees every roll!", Random = true },
	LuckyQueen = { Id = 2030126311, Name = "Lucky Queen", Text = "Double luck, for ever!", Random = true },
	AutoSell = { Id = 2032862250, Name = "Auto Sell", Text = "Your honey sells itself!" },
	InfiniteInventory = { Id = 2030624310, Name = "Infinite Inventory", Text = "Room for every bee!" },
	VIP = { Id = 2030714311, Name = "VIP", Text = "A crown, a gold name, more honey!" },
}
GameConfig.PassOrder = { "StarterPack", "Rolls", "LuckyQueen", "AutoSell", "InfiniteInventory", "VIP" } -- the order of the cards

-- What each pass does:
-- STARTER PACK: gives everything in this list, once. Each line is ONE of:
--   Bee = "Epic"                                  one bee (a name from the left side of THE BEES list)
--   Boost = "Honey", Minutes = 15, Count = 2      that many boosts of that length, into the Inventory
GameConfig.StarterPack = {
	{ Bee = "Epic" }, -- a Royal Bee
	{ Boost = "Honey", Minutes = 15, Count = 2 }, -- two Double Honey boosts
	{ Boost = "Luck", Minutes = 15, Count = 2 }, -- two Double Luck boosts
}
-- +2 ROLLS: GameConfig.GamePassRollStands more honeycomb stands (see QUEEN BEE above).
-- LUCKY QUEEN: Queen's Luck is multiplied by this for every roll, always. (A Double Luck boost
-- multiplies on top of it.)
GameConfig.LuckyQueenLuck = 2
-- AUTO SELL: honey is sold the moment it reaches the Honey Jars, at the Honey Market's price
-- right then. It sells this often, in seconds. (The owner can switch it off in the Shop window.)
GameConfig.AutoSellSeconds = 1
-- INFINITE INVENTORY: no limit on spare bees. (This number is NOT a limit for players. It only
-- stops a broken save from holding a silly number of bees.)
GameConfig.InfiniteBagLimit = 5000
-- VIP: a crown and a gold name over the player's head, a gold [VIP] in the chat, and every jar
-- the bees bring counts this many times (1.1 = 10% more honey). Offline honey gets it too.
GameConfig.VipHoney = 1.1

-- CARRYING JARS -----------------------------------------------------------------
-- You can carry as many jars as you like. You hold them in a stack above your head.
-- The stack is only a picture of how much you carry: each number below is how many jars
-- you must be carrying for the stack to grow one jar taller (6 numbers = up to 6 tall).
GameConfig.CarryStackSteps = { 1, 25, 75, 200, 500, 1200 }

-- PLAYER ----------------------------------------------------------------------
GameConfig.WalkSpeed = 20 -- how fast players run (Roblox's normal speed is 16). The Walk Speed upgrade multiplies it, up to x1.5.

-- THE FIVE RARITIES -----------------------------------------------------------
-- Every bee belongs to one rarity. The rarity decides how often its bees are rolled, and
-- how special they look.
-- Chance:     how often a roll gives a bee of this rarity. Bigger = more common.
--             (The five chances add up to 100, so each one is a percentage: 2 means 2 rolls
--             in 100, and 0.3 means 3 rolls in 1000.) Queen's Luck multiplies every chance
--             except the first rarity's: with x2 luck, Legendary is 0.6 and Epic is 4.
--             The first rarity gets whatever is left of the 100, so the more luck a player
--             has, the fewer Common bees they see (none at all from about x3.2 luck).
-- Color:      the colour its bees' names are written in, and of their window on the hive
-- Sparkles:   true makes its bees glitter
-- Rainbow:    true writes its bees' names in moving rainbow colours
-- BigReveal:  true gives the big show when one hatches on a stand: a golden egg that shakes
--             for longer, then a flash, confetti and a fanfare
-- Trail:      true gives its bees a rainbow sparkle trail while they fly
-- (Auto Roll's stop list in the Settings window shows these five names.)
GameConfig.RarityOrder = { "Common", "Uncommon", "Rare", "Epic", "Legendary" } -- most common first

GameConfig.Rarities = {
	Common = { DisplayName = "Common", Chance = 68.2, Color = Color3.fromRGB(255, 200, 40) },
	Uncommon = { DisplayName = "Uncommon", Chance = 24.5, Color = Color3.fromRGB(90, 225, 110) },
	Rare = { DisplayName = "Rare", Chance = 5, Color = Color3.fromRGB(80, 170, 255), Sparkles = true },
	Epic = { DisplayName = "Epic", Chance = 2, Color = Color3.fromRGB(176, 96, 255), Sparkles = true }, -- 1 roll in 50
	Legendary = { -- 3 rolls in 1000 (about 1 in 333)
		DisplayName = "Legendary",
		Chance = 0.3,
		Color = Color3.fromRGB(255, 140, 30),
		Sparkles = true,
		Rainbow = true,
		BigReveal = true,
		Trail = true,
	},
}

-- LIMITED is a sixth rarity, for bees that can only be got for a short time (the Halloween Egg).
-- It is NOT in RarityOrder above on purpose: the Queen never rolls a Limited bee, and Auto
-- Roll's stop list in Settings does not show it. (Its Chance is not used.)
GameConfig.Rarities.Limited = { DisplayName = "Limited", Chance = 0, Color = Color3.fromRGB(255, 122, 24), Sparkles = true }

GameConfig.BigRevealEggSeconds = 2.6 -- how long the golden egg shakes before a BigReveal bee hatches

-- THE BEES --------------------------------------------------------------------
-- Every rarity has two bees. The second one is a little better, a little dearer and harder
-- to roll.
-- Rarity:          which of the five rarities above the bee belongs to
-- BeeName:         the name players see. Change it freely.
-- NectarPerSecond: jars one bee makes per second on average (1 nectar = 1 jar)
-- Price:           Honey Coins to buy this bee from the honeycomb stand after a roll.
-- Share:           how its rarity's chance is split between the bees of that rarity.
--                  Worker 2 and Builder 1 means: out of 3 Common rolls, 2 are Worker Bees
--                  and 1 is a Builder Bee.
-- Color:           the colour of the bee's body. EVERY BEE NEEDS ITS OWN COLOUR: the game
--                  tells the bees apart by it.
-- Outfit:          what the bee wears. The pieces were made in Blender and live in
--                  ReplicatedStorage.BeeEmpire.BeeMeshes. {} = a plain bee.
-- Glow:            (optional) outfit pieces that glow, and the colour they glow in
-- Size:            (optional) how big it is next to a normal bee. 1.12 = a bit bigger.
-- The names on the left (Common, Builder...) are what the game SAVES. Never rename those,
-- or players lose their bees. (The first bee of each rarity is saved under its rarity's
-- name, because at first there was only one bee per rarity.)
-- (Do not mix up the "Worker Bee" with the little carrier bees that fly honey from the hive
-- to the jars. The scripts call those carriers "workers".)
GameConfig.BeeOrder = { "Common", "Builder", "Uncommon", "Explorer", "Rare", "Knight", "Bat", "Epic", "Wizard", "Ghost", "Legendary", "Galaxy", "PumpkinKing" } -- weakest to strongest
-- (Bat, Ghost and PumpkinKing are LIMITED bees: the Queen never rolls them. See THE HALLOWEEN EGG.)

GameConfig.Bees = {
	-- COMMON
	Common = {
		Rarity = "Common",
		BeeName = "Worker Bee",
		NectarPerSecond = 0.5,
		Price = 25,
		Share = 2,
		Color = Color3.fromRGB(255, 200, 40),
		Outfit = {},
	},
	Builder = {
		Rarity = "Common",
		BeeName = "Builder Bee",
		NectarPerSecond = 0.75,
		Price = 40,
		Share = 1,
		Color = Color3.fromRGB(214, 232, 64),
		Outfit = { "BuilderGear" }, -- hard hat, tool belt and hammer
	},
	-- UNCOMMON
	Uncommon = {
		Rarity = "Uncommon",
		BeeName = "Scout Bee",
		NectarPerSecond = 1.5,
		Price = 200,
		Share = 2,
		Color = Color3.fromRGB(90, 225, 110),
		Outfit = { "ScoutGear" }, -- goggles and a backpack
	},
	Explorer = {
		Rarity = "Uncommon",
		BeeName = "Explorer Bee",
		NectarPerSecond = 2.25,
		Price = 325,
		Share = 1,
		Color = Color3.fromRGB(40, 200, 186),
		Outfit = { "ExplorerGear" }, -- safari hat, spyglass and a rolled map
	},
	-- RARE
	Rare = {
		Rarity = "Rare",
		BeeName = "Guard Bee",
		NectarPerSecond = 5,
		Price = 1200,
		Share = 2,
		Color = Color3.fromRGB(80, 170, 255),
		Outfit = { "GuardGear" }, -- helmet, shield and spear
	},
	Knight = {
		Rarity = "Rare",
		BeeName = "Knight Bee",
		NectarPerSecond = 7.5,
		Price = 2000,
		Share = 1,
		Color = Color3.fromRGB(92, 108, 242),
		Outfit = { "KnightGear" }, -- silver helmet with a red plume, chest plate, sword and shield
	},
	-- EPIC
	Epic = {
		Rarity = "Epic",
		BeeName = "Royal Bee",
		NectarPerSecond = 15,
		Price = 5000,
		Share = 2,
		Color = Color3.fromRGB(176, 96, 255),
		Outfit = { "RoyalGear" }, -- red cape and a gold band
	},
	Wizard = {
		Rarity = "Epic",
		BeeName = "Wizard Bee",
		NectarPerSecond = 22,
		Price = 8000,
		Share = 1,
		Color = Color3.fromRGB(232, 84, 204),
		Outfit = { "WizardGear" }, -- tall starry hat, cape and wand
	},
	-- LEGENDARY
	Legendary = {
		Rarity = "Legendary",
		BeeName = "Emperor Bee",
		NectarPerSecond = 50,
		Price = 30000,
		Share = 2,
		Color = Color3.fromRGB(255, 140, 30),
		Outfit = { "EmperorGear", "Crown" }, -- white-and-gold cape and a crown
		Size = 1.12,
	},
	Galaxy = {
		Rarity = "Legendary",
		BeeName = "Galaxy Bee",
		NectarPerSecond = 75,
		Price = 50000,
		Share = 1,
		Color = Color3.fromRGB(52, 44, 120),
		Outfit = { "GalaxyGear" }, -- starry purple cape
		Glow = { GalaxyGlow = Color3.fromRGB(110, 225, 255) }, -- a ring of light, a big star and little stars
		Size = 1.12,
	},
}

-- LIMITED BEES (Halloween 2026). They only come out of the Halloween Egg (see below), so they
-- have no Price. A bee may carry its own Rainbow / BigReveal / Trail (otherwise it takes its
-- rarity's). Secret = true: the bee is shown as "???" until the player owns one.
-- NEVER remove these three, even after Halloween: players keep their bees for ever.
GameConfig.Bees.Bat = {
	Rarity = "Limited",
	BeeName = "Bat Bee",
	NectarPerSecond = 12,
	Color = Color3.fromRGB(96, 52, 130),
	Outfit = { "BatGear" }, -- bat ears, bat wings and little fangs
}
GameConfig.Bees.Ghost = {
	Rarity = "Limited",
	BeeName = "Ghost Bee",
	NectarPerSecond = 45,
	Color = Color3.fromRGB(236, 240, 255),
	Outfit = { "GhostGear" }, -- a white sheet with a hood, and a tiny ghost friend
}
GameConfig.Bees.PumpkinKing = {
	Rarity = "Limited",
	BeeName = "Pumpkin King Bee",
	NectarPerSecond = 500,
	Color = Color3.fromRGB(44, 38, 56),
	Outfit = { "PumpkinKingGear" }, -- a pumpkin helmet with a crown, and a purple cape
	Glow = { PumpkinGlow = Color3.fromRGB(255, 196, 60) }, -- the helmet's carved face, and sparks
	Size = 1.3,
	Secret = true,
	Rainbow = true,
	BigReveal = true,
	Trail = true,
}

-- THE HALLOWEEN EGG (a limited-time event) --------------------------------------------------
-- A big pumpkin egg stands in a spooky corner next to the Flower Garden. A player carries
-- honey jars to it and presses E: the egg takes JarCost jars and hatches ONE of its bees.
-- When the end day comes, the egg and its corner vanish by themselves (nothing needs to be
-- changed here). Players keep the bees they got.
--   Ends:       the egg leaves at the START of this day (world clock, UTC). With Day = 3 its
--               last day is the 2nd.
--   JarCost:    jars handed over for one roll (jars the player is carrying)
--   LuckCounts: true = Queen's Luck, Double Luck boosts and the Lucky Queen pass change the
--               chances, the same way they do at the Queen. false = the same for everyone.
--   Bees:       most common first. Chance is a percentage (0.005 = 1 roll in 20,000). Luck
--               multiplies every chance except the first bee's, and the first bee gets
--               whatever is left of 100.
--   HatchSeconds: how long the egg shakes before the bee pops out
GameConfig.HalloweenEgg = {
	Name = "Halloween Egg",
	Ends = { Year = 2026, Month = 11, Day = 3 },
	JarCost = 1000,
	LuckCounts = true,
	Bees = {
		{ Bee = "Bat", Chance = 0 }, -- gets what is left: about 90%
		{ Bee = "Ghost", Chance = 10 },
		{ Bee = "PumpkinKing", Chance = 0.005 }, -- 1 in 20,000: about 20 million jars with no luck at all
	},
	HatchSeconds = 2.2,
}

-- SAVING AND SAFETY (you will rarely need to change these) ---------------------
GameConfig.DataStoreName = "BeeEmpire_PlayerData_v1" -- changing this name wipes everyone's progress
GameConfig.AutosaveSeconds = 90 -- how often progress is saved while playing
GameConfig.InteractDistance = 10 -- how close (in studs) a player must be to use a station
GameConfig.ActionCooldown = 0.2 -- seconds a player must wait between station uses

-- HELPERS (not balance numbers; these just read the tables above) ------------------

-- The settings for a hive level, e.g. GameConfig.GetHive(2).Capacity
function GameConfig.GetHive(level: number)
	return GameConfig.HiveLevels[math.clamp(math.floor(level), 1, #GameConfig.HiveLevels)]
end

-- The biggest hive's capacity (used to know how many slots can ever exist)
GameConfig.MaxHiveCapacity = 0
for _, hive in GameConfig.HiveLevels do
	GameConfig.MaxHiveCapacity = math.max(GameConfig.MaxHiveCapacity, hive.Capacity)
end

-- Each bee also carries a few things copied from its rarity, so the scripts can read them
-- straight off the bee: bee.DisplayName is "Common", bee.RarityColor is the name colour.
for _, bee in GameConfig.Bees do
	local rarity = GameConfig.Rarities[bee.Rarity]
	bee.DisplayName = rarity.DisplayName
	bee.RarityColor = rarity.Color
	-- (a bee may set these itself; otherwise it takes its rarity's)
	bee.Sparkles = (if bee.Sparkles ~= nil then bee.Sparkles else rarity.Sparkles) == true
	bee.Rainbow = (if bee.Rainbow ~= nil then bee.Rainbow else rarity.Rainbow) == true
	bee.BigReveal = (if bee.BigReveal ~= nil then bee.BigReveal else rarity.BigReveal) == true
	bee.Trail = (if bee.Trail ~= nil then bee.Trail else rarity.Trail) == true
end

-- Boosts waiting in an Inventory are counted per kind AND length, under a name like
-- "Honey_10" (a Double Honey boost of 10 minutes). These two turn that name into its
-- parts and back. ReadBoostItemKey gives nil for a name that makes no sense.
function GameConfig.BoostItemKey(kind: string, minutes: number): string
	return kind .. "_" .. math.floor(minutes)
end

function GameConfig.ReadBoostItemKey(key: any): (string?, number?)
	if typeof(key) ~= "string" then
		return nil, nil
	end
	local kind, minutesText = key:match("^(%a+)_(%d+)$")
	local minutes = tonumber(minutesText)
	if kind and GameConfig.Boosts[kind] and minutes and minutes >= 1 and minutes <= 600 then
		return kind, minutes
	end
	return nil, nil
end

-- THE CHANCES OF A ROLL. (The Queen rolls with these, and the Shop's "Bee Chances" window
-- shows them, so the two can never disagree.)
-- The bees of each rarity, weakest first: { Common = { "Common", "Builder" }, ... }
GameConfig.BeesOfRarity = {}
for _, beeName in GameConfig.BeeOrder do
	local rarityName = GameConfig.Bees[beeName].Rarity
	GameConfig.BeesOfRarity[rarityName] = GameConfig.BeesOfRarity[rarityName] or {}
	table.insert(GameConfig.BeesOfRarity[rarityName], beeName)
end

-- The bees the Queen can roll, weakest first (every bee except the Limited ones).
GameConfig.QueenBees = {}
for _, beeName in GameConfig.BeeOrder do
	if table.find(GameConfig.RarityOrder, GameConfig.Bees[beeName].Rarity) then
		table.insert(GameConfig.QueenBees, beeName)
	end
end

-- How likely each rarity is with this much luck: { Common = 36.4, Uncommon = 49, ... }, and
-- what the numbers add up to. Luck multiplies the Chance of every rarity except the most
-- common one, so x2 luck really is twice as many Legendary bees. The rarest are handed their
-- share first and the most common rarity gets whatever is left, so the numbers always add up
-- to the same total: the more luck, the fewer Common bees (and with a huge amount of luck,
-- the fewer Uncommon ones).
function GameConfig.RarityChances(luck: number): ({ [string]: number }, number)
	local chances: { [string]: number } = {}
	local total = 0
	for _, rarityName in GameConfig.RarityOrder do
		if GameConfig.BeesOfRarity[rarityName] then
			total += GameConfig.Rarities[rarityName].Chance
		end
	end
	local left = total
	for index = #GameConfig.RarityOrder, 1, -1 do
		local rarityName = GameConfig.RarityOrder[index]
		local chance = 0
		if GameConfig.BeesOfRarity[rarityName] then
			chance = if index == 1 then left else math.min(left, GameConfig.Rarities[rarityName].Chance * math.max(1, luck))
		end
		chances[rarityName] = chance
		left -= chance
	end
	return chances, total
end

-- The chance of each BEE in one roll with this much luck, in percent: { Common = 45.47, ... }.
-- (A rarity's chance is split between its bees by their Share.) The ten numbers add up to 100.
function GameConfig.BeeChances(luck: number): { [string]: number }
	local chances, total = GameConfig.RarityChances(luck)
	local result: { [string]: number } = {}
	for rarityName, list in GameConfig.BeesOfRarity do
		if chances[rarityName] == nil then
			continue -- (a rarity the Queen never rolls: Limited)
		end
		local shares = 0
		for _, beeName in list do
			shares += GameConfig.Bees[beeName].Share or 1
		end
		for _, beeName in list do
			local share = GameConfig.Bees[beeName].Share or 1
			result[beeName] = if total > 0 and shares > 0 then chances[rarityName] / total * 100 * share / shares else 0
		end
	end
	return result
end

-- THE HALLOWEEN EGG'S CLOCK AND CHANCES.
-- The moment the egg leaves, as a number of seconds on the world clock (what os.time() gives).
function GameConfig.EggEndsAt(egg): number
	local ends = egg.Ends
	return os.time({ year = ends.Year, month = ends.Month, day = ends.Day, hour = 0, min = 0, sec = 0 })
end

-- The chance of each of an egg's bees in one roll with this much luck, in percent:
-- { Bat = 79.99, Ghost = 20, PumpkinKing = 0.01 }. The rule is the Queen's: luck multiplies
-- every chance except the most common bee's, the rarest are handed their share first, and
-- the most common bee gets whatever is left of 100.
function GameConfig.EggChances(egg, luck: number): { [string]: number }
	local times = if egg.LuckCounts then math.max(1, luck) else 1
	local result: { [string]: number } = {}
	local left = 100
	for index = #egg.Bees, 1, -1 do
		local entry = egg.Bees[index]
		local chance = if index == 1 then left else math.min(left, entry.Chance * times)
		result[entry.Bee] = chance
		left -= chance
	end
	return result
end

-- The rarity of a bee ("Builder" gives the Common rarity). A rarity's own name works too.
function GameConfig.RarityOf(name: string)
	local bee = GameConfig.Bees[name]
	return GameConfig.Rarities[if bee then bee.Rarity else name]
end

return GameConfig
