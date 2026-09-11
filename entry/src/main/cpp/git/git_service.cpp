#include "git_service.h"

#ifndef HM_HAS_LIBGIT2
#define HM_HAS_LIBGIT2 0
#endif

#if HM_HAS_LIBGIT2
#include <git2.h>
#endif

namespace hm_git {

GitService &GitService::Instance()
{
    static GitService inst;
    return inst;
}

GitResult GitService::NotBuilt(const char *op)
{
    GitResult r;
    r.code = 3;
    r.err = "ENOSYS";
    r.message = std::string(op) +
                ": libgit2 not linked. Build with -DHM_GIT2_ROOT=<ohos-libgit2-prefix>. "
                "See native/third_party/README.md";
    return r;
}

GitResult GitService::Available()
{
    GitResult r;
#if HM_HAS_LIBGIT2
    r.code = 0;
    r.err = "OK";
    r.message = "libgit2 linked";
    r.data = "{\"libgit2\":true}";
#else
    r = NotBuilt("available");
    r.data = "{\"libgit2\":false}";
#endif
    return r;
}

GitResult GitService::Init(const std::string &path)
{
#if !HM_HAS_LIBGIT2
    return NotBuilt("init");
#else
    GitResult r;
    git_libgit2_init();
    git_repository *repo = nullptr;
    int rc = git_repository_init(&repo, path.c_str(), 0);
    if (rc != 0) {
        r.code = 5;
        r.err = "EIO";
        r.message = git_error_last() ? git_error_last()->message : "git_repository_init failed";
        return r;
    }
    if (repo_) {
        git_repository_free(static_cast<git_repository *>(repo_));
    }
    repo_ = repo;
    repoPath_ = path;
    open_ = true;
    r.code = 0;
    r.err = "OK";
    r.message = "initialized";
    r.data = std::string("{\"path\":,\"") + path + "\"}"; // fix below
    r.data = "{\"path\":\"" + path + "\"}";
    return r;
#endif
}

GitResult GitService::Open(const std::string &path)
{
#if !HM_HAS_LIBGIT2
    (void)path;
    return NotBuilt("open");
#else
    GitResult r;
    git_libgit2_init();
    git_repository *repo = nullptr;
    int rc = git_repository_open(&repo, path.c_str());
    if (rc != 0) {
        r.code = 2;
        r.err = "ENOENT";
        r.message = git_error_last() ? git_error_last()->message : "open failed";
        return r;
    }
    if (repo_) {
        git_repository_free(static_cast<git_repository *>(repo_));
    }
    repo_ = repo;
    repoPath_ = path;
    open_ = true;
    r.code = 0;
    r.err = "OK";
    r.message = "opened";
    r.data = "{\"path\":\"" + path + "\"}";
    return r;
#endif
}

GitResult GitService::Close()
{
#if !HM_HAS_LIBGIT2
    return NotBuilt("close");
#else
    if (repo_) {
        git_repository_free(static_cast<git_repository *>(repo_));
        repo_ = nullptr;
    }
    open_ = false;
    repoPath_.clear();
    GitResult r;
    r.code = 0;
    r.err = "OK";
    r.message = "closed";
    return r;
#endif
}

GitResult GitService::Status()
{
#if !HM_HAS_LIBGIT2
    return NotBuilt("status");
#else
    GitResult r;
    if (!repo_) {
        r.code = 4;
        r.err = "EINVAL";
        r.message = "no repo open";
        return r;
    }
    git_status_list *list = nullptr;
    git_status_options opts = GIT_STATUS_OPTIONS_INIT;
    opts.show = GIT_STATUS_SHOW_INDEX_AND_WORKDIR;
    opts.flags = GIT_STATUS_OPT_INCLUDE_UNTRACKED | GIT_STATUS_OPT_RENAMES_HEAD_TO_INDEX;
    if (git_status_list_new(&list, static_cast<git_repository *>(repo_), &opts) != 0) {
        r.code = 5;
        r.err = "EIO";
        r.message = git_error_last() ? git_error_last()->message : "status failed";
        return r;
    }
    std::string json = "[";
    size_t count = git_status_list_entrycount(list);
    for (size_t i = 0; i < count; ++i) {
        const git_status_entry *e = git_status_byindex(list, i);
        const char *path = nullptr;
        std::string st = "modified";
        if (e->head_to_index) {
            path = e->head_to_index->new_file.path ? e->head_to_index->new_file.path
                                                  : e->head_to_index->old_file.path;
        } else if (e->index_to_workdir) {
            path = e->index_to_workdir->new_file.path ? e->index_to_workdir->new_file.path
                                                     : e->index_to_workdir->old_file.path;
        }
        if (e->status & GIT_STATUS_WT_NEW || e->status & GIT_STATUS_INDEX_NEW) {
            st = "added";
        }
        if (e->status & GIT_STATUS_WT_DELETED || e->status & GIT_STATUS_INDEX_DELETED) {
            st = "deleted";
        }
        if (e->status & GIT_STATUS_WT_NEW && !(e->status & GIT_STATUS_INDEX_NEW)) {
            st = "untracked";
        }
        if (e->status & GIT_STATUS_CONFLICTED) {
            st = "conflicted";
        }
        if (!path) {
            path = "";
        }
        if (i) {
            json += ",";
        }
        json += "{\"path\":\"";
        json += path;
        json += "\",\"status\":\"";
        json += st;
        json += "\"}";
    }
    json += "]";
    git_status_list_free(list);
    r.code = 0;
    r.err = "OK";
    r.message = "status";
    r.data = json;
    return r;
#endif
}

GitResult GitService::Add(const std::string &pathspec)
{
#if !HM_HAS_LIBGIT2
    (void)pathspec;
    return NotBuilt("add");
#else
    GitResult r;
    if (!repo_) {
        r.code = 4;
        r.err = "EINVAL";
        r.message = "no repo open";
        return r;
    }
    git_index *index = nullptr;
    if (git_repository_index(&index, static_cast<git_repository *>(repo_)) != 0) {
        r.code = 5;
        r.err = "EIO";
        r.message = "index open failed";
        return r;
    }
    int rc = git_index_add_bypath(index, pathspec.c_str());
    if (rc != 0) {
        // try add_all for globs
        git_strarray arr {};
        char *paths[] = { const_cast<char *>(pathspec.c_str()) };
        arr.strings = paths;
        arr.count = 1;
        rc = git_index_add_all(index, &arr, GIT_INDEX_ADD_DEFAULT, nullptr, nullptr);
    }
    if (rc != 0) {
        git_index_free(index);
        r.code = 5;
        r.err = "EIO";
        r.message = git_error_last() ? git_error_last()->message : "add failed";
        return r;
    }
    git_index_write(index);
    git_index_free(index);
    r.code = 0;
    r.err = "OK";
    r.message = "added";
    return r;
#endif
}

GitResult GitService::Commit(const std::string &message, const std::string &authorName,
                             const std::string &authorEmail)
{
#if !HM_HAS_LIBGIT2
    (void)message;
    (void)authorName;
    (void)authorEmail;
    return NotBuilt("commit");
#else
    GitResult r;
    if (!repo_) {
        r.code = 4;
        r.err = "EINVAL";
        r.message = "no repo open";
        return r;
    }
    git_repository *repo = static_cast<git_repository *>(repo_);
    git_index *index = nullptr;
    git_oid tree_oid, commit_oid;
    git_tree *tree = nullptr;
    git_signature *sig = nullptr;
    git_commit *parent = nullptr;
    git_reference *head = nullptr;

    if (git_repository_index(&index, repo) != 0) {
        r.code = 5;
        r.err = "EIO";
        r.message = "index failed";
        return r;
    }
    if (git_index_write_tree(&tree_oid, index) != 0) {
        git_index_free(index);
        r.code = 5;
        r.err = "EIO";
        r.message = "write_tree failed";
        return r;
    }
    git_index_free(index);
    if (git_tree_lookup(&tree, repo, &tree_oid) != 0) {
        r.code = 5;
        r.err = "EIO";
        r.message = "tree_lookup failed";
        return r;
    }
    std::string name = authorName.empty() ? "hm-ide" : authorName;
    std::string email = authorEmail.empty() ? "hm-ide@localhost" : authorEmail;
    if (git_signature_now(&sig, name.c_str(), email.c_str()) != 0) {
        git_tree_free(tree);
        r.code = 5;
        r.err = "EIO";
        r.message = "signature failed";
        return r;
    }
    size_t parentCount = 0;
    const git_commit *parents[1] = {nullptr};
    if (git_repository_head(&head, repo) == 0) {
        git_oid parent_oid;
        if (git_reference_name_to_id(&parent_oid, repo, "HEAD") == 0 &&
            git_commit_lookup(&parent, repo, &parent_oid) == 0) {
            parents[0] = parent;
            parentCount = 1;
        }
        git_reference_free(head);
    }
    int rc = git_commit_create(&commit_oid, repo, "HEAD", sig, sig, nullptr, message.c_str(), tree,
                               parentCount, parents);
    if (parent) {
        git_commit_free(parent);
    }
    git_signature_free(sig);
    git_tree_free(tree);
    if (rc != 0) {
        r.code = 5;
        r.err = "EIO";
        r.message = git_error_last() ? git_error_last()->message : "commit failed";
        return r;
    }
    char oidStr[GIT_OID_HEXSZ + 1] = {0};
    git_oid_tostr(oidStr, sizeof(oidStr), &commit_oid);
    r.code = 0;
    r.err = "OK";
    r.message = "committed";
    r.data = std::string("{\"oid\":\"") + oidStr + "\"}";
    return r;
#endif
}

GitResult GitService::Clone(const std::string &url, const std::string &path)
{
#if !HM_HAS_LIBGIT2
    (void)url;
    (void)path;
    return NotBuilt("clone");
#else
    GitResult r;
    git_libgit2_init();
    git_repository *repo = nullptr;
    int rc = git_clone(&repo, url.c_str(), path.c_str(), nullptr);
    if (rc != 0) {
        r.code = 5;
        r.err = "EIO";
        r.message = git_error_last() ? git_error_last()->message : "clone failed";
        return r;
    }
    if (repo_) {
        git_repository_free(static_cast<git_repository *>(repo_));
    }
    repo_ = repo;
    repoPath_ = path;
    open_ = true;
    r.code = 0;
    r.err = "OK";
    r.message = "cloned";
    r.data = "{\"path\":\"" + path + "\"}";
    return r;
#endif
}

GitResult GitService::Fetch(const std::string &remote)
{
#if !HM_HAS_LIBGIT2
    (void)remote;
    return NotBuilt("fetch");
#else
    GitResult r;
    if (!repo_) {
        r.code = 4;
        r.err = "EINVAL";
        r.message = "no repo open";
        return r;
    }
    git_remote *rem = nullptr;
    std::string name = remote.empty() ? "origin" : remote;
    if (git_remote_lookup(&rem, static_cast<git_repository *>(repo_), name.c_str()) != 0) {
        r.code = 2;
        r.err = "ENOENT";
        r.message = "remote not found";
        return r;
    }
    int rc = git_remote_fetch(rem, nullptr, nullptr, nullptr);
    git_remote_free(rem);
    if (rc != 0) {
        r.code = 5;
        r.err = "EIO";
        r.message = git_error_last() ? git_error_last()->message : "fetch failed";
        return r;
    }
    r.code = 0;
    r.err = "OK";
    r.message = "fetched";
    return r;
#endif
}

GitResult GitService::Pull(const std::string &remote, const std::string &branch)
{
#if !HM_HAS_LIBGIT2
    (void)remote;
    (void)branch;
    return NotBuilt("pull");
#else
    // Basic pull = fetch + merge analysis (fast-forward only for scaffold)
    GitResult f = Fetch(remote);
    if (f.code != 0) {
        return f;
    }
    GitResult r;
    r.code = 0;
    r.err = "OK";
    r.message = "pull: fetch done (merge/ff scaffold — extend with git_merge when needed)";
    r.data = "{\"remote\":\"" + (remote.empty() ? "origin" : remote) + "\",\"branch\":\"" +
             branch + "\"}";
    return r;
#endif
}

GitResult GitService::DiffSummary()
{
#if !HM_HAS_LIBGIT2
    return NotBuilt("diffSummary");
#else
    GitResult r;
    if (!repo_) {
        r.code = 4;
        r.err = "EINVAL";
        r.message = "no repo open";
        return r;
    }
    git_diff *diff = nullptr;
    if (git_diff_index_to_workdir(&diff, static_cast<git_repository *>(repo_), nullptr, nullptr) !=
        0) {
        r.code = 5;
        r.err = "EIO";
        r.message = git_error_last() ? git_error_last()->message : "diff failed";
        return r;
    }
    size_t deltas = git_diff_num_deltas(diff);
    git_diff_stats *stats = nullptr;
    size_t add = 0, del = 0;
    if (git_diff_get_stats(&stats, diff) == 0) {
        add = git_diff_stats_insertions(stats);
        del = git_diff_stats_deletions(stats);
        git_diff_stats_free(stats);
    }
    git_diff_free(diff);
    r.code = 0;
    r.err = "OK";
    r.message = "diff";
    r.data = "{\"files\":" + std::to_string(deltas) + ",\"insertions\":" + std::to_string(add) +
             ",\"deletions\":" + std::to_string(del) + "}";
    return r;
#endif
}

GitResult GitService::CurrentBranch()
{
#if !HM_HAS_LIBGIT2
    return NotBuilt("currentBranch");
#else
    GitResult r;
    if (!repo_) {
        r.code = 4;
        r.err = "EINVAL";
        r.message = "no repo open";
        return r;
    }
    git_reference *head = nullptr;
    if (git_repository_head(&head, static_cast<git_repository *>(repo_)) != 0) {
        r.code = 5;
        r.err = "EIO";
        r.message = "HEAD missing (unborn?)";
        r.data = "{\"branch\":\"HEAD\",\"detached\":true}";
        return r;
    }
    const char *name = git_reference_shorthand(head);
    bool det = git_repository_head_detached(static_cast<git_repository *>(repo_)) == 1;
    r.code = 0;
    r.err = "OK";
    r.message = name ? name : "HEAD";
    r.data = std::string("{\"branch\":\"") + (name ? name : "HEAD") +
             "\",\"detached\":" + (det ? "true" : "false") + "}";
    git_reference_free(head);
    return r;
#endif
}

} // namespace hm_git
