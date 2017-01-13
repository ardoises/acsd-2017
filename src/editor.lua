local Copas = require "copas"
local Layer = require "layeredata"

math.randomseed (os.time ())

return function ()
  local Editor = {}
  local Client = {}
  local Server = {}
  Editor.__index = Editor
  Client.__index = Client
  Server.__index = Server

  local editor  = setmetatable ({}, Editor)
  local running = true
  local threads = {}

  local function empty ()
    local layer = Layer.new {}
    layer [Layer.key.refines] = {}
    return layer
  end

  local function apply (target, patch)
    local refines = target [Layer.key.refines]
    if #refines > 0 then -- proxy
      Layer.write_to (target, refines [#refines])
      local ok, err = pcall (patch, target)
      Layer.write_to (target, nil)
      return ok, err
    else -- model
      patch (target)
    end
  end

  local function push (target, layer)
    local refines = target [Layer.key.refines]
    refines [#refines+1] = layer
  end

  local function pop (target, layer)
    local refines = target [Layer.key.refines]
    for i = #refines, 1, -1 do
      if refines [i] == layer then
        table.remove (refines, i)
        return
      end
    end
  end

  local function receive (to, filter)
    filter = filter or function () return true end
    while running do
      Copas.sleep (0)
      local message = to.messages [1]
      if message and filter (table.unpack (message)) then
        if math.random (10) > 5 then
          Copas.sleep (0)
        end
        table.remove (to.messages, 1)
        return table.unpack (message)
      end
    end
  end

  local function send (to, ...)
    to.messages [#to.messages+1] = { ... }
    Copas.sleep (0)
  end

  local server = setmetatable ({
    proxy    = empty (),
    model    = empty (),
    clients  = {},
    messages = {},
  }, Server)
  push (server.proxy, server.model)

  function Client.new ()
    local client = setmetatable ({
      proxy    = empty (),
      model    = empty (),
      messages = {},
    }, Client)
    push (client.proxy, client.model)
    server.clients [client] = true
    Copas.addthread (function ()
      while running do
        client:update ()
      end
    end)
    return client
  end
  Client.send    = send
  Client.receive = receive
  Server.send    = send
  Server.receive = receive

  function Client:patch (patch)
    local co = Copas.addthread (function ()
      -- create a new layer for the patch
      local layer = empty ()
      push (self.proxy, layer)
      -- apply the patch locally
      local success = apply (self.proxy, patch)
      if success then
        -- send the patch to the server
        server:send (self, patch)
        -- receive answer from the server
        local _, _, ack = self:receive (function (_, p, _) return p == patch end)
        if ack then
          -- insert the patch into the model
          apply (self.model, patch)
        end
      end
      -- cleanup
      pop (self.proxy, layer)
      threads [coroutine.running ()] = nil
      return success
    end)
    threads [co] = true
  end

  function Client:update ()
    local _, patch = self:receive (function (client, _) return client ~= self end)
    if patch then
      apply (self.model, patch)
    end
  end

  function Server:handle ()
    local origin, patch = self:receive ()
    if not patch then
      return
    end
    -- test the patch
    local layer = empty ()
    push (self.proxy, layer)
    local success = apply (self.proxy, patch)
    if success then
      -- apply the patch
      apply (self.model, patch)
      -- send the successful patch to clients
      for client in pairs (self.clients) do
        client:send (origin, patch, success)
      end
    else
      -- send failure message
      origin:send (origin, patch, success)
    end
    -- cleanup
    pop (self.proxy, layer)
  end

  Copas.addthread (function ()
    while running do
      server:handle ()
    end
  end)

  editor.server = server

  function Editor.run (_, f)
    Copas.addthread (function ()
      running = true
      f ()
      running = false
    end)
    Copas.loop ()
  end

  function Editor.wait ()
    repeat
      Copas.sleep (0)
      local finished = next (threads) == nil
      for client in pairs (server.clients) do
        finished = finished and #client.messages == 0
      end
      finished = finished and #server.messages == 0
    until finished
  end

  function Editor.client ()
    return Client.new ()
  end

  return editor
end
