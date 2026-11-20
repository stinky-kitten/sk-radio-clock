"""Host contract checks; Pico hardware is replaced by small test doubles.

Run: python3 HostSupport/SwiftPlatformTests/test.py /path/to/toolchain/usr/include
"""

import os
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[2]
include = Path(sys.argv[1]).resolve()
compiler = os.environ.get("CC", "clang")
with tempfile.TemporaryDirectory(prefix="sk-swift-platform-") as directory:
    work = Path(directory)
    (work / "pico").mkdir()
    (work / "pico/mutex.h").write_text("""#include <assert.h>
typedef struct { unsigned depth; } recursive_mutex_t;
#define auto_init_recursive_mutex(name) static recursive_mutex_t name
extern unsigned pal_test_lock_depth;
extern unsigned pal_test_lock_operations;
static inline void recursive_mutex_enter_blocking(recursive_mutex_t *m) {
    ++pal_test_lock_operations;
    pal_test_lock_depth = ++m->depth;
}
static inline void recursive_mutex_exit(recursive_mutex_t *m) {
    ++pal_test_lock_operations;
    assert(m->depth > 0);
    pal_test_lock_depth = --m->depth;
}
""")
    (work / "pico/stdio.h").write_text("""#include <stdbool.h>
int stdio_put_string(const char *, int, bool, bool);
""")
    flags = ["-std=c2x", "-Wall", "-Wextra", "-Werror", "-fshort-enums",
             "-fsanitize=address,undefined", "-g", "-I" + str(include)]
    subprocess.run([compiler, *flags, "-I" + str(work),
                    "-Dmalloc=pal_test_malloc", "-Dfree=pal_test_free", "-c",
                    str(root / "src/platform/SwiftPlatform.c"),
                    "-o", str(work / "platform.o")], check=True)
    subprocess.run([compiler, *flags, str(Path(__file__).with_name("SwiftPlatformTests.c")),
                    str(work / "platform.o"), "-o", str(work / "test")], check=True)
    subprocess.run([str(work / "test")], check=True)
    # Verify argument forwarding separately: the real deallocator intentionally
    # ignores size/alignment/flags, so functional free tests cannot detect swaps.
    source = (root / "src/platform/SwiftPlatform.c").read_text()
    call = "_swift_deallocate(pointer, alignment, size, flags);"
    assert source.count(call) == 1
    intercepted = source.replace(call, """extern void pal_test_deallocate_forward(
        void *, size_t, size_t, swift_dealloc_flags_t);
    pal_test_deallocate_forward(pointer, alignment, size, flags);""")
    (work / "forwarding.c").write_text(intercepted)
    subprocess.run([compiler, *flags, "-I" + str(work),
                    "-Dmalloc=pal_test_malloc", "-Dfree=pal_test_free", "-c",
                    str(work / "forwarding.c"), "-o", str(work / "forwarding.o")], check=True)
    subprocess.run([compiler, *flags, "-DPAL_TEST_FORWARDING",
                    str(Path(__file__).with_name("SwiftPlatformTests.c")),
                    str(work / "forwarding.o"), "-o", str(work / "forwarding-test")], check=True)
    subprocess.run([str(work / "forwarding-test")], check=True)
