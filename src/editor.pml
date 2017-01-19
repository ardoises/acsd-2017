#define CLIENTS	3
#define PATCHES 3

typedef Client {
  chan queue = [CLIENTS * PATCHES] of { bool, bool, byte, byte, byte }; // connection, success, origin, patch | model, patch_id
  byte model = 0;
  byte layers  [PATCHES] = 255;
  byte patches [PATCHES] = 0;
}

typedef Server {
  chan queue = [CLIENTS * PATCHES] of { bool, bool, byte, byte, byte }; // connection, success, origin, patch, patch_id
  bool clients [CLIENTS] = false;
  byte model = 0;
}

Client clients [CLIENTS];
Server server;

proctype server_loop () {
  byte origin, patch, patch_id;
  do
  :: server.queue ? true, false, origin, patch, patch_id ->
     server.clients [origin] = true;
     clients [origin].queue ! true, true, origin, server.model, patch_id;
  :: server.queue ? false, false, origin, patch, patch_id ->
     clients [origin].queue ! false, false, origin, patch, patch_id;
  :: server.queue ? false, false, origin, patch, patch_id ->
     server.model = patch;
     byte id = 0;
     do
     :: id < CLIENTS ->
        if
        ::   server.clients [id] ->
           clients [id].queue ! false, true, origin, patch, patch_id;
        :: ! server.clients [id] ->
           break;
        fi
        id = id + 1;
     :: id >= CLIENTS ->
        break;
     od;
  od
}

proctype client_loop (byte id) {
  byte origin, patch, patch_id;
  do
  :: clients [id].queue ? true, true, id, patch, patch_id ->
     clients [id].model = patch;
  :: clients [id].queue ? false, true, origin, patch, patch_id ->
     if
     :: origin != id ->
        clients [id].model = patch;
     :: origin == id ->
        clients [id].model = patch;
        clients [id].layers [patch_id] = 255;
     fi
  :: clients [id].queue ? false, false, id, patch, patch_id ->
     clients [id].layers [patch_id] = 255;
  od;
}

proctype patch_client (byte id) {
  byte patch_id = 0;
  run client_loop (id);
  server.queue ! true, false, id, 255, 0;
  do
  :: patch_id < PATCHES ->
     clients [id].layers [patch_id] = clients [id].patches [patch_id];
     server.queue ! false, false, id, clients [id].patches [patch_id], patch_id;
     patch_id = patch_id + 1;
  :: patch_id < PATCHES ->
     patch_id = patch_id + 1;
  :: patch_id >= PATCHES ->
     break;
  od;
}

init {
  run server_loop ();
  byte id    = 0;
  byte value = 1;
  do
  :: id < CLIENTS ->
     byte j = 0
     do
     :: j < PATCHES ->
        clients [id].layers  [j] = 255;
        clients [id].patches [j] = value;
        value = value + 1;
        j     = j     + 1;
     :: j >= PATCHES ->
        break;
     od;
     run patch_client (id);
     id = id + 1;
  :: id >= CLIENTS ->
     break;
  od
}

ltl flushed {
  eventually always (
     true
  && clients [0].layers [0] == 255
  && clients [0].layers [1] == 255
  && clients [0].layers [2] == 255
  && clients [1].layers [0] == 255
  && clients [1].layers [1] == 255
  && clients [1].layers [2] == 255
  && clients [2].layers [0] == 255
  && clients [2].layers [1] == 255
  && clients [2].layers [2] == 255
  )
}
ltl consistency {
  eventually always (
     true
  && clients [0].model == server.model
  && clients [1].model == server.model
  && clients [2].model == server.model
  )
}
