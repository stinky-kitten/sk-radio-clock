//
//  MSFDiagnostics.c
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-09-30.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

#include "MSFDiagnostics.h"

#include <stdatomic.h>

#include <hardware/sync.h>

// Main and the GPIO callback run on the same core. The IRQ owns head and
// dropped; the foreground owns tail. An interrupt mask protects each pop/copy.
static MSFDiagnostic records[MSF_DIAGNOSTIC_CAPACITY];
static volatile uint32_t head;
static volatile uint32_t tail;
static volatile uint32_t dropped;
static MSFFrameRecord completed_frame;
static volatile bool frame_pending;
static volatile uint32_t frame_dropped;

void msf_diagnostics_enqueue(bool rising, uint8_t state,
                             bool has_previous, uint64_t since_previous,
                             bool has_second, uint64_t since_second,
                             uint32_t scan_index, uint8_t reset_reason,
                             uint8_t scan_event, uint8_t phase_step,
                             uint8_t missing_slots, int32_t phase_error_us)
{
    uint32_t next = head;
    if (next - tail == MSF_DIAGNOSTIC_CAPACITY) {
        // Drop the newest diagnostic rather than delaying signal decoding.
        if (dropped != UINT32_MAX) ++dropped;
        return;
    }

    records[next % MSF_DIAGNOSTIC_CAPACITY] = (MSFDiagnostic) {
        .since_previous = since_previous,
        .since_second = since_second,
        .scan_index = scan_index,
        .phase_error_us = phase_error_us,
        .state = state,
        .reset_reason = reset_reason,
        .scan_event = scan_event,
        .phase_step = phase_step,
        .missing_slots = missing_slots,
        .rising = rising,
        .has_previous = has_previous,
        .has_second = has_second,
    };
    atomic_signal_fence(memory_order_release);
    head = next + 1;
}

bool msf_diagnostics_pop(MSFDiagnostic *record)
{
    uint32_t irq_state = save_and_disable_interrupts();
    uint32_t next = tail;
    if (next == head) {
        restore_interrupts(irq_state);
        return false;
    }
    *record = records[next % MSF_DIAGNOSTIC_CAPACITY];
    tail = next + 1;
    restore_interrupts(irq_state);
    return true;
}

uint32_t msf_diagnostics_take_dropped(void)
{
    uint32_t irq_state = save_and_disable_interrupts();
    uint32_t count = dropped;
    dropped = 0;
    restore_interrupts(irq_state);
    return count;
}

void msf_frame_publish(uint64_t a_bits, uint64_t b_bits, uint64_t unknown_bits,
                       uint32_t data_count, bool has_opening_marker,
                       uint64_t closing_marker_us)
{
    if (frame_pending) {
        if (frame_dropped != UINT32_MAX) ++frame_dropped;
        return;
    }
    completed_frame = (MSFFrameRecord) {
        .a_bits = a_bits, .b_bits = b_bits, .unknown_bits = unknown_bits,
        .closing_marker_us = closing_marker_us,
        .data_count = data_count, .has_opening_marker = has_opening_marker
    };
    atomic_signal_fence(memory_order_release);
    frame_pending = true;
}

bool msf_frame_take(MSFFrameRecord *record)
{
    uint32_t irq_state = save_and_disable_interrupts();
    if (!frame_pending) {
        restore_interrupts(irq_state);
        return false;
    }
    *record = completed_frame;
    frame_pending = false;
    restore_interrupts(irq_state);
    return true;
}

uint32_t msf_frame_take_dropped(void)
{
    uint32_t irq_state = save_and_disable_interrupts();
    uint32_t count = frame_dropped;
    frame_dropped = 0;
    restore_interrupts(irq_state);
    return count;
}
