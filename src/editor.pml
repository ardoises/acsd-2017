#define CLIENTS 2
#define PATCHES 2

typedef Client {
  chan queue    = [2 * CLIENTS * PATCHES] of { bool, bool, byte, byte }; // connection, success, origin, patch | model
  byte model    = 255;
  byte patch_id = 0;
  byte layers  [PATCHES] = 255;
  byte patches [PATCHES] = 0;
}

typedef Server {
  chan queue = [2 * CLIENTS * PATCHES] of { bool, bool, byte, byte }; // connection, success, origin, patch
  bool clients [CLIENTS] = false;
  byte model = 0;
}

Server server;
Client clients [CLIENTS];

proctype server_loop () {
  byte origin, patch;
  do
  :: atomic { // connect
       server.queue ? true, false, origin, patch ->
       server.clients [origin] = true;
       clients [origin].queue ! true, true, origin, server.model;
     }
  :: atomic { // invalid patch
       server.queue ? false, false, origin, patch ->
       clients [origin].queue ! false, false, origin, patch;
     }
  :: atomic { // valid patch
       server.queue ? false, false, origin, patch ->
       server.model = patch;
       byte id = 0;
       do
       :: id < CLIENTS ->
          if
          :: server.clients [id] == true ->
             clients [id].queue ! false, true, origin, patch;
          :: server.clients [id] == false;
          fi;
          id++;
       :: id >= CLIENTS ->
          break;
       od;
     }
  od
}

proctype client_loop (byte id) {
  byte origin, patch;
  do
  :: atomic { // connect
       clients [id].queue ? true, true, id, patch ->
       clients [id].model = patch;
     }
  :: atomic { // invalid patch
       clients [id].queue ? false, false, id, patch ->
       clients [id].layers [clients [id].patch_id] = 255;
       clients [id].patch_id++;
     }
  :: atomic { // valid patch
       clients [id].queue ? false, true, origin, patch ->
       if
       :: origin != id ->
          clients [id].model = patch;
       :: origin == id ->
          clients [id].model = patch;
          clients [id].layers [clients [id].patch_id] = 255;
          clients [id].patch_id++;
       fi
     }
  od;
}

proctype patch_client (byte id) {
  byte patch = 0;
  run client_loop (id);
  server.queue ! true, false, id, 255;
  do
  :: atomic {
       patch < PATCHES ->
       byte p_id    = clients [id].patch_id;
       byte p_value = clients [id].patches [patch];
       clients [id].layers [p_id] = p_value;
       server.queue ! false, false, id, p_value;
       patch++;
     }
  :: atomic {
       patch < PATCHES ->
       patch++;
     }
  :: atomic {
       patch >= PATCHES ->
       break;
     }
  od;
}

init {
  run server_loop ();
  byte id    = 0;
  byte value = 1;
  do
  :: id < CLIENTS ->
     atomic {
       byte j = 0
       do
       :: j < PATCHES ->
          clients [id].layers  [j] = 255;
          clients [id].patches [j] = value;
          value++;
          j++;
       :: j >= PATCHES ->
          break;
       od;
       run patch_client (id);
       id++;
     }
  :: id >= CLIENTS ->
     break;
  od
}

ltl empty_layers {
  eventually always (
     true
  && clients [0].layers [0] == 255
  && clients [0].layers [1] == 255
  /*&& clients [0].layers [2] == 255*/
  && clients [1].layers [0] == 255
  && clients [1].layers [1] == 255
  /*&& clients [1].layers [2] == 255*/
  )
}

ltl consistency {
  eventually always (
     true
  && clients [0].model == server.model
  && clients [1].model == server.model
  )
}
