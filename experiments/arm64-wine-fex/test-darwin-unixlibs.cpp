// Loads a built FEX Wine unixlib and exercises its Darwin-facing operations.
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <dlfcn.h>
#include <sys/mman.h>
#include <unistd.h>

using Handler = int32_t (*)(void*);
constexpr uint32_t STATUS_SUCCESS = 0;
constexpr uint32_t STATUS_NOT_SUPPORTED = 0xC00000BB;

struct HardwareTSOArgs { bool Enable; };
struct AtomicArgs { uint64_t Flags; };
struct MadviseArgs {
  const void* Addr;
  size_t Size;
  int32_t Advise;
  uint32_t Pad;
};
struct VMANameArgs {
  const void* Addr;
  size_t Size;
  const char* Name;
};
struct SHMArgs {
  void* Base;
  uint32_t MapSize;
  uint32_t MaxSize;
};

[[noreturn]] static void fail(const char* operation, uint32_t got, uint32_t expected) {
  std::fprintf(stderr, "FAIL: %s returned 0x%08x, expected 0x%08x\n", operation, got, expected);
  std::exit(1);
}

static void expect(const char* operation, int32_t result, uint32_t expected) {
  const auto actual = static_cast<uint32_t>(result);
  if (actual != expected) fail(operation, actual, expected);
  std::printf("PASS: %-24s 0x%08x\n", operation, actual);
}

int main(int argc, char** argv) {
  if (argc != 2) {
    std::fprintf(stderr, "usage: %s /path/to/libwow64fex.so\n", argv[0]);
    return 2;
  }

  void* library = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
  if (!library) {
    std::fprintf(stderr, "dlopen failed: %s\n", dlerror());
    return 1;
  }
  auto handlers = reinterpret_cast<Handler*>(dlsym(library, "__wine_unix_call_funcs"));
  if (!handlers) {
    std::fprintf(stderr, "missing __wine_unix_call_funcs: %s\n", dlerror());
    return 1;
  }

  HardwareTSOArgs tso {true};
  expect("hardware TSO", handlers[0](&tso), STATUS_NOT_SUPPORTED);
  AtomicArgs atomic {0};
  expect("unaligned atomics", handlers[1](&atomic), STATUS_NOT_SUPPORTED);

  const size_t pageSize = static_cast<size_t>(getpagesize());
  void* page = mmap(nullptr, pageSize, PROT_READ | PROT_WRITE,
                    MAP_PRIVATE | MAP_ANON, -1, 0);
  if (page == MAP_FAILED) {
    std::perror("mmap");
    return 1;
  }
  MadviseArgs madviseArgs {page, pageSize, MADV_NORMAL, 0};
  expect("madvise", handlers[2](&madviseArgs), STATUS_SUCCESS);
  VMANameArgs nameArgs {page, pageSize, "fex-test"};
  expect("VMA naming", handlers[3](&nameArgs), STATUS_NOT_SUPPORTED);
  munmap(page, pageSize);

  SHMArgs shared {nullptr, static_cast<uint32_t>(pageSize), static_cast<uint32_t>(pageSize * 2)};
  expect("shared stats allocate", handlers[4](&shared), STATUS_SUCCESS);
  if (!shared.Base) {
    std::fprintf(stderr, "FAIL: shared stats returned a null base\n");
    return 1;
  }
  shared.MapSize = static_cast<uint32_t>(pageSize * 2);
  expect("shared stats grow", handlers[4](&shared), STATUS_SUCCESS);
  expect("shared stats delete", handlers[5](nullptr), STATUS_SUCCESS);
  munmap(shared.Base, shared.MaxSize);

  dlclose(library);
  return 0;
}
