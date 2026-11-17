-- SkillRat: Auction House scanning, written against Blizzard's C_AuctionHouse API.
-- For each item we keep every listing as { unit price, quantity }, cheapest first, so the planner knows both the price
-- and how many are really for sale (buying 60 Copper Bar may cost more per bar than buying 5).
local _, ns = ...

local Scanner = {}
ns.Scanner = Scanner

local MAX_PAIRS = 60          -- listings kept per item (cheapest first)
local FULL_SCAN_COOLDOWN = 15 * 60

local function AH() return C_AuctionHouse end

function Scanner.IsOpen()
  return AuctionHouseFrame and AuctionHouseFrame:IsShown() and AH() ~= nil
end

-- listings: { [unit] = qty } -> saved entry
local function Store(itemID, listings)
  local units = {}
  for unit in pairs(listings) do units[#units + 1] = unit end
  table.sort(units)
  local list, total = {}, 0
  for i, unit in ipairs(units) do
    total = total + listings[unit]
    if i <= MAX_PAIRS then
      list[#list + 1] = unit
      list[#list + 1] = listings[unit]
    end
  end
  local db = ns.DB()
  if #units == 0 then
    db.prices[itemID] = { t = time(), min = nil, qty = 0, list = {} }
  else
    db.prices[itemID] = { t = time(), min = units[1], qty = total, list = list }
  end
end
Scanner.Store = Store

---------------------------------------------------------------------------
-- Status (shown by the UI)
---------------------------------------------------------------------------
Scanner.status = ""
local function SetStatus(text, ...)
  Scanner.status = select("#", ...) > 0 and text:format(...) or text
  if ns.OnScanStatus then ns.OnScanStatus(Scanner.status) end
end

---------------------------------------------------------------------------
-- Full scan (the whole Auction House at once, every 15 minutes at most)
---------------------------------------------------------------------------
local full = CreateFrame("Frame")

function Scanner.FullScanCooldown()
  local last = ns.DB().lastFullScan or 0
  return math.max(0, FULL_SCAN_COOLDOWN - (time() - last))
end

local function FinishFull(byItem)
  local n = 0
  for itemID, listings in pairs(byItem) do
    Store(itemID, listings)
    n = n + 1
  end
  Scanner.busy = nil
  SetStatus("Full scan done: %d items priced.", n)
  if ns.OnPricesChanged then ns.OnPricesChanged() end
end

local function ReadReplicate()
  local total = AH().GetNumReplicateItems()
  local byItem, i = {}, 0
  Scanner.progress = 0
  SetStatus("Reading %d auctions...", total)
  local function step()
    if not Scanner.IsOpen() then
      Scanner.busy = nil
      SetStatus("Scan stopped: the Auction House was closed.")
      return
    end
    local last = math.min(i + 250, total) - 1
    for k = i, last do
      local info = { AH().GetReplicateItemInfo(k) }
      local count, buyout, itemID = info[3], info[10], info[17]
      if itemID and count and count > 0 and buyout and buyout > 0 then
        local unit = math.floor(buyout / count)
        local listings = byItem[itemID]
        if not listings then listings = {}; byItem[itemID] = listings end
        listings[unit] = (listings[unit] or 0) + count
      end
    end
    i = last + 1
    if i < total then
      Scanner.progress = i / total
      SetStatus("Reading auctions... %d%%", math.floor(i / total * 100))
      C_Timer.After(0.01, step)
    else
      FinishFull(byItem)
    end
  end
  step()
end

full:SetScript("OnEvent", function(self, event)
  if event == "REPLICATE_ITEM_LIST_UPDATE" then
    self:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE")
    ReadReplicate()
  end
end)

function Scanner.FullScan()
  if not Scanner.IsOpen() then return ns.Print("open the Auction House first.") end
  if Scanner.busy then return ns.Print("a scan is already running.") end
  local wait = Scanner.FullScanCooldown()
  if wait > 0 then
    return ns.Print("the game allows one full scan every 15 minutes: %d min left. Use \"Scan prices\" for one profession.", math.ceil(wait / 60))
  end
  Scanner.busy = "full"
  ns.DB().lastFullScan = time()
  full:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
  Scanner.progress = 0
  SetStatus("Full scan: waiting for the Auction House...")
  AH().ReplicateItems()
end

---------------------------------------------------------------------------
-- Item scan (a list of items, one search each: every listing with its quantity)
---------------------------------------------------------------------------
local item = CreateFrame("Frame")
local queue, current, timeout = {}, nil, nil
local SORTS = { { sortOrder = Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0, reverseSort = false } }

local NextItem

local function ReadCurrent()
  if not current then return end
  local id = current.id
  local listings = {}
  local n = AH().GetNumCommoditySearchResults and AH().GetNumCommoditySearchResults(id) or 0
  for i = 1, n do
    local r = AH().GetCommoditySearchResultInfo(id, i)
    local unit = r and (r.unitPrice or r.price)
    if unit and r.quantity and r.quantity > 0 then listings[unit] = (listings[unit] or 0) + r.quantity end
  end
  if n == 0 and AH().GetNumItemSearchResults then
    local key = current.key
    for i = 1, AH().GetNumItemSearchResults(key) do
      local r = AH().GetItemSearchResultInfo(key, i)
      if r and r.buyoutAmount and r.quantity and r.quantity > 0 then
        local unit = math.floor(r.buyoutAmount / r.quantity)
        listings[unit] = (listings[unit] or 0) + r.quantity
      end
    end
  end
  Store(id, listings)
  current = nil
  NextItem()
end

item:SetScript("OnEvent", function(_, event, arg)
  if not current then return end
  if event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
    if arg ~= current.id then return end
    if AH().HasFullCommoditySearchResults and not AH().HasFullCommoditySearchResults(current.id) then
      AH().RequestMoreCommoditySearchResults(current.id)
      return
    end
    ReadCurrent()
  elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
    if AH().HasFullItemSearchResults and not AH().HasFullItemSearchResults(current.key) then
      AH().RequestMoreItemSearchResults(current.key)
      return
    end
    ReadCurrent()
  elseif event == "AUCTION_HOUSE_CLOSED" then
    queue, current = {}, nil
    Scanner.busy = nil
    item:UnregisterAllEvents()
    SetStatus("Scan stopped: the Auction House was closed.")
  end
end)

local function Send()
  if not current then return end
  if AH().IsThrottledMessageSystemReady and not AH().IsThrottledMessageSystemReady() then
    C_Timer.After(0.2, Send)
    return
  end
  AH().SendSearchQuery(current.key, SORTS, false)
  local token = current
  -- no answer (item never listed, server busy): move on after 4 seconds
  C_Timer.After(4, function() if current == token then ReadCurrent() end end)
end

NextItem = function()
  if not Scanner.IsOpen() then
    queue, current, Scanner.busy = {}, nil, nil
    item:UnregisterAllEvents()
    return
  end
  local id = table.remove(queue, 1)
  if not id then
    Scanner.busy = nil
    item:UnregisterAllEvents()
    SetStatus("Prices updated for %d items.", Scanner.total or 0)
    if ns.OnPricesChanged then ns.OnPricesChanged() end
    return
  end
  local total = Scanner.total or 0
  Scanner.progress = total > 0 and (total - #queue - 1) / total or 0
  SetStatus("Scanning prices... %d / %d", total - #queue, total)
  current = { id = id, key = AH().MakeItemKey(id) }
  Send()
end

function Scanner.ScanItems(itemIDs)
  if not Scanner.IsOpen() then return ns.Print("open the Auction House first.") end
  if Scanner.busy then return ns.Print("a scan is already running.") end
  queue = {}
  for _, id in ipairs(itemIDs) do
    if not ns.VENDOR[id] then queue[#queue + 1] = id end
  end
  if #queue == 0 then return end
  Scanner.busy, Scanner.total = "items", #queue
  item:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
  item:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
  item:RegisterEvent("AUCTION_HOUSE_CLOSED")
  NextItem()
end

function Scanner.Stop()
  queue, current, Scanner.busy = {}, nil, nil
  item:UnregisterAllEvents()
  full:UnregisterAllEvents()
  SetStatus("Scan stopped.")
end

---------------------------------------------------------------------------
-- Show items in the Auction House's own Buy tab (search by name)
---------------------------------------------------------------------------
function Scanner.SearchInAH(itemID)
  if not Scanner.IsOpen() then return end
  local name = ns.ItemName(itemID)
  if not name then return end
  -- Auctionator installed: its shopping tab can show several items at once
  if Auctionator and Auctionator.API and Auctionator.API.v1 and Auctionator.API.v1.MultiSearchExact and ns.useAuctionator then
    Auctionator.API.v1.MultiSearchExact("SkillRat", { name })
    return
  end
  if AuctionHouseFrame.SetDisplayMode and AuctionHouseFrameDisplayMode then
    AuctionHouseFrame:SetDisplayMode(AuctionHouseFrameDisplayMode.Buy)
  end
  local bar = AuctionHouseFrame.SearchBar
  if bar and bar.SearchBox then
    bar.SearchBox:SetText(name)
    if bar.StartSearch then bar:StartSearch() end
  end
end

-- Several items: Auctionator (if installed) shows them all; otherwise the first one in Blizzard's Buy tab.
function Scanner.SearchManyInAH(itemIDs)
  if not Scanner.IsOpen() then return end
  local names = {}
  for _, id in ipairs(itemIDs) do
    local n = ns.ItemName(id)
    if n and not ns.VENDOR[id] then names[#names + 1] = n end
  end
  if #names == 0 then return end
  if Auctionator and Auctionator.API and Auctionator.API.v1 and Auctionator.API.v1.MultiSearchExact then
    Auctionator.API.v1.MultiSearchExact("SkillRat", names)
  else
    Scanner.SearchInAH(itemIDs[1])
  end
end
