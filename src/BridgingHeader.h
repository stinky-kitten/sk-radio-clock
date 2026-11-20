//
//  BridgingHeader.h
//  sk-radio-clock
//
//  Created by Gary J.H. Atkinson on 2026-09-24.
//  Copyright © 2026 Stinky Kitten Ltd. All rights reserved.
//

#pragma once

// Pico SDK multicore entry point.
// Declared separately to avoid importing architecture-specific
// spinlock implementations into Embedded Swift.
extern void multicore_launch_core1(void (*entry)(void));

#include <stdlib.h>
#include <time.h>
_Static_assert(sizeof(time_t) == 8, "UTC diagnostics require 64-bit time_t");
#include <pico/time.h>
#include <pico/stdlib.h>
#if defined(CYW43_LWIP)
#include <pico/cyw43_arch.h>
#endif
#if defined(CYW43_LWIP) && CYW43_LWIP
#include <lwip/dhcp.h>
#include <lwip/apps/sntp.h>
#include <pico/aon_timer.h>
// Swift cannot import the function-like CYW43_COUNTRY expansion. Keep the
// value derived from the SDK rather than duplicating the country encoding.
static const uint32_t radio_clock_country_uk = CYW43_COUNTRY_UK;
#endif
#include <hardware/irq.h>

#include "msf/diagnostics/MSFDiagnostics.h"  // IWYU pragma: keep

#include <math.h>
