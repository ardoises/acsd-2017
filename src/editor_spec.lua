local assert = require "luassert"
local Editor = require "editor"

math.randomseed (os.time ())

describe ("collaborative edition", function ()

  it ("works on simple example", function ()
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
    assert.are.equal (2         , editor.server.model.x)
    assert.are.equal (c1.model.x, editor.server.model.x)
    assert.are.equal (c2.model.x, editor.server.model.x)
  end)

  it ("is consistent between clients and server", function ()
    local editor    = Editor ()
    local clients   = {}
    local nclients  = 2
    local nmessages = 3
    for i = 1, nclients do
      clients [i] = editor:client ()
    end
    editor:run (function ()
      for _ = 1, nmessages do
        for _, client in ipairs (clients) do
          local value = math.random (1000)
          client:patch (function (model)
            model.value = value
          end)
        end
      end
      editor:wait ()
    end)
    for _, client in ipairs (clients) do
      assert.are.equal (client.model.value, editor.server.model.value)
    end
  end)

  it ("is consistent with patch order", function ()
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
    for i, client in ipairs (clients) do
      local cvalues = values [client]
      for j, value in ipairs (client.model [i]) do
        assert.are.equal (value, cvalues [j])
      end
    end
  end)

end)
