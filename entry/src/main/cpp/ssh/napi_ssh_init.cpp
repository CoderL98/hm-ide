/**
 * libhm_ssh.so — SSH auto-deploy NAPI surface for Scheme B.
 *
 * Full API is exported for ArkTS SshDeployService. On-device linking of libssh/libssh2
 * against OHOS NDK is not available in this tree by default → ENOSYS.
 * Host path: tools/hm-ssh-helper + tools/ssh-deploy-agent.sh
 *
 * When HM_HAS_LIBSSH2=1 and third_party/libssh2 is linked, implementations below
 * can be filled; until then every mutating call returns ENOSYS with step hints.
 */
#include <napi/native_api.h>
#include <string>

static napi_value MakeResult(napi_env env, bool ok, const char *code, const char *message) {
    napi_value obj;
    napi_create_object(env, &obj);
    napi_value v_ok, v_code, v_msg;
    napi_get_boolean(env, ok, &v_ok);
    napi_create_string_utf8(env, code, NAPI_AUTO_LENGTH, &v_code);
    napi_create_string_utf8(env, message, NAPI_AUTO_LENGTH, &v_msg);
    napi_set_named_property(env, obj, "ok", v_ok);
    napi_set_named_property(env, obj, "code", v_code);
    napi_set_named_property(env, obj, "message", v_msg);
    return obj;
}

static napi_value MakeResultExtra(napi_env env, bool ok, const char *code, const char *message,
                                  const char *extraKey, const char *extraVal) {
    napi_value obj = MakeResult(env, ok, code, message);
    if (extraKey && extraVal) {
        napi_value v;
        napi_create_string_utf8(env, extraVal, NAPI_AUTO_LENGTH, &v);
        napi_set_named_property(env, obj, extraKey, v);
    }
    return obj;
}

#if defined(HM_HAS_LIBSSH2) && HM_HAS_LIBSSH2
// Placeholder for real libssh2 integration (see entry/src/main/cpp/third_party/README.md)
#endif

static napi_value Available(napi_env env, napi_callback_info info) {
    (void)info;
#if defined(HM_HAS_LIBSSH2) && HM_HAS_LIBSSH2
    return MakeResult(env, true, "OK", "libssh2 linked");
#else
    return MakeResult(env, false, "ENOSYS",
        "hm_ssh: on-device libssh2 not linked. Use host tools/hm-ssh-helper or tools/ssh-deploy-agent.sh");
#endif
}

/** detectRemoteArch(host, port, user, authMode, key, password) */
static napi_value DetectRemoteArch(napi_env env, napi_callback_info info) {
    (void)info;
    return MakeResultExtra(env, false, "ENOSYS",
        "detectRemoteArch stub — host: ssh user@host uname -m", "arch", "");
}

/** uploadAgent(localBinary, host, port, user, authMode, key, password, agentPort) */
static napi_value UploadAgent(napi_env env, napi_callback_info info) {
    (void)info;
    return MakeResult(env, false, "ENOSYS",
        "uploadAgent stub — scp agent/dist/hm-ide-agent-*-linux → ~/.hm-ide-agent/bin/hm-ide-agent");
}

/** installAndStart(host, port, user, authMode, key, password, agentPort, token) */
static napi_value InstallAndStart(napi_env env, napi_callback_info info) {
    (void)info;
    return MakeResult(env, false, "ENOSYS",
        "installAndStart stub — remote: chmod +x; nohup hm-ide-agent --port P --token T");
}

/** localForward(host, port, user, authMode, key, password, agentPort) */
static napi_value LocalForward(napi_env env, napi_callback_info info) {
    (void)info;
    return MakeResult(env, false, "ENOSYS",
        "localForward stub — ssh -N -L 127.0.0.1:P:127.0.0.1:P");
}

/** replaceAndRestart(...) — version mismatch path */
static napi_value ReplaceAndRestart(napi_env env, napi_callback_info info) {
    (void)info;
    return MakeResult(env, false, "ENOSYS",
        "replaceAndRestart stub — upload .new, mv, pkill, nohup; or agent.upgrade RPC");
}

/** deployAll(...) — full pipeline: detect→upload→start→forward */
static napi_value DeployAll(napi_env env, napi_callback_info info) {
    (void)info;
    return MakeResult(env, false, "ENOSYS",
        "deployAll stub — run tools/ssh-deploy-agent.sh or hm-ssh-helper deploy");
}

/** hostHelperHint(host, port, user, remotePath, agentPort) → message with command */
static napi_value HostHelperHint(napi_env env, napi_callback_info info) {
    (void)info;
    return MakeResult(env, true, "HINT",
        "tools/ssh-deploy-agent.sh -h HOST -u USER -r REMOTE -a PORT");
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"available", nullptr, Available, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"detectRemoteArch", nullptr, DetectRemoteArch, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"uploadAgent", nullptr, UploadAgent, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"installAndStart", nullptr, InstallAndStart, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"localForward", nullptr, LocalForward, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"replaceAndRestart", nullptr, ReplaceAndRestart, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"deployAll", nullptr, DeployAll, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"hostHelperHint", nullptr, HostHelperHint, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module hm_ssh_module = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "hm_ssh",
    .nm_priv = ((void *)0),
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterHmSshModule(void) {
    napi_module_register(&hm_ssh_module);
}
