/**
 * Local PTY session manager for HarmonyOS NEXT (NAPI).
 * Primary path: posix_openpt / /dev/ptmx + grantpt/unlockpt + fork + setsid +
 * TIOCSCTTY + dup2 + exec sh. Optional forkpty/openpty when headers+libutil exist.
 * On device, SELinux / sandbox often blocks /dev/ptmx for third-party apps;
 * Available()/Start() surface EPERM / ENOSYS so UI can fall back to sandbox shell.
 */
#include "pty_session.h"

#include <cerrno>
#include <cstring>
#include <fcntl.h>
#include <signal.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>

#if defined(__has_include)
#  if __has_include(<pty.h>)
#    include <pty.h>
#    define HM_HAS_PTY_H 1
#  endif
#  if __has_include(<util.h>)
#    include <util.h>
#    define HM_HAS_UTIL_H 1
#  endif
#endif

#ifndef HM_HAS_PTY_H
#  define HM_HAS_PTY_H 0
#endif
#ifndef HM_HAS_UTIL_H
#  define HM_HAS_UTIL_H 0
#endif

/* Only call openpty when both header and CMake-linked libutil are present */
#if (HM_HAS_PTY_H || HM_HAS_UTIL_H) && defined(HM_LINK_LIBUTIL)
#  define HM_TRY_OPENPTY 1
#else
#  define HM_TRY_OPENPTY 0
#endif

namespace hm_pty {

namespace {

bool PathExists(const char *path)
{
    struct stat st {};
    return ::stat(path, &st) == 0;
}

void ChildExecShell(const std::string &shell, const std::string &cwd)
{
    if (!cwd.empty()) {
        (void)::chdir(cwd.c_str());
    }
    setenv("TERM", "xterm-256color", 1);
    setenv("COLORTERM", "truecolor", 1);
    const char *sh = shell.c_str();
    execl(sh, sh, static_cast<char *>(nullptr));
    execl("/system/bin/sh", "sh", static_cast<char *>(nullptr));
    execl("/bin/sh", "sh", static_cast<char *>(nullptr));
    execl("/system/bin/bash", "bash", static_cast<char *>(nullptr));
    _exit(127);
}

PtyErr ErrnoToPty(int e)
{
    switch (e) {
        case EPERM:
        case EACCES:
            return PtyErr::Perm;
        case ENOENT:
            return PtyErr::NoEnt;
        case ENOSYS:
#if defined(ENOTSUP)
        case ENOTSUP:
#endif
#if defined(EOPNOTSUPP) && (!defined(ENOTSUP) || EOPNOTSUPP != ENOTSUP)
        case EOPNOTSUPP:
#endif
            return PtyErr::NoSys;
        case EINVAL:
            return PtyErr::Inval;
        case EIO:
            return PtyErr::Io;
        case EBUSY:
            return PtyErr::Busy;
        default:
            return PtyErr::Unknown;
    }
}

std::string ErrMsg(const char *prefix, int e)
{
    std::string m(prefix);
    m += ": ";
    m += std::strerror(e);
    m += " (";
    m += std::to_string(e);
    m += ")";
    return m;
}

} // namespace

PtySessionManager &PtySessionManager::Instance()
{
    static PtySessionManager inst;
    return inst;
}

PtySessionManager::~PtySessionManager()
{
    std::vector<int> ids;
    {
        std::lock_guard<std::mutex> lock(mapMu_);
        for (auto &kv : sessions_) {
            ids.push_back(kv.first);
        }
    }
    for (int id : ids) {
        (void)Kill(id);
    }
}

const char *PtySessionManager::ErrName(PtyErr e)
{
    switch (e) {
        case PtyErr::OK:
            return "OK";
        case PtyErr::Perm:
            return "EPERM";
        case PtyErr::NoEnt:
            return "ENOENT";
        case PtyErr::NoSys:
            return "ENOSYS";
        case PtyErr::Inval:
            return "EINVAL";
        case PtyErr::Io:
            return "EIO";
        case PtyErr::Busy:
            return "EBUSY";
        case PtyErr::Srch:
            return "ESRCH";
        default:
            return "EUNKNOWN";
    }
}

bool PtySessionManager::SetWinsize(int fd, int cols, int rows)
{
    if (fd < 0) {
        return false;
    }
    struct winsize ws {};
    ws.ws_col = static_cast<unsigned short>(cols > 0 ? cols : 80);
    ws.ws_row = static_cast<unsigned short>(rows > 0 ? rows : 24);
    return ::ioctl(fd, TIOCSWINSZ, &ws) == 0;
}

std::string PtySessionManager::ProbeShell(const std::string &preferred)
{
    if (!preferred.empty() && PathExists(preferred.c_str())) {
        return preferred;
    }
    static const char *kCandidates[] = {
        "/system/bin/sh",
        "/bin/sh",
        "/system/bin/bash",
        "/bin/bash",
        "/system/bin/ash",
        nullptr,
    };
    for (int i = 0; kCandidates[i]; ++i) {
        if (PathExists(kCandidates[i])) {
            return kCandidates[i];
        }
    }
    return preferred.empty() ? "/system/bin/sh" : preferred;
}

PtyStatus PtySessionManager::Available()
{
    PtyStatus st;
    int fd = ::open("/dev/ptmx", O_RDWR | O_CLOEXEC | O_NOCTTY);
    if (fd < 0) {
        int e = errno;
        st.code = ErrnoToPty(e);
        if (st.code == PtyErr::Unknown) {
            st.code = PtyErr::NoSys;
        }
        st.message = ErrMsg("open(/dev/ptmx)", e);
        return st;
    }
    ::close(fd);
    st.code = PtyErr::OK;
#if HM_TRY_OPENPTY
    st.message = "ptmx_ok;openpty_available";
#else
    st.message = "ptmx_ok;posix_openpt_path";
#endif
    return st;
}

PtyStatus PtySessionManager::OpenMaster(int &masterFd, std::string &slaveName)
{
    PtyStatus st;
    masterFd = -1;
    slaveName.clear();

#if HM_TRY_OPENPTY
    {
        int m = -1;
        int s = -1;
        char nameBuf[128] = {0};
        if (::openpty(&m, &s, nameBuf, nullptr, nullptr) == 0) {
            ::close(s);
            masterFd = m;
            slaveName = nameBuf;
            st.code = PtyErr::OK;
            return st;
        }
    }
#endif

#ifdef O_CLOEXEC
    int m = ::posix_openpt(O_RDWR | O_NOCTTY | O_CLOEXEC);
#else
    int m = ::posix_openpt(O_RDWR | O_NOCTTY);
#endif
    if (m < 0) {
        m = ::open("/dev/ptmx", O_RDWR | O_NOCTTY
#ifdef O_CLOEXEC
                                    | O_CLOEXEC
#endif
        );
    }
    if (m < 0) {
        int e = errno;
        st.code = ErrnoToPty(e);
        st.message = ErrMsg("posix_openpt/ptmx", e);
        return st;
    }

    (void)::grantpt(m);
    if (::unlockpt(m) != 0) {
        int e = errno;
        ::close(m);
        st.code = ErrnoToPty(e);
        st.message = ErrMsg("unlockpt", e);
        return st;
    }

    char *pts = ::ptsname(m);
    if (pts == nullptr) {
        int e = errno;
        ::close(m);
        st.code = ErrnoToPty(e);
        st.message = ErrMsg("ptsname", e);
        return st;
    }
    masterFd = m;
    slaveName = pts;
    st.code = PtyErr::OK;
    return st;
}

PtyStatus PtySessionManager::SpawnChild(int masterFd, const std::string &slaveName,
                                        int cols, int rows, const std::string &cwd,
                                        const std::string &shell, pid_t &outPid)
{
    PtyStatus st;
    outPid = -1;

    SetWinsize(masterFd, cols, rows);

    pid_t pid = ::fork();
    if (pid < 0) {
        int e = errno;
        st.code = ErrnoToPty(e);
        st.message = ErrMsg("fork", e);
        return st;
    }
    if (pid == 0) {
        ::close(masterFd);
        if (::setsid() < 0) {
            _exit(126);
        }
        int slave = ::open(slaveName.c_str(), O_RDWR);
        if (slave < 0) {
            _exit(125);
        }
#ifdef TIOCSCTTY
        (void)::ioctl(slave, TIOCSCTTY, 0);
#endif
        struct winsize ws {};
        ws.ws_col = static_cast<unsigned short>(cols > 0 ? cols : 80);
        ws.ws_row = static_cast<unsigned short>(rows > 0 ? rows : 24);
        (void)::ioctl(slave, TIOCSWINSZ, &ws);

        ::dup2(slave, STDIN_FILENO);
        ::dup2(slave, STDOUT_FILENO);
        ::dup2(slave, STDERR_FILENO);
        if (slave > STDERR_FILENO) {
            ::close(slave);
        }
        ChildExecShell(shell, cwd);
        _exit(127);
    }

    outPid = pid;
    st.code = PtyErr::OK;
    return st;
}

void PtySessionManager::StartReader(Session *s)
{
    s->reader = std::thread([s]() {
        char buf[4096];
        while (!s->stopReader) {
            fd_set rfds;
            FD_ZERO(&rfds);
            FD_SET(s->masterFd, &rfds);
            struct timeval tv {};
            tv.tv_sec = 0;
            tv.tv_usec = 200000;
            int r = ::select(s->masterFd + 1, &rfds, nullptr, nullptr, &tv);
            if (s->stopReader) {
                break;
            }
            if (r < 0) {
                if (errno == EINTR) {
                    continue;
                }
                break;
            }
            if (r == 0) {
                if (s->pid > 0) {
                    int status = 0;
                    pid_t w = ::waitpid(s->pid, &status, WNOHANG);
                    if (w == s->pid) {
                        s->alive = false;
                        break;
                    }
                }
                continue;
            }
            ssize_t n = ::read(s->masterFd, buf, sizeof(buf));
            if (n > 0) {
                std::lock_guard<std::mutex> lock(s->bufMu);
                s->outBuf.append(buf, static_cast<size_t>(n));
                if (s->outBuf.size() > 1024 * 1024) {
                    s->outBuf.erase(0, s->outBuf.size() - 512 * 1024);
                }
            } else if (n == 0) {
                s->alive = false;
                break;
            } else {
                if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) {
                    continue;
                }
                s->alive = false;
                break;
            }
        }
    });
}

PtyStatus PtySessionManager::Start(int cols, int rows, const std::string &cwd,
                                   const std::string &shell)
{
    PtyStatus probe = Available();
    if (probe.code != PtyErr::OK) {
        return probe;
    }

    int masterFd = -1;
    std::string slaveName;
    PtyStatus openSt = OpenMaster(masterFd, slaveName);
    if (openSt.code != PtyErr::OK) {
        return openSt;
    }

    int flags = ::fcntl(masterFd, F_GETFL, 0);
    if (flags >= 0) {
        (void)::fcntl(masterFd, F_SETFL, flags | O_NONBLOCK);
    }

    std::string sh = ProbeShell(shell);
    pid_t pid = -1;
    PtyStatus spawnSt = SpawnChild(masterFd, slaveName, cols, rows, cwd, sh, pid);
    if (spawnSt.code != PtyErr::OK) {
        ::close(masterFd);
        return spawnSt;
    }

    auto *s = new Session();
    s->masterFd = masterFd;
    s->pid = pid;
    s->cols = cols > 0 ? cols : 80;
    s->rows = rows > 0 ? rows : 24;
    s->alive = true;
    s->stopReader = false;

    {
        std::lock_guard<std::mutex> lock(mapMu_);
        s->id = nextId_++;
        sessions_[s->id] = s;
    }
    StartReader(s);

    PtyStatus st;
    st.code = PtyErr::OK;
    st.sessionId = s->id;
    st.message = std::string("started shell=") + sh + " pts=" + slaveName;
    return st;
}

PtyStatus PtySessionManager::Write(int sessionId, const std::string &data)
{
    PtyStatus st;
    Session *s = nullptr;
    {
        std::lock_guard<std::mutex> lock(mapMu_);
        auto it = sessions_.find(sessionId);
        if (it == sessions_.end()) {
            st.code = PtyErr::Srch;
            st.message = "session not found";
            return st;
        }
        s = it->second;
    }
    if (!s->alive || s->masterFd < 0) {
        st.code = PtyErr::Io;
        st.message = "session dead";
        return st;
    }
    const char *p = data.data();
    size_t left = data.size();
    while (left > 0) {
        ssize_t n = ::write(s->masterFd, p, left);
        if (n < 0) {
            if (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK) {
                continue;
            }
            st.code = ErrnoToPty(errno);
            st.message = ErrMsg("write", errno);
            return st;
        }
        p += n;
        left -= static_cast<size_t>(n);
    }
    st.code = PtyErr::OK;
    st.sessionId = sessionId;
    return st;
}

PtyStatus PtySessionManager::Drain(int sessionId, std::string &out)
{
    out.clear();
    PtyStatus st;
    Session *s = nullptr;
    {
        std::lock_guard<std::mutex> lock(mapMu_);
        auto it = sessions_.find(sessionId);
        if (it == sessions_.end()) {
            st.code = PtyErr::Srch;
            st.message = "session not found";
            return st;
        }
        s = it->second;
    }
    {
        std::lock_guard<std::mutex> lock(s->bufMu);
        out.swap(s->outBuf);
    }
    st.code = PtyErr::OK;
    st.sessionId = sessionId;
    if (!s->alive && out.empty()) {
        st.message = "exited";
    }
    return st;
}

PtyStatus PtySessionManager::Resize(int sessionId, int cols, int rows)
{
    PtyStatus st;
    Session *s = nullptr;
    {
        std::lock_guard<std::mutex> lock(mapMu_);
        auto it = sessions_.find(sessionId);
        if (it == sessions_.end()) {
            st.code = PtyErr::Srch;
            st.message = "session not found";
            return st;
        }
        s = it->second;
    }
    s->cols = cols;
    s->rows = rows;
    if (!SetWinsize(s->masterFd, cols, rows)) {
        st.code = ErrnoToPty(errno);
        st.message = ErrMsg("TIOCSWINSZ", errno);
        st.sessionId = sessionId;
        return st;
    }
    st.code = PtyErr::OK;
    st.sessionId = sessionId;
    return st;
}

void PtySessionManager::StopAndErase(int sessionId)
{
    Session *s = nullptr;
    {
        std::lock_guard<std::mutex> lock(mapMu_);
        auto it = sessions_.find(sessionId);
        if (it == sessions_.end()) {
            return;
        }
        s = it->second;
        sessions_.erase(it);
    }
    s->stopReader = true;
    s->alive = false;
    if (s->masterFd >= 0) {
        ::close(s->masterFd);
        s->masterFd = -1;
    }
    if (s->reader.joinable()) {
        s->reader.join();
    }
    delete s;
}

PtyStatus PtySessionManager::Kill(int sessionId)
{
    PtyStatus st;
    Session *s = nullptr;
    {
        std::lock_guard<std::mutex> lock(mapMu_);
        auto it = sessions_.find(sessionId);
        if (it == sessions_.end()) {
            st.code = PtyErr::Srch;
            st.message = "session not found";
            return st;
        }
        s = it->second;
    }
    if (s->pid > 0) {
        ::kill(s->pid, SIGHUP);
        ::kill(s->pid, SIGTERM);
        int status = 0;
        for (int i = 0; i < 20; ++i) {
            pid_t w = ::waitpid(s->pid, &status, WNOHANG);
            if (w == s->pid || (w < 0 && errno == ECHILD)) {
                break;
            }
            usleep(50 * 1000);
        }
        if (::waitpid(s->pid, &status, WNOHANG) == 0) {
            ::kill(s->pid, SIGKILL);
            (void)::waitpid(s->pid, &status, 0);
        }
        s->pid = -1;
    }
    StopAndErase(sessionId);
    st.code = PtyErr::OK;
    st.sessionId = sessionId;
    st.message = "killed";
    return st;
}

} // namespace hm_pty
