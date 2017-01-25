local Copas   = require "copas"
local Layer   = require "layeredata"
local Serpent = require "serpent"

math.randomseed (os.time ())

return function (fs)

  -- Classes for editor, client and server:
  local Editor_mt = {}
  local Editor    = setmetatable ({}, Editor_mt)
  Editor.__index  = Editor
  function Editor_mt.__call (_, t)
    return setmetatable (t, Editor)
  end

  local Server_mt = {}
  local Server    = setmetatable ({}, Server_mt)
  Server.__index  = Server
  function Server_mt.__call (_, t)
    return setmetatable (t, Server)
  end

  local Client_mt = {}
  local Client    = setmetatable ({}, Client_mt)
  Client.__index  = Client
  function Client_mt.__call (_, t)
    return setmetatable (t, Client)
  end

  -- The `editor`:
  local editor  = Editor {
    running = true,
    id      = 0,
    last    = os.time (),
  }

  -- Return a new empty layer:
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

  -- Add `layer` at the top of the refinements of `target`:
  local function push (target, layer)
    local refines = target [Layer.key.refines]
    refines [#refines+1] = layer
  end

  -- Remove the bottommost layer from the refinements of `target`:
  local function pop (target)
    local refines = target [Layer.key.refines]
    for i = 2, #refines-1 do -- start at 2 to avoid removing the model
      refines [i-1] = refines [i]
    end
    refines [#refines] = nil
  end

  -- Return the first message received by `to`:
  local function receive (to)
    while editor.running or #to.messages ~= 0 do
      -- This sleep must be at the beginning, **not** at the end,
      -- because it would not ensure that the last message is received.
      Copas.sleep (0)
      local message = to.messages [1]
      if message then
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

  -- Send a `message` to `to`:
  local function send (to, message)
    -- Randomly sleep to create nondeterminism:
    if math.random () > 0.5 then Copas.sleep (0) end
    if to.id then
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
  editor.server = Server {
    proxy    = empty (),
    model    = empty (),
    patches  = {},
    clients  = {},
    messages = {},
  }
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
        pop (editor.server.proxy)
      else
        assert (false)
      end
    end
  end)

  -- Create a client:
  function Editor.client ()
    local client = Client {
      id       = editor.id,
      proxy    = empty (),
      model    = empty (),
      messages = {},
    }
    editor.id = editor.id + 1
    push (client.proxy, client.model)
    editor.server:send {
      origin  = client,
      connect = true,
    }

    -- Create a thread to wait for patches and answers:
    Copas.addthread (function ()
      while true do
        local message = client:receive ()
        if not message then
          return
        end
        editor.last = os.time ()
        if message.success then
          apply (client.model, message.patch)
        end
        if message.origin == client then
          pop (client.proxy)
        end
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
    else
      -- Cleanup:
      pop (self.proxy)
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
