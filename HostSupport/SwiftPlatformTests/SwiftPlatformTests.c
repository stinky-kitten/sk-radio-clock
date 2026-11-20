#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <swift/EmbeddedPlatform.h>

// These entry points were added after the September header.
void _swift_lockStandardOutput(void);
void _swift_unlockStandardOutput(void);

static_assert(sizeof(swift_alloc_flags_t) == 8, "PAL allocation flags must be 64-bit");
static_assert(sizeof(swift_dealloc_flags_t) == 8, "PAL deallocation flags must be 64-bit");
static_assert(sizeof(__swift_typeid_t) == 8, "PAL type IDs must be 64-bit");
static_assert(sizeof(__swift_options_t) == 8, "PAL reporting flags must be 64-bit");

unsigned pal_test_lock_depth;
unsigned pal_test_lock_operations;
static void *last_allocation;
static bool fail_allocation;
static unsigned frees;
static unsigned writes;
static unsigned mallocs;
static unsigned char output[64];
static size_t output_count;
static int write_limit = 64;

void *pal_test_malloc(size_t size) {
    ++mallocs;
    if (fail_allocation) return NULL;
    last_allocation = malloc(size);
    assert(last_allocation);
    memset(last_allocation, 0xa5, size);
    return last_allocation;
}

#ifdef PAL_TEST_FORWARDING
static unsigned forwards;
static void *forwarded_pointer;
static size_t forwarded_alignment;
static size_t forwarded_size;
static swift_dealloc_flags_t forwarded_flags;

// The runner intercepts only the typed function's call in a temporary copy.
void pal_test_deallocate_forward(void *pointer, size_t alignment, size_t size, swift_dealloc_flags_t flags) {
    ++forwards;
    forwarded_pointer = pointer;
    forwarded_alignment = alignment;
    forwarded_size = size;
    forwarded_flags = flags;
    _swift_deallocate(pointer, alignment, size, flags);
}
#endif

static void typed_deallocate(void *pointer, size_t size, size_t alignment, swift_dealloc_flags_t flags) {
    // The header's prose permits NULL despite its _Nonnull annotation.
    void (*deallocate)(void *, size_t, size_t, swift_dealloc_flags_t, __swift_typeid_t) = _swift_typedDeallocate;
#ifdef PAL_TEST_FORWARDING
    const unsigned previous = forwards;
#endif
    deallocate(pointer, size, alignment, flags, 0xfedcba9876543210ULL);
#ifdef PAL_TEST_FORWARDING
    assert(forwards == previous + 1);
    assert(forwarded_pointer == pointer && forwarded_alignment == alignment);
    assert(forwarded_size == size && forwarded_flags == flags);
#endif
}

static void report_errors(void) {
    const unsigned before_mallocs = mallocs, before_frees = frees, before_writes = writes;
    const unsigned before_locks = pal_test_lock_operations, before_depth = pal_test_lock_depth;
    // Counted, non-NUL-terminated UTF-8, with an embedded NUL in the message.
    const unsigned char message[] = {'x', 0, 0xc3, 0xa9};
    const unsigned char file[] = {0xc3, 0xa9, '.', 's'};
    for (unsigned kind = 0; kind < 4; ++kind) {
        _swift_reportErrorAt(message, sizeof(message), file, sizeof(file), SIZE_MAX,
                            (1ULL << 40) | kind);
    }
    _swift_reportErrorAt(NULL, 0, NULL, 0, 0, 0);
    assert(mallocs == before_mallocs && frees == before_frees && writes == before_writes);
    assert(pal_test_lock_operations == before_locks && pal_test_lock_depth == before_depth);
}

void pal_test_free(void *pointer) {
    assert(pointer == last_allocation);
    ++frees;
    free(pointer);
}

int stdio_put_string(const char *chars, int count, bool newline, bool cr_translation) {
    assert(pal_test_lock_depth > 0);
    assert(!newline && cr_translation);
    ++writes;
    if (count > write_limit) count = write_limit;
    assert(output_count + (size_t)count <= sizeof(output));
    memcpy(output + output_count, chars, (size_t)count);
    output_count += (size_t)count;
    return count;
}

int main(void) {
    report_errors(); // No stdio or lock initialization is required.
    unsigned allocations = 0;
    const size_t sizes[] = {0, 1, 7, 16, 127, 4097};
    for (size_t alignment = sizeof(void *); alignment <= 4096; alignment *= 2) {
        for (size_t i = 0; i < sizeof(sizes) / sizeof(sizes[0]); ++i) {
            for (unsigned zero = 0; zero < 2; ++zero) {
                // High flag bits must not be truncated by short-enum builds.
                const swift_alloc_flags_t flags = (1ULL << 40) | zero;
                unsigned char *p = _swift_allocate(alignment, sizes[i], flags);
                assert(p && (uintptr_t)p % alignment == 0);
                for (size_t n = 0; n < sizes[i]; ++n) assert(p[n] == (zero ? 0 : 0xa5));
                memset(p, 0x5a, sizes[i]);
                // The PAL allows unknown size and alignment during deallocation.
                _swift_deallocate(p, 0, SIZE_MAX, SWIFT_DEALLOC_NONE);
                ++allocations;
                p = _swift_allocate(alignment, sizes[i], flags);
                assert(p && (uintptr_t)p % alignment == 0);
                typed_deallocate(p, sizes[i], alignment, (swift_dealloc_flags_t)(1ULL << 40));
                ++allocations;
                p = _swift_allocate(alignment, sizes[i], flags);
                assert(p);
                typed_deallocate(p, SIZE_MAX, 0, SWIFT_DEALLOC_NONE);
                ++allocations;
            }
        }
    }
    assert(frees == allocations);
    // The header's prose permits NULL, despite its _Nonnull annotation.
    void (*deallocate)(void *, size_t, size_t, swift_dealloc_flags_t) = _swift_deallocate;
    deallocate(NULL, 0, SIZE_MAX, SWIFT_DEALLOC_NONE);
    typed_deallocate(NULL, SIZE_MAX, 0, SWIFT_DEALLOC_NONE);
    assert(frees == allocations);
    assert(!_swift_allocate(0, 1, SWIFT_ALLOC_NONE));
    assert(!_swift_allocate(3, 1, SWIFT_ALLOC_NONE));
    assert(!_swift_allocate(sizeof(void *), SIZE_MAX, SWIFT_ALLOC_NONE));
    fail_allocation = true;
    assert(!_swift_allocate(16, 1, SWIFT_ALLOC_NONE));

    const unsigned char bytes[] = {'a', 0, 'b', '\n', 0xc3, 0xa9};
    _swift_lockStandardOutput();
    _swift_lockStandardOutput();
    assert(pal_test_lock_depth == 2);
    report_errors(); // Reentrant reporting must not touch an already-held lock.
    assert(_swift_writeToStandardOutput(NULL, 0) == 0 && writes == 0);
    write_limit = 2;
    assert(_swift_writeToStandardOutput(bytes, sizeof(bytes)) == sizeof(bytes));
    assert(writes == 3 && output_count == sizeof(bytes));
    assert(memcmp(output, bytes, sizeof(bytes)) == 0);
    write_limit = 0;
    assert(_swift_writeToStandardOutput(bytes, sizeof(bytes)) == 0);
    _swift_unlockStandardOutput();
    assert(pal_test_lock_depth == 1);
    _swift_unlockStandardOutput();
    assert(pal_test_lock_depth == 0);
    printf("PAL contracts passed: %u allocations, typed forwarding/free, safe no-op reporting, output and locks\n",
           allocations);
}
