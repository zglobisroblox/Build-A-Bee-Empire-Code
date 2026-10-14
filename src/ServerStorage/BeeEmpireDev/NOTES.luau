--[[
==============================================================================
 BEE EMPIRE - PROJECT NOTES            (this file does nothing; it is just notes)
==============================================================================

STATUS (3 Oct 2026): rolling bees at your own Queen, bees flying to a shared
Flower Garden, and an Upgrade Shop on every plot are built and tested in Studio.
Saving is written but still NOT tested for real.

THE GAME LOOP
	Press E at the Queen on your plot to ROLL a random bee (25 coins, first one
	free). It pops out of the pink nursery hive behind her and goes to work in
	YOUR BEEHIVE (or into your bag if the hive is full) -> working bees fly to the
	Flower Garden in the middle of the map, pollinate a flower and fly home ->
	each finished trip adds jars to your blue station -> Collect -> Sell at the
	red Honey Market -> roll more bees / upgrade your hive.

THE PLOT (112 x 88 studs)
	A lamp-lit avenue runs from the entrance arch to the beehive at the back.
	Left: blue collection station and red Honey Market.
	Right: the Queen's roll area with the pink nursery hive, and right beside it
	the teal Upgrade Shop (builder bee, price board above the roof).

THE BEEHIVE (GameConfig.HiveLevels)
	One hive per player. 5 levels: Tiny (arm-sized), Cozy, Busy, Grand, Royal.
	Each level holds more bees (2 / 4 / 6 / 9 / 12) and its station stores more jars.
	Press E at the hive (or the My Hive button, or key B) for the My Hive window.
	Bigger hives are BOUGHT at the Upgrade Shop.

THE UPGRADE SHOP (GameConfig.Upgrades + GameConfig.UpgradeOrder)
	Press E at the shop for the Upgrade Shop window. Sells:
	  Beehive (more bees), Backpack (carry more jars), Queen's Luck (better
	  rolls), Bee Speed (faster flower trips = more jars per minute).
	The server only sells while the player stands at their own shop.
	ReplicatedStorage.BeeEmpire.Upgrades has the shared level / price helpers.

FLOWER TRIPS (GameConfig.TripSeconds)
	The server keeps a trip clock per working bee (HiveService). A bee brings
	NectarPerSecond x TripSeconds jars each trip. The flying you see is drawn on
	each player's device (WorldFX) from the same clock.

WHERE EVERYTHING LIVES
	ReplicatedStorage.BeeEmpire
		GameConfig        ALL balance numbers (rarities, roll cost, hive levels...).
		HiveModelFactory  The look of each hive level (placeholder Parts).
		BeeModelFactory   Placeholder bee.     PropFactory  Egg / jar / coin props.
		NumberFormat      1500 -> "1.5K".
		Remotes           Notify, Effect (server->player); PlaceBee(rarity, slot?),
		                  RemoveBee(slot), EquipBest, SellBee(rarity), BuyUpgrade(id)
		                  (player->server). Roll / Collect / Sell use press-E buttons.
	ServerScriptService.BeeEmpire
		Main              Starts the game; checks every request.
		Services.HiveService        Hive models, bee trips, deliveries, upgrades.
		Services.BeeService         Rolling (with luck), place / remove / equip best / sell.
		Services.UpgradeService     The Upgrade Shop: buying, and its price board.
		Services.ProductionService  Jars, Collect, Sell, jar on your back.
		Services.DataService / PlotService / Notifier
	StarterPlayer.StarterPlayerScripts.BeeEmpireClient   (all UI is built by code)
		UIKit       The bubbly style: buttons, windows, cards, icons, sounds.
		State       Reads player attributes; works out the hint + arrow target.
		HUD         Counters (left), My Hive / Equip Best (right), hint (bottom).
		HivePanel   My Hive window.     UpgradePanel   Upgrade Shop window.
		Effects     Toasts, flying coins/jars, new-bee cards, hive-upgrade reveal.
		WorldFX     Honey press-E buttons, your-hive glow, arrows, roll animation,
		            bees flying to the flowers.
		ClientMain  Starts everything.
	Workspace.FlowerGarden (Flowers.FlowerN with a BeeSpot attribute),
	Workspace.Plots.Plot1-6 (HiveAnchor, HiveSpot, Queen, CollectStation, Market),
	Workspace.Map
	ServerStorage.BeeEmpireDev.PlotBuilder   Dev tool that rebuilds the map:
		require(game.ServerStorage.BeeEmpireDev.PlotBuilder).BuildAll()

SAVE DATA
	Coins, HiveLevel, Upgrades (levels), JarsCarried, JarsStored, Bees (bag),
	Cells (hive slots).

REVIEW AGENTS
	Bob = strict QA reviewer. Donny = 13-year-old player. Donny's first verdict
	(before rolling + flower trips) was 4/10: needs more bee variety, something
	to do while bees work, rebirth, sound.

TO DO BEFORE REAL PLAYERS JOIN
	[x] Publish the place.
	[ ] Game Settings > Security > Enable Studio Access to API Services (test saving).
	[ ] Game Settings > Places > Server size = 6 (there are only 6 plots!).
	[ ] Test saving: earn coins, upgrade the hive, stop, play again.
	[ ] Session locking in DataService.

IDEAS (not started)
	- More shop upgrades: auto roll, multi roll, jar value, station storage.
	- Sell station price multiplier that changes over time; leaderboards.
	- More bee rarities and a bee index; rebirth; music and sounds.
	- Donny's small fixes: exact coins under 10K, sell-all, growing jar pile.
==============================================================================
]]

--[[
	TOY-BRICK RESTYLE (3 Oct 2026) - the look now follows Build An Ant Empire, with our own
	bee-themed art (nothing was copied from that game; only the style).

	What changed
	- UIKit: flat bright buttons with a dark outline and a darker lip; windows have a coloured
	  title bar (picture, title, coins, red X) over a dark see-through body; no screen dimming.
	  Kit.Bands / Kit.SetBands make the two-tone fills; Kit.LockIcon is the gold padlock.
	- HUD: Equip Best + My Hive sit in the Roblox top bar (ScreenGui "BeeEmpireTopBar", centred on
	  the screen); the hint is a line of outlined text under them; coins (big, green), jars and
	  speed are bottom-left (middle-left on phones). The whole HUD hides while a window is open.
	- Messages (toasts) are plain outlined text under the hint; the "NEW BEE!" card is at the
	  bottom of the screen; press-E prompts are dark boxes.
	- Upgrade Shop window: one bright panel per upgrade with "Holds 2 > 4 bees" and a price button.
	- World: every big block face has a square-stud picture (ReplicatedStorage.BeeEmpire.Studs -
	  one image id, change it there and re-run PlotBuilder). Grass patches, orange stepped paths,
	  block trees and flowers, a fence round the garden, lilac cliffs round the map, blue haze.
	- Plots: jewelled Queen pedestal, leaning "ROLL A BEE" sign, odds screen with red frame and
	  yellow bulbs, upgrade board with a panel per upgrade (Upgrades.Board.Face.Panel_<id>;
	  UpgradeService fills Value and Price.Label, WorldFX turns the pill green/grey for the owner).
	- Bees and the beehive are built from blocks now (BeeModelFactory, HiveModelFactory).
	- Upgrades.DescribeChange / DescribeChangeShort give the "2 > 4" texts.
	- WorldFX now copes with StreamingEnabled (plot parts arriving late), so "Your Hive!" shows.

	Safety net: ServerStorage.BeeEmpireDev.Backup_OldLook holds the scripts from before the
	restyle (UIKit, HUD, Effects, WorldFX, HivePanel, UpgradePanel, PlotBuilder, UpgradeService,
	HiveModelFactory, BeeModelFactory). To go back, copy a backup's text over the live script and,
	for the map, run the old PlotBuilder's BuildAll().

	Seen in the reference but NOT built (ideas for later, each is a new feature)
	- a beehive shaped like a stepped pyramid with one coloured doorway per bee, padlocks on
	  locked spots and "Empty" on free ones
	- three bee offers on stalls at the Queen (buy one, carry it home), "New!!" tags
	- a Honey Market price that changes every few seconds (red-to-green bar and countdown)
	- Bee Index, Daily Rewards, Playtime Rewards, Settings/Codes, offline earnings windows
	- "<Name>'s Hive" bubbles with the owner's picture and a light beam over each plot

	Testing tip: loadstring(script.Source) in the command bar checks a script still compiles.
	Careful when patching text: "return Upgrades" also matches "return Upgrades.Describe(...)".
]]

--[[
	WORKER BEES AND HONEY JARS (4 Oct 2026) - how honey reaches the player now

	flowers -> HIVE -> worker bee -> HONEY JARS -> the player grabs them -> Honey Market

	- A bee comes home from the flowers: its honey waits inside the hive (HiveService, "waiting").
	- Worker bees carry it to the plot's Honey Jars pad (the model is still called CollectStation;
	  workers aim at CollectStation.DropSpot). Workers are free and automatic: half as many as the
	  bees working in the hive, at least one (GameConfig.WorkersPerBee). A flight to the jars takes
	  GameConfig.WorkerCarrySeconds, the flight back GameConfig.WorkerReturnSeconds.
	- Honey only counts in the jars when the worker lands (HiveService.StepHoney, called twice a
	  second by ProductionService.Step). (There used to be a limit per hive level, MaxJarsStored. It was removed on
	  4 Oct 2026: see NO JAR LIMIT at the bottom.)
	- Press E once at the jars ("Grab Jars") to take everything you can carry (the Backpack upgrade
	  is still the limit). The server puts a Model called HoneyStack in the character: a stack of
	  jars welded above the head, up to GameConfig.MaxJarsShownCarried tall, with a sign.
	- Arms up: every player's screen turns the shoulder joints of anyone who has a HoneyStack
	  (WorldFX, section 5c, on RunService.PreSimulation). It sets the joint's Transform, which works
	  on both old (Motor6D) and new (AnimationConstraint) avatars. Changing C0 or the joint's
	  attachments from the server does NOT work on the new avatars.
	- Worker bees are plain block bees (BeeModelFactory with Cargo = true) tagged "BeeWorker".
	  The server sets attributes on each (State, LegStart, LegSeconds, Amount, HivePoint, JarPoint)
	  and each screen draws it flying (WorldFX, section 5b). The "+N" pops at the jars when a
	  worker lands.
	- The scripts from before this change are in ServerStorage.BeeEmpireDev.Backup_BeforeWorkerBees.

	Not seen yet with my own eyes: the laptop was locked while this was built, so the 3D picture
	could not be checked (the numbers and states were all tested in Play mode). Worth a look:
	the pad, the worker's size and colour, how tall the stack is, the arms.
	The upgrade is still called "Backpack" even though jars are now held up.
]]

--[[
	ROUND 2 ON THE HONEY FLOW (4 Oct 2026, later the same day) - after the owner played it

	- NO BACKPACK. Carrying is unlimited. The Backpack upgrade is gone (GameConfig.Upgrades,
	  UpgradeOrder = Hive, Luck, BeeSpeed), the Player attribute MaxJarsCarried is gone, and
	  "Grab Jars" takes every jar in the Honey Jars. Ignore what the section above says about
	  the Backpack limit and GameConfig.MaxJarsShownCarried: the stack's height now comes from
	  GameConfig.CarryStackSteps (how many jars you must carry for the stack to grow by one).
	- The jar stack is fixed to the CHEST (UpperTorso / Torso), not the head, and the client
	  holds the whole arm stiff (shoulder, elbow and wrist joints) leaning in under the bottom
	  jar. Stack and arms hang off the same body part, so they move together. (The owner said
	  the first version's arms "sway back a lot and look disjointed".)
	- Worker bees no longer hover in one spot while they wait: they fly loops round the hive
	  (attributes HiveMiddle and LoopRadius on each worker). When honey is ready they swoop to
	  the hive door, the little jar appears under them, and they fly to the Honey Jars.
	- The upgrade board on each plot now has three panels; an odd one out sits in the middle
	  of the bottom row.
	- Rebuilding the map from the command bar: Studio remembers shared modules for the whole
	  session, so after changing GameConfig the PlotBuilder can still see the OLD numbers.
	  Close and reopen the place first, or build with fresh copies of ReplicatedStorage.BeeEmpire.
	- Scripts from before this round: ServerStorage.BeeEmpireDev.Backup_BeforeUnlimitedCarry.
]]

--[[
	NEW STANDS (4 Oct 2026, evening) - the owner sent two pictures of the ant game's stands

	- Both stands moved further left and each FACES THE MIDDLE OF THE PLOT (PlotBuilder:
	  standFrame, standPad, honeyCrate). They sit at plot spots (-45, -14) and (-45, 18).
	- Honey Market (model "Market"): tan pad with a stepped lime edge, a table (the part is
	  still called Counter and holds the Sell button), gold on and beside it, dark crates, a
	  shelf of honey and a shopkeeper bee in a top hat (ShopBee). No awning. No price multiplier
	  yet: the owner said to leave that for later.
	- Honey Jars (model "CollectStation"): pad with a stepped yellow edge, crates with a honey-jar
	  picture, earth blocks with grass, and a big jar-shaped sign. CollectStation.Sign.Face.Amount
	  shows the honey waiting (ProductionService.updateStation writes it). The twelve Jars still
	  appear as honey arrives: six on the crates, six on the floor in front.
	- Scripts from before: ServerStorage.BeeEmpireDev.Backup_BeforeNewStands.
	HONEY JARS STAND, MORE DETAIL (4 Oct 2026, later)
	- The floating "Honey Jars / 8 of 150 jars" text above the stand is gone (the user asked
	  for it to be deleted). CollectStation.Table no longer has an Info sign.
	- The jar-shaped sign now does that job. CollectStation.Sign.Face has:
	    Amount = the big number
	    Honey  = a honey-coloured frame that gets taller the more honey is waiting
	  ProductionService.updateStation sets both (SIGN_HONEY_EMPTY / SIGN_HONEY_FULL are how
	  much of the sign the honey covers with nothing waiting, and with every jar showing).
	- Each jar in CollectStation.Jars now has a Lid AND a Label. The game shows and hides every
	  part inside a jar together with the jar, so more pieces can be added without code changes.
	- New decoration, all built in PlotBuilder: crates with corner posts and lids, honeycomb
	  chunks on the top crate, a big honey pot with a dipper and a puddle, a leaning slab of
	  honeycomb, flowers and grass on the earth blocks, honey dripping off the sign and the
	  earth, and a lantern hanging on each side of the sign.
	- The "go here" arrow for Honey Jars sits a little lower (WorldFX findTarget, 21.5).
	- Scripts from before this change: ServerStorage.BeeEmpireDev.Backup_BeforeJarsDetail.

	NO JAR LIMIT (4 Oct 2026, the user: "dont make 150 jars the limit, have no limit to it")
	- Any amount of honey can wait at the Honey Jars now. Nothing is wasted any more.
	- GameConfig.HiveLevels no longer has MaxJarsStored. HiveService.StepHoney(plot) no longer
	  takes a "room" number. DataService only keeps a sanity cap on the saved amount.
	- Because there is no "full", the stand cannot show "N of M". Instead
	  GameConfig.JarsShownSteps says how many jars must be waiting for each of the stand's 12
	  jars to appear; the honey in the sign rises in the same 12 steps. It is only a picture.
	- Removed with the limit: the red number and "FULL!" tag on the sign, the on-screen hint
	  "Your Honey Jars are FULL!", and the "Honey Jars hold N" line in the My Hive window.
	  The hint "Grab your honey jars!" still appears once a trip is worth it.
	- Scripts from before this change: ServerStorage.BeeEmpireDev.Backup_BeforeNoJarLimit.
	ROLL AREA: FREE ROLLS, BUY FROM THE HONEYCOMB STAND (4 Oct 2026, evening)
	- The owner's choices: rolling is FREE (2 second wait, GameConfig.RollCooldown); bees cost
	  25 / 200 / 1,200 (GameConfig.Rarities[...].Price); the first bee is free (FirstBeeFree: a
	  player with no bees is offered the most common bee at price 0); a bought bee flies to the
	  hive or bag by itself; only 1 stand for now (GameConfig.RollStands), more by an upgrade later.
	- BeeService.Roll puts an OFFER on Queen.Stands.Stand1 (attributes OfferStart, OfferRarity,
	  OfferPrice, OfferNew; kept in server memory only). BeeService.BuyOffer (prompt Action
	  "BuyBee" on Stand.BuySpot, wired in Main) checks reveal time, coins and room, then gives
	  the bee and fires the "Bought" effect. If hive AND bag are full it refuses and charges nothing.
	- WorldFX section 4 draws the show on every player's screen from those attributes: mystery
	  egg (RollEggSeconds), black shadow (RollShadowSeconds), then the bee, name, rarity, price
	  pill and a "New!" tag. It also switches the Buy button on only when the bee is revealed.
	- State: RollCost is gone; State.Offer / CheapestBeePrice / BeeWouldHelp drive the hints
	  ("Take your FREE bee...", "Buy the bee on your honeycomb stand!", arrow target "Stand").
	- The arrow now keeps looking for its target every half second (the Queen's parts reach a
	  player's device late because of streaming, and the arrow used to stay hidden).
	- Map: PlotBuilder builds the roll area on a pad at standFrame(37, -13) (rollStand, hexPlate,
	  combFace helpers). The nursery hive is gone. The Upgrade Shop MOVED to standFrame(39, 24)
	  and faces the middle (its pieces go through shopAt(); its look is unchanged).
	- Play-tested with one player: free first bee, too-early buy refused, cooldown, too few coins
	  refused, paid buy, hive full -> bag, bag full refused, all three stages, real E buttons.
	- Reviewed on 5 Oct 2026 (3 reviewers + a sceptic). Everything they confirmed was small and
	  is fixed: the hint no longer gives the roll away before the reveal (a paid offer is only
	  shared with the player's screen after it hatches); the "roll for a better bee" hint stays
	  quiet while a helpful bee is waiting on the stand; "Your bee bag is full!" shows instead of
	  "Buy the bee" when there is no room; a double tap on Buy no longer shows a message; the
	  banner trim no longer flickers. The wider odds board and the arrow retry were play-tested.
	- WATCH OUT if GameConfig.RollStands ever becomes 3: the third stand spot (-9.6, -5.6 in
	  STAND_SPOTS) overlaps the Queen's pedestal. Move that spot first.
	- Not tested: two players at once.
	- Scripts from before this change: ServerStorage.BeeEmpireDev.Backup_BeforeRollStand.
	NEW UI LOOK (5 Oct 2026)
	- The whole on-screen UI was restyled after the owner's Figma design (file "Build A Bee
	  Empire - UI", key DN7FnIgdM4ndDqPJ1Vxqg6: a kit sheet and three screen mock-ups). Dark
	  see-through windows, two-colour bars and buttons, thick dark outlines, FredokaOne.
	- All sizes in the client scripts are written for a 1280 x 720 screen (touch: 1040 x 580)
	  and scaled by UIKit. Outlines get thinner on small screens (Kit.Stroke), and shrinking
	  text may go down to 7 pixels so nothing is cut off on phones.
	- Checked on a desktop-size screen and on an iPhone 7 in Studio's device simulator.
	- Scripts from before this change: ServerStorage.BeeEmpireDev.Backup_BeforeNewUI.
	REAL PICTURES INSTEAD OF DRAWN ICONS (8 Oct 2026)
	- The owner asked for "actual images" like Build An Ant Empire / Grow a Garden, and chose:
	  keep the approved design, make the pictures from OUR OWN 3D models, upload them to their
	  Roblox account. Nothing was taken from the other games.
	- 14 pictures (512 x 512, see-through background, dark ink outline): Coin, Jar, Lock,
	  Arrow, Clover, SpeedBee, one bee per kind, one hive per level. Their Roblox picture numbers
	  are all in ReplicatedStorage.BeeEmpire.UIImages. The same pictures are in the Figma file
	  (page "UI Kit", frame "Real pictures").
	- UIKit's icon helpers (CoinIcon, JarIcon, BeeIcon, HiveIcon, ArrowIcon, CloverIcon,
	  SpeedIcon, LockIcon) now just show those pictures, so every menu changed at once. UIKit
	  fetches all of them when the game starts. The big "new bee" reveal card still shows the
	  live spinning 3D model.
	- In the world, the Upgrade board's three pictures and the price coin on the honeycomb
	  stand use the same pictures (PlotBuilder: picture(), PANEL_PICTURES). The built map was
	  patched in place, so no rebuild was needed.
	- HOW THE PICTURES ARE MADE: Studio cannot save a picture of a model, so
	  ServerStorage.BeeEmpireDev.IconStudio writes each model out as a list of its blocks
	  (IconStudio.Export()). A small drawing program outside Studio (kept with the AI helper's
	  session files: icon-tools/render-icons.ps1 + IconRenderer.cs + models.txt) draws them, and
	  they are uploaded with the Studio AI connection. Roblox would not accept Figma's links
	  ("not trusted"); pictures served from this computer (http://localhost) were accepted.
	- TO ADD A NEW KIND OF BEE (or any picture): add it to PICTURES in IconStudio, export, draw,
	  upload, then add its number to UIImages. Until then the new bee shows the first bee's picture.
	- Play-tested with one player on desktop size and iPhone 7 size: top buttons, counters,
	  My Hive, Upgrade Shop, the world board. No script errors.
	- Scripts from before this change: ServerStorage.BeeEmpireDev.Backup_BeforeRealPictures
	  (UIKit, UpgradePanel, PlotBuilder).
	FIVE KINDS OF BEE, NEW NAMES, BLENDER MODELS (8 Oct 2026)
	- The owner's choices: names by hive job; chunky-toy look made in Blender; the 2 new bees
	  "easier to get"; and they agreed to click Import 3D themselves when a batch is ready.
	- Names (GameConfig.Rarities[...].BeeName): Common = Worker Bee, Uncommon = Scout Bee,
	  Rare = Guard Bee, Epic = Royal Bee, Legendary = Emperor Bee. The saved keys (Common,
	  Uncommon...) did NOT change, so saved bees are safe.
	- New kinds: Epic (weight 2 = 1 roll in 50, costs 5,000, sells 400, 15 jars a second) and
	  Legendary (weight 0.5 = 1 in 200, costs 30,000, sells 2,500, 50 a second). Weights are now
	  68 / 24.5 / 5 / 2 / 0.5 (they add up to 100).
	- The odds board has 7 lines now, so its writing limit went from 36 to 31 (PlotBuilder and
	  the 6 built boards). UIKit.CARD_FADES got Epic and Legendary colours.
	- The little bees that carry honey to the jars are called "carrier bees" in messages to
	  players (the Common bee is the Worker Bee now). The scripts still call them "workers".
	- Menu pictures of all 5 bees were drawn in Blender and uploaded (UIImages.Bees).
	- BLENDER: the owner installed Blender 5.2. The AI helper runs it without its window:
	  blender --background --factory-startup --python blender/bees.py -- <folder> preview icons export
	  (the script is kept with the AI helper's session files; a copy of the model file is in the
	  folder "BeeEmpire models" on the owner's Desktop).
	- The bee is built from shared pieces, all in "bee space" (x right, y up, z to the tail, the
	  bee faces -z, body middle at (0, 0, 0.3), 1 unit = 1 stud): Body (white, takes the bee's
	  colour), Details (stripes, face, collar, legs; own colours painted on the mesh), Wing (used
	  twice, at (0.95, 1.02, 0.25) turned 25 degrees and mirrored), and the outfits ScoutGear,
	  GuardGear, RoyalGear, EmperorGear and Crown (Emperor wears EmperorGear + Crown).
	- GETTING MODELS INTO ROBLOX: only Studio's own Import 3D window works. Tested and blocked
	  from the AI connection: AssetService:CreateAssetAsync ("not available yet") and reading
	  files from this computer (the game's Allow HTTP Requests is off, and should stay off).
	- The model file has every piece standing on the same spot plus four small cubes named
	  MarkOrigin (0, -8, 0), MarkRight (10, -8, 0), MarkUp (0, 2, 0), MarkBack (0, -8, 10) in bee
	  space. After the import, those cubes tell a script which way is up and how big a stud is.
	- IMPORTED AND SWITCHED OVER (8 Oct 2026, later): the owner imported the file; size and
	  painted colours came through correctly (1 unit = 1 stud; the import is turned half a turn
	  round, which the marker cubes showed). The eight pieces are now templates in
	  ReplicatedStorage.BeeEmpire.BeeMeshes; each has a "Place" attribute (where it sits in bee
	  space). The raw import with its marker cubes is kept in BeeEmpireDev.ImportedBees.
	- BeeModelFactory now builds every bee from those pieces (4 to 6 parts instead of 17).
	  Create(colour, options) works as before: a colour that matches a kind in GameConfig gets
	  that kind's Outfit and Size (GameConfig.Rarities[...].Outfit / .Size); any other colour is
	  a plain bee (the black shadow on the stand, the carrier bees, the shopkeepers).
	  options.Outfit forces an outfit: the Queen wears { "RoyalGear", "Crown" }.
	- The Queen, the builder bee and the shop bee on all 6 plots were swapped in place (their
	  hats were kept); PlotBuilder makes the Queen the same way on a rebuild.
	- To add a kind of bee later: model its outfit in blender/bees.py, import it, add the piece
	  to BeeMeshes with a Place attribute, then name it in that kind's Outfit.
	- Play-tested with one player: free roll, egg/shadow/reveal on the stand, buying, the bee in
	  the hive, the carrier bee, an Emperor shown on the stand. No script errors.
	- Scripts from before the switch: ServerStorage.BeeEmpireDev.Backup_BeforeBlenderBees.
	- NATURE PIECES (8 Oct 2026): the owner worried the smooth Blender pieces would mean losing
	  the studs. They do not: a Roblox Texture sits on a MeshPart face by face, just like on a
	  block, so Studs.Face(meshPart, face) works on Blender pieces. The owner then asked for the
	  pieces "a little sharper" (blender/props.py: R = 0.45, blocky mushrooms) and imported
	  BeeEmpire-nature.fbx. The 13 pieces are templates in BeeEmpireDev.PropMeshes (attribute
	  "Place" = where the piece sits when the prop stands at the origin); the raw import is in
	  BeeEmpireDev.ImportedNature. Shared Blender helpers: blender/toykit.py.
	  Pieces: Tree (give it an invisible 3 x 10 x 3 "Trunk" block so players bump into it),
	  FlowerStem + FlowerBlossom (lawn flowers and the plots' tiny flowers; the blossom is white
	  and takes the flower's colour), GrassTuft, GardenStem (a 1 x 1 x 1 post, stretched to each
	  stem), GardenLeaf, GardenPetals and GardenMiddle (the Flower Garden's flowers; modelled
	  for a head 5 studs wide, so their size is head / 5; petals and middle are white and take
	  the flower's colours; keep each flower model's name, its BeeSpot attribute and a
	  PrimaryPart called Middle), FencePost and FenceRail (the rail is 1 stud long along z),
	  Bush, Rock and Mushroom (new decorations).
	- DONE (8 Oct 2026, late): the owner saw a sample corner, said "it looks great", and the
	  whole map was rebuilt with the pieces. PlotBuilder now has prop() (puts a piece at a
	  ground point, with a size and a tint), studded() (marks a piece; AddStuds then lays the
	  stud picture on all six sides) and its own dice "look" for turns and sizes. tree,
	  flower, tuft, gardenFlower, the garden fence and the plots' tinyFlower / tuft all use the
	  pieces. BuildWorld also scatters 26 bushes, 16 rocks and 30 mushroom clumps on free lawn
	  (Map.Nature; its own seed 31, so changing those numbers moves nothing else).
	  Studs: trees, bushes and rocks. Plain: flowers, grass, mushrooms, fence.
	- HOW THE MAP WAS REBUILT (do it this way again): clone ReplicatedStorage.BeeEmpire into
	  ServerStorage as TEMP_BeeEmpire_Fresh, clone PlotBuilder as TEMP_PlotBuilder with every
	  "ReplicatedStorage.BeeEmpire" in its source swapped for
	  "game.ServerStorage.TEMP_BeeEmpire_Fresh", require that copy, call BuildAll(), delete
	  both. (Plain require would use modules Studio remembered from earlier in the session.)
	- The flowers and grass kept their old places (the old dice are still rolled the same way).
	  Garden flowers are still models named Flower1..49 in FlowerGarden.Flowers with a BeeSpot
	  attribute and a PrimaryPart called Middle, which is all HiveService needs.
	- Play-tested with one player after the rebuild: roll, buy, the bee was sent to a garden
	  flower's BeeSpot, a carrier bee appeared, all 6 upgrade boards show prices. No script errors.
	- Still block-built: the small flowers the hive grows at level 3 and up (HiveModelFactory),
	  the hive itself, the stands and shops, lamp posts, honey jars.
	- The map tool from before this change: ServerStorage.BeeEmpireDev.Backup_BeforeNatureProps
	  (rebuilding with it brings the old block trees and flowers back).
	OPEN HOME AREAS, LIKE BUILD AN ANT EMPIRE (8 Oct 2026, night)
	- The owner sent two photos of that game and asked for "the whole area first": bigger
	  areas and paths that feel put together. Their choices: open layout like the photos, about
	  1.5 times bigger, KEEP our bright colours, decorations only (no fake stations).
	- A home area is 124 x 116 now (was 112 x 88) and has NO floor of its own. Ring radius 180
	  (was 146), map size 530 (was 430). In the area's own directions (+z = towards the garden):
	    the hive's platform   x -31..31, z -57..-11, top at height 1.2 (PLATFORM_TOP), a bright
	                          kerb round it, two steps up at the front middle
	    hive at (0, -38); spawn pad at (0, -16) on the platform, facing the garden
	    main road             18 wide, from the steps (z -5) to the front edge (z 58)
	    cross road            8 wide along z = 0, out to x = -42 and 42
	    Honey Jars (-44, -15), Upgrade Shop (44, -15), Queen (41, 12), Honey Market (-42, 30)
	    side paths to the Queen (z 12) and the market (z 27); entrance arch at z 54
	  Standing on the platform looking out: Queen front left, market front right.
	- steppedPath() makes every path: an orange plate on a darker rim with pixel-stepped edges.
	  Side paths sit at 0.27, the main road at 0.3, so they never flicker where they cross.
	- Every station pad (standPad, and the shop's carpet) now has a dark earth border under it,
	  because it stands on open grass. FLOOR (0.6) is now just "how high pads are".
	- The world: paths are 18 wide and all join a ring road round the garden; trees stand
	  between the areas at 156, 196 and 236 from the middle plus the four corners; more lawn
	  patches, flowers, bushes, rocks and mushrooms; bare earth and flat stones (Map.Nature).
	- Each area's Dressing model: lawn patches, earth, stones, 5 bushes, 3 rocks, 6 mushrooms,
	  16 grass tufts, 14 flowers, placed by that area's own dice (seed 100 + its number) and
	  never on a path, the platform or a station (see clear() and KEEP_CLEAR in BuildPlot).
	- The scripts needed no change: they only look for SpawnPad, OwnerSign, HiveAnchor,
	  HiveSpot and the stations by name. An unseen part "Base" is still the plot's PrimaryPart.
	- A bee's trip to the garden takes GameConfig.TripSeconds whatever the distance, so the
	  bigger map does not slow honey down (the bees just fly faster).
	- Play-tested with one player: spawn on the platform, walked down the steps, along the
	  cross road and back up, rolled, bought, 16 jars arrived, grabbed them, sold them (50 ->
	  82 coins). No script errors. Not tested: phone, two players.
	- The map tool from before: ServerStorage.BeeEmpireDev.Backup_BeforeOpenLayout (rebuild
	  with it, the fresh-copy way, to get the walled yellow plots back).
	FLATTER, MORE NATURAL HOME AREAS (8 Oct 2026, late night) - THIS REPLACES THE LAYOUT ABOVE
	- The owner's words after seeing the platform version: "dont make everything on a
	  platform", the upgrade station is "just a board next to the egg roll", "dont have
	  anything on an actual platform make it a lot more natural", "remove the lamp posts those
	  make it ugly", and the jar area and the sell area "should be one area not too close to
	  each other but not seperate either".
	- So now: NOTHING is raised. FLOOR is 0, the hive's platform, kerbs and steps are gone, and
	  a station's ground is a thin patch of bare earth with a stepped edge (groundPatch;
	  PAD_TOP 0.2, about level with the road). The hive stands on a pale patch (HiveGround).
	- No lamp posts or lanterns anywhere on the plots (road, Queen's area, board, jar sign).
	  The two banner poles behind the hive are gone too.
	- The Upgrade Shop is only the board now (model Upgrades: Board, two posts, UpgradeSpot),
	  no pavilion, counter or builder bee. It stands beside the Queen's roll area, on the
	  hive's side, at (31, -17).
	- BUTTONS TOO CLOSE: with the board at (31, -11) pressing E at the board rolled a bee
	  instead, because both buttons were in reach. Fixed by moving the board a little and
	  shortening both: "Roll a Bee" reaches 9 studs, "Upgrades" 7; the two buttons are 17
	  apart. Keep any new button's reach from overlapping its neighbours.
	- Places now (+z = towards the garden): hive (0, -34); spawn point unseen on the road at
	  (0, -8); road 18 wide from z -17 to the front edge, a little wider in front of the hive;
	  Queen (34, 14); upgrade board (31, -17); Honey Jars (-34, -6) and Honey Market (-36, 26)
	  together in one clearing of lighter lawn, the honey yard; stepping stones lead from
	  the road to each station (no cross road or side paths any more); entrance arch at z 54.
	- Play-tested with one player: spawn, walked to the jars, the market and back, upgrade
	  board opens the Upgrades window, roll, buy, grabbed 8 jars, sold them (50 -> 66 coins).
	  No script errors. Not tested: phone, two players.
	- The map tool from before this change (platform version): Backup_BeforeNaturalLayout.
	- Later batches: the hive (5 levels), the stands and shops, lamp posts, honey jars.
	- Play-tested with one player: board text, 20,000 pretend rolls match the odds, My Hive
	  shows all five kinds. No script errors.
	- Scripts from before this change: ServerStorage.BeeEmpireDev.Backup_BeforeFiveBees.
	THE ROLL AREA REVAMP (8 Oct 2026, evening) - THIS REPLACES WHAT IS SAID ABOVE ABOUT THE
	QUEEN'S AREA, THE ODDS BOARD AND GameConfig.RollStands
	- What the owner asked for: no chances board ("we dont need that"); Auto Roll for 1k coins
	  as a one-time purchase whose sign then goes away; a spot on the upgrade board to add
	  more rolls, 5 at most, 3 with coins and the other 2 by a game pass later; the Queen in
	  the middle; the crown banner behind her removed. Mid-way they added: do NOT show
	  placeholders for stands that are not bought ("dont keep the other stands there"); a
	  stand only appears when it is bought, and they re-arrange: 1 in the middle, 2 split
	  either side, 3 with one in the middle, 5 adds the two outer ones.
	- Auto Roll, their answer to my question: an on/off button on the screen. They also want,
	  LATER, a setting for which kinds to roll past, so Auto Roll stops by itself when a kind
	  the player is waiting for turns up (e.g. skip Common and Uncommon, stop at Rare).
	  NOT BUILT YET.
	- Numbers (all in GameConfig): Upgrades.Rolls = "More Rolls" (1 stand free, 2nd 750, 3rd
	  6,000), RollStandSpots 5, GamePassRollStands 2, AutoRollPrice 1000, AutoRollSeconds 8,
	  AutoRollRange 45. GameConfig.RollStands is gone. The prices and the 8 seconds are my
	  picks; the owner has not commented on them yet.
	- How it works: BeeService owns it all. The map has ONE stand (Queen.Stands.Stand1); when
	  the server starts BeeService copies it for stands 2-5 and keeps the copies out of the
	  world. showRollArea(plot, owned, autoBought) puts the first `owned` stands on the
	  places the map tool wrote on the Stands folder (attributes "Spot_<how many>_<which>")
	  and takes the Auto Roll sign (Queen.AutoRoll) out once it is bought. A roll fills every
	  owned stand. Each player's screen gets Offer1..Offer5 / OfferPrice1..5 (the old
	  OfferRarity / OfferPrice attributes on the player are gone).
	- Auto Roll: data.AutoRoll (bought, saved) and data.AutoRollOn (saved). Bought with E at
	  the sign (prompt action "BuyAutoRoll"); switched by the HUD button through the new
	  remote SetAutoRoll; BeeService.StepAutoRoll (called twice a second from Main) rolls for
	  players who have it on AND stand within AutoRollRange of their Queen. That range is my
	  addition: without it the roll sounds and the "buy the bee" hint kept firing while the
	  player was away at the market.
	- The game pass is NOT built. BeeService.passStands(player) returns 0 with a note where
	  the ownership check goes. On the board and in the window More Rolls shows "3 of 5" and
	  "SOON" at its top coin level (Upgrades.PassLevels / TopLabel / DescribeTop).
	- Main now connects a button the moment it appears in a plot (DescendantAdded), because
	  the copied stands arrive later.
	- Map: roll area at (40, 14), earth pad 42 x 30. Queen (scale 1.6, was 2) on a round
	  pedestal at the pad's middle-front, "ROLL A BEE" sign and Roll button (reach 7) in front
	  of her, stand arc 13 studs behind her, Auto Roll sign at the front right (reach 6). The
	  stand is drawn big and shrunk to 0.75 (STAND_SIZE) so five fit; Buy reach 8. Upgrade
	  board moved to (30, -21), reach 8, 4 panels now. Gone: the odds board, the crown banner,
	  the comb / jelly pots / planter that stood where more stands would go.
	- KNOWN COMPROMISE: with the Queen in the middle and the first stand in the middle behind
	  her, she hides most of that stand's screen from straight in front. The egg and the bee
	  show over her head, and the hint and arrow send the player round to the stand.
	- Play-tested with one player (desktop size): free first roll and take; with 9,000 test
	  coins (StartingCoins changed for the test and put back to 50): More Rolls twice (stands
	  at -3.8/+3.8, then 0/+7.7/-7.7), a 4th refused, asking from too far refused, fake
	  SetAutoRoll before buying ignored, Auto Roll bought (sign gone, button shown), rolls
	  every 8 s, off = none, on again = rolls, at the market = none, E at stand 2 bought that
	  bee and did not roll. No script errors. NOT tested: phone screen, two players, saving
	  of AutoRoll (saving is off in Studio).
	- New menu picture: UIImages.Egg (the mystery egg) for More Rolls.
	- Scripts from before: ServerStorage.BeeEmpireDev.Backup_BeforeRollRevamp (ClientMain is
	  not in it: its only change is two lines that call WorldFX.PlayNewStand).
	- BLENDER PIECES FOR THIS AREA (imported by the owner the same night, from
	  BeeEmpire-rollarea.fbx made by blender/rollarea.py): Stall, StallBulbs, Pedestal and
	  PedestalGems are templates in BeeEmpireDev.PropMeshes; Egg is in
	  ReplicatedStorage.BeeEmpire.BeeMeshes (players' devices build the egg). The raw import
	  is BeeEmpireDev.ImportedRollArea. Their fronts face -z, so PlotBuilder turns them half
	  round. StallBulbs and PedestalGems are white meshes shown as Neon in a colour.
	- The stand now: an unseen solid block (Body), the block Screen / BeeSpot / BuySpot /
	  NewTag as before (laid out big, shrunk to 0.75), and then the Stall and Bulbs pieces
	  added at their real size. The pedestal: the Pedestal piece (studs on top only) and
	  Gems, an unseen round block to bump into (PodiumSolid), and the name sign on its own
	  upright unseen block (NameSpot): a floating sign's height is measured along the part
	  it hangs on, and a cylinder part lies on its side, so the sign went sideways at first.
	  The old block helpers hexPlate / roundPlate / combFace are gone from the map tool.
	- WorldFX.makeEgg uses the Egg piece (and still builds the block egg if it is missing).
	- Play-tested with one player after the swap: free roll, egg, bee on the stand, took it.
	  No script errors. Three stands were checked in the editor by copying stand 1 onto its
	  places (the looks move with it); not re-run in play after the swap.
	- Scripts from just before the swap: BeeEmpireDev.Backup_BeforeBlenderRollArea.
	SAFETY ROUND (9 Oct 2026): SAVING, PHONE SCREEN, TWO PLAYERS
	- The owner turned on "Enable Studio Access to API Services". From now on a play-test in
	  Studio loads and saves REAL progress (the owner's own), exactly like the live game.
	  So for any test that needs pretend coins: change GameConfig.DataStoreName to a test
	  name and StartingCoins to what is needed, test, and PUT BOTH BACK (done each time
	  here; test stores used: BeeEmpire_TEST_SaveCheck_A, BeeEmpire_TEST_TwoPlayers_A).
	- SAVING WORKS. On a test store: took the free bee, bought More Rolls, Beehive, Luck,
	  Bee Speed and Auto Roll, switched Auto Roll off, let 24 jars arrive, stopped, started
	  again: coins 6,100, hive level 2, all four upgrades, the bee in its spot, Auto Roll
	  owned and still off, 24 jars waiting all came back, and the home showed two stands, no
	  Auto Roll sign and the level-2 hive. Not tested: the autosave timer on its own, a
	  crash, the same player in two servers (there is still no session lock).
	- PHONE SCREEN (Samsung Galaxy A06, 800 x 360, through StudioDeviceSimulatorService):
	  the HUD, the Auto Roll switch (clear of the jump button), the Upgrade Shop window, the
	  My Hive window and a roll all fit and read well. One fix: the screen-edge arrow could
	  sit on the thumbstick or beside the jump button, so on touch screens it now stays
	  nearer the middle (WorldFX: EDGE_REACH_SIDE_TOUCH). Only this one phone was tried; no
	  tablet, no real finger taps (the buttons were pressed with the E and B keys).
	- TWO PLAYERS (StudioTestService:ExecuteMultiplayerTestAsync with a throw-away server
	  script that called the services for each player): two different homes, each player at
	  their own spawn; a roll fills only its owner's stand; a player who has not rolled
	  cannot buy; More Rolls and Auto Roll change only the buyer's home; the buyer's Queen
	  auto-rolls only their stands; when that player leaves, their home goes back to one
	  stand in the middle with the Auto Roll sign, and the other player is untouched. Not
	  covered: the second player's own button presses going through Main's checks, and two
	  real devices.
	- MAX PLAYERS still reads 60 from inside Studio (edit mode and the test server) after
	  the owner changed it in Game Settings > Places. Either it was not saved or Studio only
	  shows the new number after a restart. Check again next session; it must be 6.
	- TOOL NOTE: screen_capture does not show BillboardGuis that live in PlayerGui (the
	  press-E buttons and the bouncing "go here" arrow), although they are there and work.
	  Check those by their properties, not by the picture.
	THE BLENDER HIVES WITH BEE WINDOWS (9 Oct 2026)
	- The owner: "do the hives and make them all bigger". Their answers to my questions: a
	  "beehive with bee windows" and "Bigger" (level 1 about 7 studs tall, level 5 about 22).
	- Pieces (blender/hives.py, imported by the owner from BeeEmpire-hives.fbx): Hive1..Hive5,
	  HiveWindowFrame, HiveWindowPane in ReplicatedStorage.BeeEmpire.HiveMeshes (both the
	  server and players' devices build hives). Raw import: BeeEmpireDev.ImportedHives.
	- A hive is a stack of rounded-SQUARE rings (not round), so the stud pattern lies flat on
	  its sides. Heights 7.2 / 10.3 / 13.6 / 17.4 / 21.8, stands 5.4 / 8 / 11.5 / 15 / 19 wide.
	- BEE WINDOWS: one six-sided window per bee spot (GameConfig capacity: 2/4/6/9/12), in a
	  honeycomb triangle on the front, on the rings above the door. HiveModelFactory works
	  out the rows from the capacity and the ring sizes (BLENDER_SHAPES, made by the Blender
	  script; hive-shapes.lua in blender/out), so changing a Capacity moves the windows by
	  itself as long as they fit. Window N belongs to bee spot N.
	  HiveModelFactory.SetWindow(hive, n, colour or nil) lights it (Neon in the bee's colour)
	  or makes it dark; HiveService.RefreshBees does that for every spot.
	  HiveModelFactory.WindowPoint(hive, n) is where bee N leaves and comes home.
	- The hive model now: unseen solid blocks "Stand" (PrimaryPart) and "BodySolid", the
	  piece "Looks" (studs on top and four sides), folder "Windows" (FrameN, PaneN). The old
	  block hive is still in HiveModelFactory (createFromBlocks) and is built only if the
	  HiveMeshes folder is missing.
	- Menu pictures: five new hive pictures uploaded, UIImages.Hives.
	- Play-tested with one player on a test save: level 1 on joining and on an empty home;
	  first bee lights window 1 and leaves from it; upgraded 1 -> 5 (windows 2, 4, 6, 9, 12,
	  the lit window stays lit, the Open Hive button and the sign move out, a 6th level is
	  refused); a Common, a Legendary and an Uncommon lit windows 1, 2, 3 in yellow, orange
	  and green and window 4 stayed dark. No script errors.
	- NOT LOOKED AT YET: how the studs sit on the hive's sides, the hive in the "hive
	  upgraded" card and the menus. Studio's window was minimized during this work, so the
	  3D view could not be photographed (one far-away picture was taken before that).
	- Scripts from before: BeeEmpireDev.Backup_BeforeBlenderHives.
	THE SETTINGS WINDOW (9 and 10 Oct 2026)
	- The owner looked at the new hives ("i checked it looks good") and asked for a Settings
	  window with: music volume, the Auto Roll setting, and a luck setting. Their answers:
	  a happy song picked by me from Roblox's free library; Auto Roll PAUSES for a wanted bee
	  and carries on after it is bought (or Keep Rolling is tapped); luck = pick any level
	  you own; plus a sound effects slider.
	- WHERE THINGS ARE
	  GameConfig: MusicId ("Playtime", APM Music, from Roblox's free library; 105 s, loops),
	    MusicLoudness, DefaultMusicVolume, DefaultSoundVolume, AutoRollStopDefault (Epic and
	    Legendary).
	  DataService: data.Settings = { Music, Sounds, StopFor = { Epic = true... }, Luck }.
	    Old saves get the starting settings and all their luck. LuckLevelInUse / LuckInUse.
	    Player attributes: Set_Music, Set_Sounds, Set_Luck, Set_Stop_<Rarity>.
	  Services.SettingsService (new): checks and stores every setting. Main: remotes
	    SetSetting (name, value, extra) and KeepRolling, each behind the cooldown.
	  BeeService: wantedOffer / shareWaiting (player attributes AutoRollWaiting = the bee,
	    AutoRollWaitingStand), KeepRolling, RefreshWaiting; a roll uses LuckInUse; buying a
	    bee makes Auto Roll wait one full AutoRollSeconds.
	  UpgradeService: buying Queen's Luck sets the luck in use back to the highest.
	  Client: SettingsPanel (new; window opened by the gear button in the top bar), Audio
	    (new; the song, and Kit.SetSoundVolume), State (MusicVolume, SoundVolume, StopsFor,
	    LuckLevelInUse, AutoRollWaiting), HUD (gear button; the Auto Roll button turns into
	    an orange "Keep Rolling" with "<bee> found!" above it).
	  Pictures: UIImages.Gear / Music / Speaker (blender/uiicons.py).
	- The Auto Roll row is hidden until Auto Roll is bought (no placeholders). The window is
	  kept short on purpose: windows are shrunk until their height fits, so shorter = bigger
	  on a phone. "Fit" labels grow to fill their box, so give them a box no taller than
	  the writing.
	- TESTED on test saves: every setting saved and came back after leaving; bad values
	  refused or clamped (text, not-a-number, 9999, -40, luck not owned, unknown bee, spam);
	  slider dragged with the mouse on desktop and at phone size; Auto Roll waited, Keep
	  Rolling rolled on, buying the bee let it carry on; phone layout fits.
	- The Figma file has frame "4. Settings window" (and a gear + Keep Rolling button on
	  "1. While playing"), but the free Figma plan ran out of tool calls for the month right
	  after it was drawn, so it was never looked at through the tool. The game is the truth.
	- Scripts from before: BeeEmpireDev.Backup_BeforeSettings.

	TEN BEES IN FIVE RARITIES (10 Oct 2026)
	- The owner asked for 5 more bees, one per rarity, "slightly better" and "slightly more
	  expensive"; the Settings stop list to show rarities, not bees, and no pictures; and
	  Legendary to feel special (rainbow text, "more dopamine"). Their choices: names
	  Builder, Explorer, Knight, Wizard, Galaxy; outfits made in Blender (they imported
	  BeeEmpire-newbees.fbx); each rarity keeps its chance and the new bee is the rarer one
	  (1 roll in 3 of that rarity); Legendary gets a big reveal and a rainbow sparkle trail
	  (they did NOT pick the message to the whole server).
	- HOW THE CONFIG IS NOW ORGANISED (this changed a lot)
	  GameConfig.RarityOrder / Rarities = the FIVE rarities (Chance, Color, Sparkles,
	    Rainbow, BigReveal, Trail).
	  GameConfig.BeeOrder / Bees = the TEN bees (Rarity, BeeName, NectarPerSecond, Price,
	    SellValue, Share, Color, Outfit, Glow, Size). Each bee also gets, copied from its
	    rarity when the config loads: DisplayName, RarityColor, Sparkles, Rainbow,
	    BigReveal, Trail. GameConfig.RarityOf(name) takes a bee's or a rarity's name.
	  The first bee of each rarity is saved under its rarity's name (Common, Uncommon...),
	  the new ones under Builder, Explorer, Knight, Wizard, Galaxy. In saves and scripts the
	  field / variable is still called "Rarity" / rarityName even though it now holds a
	  BEE's name. Every bee needs its own body Color: the bee builder finds a bee by it.
	- Rolling: first a rarity (Chance, with luck on all but the first), then a bee by Share.
	- Legendary extras: Kit.SetRainbow / RarityText / BeeNameText (rainbow writing on the
	  stand's screen, cards, messages, the Settings card, My Hive); a golden egg that lasts
	  BigRevealEggSeconds (the server's ReadyAt and the client both use it);
	  Effects.BigReveal (flash, "LEGENDARY!" banner, confetti, fanfare from built-in
	  sounds); BeeModelFactory Trail option (a SOLID rainbow ribbon and sparkles: a glowing
	  one hardly shows against the bright ground); Glow pieces are Neon (Galaxy's ring).
	- Hive windows now glow in the RARITY's colour (both Common bees: yellow).
	- Notifier.Send has a 5th value, rainbow.
	- TESTED on a test save with Legendary made common for the test: all ten bag counters;
	  rolls gave old and new bees; golden egg, beam, rainbow labels on the stand; bought
	  Galaxy, Emperor, Explorer, Builder, Scout; pictures show in My Hive; saved and came
	  back; rarity cards in Settings; Auto Roll waited for a Builder with Common ticked;
	  trail and banner seen on screen. Knight and Wizard were only seen built in the editor
	  (a line-up of all ten), not rolled.
	- Blender: blender/bees.py (modes newpreview, icons newonly, exportnew). Raw import:
	  BeeEmpireDev.ImportedNewBees. Scripts from before: BeeEmpireDev.Backup_BeforeTenBees.
	THE HONEY MARKET'S PRICE (10 Oct 2026)
	- The owner said progression is too slow ("the most important part of a game is the first
	  3 minutes") and asked for a sell multiplier like Build An Ant Empire's. This reverses
	  the 4 Oct "no sell price multiplier yet". Their choices: a NEW RANDOM price every 30
	  seconds, the SAME for everyone in the server, never below 1x, usually 2x to 3x, a rare
	  top of 5x. (The ant game's own price runs from about 0.5x to 2x: see reference-notes.)
	- GameConfig: SellPriceSeconds (30), SellPriceBands (Min, Max, Chance: 5% 1.0-1.4,
	  20% 1.5-1.9, 55% 2.0-3.0, 15% 3.1-4.0, 5% 4.1-5.0; average about 2.5x), SellPriceStep
	  (0.1), SellPriceHigh (4: from here up it is "a great price"). JarValue is still 2.
	- Services.MarketService (new): picks the price, MarketService.Price() / Worth(jars) /
	  SignText(); writes workspace attributes SellPrice and SellPriceChangesAt (server
	  time). Main starts it before the plots are reset. ProductionService.Sell pays
	  Worth(jars) and sends "Sold N jars at x2.4!" (rainbow for a great price).
	- Client: State.SellPrice / SellPriceSecondsLeft / SellPriceIsHigh (State.Changed also
	  fires when the price changes); HUD has a Price row above the bee rate (coin, "x2.4",
	  "new in 12s") and shows a rainbow "Honey price is x4.7! Sell now!" message when a great
	  price arrives; State.Objective says "Sell your jars now!" while the price is great and
	  the player has honey; WorldFX draws a PriceBoard over every market's Counter (price,
	  red-to-green bar with a marker, countdown); Kit.PriceColor / Kit.PriceText.
	- TESTED on a test save (price changes every 8 s and great prices made common, for the
	  test only): changes on time, HUD and all six boards follow, a sale of 35,360 jars at
	  x1.8 paid 127,296 coins, the great-price message, hint and rainbow all showed, phone
	  size fits. Not tested: two players seeing the same price (it is one workspace value).
	- What the owner wants next: make upgrades (or everything) a little cheaper. Advice
	  given: play with the price first, then lower only the early prices.
	- Scripts from before: BeeEmpireDev.Backup_BeforeSellPrice.

	ENDLESS QUEEN'S LUCK (10-11 Oct 2026)
	- The owner asked: "make the luck upgrades a lot smaller so kids can click on it more",
	  "dont put a limit on the luck upgrades just a lot more expensive as they go on but also
	  very small luck boosts forward", "make the legendary ones a little more rare", and "add
	  a luck multiplier to the bottom of the screen and remove the sell multiplier thats at
	  the bottom". The numbers below were picked by the assistant, not by the owner.
	- GameConfig.Upgrades.Luck has no Levels list any more. It has
	  Endless = { Step = 0.1, FirstCost = 75, Growth = 1.15 }: level 1 is x1, each level adds
	  Step, the first upgrade costs FirstCost and each next one Growth times more (rounded to
	  two digits: 75, 86, 99, 110, 130...). x1.5 = 500 in all, x2 = 1,510, x3 = 7,700,
	  x4 = 32,600, x5 = 132K, x6 = 539K, x7 = 2.2M.
	- Upgrades module: IsEndless(id), LevelText(id, level) ("Level 7" with no "/ 5"); ValueAt,
	  NextCost, CleanLevel, MaxLevel and Exists all understand an endless upgrade.
	  ENDLESS_SAFETY_LEVELS (2000) only guards against a broken save.
	- WHAT LUCK DOES CHANGED. Before: luck multiplied the weight of every rarity but the
	  first, so the real boost shrank as luck grew (x4 luck gave about x2 Legendaries, and
	  nothing changed past about x8). Now BeeService.rarityChances(luck) multiplies each
	  Chance by luck, hands the rarest their share first and gives the first rarity what is
	  left of the 100. x2 luck is exactly twice the Legendaries. Common is gone from x3.2,
	  Uncommon from about x14. BeeService.RarityChances and BeeService.RollBee are exposed
	  for checking the odds; neither changes anything.
	- Rarities: Legendary Chance 0.5 > 0.3, Common 68 > 68.2 (still adds up to 100).
	- Old saves: DataService SAVE_VERSION is 2. A version 1 save has its luck level turned
	  into what the same coins buy now (OLD_LUCK_LEVELS = { 1, 6, 14, 24, 34 }: x1.5 stays
	  x1.5, x2 > x2.3, x3 > x3.3, x4 > x4.3) and its "luck in use" setting the same way.
	- HUD: the Price row is gone. A Luck row (clover, "x1.3 luck", or "x1.9 luck (of x2.8)"
	  when turned down in Settings) took its place and bounces when luck changes. The
	  great-price message is still sent from HUD.refresh. The price board over each market,
	  the great-price hint and the sale message are untouched.
	- State: LuckInUse(), LuckOwned(), UpgradeWorthAVisit(). The "You can afford an upgrade!"
	  hint only counts an endless upgrade while its price is at most
	  GameConfig.EndlessHintShare (0.1) of the next hive's price, so a new player saves for
	  the 250 coin hive first and then gets about six cheap luck clicks on the way to the
	  next hive. Players can still buy luck whenever they like.
	- SettingsPanel: Queen's Luck is a slider now (makeSlider takes Min, Max(), Step, Format
	  and an optional CentreY), counted in luck levels. It hides until some luck is bought.
	- TESTED: 200,000 rolls each at x1, x2.3 and x4 match the table; an old save (luck level
	  3, in use 2) loaded as level 14, in use 6; buying by remote and with the real button;
	  prices 460, 530, 610, 700, 810; the hint cases above with a brand-new save; the slider
	  on a phone-size screen (dragged to the middle: level 10 of 19, saved). Not tested: how
	  the first 3 minutes feel to a real new player, and luck beyond level 19.
	- Scripts from before: BeeEmpireDev.Backup_BeforeLuckRework.

	PLOT 1 WAS FOUND OUT OF PLACE (11 Oct 2026)
	- The owner asked "why is my hive far away from everything". workspace.Plots.Plot1 was at
	  (249.2, 6.5, 191.0) facing (1, 0, 0) instead of (155.885, -0.3, 90) facing
	  (0.866, 0, 0.5): moved 137.5 studs, lifted 6.8 and turned 30 degrees, all in one piece.
	  Cause unknown; it looks like a mouse drag in the 3D view. No script here moves a plot.
	- How the true spot was found: Queen.QueenBee and Market.ShopBee each carry a BasePivot
	  attribute (the world CFrame they were built at; the client bobs them from it, which is
	  why they stayed behind). plotCFrame = BasePivot * (plot:ToObjectSpace(bee pivot))^-1.
	  Both bees and the ring formula (180 studs out, plot N at 30 + 60 x (N-1) degrees,
	  facing outward) gave the same answer. Plot1 was put back with PivotTo.
	- Worth doing if it happens again: set Locked = true on the parts of workspace.Plots so a
	  click in the 3D view cannot grab them (offered to the owner, not done).
	- A lesson for the assistant: the test DataStoreName was still set when the chat was
	  interrupted overnight, so any play-test in between used a pretend save. Put the real
	  name back before every pause, not only at the very end.
	FOUR SAVED-FOR-LATER THINGS, AND THE LOCK (11 Oct 2026)
	- The owner said "fix the things i said yesterday". Their answers to questions: the
	  carrier bees' problem is that THEY OVERLAP; Roll Speed speeds up AUTO ROLL ONLY; its
	  best level rolls EVERY 2 SECONDS; and yes, LOCK the home areas in Studio.
	- ROLL SPEED. GameConfig.Upgrades.RollSpeed: Value = seconds between the Queen's own
	  rolls (8, 7, 6, 5, 4, 3, 2; costs 500, 1,500, 5,000, 15,000, 50,000, 150,000: my
	  numbers), NeedsAutoRoll = true. GameConfig.AutoRollSeconds is gone (level 1 is the old
	  8). New: AutoRollBuyPause (3), AutoRollJoinWait (10). BeeService.autoRollSeconds(data);
	  after a roll the next one waits max(roll seconds, how long the eggs take), so a golden
	  egg is never rolled away half-shaken. Main looks every 0.25 s now. Upgrades.NeedsAutoRoll;
	  UpgradeService refuses it before Auto Roll is bought; State.UpgradeAvailable hides the
	  row in the Upgrade Shop window and keeps it out of the hint. The window's rows are
	  100 tall now and sit in a list, so it is shorter than before with four rows.
	  Picture: UIImages.FastEgg (the egg leaning forward with speed lines; blender\rollarea.py
	  mode "fasticon"). NOT on the board in the world: that still has its four panels
	  (PlotBuilder skips NeedsAutoRoll upgrades). Adding a fifth panel is open.
	- SAVED STAND BEES. data.Offers = { ["2"] = { Rarity = "Epic", Free = true? } }, cleaned
	  in DataService. BeeService.rememberOffers after every roll and buy; restoreOffers in
	  SetupPlayer shows them already hatched (OfferStart an hour old, so no egg and no
	  sound) at today's prices. Auto Roll treats them like any bees: it waits for the
	  rarities ticked in Settings, and otherwise rolls again AutoRollJoinWait seconds after
	  the join. (So a saved Rare is rolled away after 10 s if Rare is not ticked.)
	- ROLL SOUNDS. WorldFX.rollLoudness(spot): 1 within GameConfig.RollSoundRange (30) studs
	  of the stand, fading to 0 over RollSoundFade (10) more. Kit.PlaySound(name, speed,
	  loudness) and Effects.BigReveal(beeName, loudness). The flash, letters and confetti of
	  a Legendary still show from anywhere; only its fanfare follows the distance.
	- CARRIER BEES (the scripts call them workers). A worker is 2.9 wide, 2.9 tall, 4.2 long.
	  Before, lanes were 1.5 to 1.7 studs apart and the waiting loop put returning workers at
	  the same angle, so two looked like one double bee. Now: HiveService gives lanes
	  WORKER_GAP (3.5) apart in rows of 3 (a second row 3.3 higher), the circle is lower
	  (0.45 of the body) and wider (radius + 4), and LoopSlot = the lane's number. WorldFX
	  moves each hive's workers as a group: a flying worker holds one lane there and back;
	  workers leaving the circle together take neighbouring free lanes in flying order (paths
	  never cross); they fly in above the door row and drop onto their spot; after a
	  delivery a worker waits at its door until there is WORKER_ROOM (5.2 studs) on the
	  circle, drops straight out onto it, then flies round with the others (same way, same
	  speed). MEASURED with 3 workers: closest two were 0.69 studs before, 3.05 after, with
	  no moment under 3 studs in 34 s. Not measured with 5 or 6 workers.
	- LOCK. Every part in workspace.Plots has Locked = true (3,138 parts), so a click in the
	  3D view cannot grab a home area. workspace.Map and FlowerGarden are NOT locked. A
	  rebuild with PlotBuilder makes unlocked parts: lock them again afterwards.
	- TESTED on test saves: Roll Speed bought to the top (Auto Roll measured every 2.1 s);
	  a brand-new save shows four shop rows and the server refuses Roll Speed; three stand
	  bees were still there after leaving and rejoining, one was bought; a saved Epic kept
	  Auto Roll waiting after rejoining; the join wait measured 40.1 s with a test value of
	  40; sounds: full volume at 8 studs, about half at 35, none at 60; the five-row shop on
	  a phone-size screen.
	- Scripts from before: BeeEmpireDev.Backup_BeforeSavedForLater.
	THE NEW FLOWER GARDEN (11 Oct 2026)
	- The owner: "i want the actual flower garden to look a lot more detailed and cooler
	  though, the area is good but the size of everything could be better and more detailed".
	  Their choices: a GIANT SUNFLOWER in the middle, flowers of MIXED SIZES (small at the
	  fence to giants near the middle), SWAYING flowers and a POND with lily pads. Not chosen:
	  butterflies and pollen, flower arches. They also said no to locking the rest of the map
	  and to putting Roll Speed on the board in the world.
	- Made by blender\garden.py (modes lineup, preview, export): 20 pieces, now templates in
	  BeeEmpireDev.PropMeshes (raw import: BeeEmpireDev.ImportedGarden). Flowers are two
	  pieces each, a painted Body and white Petals the game tints: DaisyBody/DaisyPetals,
	  TulipBody/TulipPetals, PoppyBody/PoppyPetals, BellBody/BellBells,
	  SpikeBody/SpikeBlossoms; Sunflower is one painted piece. The giant sunflower is
	  SunGiantStem + SunGiantHeadA/B/C, all modelled in place, so all four go on the same
	  spot. Pond: LilyPad, LilyBloom (pad + yellow middle), LilyPetals (white), Reeds, Frog.
	- The same script writes the layout; it is kept as BeeEmpireDev.GardenLayout (Kinds with
	  each flower's pieces, height and bee spot; Flowers, Beds, Stones, Pads, Reeds, Extras as
	  short rows; GiantSpots; Pond; Frog; GiantTurn = -90 so the three faces look between the
	  gates). To change the garden: edit garden.py, run it, replace GardenLayout, run
	  PlotBuilder.BuildGarden() from a fresh clone.
	- PlotBuilder.BuildGarden was rewritten: same meadow, soil rim, fence and gates; flat soil
	  beds; stepping stones; a mound with the giant sunflower (an unseen Trunk block is what
	  players bump into); 90 flowers named Flower001.. with BeeSpot, plus 6 FlowerGiantN
	  holders with BeeSpot for the three faces (96 bee spots, was 49); the pond (smooth blue
	  water marked NoStuds, 22 rim stones, pads, frog, reeds); bushes, rocks, mushrooms, grass
	  and lawn flowers. Flowers 10 studs or taller and the giant get the stud pattern.
	  steppedDisc takes an optional centre and strip width now. The sign floats at 44 studs.
	- SWAY. Models tagged "GardenSway" carry Foot (CFrame) and Tall. WorldFX section 10 leans
	  each one from its foot (15 / Tall degrees, between 0.7 and 4) with a wave across the
	  garden, moving all parts with one BulkMoveTo, only within 190 studs of the camera.
	  StreamingEnabled is on, so a flower's parts are listed when they arrive.
	- My own additions, told to the owner: THREE heads on the sunflower (so no home area
	  looks at its back) and ONE frog.
	- CHECKED in a play-test: 533 parts, 108 swaying things, 96 bee spots; flowers move
	  (a 3-stud flower's petals 0.2 studs, the giant's head 0.36, before the lean was raised);
	  seven bees of the test save were all heading for new flowers; no script errors.
	  Not checked: a phone, the frame rate, more than one player.
	- Before: BeeEmpireDev.Backup_BeforeNewGarden (the old garden model, the map tool, the
	  client scripts). Pictures: new-look 60-62 (the plan) and 63-65 (in the game).
THE FIRST 3 MINUTES, TIMED - CHEAPER FIRST UPGRADES - THE HINT IS A TUTORIAL (2026-10-12)
	The owner chose "first 3 minutes" as the next job, said yes to my prices and hint, and
	added: "make the hints only there until you do everything once, roll a better bee, get
	an upgrade, sell, and then make it go away, thatll be the tutorial".

	- MEASURED FIRST (old prices, old hint): a pretend new player on a brand-new test save
	  who did exactly what the hint said and never stood still. 0:07 free bee, 0:14 second
	  bee, 0:34 first sale, 1:09 Cozy Hive (250), 1:40 four Worker Bees, 1:52 to 3:00 six
	  luck upgrades, 3:35 Bee Speed, 5:04 second stand. At 3:00: still only 4 Worker Bees.
	  Two problems: nothing to buy from 0:14 to 1:09, and with a full hive the hint only
	  said "Save 1.5K coins for a bigger hive!", never "roll for better bees" (7 rolls in
	  5 minutes), although a better bee is the best buy in the game.
	- PRICES CHANGED (GameConfig): Cozy Hive 250 > 100, Busy Hive 1,500 > 1,000, Bee Speed's
	  first step 400 > 250, the second roll stand 750 > 400. Nothing else.
	- THE TUTORIAL. The hint and the arrow stay until three lessons are done, each once:
	  "Sold" (ProductionService.Sell), "Upgrade" (UpgradeService.Buy, the hive counts) and
	  "BetterBee" (a better bee takes a weaker working bee's place: BeeService.EquipBest or
	  PlaceBee). Services.TutorialService.Mark ticks them off in data.Tutorial
	  { Sold, Upgrade, BetterBee, Done } (saved); DataService shares them as the attributes
	  Tut_Sold, Tut_Upgrade, Tut_BetterBee and TutorialDone. When all three are done the
	  player gets a rainbow "Tutorial done!" message and State.Objective returns "" with no
	  target for ever: HUD hides the hint line, WorldFX has nothing to point the arrow at.
	  The "!" badges on My Hive and Equip Best, the great-price message and the Auto Roll
	  "found" message are not part of the hint and stay.
	- "BetterBee" is a SWAP on purpose. Buying a Builder Bee into a free spot does not count:
	  a third of players would then finish at 0:50 with two empty spots, and nobody would
	  learn that a full hive means "roll for better bees, then Equip Best".
	- OLD SAVES have no data.Tutorial. DataService.sanitize works it out from what they own:
	  an upgrade (or Auto Roll), a bee that is not the starter kind, and for "Sold" either of
	  those or more coins than a new player starts with. All three = Done at once.
	- THE HINT'S NEW LINES (State.Objective), only once the Upgrade lesson is done and the
	  hive is full: "Roll for better bees!" (arrow at the Queen) when the player can pay for
	  the cheapest bee that beats their weakest; "Save N more coins for the X on your stand!"
	  when a better bee is waiting and their bees earn the missing coins within
	  GameConfig.SaveForBeeSeconds (45); otherwise "Earn N more coins for a better bee!".
	  "You can afford an upgrade!" is only said until the first upgrade is bought.
	- CHECKED in play-tests on test saves: a brand-new player was led through all of it and
	  the tutorial ended at 1:37 (first sale 0:35, Cozy Hive 0:54, four bees 1:19, Builder
	  Bee swapped in 1:37); the hint line hid and the arrow went; after leaving and coming
	  back it was still done; an old rich save (TenBees_A) came in as done; an old save with
	  two Worker Bees and 25 coins (LuckFresh_B) still got the hint. No script errors.
	  Not checked: a phone, a real child, the "Tutorial done!" message by eye, the
	  "Save N more coins for the X" and "Earn N more coins" lines (they did not come up).
	- THE TOOL: BeeEmpireDev.FirstMinutesSim plays the start of the game hundreds of times in
	  a second or two (its own header says how). It copies GameConfig, follows the hint's
	  rules, and uses walking distances from Plot1 and action times measured in the real
	  play. Its middle result matched the real play within a few seconds. With the new
	  prices and the tutorial (500 games): Cozy Hive 0:50, four bees 1:18, tutorial done
	  1:47 in the middle game, 1:29 for a quick one, 2:07 for a slow one, 4:00 the slowest.
	  TRAP: in Edit mode require() remembers a module, so a GameConfig changed since Studio
	  was opened looked unchanged. The tool now reads a fresh copy (GameConfig:Clone()).
	- A WAY TO TEST: a Client script can require the game's own State module
	  (player.PlayerScripts.BeeEmpireClient.State). It is a second copy, but it reads the same
	  attributes, so a pretend player can do whatever State.Objective() really says.
	- STILL OLD: the later prices (Grand Hive 8,000, Royal Hive 40,000, Bee Speed and Roll
	  Speed from their second step, the third stand 6,000, Auto Roll 1,000).
	- Before: BeeEmpireDev.Backup_BeforeTutorial. Pictures: new-look 66 (hint showing) and
	  67 (tutorial done, no hint). Test saves: BeeEmpire_TEST_First3_A (5 minutes with the
	  old prices), BeeEmpire_TEST_Tutorial_A (tutorial done, 4 bees, Cozy Hive).
OFFLINE HONEY AND "YOUR BEES EARN OFFLINE!" (2026-10-12)
	The owner sent six pictures of the ant game (offline rewards, daily rewards, playtime
	rewards, passes, packs, the leave menu) as "references for things i want you to do", and
	asked for this first: "make it so that you earn money offline, and when you go to leave
	the game, theres 2 rainbow things that say bees earn offline in rainbow". Their answers:
	the reward is HONEY JARS (not coins), at most 4 HOURS count, bees work at HALF SPEED while
	away, and no paid "Keep 3x" button yet. The other pictures are for later.

	- NUMBERS (GameConfig): OfflineMaxHours = 4, OfflineSpeed = 0.5, OfflineMinSeconds = 60.
	- HOW IT WORKS. DataService writes data.LastSeen = os.time() every time it saves. On the
	  next join, the time since then is the time away (DataService.TakeAwaySeconds hands it
	  out once). Services.OfflineService.SetupPlayer (called from Main after the other
	  services) turns it into jars: hive jars per second (Bee Speed counts) x OfflineSpeed x
	  seconds, floored. They WAIT in data.Offline { Jars, Seconds } (saved, shared as the
	  attributes OfflineJars and OfflineSeconds) until the player collects. Collecting
	  (remote ClaimOffline > OfflineService.Claim) moves them to JarsStored, so they are
	  grabbed and sold like any honey, at the price of the moment.
	- Jars not collected are kept when the player leaves. More time away adds to them, but
	  the waiting jars never stand for more than OfflineMaxHours in all.
	- A save from before this existed has no LastSeen, so its first time away is not paid.
	- THE WINDOW: client module WelcomePanel ("Offline Honey" / "Welcome Back!"). It opens by
	  itself 1.5 s after joining when OfflineJars > 0. One green Collect button. Closing it
	  any other way (the red X, another window opening) collects too.
	- THE TWO RAINBOW LINES: client module LeaveBanner. A ScreenGui with "Your Bees Earn
	  Offline!" at the top and bottom, switched on by GuiService.MenuOpened and off by
	  MenuClosed (Roblox's own Esc menu). Roblox draws its menu on top, so the lines show
	  through it. The wording is mine (the owner said "bees earn offline").
	- CHECKED on a test save (BeeEmpire_TEST_Tutorial_A, 2.25 jars a second), by setting
	  LastSeen back in the test save from the command bar (DataStoreService works there):
	  3 hours away gave 12,154 jars = 2.25 x 0.5 x 10,804; Collect put them on the stand
	  (sign "12.2K"); 10 hours away gave 16,200 = exactly 4 hours; leaving without collecting
	  and coming straight back kept the same 16,200 (not lost, not doubled); the red X
	  collected; eight extra collect requests with made-up numbers gave nothing; an old save
	  with no LastSeen got no window. Phone screen: the window fits and the smallest writing
	  is 14 px. No script errors.
	- NOT CHECKED: the two lines appearing when Roblox's menu really opens. A script cannot
	  press Esc ("key is permanently bound to a CoreGUI core action"), so I switched the lines
	  on by hand for the picture. The owner has to press Esc once to see it for real.
	- TO KNOW: almost everything in the game costs less than one hour of honey, so a player
	  who comes back the next day can buy nearly all of it. I told the owner; they still
	  chose half speed. The later prices need to grow (see the first-3-minutes note above).
	  There is still no session lock.
	- Before: BeeEmpireDev.Backup_BeforeOffline. Pictures: new-look 68 (window), 69 (the two
	  lines), 70 (phone, with the lines switched on by hand).
DAILY REWARDS AND BOOSTS (2026-10-12)
	The owner: "daily rewards next, and the first one should be 500 coins, then you think of
	the rest and research and ask questions". Their answers: rewards are COINS, BEES AND
	BOOSTS; day 7 is an EMPEROR BEE; a missed day KEEPS YOUR PLACE; coin rewards are ALWAYS
	THE SAME (they do not grow with the hive). The rest of the list is mine.

	- THE WEEK (GameConfig.DailyRewards, one line per day, the last line is the tall card):
	  500 coins / Double Honey 10 min / Guard Bee / Double Luck 15 min / 5,000 coins /
	  Royal Bee / Emperor Bee. Then round again from day 1.
	- TIMING: GameConfig.DailyRewardHours = 20. The next reward can be collected 20 hours
	  after the last one was (not at midnight), so playing at the same time every day always
	  works. A new player's first reward is ready at once.
	- SAVED: data.Daily { Day = rewards collected in all, NextAt = os.time() from which the
	  next is ready }. Shared as DailyDay (Day mod 7) and DailyNextAt. Screens compare it
	  with workspace:GetServerTimeNow(), which is the same clock as the server's os.time()
	  (checked: 0.4 s apart).
	- Services.DailyService.Claim (remote ClaimDaily, no numbers in the request) gives the
	  reward. A BEE goes through the new BeeService.GiveBee: into a free hive spot, else the
	  bag; if both are full the reward is NOT used up and the player is told to make room.
	- BOOSTS (new): GameConfig.Boosts { Honey = Double Honey x2, Luck = Double Luck x2 },
	  BoostOrder, BoostMaxMinutes = 120. Services.BoostService keeps seconds left in
	  data.Boosts (saved) and runs them down once a second, ONLY while the player is in the
	  game. A boost starts when it is won; winning it again adds minutes. What a boost does:
	  ProductionService.Step multiplies jars arriving at the Honey Jars; BeeService.Roll
	  multiplies the luck of a roll; both ask DataService.BoostMultiplier. Offline honey is
	  never boosted. The screen is told when each boost ends (BoostEnds_Honey / _Luck).
	- SCREEN: client module DailyPanel (lime "Daily Rewards" window: six small cards and
	  the tall last day; a collected card is shaded with a tick; the next card has a green
	  Claim button, or shows the wait; on a phone the whole card can be tapped because the
	  button is only 19 px tall there). A calendar button at the left of the top row, with a
	  "!" while a reward is ready. The window also opens by itself once per visit when a
	  reward is ready: after the "Welcome Back!" window, and never during the tutorial.
	  HUD: one rainbow line per running boost ("x2 honey  9:41"), the jars-per-second and
	  luck numbers show the boost. New pictures: Calendar (blender\rewards.py, uploaded,
	  UIImages.Calendar) and Kit.BoostIcon (the jar or clover picture with "x2" on it).
	- CHECKED on test saves: the window after Welcome Back; day 1 gave 500 coins, shaded its
	  card, next wait 20.00 h, and a second request gave nothing; with the wait set to 0 for
	  the test, days 2 to 7 all gave the right thing (Double Honey: the stand gained 4.50
	  jars a second against 2.25; Guard, Royal and Emperor Bee went to the bag because the
	  hive was full; +5,000 coins; Double Luck showed "x2 luck" in rainbow) and the count
	  went back to day 1; leaving for 82 s kept the boosts' seconds (517 > 508 on return)
	  and offline honey was not doubled (95 jars for 85 s); phone: window fits, smallest
	  writing 12.8 px, tapping the card collects; a brand-new player got no pop-up during
	  the tutorial but could collect from the calendar button. No script errors.
	- NOT CHECKED: Double Luck by counting rolls (it is one line: luck x 2 in BeeService.Roll);
	  a boost running out to "has ended" (not waited for); two players.
	- TO KNOW: a new player who taps the calendar at once starts with 550 coins, which makes
	  the first minutes quicker than the timing above. Reward bees pile up for long-time
	  players (an Emperor Bee every 7 days).
	- Before: BeeEmpireDev.Backup_BeforeDailyRewards. Pictures: new-look 71 to 74.
	  Test saves: BeeEmpire_TEST_Tutorial_A (now rich in reward bees), BeeEmpire_TEST_Daily_New.
THE INVENTORY - DELETE AND LOCK INSTEAD OF SELL - BOOSTS WAIT UNTIL USED (2026-10-12)
	The owner: "we need an inventory to hold the extra bees you keep and boosts, two seperate
	tabs for those, keep the same style of ui ... also remove the sell bee part just make it
	a delete thing and add a lock feature. put it on the left side of the screen in the
	middle. also put the daily rewards in the top right of the screen, a smaller icon since
	itll auto open every time you get on and can get one of them". Their answers to my two
	questions: boosts WAIT in the inventory until Use is pressed; spare bees live ONLY in
	the inventory (the bag box left My Hive).

	- THE WINDOW: client module InventoryPanel (teal "Inventory" window, backpack picture).
	  Tab BEES: one card per kind of spare bee (strongest first, "x2" count, a padlock on a
	  locked kind); pick a kind, then Equip (PlaceBee: a free spot, or in place of a weaker
	  bee), Lock / Unlock, Delete (two taps: "Tap again!"), and Equip Best.
	  Tab BOOSTS: a "Running now" line with the time left, and one card per saved boost
	  (kind + minutes, "x2" count) with a Use button.
	- SELLING A BEE IS GONE. BeeService.DeleteBee (remote DeleteBee, was SellBee) removes one
	  spare bee for nothing; it still refuses the player's very last bee. The bees' SellValue
	  numbers were taken out of GameConfig. Selling HONEY is unchanged.
	- THE LOCK is per KIND of bee (bees of one kind are all the same): data.Locked
	  { Epic = true }, attributes Lock_<name>, BeeService.SetLock (remote LockBee). A locked
	  kind cannot be deleted; the server refuses even if a screen asks. It can still be
	  equipped or swapped out.
	- BOOSTS ARE ITEMS NOW. A boost reward calls BoostService.Give: it is counted in
	  data.BoostItems under "Honey_10" (kind_minutes; GameConfig.BoostItemKey /
	  ReadBoostItemKey), shared as BoostItem_Honey_10. BoostService.Use (remote UseBoost,
	  kind + minutes) checks the player has one, refuses if more than BoostMaxMinutes of that
	  kind would be running, takes one away and starts it. Boosts already running in old
	  saves just keep running.
	- MY HIVE (HivePanel, rewritten on the right side): hive spots, then Take Out, Equip Best
	  and an Inventory button with the number of spare bees. Tapping an empty spot opens the
	  Inventory. No bag box, no Place, no Sell.
	- HUD: the Inventory button (backpack + the word) is on the left edge in the middle; on a
	  phone the counters sit to its right. Its "!" shows while a spare bee is waiting and the
	  hive has a free spot (that "!" used to be on My Hive). Bees bought with a full hive fly
	  into it. The Daily Rewards calendar is now a small picture with no plate at the right
	  end of the top bar (the top row is Equip Best, My Hive and the gear again).
	  Both use the new pictureButton helper in HUD.
	- WORDS: "bag" became "Inventory" in the messages ("Your Inventory is full! Delete a
	  spare bee first."). The hint for "a spare bee and a free spot" now says "Your hive has
	  room for a spare bee! Press Equip Best!". MaxBeesInBag (20) is still the limit.
	- New picture: Backpack (blender\rewards.py mode backpack, uploaded, UIImages.Backpack).
	- CHECKED on test saves: the window opens from the button; lock shows a padlock, is saved,
	  and a forced delete of a locked kind was refused; one tap on Delete does nothing, two
	  taps remove one bee and pay nothing; Equip put an Emperor Bee into a full hive in place
	  of a Worker Bee; day 2 of the daily rewards put Double Honey in the inventory and did
	  NOT start it; Use added 900 s of Double Luck and took one away; asking for boosts the
	  player does not have gave nothing; Take Out moved a bee to the inventory and the "!"
	  appeared; a brand-new player started normally and a bee bought with a full hive became
	  a spare bee. Phone: both windows fit; smallest writing 10.4 px (a bee's name on its
	  card); the word "Inventory" no longer touches the counters. No script errors.
	- NOT CHECKED: the limit of 2 hours of one boost running (the refusal message); the
	  Inventory with all ten kinds and 20 bees; the Boosts tab on a phone.
	- Before: BeeEmpireDev.Backup_BeforeInventory. Pictures: new-look 75 to 80.
	  Test saves: BeeEmpire_TEST_Tutorial_A, BeeEmpire_TEST_Inv_New.

	THE SHOP AND THE SIX PASSES (2026-10-12)
	- Michal asked for: game passes ("one that is infinite storage/inventory, a starter pack
	  that is super cheap and seems really good but isnt too op just like an epic bee and some
	  boosts, and the +2 rolls and make the upgrade one just say max at 3"), my own ideas, the
	  same style, and the shop icon above the Inventory. His answers to my questions: also
	  build Auto Sell, VIP and Lucky Queen (NOT Double Honey Forever); Starter Pack = 1 Royal
	  Bee + 2 Double Honey + 2 Double Luck boosts of 15 minutes; yes to a small "Bee Chances"
	  button in the Shop; prices Starter Pack 25, Infinite Inventory 99, +2 Rolls 199 Robux.
	  (My suggestions for the other three, not yet agreed: Auto Sell 149, VIP 249, Lucky
	  Queen 299.)
	- THE PASSES DO NOT EXIST ON ROBLOX YET. Each must be made on the Roblox website (Creator
	  Hub > the game > Monetization > Passes), then its number goes in GameConfig.Passes
	  (Id = ...). While an Id is 0 the pass is not on sale: its card says "Soon" in Studio and
	  is hidden in the real game (with no Ids at all, the Shop button is hidden too). Prices
	  are set on the website; the Shop reads them from Roblox (never from our files). Pictures
	  for the website: Downloads\roblox game\Pass icons (512 x 512, made from ui-icons).
	- GameConfig "THE SHOP": Passes, PassOrder, StarterPack (what it gives), LuckyQueenLuck
	  (2), AutoSellSeconds (1), InfiniteBagLimit (5000, a safety number), VipHoney (1.1).
	  Also new there: THE CHANCES OF A ROLL (BeesOfRarity, RarityChances, BeeChances). The
	  Queen rolls with these and the Shop shows them, so they can never disagree.
	- Server. PassService: asks Roblox who owns what (UserOwnsGamePassAsync) on joining and
	  again after a purchase window closes with "bought"; asks PolicyService whether this
	  player may be sold passes that change random rolls (ArePaidRandomItemsRestricted; until
	  answered it counts as "no"); helpers Owns, LuckMultiplier, HoneyMultiplier, BagLimit,
	  ExtraStands. Marks on the player: Pass_<name>, RandomPassesAllowed, PassesChecked.
	  ShopService: opens the Starter Pack once (save field StarterPackOpened; the bee always
	  fits, GiveBee(..., true)), refreshes the stands for +2 Rolls, dresses a VIP (crown =
	  BeeMeshes.Crown x1.5 welded to the head, gold "VIP" + name billboard, Roblox's own name
	  hidden), and handles the Buy request (remote BuyPass: the SERVER opens Roblox's purchase
	  window after checking). Main: PassService.Begin before the save loads, then waits up to
	  4 s for Roblox's answers so stands are right from the first moment.
	  Other scripts: BeeService (stands, luck x2, bag limit), ProductionService (VIP honey with
	  the part-jar carried over; Auto Sell sells JarsStored once a second at the server's
	  price, unless Settings.AutoSell is false), OfflineService (VIP honey counts offline),
	  DataService (Settings.AutoSell, StarterPackOpened, BagLimit, VIP in JarsPerSecond; the
	  bag's hard limit when loading is now InfiniteBagLimit), SettingsService ("AutoSell").
	- "MAX at 3": Upgrades.PassLevels and ShownMaxLevel are gone. More Rolls reads
	  "Level 3 / 3" and MAX. The describing functions take a "bonus" (the pass's 2 stands), so
	  an owner reads "5 bees per roll"; the board in the world gets the same bonus.
	- Screen. ShopPanel (pink window, six wide cards: picture left, name and words right,
	  button underneath; Starter Pack has a red DEAL! flag). Buttons: Robux sign + price,
	  "Soon" (no Id), "Not available" (roll-changing pass in a restricted country), "Owned" /
	  "Opened", and for Auto Sell an ON/OFF switch. "Bee Chances" page: every bee's chance now
	  and with x2 luck, at the luck the player really has (boost and Lucky Queen counted), a
	  note about +2 Rolls and rounding. HUD: Shop button (market stall) lives INSIDE the
	  Inventory button's frame, 110 above it, so it scales and hides with it. VipChat: gold
	  [VIP] before chat messages (reads the server's Pass_VIP mark). State: OwnsPass,
	  RandomPassesAllowed, BagLimit, PassStands, PassLuck, RollLuck, AutoSellOn. Inventory
	  count says "(no limit)" for owners. No "Sell now!" message while Auto Sell is on.
	- WHY THE CHANCES LIST: Roblox's paid-random-items rule. Anything bought with Robux that
	  changes random outcomes (luck boosts, more rolls) needs every outcome's chance shown
	  before buying, and may not be sold where ArePaidRandomItemsRestricted is true. That is
	  why three passes carry Random = true (the Starter Pack because of its luck boosts).
	- TESTING WITHOUT REAL PASSES (Studio only): attributes on ServerStorage.BeeEmpireDev:
	  TestPass_<name> = true gives the pass (set in Edit to own it on joining, or on the
	  running server to "buy" it mid-game), TestNoRandom = true pretends a restricted
	  country. They only work when RunService:IsStudio(). A purchase made in Studio is
	  believed too (Studio purchases are pretend ones).
	- Pictures: blender\shop.py (Shop, PassStarter, PassInventory, PassRolls, PassAutoSell,
	  PassVIP, PassLucky), ids in UIImages (Shop, Passes) and icon-tools\asset-ids.txt.
	- TESTED on test saves (BeeEmpire_TEST_Tutorial_A, BeeEmpire_TEST_Shop_New2), one player:
	  +2 Rolls: 1 stand became 3, the board said "3 > 4", every roll gave 3 bees. Lucky Queen
	  with a Double Luck boost: the screen said x4 luck and 27 rolled bees held no Common ones
	  (at x4 there are none; at x2 a third would be). Auto Sell: 112,306 waiting jars sold at
	  once for 471,685 coins at x2.1, jars stayed at 0, switch off/on worked. VIP: crown,
	  gold name, jars per second x1.1. Starter Pack: Royal Bee went to work, 2 + 2 boosts in
	  the Inventory, saved as opened, NOT handed out again after rejoining. Owned on joining
	  (brand-new save): stands, crown and pack were all there at the start, tutorial still
	  ran. Infinite Inventory: limit 5000, count says "(no limit)". Requests: nonsense pass
	  names ignored; an owned pass answers "You already have VIP!"; no Id answers "not on
	  sale yet"; a restricted country answers "not available in your country" and the card
	  says "Not available". Phone: buttons clear of Roblox's top bar; smallest writing in
	  the Shop 10.4 px. Roblox's Robux sign draws in the game's font. No script errors.
	- NOT CHECKED (needs real passes): a real purchase from start to finish; the price read
	  from Roblox; the [VIP] chat tag; two players seeing each other's crown; Infinite
	  Inventory with more than 20 bees actually in it; the 4-second wait when Roblox is slow.
	- Before: BeeEmpireDev.Backup_BeforeShop. Pictures: new-look 81 to 86.

	THE PASSES ARE REAL NOW (2026-10-12, later the same day)
	- Michal made the six passes on the Roblox website and sent their numbers. They are in
	  GameConfig.Passes: Starter Pack 2031986278, +2 Rolls 2030036311, Lucky Queen 2030126311,
	  Auto Sell 2032862250, Infinite Inventory 2030624310, VIP 2030714311. Roblox confirmed
	  each one (right name, on sale, made by Michal's account) and his prices: Starter Pack
	  25, +2 Rolls 199, Lucky Queen 99, Auto Sell 149, Infinite Inventory 49, VIP 199 Robux.
	  (He chose lower prices than my ideas for Lucky Queen, Infinite Inventory and VIP.)
	- The Shop shows those prices, read from Roblox, with the Robux sign (new-look 87).
	- FOUND: in Roblox Studio, Roblox says the game's maker owns EVERY pass. All six switched
	  on at once and no price showed. So PassService now ignores Roblox's "owns" answer in
	  Studio: a tester starts with no passes, like a new player. TestRealPasses = true (on
	  BeeEmpireDev, Studio only) uses Roblox's answer again. The real game is not changed.
	  With Roblox's answer in use, all six passes applied on joining with no errors (3 stands,
	  crown, "Owned" on every card), so the real path is tested for an owner.
	- MANAGED PRICING (Michal asked): it is Roblox's regional pricing plus price tests, and is
	  on by default for new passes. The Shop reads each player's own price on their own
	  device (GetProductInfoAsync), which is what Roblox asks for, and no price is written in
	  our files. My advice was to leave it on.
	- NOT CHECKED: a real purchase by a player who does not own the pass (never click a
	  purchase window), the [VIP] chat tag, two players. The game must be PUBLISHED before
	  players see the Shop.

	THE HALLOWEEN EGG - A LIMITED-TIME EVENT, THREE LIMITED BEES (2026-10-12, evening)
	- Michal asked for: "a limited edition halloween egg that leaves in 2 weeks", "around the
	  flower garden just in an area", Halloween themed, "you need to give jars to it, 1k jars
	  to roll it", 3 bees, "one ultra rare that will be a 'secret' pet with like a very very
	  very very low rarity", all of them limited-time bees "as a rarity", not in Auto Roll.
	  Michal's answers: the secret costs about "20 mil jars" (= 1 roll in 20,000); it leaves after
	  2 November (he picked that over exactly 2 weeks, which ended before Halloween); luck
	  COUNTS (I had advised no); bees "Strong" (12 / 45 / 500 jars a second).
	  MINE, not yet judged: the names (Bat Bee, Ghost Bee, Pumpkin King Bee), Ghost Bee's 10%,
	  the look of everything, the spot, chances on a board at the egg with the secret as
	  "???", no server-wide message for the secret, the once-per-visit message.
	- BECAUSE LUCK COUNTS the secret is much easier for lucky players: 1 in 20,000 at x1 luck,
	  1 in 10,000 at x2, 1 in 5,000 at x4, about 1 in 1,700 at x12, 1 in 714 at x28 (a lot of
	  Queen's Luck + a Double Luck boost + the Lucky Queen pass). From x10 luck up there are
	  no Bat Bees at all (Ghost takes what is left). To stop that: LuckCounts = false.
	- GameConfig: Rarities.Limited (NOT in RarityOrder, so the Queen never rolls it and
	  Settings' Auto Roll list does not show it); Bees.Bat / Ghost / PumpkinKing (no Price;
	  PumpkinKing has Secret, Rainbow, BigReveal, Trail and Size 1.3; a bee's own flags now
	  win over its rarity's); they are in BeeOrder by strength; QueenBees = the bees the
	  Queen can roll (State's price hints and the Shop's list use it); HalloweenEgg { Ends,
	  JarCost, LuckCounts, Bees, HatchSeconds }; EggEndsAt(egg) (UTC; Day = 3 means the 2nd is
	  the last day); EggChances(egg, luck) (the Queen's rule: luck multiplies all but the most
	  common, which gets the rest). NEVER remove the three bees: players keep them.
	- Server. HalloweenService: on start, if the end has not come, clones
	  ServerStorage.BeeEmpireEvents.HalloweenCorner into the world, moves the map decorations
	  inside its circle to BeeEmpireEvents.MovedForHalloween (4 things at this spot), sets
	  workspace attribute HalloweenEggEndsAt, connects the egg's prompt. A loop every 15 s
	  removes the corner when the end comes and puts the decorations back. feed(): event on,
	  within 24 studs, not mid-hatch, JarsCarried >= cost, BeeService.HasRoom, then
	  ProductionService.TakeCarried, Pick(luck) (BeeService.RollLuck = the Queen's luck),
	  BeeService.GiveBee, effect "EggHatched". New helpers: BeeService.RollLuck / HasRoom,
	  ProductionService.TakeCarried. Nothing new is saved (bees are saved by name).
	- THE CORNER is built by BeeEmpireDev.HalloweenBuilder.Build() (a command-bar tool; it
	  reads FRESH copies of GameConfig / UIImages because Studio keeps old copies of required
	  scripts). Middle (40, 0, 71), front towards the garden's middle, ground radius 17.5.
	  Pieces from blender/halloween.py: HwEgg + HwEggGlow, HwPedestal + HwPedestalGems,
	  Pumpkin + PumpkinFace, Gravestone, SpookyTree, BatProp, Ghostie, Cauldron + CauldronGoo,
	  HwSign (in BeeEmpireDev.PropMeshes; raw import BeeEmpireDev.ImportedHalloween). Studs on
	  the ground, pedestal, pumpkins, gravestones, trees, cauldron and sign. Only two soft
	  lights (egg, cauldron): the game's bloom washed lit pumpkins out to yellow.
	  Bee outfits BatGear, GhostGear, PumpkinKingGear, PumpkinGlow are in BeeMeshes
	  (blender/halloween_gear.py, drawn through blender/bees.py modes hwpreview / hwicons).
	- Screen. WorldFX section 11 (tag "HalloweenCorner"): the egg breathes, bats circle,
	  ghosts bob, the board shows THIS player's chances, luck and the countdown, the secret
	  row is "???" and a black shape until the player owns one; PlayEggHatch shakes the egg.
	  ClientMain: "EggHatched" (shake, then the bee's card) and one message per visit.
	  Effects.Rolled: a Limited bee gets the middle card, the Secret one the big reveal with
	  "SECRET BEE!!!". ShopPanel's Bee Chances page has a second list for the egg (button
	  "Halloween Egg" / "Queen's Bees"), because paid luck changes the egg's chances too.
	  NumberFormat.Percent ("90%", "0.005%"). Kit: Limited card colours, HalloweenEggIcon.
	- Auto Sell owners carry no jars: the egg tells them to switch Auto Sell off in the Shop.
	- TESTING (Studio only): BeeEmpireDev attribute TestEggEndsIn = seconds makes the event
	  end that long after the server starts (0 = already over).
	- TESTED on BeeEmpire_TEST_Tutorial_A: 20 rolls took exactly 1,000 jars each; a second
	  press during the hatch did nothing; a full Inventory and too few jars each gave their
	  message and took nothing; Equip Best put three Ghost Bees to work (66 -> 185 jars a
	  second); the secret reveal (its chance raised for the test, then put back to 0.005);
	  with TestEggEndsIn = 80 the corner vanished by itself, the 4 decorations came back and
	  the bees stayed; a server started after the end has no corner and no errors. Dice: 2
	  million pretend rolls at x1 luck gave 84 secrets (100 expected), at x4 394 (400
	  expected). Phone: corner, board and the Shop's egg list all readable.
	- NOT CHECKED: the egg's prompt on a real phone tap; two players at the egg at once; the
	  trail and sparkles of a Pumpkin King flying to the flowers; frame rate with the corner.
	- Before: BeeEmpireDev.Backup_BeforeHalloween. Pictures: new-look 88 to 94.

	THE HALLOWEEN EGG SANK INTO ITS PEDESTAL - FIXED (2026-10-12, late)
	- Michal: "i dont like the way the pumpkin egg is sitting like clipped in the ground, make
	  it stand up". He was right, and my test pictures had missed it (my own character stood
	  in front of the egg in every one).
	- Cause: WorldFX moves the egg every frame with EggModel:PivotTo(BasePivot ...). BasePivot
	  is the point the egg stands on. But a Model with a PrimaryPart is moved by THAT PART's
	  handle (its middle), not by Model.WorldPivot, so the egg's middle was put on the
	  pedestal and the egg sank about 3.4 studs (and was turned half round).
	- Fix, in BeeEmpireDev.HalloweenBuilder: Egg.PivotOffset = Egg.CFrame:ToObjectSpace(the
	  standing point), the same thing BeeModelFactory does for a bee's body. Rebuilt the
	  corner. Measured in play: the egg's bottom now moves between y 1.43 and 1.66 (pedestal
	  top 1.46) and its face looks straight at the garden. Picture: new-look 95.
	SERVER SIZE IS 6 - THE "60" WAS ONLY STUDIO'S READING (2026-10-13)
	- Michal asked "how do i make it 6 player servers". game.Players.MaxPlayers still read 60
	  in Studio, as it had for days. His screenshot of the Creator Dashboard (Places > the
	  place > Access > "Maximum Visitor Count") showed 6, and he said "its been on 6".
	- So: Players.MaxPlayers read from Studio is NOT the game's real server size. The real
	  number is only on the website. Do not report "60" again.

	THUMBNAILS AND THE GAME ICON (2026-10-13) - PICTURES ONLY, NOTHING IN THE GAME CHANGED
	- Michal sent three thumbnails of the ant game and asked for "some thumbnails for the
	  game like so". His answers: all three scenes (a giant bee over the hive, riding a giant
	  bee, a line of bees to the hive), a "Beekeeper kid" as the character, no words, and a
	  square icon too.
	- Made with blender/thumbnails.py in the session folder (modes: queen ride line icon, and
	  "draft" for a quick half-size try). It borrows the makers from bees.py, hives.py,
	  props.py and garden.py, so the pictures show the game's own models. Made only for the
	  pictures: the kid (straw hat, bee-striped shirt, posable arms and legs), a honey jar,
	  clouds, a square sun.
	- The look: Cycles, a perspective camera low to the ground, studs pressed into the lawn
	  and every map piece (a shader, one stud per stud), a sky that fades by picture height.
	  The lawn throws back pale light instead of its own green, or every white thing above
	  it turns mint green. Clouds shine a little by themselves for the same reason.
	- The giant bee in pictures 1 and the icon is the Queen exactly as PlotBuilder makes her
	  (yellow, RoyalGear + Crown). No bee can be ridden in the game: picture 2 is the style
	  of Michal's example, not a feature. Told him so.
	- Files for Michal: Downloads\roblox game\Thumbnails ("1 Giant Queen", "2 Riding a giant
	  bee", "3 Line of bees": 1920x1080 PNG, each about 2 MB, under Roblox's 3 MB; "Game
	  icon": 512x512). Copies: new-look 96 to 99. He uploads them himself on the Creator
	  Dashboard (Configurations > Places > the place > Thumbnails / Icon).
	- A full-size picture takes about 3.5 minutes on this PC, a draft about 10 seconds.
	NEW SKY AND LIGHT, AND THE OUTSKIRTS (2026-10-13)
	- Michal: "now make the lighting and sky a little better in the game, its pretty bland, and
	  make the outskirts a little better as well". No questions asked this time; every choice
	  below is mine and not yet judged by him.
	- What was wrong: the place still had the starting template's grey Atmosphere and its
	  Bloom next to ours. Only the FIRST Atmosphere counts, so our blue "BeeHaze" had never
	  shown: everything far away faded to grey. The sun stood almost overhead (ClockTime 13.5,
	  latitude 0), so nothing threw a shadow. The sky had no clouds. The outskirts were two
	  bare lilac walls, 526 to 680 studs long.
	- New dev tool: ServerStorage.BeeEmpireDev.SceneryBuilder (Sky(), Outskirts(), Build()).
	  PlotBuilder.BuildWorld() now ends by calling Build() on a fresh copy, instead of setting
	  its own light, so a map rebuild keeps both. Run by hand:
	  require(game.ServerStorage.BeeEmpireDev.SceneryBuilder:Clone()).Build()
	- Sky(): all numbers are in the LOOK table at the top of the tool. ClockTime 14, latitude 22
	  (sun about 60 degrees up: real shadows, but the 57-stud cliff's shadow stops before the
	  home areas); warm sunlit sides (ColorShift_Top), bluish shade (Ambient / OutdoorAmbient);
	  ONE blue Atmosphere "BeeHaze"; "BeeColor", "BeeBloom" (0.5 / 28 / threshold 1.6),
	  "BeeSunRays"; Roblox's own drifting Clouds under Terrain ("BeeClouds"). It deletes every
	  PostEffect and Atmosphere in Lighting first. The Sky object (Roblox's template sky) is
	  kept; its sun is a little bigger and its stars are off. No live script touches Lighting.
	- Outskirts(): makes workspace.Map.Outskirts (about 1,200 parts, all Anchored, cannot be
	  bumped, touched or clicked, Locked). The cliffs themselves (Map.Walls) are unchanged.
	    CliffFaces  blocks of lighter and darker rock on the faces, grass hanging over the edges
	    Outcrops    piles of rock with grass caps on the tall cliff, so its top is not a ruler line
	    CliffPlants trees, bushes, rocks, big garden flowers, giant mushrooms on both cliff tops
	    CliffFoot   bushes, rocks, grass and little flowers on the lawn right at the wall
	    HoneyFalls  six, one behind every home (sides z: along 0; sides x: along -90 and 90):
	                a giant hive on the tall cliff (HiveMeshes Hive1 x3.3 or Hive3 x2.1), honey
	                over both cliffs into a thin puddle on the lawn, giant honeycomb cells
	                (the hive-window pieces, x7 and x5.4)
	    FarHills    big stepped hills behind the cliffs (CastShadow off)
	  Stud pictures go only on faces a player can see (top, the inward side, the ends).
	  Fixed seeds: the layout is the same every time.
	- Tested in play on BeeEmpire_TEST_Tutorial_A (real save name put back and checked): the
	  light is the same while playing, no errors, Halloween corner looks right, 60 frames a
	  second on this PC. NOT measured: speed on a real phone, and how it looks on a phone's
	  low graphics setting (Roblox switches the clouds and shadows off there by itself).
	- The frame-time test "with / without the outskirts" was useless (taking 1,200 parts away
	  made Studio stutter): do not trust that number.
	- Undo: Backup_BeforeNewSky holds the old Lighting children, the old Lighting numbers (as
	  attributes), the old PlotBuilder and the old Walls. Deleting Map.Outskirts removes the
	  scenery. Pictures: new-look 100 (before) to 103.
	THE LOADING SCREEN (2026-10-13)
	- Michal sent the ant game's loading screen (an apple sign with the game's name, a crowned
	  beetle, "Loading(96%)") and asked: "make a loading screen for the game like this ... and
	  include a skip button in the bottm right corner. this is to make sure everything loads in
	  properly before the player can play, but make sure it doesnt last too long loading in".
	  Michal's answers: a honeycomb sign, 8 seconds at the longest, and yes to a tip line. While I
	  was testing he added: "also remove the jars they are out of place and look bad" (I had a
	  row of little honey jars filling up, with a bee flying along them: gone, bee and all).
	- The script: ReplicatedFirst.BeeEmpireLoading (LocalScript). It runs before anything else
	  has arrived, so it cannot use UIKit or GameConfig: its colours, font and the three
	  timings (LONGEST = 8, SHORTEST = 2.5, FADE = 0.45) are at its own top.
	- What it waits for: its own picture, game.Loaded, the menu pictures (UIImages.All), the
	  stud picture, the BeeMeshes and HiveMeshes pieces, the player's DataLoaded attribute, the
	  character. The percent is real (12 + 13 + 45 + 18 + 12).
	- It goes when all of that is ready (never before SHORTEST), or at LONGEST, or on Skip. A
	  safety net removes it at LONGEST + 2.5 whatever happens, and the main loop sits in a
	  pcall: a broken loading screen must never lock anybody out.
	- While it shows: walking and jumping are swallowed, touch controls hidden, ProximityPrompts
	  off, Roblox's own buttons (chat, player list...) off. All are put back to what they were.
	  The player has the attribute LoadingScreen = true (client side only);
	  State.LoadingScreenUp() reads it, and the Welcome Back window, the Daily Rewards pop-up
	  and the Halloween Egg message all wait for it.
	- The picture: blender/thumbnails.py mode "loading", 2400 x 1080 (phone-wide, on purpose:
	  a 16:9 picture lost its bottom on a wide phone and cut the Queen in half). A wide phone
	  shows all of it; a desktop or tablet shows the middle. Roblox shrinks pictures to 1024,
	  so it is uploaded as three strips of 816 that overlap by 24 (STRIPS in the script;
	  numbers also in icon-tools/asset-ids.txt). Two earlier uploads (LoadingLeft / Right)
	  are not used.
	- The game's name is NOT in the picture: two TextLabels (and their dark shadows) sit on the
	  sign, leaning 9 degrees like it. Where the sign is comes from the Blender script's
	  "SIGN middle" printout (SIGN in the script). Move the sign and that number must follow.
	- A UIGradient on a CanvasGroup tints EVERYTHING inside it (the whole picture went blue).
	  The sky fade sits on its own Frame.
	- Tested on BeeEmpire_TEST_Tutorial_A (real save name put back): closes at 2.8 s when all
	  is loaded; Skip closes it at once; with the save held back it sat at 82% and closed at
	  8.00 s; Welcome Back opened about a second after it had gone; desktop and phone size
	  looked at. NOT tested: a real phone, a real slow connection, a tablet (4:3) by eye.
	- Undo: delete ReplicatedFirst.BeeEmpireLoading (Roblox's own loading screen comes back);
	  the four changed client scripts are in Backup_BeforeLoadingScreen.
	  Pictures: new-look 104 to 106.
	"OTHER PLAYERS' BEES" IN SETTINGS (2026-10-14)
	- Michal: "halloween egg works with two people" (his own test: the egg with two players at
	  once now works), then "add a option in settings that turns off other peoples bees just in
	  case some people are overwhelmed or it lags". His answers: hide their FLYING bees (the
	  foragers going to the flowers and the honey carriers; their Queen and their roll stands
	  stay), and show them by default for everyone.
	- Saved like the other settings: data.Settings.OtherBees (true = shown, the default; an old
	  save without it counts as shown), attribute Set_OtherBees, remote SetSetting
	  ("OtherBees", boolean), checked in SettingsService. State.ShowOtherBees().
	- SettingsPanel: a row "Other players' bees" under Sounds with one Kit.Button, "Shown"
	  (green) or "Hidden" (grey), the same look as the Shop's Auto Sell switch. The window is
	  one row taller; on a phone with Auto Roll bought it still fits (checked).
	- WorldFX section 5d: a bee that is under a plot that is not mine, while the setting says
	  hidden, gets LocalTransparencyModifier = 1 on every part (this device only) and its
	  sparkles / trails / lights switched off; moveForagers and moveWorkers skip it, so it is
	  not moved at all. Showing again puts each sparkle back as it was.
	- Bug found and fixed in the test: the "what was each sparkle before" table was a WEAK table
	  keyed by Roblox objects. Luau dropped the entries (the object's Lua wrapper is collected
	  even though the object lives on), so the sparkles never came back. Now a normal table,
	  emptied when a bee is shown again or removed. Never key a weak table by Instances.
	- Tested in one-player play on TEST saves: copies of my bees put into an empty home were
	  hidden and still, mine kept flying; shown again they flew and sparkled; the choice was
	  still in the save after leaving; the Settings button switched it; the window fits a phone.
	  NOT tested: a real second player, and how much it really helps on a slow phone.
	- Undo: Backup_BeforeOtherBees (DataService, SettingsService, State, SettingsPanel, WorldFX).
	  Pictures: new-look 107 and 108.
	WALK SPEED UPGRADE (2026-10-14)
	- Michal: "now in the upgrades shop add player walkspeed, cap it at 1.5x normal and make it so
	  each upgrade is 0.01 so you need it 50 times, this will slow progression down if people want
	  to max it out". Michal's answers: about 1 million coins to max it (first step 150, each 15%
	  dearer, the same growth as Queen's Luck) and the name "Walk Speed".
	- GameConfig.Upgrades.WalkSpeed = { Name, WindowOnly = true, Steps = { Step = 0.01, Top = 1.5,
	  FirstCost = 150, Growth = 1.15 } }; UpgradeOrder has it before Roll Speed. Real prices:
	  150, 170, 200, 230 ... the last (level 50 -> 51) 140,000; x1.1 costs 3,050 in all, x1.25
	  31,880, all 50 steps 1,078,980.
	- Upgrades module: a new kind, STEPPED (Steps rule): like Queen's Luck's endless rule but with
	  a top. MaxLevel = 1 + (Top - 1) / Step = 51 (level 1 = nothing bought). LevelText shows
	  "7 / 50 bought". New helpers IsStepped (luck or walk speed) and WindowOnly.
	- Server: UpgradeService.ApplyWalkSpeed(player) sets Humanoid.WalkSpeed = GameConfig.WalkSpeed x
	  the upgrade (x1 until the save has loaded). Main calls it on every CharacterAdded and once the
	  save is in; buying a step calls it. Nothing else sets WalkSpeed.
	- Not on the board in the yard (it has room for four): PlotBuilder skips WindowOnly upgrades,
	  like Roll Speed. The board in the place was not rebuilt.
	- The tutorial hint counts it like Queen's Luck (State.UpgradeWorthAVisit uses IsStepped), so
	  new players are not sent to buy small steps before their next hive.
	- Picture: blender/walkspeed.py (a bee-striped sneaker with a wing and speed lines) ->
	  UIImages.WalkSpeed rbxassetid://89333949046329, Kit.WalkSpeedIcon.
	- Tested on BeeEmpire_TEST_TenBees_A (real save name put back): 20 -> 20.2 -> 20.4 -> 20.6 for
	  150 / 170 / 200 coins; level 50 -> 51 cost 140,000 and gave exactly 30; one more was refused
	  ("Walk Speed is already at its best!"); 30 again after respawning; the window with six rows
	  fits a phone (scale 0.34: small but readable). That test save now has Walk Speed maxed.
	- FirstMinutesSim does not know about Walk Speed (its timings ignore it).
	- Undo: Backup_BeforeWalkSpeed (GameConfig, Upgrades, UIImages, UIKit, UpgradePanel, State,
	  UpgradeService, Main, PlotBuilder). Pictures: new-look 109 and 110.
	BETTER SOUND EFFECTS (2026-10-14)
	- Michal: "the overall music is good, but the sound affects need to be better, research what
	  other games have, ask questions and then change it to more satisfying and just overall better".
	  Michal's answers: bubbly cartoon style; rarer bees sound bigger (Common a pop ... Legendary a big
	  show); add bees buzzing at hives (he did NOT pick: a 'not enough coins' sound, a window-close
	  sound, hover ticks); I pick the sounds and he listens afterwards. The music was not touched.
	- Before: 6 sounds built into Roblox (clickfast, switch, electronicpingshort, victory, Kerplunk,
	  snap). The same "victory" tune played for upgrades, hives, passes and every bee above Common.
	- Source: ONLY Roblox's licensed library: Pro Sound Effects recordings ("Courtesy of Pro Sound
	  Effects", creator ProSoundEffects). Most other free uploads are copied from other games.
	  The Pro library is real recordings (no ready-made cartoon UI set), so the bubbly style is
	  BUILT: pops, a xylophone-like ding played at different pitches (chords and runs), a
	  triangle, a shaker, pixie twinkles, a magic burst, a desk bell, whooshes and a bee swarm.
	- GameConfig.Sounds = 11 sounds (Id, Volume, From/To = part of the recording, Speed, Vary =
	  random pitch wobble). GameConfig.SoundTunes = 20 jingles, each a list of { sound, start,
	  pitch, loudness }. SoundScale = the notes coins and jars climb as they land. RiseLead, BuzzNear,
	  BuzzFar. To swap a sound, change its Id (and Volume) in GameConfig; nothing else.
	- Volumes: measured with ServerStorage.BeeEmpireDev.SoundLab (AudioPlayer:GetWaveformAsync,
	  so nothing plays out loud), set so each sound is about as loud as the old one in its place.
	  AssetService:SearchAudio searches the library from the command bar (Artist, Description).
	- UIKit SOUNDS: Kit.PlaySound(name, pitch, loudness) plays a jingle or a single sound (always a
	  clone, so the pitch can wobble); the same jingle asked again within 0.1 s plays once (3-5
	  stands roll together); of bee reveals at the same moment the rarest wins. Kit.ScaleNote,
	  Kit.RevealSoundFor(bee) (Common Reveal1 .. Epic Reveal4, top tier and secret BigReveal,
	  Limited = Rare), Kit.LoopSound (3D loop that follows the Sounds slider).
	- Where they play: buttons Click; windows Open; stands Shake / GoldEgg (+ Rise timed to peak on
	  the reveal) / Shadow / Reveal1-4 / BigReveal; buying from a stand Buy (top tier Celebrate:
	  Effects.Rolled's new 3rd argument `bought`); daily/egg/starter-pack bees their reveal jingle;
	  Sell (desk bell) + coins landing climb a scale; Jar + jars landing climb; Upgrade; hive, pass
	  Celebrate; boosts, offline honey, starter pack, Halloween toast Reward; great price Alert;
	  deleting a bee Delete; the Halloween Egg's shakes climb + Rise into the hatch.
	- WorldFX section 12: every OWNED hive (OwnerUserId ~= 0) gets a BuzzSpot attachment half way
	  up with a looping Buzz (full within 8 studs, gone by 40). Checked every second.
	- Tested on BeeEmpire_TEST_TenBees_A (real name and Legendary chance put back, checked): all 11
	  sounds load in play; roll, shadow, reveal, buy, grab jars, sell, Legendary golden egg (with
	  Legendary at 60% for one run) all played the right jingles at the right times; the coin and
	  jar notes climb in landing order; only the owned hive buzzes; every jingle plays without error.
	  NOT judged by ear: I cannot hear. Michal listens and says which to swap.
	- Undo: Backup_BeforeBetterSounds (GameConfig, UIKit, Effects, WorldFX, ClientMain, HUD).
	NEW BEE AND HIVE SCREENS (2026-10-14)
	- Michal: "the ui when you buy a new bee or hive is ugly, we need to make it more satisfying and just
	  overall a lot better". Michal's answers: the full-screen reveal ONLY for Legendary (and the secret bee);
	  the "glowing spotlight" look; show the chance ("1 in 50") and nothing else (not honey per
	  second, not NEW!, not hive space); the hive screen shows the old hive turning into the new one.
	- Effects, section BIG REVEALS (rewritten): startReveal dims (0.35) and blurs the world (a
	  BlurEffect "RevealBlur" in the camera, this screen only, size 14) and builds a Stage that
	  shrinks away on close; closeWhenDone (tap after 0.6 s, or the hold time); makeLight (a glow in
	  the colour, coloured rays turning one way, white rays the other, a breathing white heart);
	  makePill; twinkles (stars that pop and fade round a spot while the reveal is up); confetti
	  moved up here (with a zIndex so it falls over a reveal).
	- Spotlight (Legendary / secret, from Effects.Rolled): the 3D bee turns and bobs on the light,
	  rarity in big letters (rainbow for the best) rocking, the bee's name, a pill "1 in 333"
	  (chanceText: GameConfig.BeeChances(State.RollLuck()), or EggChances for Halloween bees), 12
	  twinkles, 80 confetti, 4.5 s (secret 6 s), then the bee flies to the My Hive button.
	- Small card (every other bee): slides up at the bottom (520 x 134, does not block), a CanvasGroup
	  body with the rarity fade, a gloss and a shine that sweeps once, the bee picture big on the left
	  on a glow (+ turning rays from Rare, + twinkles from Epic), a yellow NEW BEE! tab, the name, a
	  rarity pill and a chance pill. 2.2 s, then the bee flies to the bag and the card slides down.
	- Hive: the old hive shakes harder and harder under a dim light (its viewport CAMERA tilts: a
	  3D picture cannot be rotated like a flat one) for 1.05 s with three climbing Shake sounds,
	  then a flash, Celebrate, the new hive pops in turning, full light, confetti, HIVE UPGRADED!,
	  its name and a pill "4 bees > 6 bees" whose new number counts up (RichText, lime).
	- Pictures: UIImages.Fx = Rays 121656174186329, Glow 78079692624152, Sparkle 123529723591210:
	  white, drawn by code (icon-tools/make-fx.ps1), tinted in the game; added to UIImages.All().
	- Not changed: the big LEGENDARY! letters and confetti on the stand when one hatches (BigReveal).
	- Tested on BeeEmpire_TEST_TenBees_A (real name put back, checked): pictures of every screen on a
	  computer and on the phone simulator (samsung_galaxy_a06, put back to average_laptop); a real
	  roll and buy showed the small card with "Common" and "1 in 2" and it went away after 3 s; no
	  game errors. "tap to close" made bigger after the phone pictures. Pictures: new-look 111-119.
	- Undo: Backup_BeforeNewReveals (Effects, UIImages).
]]

return nil
