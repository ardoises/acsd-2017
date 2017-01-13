local Copas = require "copas"
local Layer = require "layeredata"

math.randomseed (os.time ())

return function ()

  -- Classes for editor, client and server:
  local Editor = {}
  local Client = {}
  local Server = {}
  Editor.__index = Editor
  Client.__index = Client
  Server.__index = Server

  -- Create `editor`:
  local editor  = setmetatable ({}, Editor)
  local running = true
  local threads = {}

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
    while running or #to.messages ~= 0 do
      -- This sleep must be at the beginning, **not** at the end,
      -- because it would not ensure that the last message is received.
      Copas.sleep (0)
      local message = to.messages [1]
      if message and filter (table.unpack (message)) then
        if math.random (10) > 5 then
          -- Randomly sleep to create nondeterminism:
          Copas.sleep (0)
        end
        table.remove (to.messages, 1)
        -- If `message` exists and matches `filter`, return its contents.
        return table.unpack (message)
      end
    end
  end

  -- Send a message:
  local function send (to, ...)
    to.messages [#to.messages+1] = { ... }
  end

  -- Add the `send` and `receive` methods to clients and server:
  Client.send    = send
  Client.receive = receive
  Server.send    = send
  Server.receive = receive

  -- Create the server:
  local server = setmetatable ({
    proxy    = empty (),
    model    = empty (),
    clients  = {},
    messages = {},
  }, Server)
  push (server.proxy, server.model)
  editor.server = server

  -- Create a client:
  function Editor.client ()
    local client = setmetatable ({
      proxy    = empty (),
      model    = empty (),
      messages = {},
    }, Client)
    push (client.proxy, client.model)
    server.clients [client] = true
    -- Create a thread to wait for patches from other clients:
    Copas.addthread (function ()
      while true do
        local _, patch = client:receive (function (c, _) return c ~= client end)
        if not patch then
          return
        end
        apply (client.model, patch)
      end
    end)
    return client
  end

  -- Apply a patch on a client:
  function Client:patch (patch)
    local co = Copas.addthread (function ()
      -- Create a fresh layer to apply `patch`:
      local layer = empty ()
      push (self.proxy, layer)
      -- Apply `patch` locally:
      local success = apply (self.proxy, patch)
      if success then
        -- Send `patch` to the server:
        server:send (self, patch)
        -- Receive the answer from the server:
        local _, _, ack = self:receive (function (_, p, _) return p == patch end)
        if ack then
          -- Apply `patch` to the model:
          apply (self.model, patch)
        end
      end
      -- Cleanup:
      pop (self.proxy, layer)
      threads [coroutine.running ()] = nil
      return success
    end)
    -- Store the thread, required to detect termination:
    threads [co] = true
  end

  -- Create a thread to perform the server loop:
  Copas.addthread (function ()
    while running do
      -- Receive a patch from any client:
      local origin, patch = server:receive ()
      if not patch then
        return
      end
      -- Test the patch on a fresh layer:
      local layer = empty ()
      push (server.proxy, layer)
      local success = apply (server.proxy, patch)
      if success then
        -- Apply the patch to the model:
        apply (server.model, patch)
        -- Send the successful patch to all clients:
        for client in pairs (server.clients) do
          client:send (origin, patch, success)
        end
      else
        -- Send a failure message to the origin client:
        origin:send (origin, patch, success)
      end
      -- Cleanup:
      pop (server.proxy, layer)
    end
  end)

  -- Run the editor and perform actions described in the `f` function:
  function Editor.run (_, f)
    Copas.addthread (function ()
      running = true
      f ()
      running = false
    end)
    Copas.loop ()
  end

  -- Wait for edition to finish:
  function Editor.wait ()
    repeat
      Copas.sleep (0)
      local finished = next (threads) == nil
      for client in pairs (server.clients) do
        finished = finished and #client.messages == 0
      end
      finished = finished and #server.messages == 0
    until finished
    for client in pairs (server.clients) do
      local refines = client.proxy [Layer.key.refines]
      assert (#refines == 1)
    end
  end

  return editor
end
