local Harness = require("tests.harness")
local Input = require("src.core.Input")

-- Input:poll takes an injectable isDown(key) function precisely so it can
-- be unit tested without a real love.keyboard.

Harness.test("Input: default keyboard binding, isDown reflects the primary key", function()
  local input = Input.new()
  local pressedKeys = { up = true }
  input:poll(function(key) return pressedKeys[key] or false end)
  Harness.assertTrue(input:isDown("up"))
  Harness.assertTrue(not input:isDown("down"))
end)

Harness.test("Input: alt (WASD-style) binding also drives the same button", function()
  local input = Input.new()
  local pressedKeys = { w = true } -- alt binding for "up"
  input:poll(function(key) return pressedKeys[key] or false end)
  Harness.assertTrue(input:isDown("up"))
end)

Harness.test("Input: pressed() is true only on the step the key went down", function()
  local input = Input.new()
  local down = false
  local isDown = function(key) return key == "z" and down end

  input:poll(isDown) -- step 1: not down yet
  Harness.assertTrue(not input:pressed("a"))

  down = true
  input:poll(isDown) -- step 2: just went down
  Harness.assertTrue(input:pressed("a"), "should be a fresh press")

  input:poll(isDown) -- step 3: still held
  Harness.assertTrue(not input:pressed("a"), "should not re-fire while held")
  Harness.assertTrue(input:isDown("a"), "isDown should still be true while held")
end)

Harness.test("Input: released() is true only on the step the key went up", function()
  local input = Input.new()
  local down = true
  local isDown = function(key) return key == "z" and down end

  input:poll(isDown)
  Harness.assertTrue(not input:released("a"))

  down = false
  input:poll(isDown)
  Harness.assertTrue(input:released("a"), "should fire on release")

  input:poll(isDown)
  Harness.assertTrue(not input:released("a"), "should not re-fire once already released")
end)

Harness.test("Input: rebind changes which key drives a button", function()
  local input = Input.new()
  input:rebind("a", "k")
  local isDown = function(key) return key == "k" end
  input:poll(isDown)
  Harness.assertTrue(input:isDown("a"))
end)

Harness.test("Input: rebind rejects an unknown button name", function()
  local input = Input.new()
  local ok = pcall(function() input:rebind("nope", "k") end)
  Harness.assertTrue(not ok, "rebinding an unknown button should error")
end)
