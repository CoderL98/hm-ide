#ifndef HM_IDE_CLANG_SERVICE_H
#define HM_IDE_CLANG_SERVICE_H

#include <string>
#include <vector>

#ifndef HM_HAS_LIBCLANG
#define HM_HAS_LIBCLANG 0
#endif

namespace hm_clang {

struct ClangResult {
  int code = 0;
  std::string err;
  std::string message;
  std::string data; // JSON
};

class ClangService {
public:
  static ClangService &Instance();

  ClangResult Available();
  /** Parse file; returns diagnostics JSON array */
  ClangResult ParseFile(const std::string &path, const std::string &argsJson);
  ClangResult Diagnostics(const std::string &path, const std::string &argsJson);

private:
  ClangService() = default;
  ClangResult NotBuilt(const char *op);
};

} // namespace hm_clang

#endif
