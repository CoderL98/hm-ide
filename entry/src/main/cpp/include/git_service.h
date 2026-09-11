#ifndef HM_IDE_GIT_SERVICE_H
#define HM_IDE_GIT_SERVICE_H

#include <string>
#include <vector>

#ifndef HM_HAS_LIBGIT2
#define HM_HAS_LIBGIT2 0
#endif

namespace hm_git {

struct GitResult {
  int code = 0;
  std::string err;
  std::string message;
  std::string data;
};

class GitService {
public:
  static GitService &Instance();

  GitResult Available();
  GitResult Init(const std::string &path);
  GitResult Open(const std::string &path);
  GitResult Close();
  GitResult Status();
  GitResult Add(const std::string &pathspec);
  GitResult Commit(const std::string &message, const std::string &authorName,
                   const std::string &authorEmail);
  GitResult Clone(const std::string &url, const std::string &path);
  GitResult Fetch(const std::string &remote);
  GitResult Pull(const std::string &remote, const std::string &branch);
  GitResult DiffSummary();
  GitResult CurrentBranch();

private:
  GitService() = default;
  std::string repoPath_;
  bool open_ = false;
  void *repo_ = nullptr; // git_repository* when HM_HAS_LIBGIT2
  GitResult NotBuilt(const char *op);
};

} // namespace hm_git

#endif
