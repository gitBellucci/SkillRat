-- SkillRat: the cheapest way from one skill level to another.
-- At each skill point, every usable recipe is priced: reagent cost (current Auction House listings, cheapest first,
-- minus what earlier steps already bought) divided by the chance that a craft gives a point. The cheapest is kept,
-- its reagents are taken from the listings, and so on up to the target level.
local _, ns = ...

local Planner = {}
ns.Planner = Planner

-- Chance that a craft gives a skill point at level `s`: orange 100%, then falling to 0 at grey (Classic rule)
function Planner.Chance(r, s)
  local minL, yellow, grey = r[4], r[5], r[6]
  if s < minL or s >= grey then return 0 end
  if s < yellow then return 1 end
  return (grey - s) / (grey - yellow)
end

-- Supply of one reagent: vendor (unlimited, fixed price) or Auction House listings
local function NewMarket()
  local m = { used = {} }
  local db = ns.DB()

  -- price of the next unit of itemID; nil if unknown, math.huge if the Auction House has run out
  function m.UnitPrice(itemID)
    local vendor = ns.VendorPrice(itemID)
    if vendor then return vendor, "vendor" end
    local p = db.prices[itemID]
    if not p or not p.list then return nil, "unknown" end
    local need = (m.used[itemID] or 0)
    local list = p.list
    for i = 1, #list, 2 do
      need = need - list[i + 1]
      if need < 0 then return list[i], "ah" end
    end
    if #list == 0 then return nil, "none" end
    -- more than what is listed: last listed price with a penalty, so cheaper recipes are preferred
    return list[#list - 1] * 1.5, "short"
  end

  function m.Take(itemID, n)
    m.used[itemID] = (m.used[itemID] or 0) + n
  end

  -- exact cost of buying n units from scratch, and how many could not be bought
  function m.CostOf(itemID, n)
    local vendor = ns.VendorPrice(itemID)
    if vendor then return vendor * n, 0, "vendor" end
    local p = db.prices[itemID]
    if not p or not p.list or #p.list == 0 then return nil, n, "unknown" end
    local cost, left, list = 0, n, p.list
    for i = 1, #list, 2 do
      local take = math.min(left, list[i + 1])
      cost, left = cost + take * list[i], left - take
      if left <= 0 then break end
    end
    if left > 0 then cost = cost + left * list[#list - 1] end -- missing units at the last listed price
    return cost, left, "ah"
  end
  return m
end

local function UsesExcluded(r, excluded)
  local reag = r[8]
  for i = 1, #reag, 2 do
    if excluded[reag[i]] then return true end
  end
  return false
end

--- opts: { prof, from, to, mode = "trainer" | "known" | "all", excluded = { [itemID] = true } }
--- Returns a plan: { steps = { { recipe, from, to, crafts, cost } }, total, reagents = { { id, need, cost, short } },
---   missing = { [itemID] = true }, stoppedAt = level or nil }
function Planner.Build(opts)
  local recipes = ns.Recipes(opts.prof)
  local known = ns.CharDB().known[opts.prof]
  local excluded = opts.excluded or {}
  local candidates = {}
  for _, r in ipairs(recipes) do
    local ok
    if opts.mode == "known" then
      ok = known and known[r[1]]
    elseif opts.mode == "all" then
      ok = true
    else
      ok = (known and known[r[1]]) or r[7] == 0
    end
    if ok and not UsesExcluded(r, excluded) then candidates[#candidates + 1] = r end
  end

  local market = NewMarket()
  local plan = { steps = {}, missing = {}, opts = opts }
  local crafts = {}   -- [recipe] = fractional crafts
  local order = {}
  local last

  for s = opts.from, opts.to - 1 do
    local best, bestCost
    for _, r in ipairs(candidates) do
      local chance = Planner.Chance(r, s)
      if chance > 0 then
        local cost, reag = 0, r[8]
        for i = 1, #reag, 2 do
          local unit, why = market.UnitPrice(reag[i])
          if not unit then
            plan.missing[reag[i]] = true
            cost = nil
            break
          end
          cost = cost + unit * reag[i + 1]
        end
        if cost then
          local perPoint = cost / chance
          if not bestCost or perPoint < bestCost then best, bestCost = r, perPoint end
        end
      end
    end
    if not best then
      plan.stoppedAt = s
      break
    end
    local n = 1 / Planner.Chance(best, s)
    local reag = best[8]
    for i = 1, #reag, 2 do market.Take(reag[i], reag[i + 1] * n) end
    crafts[best] = (crafts[best] or 0) + n
    if last and last.recipe == best then
      last.to = s + 1
      last.crafts = last.crafts + n
    else
      last = { recipe = best, from = s, to = s + 1, crafts = n }
      order[#order + 1] = last
    end
  end

  return Planner.Finish(plan, order, market)
end

-- whole crafts, then the exact cost of every reagent bought from scratch
function Planner.Finish(plan, order, market)
  local need = {}
  for _, step in ipairs(order) do
    step.crafts = math.max(1, math.ceil(step.crafts - 0.001))
    local reag = step.recipe[8]
    for i = 1, #reag, 2 do need[reag[i]] = (need[reag[i]] or 0) + reag[i + 1] * step.crafts end
  end
  local total, list = 0, {}
  local unitCost = {}
  for id, n in pairs(need) do
    local cost, short, kind = market.CostOf(id, n)
    total = total + (cost or 0)
    unitCost[id] = cost and cost / n or 0
    list[#list + 1] = { id = id, need = n, cost = cost, short = short > 0 and short or nil, kind = kind }
  end
  table.sort(list, function(a, b) return (a.cost or 0) > (b.cost or 0) end)
  for _, step in ipairs(order) do
    local c, reag = 0, step.recipe[8]
    for i = 1, #reag, 2 do c = c + unitCost[reag[i]] * reag[i + 1] * step.crafts end
    step.cost = c
  end
  plan.steps, plan.reagents, plan.total = order, list, total
  return plan
end

-- A saved list: { opts = {...}, steps = { { spell, from, to, crafts } } } -> a plan priced with today's prices
function Planner.Rebuild(saved)
  local byId = {}
  for _, r in ipairs(ns.Recipes(saved.opts.prof) or {}) do byId[r[1]] = r end
  local order = {}
  for _, st in ipairs(saved.steps or {}) do
    local r = byId[st.spell]
    if r then order[#order + 1] = { recipe = r, from = st.from, to = st.to, crafts = st.crafts } end
  end
  local plan = { steps = {}, missing = {}, opts = saved.opts, savedName = saved.name }
  return Planner.Finish(plan, order, NewMarket())
end

-- What to keep of a plan to save it
function Planner.ToSaved(plan, name)
  local steps = {}
  for _, st in ipairs(plan.steps) do
    steps[#steps + 1] = { spell = st.recipe[1], from = st.from, to = st.to, crafts = st.crafts }
  end
  local o = plan.opts
  return { name = name, t = time(), steps = steps,
           opts = { prof = o.prof, from = o.from, to = o.to, mode = o.mode, excluded = o.excluded } }
end

-- Reagents of one step (or the whole plan): { { id, need } }
function Planner.StepReagents(step)
  local out, reag = {}, step.recipe[8]
  for i = 1, #reag, 2 do out[#out + 1] = { id = reag[i], need = reag[i + 1] * step.crafts } end
  return out
end
