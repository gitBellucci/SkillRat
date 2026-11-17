-- SkillRat: level your professions for the fewest coins.
-- Core: saved data, professions, known recipes, items, vendor prices, money.
local ADDON, ns = ...
SkillRat = ns

ns.VERSION = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version") or "?"

-- Professions: our id (same as the recipe data) -> skill line and the spell used for its name and icon
ns.PROFESSIONS = {
  { id = 4,  skillLine = 171, spell = 2259 },  -- Alchemy
  { id = 2,  skillLine = 164, spell = 2018 },  -- Blacksmithing
  { id = 6,  skillLine = 185, spell = 2550 },  -- Cooking
  { id = 10, skillLine = 333, spell = 7411 },  -- Enchanting
  { id = 9,  skillLine = 202, spell = 4036 },  -- Engineering
  { id = 1,  skillLine = 129, spell = 3273 },  -- First Aid
  { id = 3,  skillLine = 165, spell = 2108 },  -- Leatherworking
  { id = 7,  skillLine = 186, spell = 2656 },  -- Mining (smelting)
  { id = 13, skillLine = 40,  spell = 2842 },  -- Poisons
  { id = 8,  skillLine = 197, spell = 3908 },  -- Tailoring
}
ns.PROF_BY_ID, ns.PROF_BY_LINE = {}, {}
for _, p in ipairs(ns.PROFESSIONS) do
  ns.PROF_BY_ID[p.id] = p
  ns.PROF_BY_LINE[p.skillLine] = p
end

function ns.Print(msg, ...)
  DEFAULT_CHAT_FRAME:AddMessage("|cffd6a020SkillRat|r " .. (select("#", ...) > 0 and msg:format(...) or msg))
end

function ns.DB()
  SkillRatDB = type(SkillRatDB) == "table" and SkillRatDB or {}
  local db = SkillRatDB
  db.prices = db.prices or {}      -- [itemID] = { t = time, min = copper, qty = total, list = { unit, qty, ... } }
  db.vendor = db.vendor or {}      -- [itemID] = copper, learned from vendors
  db.excluded = db.excluded or {}  -- [prof] = { [itemID] = true }
  return db
end

function ns.CharDB()
  SkillRatCharDB = type(SkillRatCharDB) == "table" and SkillRatCharDB or {}
  local c = SkillRatCharDB
  c.known = c.known or {}          -- [prof] = { [spellID] = true }, read from the profession window
  return c
end

---------------------------------------------------------------------------
-- Names, icons, money
---------------------------------------------------------------------------
function ns.ProfName(p)
  local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(p.spell)
  return info and info.name or ("Profession " .. p.id)
end

function ns.ProfIcon(p)
  return C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(p.spell) or 134400
end

function ns.ItemName(itemID)
  local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
  if not name and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
  return name
end

function ns.ItemIcon(itemID)
  local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)
  return icon or 134400
end

function ns.SpellName(spellID)
  local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
  return info and info.name
end

function ns.Money(copper)
  if not copper then return "?" end
  copper = math.floor(copper + 0.5)
  if GetMoneyString then return GetMoneyString(copper, true) end
  return ("%dg %ds %dc"):format(copper / 10000, (copper / 100) % 100, copper % 100)
end

-- signed amount: green +, red -
function ns.SignedMoney(copper)
  if not copper then return "?" end
  if copper < 0 then return "|cffff5555-|r" .. ns.Money(-copper) end
  return "|cff55ff55+|r" .. ns.Money(copper)
end

-- vendor sell price of one item (nil while the game has not loaded it)
function ns.VendorSell(itemID)
  local info = C_Item and C_Item.GetItemInfo or GetItemInfo
  local sell = select(11, info(itemID))
  return sell
end

-- what selling every crafted item of a plan to a vendor gives back; second value: items whose price is not loaded yet
function ns.PlanVendorValue(plan)
  local total, unknown = 0, 0
  for _, step in ipairs(plan.steps) do
    local r = step.recipe
    if r[2] and r[2] > 0 then
      local sell = ns.VendorSell(r[2])
      if sell then
        total = total + sell * step.crafts * math.max(1, r[3] or 1)
      else
        unknown = unknown + 1
      end
    end
  end
  return total, unknown
end

---------------------------------------------------------------------------
-- Your professions and their levels
---------------------------------------------------------------------------
-- Returns { [prof id] = { level, max } } for the professions this character has learned.
function ns.PlayerProfessions()
  local out = {}
  if GetProfessions and GetProfessionInfo then
    for _, index in pairs({ GetProfessions() }) do
      if index then
        local _, _, rank, maxRank, _, _, skillLine = GetProfessionInfo(index)
        local p = skillLine and ns.PROF_BY_LINE[skillLine]
        if p then out[p.id] = { level = rank or 0, max = maxRank or 0 } end
      end
    end
  end
  if next(out) == nil and GetNumSkillLines and GetSkillLineInfo then
    local byName = {}
    for _, p in ipairs(ns.PROFESSIONS) do byName[ns.ProfName(p)] = p end
    for i = 1, GetNumSkillLines() do
      local name, isHeader, _, rank, _, _, maxRank = GetSkillLineInfo(i)
      local p = not isHeader and name and byName[name]
      if p then out[p.id] = { level = rank or 0, max = maxRank or 0 } end
    end
  end
  -- what the profession window said last (more up to date while it is open)
  local c = ns.CharDB()
  for id, lv in pairs(c.levels or {}) do
    if out[id] then out[id].level = math.max(out[id].level, lv) end
  end
  return out
end

---------------------------------------------------------------------------
-- Recipes
---------------------------------------------------------------------------
-- Recipe entry fields (Data/Recipes.lua): 1 spell, 2 item made, 3 how many, 4 min (orange), 5 yellow, 6 grey,
-- 7 recipe item (0 = trainer), 8 reagents { itemID, count, ... }, 9 thresholds estimated
local recipeCache = {}
function ns.Recipes(profID)
  if recipeCache[profID] then return recipeCache[profID] end
  local list = {}
  for _, r in ipairs(ns.RECIPES[profID] or {}) do
    -- only recipes that exist in this client (WoW Forever drops some Classic and Season of Discovery ones)
    if ns.SpellName(r[1]) then
      list[#list + 1] = r
    end
  end
  if #list > 0 then recipeCache[profID] = list end
  return list
end

-- Reagents used by a profession's recipes (for scanning and the exclusion list)
function ns.ProfReagents(profID)
  local set, list = {}, {}
  for _, r in ipairs(ns.Recipes(profID)) do
    local reag = r[8]
    for i = 1, #reag, 2 do
      if not set[reag[i]] then
        set[reag[i]] = true
        list[#list + 1] = reag[i]
      end
    end
  end
  return list
end

-- Recipes this character knows, read from the profession window
local function ReadKnownRecipes()
  if not (C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetRecipeInfo) then return end
  local base = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
  local p = base and base.professionID and ns.PROF_BY_LINE[base.professionID]
  if not p and base and base.parentProfessionID then p = ns.PROF_BY_LINE[base.parentProfessionID] end
  if not p then return end
  local c = ns.CharDB()
  local known = {}
  for _, id in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
    local info = C_TradeSkillUI.GetRecipeInfo(id)
    if info and info.learned then known[id] = true end
  end
  if next(known) then c.known[p.id] = known end
  if base.skillLevel and base.skillLevel > 0 then
    c.levels = c.levels or {}
    c.levels[p.id] = base.skillLevel
  end
  ns.openProfession = p.id
  if ns.OnProfessionRead then ns.OnProfessionRead(p.id) end
end
ns.ReadKnownRecipes = ReadKnownRecipes

---------------------------------------------------------------------------
-- Vendor prices: defaults in Data/Vendor.lua, replaced by what vendors really ask
---------------------------------------------------------------------------
function ns.VendorPrice(itemID)
  local db = ns.DB()
  return db.vendor[itemID] or ns.VENDOR[itemID]
end

local function ReadMerchant()
  if not (GetMerchantNumItems and GetMerchantItemID and GetMerchantItemInfo) then return end
  local db = ns.DB()
  for i = 1, GetMerchantNumItems() do
    local itemID = GetMerchantItemID(i)
    if itemID and ns.VENDOR[itemID] then
      local _, _, price, quantity = GetMerchantItemInfo(i)
      if price and price > 0 then db.vendor[itemID] = price / math.max(quantity or 1, 1) end
    end
  end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("MERCHANT_SHOW")
pcall(ev.RegisterEvent, ev, "TRADE_SKILL_SHOW")
pcall(ev.RegisterEvent, ev, "TRADE_SKILL_LIST_UPDATE")
pcall(ev.RegisterEvent, ev, "TRADE_SKILL_CLOSE")
ev:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 == ADDON then ns.DB(); ns.CharDB() end
    if ns.OnAddonLoaded then ns.OnAddonLoaded(arg1) end
  elseif event == "PLAYER_LOGIN" then
    if ns.OnLogin then ns.OnLogin() end
  elseif event == "MERCHANT_SHOW" then
    pcall(ReadMerchant)
  elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_LIST_UPDATE" then
    pcall(ReadKnownRecipes)
  elseif event == "TRADE_SKILL_CLOSE" then
    ns.openProfession = nil
  end
end)

SLASH_SKILLRAT1 = "/skillrat"
SLASH_SKILLRAT2 = "/srat"
SlashCmdList.SKILLRAT = function()
  if ns.ToggleStandalone then ns.ToggleStandalone() end
end
