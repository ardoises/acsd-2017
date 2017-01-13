local assert = require "luassert"
local Editor = require "editor"

math.randomseed (os.time ())

describe ("collaborative edition", function ()

  it ("works on simple example", function ()
    -- This example creates two clients `c1` and `c2`.
    -- They update the model by adding `1` to a field of the model.
    local editor = Editor ()
    local c1 = editor:client ()
    local c2 = editor:client ()
    editor:run (function ()
      c1:patch (function (model)
        model.x = (model.x or 0) + 1
      end)
      c2:patch (function (model)
        model.x = (model.x or 0) + 1
      end)
      editor:wait ()
    end)
    -- Check that the final value is `2` for the server model,
    -- and for both clients:
    assert.are.equal (2         , editor.server.model.x)
    assert.are.equal (c1.model.x, editor.server.model.x)
    assert.are.equal (c2.model.x, editor.server.model.x)
    assert.are.equal (c1.proxy.x, editor.server.model.x)
    assert.are.equal (c2.proxy.x, editor.server.model.x)
  end)

  it ("is consistent between clients and server", function ()
    -- This example creates several clients that apply several patches.
    -- Each patch updates a specific field of the model with a random value.
    local editor    = Editor ()
    local clients   = {}
    local nclients  = 5
    local nmessages = 5
    for i = 1, nclients do
      clients [i] = editor:client ()
    end
    editor:run (function ()
      for _ = 1, nmessages do
        for _, client in ipairs (clients) do
          -- We cannot put the `math.random` call within the patch,
          -- as its result would take different values in the server
          -- and the clients.
          local value = math.random (1000)
          client:patch (function (model)
            model.value = value
          end)
        end
      end
      editor:wait ()
    end)
    -- Check that the server and all clients agree on the final value:
    for _, client in ipairs (clients) do
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
    local editor    = Editor ()
    local clients   = {}
    local nclients  = 5
    local nmessages = 5
    local values    = {}
    for i = 1, nclients do
      local client    = editor:client ()
      clients [i]     = client
      values [client] = {}
    end
    editor:run (function ()
      for i, client in ipairs (clients) do
        client:patch (function (model)
          model [i] = {}
        end)
      end
      for _ = 1, nmessages do
        for i, client in ipairs (clients) do
          -- We cannot put the `math.random` call within the patch,
          -- as its result would take different values in the server
          -- and the clients.
          local value   = math.random (1000)
          local cvalues = values [client]
          cvalues [#cvalues+1] = value
          client:patch (function (model)
            local mypart = model [i]
            mypart [#mypart+1] = value
          end)
        end
      end
      editor:wait ()
    end)
    -- Check that the sequence of patches is preserved for each client:
    for i, client in ipairs (clients) do
      local cvalues = values [client]
      for j, value in ipairs (client.model [i]) do
        assert.are.equal (value, cvalues [j])
      end
    end
  end)

end)
