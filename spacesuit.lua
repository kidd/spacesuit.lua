_TEST = true

local assert_count = 0
local assert_equal = function(expected, actual, failure_message, level)
  level = level or 2
  assert_count =  assert_count + 1
  if not (expected == actual) then
    if ngx then print(ngx._log) end
    error(failure_message or
      j{"[0;31;40mError: ",       i(expected) ,
        " expected, but given " , i(actual),  "[0;37;40m"}, level)
  end
  return true
end

local assert_equal_rec = function (expected, actual, failure_message, level)
  level = level or 2
  if type(expected) == 'table' then
    if #expected == 0 and #actual == 0  then return true end

    for i = 0, #expected do
      assert_equal_rec(expected[i], actual[i], failure_message, level + 1)
    end
  else
    return assert_equal(expected, actual, failure_message, level+1)
  end
  return true
end

local assert_raise = function (f, msg)
  if pcall(f) then error(msg or 'raised expected but not happened') end
  return true
end

local spy = function (f)
  local log = {}                -- deep hash logging all call params and result
  local leaf = {}               -- unique value for result
  local count = 0
  return setmetatable(
    { called = function (x)
          return
            assert(((x == nil) and (count > 0)) or (x == count))
    end,
      called_with = function (...)
        local args = {...}      -- arguments
        local cache = log       -- alias to navigate the log
        local call_log = {}
        for i, v in pairs(args) do -- we navigate the log table
          if not cache[v] then
            error('not called with ' .. v)
          else
            cache = cache[v]
            table.insert(call_log, v) -- logging in the call_log the actual params
          end
        end
        if not cache[leaf] then -- the tree exists but is not a leaf
          error ('not leaf')
        else
          return {
            and_returns_with = function(...)
              local args = {...}
              local call_path = log
              for i,v in ipairs(call_log) do
                call_path = call_path[v]
              end
              if call_path[leaf] ~= args[1] then error('not returned') end
              -- for i,v in ipairs(call_path[leaf]) do
              --   if call_log[i] ~= v then error('not returned') end
              -- end
              return true
            end
          }
        end
    end,

    }, {__call = function (t, ...)
          local args = {...}
          local cache_path = log
          count = count+1
          for i, v in ipairs(args) do
            cache_path[v] = {}
            cache_path = cache_path[v]
          end
          cache_path[leaf] = f(...)
          return cache_path[leaf]
    end
  })
end

local make_spy = function (m, fname)
  local old = m[fname]
  local sp = spy(old)
  m[fname] = setmetatable(
    {clean = function () m[fname] = old end },
    { __call = function(t, ...) return sp(...) end,
      __index = sp})
end

local stub = function (m, fname, f)
  local old = m[fname]
  m[fname] = setmetatable(
    {clean = function () m[fname] = old end },
    { __call = function(t, ...) return f(...) end,
      __index = f})
end

-- TESTS
-- testing assert raise
assert_raise(function() error() end)
assert_raise(function() assert_raise(function() end) end)
assert_raise(function() assert_raise(function() assert_raise(function() error() end) end) end)

local function inc(a) return a+1 end
local function sum(x,y) return x+y end
-- spy returning new fun
local s = spy(inc)

assert(6  == s(5))
assert(-4 == s(-5))

-- Called
assert(s.called())              -- any number of times
assert(s.called(2))             -- fixed number of times
assert(s.called(2))
assert_raise(function() s.called(3) end)
assert_raise(function() s.called(1) end)

s.called_with(5).and_returns_with(6)
s.called_with(-5).and_returns_with(-4)
assert_raise(function() s.called_with(5).and_returns_with(7) end)
assert_raise(function() s.called_with(4, 5) end)
s = spy(inc)                    -- new spy
assert_raise(function() s.called_with(5).and_returns_with(6) end)
assert(s.called(0))             -- not called ever

-- multiple params
local su = spy(sum)
assert(su(5, 6) == 11)
assert(su(6,7) == 13)
su.called_with(5, 6).and_returns_with(11)
su.called_with(6, 7).and_returns_with(13)
assert_raise(function() su.called_with(5, 4).and_returns_with(9) end)

-- spy substituting a function of a module
local m = { foo = function (x, y) return x + y end }
make_spy(m, 'foo')
assert(m.foo(1,2) == 3)
assert(m.foo(5,6) == 11)
assert(m.foo.called_with(1,2).and_returns_with(3))
-- cleaning spy
m.foo.clean()
assert_raise(function() m.foo.called_with(1,2).and_returns_with(3) end)
assert(m.foo(4,3) == 7)

stub(m, 'foo', function() return 42 end)
assert(m.foo(333) == 42)
assert_raise(m.foo(333,33) == 44)
m.foo.clean()
assert(m.foo(4,3) == 7)

return {
  on = make_spy,
  new = spy,
  assert_raise = assert_raise,
  assert_equal = assert_equal,
  assert_equal_rec = assert_equal_rec
}
