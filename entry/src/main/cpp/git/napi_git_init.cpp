#include "napi/native_api.h"
#include "git_service.h"
#include <string>

namespace {

napi_value Make(napi_env env, const hm_git::GitResult &st)
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
    return Make(env, hm_git::GitService::Instance().Available());
}

napi_value InitRepo(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    std::string path = argc >= 1 ? Str(env, args[0]) : "";
    return Make(env, hm_git::GitService::Instance().Init(path));
}

napi_value Open(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    return Make(env, hm_git::GitService::Instance().Open(argc >= 1 ? Str(env, args[0]) : ""));
}

napi_value Close(napi_env env, napi_callback_info info)
{
    (void)info;
    return Make(env, hm_git::GitService::Instance().Close());
}

napi_value Status(napi_env env, napi_callback_info info)
{
    (void)info;
    return Make(env, hm_git::GitService::Instance().Status());
}

napi_value Add(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    return Make(env, hm_git::GitService::Instance().Add(argc >= 1 ? Str(env, args[0]) : ""));
}

napi_value Commit(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value args[3] = {nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    std::string msg = argc >= 1 ? Str(env, args[0]) : "";
    std::string name = argc >= 2 ? Str(env, args[1]) : "";
    std::string email = argc >= 3 ? Str(env, args[2]) : "";
    return Make(env, hm_git::GitService::Instance().Commit(msg, name, email));
}

napi_value Clone(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    return Make(env, hm_git::GitService::Instance().Clone(
                         argc >= 1 ? Str(env, args[0]) : "", argc >= 2 ? Str(env, args[1]) : ""));
}

napi_value Fetch(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    return Make(env, hm_git::GitService::Instance().Fetch(argc >= 1 ? Str(env, args[0]) : "origin"));
}

napi_value Pull(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    return Make(env, hm_git::GitService::Instance().Pull(
                         argc >= 1 ? Str(env, args[0]) : "origin",
                         argc >= 2 ? Str(env, args[1]) : ""));
}

napi_value DiffSummary(napi_env env, napi_callback_info info)
{
    (void)info;
    return Make(env, hm_git::GitService::Instance().DiffSummary());
}

napi_value CurrentBranch(napi_env env, napi_callback_info info)
{
    (void)info;
    return Make(env, hm_git::GitService::Instance().CurrentBranch());
}

napi_value InitModule(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        {"available", nullptr, Available, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"init", nullptr, InitRepo, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"open", nullptr, Open, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"close", nullptr, Close, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"status", nullptr, Status, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"add", nullptr, Add, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"commit", nullptr, Commit, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"clone", nullptr, Clone, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"fetch", nullptr, Fetch, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"pull", nullptr, Pull, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"diffSummary", nullptr, DiffSummary, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"currentBranch", nullptr, CurrentBranch, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}

} // namespace

static napi_module hmGitModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = InitModule,
    .nm_modname = "hm_git",
    .nm_priv = ((void *)0),
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterHmGitModule(void)
{
    napi_module_register(&hmGitModule);
}
