local assert = require "luassert"
local Editor = require "editor"

math.randomseed (os.time ())

describe ("collaborative edition", function ()

  it ("works on simple example", function ()
    -- This example creates two clients `c1` and `c2`.
    -- They update the model by adding `1` to a field of the model.
    local function test (client)
      client:patch (function (model)
        model.x = (model.x or 0) + 1
      end)
    end
    local editor = Editor { test, test, test, test }
    -- Check that the final value is `2` for the server model,
    -- and for both clients:
    assert.are.equal (4, editor.server.model.x)
    for client in pairs (editor.clients) do
      assert.are.equal (client.model.x, editor.server.model.x)
      assert.are.equal (client.proxy.x, editor.server.model.x)
    end
  end)

  it ("works on simple example", function ()
    -- This example creates two clients `c1` and `c2`.
    -- They update the model by adding `1` to a field of the model.
    local function test (client)
      local value = math.random (100)
      client:patch (function (model)
        model.x = value
      end)
    end
    local editor = Editor { test, test, test, test }
    for client in pairs (editor.clients) do
      assert.are.equal (client.model.x, editor.server.model.x)
      assert.are.equal (client.proxy.x, editor.server.model.x)
    end
  end)

  it ("is consistent between clients and server", function ()
    -- This example creates several clients that apply several patches.
    -- Each patch updates a specific field of the model with a random value.
    local nmessages  = 5
    local function test (client)
      for _ = 1, nmessages do
        -- We cannot put the `math.random` call within the patch,
        -- as its result would take different values in the server
        -- and the clients.
        local value = math.random (1000)
        client:patch (function (model)
          model.value = value
        end)
      end
    end
    local editor = Editor { test, test, test, test }
    -- Check that the server and all clients agree on the final value:
    for client in pairs (editor.clients) do
      assert.are.equal (client.model.value, editor.server.model.value)
      assert.are.equal (client.proxy.value, editor.server.model.value)
    end
  end)

  it ("is consistent with patch order", function ()
    -- This example creates several clients, that apply several patches.
    -- The model stores several stacks, one for each client.
    -- Each patch pushes a random value to the stack corresponding
    -- to its client in the model.
    -- The sequence of patches applied from a client should be preserved.
    local clients    = {}
    local values     = {}
    local parameters = {}
    local nclients   = 5
    local nmessages  = 5
    for i = 1, nclients do
      parameters [i] = function (client)
        local cvalues    = {}
        values  [client] = cvalues
        clients [i     ] = client
        client:patch (function (model)
          model [i] = {}
        end)
        for _ = 1, nmessages do
          -- We cannot put the `math.random` call within the patch,
          -- as its result would take different values in the server
          -- and the clients.
          local value = math.random (1000)
          cvalues [#cvalues+1] = value
          client:patch (function (model)
            model [i] [#model [i]+1] = value
          end)
        end
      end
    end
    local _ = Editor (parameters)
    -- Check that the sequence of patches is preserved for each client:
    for i, client in ipairs (clients) do
      local cvalues = values [client]
      for j, value in ipairs (client.model [i]) do
        assert.are.equal (value, cvalues [j])
      end
    end
  end)

end)
