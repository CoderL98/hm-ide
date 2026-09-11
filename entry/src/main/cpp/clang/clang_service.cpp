#include "clang_service.h"

#if HM_HAS_LIBCLANG
#include <clang-c/Index.h>
#include <sstream>
#endif

namespace hm_clang {

ClangService &ClangService::Instance()
{
    static ClangService inst;
    return inst;
}

ClangResult ClangService::NotBuilt(const char *op)
{
    ClangResult r;
    r.code = 3;
    r.err = "ENOSYS";
    r.message = std::string(op) +
                ": libclang not linked. Build with -DLLVM_ROOT=<ohos-llvm-prefix>. "
                "See native/third_party/README.md (binary size warning).";
    r.data = "[]";
    return r;
}

ClangResult ClangService::Available()
{
    ClangResult r;
#if HM_HAS_LIBCLANG
    r.code = 0;
    r.err = "OK";
    r.message = "libclang linked";
    r.data = "{\"libclang\":true}";
#else
    r = NotBuilt("available");
    r.data = "{\"libclang\":false}";
#endif
    return r;
}

#if HM_HAS_LIBCLANG
static std::vector<std::string> ParseArgsJson(const std::string &argsJson)
{
    // Minimal: expect JSON array of strings like ["-std=c++17","-I/foo"] — naive split
    std::vector<std::string> out;
    std::string cur;
    bool inStr = false;
    for (size_t i = 0; i < argsJson.size(); ++i) {
        char c = argsJson[i];
        if (c == '"') {
            if (inStr) {
                out.push_back(cur);
                cur.clear();
                inStr = false;
            } else {
                inStr = true;
            }
            continue;
        }
        if (inStr) {
            if (c == '\\' && i + 1 < argsJson.size()) {
                cur.push_back(argsJson[++i]);
            } else {
                cur.push_back(c);
            }
        }
    }
    if (out.empty()) {
        out.push_back("-std=c++17");
        out.push_back("-Wall");
    }
    return out;
}
#endif

ClangResult ClangService::ParseFile(const std::string &path, const std::string &argsJson)
{
    return Diagnostics(path, argsJson);
}

ClangResult ClangService::Diagnostics(const std::string &path, const std::string &argsJson)
{
#if !HM_HAS_LIBCLANG
    (void)path;
    (void)argsJson;
    return NotBuilt("diagnostics");
#else
    ClangResult r;
    auto args = ParseArgsJson(argsJson);
    std::vector<const char *> cargs;
    for (auto &a : args) {
        cargs.push_back(a.c_str());
    }

    CXIndex index = clang_createIndex(0, 0);
    CXTranslationUnit tu = nullptr;
    CXErrorCode err = clang_parseTranslationUnit2(
        index, path.c_str(), cargs.data(), static_cast<int>(cargs.size()), nullptr, 0,
        CXTranslationUnit_None, &tu);
    if (err != CXError_Success || !tu) {
        clang_disposeIndex(index);
        r.code = 5;
        r.err = "EIO";
        r.message = "clang_parseTranslationUnit2 failed";
        r.data = "[]";
        return r;
    }

    unsigned n = clang_getNumDiagnostics(tu);
    std::string json = "[";
    for (unsigned i = 0; i < n; ++i) {
        CXDiagnostic diag = clang_getDiagnostic(tu, i);
        CXString spelling = clang_getDiagnosticSpelling(diag);
        CXSourceLocation loc = clang_getDiagnosticLocation(diag);
        CXFile file;
        unsigned line = 0, col = 0, offset = 0;
        clang_getSpellingLocation(loc, &file, &line, &col, &offset);
        CXString fname = clang_getFileName(file);
        enum CXDiagnosticSeverity sev = clang_getDiagnosticSeverity(diag);
        const char *sevStr = "info";
        if (sev == CXDiagnostic_Warning) {
            sevStr = "warning";
        } else if (sev == CXDiagnostic_Error || sev == CXDiagnostic_Fatal) {
            sevStr = "error";
        }
        if (i) {
            json += ",";
        }
        json += "{\"file\":\"";
        json += clang_getCString(fname) ? clang_getCString(fname) : path.c_str();
        json += "\",\"line\":";
        json += std::to_string(line);
        json += ",\"column\":";
        json += std::to_string(col);
        json += ",\"severity\":\"";
        json += sevStr;
        json += "\",\"message\":\"";
        const char *msg = clang_getCString(spelling);
        if (msg) {
            for (const char *p = msg; *p; ++p) {
                if (*p == '"' || *p == '\\') {
                    json.push_back('\\');
                }
                if (*p == '\n') {
                    json += "\\n";
                } else {
                    json.push_back(*p);
                }
            }
        }
        json += "\"}";
        clang_disposeString(spelling);
        clang_disposeString(fname);
        clang_disposeDiagnostic(diag);
    }
    json += "]";
    clang_disposeTranslationUnit(tu);
    clang_disposeIndex(index);
    r.code = 0;
    r.err = "OK";
    r.message = "diagnostics";
    r.data = json;
    return r;
#endif
}

} // namespace hm_clang
