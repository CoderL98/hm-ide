#ifndef HM_IDE_PTY_SESSION_H
#define HM_IDE_PTY_SESSION_H

#include <cstdint>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

namespace hm_pty {

enum class PtyErr : int {
    OK = 0,
    Perm = 1,      // EPERM / EACCES
    NoEnt = 2,     // ENOENT
    NoSys = 3,     // ENOSYS / ENOTSUP
    Inval = 4,     // EINVAL
    Io = 5,        // EIO
    Busy = 6,      // EBUSY
    Srch = 7,      // ESRCH
    Unknown = 99,
};

struct PtyStatus {
    PtyErr code = PtyErr::OK;
    std::string message;
    int sessionId = -1;
};

struct Session {
    int id = -1;
    int masterFd = -1;
    pid_t pid = -1;
    int cols = 80;
    int rows = 24;
    bool alive = false;
    std::mutex bufMu;
    std::string outBuf;
    std::thread reader;
    bool stopReader = false;
};

class PtySessionManager {
public:
    static PtySessionManager &Instance();

    /** Probe /dev/ptmx (and optional symbols). Does not fork. */
    PtyStatus Available();

    PtyStatus Start(int cols, int rows, const std::string &cwd, const std::string &shell);
    PtyStatus Write(int sessionId, const std::string &data);
    /** Drain buffered stdout/stderr (merged). Empty string if none. */
    PtyStatus Drain(int sessionId, std::string &out);
    PtyStatus Resize(int sessionId, int cols, int rows);
    PtyStatus Kill(int sessionId);

    static const char *ErrName(PtyErr e);

private:
    PtySessionManager() = default;
    ~PtySessionManager();
    PtySessionManager(const PtySessionManager &) = delete;
    PtySessionManager &operator=(const PtySessionManager &) = delete;

    int nextId_ = 1;
    std::mutex mapMu_;
    std::unordered_map<int, Session *> sessions_;

    PtyStatus OpenMaster(int &masterFd, std::string &slaveName);
    PtyStatus SpawnChild(int masterFd, const std::string &slaveName,
                         int cols, int rows, const std::string &cwd,
                         const std::string &shell, pid_t &outPid);
    void StartReader(Session *s);
    void StopAndErase(int sessionId);
    bool SetWinsize(int fd, int cols, int rows);
    static std::string ProbeShell(const std::string &preferred);
};

} // namespace hm_pty

#endif
