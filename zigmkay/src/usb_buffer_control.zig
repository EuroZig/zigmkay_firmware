// SPDX-License-Identifier: GPL-2.0
//! Adapted from zigmkay_firmware 3ee4135d308f18f15cc51b1d73e33e1b36bf517f.
//! RP2040 single-buffer control fields, datasheet section 4.1.2.7.1.
pub const available: u32 = 1 << 10;
pub const stall: u32 = 1 << 11;
pub const pid: u32 = 1 << 13;
pub const full: u32 = 1 << 15;

/// Call only after EP_ABORT_DONE grants ownership (or a bus reset).
/// HAL write/listen XOR the PID bit, so zero starts both directions DATA1.
pub fn prepareSetup(raw: u32) u32 {
    return raw & ~(available | full | stall | pid);
}

/// EP_ABORT_DONE is write-one-to-clear, not a read/modify/write register.
pub fn abortDoneAck(mask: u32) u32 {
    return mask;
}

/// RP2040-E2 forbids revoking an owned buffer on early silicon. The clock and
/// iteration bounds keep a stalled timer/peripheral from blocking the loop.
pub fn revoke(backend: anytype, mask: u32) error{ UnsupportedChipRevision, AbortTimeout }!void {
    const active = backend.active(mask);
    if (active == 0) return;
    if (backend.revision() < 2) return error.UnsupportedChipRevision;
    backend.abort(active);
    const start = backend.now();
    var attempts: usize = 0;
    while (backend.done() & active != active) : (attempts += 1) {
        if (backend.now() -| start >= 1000 or attempts >= 100000) return error.AbortTimeout;
    }
}
