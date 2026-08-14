-- Field.lua pulls in love.graphics-touching modules (Font, TileImage),
-- but those only call love.* *inside* functions, not at module-load
-- time -- so Field itself, and its pure Field.formatHud helper, are
-- headlessly requireable/testable like the rest of this codebase, even
-- though Field.new()/Field:draw() themselves are not (they need a real
-- love context).

local Harness = require("tests.harness")
local Field = require("src.app.states.Field")
local Stats = require("src.entities.Stats")

Harness.test("Field.formatHud: matches the VERIFIED 'LP <n> MP <n> G <n>' format exactly", function()
  local stats = Stats.new({ curLP = 19, maxLP = 19, curMP = 6, maxMP = 6, level = 1, gold = 50 })
  Harness.assertEqual(Field.formatHud(stats), "LP 19 MP 6 G 50")
end)

Harness.test("Field.formatHud: reflects live stat changes (e.g. after damage)", function()
  local stats = Stats.new({ curLP = 19, maxLP = 19, curMP = 6, maxMP = 6, gold = 50 })
  stats:damage(3)
  Harness.assertEqual(Field.formatHud(stats), "LP 16 MP 6 G 50")
end)
