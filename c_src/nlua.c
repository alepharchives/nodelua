/**
Copyright (c) 2012 Benjamin Halsted <bhalsted@gmail.com>

Permission is hereby granted, free of charge, to any person obtaining a
copy of this software and associated documentation files (the"Software"),
to deal in the Software without restriction, including without limitation
the rights to use, copy, modify, merge, publish, distribute, sublicense,
and/or sell copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included
in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR
OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.
**/

#include "nl_util.h"
#include "state.h"

#include <erl_nif.h>
#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
#include <string.h>
#include <assert.h>

/* TODO List:

Since it is easier to lean on the websocket implementation in cowboy I have started
  using it for the sockets. The socket API should better reflect this, it should be
  able to handle paths and know more about the requests that come in.

Give the lua scripts the ability to set up a cowboy (erl) socket server and
  register a callback function.

Bind the erllua instance (think trap_exit) to the lua.erl instance.

Make redis available with the important bits non-configurable:
  https://github.com/wooga/eredis

Search for TODO @@@ and fix them!

If someone sends a message to a lua instance that has gone away, what should happen?

Send lua error results back to erlang

create a sandbox for running scripts in the main lua script
  http://lua-users.org/wiki/LuaModuleFunctionCritiqued

add the ability to 'require' other scripts in the sandbox

Experiment with using binaries to move socket data arround in lua in order 
  to translate faster. 
Experimest with using bson binaries in erlang and lua.

Interrupt threads that are taking too much time
  may need no move away from using erlang thread API and using posix threads
  pthread_t pthread_self(void)

socket reference:
  https://bitbucket.org/liamdevine/luasocket_ipv6_lua_51_52/src/538dcef303e2/src/socket_scripts.c
translation ref:
  https://github.com/davisp/emonk/blob/master/c_src/to_js.c
module ref:
  https://github.com/carvalho/numlua/blob/master/numlua.h
*/

// Prototypes
static ERL_NIF_TERM nlua_load_core(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]);
static ERL_NIF_TERM nlua_send_core(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]);

static ErlNifFunc nif_funcs[] =
{
    {"load_core", 2, nlua_load_core},
    {"send_core", 2, nlua_send_core}
};

// returns {ok, resource} or {error, {kind, message}}
static ERL_NIF_TERM nlua_load_core(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
  ERL_NIF_TERM result;

  if(2 != argc)
  {
    return enif_make_badarg(env);
  }

  const ERL_NIF_TERM script = argv[0];
  const ERL_NIF_TERM owner_term = argv[1];

  ErlNifPid owner_pid;
  if(!enif_get_local_pid( env, owner_term, &owner_pid))
  {
    return enif_make_badarg(env);
  }

  ErlNifBinary binary;

  if(enif_inspect_iolist_as_binary(env, script, &binary))
  {
    // allocate our lua type
    result = state_add_script(env, owner_pid, (const char *)binary.data, binary.size, "script");
  }
  else
  {
    result = enif_make_badarg(env);    
  }

  return result;
}

static ERL_NIF_TERM nlua_send_core(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[])
{
  ERL_NIF_TERM result;

  if(2 == argc)
  {
    const ERL_NIF_TERM resource = argv[0];
    const ERL_NIF_TERM message = argv[1];

    if(state_send_message(env, resource, message))
    {
      result = ATOM_OK;
    }
    else
    {
      result = make_error_tuple(env, ATOM_MEMORY, "could not allocate memory for sending message");
    }    
  }
  else
  {
    result = enif_make_badarg(env);
  }

  return result;
}

static int on_load(ErlNifEnv* env, void** priv_data, ERL_NIF_TERM load_info)
{
  nl_util_init_atoms(env);

  (*priv_data) = state_create(env);

  int processor_count;
  if(enif_get_int(env, load_info, &processor_count))
  {
    int count;
    for(count = 0; count < processor_count; ++count)
    {
      state_add_worker(env);
    }
  }
  else
  {
    state_add_worker(env);
  }

  return (NULL == *priv_data) ? 1 : 0;
}

static int on_upgrade(ErlNifEnv* env, void** priv_data, void** old_priv_data, ERL_NIF_TERM load_info)
{
  (void)env; // unused
  (void)load_info; // unused
  
  // we use the old private data as before
  *priv_data = *old_priv_data;
  return 0;
}


static void on_unload(ErlNifEnv* env, void* priv_data)
{
  (void) priv_data; // unused - the state type/data is hidden in env
  state_destroy(env);
}

ERL_NIF_INIT(nlua, nif_funcs, on_load, NULL, on_upgrade, on_unload);
