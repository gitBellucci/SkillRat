-- SkillRat: interface. One planner panel, shown in the Auction House (its own tab), next to the profession window, or
-- on its own (/skillrat); plus the pinned list and the reagent exclusion list.
local _, ns = ...

local W, H = 420, 650
local ROW_H = 20
local GOLD = { 0.84, 0.63, 0.13 }

local state = { mode = "trainer" }
ns.state = state

local BACKDROP = {
  bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1,
}

local function Box(parent, w, h)
  local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  if w then f:SetSize(w, h) end
  f:SetBackdrop(BACKDROP)
  f:SetBackdropColor(0.06, 0.05, 0.08, 0.95)
  f:SetBackdropBorderColor(0.35, 0.3, 0.2, 1)
  return f
end

local function Label(parent, template, text)
  local fs = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlightSmall")
  if text then fs:SetText(text) end
  return fs
end

-- sunken box for lists, like the ones inside the game's windows
local function Inset(parent)
  local ok, f = pcall(CreateFrame, "Frame", nil, parent, "InsetFrameTemplate")
  if ok and f then return f end
  return Box(parent)
end

local ICON = "Interface\\AddOns\\SkillRat\\Media\\icon"

-- a window in the game's own style (the same frame as the profession window): round portrait, title bar, close button.
-- Returns the frame and the extra height taken by the title bar (0 with the fallback box).
local function Window(parent, w, h, title)
  local ok, f = pcall(CreateFrame, "Frame", nil, parent, "PortraitFrameTemplate")
  if not ok or not f then
    f = Box(parent, w, h)
    f.CloseButton = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    f.CloseButton:SetPoint("TOPRIGHT", 2, 2)
    f.srTitle = Label(f, "GameFontNormal")
    f.srTitle:SetPoint("TOP", 0, -8)
    function f:SetSRTitle(t) self.srTitle:SetText(t) end
    f:SetSRTitle(title)
    return f, false
  end
  f:SetSize(w, h)
  if f.SetPortraitToAsset then
    f:SetPortraitToAsset(ICON)
  else
    local p = f.portrait or (f.PortraitContainer and f.PortraitContainer.portrait)
    if p then SetPortraitToTexture(p, ICON) end
  end
  function f:SetSRTitle(t)
    if self.SetTitle then self:SetTitle(t) elseif self.TitleText then self.TitleText:SetText(t) end
  end
  f:SetSRTitle(title)
  f:EnableMouse(true)
  return f, true
end

local function Button(parent, text, w, h, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w, h or 22)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

local function EditNumber(parent, w)
  local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  e:SetSize(w, 20)
  e:SetAutoFocus(false)
  e:SetNumeric(true)
  e:SetMaxLetters(3)
  e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  return e
end

local function Tip(owner, title, lines)
  owner:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(type(title) == "function" and title() or title)
    for _, l in ipairs(type(lines) == "function" and lines() or lines or {}) do GameTooltip:AddLine(l, 1, 1, 1, true) end
    GameTooltip:Show()
  end)
  owner:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- a scrolling list of rows; fill(row, data, index) draws one row
local function ScrollList(parent, rowH, fill, onClick)
  local sf = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
  local content = CreateFrame("Frame", nil, sf)
  content:SetSize(10, 10)
  sf:SetScrollChild(content)
  sf:SetScript("OnSizeChanged", function(_, w) content:SetWidth(w) end)
  sf.rows, sf.data = {}, {}
  function sf:SetData(data)
    self.data = data
    content:SetWidth(self:GetWidth())
    for i, d in ipairs(data) do
      local row = self.rows[i]
      if not row then
        row = CreateFrame("Button", nil, content)
        row:SetHeight(rowH)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * rowH)
        row:SetPoint("RIGHT", content, "RIGHT")
        row.hl = row:CreateTexture(nil, "HIGHLIGHT")
        row.hl:SetAllPoints()
        row.hl:SetColorTexture(1, 0.85, 0.3, 0.12)
        row.sel = row:CreateTexture(nil, "BACKGROUND")
        row.sel:SetAllPoints()
        row.sel:SetColorTexture(1, 0.85, 0.3, 0.2)
        row.sel:Hide()
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(rowH - 4, rowH - 4)
        row.icon:SetPoint("LEFT", 2, 0)
        row.left = Label(row, "GameFontHighlight")
        row.left:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
        row.left:SetJustifyH("LEFT")
        row.left:SetWordWrap(false)
        row.right = Label(row, "GameFontHighlight")
        row.right:SetPoint("RIGHT", -4, 0)
        row.right:SetJustifyH("RIGHT")
        row.left:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
        row:SetScript("OnClick", function(r, mouse) if onClick then onClick(r.data, r.index, mouse) end end)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        self.rows[i] = row
      end
      row.data, row.index = d, i
      fill(row, d, i)
      row:Show()
    end
    for i = #data + 1, #self.rows do self.rows[i]:Hide() end
    content:SetHeight(math.max(10, #data * rowH))
  end
  return sf
end

---------------------------------------------------------------------------
-- Planner panel
---------------------------------------------------------------------------
local panels = {}

local function SelectedProf()
  if state.prof and ns.PROF_BY_ID[state.prof] then return state.prof end
  local mine = ns.PlayerProfessions()
  for _, p in ipairs(ns.PROFESSIONS) do if mine[p.id] then return p.id end end
  return ns.PROFESSIONS[1].id
end

local MODES = { trainer = "Trainer + known recipes", known = "Known recipes only", all = "All recipes (incl. drops)" }
local NEXT_MODE = { trainer = "known", known = "all", all = "trainer" }

local function RefreshAll()
  for _, p in ipairs(panels) do if p:IsShown() then p:Refresh() end end
  if ns.pinned and ns.pinned:IsShown() then ns.pinned:Refresh() end
end
ns.RefreshAll = RefreshAll

local function DefaultLevels(profID)
  local mine = ns.PlayerProfessions()[profID]
  local from = mine and math.max(1, mine.level) or 1
  local to = mine and mine.max and mine.max > from and mine.max or math.min(300, from + 75)
  return from, to
end

local function CreatePlanner(parent, key)
  local f, T
  if key == "ah" then
    -- inside the Auction House window: no frame of its own, the Auction House draws it
    f, T = CreateFrame("Frame", nil, parent), 0
    f:SetSize(W, H)
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ICON)
    icon:SetSize(28, 28)
    icon:SetPoint("TOPLEFT", 8, -8)
    local title = Label(f, "GameFontNormalLarge", "SkillRat")
    title:SetPoint("LEFT", icon, "RIGHT", 8, 4)
    local sub = Label(f, "GameFontDisableSmall", "the cheapest way to level a profession")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -1)
  else
    local framed
    f, framed = Window(parent, W, H, "SkillRat")
    T = framed and 24 or 0
    if framed then f:SetHeight(H + T) end
    local sub = Label(f, "GameFontDisableSmall", "the cheapest way to level a profession")
    sub:SetPoint("TOPLEFT", framed and 64 or 10, framed and -32 or -28)
  end
  f:SetFrameStrata("HIGH")
  f:SetClampedToScreen(true)
  f.key = key

  -- profession buttons (learned first)
  f.profButtons = {}
  local function LayoutProfs()
    local mine = ns.PlayerProfessions()
    local list = {}
    for _, p in ipairs(ns.PROFESSIONS) do list[#list + 1] = p end
    table.sort(list, function(a, b)
      local ma, mb = mine[a.id] and 1 or 0, mine[b.id] and 1 or 0
      if ma ~= mb then return ma > mb end
      return ns.ProfName(a) < ns.ProfName(b)
    end)
    local fw = f:GetWidth()
    if not fw or fw < 100 then fw = W end
    local stepX = math.max(24, math.min(40, math.floor((fw - 16) / #list)))
    for i, p in ipairs(list) do
      local b = f.profButtons[i]
      if not b then
        b = CreateFrame("Button", nil, f, "BackdropTemplate")
        b:SetBackdrop(BACKDROP)
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetPoint("TOPLEFT", 2, -2)
        b.tex:SetPoint("BOTTOMRIGHT", -2, 2)
        b.lv = Label(b, "NumberFontNormalSmall")
        b.lv:SetPoint("BOTTOMRIGHT", -1, 1)
        f.profButtons[i] = b
      end
      b:SetSize(stepX - 6, stepX - 6)
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", 8 + (i - 1) * stepX, -(46 + T))
      b.prof = p.id
      b.tex:SetTexture(ns.ProfIcon(p))
      local m = mine[p.id]
      b.lv:SetText(m and m.level or "")
      b.tex:SetDesaturated(not m)
      local selected = p.id == SelectedProf()
      b:SetBackdropColor(0, 0, 0, 0.6)
      if selected then
        b:SetBackdropBorderColor(1, 0.82, 0.1, 1)
      elseif m then
        b:SetBackdropBorderColor(0.55, 0.45, 0.2, 1)
      else
        b:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
      end
      b:SetScript("OnClick", function()
        state.prof = p.id
        state.from, state.to = DefaultLevels(p.id)
        state.plan, state.step = nil, nil
        RefreshAll()
      end)
      Tip(b, ns.ProfName(p), function()
        local mm = ns.PlayerProfessions()[p.id]
        return { mm and ("Your skill: %d / %d"):format(mm.level, mm.max) or "|cff999999Not learned on this character|r" }
      end)
    end
  end

  -- levels and recipe mode
  local fromL = Label(f, "GameFontNormalSmall", "From")
  fromL:SetPoint("TOPLEFT", 10, -(92 + T))
  f.from = EditNumber(f, 40)
  f.from:SetPoint("LEFT", fromL, "RIGHT", 10, 0)
  local toL = Label(f, "GameFontNormalSmall", "to")
  toL:SetPoint("LEFT", f.from, "RIGHT", 8, 0)
  f.to = EditNumber(f, 40)
  f.to:SetPoint("LEFT", toL, "RIGHT", 10, 0)
  local function ReadLevels()
    state.from = tonumber(f.from:GetText()) or state.from
    state.to = tonumber(f.to:GetText()) or state.to
  end
  f.from:SetScript("OnEditFocusLost", ReadLevels)
  f.to:SetScript("OnEditFocusLost", ReadLevels)
  f.mode = Button(f, "", 180, 20, function()
    state.mode = NEXT_MODE[state.mode] or "trainer"
    f:Refresh()
  end)
  f.mode:SetPoint("LEFT", f.to, "RIGHT", 10, 0)
  f.mode:SetPoint("RIGHT", f, "RIGHT", -8, 0)
  Tip(f.mode, "Recipes used", {
    "Trainer + known: what you know plus everything a trainer teaches.",
    "Known only: needs the profession window opened once.",
    "All: also recipes that drop or are sold (you would need to buy them)." })

  -- actions
  f.exclude = Button(f, "Exclude reagents", 130, 22, function() ns.ShowExclusions(SelectedProf()) end)
  f.exclude:SetPoint("TOPLEFT", 8, -(118 + T))
  Tip(f.exclude, "Exclude reagents", { "Recipes that use an excluded reagent are left out of the list." })
  f.scanProf = Button(f, "Scan prices", 130, 22, function()
    ns.Scanner.ScanItems(ns.ProfReagents(SelectedProf()))
  end)
  f.scanProf:SetPoint("LEFT", f.exclude, "RIGHT", 4, 0)
  Tip(f.scanProf, "Scan prices", { "Prices and quantities of every reagent this profession uses (Auction House open)." })
  f.scanAll = Button(f, "Scan whole AH", 130, 22, function() ns.Scanner.FullScan() end)
  f.scanAll:SetPoint("LEFT", f.scanProf, "RIGHT", 4, 0)
  Tip(f.scanAll, "Scan the whole Auction House", { "Every price at once. The game allows it once every 15 minutes." })

  f.status = Label(f, "GameFontDisableSmall", "")
  f.status:SetPoint("TOPLEFT", 10, -(146 + T))
  f.status:SetPoint("RIGHT", -10, 0)
  f.status:SetJustifyH("LEFT")

  -- scan progress: a bar in place of the status line while a scan runs, with a Stop button
  local bar = CreateFrame("StatusBar", nil, f)
  bar:SetPoint("TOPLEFT", 12, -(144 + T))
  bar:SetPoint("RIGHT", f, "RIGHT", -72, 0)
  bar:SetHeight(14)
  bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  bar:SetStatusBarColor(0.85, 0.65, 0.1)
  bar:SetMinMaxValues(0, 1)
  local bbg = bar:CreateTexture(nil, "BACKGROUND")
  bbg:SetAllPoints()
  bbg:SetColorTexture(0, 0, 0, 0.6)
  local border = CreateFrame("Frame", nil, bar, "BackdropTemplate")
  border:SetPoint("TOPLEFT", -3, 3)
  border:SetPoint("BOTTOMRIGHT", 3, -3)
  border:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10 })
  border:SetBackdropBorderColor(0.6, 0.5, 0.25, 1)
  bar.text = Label(bar, "GameFontHighlightSmall")
  bar.text:SetPoint("CENTER", 0, 0)
  bar:Hide()
  f.bar = bar
  f.stop = Button(f, "Stop", 58, 20, function() ns.Scanner.Stop() end)
  f.stop:SetPoint("LEFT", bar, "RIGHT", 8, 0)
  f.stop:Hide()

  f.create = Button(f, "Create the cheapest list", W - 16, 26, function()
    ReadLevels()
    local prof = SelectedProf()
    local from, to = state.from or 1, state.to or 75
    if to <= from then return ns.Print("the target level must be above the starting level.") end
    state.plan = ns.Planner.Build({ prof = prof, from = from, to = to, mode = state.mode,
                                    excluded = ns.DB().excluded[prof] or {} })
    state.step = nil
    ns.DB().lastPlan = nil
    RefreshAll()
  end)
  f.create:SetPoint("TOPLEFT", 8, -(164 + T))
  f.create:SetPoint("RIGHT", f, "RIGHT", -8 - 2 * 64, 0)
  f.lists = Button(f, "Lists", 60, 26, function() ns.ShowSavedLists() end)
  f.lists:SetPoint("TOPRIGHT", -8, -(164 + T))
  Tip(f.lists, "Saved lists", { "Open a list you saved, on any character of this account.", "It is priced again with today's prices." })
  f.save = Button(f, "Save", 60, 26, function()
    if not state.plan then return end
    local o = state.plan.opts
    local default = state.plan.savedName or ("%s %d-%d"):format(ns.ProfName(ns.PROF_BY_ID[o.prof]), o.from, o.to)
    StaticPopup_Show("SKILLRAT_SAVE_LIST", nil, nil, default)
  end)
  f.save:SetPoint("RIGHT", f.lists, "LEFT", -4, 0)
  Tip(f.save, "Save this list", { "Keep this list to use it again later or on another character." })

  -- the list of crafts
  local stepsBox = Inset(f)
  stepsBox:SetPoint("TOPLEFT", 8, -(196 + T))
  stepsBox:SetPoint("TOPRIGHT", -8, -(196 + T))
  stepsBox:SetHeight(210)
  f.steps = ScrollList(stepsBox, ROW_H, function(row, step)
    local r = step.recipe
    local name = r[2] > 0 and ns.ItemName(r[2]) or ns.SpellName(r[1]) or "?"
    row.icon:SetTexture(r[2] > 0 and ns.ItemIcon(r[2]) or ns.ProfIcon(ns.PROF_BY_ID[SelectedProf()]))
    local tag = r[7] ~= 0 and " |cffff9933(recipe)|r" or ""
    row.left:SetText(("|cffaaaaaa%d-%d|r  |cffffd100%dx|r %s%s"):format(step.from, step.to, step.crafts, name, tag))
    row.right:SetText(ns.Money(step.cost))
    row.sel:SetShown(state.step == step)
  end, function(step)
    state.step = (state.step == step) and nil or step
    RefreshAll()
    if state.step and ns.Scanner.IsOpen() then
      local ids = {}
      for _, x in ipairs(ns.Planner.StepReagents(step)) do ids[#ids + 1] = x.id end
      ns.Scanner.SearchManyInAH(ids)
    end
  end)
  f.steps:SetPoint("TOPLEFT", 4, -4)
  f.steps:SetPoint("BOTTOMRIGHT", -26, 4)

  -- reagents of the selected craft (or of the whole list)
  f.reagTitle = Label(f, "GameFontNormalSmall", "")
  f.reagTitle:SetPoint("TOPLEFT", stepsBox, "BOTTOMLEFT", 2, -6)
  local reagBox = Inset(f)
  reagBox:SetPoint("TOPLEFT", stepsBox, "BOTTOMLEFT", 0, -22)
  reagBox:SetPoint("TOPRIGHT", stepsBox, "BOTTOMRIGHT", 0, -22)
  reagBox:SetHeight(150)
  -- columns, from the right edge of a row: cost | in bags | AH / vendor | (name takes the rest) ; quantity on the left
  local COL_COST, COL_BAG, COL_SRC, COL_QTY = 78, 54, 64, 30
  local function ReagColumns(row)
    if row.qty then return end
    row.left:SetText("")
    row.right:ClearAllPoints()
    row.right:SetPoint("RIGHT", -4, 0)
    row.right:SetWidth(COL_COST)
    row.qty = Label(row, "GameFontNormal")
    row.qty:SetPoint("LEFT", row.icon, "RIGHT", 2, 0)
    row.qty:SetWidth(COL_QTY)
    row.qty:SetJustifyH("RIGHT")
    row.bag = Label(row, "GameFontHighlight")
    row.bag:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
    row.bag:SetWidth(COL_BAG)
    row.bag:SetJustifyH("RIGHT")
    row.src = Label(row, "GameFontHighlightSmall")
    row.src:SetPoint("RIGHT", row.bag, "LEFT", -6, 0)
    row.src:SetWidth(COL_SRC)
    row.src:SetJustifyH("RIGHT")
    row.name = Label(row, "GameFontHighlight")
    row.name:SetPoint("LEFT", row.qty, "RIGHT", 6, 0)
    row.name:SetPoint("RIGHT", row.src, "LEFT", -6, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
  end
  f.reags = ScrollList(reagBox, ROW_H, function(row, x)
    ReagColumns(row)
    row.icon:SetTexture(ns.ItemIcon(x.id))
    local p = ns.DB().prices[x.id]
    if ns.VendorPrice(x.id) then
      row.src:SetText("|cff88ccffvendor|r")
    elseif p then
      row.src:SetText(((x.short and "|cffff5555" or "|cff999999") .. "%d AH|r"):format(p.qty or 0))
    else
      row.src:SetText("|cffff5555no price|r")
    end
    local have = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(x.id)) or (GetItemCount and GetItemCount(x.id)) or 0
    if have >= x.need then
      row.bag:SetText(("|cff55ff55%d/%d|r"):format(math.min(have, x.need), x.need))
    elseif have > 0 then
      row.bag:SetText(("|cffffd100%d/%d|r"):format(have, x.need))
    else
      row.bag:SetText("|cff666666-|r")
    end
    row.qty:SetText(x.need)
    row.name:SetText(ns.ItemName(x.id) or ("item " .. x.id))
    row.right:SetText(x.cost and ns.Money(x.cost) or "")
  end, function(x) ns.Scanner.SearchInAH(x.id) end)
  f.reags:SetPoint("TOPLEFT", 4, -4)
  f.reags:SetPoint("BOTTOMRIGHT", -26, 4)
  -- column headers, on the title line, right-aligned like the columns
  local function ColHeader(text, rightOffset, width)
    local h = Label(f, "GameFontDisableSmall", text)
    h:SetPoint("BOTTOMRIGHT", reagBox, "TOPRIGHT", -rightOffset, 4)
    h:SetWidth(width)
    h:SetJustifyH("RIGHT")
    return h
  end
  local base = 26 + 4                                   -- scroll bar + row margin
  ColHeader("Cost", base, COL_COST)
  ColHeader("Bags", base + COL_COST + 6, COL_BAG)
  local srcHeader = ColHeader("Source", base + COL_COST + 6 + COL_BAG + 6, COL_SRC)
  -- the title stops before the headers (long craft names are cut with "...")
  f.reagTitle:SetPoint("RIGHT", srcHeader, "LEFT", -6, 0)
  f.reagTitle:SetJustifyH("LEFT")
  f.reagTitle:SetWordWrap(false)

  -- Auction House: the panel takes the whole window, crafts on the left and reagents on the right
  if key == "ah" then
    stepsBox:ClearAllPoints()
    stepsBox:SetPoint("TOPLEFT", 8, -196)
    stepsBox:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -4, 70)
    f.reagTitle:ClearAllPoints()
    f.reagTitle:SetPoint("BOTTOMLEFT", reagBox, "TOPLEFT", 2, 4)
    f.reagTitle:SetPoint("RIGHT", srcHeader, "LEFT", -6, 0)
    reagBox:ClearAllPoints()
    reagBox:SetPoint("TOPLEFT", f, "TOP", 4, -214)
    reagBox:SetPoint("BOTTOMRIGHT", -8, 70)
  end

  -- footer, like a quote: Auction House price, minus what the crafts sell for at a vendor, = total
  local AMOUNT_X = 250    -- right edge of the amounts column
  local function InvoiceLine(y, template)
    local l = Label(f, template or "GameFontNormal", "")
    l:SetPoint("BOTTOMLEFT", 12, y)
    local a = Label(f, template or "GameFontHighlight", "")
    a:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", AMOUNT_X, y)
    a:SetJustifyH("RIGHT")
    return l, a
  end
  f.ahLabel, f.ahAmount = InvoiceLine(50)
  f.vendLabel, f.vendAmount = InvoiceLine(31)
  f.totLabel, f.totAmount = InvoiceLine(10, "GameFontNormalLarge")
  f.invoiceRule = f:CreateTexture(nil, "ARTWORK")
  f.invoiceRule:SetColorTexture(0.85, 0.65, 0.2, 0.8)
  f.invoiceRule:SetHeight(1)
  f.invoiceRule:SetPoint("BOTTOMLEFT", 12, 27)
  f.invoiceRule:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", AMOUNT_X, 27)
  f.total = f.totAmount    -- (kept for older code paths)
  local vtip = CreateFrame("Frame", nil, f)
  vtip:SetPoint("BOTTOMLEFT", 8, 6)
  vtip:SetSize(AMOUNT_X, 62)
  vtip:EnableMouse(true)
  Tip(vtip, "What the leveling costs", {
    "AH price: buying every reagent at the current Auction House prices.",
    "Sold to vendor: what you get back by selling every crafted item to a vendor.",
    "Total: green = you make money, red = what the leveling really costs you." })
  f.pin = Button(f, "Pin", 60, 22, function()
    if state.plan then ns.ShowPinned(true) end
  end)
  f.pin:SetPoint("BOTTOMRIGHT", -8, 8)
  Tip(f.pin, "Pin the list", { "Keeps the list on screen while you shop and craft." })
  f.searchAll = Button(f, "Search all", 90, 22, function()
    if not state.plan then return end
    local ids = {}
    for _, x in ipairs(state.plan.reagents) do ids[#ids + 1] = x.id end
    ns.Scanner.SearchManyInAH(ids)
  end)
  f.searchAll:SetPoint("RIGHT", f.pin, "LEFT", -4, 0)
  Tip(f.searchAll, "Search every reagent", { "Shows the list's reagents in the Auction House (all at once with Auctionator)." })

  function f:Refresh()
    LayoutProfs()
    local prof = SelectedProf()
    if not state.from or not state.to or state.profForLevels ~= prof then
      state.from, state.to = DefaultLevels(prof)
      state.profForLevels = prof
    end
    if not self.from:HasFocus() then self.from:SetText(state.from) end
    if not self.to:HasFocus() then self.to:SetText(state.to) end
    self.mode:SetText(MODES[state.mode] or MODES.trainer)
    local ahOpen = ns.Scanner.IsOpen()
    self.scanProf:SetEnabled(ahOpen and not ns.Scanner.busy)
    self.scanAll:SetEnabled(ahOpen and not ns.Scanner.busy)
    self.searchAll:SetEnabled(ahOpen and state.plan ~= nil)
    self.save:SetEnabled(state.plan ~= nil)
    local n = 0
    for _ in pairs(ns.DB().excluded[prof] or {}) do n = n + 1 end
    self.exclude:SetText(n > 0 and ("Excluded: %d"):format(n) or "Exclude reagents")
    local status = ns.Scanner.status ~= "" and ns.Scanner.status or (ahOpen and "" or "Open the Auction House to scan prices.")
    self.status:SetText(status)
    local busy = ns.Scanner.busy ~= nil
    self.bar:SetShown(busy)
    self.stop:SetShown(busy)
    self.status:SetShown(not busy)
    if busy then
      self.bar:SetValue(math.max(0, math.min(1, ns.Scanner.progress or 0)))
      self.bar.text:SetText(ns.Scanner.status)
    end

    local plan = state.plan
    if plan and plan.opts.prof == prof then
      self.steps:SetData(plan.steps)
      local reag
      if state.step then
        reag = ns.Planner.StepReagents(state.step)
        local byId = {}
        for _, x in ipairs(plan.reagents) do byId[x.id] = x end
        for _, x in ipairs(reag) do
          local all = byId[x.id]
          x.cost = all and all.cost and all.need > 0 and all.cost / all.need * x.need or nil
          x.short = all and all.short
        end
        local r = state.step.recipe
        self.reagTitle:SetText(("Reagents for %dx %s"):format(state.step.crafts,
          r[2] > 0 and ns.ItemName(r[2]) or ns.SpellName(r[1]) or "?"))
      else
        reag = plan.reagents
        self.reagTitle:SetText("All reagents")
      end
      self.reags:SetData(reag)
      local missing = 0
      for _ in pairs(plan.missing) do missing = missing + 1 end
      local range = ("|cffaaaaaa(%d-%d)|r"):format(plan.opts.from, plan.stoppedAt or plan.opts.to)
      if plan.stoppedAt then range = range .. " |cffff5555stopped|r" end
      self.ahLabel:SetText("AH price " .. range)
      self.ahAmount:SetText(ns.Money(plan.total))
      local vend, unknown = ns.PlanVendorValue(plan)
      local more = unknown > 0 and " |cff999999+?|r" or ""
      self.vendLabel:SetText("Sold to vendor")
      self.vendAmount:SetText("+ " .. ns.Money(vend) .. more)
      local net = vend - plan.total
      self.totLabel:SetText("Total")
      if net >= 0 then
        self.totAmount:SetText("|cff55ff55+ " .. ns.Money(net) .. "|r")
      else
        self.totAmount:SetText("|cffff5555- " .. ns.Money(-net) .. "|r")
      end
      self.invoiceRule:Show()
      if plan.stoppedAt or missing > 0 then
        self.status:SetText(("|cffff9933%d reagent(s) have no price yet: scan them to use more recipes.|r"):format(missing))
      end
    else
      self.steps:SetData({})
      self.reags:SetData({})
      self.reagTitle:SetText("")
      for _, fs in ipairs({ self.ahLabel, self.ahAmount, self.vendLabel, self.vendAmount, self.totLabel, self.totAmount }) do fs:SetText("") end
      self.invoiceRule:Hide()
    end
  end

  local function Layout()
    local w = f:GetWidth()
    if not w or w < 100 then return end
    local bw = math.floor((w - 16 - 8) / 3)
    f.exclude:SetWidth(bw)
    f.scanProf:SetWidth(bw)
    f.scanAll:SetWidth(bw)
    if f:IsShown() then f:Refresh() end
  end
  f:SetScript("OnSizeChanged", Layout)
  f:SetScript("OnShow", function(self) Layout() self:Refresh() end)
  panels[#panels + 1] = f
  return f
end

---------------------------------------------------------------------------
-- Reagent exclusion list
---------------------------------------------------------------------------
function ns.ShowExclusions(profID)
  local f = ns.excludeFrame
  if not f then
    local framed
    f, framed = Window(UIParent, 320, 440, "Exclude reagents")
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    local hint = Label(f, "GameFontDisableSmall", "Ticked reagents are never used: recipes needing them are skipped.")
    hint:SetPoint("TOPLEFT", framed and 64 or 10, framed and -30 or -30)
    hint:SetPoint("RIGHT", -10, 0)
    hint:SetJustifyH("LEFT")
    f.list = ScrollList(f, ROW_H, function(row, id)
      local ex = ns.DB().excluded[f.prof] or {}
      row.icon:SetTexture(ns.ItemIcon(id))
      row.left:SetText((ex[id] and "|cffff5555[x]|r " or "|cff666666[  ]|r ") .. (ns.ItemName(id) or ("item " .. id)))
      row.right:SetText(ns.VendorPrice(id) and "|cff88ccffvendor|r" or "")
    end, function(id)
      local db = ns.DB()
      db.excluded[f.prof] = db.excluded[f.prof] or {}
      db.excluded[f.prof][id] = (not db.excluded[f.prof][id]) or nil
      f.list:SetData(f.items)
      RefreshAll()
    end)
    local box = Inset(f)
    box:SetPoint("TOPLEFT", 8, framed and -66 or -56)
    box:SetPoint("BOTTOMRIGHT", -8, 10)
    f.list:SetParent(box)
    f.list:SetPoint("TOPLEFT", 4, -4)
    f.list:SetPoint("BOTTOMRIGHT", -26, 4)
    ns.excludeFrame = f
  end
  f.prof = profID
  f:SetSRTitle("Exclude: " .. ns.ProfName(ns.PROF_BY_ID[profID]))
  local items = ns.ProfReagents(profID)
  table.sort(items, function(a, b) return (ns.ItemName(a) or "") < (ns.ItemName(b) or "") end)
  f.items = items
  f.list:SetData(items)
  f:Show()
end

---------------------------------------------------------------------------
-- Saved lists (account-wide)
---------------------------------------------------------------------------
StaticPopupDialogs["SKILLRAT_SAVE_LIST"] = {
  text = "Name of this list:",
  button1 = SAVE or "Save", button2 = CANCEL or "Cancel",
  hasEditBox = true, maxLetters = 60, timeout = 0, whileDead = true, hideOnEscape = true,
  OnShow = function(self, default)
    local eb = self.editBox or self.EditBox
    eb:SetText(default or ""); eb:HighlightText(); eb:SetFocus()
  end,
  OnAccept = function(self)
    local eb = self.editBox or self.EditBox
    local name = eb:GetText()
    if not state.plan or name == "" then return end
    local db = ns.DB()
    db.lists = db.lists or {}
    for i = #db.lists, 1, -1 do if db.lists[i].name == name then table.remove(db.lists, i) end end
    table.insert(db.lists, 1, ns.Planner.ToSaved(state.plan, name))
    state.plan.savedName = name
    ns.Print("list saved: " .. name)
    if ns.listsFrame and ns.listsFrame:IsShown() then ns.listsFrame:Refresh() end
  end,
  EditBoxOnEnterPressed = function(self)
    local p = self:GetParent()
    StaticPopupDialogs["SKILLRAT_SAVE_LIST"].OnAccept(p)
    p:Hide()
  end,
}

function ns.ShowSavedLists()
  local f = ns.listsFrame
  if not f then
    local framed
    f, framed = Window(UIParent, 340, 380, "Saved lists")
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    local hint = Label(f, "GameFontDisableSmall", "Click: open the list. Right-click: delete it.")
    hint:SetPoint("TOPLEFT", framed and 64 or 10, -34)
    local box = Inset(f)
    box:SetPoint("TOPLEFT", 8, framed and -62 or -50)
    box:SetPoint("BOTTOMRIGHT", -8, 10)
    f.list = ScrollList(box, ROW_H + 2, function(row, l)
      local p = ns.PROF_BY_ID[l.opts.prof]
      row.icon:SetTexture(p and ns.ProfIcon(p) or 134400)
      row.left:SetText(l.name)
      row.right:SetText(("|cffaaaaaa%d crafts  %s|r"):format(#(l.steps or {}), date("%d/%m", l.t or 0)))
    end, function(l, index, mouse)
      local db = ns.DB()
      if mouse == "RightButton" then
        table.remove(db.lists, index)
        ns.Print("list deleted: " .. l.name)
        f:Refresh()
        return
      end
      state.prof = l.opts.prof
      state.from, state.to, state.profForLevels = l.opts.from, l.opts.to, l.opts.prof
      state.mode = l.opts.mode or state.mode
      state.plan = ns.Planner.Rebuild(l)
      state.step = nil
      RefreshAll()
      f:Hide()
    end)
    f.list:SetPoint("TOPLEFT", 4, -4)
    f.list:SetPoint("BOTTOMRIGHT", -26, 4)
    function f:Refresh() self.list:SetData(ns.DB().lists or {}) end
    ns.listsFrame = f
  end
  f:Refresh()
  f:Show()
end

---------------------------------------------------------------------------
-- Pinned list (stays on screen)
---------------------------------------------------------------------------
function ns.ShowPinned(show)
  local f = ns.pinned
  if not f then
    local framed
    f, framed = Window(UIParent, 340, 290, "SkillRat")
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
      self:StopMovingOrSizing()
      local p, _, rp, x, y = self:GetPoint()
      ns.CharDB().pinPos = { p, rp, x, y }
    end)
    local pos = ns.CharDB().pinPos
    if pos then f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else f:SetPoint("RIGHT", -80, 0) end
    f.CloseButton:SetScript("OnClick", function() f:Hide(); ns.CharDB().pinned = nil end)
    f.list = ScrollList(f, 18, function(row, step)
      local r = step.recipe
      row.icon:SetTexture(r[2] > 0 and ns.ItemIcon(r[2]) or 134400)
      row.left:SetText(("|cffaaaaaa%d-%d|r |cffffd100%dx|r %s"):format(step.from, step.to, step.crafts,
        r[2] > 0 and ns.ItemName(r[2]) or ns.SpellName(r[1]) or "?"))
      row.right:SetText(ns.Money(step.cost))
    end, function(step)
      if ns.Scanner.IsOpen() then
        local ids = {}
        for _, x in ipairs(ns.Planner.StepReagents(step)) do ids[#ids + 1] = x.id end
        ns.Scanner.SearchManyInAH(ids)
      end
    end)
    local box = Inset(f)
    box:SetPoint("TOPLEFT", 8, framed and -60 or -30)
    box:SetPoint("BOTTOMRIGHT", -8, 28)
    f.list:SetParent(box)
    f.list:SetPoint("TOPLEFT", 4, -4)
    f.list:SetPoint("BOTTOMRIGHT", -26, 4)
    f.total = Label(f, "GameFontHighlightSmall")
    f.total:SetPoint("BOTTOMLEFT", 12, 10)
    -- show only the list's reagents in the Auction House (Auctionator's shopping tab when installed)
    f.search = Button(f, "Search AH", 90, 20, function()
      if not state.plan then return end
      local ids = {}
      for _, x in ipairs(state.plan.reagents) do ids[#ids + 1] = x.id end
      ns.Scanner.SearchManyInAH(ids)
    end)
    f.search:SetPoint("BOTTOMRIGHT", -8, 5)
    Tip(f.search, "Search the list's reagents", {
      "Shows only the reagents of this list in the Auction House.",
      "With Auctionator: all of them at once in its Shopping tab. Click a craft to search only its reagents." })
    function f:Refresh()
      local plan = state.plan
      if not plan then self:Hide() return end
      local p = ns.PROF_BY_ID[plan.opts.prof]
      self:SetSRTitle(("%s %d-%d"):format(ns.ProfName(p), plan.opts.from, plan.opts.to))
      self.list:SetData(plan.steps)
      self.total:SetText("Total: " .. ns.Money(plan.total))
      self.search:SetEnabled(ns.Scanner.IsOpen())
    end
    ns.pinned = f
  end
  if show then
    ns.CharDB().pinned = true
    f:Show()
    f:Refresh()
  else
    f:Hide()
  end
end

---------------------------------------------------------------------------
-- Auction House tab
---------------------------------------------------------------------------
local ahPanel, ahTab
local TAB_ID = "SkillRat"

local function MakeAHPanel()
  ahPanel = CreatePlanner(AuctionHouseFrame, "ah")
  ahPanel:SetFrameStrata(AuctionHouseFrame:GetFrameStrata())
  ahPanel:SetFrameLevel(AuctionHouseFrame:GetFrameLevel() + 20)
  ahPanel:ClearAllPoints()
  ahPanel:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPLEFT", 8, -62)
  ahPanel:SetPoint("BOTTOMRIGHT", AuctionHouseFrame, "BOTTOMRIGHT", -8, 30)
  ahPanel:Hide()
end

local function CreateAHTab()
  if ahTab or not AuctionHouseFrame then return end
  MakeAHPanel()

  -- LibAHTab (shipped with Auctionator and other addons): same tab row, highlight, and the other addons' pages hidden
  local lib = LibStub and LibStub("LibAHTab-1-0", true)
  if lib and not lib:DoesIDExist(TAB_ID) then
    lib:CreateTab(TAB_ID, ahPanel, "SkillRat", "SkillRat")
    ahTab = lib:GetButton(TAB_ID)
    return
  end

  -- no LibAHTab: our own tab after Blizzard's, behaving the same way
  local tabs = AuctionHouseFrame.Tabs
  local last = tabs and tabs[#tabs]
  ahTab = CreateFrame("Button", "SkillRatAuctionTab", AuctionHouseFrame, "AuctionHouseFrameDisplayModeTabTemplate")
  ahTab:SetText("SkillRat")
  PanelTemplates_TabResize(ahTab, 20, nil, 70)
  if last then
    ahTab:SetPoint("TOPLEFT", last, "TOPRIGHT", 3, 0)
  else
    ahTab:SetPoint("TOPLEFT", AuctionHouseFrame, "BOTTOMLEFT", 20, 2)
  end
  PanelTemplates_DeselectTab(ahTab)
  ahTab:SetScript("OnClick", function()
    AuctionHouseFrame:SetDisplayMode({})
    AuctionHouseFrame.displayMode = nil
    for _, tab in ipairs(AuctionHouseFrame.Tabs or {}) do PanelTemplates_DeselectTab(tab) end
    PanelTemplates_SelectTab(ahTab)
    if AuctionHouseFrame.SetTitle then AuctionHouseFrame:SetTitle("SkillRat") end
    ahPanel:Show()
  end)
  -- a Blizzard tab (Buy, Sell, Auctions) was chosen: hide ours
  hooksecurefunc(AuctionHouseFrame, "SetDisplayMode", function(_, mode)
    if mode ~= nil and #mode > 0 then
      ahPanel:Hide()
      PanelTemplates_DeselectTab(ahTab)
    end
  end)
  AuctionHouseFrame:HookScript("OnHide", function()
    ahPanel:Hide()
    PanelTemplates_DeselectTab(ahTab)
  end)
end

---------------------------------------------------------------------------
-- Next to the profession window (movable)
---------------------------------------------------------------------------
local profPanel

local function AttachToProfessions(frame)
  if not frame or frame.skillRatHooked then return end
  frame.skillRatHooked = true
  frame:HookScript("OnShow", function()
    if not profPanel then
      profPanel = CreatePlanner(UIParent, "prof")
      profPanel:EnableMouse(true)
      profPanel:SetMovable(true)
      profPanel:RegisterForDrag("LeftButton")
      profPanel:SetScript("OnDragStart", profPanel.StartMoving)
      profPanel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        ns.CharDB().profPos = { p, rp, x, y }
      end)
    end
    profPanel:ClearAllPoints()
    local pos = ns.CharDB().profPos
    if pos then
      profPanel:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
      profPanel:SetPoint("TOPLEFT", frame, "TOPRIGHT", 6, 0)
    end
    if ns.openProfession then state.prof = ns.openProfession end
    if not ns.CharDB().hideProfPanel then profPanel:Show() end
  end)
  frame:HookScript("OnHide", function() if profPanel then profPanel:Hide() end end)
end

ns.OnProfessionRead = function(profID)
  if profPanel and profPanel:IsShown() and state.prof ~= profID and not state.plan then
    state.prof = profID
    state.from, state.to = DefaultLevels(profID)
    state.profForLevels = profID
  end
  RefreshAll()
end

---------------------------------------------------------------------------
-- Standalone window (/skillrat)
---------------------------------------------------------------------------
local standalone
function ns.ToggleStandalone()
  if not standalone then
    standalone = CreatePlanner(UIParent, "solo")
    standalone:SetPoint("CENTER")
    standalone:EnableMouse(true)
    standalone:SetMovable(true)
    standalone:RegisterForDrag("LeftButton")
    standalone:SetScript("OnDragStart", standalone.StartMoving)
    standalone:SetScript("OnDragStop", standalone.StopMovingOrSizing)
    standalone:Hide()
  end
  standalone:SetShown(not standalone:IsShown())
end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------
ns.OnScanStatus = function() RefreshAll() end
ns.OnPricesChanged = function()
  -- rebuild the current list with the new prices
  if state.plan then
    local o = state.plan.opts
    state.plan = ns.Planner.Build(o)
    state.step = nil
  end
  RefreshAll()
end

ns.OnAddonLoaded = function(name)
  if name == "Blizzard_AuctionHouseUI" then CreateAHTab() end
  if name == "Blizzard_Professions" then AttachToProfessions(ProfessionsFrame) end
  if name == "Blizzard_TradeSkillUI" then AttachToProfessions(TradeSkillFrame) end
end

ns.OnLogin = function()
  if AuctionHouseFrame then CreateAHTab() end
  if ProfessionsFrame then AttachToProfessions(ProfessionsFrame) end
  if TradeSkillFrame then AttachToProfessions(TradeSkillFrame) end
end

local ah = CreateFrame("Frame")
ah:RegisterEvent("AUCTION_HOUSE_SHOW")
ah:RegisterEvent("AUCTION_HOUSE_CLOSED")
pcall(ah.RegisterEvent, ah, "GET_ITEM_INFO_RECEIVED")
pcall(ah.RegisterEvent, ah, "BAG_UPDATE_DELAYED")
ah:SetScript("OnEvent", function(_, event)
  if event == "AUCTION_HOUSE_SHOW" then
    CreateAHTab()
    if ns.CharDB().pinned and state.plan then ns.ShowPinned(true) end
    RefreshAll()
  elseif event == "AUCTION_HOUSE_CLOSED" then
    RefreshAll()
  elseif event == "BAG_UPDATE_DELAYED" then
    RefreshAll()
  elseif event == "GET_ITEM_INFO_RECEIVED" then
    if not ah.pending then
      ah.pending = true
      C_Timer.After(0.5, function() ah.pending = nil; RefreshAll() end)
    end
  end
end)
