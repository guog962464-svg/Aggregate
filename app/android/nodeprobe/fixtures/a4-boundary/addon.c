#include <node_api.h>

static napi_value get_napi_version(napi_env env, napi_callback_info info) {
  uint32_t version = 0;
  napi_value result;
  if (napi_get_version(env, &version) != napi_ok ||
      napi_create_uint32(env, version, &result) != napi_ok) {
    return NULL;
  }
  return result;
}

static napi_value initialize(napi_env env, napi_value exports) {
  napi_value function;
  if (napi_create_function(env, "getNapiVersion", NAPI_AUTO_LENGTH,
                           get_napi_version, NULL, &function) != napi_ok ||
      napi_set_named_property(env, exports, "getNapiVersion", function) != napi_ok) {
    return NULL;
  }
  return exports;
}

NAPI_MODULE(a4_boundary_addon, initialize)
