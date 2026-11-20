#pragma once

#include <stdint.h>
#include <stdatomic.h>

// SwiftPM-only boundary for sequential transport tests. These compiler fences
// do not mask interrupts or provide thread/multicore synchronization.
static inline uint32_t save_and_disable_interrupts(void)
{
    atomic_signal_fence(memory_order_seq_cst);
    return 0;
}

static inline void restore_interrupts(uint32_t status)
{
    (void)status;
    atomic_signal_fence(memory_order_seq_cst);
}
