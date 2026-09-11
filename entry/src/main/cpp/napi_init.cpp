/**
 * NAPI bindings for libhm_pty.so
 * Exported: available, start, write, drain, resize, kill
 */
#include "napi/native_api.h"
#include "pty_session.h"

#include <string>

namespace {

napi_value MakeResult(napi_env env, const hm_pty::PtyStatus &st, const std::string *drainData = nullptr)
{
    napi_value obj;
    napi_create_object(env, &obj);

    napi_value code;
    napi_create_int32(env, static_cast<int32_t>(st.code), &code);
    napi_set_named_property(env, obj, "code", code);

    napi_value name;
    const char *n = hm_pty::PtySessionManager::ErrName(st.code);
    napi_create_string_utf8(env, n, NAPI_AUTO_LENGTH, &name);
    napi_set_named_property(env, obj, "err", name);

    napi_value msg;
    napi_create_string_utf8(env, st.message.c_str(), NAPI_AUTO_LENGTH, &msg);
    napi_set_named_property(env, obj, "message", msg);

    napi_value sid;
    napi_create_int32(env, st.sessionId, &sid);
    napi_set_named_property(env, obj, "sessionId", sid);

    napi_value ok;
    napi_get_boolean(env, st.code == hm_pty::PtyErr::OK, &ok);
    napi_set_named_property(env, obj, "ok", ok);

    if (drainData != nullptr) {
        napi_value data;
        napi_create_string_utf8(env, drainData->c_str(), drainData->size(), &data);
        napi_set_named_property(env, obj, "data", data);
    }
    return obj;
}

std::string GetStringArg(napi_env env, napi_value v)
{
    size_t len = 0;
    napi_get_value_string_utf8(env, v, nullptr, 0, &len);
    std::string s;
    s.resize(len);
    size_t written = 0;
    napi_get_value_string_utf8(env, v, &s[0], len + 1, &written);
    if (written < s.size()) {
        s.resize(written);
    }
    return s;
}

napi_value Available(napi_env env, napi_callback_info info)
{
    (void)info;
    auto st = hm_pty::PtySessionManager::Instance().Available();
    return MakeResult(env, st);
}

/**
 * start(cols?: number, rows?: number, cwd?: string, shell?: string)
 */
napi_value Start(napi_env env, napi_callback_info info)
{
    size_t argc = 4;
    napi_value args[4] = {nullptr, nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    int32_t cols = 80;
    int32_t rows = 24;
    std::string cwd;
    std::string shell;

    if (argc >= 1 && args[0] != nullptr) {
        napi_valuetype t;
        napi_typeof(env, args[0], &t);
        if (t == napi_number) {
            napi_get_value_int32(env, args[0], &cols);
        }
    }
    if (argc >= 2 && args[1] != nullptr) {
        napi_valuetype t;
        napi_typeof(env, args[1], &t);
        if (t == napi_number) {
            napi_get_value_int32(env, args[1], &rows);
        }
    }
    if (argc >= 3 && args[2] != nullptr) {
        napi_valuetype t;
        napi_typeof(env, args[2], &t);
        if (t == napi_string) {
            cwd = GetStringArg(env, args[2]);
        }
    }
    if (argc >= 4 && args[3] != nullptr) {
        napi_valuetype t;
        napi_typeof(env, args[3], &t);
        if (t == napi_string) {
            shell = GetStringArg(env, args[3]);
        }
    }

    auto st = hm_pty::PtySessionManager::Instance().Start(cols, rows, cwd, shell);
    return MakeResult(env, st);
}

/** write(sessionId, data) */
napi_value Write(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 2) {
        hm_pty::PtyStatus st;
        st.code = hm_pty::PtyErr::Inval;
        st.message = "write(sessionId, data) requires 2 args";
        return MakeResult(env, st);
    }
    int32_t sid = -1;
    napi_get_value_int32(env, args[0], &sid);
    std::string data = GetStringArg(env, args[1]);
    auto st = hm_pty::PtySessionManager::Instance().Write(sid, data);
    return MakeResult(env, st);
}

/** drain(sessionId) -> { ok, data, ... } */
napi_value Drain(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 1) {
        hm_pty::PtyStatus st;
        st.code = hm_pty::PtyErr::Inval;
        st.message = "drain(sessionId) requires 1 arg";
        return MakeResult(env, st);
    }
    int32_t sid = -1;
    napi_get_value_int32(env, args[0], &sid);
    std::string out;
    auto st = hm_pty::PtySessionManager::Instance().Drain(sid, out);
    return MakeResult(env, st, &out);
}

/** resize(sessionId, cols, rows) */
napi_value Resize(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value args[3] = {nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 3) {
        hm_pty::PtyStatus st;
        st.code = hm_pty::PtyErr::Inval;
        st.message = "resize(sessionId, cols, rows) requires 3 args";
        return MakeResult(env, st);
    }
    int32_t sid = -1;
    int32_t cols = 80;
    int32_t rows = 24;
    napi_get_value_int32(env, args[0], &sid);
    napi_get_value_int32(env, args[1], &cols);
    napi_get_value_int32(env, args[2], &rows);
    auto st = hm_pty::PtySessionManager::Instance().Resize(sid, cols, rows);
    return MakeResult(env, st);
}

/** kill(sessionId) */
napi_value Kill(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 1) {
        hm_pty::PtyStatus st;
        st.code = hm_pty::PtyErr::Inval;
        st.message = "kill(sessionId) requires 1 arg";
        return MakeResult(env, st);
    }
    int32_t sid = -1;
    napi_get_value_int32(env, args[0], &sid);
    auto st = hm_pty::PtySessionManager::Instance().Kill(sid);
    return MakeResult(env, st);
}

napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        {"available", nullptr, Available, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"start", nullptr, Start, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"write", nullptr, Write, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"drain", nullptr, Drain, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"resize", nullptr, Resize, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"kill", nullptr, Kill, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}

} // namespace

static napi_module hmPtyModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "hm_pty",
    .nm_priv = ((void *)0),
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterHmPtyModule(void)
{
    napi_module_register(&hmPtyModule);
}
