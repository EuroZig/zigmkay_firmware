const std = @import("std");

const zigmkay = @import("zigmkay");
pub const core = zigmkay.core;
const _______: ?core.KeyDef = null;
const keycodes = @import("zkeycodes");
const kc = keycodes.layouts.keycodes.kcf;
const us = keycodes.layouts.us_international;
const macros = zigmkay.macros;
const kcm = keycodes.core;
const T = macros.T;
const AF = macros.AF;
const MED = macros.MED;
const MO = macros.MO;
const MS = macros.MS;
const SIG = macros.SIG;
const WinNav = macros.WinNav;
pub const COM_TOG = core.CUSTOM_ID_COMPANION_TOGGLE;
pub const COM_OFF = core.CUSTOM_ID_COMPANION_SHUTDOWN;
pub const COM_LOG = core.CUSTOM_ID_COMPANION_LOG_TOGGLE;

const tapping_term: core.TimeSpan = .{ .ms = 200 };

const H_ = macros.OptionsHomeRowMods{ .tapping_term = tapping_term };
const B_ = macros.OptionsBasicKeydef{ .tapping_term = tapping_term };

pub const L_BASE: usize = 0;
const L_ARROWS: usize = 1;
const L_NUM: usize = 2;
const L_EMPTY: usize = 3;
const L_BOTH: usize = 4;
const L_WIN: usize = 5;
const L_LEFT = L_NUM;
const L_RIGHT = L_ARROWS;

pub const key_count = 30;
// zig fmt: off
pub const sides = [key_count]core.Side{
  .L,.L,.L,.L,.L,       .R,.R,.R,.R,.R,
  .L,.L,.L,.L,.L,       .R,.R,.R,.R,.R,
     .L,.L,.L,.L,       .R,.R,.R,.R,
              .X,       .X
};

pub const keymap = [_][key_count]?core.KeyDef{
    .{
         T(us.Q),  T(us.W), T(us.F),   H_.S(us.P), T(us.B),                  T(us.J),   T(us.L),  T(us.U),       T(us.Y), T(us.SCLN),
         H_.S(us.A), H_.C(us.R), H_.A(us.S), H_.G(us.T), GuiH(us.G, us.T),                  T(us.M), H_.G(us.N),   H_.A(us.E),     H_.C(us.I),    H_.S(us.O),
                    GuiH(us.X, us.X),   GuiH(us.C, us.C),         T(us.D), GuiH(us.V, us.V),                  T(us.K),  T(us.H), T(us.COMM), B_.LT(L_WIN, us.DOT),
                                             B_.LT(L_LEFT, kc.SPC),                  B_.LT(L_RIGHT, kc.ENT)
    },
    // L_ARROWS - WIP (SEMICOLON & PLUS & TILD up for debate)
    .{
   H_.G(us.LBRC),    T(us.RBRC),    T(us.LCBR),          H_.S(us.RCBR), T(us.HASH),             T(us.AT),  T(kc.HOME),   AF(kc.UP),    T(kc.END),  T(us.PLUS),
    H_.S(us.LABK), H_.C(us.RABK), H_.A(us.LPRN),   H_.G(us.RPRN), T(us.SLSH),             T(kc.PGUP), AF(kc.LEFT), AF(kc.DOWN), AF(kc.RIGHT), H_.S(kc.PGDN),
                  T(us.DTIL),   T(us.AMPR),  T(us.ASTR),    T(kc.BSLS),                T(us.DLR),  H_.G(us.SCLN), H_.A(us.ACUT), H_.C(us.DGRV),
                                        B_.LT(L_LEFT, kc.ENT),                _______
    },
    // L_NUM
    .{
       H_.G(kc.ESC), T(SCRNSHT) ,    T(us.PERC),  H_.S(us.DCIR), T(us.DGRV),                  T(us.UNDS),   T(us.N7),  T(us.N8),  T(us.N9),    T(us.EQL),
       AF(kc.BSPC), H_.C(UNDO), H_.A(REDO) , H_.G(kc.ENT), T(kc.TAB),                T(us.MINS), H_.G(us.N4), H_.A(us.N5),H_.C(us.N6), H_.S(us.PLUS),
               T(kcm.L_GUI(us.X)), T(kcm.L_GUI(us.C)),   T(kc.DEL), T(kcm.L_GUI(us.V)),              T(us.EURO),   T(us.N1),  T(us.N2),  T(us.N3),
                                        _______,                                                       B_.LT(L_RIGHT, us.N0)
    },
    // L_EMPTY
    .{
            _______, _______, _______, _______, _______,                _______, _______, _______, _______, _______,
            _______, _______, _______, _______, _______,                _______, _______, _______, _______, _______,
                     _______, _______, _______, _______,                _______, _______, _______, _______,
                                             B_.LT(L_LEFT, kc.SPC),                  B_.LT(L_RIGHT, kc.ENT)

    },
    // BOTH - WIP (BACKSPC & ESC & TAB & GRAVE & CART up for debate, do we want SCRNSHT without shift?)
    .{
    H_.G(kc.ESC),   T(kc.F7),   T(kc.F8),   H_.S(kc.F9), T(kc.F10),            T(kcm.L_GUI(us.DGRV)), H_.S(kc.SPC), T(kc.SPC), T(kc.SPC), T(kc.TAB),
    AF(kc.BSPC), H_.C(kc.F4), H_.A(kc.F5), H_.G(kc.F6), T(kc.F11),             T(us.SS),  H_.G(kc.BSPC),  H_.A(kc.BSPC),  H_.C(kc.BSPC),   H_.S(kc.ESC),
                      T(kc.F1),   T(kc.F2),   T(kc.F3), T(kc.F12),            T(us.DCIR),   T(kc.DEL),   T(kc.DEL),   T(kc.DEL),
                                                   _______,              _______
    },
    // Window navigation shortcuts, activated by holding the base-layer dot key.
    .{
        WinNav(us.N7), _______, WinNav(us.N1), WinNav(us.N6), _______,             _______, _______, _______, _______, _______,
        WinNav(us.N4), _______, WinNav(us.N2), WinNav(us.N5), _______,             _______, _______, _______, _______, _______,
                    _______, WinNav(us.N3), WinNav(us.N8), _______,             _______, _______, _______, _______,
                                                            _______,             _______
    },

};

const UNDO = kcm.L_GUI(us.Z);
const REDO: core.KeyCodeFire = .{ .tap_keycode = us.Z.tap_keycode, .tap_modifiers = .{ .left_shift = true, .left_gui = true } };
pub const SCRNSHT = _GCS(us.N4);

// zig fmt: on

pub const dimensions = core.KeymapDimensions{
    .key_count = key_count,
    .layer_count = keymap.len,
};

const combo = zigmkay.combo.Options{
    .combo_timeout = .{ .ms = 40 },
    .tapping_term = .{ .ms = 200 },
};

// Plain Shift+' instead of us.DIAE: the dead variant makes the firmware tap a
// space afterwards, which macOS layouts without a dead " print literally.
const DQUO = kcm.L_SFT(kc.QUOT);

const quote_combo = zigmkay.combo.Options{
    .combo_timeout = tapping_term,
    .tapping_term = tapping_term,
};

pub const combos = [_]core.Combo2Def{
    combo.Combo_Tap(.{ 25, 26 }, L_BASE, us.COLN),
    combo.Combo_Tap(.{ 25, 26 }, L_ARROWS, us.COLN),
    quote_combo.Combo_Tap(.{ 26, 27 }, L_BASE, DQUO),
    quote_combo.Combo_Tap(.{ 26, 27 }, L_ARROWS, DQUO),
    combo.Combo_Tap_HoldMod(.{ 20, 21 }, L_BASE, us.Z, .{ .right_ctrl = true }),
    combo.Combo_Tap_HoldMod(.{ 1, 2 }, L_BASE, us.Z, .{ .right_ctrl = true }),

    // Dots for DE Umlaute:
    combo.Combo_Tap(.{ 22, 23 }, L_BASE, kcm.L_ALT(us.U)),
    combo.Combo_Tap(.{ 24, 25 }, L_BASE, kcm.L_ALT(us.U)),

    // combo.Combo_Tap_HoldMod(.{ 12, 13 }, L_BASE, us.V, .{ .left_ctrl = true, .left_shift = true }),
    // combo.Combo_Tap_HoldMod(.{ 12, 13 }, L_NUM, _Ctl(us.V), .{ .left_ctrl = true, .left_shift = true }),
    // combo.Combo_Tap_HoldMod(.{ 11, 12 }, L_NUM, _Ctl(us.X), .{ .left_ctrl = true, .left_shift = true }),
    // combo.Combo_Tap_HoldMod(.{ 12, 13 }, L_ARROWS, us.AMPR, .{ .left_ctrl = true, .left_shift = true }),

    combo.Combo_Tap(.{ 13, 16 }, L_BOTH, kcm.L_ALT(kc.F4)),

    combo.Combo_Tap(.{ 23, 24 }, L_BASE, core.KC_BOOT),
    combo.Combo_Tap(.{ 0, 4 }, L_BASE, core.KC_BOOT),
    combo.Combo_Tap(.{ 5, 4 }, L_BASE, core.KC_BOOT),
    // combo.Combo_Tap(.{ 6, 7 }, L_BASE, de.AE),
    // combo.Combo_Tap(.{ 6, 8 }, L_BASE, de.OE),
    // combo.Combo_Tap(.{ 7, 8 }, L_BASE, de.UE),

    combo.Combo_Tap(.{ 7, 8 }, L_ARROWS, us.QUES),
    combo.Combo_Tap(.{ 7, 8 }, L_NUM, us.QUES),
    combo.Combo_Tap(.{ 7, 8 }, L_BOTH, us.QUES),

    combo.Combo_Tap(.{ 1, 2 }, L_ARROWS, us.EXLM),
    combo.Combo_Tap(.{ 1, 2 }, L_NUM, us.EXLM),
    combo.Combo_Tap(.{ 1, 2 }, L_BOTH, us.EXLM),

    // combo.Combo_Tap_HoldMod(.{ 17, 18 }, L_BASE, us.MINS, .{ .left_ctrl = true, .left_alt = true }),
    combo.Combo_Tap(.{ 17, 18 }, L_ARROWS, us.PLUS),
    combo.Combo_Tap(.{ 16, 17 }, L_ARROWS, us.PIPE),

    combo.Combo_Tap(.{ 20, 21 }, L_ARROWS, us.BSLS),

    combo.Combo_Custom(.{ 1, 3 }, L_ARROWS, CUSTOM_TAP_EQ_COL),
};

const CUSTOM_TAP_EQ_COL: u8 = 3;

fn on_event(event: core.ProcessorEvent, layers: *core.LayerActivations, output_queue: *core.OutputCommandQueue) void {
    switch (event) {
        .OnHoldEnterAfter => |data| {
            layers.set_layer_state(L_BOTH, layers.is_layer_active(L_LEFT) and layers.is_layer_active(L_RIGHT));
            if (data.hold.custom) |keycode| {
                output_queue.tap_key(.{
                    .tap_keycode = keycode,
                    .tap_modifiers = data.hold.hold_modifiers,
                }) catch {};
            }
        },
        .OnHoldExitAfter => {
            layers.set_layer_state(L_BOTH, layers.is_layer_active(L_LEFT) and layers.is_layer_active(L_RIGHT));
        },
        .OnTapEnterBefore => |data| {
            if (data.tap.custom == CUSTOM_TAP_EQ_COL) {
                output_queue.tap_key(kc.SPC) catch {};
                output_queue.tap_key(us.COLN) catch {};
                output_queue.tap_key(us.EQL) catch {};
                output_queue.tap_key(kc.SPC) catch {};
            }
        },
        else => {},
    }
}

pub const custom_functions: core.CustomFunctions = .{ .on_event = on_event };

// TODO: Should these go somewhere else?

fn _GCS(fire: core.KeyCodeFire) core.KeyCodeFire {
    var copy = fire;
    copy.tap_modifiers.left_gui = true;
    copy.tap_modifiers.left_ctrl = true;
    copy.tap_modifiers.left_shift = true;
    return copy;
}

fn GuiH(keycode_fire: core.KeyCodeFire, keycode_hold: core.KeyCodeFire) core.KeyDef {
    return core.KeyDef{
        .tap_hold = .{
            .tap = .{ .key_press = keycode_fire },
            .hold = core.HoldDef{ .hold_modifiers = .{ .left_gui = true }, .custom = keycode_hold.tap_keycode },
            .tapping_term = tapping_term,
        },
    };
}
