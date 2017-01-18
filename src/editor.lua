local Copas   = require "copas"
local Layer   = require "layeredata"
local Serpent = require "serpent"

math.randomseed (os.time ())

return function (fs)

  -- Classes for editor, client and server:
  local Editor = {}
  local Client = {}
  local Server = {}
  Editor.__index = Editor
  Client.__index = Client
  Server.__index = Server

  -- Create `editor`:
  local editor  = setmetatable ({
    running = true,
    id      = 0,
    last    = os.time (),
  }, Editor)

  -- Create an empty layer:
  local function empty ()
    local layer = Layer.new {}
    layer [Layer.key.refines] = {}
    return layer
  end

  -- Apply a `patch` to a `target` layer:
  local function apply (target, patch)
    local refines = target [Layer.key.refines]
    if #refines > 0 then
      -- If `target` is a proxy, apply `patch` on it,
      -- but write to its first refinement:
      Layer.write_to (target, refines [#refines])
      local ok, err = pcall (patch, target)
      Layer.write_to (target, nil)
      return ok, err
    else
      -- If `target` is a model, apply `patch` on it.
      patch (target)
    end
  end

  -- Push `layer` in the refinements of `target`:
  local function push (target, layer)
    local refines = target [Layer.key.refines]
    refines [#refines+1] = layer
  end

  -- Pop `layer` from the refinements of `target`:
  local function pop (target, layer)
    local refines = target [Layer.key.refines]
    for i = #refines, 1, -1 do
      if refines [i] == layer then
        for j = i+1, #refines do
          refines [j-1] = refines [j]
        end
        refines [#refines] = nil
        return
      end
    end
  end

  -- Receive a message that matches `filter`:
  local function receive (to, filter)
    -- `filter` is a function that takes the message contents as arguments,
    -- and returns `true` if it is accepted:
    filter = filter or function () return true end
    while editor.running or #to.messages ~= 0 do
      -- This sleep must be at the beginning, **not** at the end,
      -- because it would not ensure that the last message is received.
      Copas.sleep (0)
      local message = to.messages [1]
      if message and filter (message) then
        -- Randomly sleep to create nondeterminism:
        if math.random () > 0.5 then Copas.sleep (0) end
        if to.id then
          print ("<", Serpent.line ({
            origin  = message.origin.id or "server",
            target  = to.id,
            connect = message.connect,
            patch   = message.patch and tostring (message.patch),
            success = message.success,
          }, {
            comment  = false,
            sortkeys = true,
            compact  = true,
            nocode   = true,
          }))
        end
        table.remove (to.messages, 1)
        -- If `message` exists and matches `filter`, return its contents.
        return message
      end
    end
  end

  -- Send a message:
  local function send (to, message)
    -- Randomly sleep to create nondeterminism:
    if math.random () > 0.5 then Copas.sleep (0) end
    if not to.id then
      print (">", Serpent.line ({
        origin  = message.origin.id or "server",
        connect = message.connect,
        patch   = message.patch and tostring (message.patch),
        success = message.success,
      }, {
        comment  = false,
        sortkeys = true,
        compact  = true,
        nocode   = true,
      }))
    end
    editor.last = os.time ()
    to.messages [#to.messages+1] = message
    -- Randomly sleep to create nondeterminism:
    if math.random () > 0.5 then Copas.sleep (0) end
  end

  -- Add the `send` and `receive` methods to clients and server:
  Client.send    = send
  Client.receive = receive
  Server.send    = send
  Server.receive = receive

  -- Create the server:
  editor.server = setmetatable ({
    proxy    = empty (),
    model    = empty (),
    patches  = {},
    clients  = {},
    messages = {},
  }, Server)
  push (editor.server.proxy, editor.server.model)

  -- Create a thread to perform the server loop:
  Copas.addthread (function ()
    while editor.running do
      -- Receive a patch from any client:
      local message = editor.server:receive ()
      if not message then
        return
      end
      if message.connect then
        for _, t in ipairs (editor.server.patches) do
          message.origin:send {
            success = true,
            patch   = t.patch,
            origin  = t.origin,
          }
        end
        editor.server.clients [message.origin] = true
      elseif message.patch then
        -- Test the patch on a fresh layer:
        local layer = empty ()
        push (editor.server.proxy, layer)
        local success = apply (editor.server.proxy, message.patch)
        if success then
          -- Apply the patch to the model:
          editor.server.patches [#editor.server.patches+1] = message
          apply (editor.server.model, message.patch)
          -- Send the successful patch to all clients:
          for client in pairs (editor.server.clients) do
            client:send {
              success = success,
              origin  = message.origin,
              patch   = message.patch,
            }
          end
        else
          -- Send a failure message to the origin client:
          message.origin:send {
            success = success,
            origin  = message.origin,
            patch   = message.patch,
          }
        end
        -- Cleanup:
        pop (editor.server.proxy, layer)
      else
        assert (false)
      end
    end
  end)

  -- Create a client:
  function Editor.client ()
    local client = setmetatable ({
      id       = editor.id,
      proxy    = empty (),
      model    = empty (),
      messages = {},
    }, Client)
    editor.id = editor.id + 1
    push (client.proxy, client.model)
    editor.server:send {
      origin  = client,
      connect = true,
    }

    -- Create a thread to wait for patches from other clients:
    Copas.addthread (function ()
      while true do
        local message = client:receive (function (message) return message.origin ~= client end)
        if not message then
          return
        end
        apply (client.model, message.patch)
      end
    end)
    return client
  end

  -- Apply a patch on a client:
  function Client:patch (patch)
    -- Create a fresh layer to apply `patch`:
    local layer = empty ()
    push (self.proxy, layer)
    -- Apply `patch` locally:
    local success = apply (self.proxy, patch)
    if success then
      -- Send `patch` to the server:
      editor.server:send {
        origin = self,
        patch  = patch,
      }
      Copas.addthread (function ()
        -- Receive the answer from the server:
        local message = self:receive (function (message) return message.origin == self and message.patch == patch end)
        if message.success then
          -- Apply `patch` to the model:
          apply (self.model, patch)
        end
        -- Cleanup:
        pop (self.proxy, layer)
      end)
    else
      -- Cleanup:
      pop (self.proxy, layer)
    end
    return success
  end

  -- Run the editor and perform actions described in the `fs` functions:
  Copas.addthread (function ()
    editor.running = true
    for _, f in ipairs (fs) do
      local client = editor:client ()
      Copas.addthread (function ()
        f (client)
      end)
    end
  end)
  Copas.addthread (function ()
    repeat
      Copas.sleep (0)
    until os.time () - editor.last >= 2 -- seconds
    editor.running = false
  end)
  Copas.loop ()

  return editor
end
