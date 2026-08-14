local Harness = require("tests.harness")
local sha1 = require("src.core.Sha1")

-- FIPS 180-1 / common reference vectors, cross-checked against the system
-- `shasum -a 1` tool during development.
Harness.test("sha1: empty string", function()
  Harness.assertEqual(sha1(""), "da39a3ee5e6b4b0d3255bfef95601890afd80709")
end)

Harness.test("sha1: 'abc'", function()
  Harness.assertEqual(sha1("abc"), "a9993e364706816aba3e25717850c26c9cd0d89d")
end)

Harness.test("sha1: 'The quick brown fox jumps over the lazy dog'", function()
  Harness.assertEqual(
    sha1("The quick brown fox jumps over the lazy dog"),
    "2fd4e1c67a2d28fced849ee1bb76e7391b93eb12")
end)

Harness.test("sha1: input spanning multiple 64-byte blocks", function()
  -- 128 'a' characters: two full blocks after the 0x80 + length padding.
  local input = string.rep("a", 128)
  -- Cross-checked with `python3 -c "import hashlib;
  -- print(hashlib.sha1(b'a'*128).hexdigest())"`.
  local expected = "ad5b3fdbcb526778c2839d2f151ea753995e26a0"
  Harness.assertEqual(sha1(input), expected)
end)
