#include "napi/native_api.h"
#include "clang_service.h"
#include <string>

namespace {

napi_value Make(napi_env env, const hm_clang::ClangResult &st)
{
    napi_value obj;
    napi_create_object(env, &obj);
    napi_value code, err, msg, data, ok;
    napi_create_int32(env, st.code, &code);
    napi_create_string_utf8(env, st.err.c_str(), NAPI_AUTO_LENGTH, &err);
    napi_create_string_utf8(env, st.message.c_str(), NAPI_AUTO_LENGTH, &msg);
    napi_create_string_utf8(env, st.data.c_str(), NAPI_AUTO_LENGTH, &data);
    napi_get_boolean(env, st.code == 0, &ok);
    napi_set_named_property(env, obj, "code", code);
    napi_set_named_property(env, obj, "err", err);
    napi_set_named_property(env, obj, "message", msg);
    napi_set_named_property(env, obj, "data", data);
    napi_set_named_property(env, obj, "ok", ok);
    return obj;
}

std::string Str(napi_env env, napi_value v)
{
    size_t len = 0;
    napi_get_value_string_utf8(env, v, nullptr, 0, &len);
    std::string s(len, '\0');
    size_t written = 0;
    napi_get_value_string_utf8(env, v, &s[0], len + 1, &written);
    s.resize(written);
    return s;
}

napi_value Available(napi_env env, napi_callback_info info)
{
    (void)info;
    return Make(env, hm_clang::ClangService::Instance().Available());
}

napi_value ParseFile(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    std::string path = argc >= 1 ? Str(env, args[0]) : "";
    std::string argsJson = argc >= 2 ? Str(env, args[1]) : "[]";
    return Make(env, hm_clang::ClangService::Instance().ParseFile(path, argsJson));
}

napi_value Diagnostics(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    std::string path = argc >= 1 ? Str(env, args[0]) : "";
    std::string argsJson = argc >= 2 ? Str(env, args[1]) : "[]";
    return Make(env, hm_clang::ClangService::Instance().Diagnostics(path, argsJson));
}

napi_value InitModule(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        {"available", nullptr, Available, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"parseFile", nullptr, ParseFile, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"diagnostics", nullptr, Diagnostics, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}

} // namespace

static napi_module hmClangModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = InitModule,
    .nm_modname = "hm_clang",
    .nm_priv = ((void *)0),
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterHmClangModule(void)
{
    napi_module_register(&hmClangModule);
}
