-- SkillRat: reagents sold by vendors (not searched on the Auction House).
-- Prices in copper are the usual Classic vendor prices; SkillRat replaces them with the real price as soon as you
-- open a vendor that sells the item.
local _, ns = ...

ns.VENDOR = {
  -- Threads
  [2320] = 10,     -- Coarse Thread
  [2321] = 100,    -- Fine Thread
  [4291] = 500,    -- Silken Thread
  [8343] = 2000,   -- Heavy Silken Thread
  [14341] = 5000,  -- Rune Thread
  -- Dyes and bleach
  [2324] = 25,     -- Bleach
  [2325] = 1000,   -- Black Dye
  [2604] = 50,     -- Red Dye
  [2605] = 100,    -- Green Dye
  [4340] = 350,    -- Gray Dye
  [4341] = 500,    -- Yellow Dye
  [4342] = 2500,   -- Purple Dye
  [6260] = 50,     -- Blue Dye
  [6261] = 1000,   -- Orange Dye
  [10290] = 2500,  -- Pink Dye
  -- Vials
  [3371] = 4,      -- Empty Vial
  [3372] = 40,     -- Leaded Vial
  [8925] = 500,    -- Crystal Vial
  [18256] = 30000, -- Imbued Vial
  -- Leatherworking / Blacksmithing / Engineering
  [4289] = 50,     -- Salt
  [2880] = 100,    -- Weak Flux
  [3466] = 2000,   -- Strong Flux
  [3857] = 500,    -- Coal
  [4399] = 200,    -- Wooden Stock
  [4400] = 2000,   -- Heavy Stock
  [10647] = 2000,  -- Engineer's Ink
  [4470] = 38,     -- Simple Wood
  [6217] = 124,    -- Copper Rod
  -- Cooking
  [159] = 5,       -- Refreshing Spring Water
  [1179] = 125,    -- Ice Cold Milk
  [2678] = 10,     -- Mild Spices
  [2692] = 40,     -- Hot Spices
  [3713] = 160,    -- Soothing Spices
  [2593] = 150,    -- Flask of Port
  [2594] = 1500,   -- Flagon of Mead
  [2596] = 120,    -- Skin of Dwarven Stout
  [30817] = 25,    -- Simple Flour
  -- Poisons
  [2928] = 20,     -- Dust of Decay
  [2930] = 50,     -- Essence of Pain
  [5173] = 100,    -- Deathweed
  [8923] = 200,    -- Essence of Agony
  [8924] = 100,    -- Dust of Deterioration
}
