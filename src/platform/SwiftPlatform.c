#include <limits.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

// Swift's header uses Clang feature queries; GCC supports the C23 declarations.
#ifndef __has_feature
#define __has_feature(feature) 0
#endif
#include <swift/EmbeddedPlatform.h>

#include "pico/mutex.h"
#include "pico/stdio.h"

// Follow swift/EmbeddedPlatform.h, including its 64-bit flags under -fshort-enums.
// Use malloc/free so the Pico SDK's multicore heap locking and checks apply.
// Store the original allocation so deallocation needs neither size nor alignment.
void *_swift_allocate(size_t alignment, size_t size, swift_alloc_flags_t flags) {
    if (alignment < sizeof(void *) || (alignment & (alignment - 1)) != 0) return NULL;
    const size_t overhead = alignment - 1 + sizeof(void *);
    const size_t payload = size ? size : 1;
    if (payload > SIZE_MAX - overhead) return NULL;
    void *allocation = malloc(payload + overhead);
    if (!allocation) return NULL;
    const uintptr_t start = (uintptr_t)allocation + sizeof(void *);
    void *result = (void *)((start + alignment - 1) & ~(uintptr_t)(alignment - 1));
    ((void **)result)[-1] = allocation;
    if (flags & SWIFT_ALLOC_ZERO_MEMORY) memset(result, 0, size);
    return result;
}

void _swift_deallocate(void *pointer, size_t alignment, size_t size, swift_dealloc_flags_t flags) {
    (void)alignment;
    (void)size;
    (void)flags;
    if (pointer) free(((void **)pointer)[-1]);
}

void _swift_typedDeallocate(void *pointer, size_t size, size_t alignment,
                            swift_dealloc_flags_t flags, __swift_typeid_t typeId) {
    (void)typeId;
    // Typed deallocation takes size before alignment; the untyped PAL reverses them.
    _swift_deallocate(pointer, alignment, size, flags);
}

void _swift_reportErrorAt(const unsigned char *message, size_t messageCount,
                          const unsigned char *fileName, size_t fileNameCount,
                          size_t line, __swift_options_t flags) {
    // The PAL contract permits no reporting. Pico stdio acquires locks and calls
    // drivers even on a fatal path; it is not safe to assume initialized locks,
    // usable USB, or a non-IRQ/non-reentrant context here. Do not dereference the
    // counted UTF-8 buffers or attempt output. Swift performs the terminal trap
    // after this function returns, retaining the failure's debug information.
    (void)message;
    (void)messageCount;
    (void)fileName;
    (void)fileNameCount;
    (void)line;
    (void)flags;
}

// Swift can recursively print while formatting a value. Keep the whole print
// serialized between cores; Pico stdio separately locks each individual write.
auto_init_recursive_mutex(swift_stdout_mutex);

void _swift_lockStandardOutput(void) {
    recursive_mutex_enter_blocking(&swift_stdout_mutex);
}

void _swift_unlockStandardOutput(void) {
    recursive_mutex_exit(&swift_stdout_mutex);
}

size_t _swift_writeToStandardOutput(const unsigned char *chars, size_t count) {
    size_t written = 0;
    while (written < count) {
        const size_t remaining = count - written;
        const int chunk = remaining > INT_MAX ? INT_MAX : (int)remaining;
        const int result = stdio_put_string((const char *)chars + written, chunk, false, true);
        if (result <= 0) break;
        written += (size_t)result;
    }
    return written;
}
