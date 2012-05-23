#ifndef NODELUA_STATE
#define NODELUA_STATE

#include <erl_nif.h>

typedef struct state_work* state_work_ptr;

void* state_create(ErlNifEnv* env);
void state_destroy(ErlNifEnv* env);

int state_add_worker(ErlNifEnv* env);

ERL_NIF_TERM state_add_script(ErlNifEnv* env, const char * data, size_t size, const char * name);
int state_send_message(ErlNifEnv* env, ERL_NIF_TERM resource_term, ERL_NIF_TERM message);

ERL_NIF_TERM state_make_resource(ErlNifEnv* env, void** resource, ErlNifResourceType* resource_type, state_work_ptr data);
int state_work_addref(state_work_ptr state_work);
int state_work_decref(state_work_ptr state_work);

#endif