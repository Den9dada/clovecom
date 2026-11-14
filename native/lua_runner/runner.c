/* 应用私有 Lua 工作进程：内存预算和不可变二进制值由原生层提供。 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#ifdef _WIN32
#include <io.h>
#include <fcntl.h>
#include <wchar.h>
#endif
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

typedef struct { size_t used, limit; } MemoryBudget;
typedef struct { size_t length; unsigned char data[1]; } Bytes;
static const char *BYTES_TYPE = "clovertls.Bytes";

static void *budget_alloc(void *ud, void *ptr, size_t old_size, size_t size) {
  MemoryBudget *budget = (MemoryBudget *)ud;
  if (!ptr) old_size = 0;
  if (!size) {
    budget->used -= old_size;
    free(ptr);
    return NULL;
  }
  if (size > budget->limit || budget->used - old_size > budget->limit - size)
    return NULL;
  void *result = realloc(ptr, size);
  if (result) budget->used = budget->used - old_size + size;
  return result;
}

static Bytes *check_bytes(lua_State *L, int index) {
  return (Bytes *)luaL_checkudata(L, index, BYTES_TYPE);
}

static int bytes_new(lua_State *L) {
  size_t length;
  const char *data = luaL_checklstring(L, 1, &length);
  if (length > 1024 * 1024) return luaL_error(L, "单个 Bytes 超过 1 MiB 上限");
  Bytes *value = (Bytes *)lua_newuserdatauv(L, sizeof(Bytes) + length, 0);
  value->length = length;
  memcpy(value->data, data, length);
  luaL_setmetatable(L, BYTES_TYPE);
  return 1;
}

static int bytes_raw(lua_State *L) {
  Bytes *value = check_bytes(L, 1);
  lua_pushlstring(L, (const char *)value->data, value->length);
  return 1;
}

static int bytes_is(lua_State *L) {
  lua_pushboolean(L, luaL_testudata(L, 1, BYTES_TYPE) != NULL);
  return 1;
}

static int bytes_len(lua_State *L) {
  lua_pushinteger(L, (lua_Integer)check_bytes(L, 1)->length);
  return 1;
}

static int bytes_tostring(lua_State *L) {
  lua_pushfstring(L, "Bytes(%I)", (lua_Integer)check_bytes(L, 1)->length);
  return 1;
}

static int bytes_methods(lua_State *L) {
  luaL_checktype(L, 1, LUA_TTABLE);
  luaL_getmetatable(L, BYTES_TYPE);
  lua_pushvalue(L, 1);
  lua_setfield(L, -2, "__index");
  return 0;
}

static int run_sdk(FILE *file, int check_only) {
  MemoryBudget budget = {0, 128 * 1024 * 1024};
  lua_State *L = lua_newstate(budget_alloc, &budget);
  if (!L) return 2;
  luaL_openlibs(L);
  luaL_newmetatable(L, BYTES_TYPE);
  lua_pushcfunction(L, bytes_len); lua_setfield(L, -2, "__len");
  lua_pushcfunction(L, bytes_tostring); lua_setfield(L, -2, "__tostring");
  lua_pushliteral(L, "Bytes"); lua_setfield(L, -2, "__metatable");
  lua_pop(L, 1);
  lua_pushcfunction(L, bytes_new); lua_setglobal(L, "__host_bytes_new");
  lua_pushcfunction(L, bytes_raw); lua_setglobal(L, "__host_bytes_raw");
  lua_pushcfunction(L, bytes_is); lua_setglobal(L, "__host_bytes_is");
  lua_pushcfunction(L, bytes_methods); lua_setglobal(L, "__host_bytes_methods");
  lua_pushboolean(L, check_only); lua_setglobal(L, "__host_check_only");
  fseek(file, 0, SEEK_END);
  long length = ftell(file);
  rewind(file);
  if (length < 0 || length > 2 * 1024 * 1024) { lua_close(L); return 2; }
  char *source = (char *)malloc((size_t)length + 1);
  if (!source) { lua_close(L); return 2; }
  size_t read = fread(source, 1, (size_t)length, file);
  int status = luaL_loadbufferx(L, source, read, "@host_sdk.lua", "t");
  free(source);
  if (status == LUA_OK) status = lua_pcall(L, 0, 0, 0);
  if (status != LUA_OK) fprintf(stderr, "%s\n", lua_tostring(L, -1));
  lua_close(L);
  return status == LUA_OK ? 0 : 1;
}

#ifdef _WIN32
int wmain(int argc, wchar_t **argv) {
  if (argc < 2) return 2;
  _setmode(_fileno(stdin), _O_BINARY);
  _setmode(_fileno(stdout), _O_BINARY);
  FILE *file = _wfopen(argv[1], L"rb");
  if (!file) return 2;
  int result = run_sdk(file, argc > 2 && wcscmp(argv[2], L"--check") == 0);
  fclose(file);
  return result;
}
#else
int main(int argc, char **argv) {
  if (argc < 2) return 2;
  FILE *file = fopen(argv[1], "rb");
  if (!file) return 2;
  int result = run_sdk(file, argc > 2 && strcmp(argv[2], "--check") == 0);
  fclose(file);
  return result;
}
#endif
