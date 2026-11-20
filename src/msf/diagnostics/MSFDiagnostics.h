//
//  MSFDiagnostics.h
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-09-30.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

#pragma once

#include <stdint.h>
#include <stdbool.h>

#define MSF_DIAGNOSTIC_CAPACITY 64u

typedef struct {
    uint64_t since_previous;
    uint64_t since_second;
    uint32_t scan_index;
    int32_t phase_error_us;
    uint8_t state;
    uint8_t reset_reason;
    uint8_t scan_event;
    uint8_t phase_step;
    uint8_t missing_slots;
    bool rising;
    bool has_previous;
    bool has_second;
} MSFDiagnostic;

void msf_diagnostics_enqueue(bool rising, uint8_t state,
                             bool has_previous, uint64_t since_previous,
                             bool has_second, uint64_t since_second,
                             uint32_t scan_index, uint8_t reset_reason,
                             uint8_t scan_event, uint8_t phase_step,
                             uint8_t missing_slots, int32_t phase_error_us);
bool msf_diagnostics_pop(MSFDiagnostic *record);
uint32_t msf_diagnostics_take_dropped(void);

typedef struct {
    uint64_t a_bits;
    uint64_t b_bits;
    uint64_t unknown_bits;
    uint64_t closing_marker_us;
    uint32_t data_count;
    bool has_opening_marker;
} MSFFrameRecord;

void msf_frame_publish(uint64_t a_bits, uint64_t b_bits, uint64_t unknown_bits,
                       uint32_t data_count, bool has_opening_marker,
                       uint64_t closing_marker_us);
bool msf_frame_take(MSFFrameRecord *record);
uint32_t msf_frame_take_dropped(void);
