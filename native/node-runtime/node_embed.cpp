// node_embed.cpp — embedded Node.js runtime for capacitor-harmony.
//
// This translation unit loads the prebuilt shared libnode.so shipped by
// https://github.com/electerm/ohos-node-shared AT RUNTIME with dlopen() —
// exactly how electerm-harmony consumes the same library. It must NOT link
// libnode.so at build time: that records DT_NEEDED "libnode.so.137" (the
// library's SONAME) while the file shipped in the HAP is named "libnode.so",
// and the OHOS linker resolves DT_NEEDED by exact filename only — so the
// napi module would fail to load. dlopen("libnode.so") from inside the
// module, in contrast, searches the app's lib dir (the caller's linker
// namespace) and finds the file. It also keeps the module loadable when
// libnode.so is absent, so the failure becomes a reportable error instead
// of a broken import.
//
// This TU includes no NAPI and no Node headers — it talks to capacitor_node.cpp
// only through node_bridge.h, and to libnode.so only through dlsym. That is
// why it can be compiled into the same shared library as the OHOS NAPI glue.
//
// On-device launch recipe (proven in electerm-harmony, which runs the same
// ohos-node-shared build):
//   1. dlopen libnode.so (same dir as this module, else namespace search) and
//      dlsym node::Start; every step is written to the boot log;
//   2. repair stdio fds 0/1/2 — libuv's uv__close asserts fd > STDERR_FILENO;
//   3. install a SIGSYS seccomp shim — the app sandbox traps syscalls node
//      probes (membarrier, perf_event_open, io_uring_setup, …) and the
//      default action kills the thread; the shim converts the trap into a
//      logged ENOSYS so node's probes no-op instead of aborting;
//   4. run node::Start with --jitless (THE fix for OpenHarmony's W^X policy:
//      V8 never maps PROT_EXEC pages, so no mprotect(PROT_EXEC)/EPERM ->
//      CHECK_EQ(ENOMEM, errno) abort) plus --no-verify-heap;
//   5. capture node's stdout/stderr via a pipe and forward each line to the
//      OHOS side (out_cb) and a boot log file for on-device debugging.

#include "node_bridge.h"

#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <ucontext.h>
#include <unistd.h>

#include <mutex>
#include <string>

static std::mutex g_state_mutex;
static bool g_running = false;
static int g_exit_code = 0;
static cap_output_cb g_out_cb = nullptr;
static cap_exit_cb g_exit_cb = nullptr;
static int g_log_fd = -1;     // boot log file (<data_dir>/node-boot.log)
static pid_t g_node_tid = 0;  // tid of the node::Start thread

/** Signature of node::Start(int argc, char* argv[]). */
typedef int (*node_start_fn)(int argc, char* argv[]);

// libnode.so handle + resolved entry point. Loaded once, never closed —
// node keeps global state long after Start returns.
static void* g_libnode = nullptr;
static node_start_fn g_node_start = nullptr;

// Mangled names for node::Start across Node major versions (int/char** form).
static const char* kNodeStartSymbols[] = {
    "_ZN4node5StartEiPPc",   // int node::Start(int, char**) — Node 24
    "_ZN4node5StartEiPKPKc", // int node::Start(int, const char* const*)
    nullptr,
};

// ---------------------------------------------------------------- logging ---
// Normal-context logging (NOT from a signal handler): writes to the boot log
// file and forwards to the OHOS side through out_cb.
static void LogLine(const char* level, const char* msg) {
  if (g_log_fd >= 0) {
    dprintf(g_log_fd, "%s: %s\n", level, msg);
  }
  if (g_out_cb != nullptr) {
    g_out_cb(level, msg);
  }
}

// Async-signal-safe write of a fixed string to the boot log file.  Used from
// signal handlers, so it performs NO formatting and NO libc locks — just a
// bare write(2).  (A signal handler that calls printf-family/vsnprintf can
// deadlock if the trapped thread already holds a libc lock.)
static void SafeWrite(const char* s) {
  if (g_log_fd < 0) return;
  size_t n = strlen(s);
  ssize_t ignored = write(g_log_fd, s, n);
  (void)ignored;
}

// ------------------------------------------------------------- libnode -------
/**
 * dlopen libnode.so and resolve node::Start.
 *
 * Candidate paths, in order:
 *   1. the directory THIS module was loaded from (dladdr) — on device that
 *      is the app's installed lib dir, where the HAP's libs/arm64-v8a files
 *      (libnode.so included) were extracted;
 *   2. the bare name "libnode.so" — the linker namespace of the caller (our
 *      napi module) has the app lib dir on its search path, so this resolves
 *      the same file even when dladdr is unavailable;
 *   3. the SONAME "libnode.so.137" — in case a future packaging ships the
 *      file under its real SONAME.
 *
 * Every attempt is written to the boot log, so a missing/broken libnode.so
 * can be diagnosed from the app UI (the log is what Node.getLog returns).
 *
 * Returns nullptr after logging the reason on failure.
 */
static node_start_fn LoadLibnode() {
  if (g_node_start != nullptr) {
    return g_node_start;
  }
  if (g_libnode != nullptr) {
    // Loaded before but the symbol was not found — do not retry endlessly.
    return nullptr;
  }

  std::string last_err = "not attempted";
  const char* candidates[4] = {nullptr, "libnode.so", "libnode.so.137", nullptr};

  // Candidate 0: directory of this very module (dladdr needs no knowledge of
  // bundle paths and works for every app that ships libnode.so in its HAP).
  char self_dir[4096] = {0};
  Dl_info info;
  memset(&info, 0, sizeof(info));
  if (dladdr((void*)&LoadLibnode, &info) != 0 && info.dli_fname != nullptr &&
      info.dli_fname[0] == '/') {
    snprintf(self_dir, sizeof(self_dir), "%s", info.dli_fname);
    char* slash = strrchr(self_dir, '/');
    if (slash != nullptr) {
      *(slash + 1) = '\0';
      size_t len = strlen(self_dir);
      if (len + strlen("libnode.so") + 1 < sizeof(self_dir)) {
        memmove(self_dir + len, "libnode.so", strlen("libnode.so") + 1);
        candidates[0] = self_dir;
      }
    }
  }

  for (int i = 0; i < 4 && candidates[i] != nullptr; i++) {
    LogLine("log", (std::string("node_embed: dlopen(\"") + candidates[i] +
                     "\", RTLD_NOW | RTLD_LOCAL)")
                        .c_str());
    void* h = dlopen(candidates[i], RTLD_NOW | RTLD_LOCAL);
    if (h == nullptr) {
      const char* err = dlerror();
      last_err = std::string(candidates[i]) + ": " +
                 (err != nullptr ? err : "dlopen returned NULL");
      LogLine("log",
              (std::string("node_embed: dlopen failed — ") + last_err).c_str());
      continue;
    }
    g_libnode = h;
    for (int s = 0; kNodeStartSymbols[s] != nullptr; s++) {
      void* sym = dlsym(h, kNodeStartSymbols[s]);
      if (sym != nullptr) {
        g_node_start = (node_start_fn)sym;
        LogLine("log",
                (std::string("node_embed: resolved node::Start as ") +
                 kNodeStartSymbols[s])
                    .c_str());
        return g_node_start;
      }
    }
    const char* err = dlerror();
    last_err = std::string("node::Start not exported by ") + candidates[i] +
               (err != nullptr ? std::string(" (") + err + ")" : std::string());
    LogLine("error",
            (std::string("node_embed: ") + last_err).c_str());
    // Keep g_libnode (avoid reloading the same image) and give up.
    return nullptr;
  }

  LogLine("error",
          (std::string("node_embed: could not load libnode.so — ") + last_err)
              .c_str());
  return nullptr;
}

// ------------------------------------------------------- SIGSYS shim --------
// Map seccomp-trapped syscalls to ENOSYS instead of letting the default
// action (SIGSYS -> thread kill) take the node thread down.  Ported from
// electerm-harmony's verified node_ctl.c shim.

// Is there an aarch64 `svc #0` (encoded 0xd4000001) at `pc`?  Deciding by
// comparing the frame PC with si_addr is unreliable (both come from the same
// pt_regs); reading the encoding is the only robust check.
static int PcIsSvcInsn(unsigned long pc) {
  if (pc == 0 || (pc & 3u) != 0) return 0;
  unsigned int insn = 0;
  memcpy(&insn, (const void*)pc, sizeof(insn));
  return (insn & 0xffe0001fu) == 0xd4000001u;
}

static void SigsysHandler(int sig, siginfo_t* si, void* ctx) {
  (void)sig;
  // Only emulate a real seccomp trap.  A SIGSYS delivered by raise()/kill()
  // carries no syscall context; rewriting the register file for it corrupts
  // whatever thread happened to be running.
  if (!si || !ctx || si->si_code != 1 /* SYS_SECCOMP */) {
    signal(SIGSYS, SIG_DFL);
    raise(SIGSYS);
    return;
  }
  // Fixed marker only — no snprintf/strlen in the hot path (async-signal-safe).
  SafeWrite("[embed] SIGSYS trapped by seccomp -> shimmed to ENOSYS\n");
  ucontext_t* uc = (ucontext_t*)ctx;
#if defined(__aarch64__)
  if (PcIsSvcInsn(uc->uc_mcontext.pc)) {
    uc->uc_mcontext.pc += 4;
  }
  uc->uc_mcontext.regs[0] = (unsigned long)-1;
#elif defined(__x86_64__)
  unsigned long pc = (unsigned long)uc->uc_mcontext.gregs[REG_RIP];
  if (pc != 0) {
    unsigned char c[2] = {0, 0};
    memcpy(c, (const void*)pc, 2);
    if (c[0] == 0x0fu && c[1] == 0x05u) {
      uc->uc_mcontext.gregs[REG_RIP] += 2;
    }
  }
  uc->uc_mcontext.gregs[REG_RAX] = (unsigned long)-1;
#endif
  // Return EXACTLY -1, not -ENOSYS: OHOS musl's syscall() passes raw x0
  // through without errno translation, so -38 leaks to callers as a bogus
  // value (device-proven fatal in libuv uv__iou_init: ringfd=-38 sailed past
  // its `== -1` guard, failed mmap/epoll_ctl, cleanup called uv__close(-38)
  // -> assert(fd > STDERR_FILENO) -> abort).
  errno = ENOSYS;
}

static void InstallSigsysShim() {
  struct sigaction sa;
  memset(&sa, 0, sizeof(sa));
  sa.sa_sigaction = SigsysHandler;
  sa.sa_flags = SA_SIGINFO;
  if (sigaction(SIGSYS, &sa, NULL) != 0) {
    LogLine("error", "installSigsysShim: sigaction(SIGSYS) failed");
  }
}

// ----------------------------------------------------- crash markers --------
// Name the killer signal in the boot log (and park the node thread instead of
// dying) so the app survives and the UI can show "stopped" with a reason.
static void CrashMarkerHandler(int sig, siginfo_t* si, void* ctx) {
  // Name the killer precisely (signal + fault address + pc) — this is usually
  // the only clue we get on-device, since the trap happens before node prints
  // anything. Boot log only: LogLine is not async-signal-safe.
  unsigned long fault_addr = si ? (unsigned long)si->si_addr : 0;
  int si_code = si ? si->si_code : 0;
  unsigned long pc = 0;
#if defined(__aarch64__)
  if (ctx != nullptr) {
    pc = (unsigned long)((ucontext_t*)ctx)->uc_mcontext.pc;
  }
#elif defined(__x86_64__)
  if (ctx != nullptr) {
    pc = (unsigned long)((ucontext_t*)ctx)->uc_mcontext.gregs[REG_RIP];
  }
#endif
  char b[256];
  int n = snprintf(b, sizeof(b),
                   "[embed] fatal: signal %d code %d addr 0x%lx pc 0x%lx\n",
                   sig, si_code, fault_addr, pc);
  if (n > 0) SafeWrite(b);
  long tid = (long)syscall(__NR_gettid);
  if (g_node_tid > 0 && tid == (long)g_node_tid) {
    // Node's thread crashed — keep the app alive, surface the failure.
    std::lock_guard<std::mutex> lock(g_state_mutex);
    g_running = false;
    cap_exit_cb cb = g_exit_cb;
    g_exit_cb = nullptr;
    if (cb) cb(sig);
    for (;;) pause();
  }
  signal(sig, SIG_DFL);
  raise(sig);
}

static void InstallCrashMarkers() {
  struct sigaction sa;
  memset(&sa, 0, sizeof(sa));
  sa.sa_sigaction = CrashMarkerHandler;
  sa.sa_flags = SA_SIGINFO;
  const int sigs[] = {SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE};
  for (size_t i = 0; i < sizeof(sigs) / sizeof(sigs[0]); i++) {
    if (sigaction(sigs[i], &sa, NULL) != 0) {
      LogLine("error", "installCrashMarkers: sigaction failed");
    }
  }
}

// --------------------------------------------------------- fd repair --------
// Guarantee fds 0/1/2 are open; libuv's uv__close asserts fd > STDERR_FILENO,
// so a closed std fd that gets reused through a dup2/close chain aborts.
static void RepairStdio() {
  for (int fd = 0; fd <= 2; fd++) {
    struct stat st;
    if (fstat(fd, &st) == 0) continue;
    int nfd = open("/dev/null", O_RDWR);
    if (nfd < 0) {
      LogLine("error", "RepairStdio: open(/dev/null) failed");
      continue;
    }
    if (nfd != fd) {
      dup2(nfd, fd);
      close(nfd);
    }
  }
}

// ---------------------------------------------------- stdio capture ---------
// Reader thread: drains the pipe fd 1/2 were dup2'd onto, forwards each line
// to out_cb + boot log.  Bounded and non-blocking on the writer side.
static void* StdioReaderThread(void* arg) {
  int rd = (int)(intptr_t)arg;
  char buf[8192];
  char line[1024];
  size_t linelen = 0;
  for (;;) {
    ssize_t r = read(rd, buf, sizeof(buf));
    if (r <= 0) break;
    for (ssize_t i = 0; i < r; i++) {
      char c = buf[i];
      if (c == '\n' || linelen >= sizeof(line) - 1) {
        line[linelen] = '\0';
        if (linelen > 0) {
          const char* lvl = (strstr(line, "error") || strstr(line, "Error") ||
                             strstr(line, "assert") || strstr(line, "Abort") ||
                             strstr(line, "abort"))
                                ? "error"
                                : "log";
          LogLine(lvl, line);
        }
        linelen = 0;
      } else if (c != '\r' && c != '\0') {
        line[linelen++] = c;
      }
    }
  }
  return NULL;
}

// ----------------------------------------------------------- node thread -----
struct NodeArgs {
  std::string entry_path;
  std::string data_dir;
};

/** Mark the runtime stopped and hand the exit code to the OHOS side once. */
static void FinishWith(int rc) {
  std::lock_guard<std::mutex> lock(g_state_mutex);
  g_running = false;
  g_exit_code = rc;
  cap_exit_cb cb = g_exit_cb;
  g_exit_cb = nullptr;
  if (cb) cb(rc);
}

static void* NodeThreadMain(void* arg) {
  NodeArgs* na = static_cast<NodeArgs*>(arg);
  std::string entry_path = std::move(na->entry_path);
  std::string data_dir = std::move(na->data_dir);
  delete na;

  g_node_tid = (pid_t)syscall(__NR_gettid);
  LogLine("log", "node_embed: starting embedded Node");

  // boot log (same file electerm-harmony writes, for on-device debugging)
  if (!data_dir.empty()) {
    std::string logPath = data_dir + "/node-boot.log";
    int fd = open(logPath.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd >= 0) {
      // Never keep the boot log on a std fd: RepairStdio()/dup2() below take
      // over 0/1/2, which would silently redirect the log into the stdio pipe
      // (and, worse, make SafeWrite() feed the reader its own output).
      if (fd <= 2) {
        int high = fcntl(fd, F_DUPFD, 3);
        if (high >= 0) {
          close(fd);
          fd = high;
        }
      }
      g_log_fd = fd;
    } else {
      LogLine("error", "node_embed: cannot open boot log");
    }
  }

  RepairStdio();
  InstallCrashMarkers();
  InstallSigsysShim();
  setenv("UV_USE_IO_URING", "0", 1);  // io_uring_setup is seccomp-trapped
  setenv("NODE_ENV", "production", 1);
  setenv("HOST", "127.0.0.1", 1);
  setenv("PORT", "3000", 1);
  if (!data_dir.empty()) {
    if (chdir(data_dir.c_str()) != 0) {
      LogLine("error", "node_embed: chdir to data dir failed");
    }
  }

  // Refuse to start rather than let node call exit() — a missing entry file
  // would otherwise tear down the whole app process.
  struct stat entryStat;
  if (stat(entry_path.c_str(), &entryStat) != 0) {
    std::string msg = std::string("node_embed: entry file missing: ") + entry_path +
                      " (errno " + std::to_string(errno) + ")";
    LogLine("error", msg.c_str());
    FinishWith(1);
    return NULL;
  }

  // Redirect fd 1/2 onto a pipe so node output is observable.  A 1 MB buffer
  // avoids the reader being descheduled and a writer blocking on a full pipe.
  int fds[2];
  if (pipe(fds) == 0) {
    int rd = fds[0];
    int wr = fds[1];
    dup2(wr, 1);
    dup2(wr, 2);
    close(wr);
    pthread_t rdth;
    if (pthread_create(&rdth, NULL, StdioReaderThread,
                       (void*)(intptr_t)rd) == 0) {
      pthread_detach(rdth);
    } else {
      close(rd);
    }
  } else {
    LogLine("error", "node_embed: pipe() failed");
  }

  // Load libnode.so NOW (not at process start): a failure here is logged and
  // reported through exit_cb instead of breaking the whole module import.
  node_start_fn start_fn = LoadLibnode();
  if (start_fn == nullptr) {
    LogLine("error", "node_embed: refusing to continue without libnode.so");
    FinishWith(1);
    return NULL;
  }

  // argv for node::Start.  node consumes the flags and runs entry_path as the
  // script (process.argv[1]); --jitless is the OpenHarmony W^X fix.
  char arg0[] = "node";
  char flag1[] = "--no-verify-heap";
  char flag2[] = "--jitless";
  char entry_buf[4096];
  snprintf(entry_buf, sizeof(entry_buf), "%s", entry_path.c_str());
  char* argv[] = {arg0, flag1, flag2, entry_buf, NULL};
  int argc = 4;

  {
    std::string msg = std::string("node_embed: cwd=") + data_dir +
                      " entry=" + entry_path + " size=" +
                      std::to_string((long long)entryStat.st_size);
    LogLine("log", msg.c_str());
  }
  LogLine("log", "node_embed: calling node::Start (--jitless --no-verify-heap)");
  int rc = start_fn(argc, argv);  // blocks while the server runs

  {
    std::string msg = "node_embed: node::Start returned rc=" + std::to_string(rc) +
                      " — backend stopped";
    LogLine("error", msg.c_str());
  }
  FinishWith(rc);
  return NULL;
}

void node_embed_run(const char* entry_path, const char* data_dir,
                    cap_output_cb out_cb, cap_exit_cb exit_cb) {
  if (entry_path == nullptr) return;
  {
    std::lock_guard<std::mutex> lock(g_state_mutex);
    if (g_running) return;
    g_running = true;
    g_out_cb = out_cb;
    g_exit_cb = exit_cb;
  }

  NodeArgs* na = new NodeArgs();
  na->entry_path = entry_path ? entry_path : "";
  na->data_dir = data_dir ? data_dir : "";

  // node::Start wants a big stack (V8 + the deep C++ bootstrap).
  pthread_t th;
  pthread_attr_t attr;
  pthread_attr_init(&attr);
  pthread_attr_setstacksize(&attr, 32 * 1024 * 1024);
  int prc = pthread_create(&th, &attr, NodeThreadMain, na);
  pthread_attr_destroy(&attr);
  if (prc != 0) {
    delete na;
    std::lock_guard<std::mutex> lock(g_state_mutex);
    g_running = false;
    g_out_cb = nullptr;
    cap_exit_cb cb = g_exit_cb;
    g_exit_cb = nullptr;
    if (cb) cb(prc);
    return;
  }
  pthread_detach(th);
}

void node_embed_stop() {
  // node::Start runs in-process (same app process); a clean stop would require
  // signalling the node thread, which would take down the whole app. The app's
  // own lifecycle ends the server, so stop is a no-op here.
}

int node_embed_is_running() {
  std::lock_guard<std::mutex> lock(g_state_mutex);
  return g_running ? 1 : 0;
}
