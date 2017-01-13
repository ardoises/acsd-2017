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
        model.x = 1
      end)
      c2:patch (function (model)
        model.y = 2
      end)
      editor:wait ()
    end)
    assert.are.equal (c1.model.x, editor.server.model.x)
    assert.are.equal (c1.model.y, editor.server.model.y)
    assert.are.equal (c2.model.x, editor.server.model.x)
    assert.are.equal (c2.model.y, editor.server.model.y)
  end)

  it ("works with random values", function ()
    local editor = Editor ()
    local clients = {}
    local n       = 10
    for i = 1, n do
      clients [i] = editor:client ()
    end
    editor:run (function ()
      for _ = 1, n do
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

end)
