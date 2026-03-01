//+------------------------------------------------------------------+
//| PanelUI.mqh – UI Configuration Template                          |
//| Change colors, fonts, sizes here to customize the panel look.    |
//+------------------------------------------------------------------+
#ifndef PANEL_UI_MQH
#define PANEL_UI_MQH

// ════════════════════════════════════════════════════════════════════
// LAYOUT
// ════════════════════════════════════════════════════════════════════
#define PREFIX       "Bot_"
#define PX           15          // Panel X origin
#define PY           25          // Panel Y origin
#define PW           320         // Panel width
#define MARGIN       12          // Inner margin
#define IX           (PX + MARGIN)
#define IW           (PW - 2 * MARGIN)

// ════════════════════════════════════════════════════════════════════
// FONTS
// ════════════════════════════════════════════════════════════════════
#define FONT_MAIN    "Segoe UI"
#define FONT_BOLD    "Segoe UI Semibold"
#define FONT_MONO    "Consolas"

// ════════════════════════════════════════════════════════════════════
// COLORS – Panel Background & Text
// ════════════════════════════════════════════════════════════════════
#define COL_BG        C'25,25,35'       // Panel background
#define COL_TITLE_BG  C'35,40,60'       // Title bar background
#define COL_TITLE_TXT C'170,180,215'    // Title text
#define COL_TEXT      C'210,210,220'    // Primary text
#define COL_DIM       C'130,130,150'    // Dimmed/secondary text
#define COL_BORDER    C'50,50,65'       // Border/separator
#define COL_SEC_HDR   C'100,110,140'    // Section header labels (INFO, TRADE, etc.)

// ════════════════════════════════════════════════════════════════════
// COLORS – Input Fields
// ════════════════════════════════════════════════════════════════════
#define COL_EDIT_BG   C'35,35,50'       // Edit background
#define COL_EDIT_BD   C'60,60,80'       // Edit border

// ════════════════════════════════════════════════════════════════════
// COLORS – Buttons
// ════════════════════════════════════════════════════════════════════
#define COL_BUY       C'8,153,129'      // BUY button
#define COL_BUY_HI    C'0,180,150'      // BUY hover
#define COL_SELL      C'220,50,47'      // SELL button
#define COL_SELL_HI   C'245,65,60'      // SELL hover
#define COL_BTN       C'55,55,72'       // Generic button background
#define COL_BTN_TXT   C'200,200,220'    // Button text
#define COL_CLOSE     C'140,35,35'      // Close-all button background
#define COL_WHITE     C'255,255,255'    // White text

#define COL_HDR_BTN   C'40,40,55'       // Header buttons (Set/Dark/Lines/▼)
#define COL_BUY_PND   C'0,100,65'       // BUY PENDING button
#define COL_SELL_PND  C'170,40,40'      // SELL PENDING button
#define COL_CONFIRM   C'55,90,160'      // Pending confirm mode (blue)
#define COL_MINUS_BG  C'80,40,40'       // Minus [-] button (red)
#define COL_PLUS_BG   C'40,80,40'       // Plus [+] button (green)
#define COL_PRESET_BG C'50,50,70'       // Preset/mode buttons (risk %, ATR, etc.)

// ════════════════════════════════════════════════════════════════════
// COLORS – Toggle States (Trail/Grid/AutoTP)
// ════════════════════════════════════════════════════════════════════
#define COL_ON_BG     C'0,100,60'       // Active/ON toggle background (green)
#define COL_OFF_BG    C'60,60,85'       // Inactive/OFF toggle background
#define COL_OFF_TXT   C'180,180,200'    // Inactive/OFF toggle text

// ════════════════════════════════════════════════════════════════════
// COLORS – Trail Mode States
// ════════════════════════════════════════════════════════════════════
#define COL_TRAIL_ACTIVE_BD C'0,140,80'     // Active trail border (green)
#define COL_MODE_WAIT_BG    C'30,80,140'    // Selected-waiting background (blue)
#define COL_MODE_WAIT_BD    C'50,120,200'   // Selected-waiting border (blue)
#define COL_MODE_DIM_BG     C'50,50,70'     // Inactive mode button background
#define COL_MODE_DIM_TXT    C'140,140,160'  // Inactive mode button text

// ════════════════════════════════════════════════════════════════════
// COLORS – Close Section
// ════════════════════════════════════════════════════════════════════
#define COL_CLOSE_PART_BG   C'120,50,50'    // Close 50%/75% background
#define COL_CLOSE_PART_TXT  C'220,180,180'  // Close 50%/75% text
#define COL_CLOSE_ALL_TXT   C'255,200,200'  // Close 100% text

// ════════════════════════════════════════════════════════════════════
// COLORS – Grid Level Button
// ════════════════════════════════════════════════════════════════════
#define COL_GRID_LVL_BG    C'40,50,80'     // Grid level button background
#define COL_GRID_LVL_TXT   C'180,200,255'  // Grid level button text

// ════════════════════════════════════════════════════════════════════
// COLORS – Disabled/Placeholder
// ════════════════════════════════════════════════════════════════════
#define COL_DIS_BG    C'38,38,50'
#define COL_DIS_TXT   C'97,97,120'

// ════════════════════════════════════════════════════════════════════
// COLORS – Status & P&L
// ════════════════════════════════════════════════════════════════════
#define COL_PROFIT    C'0,180,100'      // Positive P&L
#define COL_LOSS      C'230,60,60'      // Negative P&L
#define COL_LOCK_UP   C'0,130,75'       // Positive SL Lock
#define COL_LOCK_DN   C'170,55,55'      // Negative SL Lock
#define COL_LONG      C'0,180,100'      // LONG direction text
#define COL_SHORT     C'220,80,80'      // SHORT direction text

// ════════════════════════════════════════════════════════════════════
// COLORS – Lines Hidden Toggle
// ════════════════════════════════════════════════════════════════════
#define COL_LINES_OFF C'100,40,40'      // Lines button when hidden (red bg)

// ════════════════════════════════════════════════════════════════════
// COLORS – Chart Lines
// ════════════════════════════════════════════════════════════════════
#define COL_LINE_SL       C'255,200,0'      // Active SL (yellow)
#define COL_LINE_ENTRY    C'100,150,255'    // Entry line (blue)
#define COL_LINE_SL_BUY   C'38,166,154'     // Preview buy SL (teal)
#define COL_LINE_SL_SELL  C'239,83,80'      // Preview sell SL (red)
#define COL_LINE_TP       C'0,200,83'       // TP line (green)
#define COL_LINE_DCA      C'255,152,0'      // DCA levels (orange)
#define COL_LINE_AVG      C'0,188,212'      // Average entry (cyan)
#define COL_LINE_PENDING  clrOrange          // Pending entry line

// ════════════════════════════════════════════════════════════════════
// COLORS – Dark Theme (TradingView-style)
// ════════════════════════════════════════════════════════════════════
#define DARK_BG         C'19,23,34'
#define DARK_FG         C'200,200,210'
#define DARK_BULL       C'38,166,154'
#define DARK_BEAR       C'239,83,80'
#define DARK_GRID       C'30,34,45'
#define DARK_VOLUME     C'60,63,80'
#define DARK_BID        C'33,150,243'
#define DARK_ASK        C'255,152,0'
#define DARK_STOP       C'255,50,50'

// ════════════════════════════════════════════════════════════════════
// COLORS – Light Theme
// ════════════════════════════════════════════════════════════════════
#define LIGHT_BG        C'255,255,255'
#define LIGHT_FG        C'60,60,60'
#define LIGHT_BULL      C'8,153,129'
#define LIGHT_BEAR      C'242,54,69'
#define LIGHT_GRID      C'230,230,230'
#define LIGHT_VOLUME    C'180,180,180'
#define LIGHT_BID       C'33,150,243'
#define LIGHT_ASK       C'255,152,0'
#define LIGHT_STOP      C'255,50,50'

// Theme toggle button colors
#define COL_LIGHT_BTN_BG  C'200,200,210'   // Light theme button bg
#define COL_LIGHT_BTN_TXT C'30,30,40'      // Light theme button text

// ════════════════════════════════════════════════════════════════════
// OBJECT NAMES
// ════════════════════════════════════════════════════════════════════
#define OBJ_BG         PREFIX "bg"
#define OBJ_TITLE_BG   PREFIX "title_bg"
#define OBJ_TITLE      PREFIX "title"
#define OBJ_TITLE_INFO PREFIX "title_info"
#define OBJ_TITLE_LOCK PREFIX "title_lock"
#define OBJ_RISK_LBL   PREFIX "risk_lbl"
#define OBJ_RISK_EDT   PREFIX "risk_edt"
#define OBJ_SPRD_LBL   PREFIX "sprd_lbl"
#define OBJ_STATUS_LBL PREFIX "status_lbl"
#define OBJ_LOCK_LBL   PREFIX "lock_lbl"
#define OBJ_LOCK_VAL   PREFIX "lock_val"
#define OBJ_BUY_BTN    PREFIX "buy_btn"
#define OBJ_SELL_BTN   PREFIX "sell_btn"
#define OBJ_CLOSE_BTN  PREFIX "close_btn"
#define OBJ_BUY_PND    PREFIX "buy_pnd"
#define OBJ_SELL_PND   PREFIX "sell_pnd"

#define OBJ_SEP1       PREFIX "sep1"
#define OBJ_SEP2       PREFIX "sep2"
#define OBJ_SEP3       PREFIX "sep3"
#define OBJ_SEP5       PREFIX "sep5"
#define OBJ_SEC_INFO   PREFIX "sec_info"
#define OBJ_SEC_TRADE  PREFIX "sec_trade"
#define OBJ_SEC_ORDER  PREFIX "sec_order"

// ORDER MANAGEMENT buttons
#define OBJ_TRAIL_BTN  PREFIX "trail_btn"
#define OBJ_TM_PRICE   PREFIX "tm_price"
#define OBJ_TM_CLOSE   PREFIX "tm_close"
#define OBJ_TM_SWING   PREFIX "tm_swing"
#define OBJ_TM_STEP    PREFIX "tm_step"
#define OBJ_TM_BE      PREFIX "tm_be"
#define OBJ_GRID_BTN   PREFIX "grid_btn"
#define OBJ_GRID_LVL   PREFIX "grid_lvl"
#define OBJ_AUTOTP_BTN PREFIX "autotp_btn"

// Chart lines (SL levels)
#define OBJ_SL_BUY_LINE   PREFIX "sl_buy_line"
#define OBJ_SL_SELL_LINE  PREFIX "sl_sell_line"
#define OBJ_SL_ACTIVE     PREFIX "sl_active"
#define OBJ_ENTRY_LINE    PREFIX "entry_line"
#define OBJ_PENDING_LINE  PREFIX "pending_line"

// Chart lines (Auto TP / Grid DCA)
#define OBJ_TP1_LINE      PREFIX "tp1_line"
#define OBJ_AVG_ENTRY     PREFIX "avg_entry"
#define OBJ_DCA1_LINE     PREFIX "dca1_line"
#define OBJ_DCA2_LINE     PREFIX "dca2_line"
#define OBJ_DCA3_LINE     PREFIX "dca3_line"
#define OBJ_DCA4_LINE     PREFIX "dca4_line"
#define OBJ_DCA5_LINE     PREFIX "dca5_line"
#define OBJ_GRID_INFO     PREFIX "grid_info"

// Theme toggle button
#define OBJ_THEME_BTN     PREFIX "theme_btn"

// Collapse button
#define OBJ_COLLAPSE_BTN  PREFIX "collapse_btn"
#define OBJ_LINES_BTN     PREFIX "lines_btn"
#define OBJ_CLOSE50_BTN   PREFIX "close50_btn"
#define OBJ_CLOSE75_BTN   PREFIX "close75_btn"

// Settings panel
#define OBJ_SETTINGS_BTN  PREFIX "settings_btn"
#define OBJ_SET_SEP       PREFIX "set_sep"
#define OBJ_SET_SEC       PREFIX "set_sec"
#define OBJ_SET_RISK_LBL  PREFIX "set_risk_lbl"
#define OBJ_SET_RISK_EDT  PREFIX "set_risk_edt"
#define OBJ_SET_RISK_PLUS PREFIX "set_rplus"
#define OBJ_SET_RISK_MINUS PREFIX "set_rminus"
#define OBJ_SET_R1        PREFIX "set_r1"
#define OBJ_SET_R2        PREFIX "set_r2"
#define OBJ_SET_R5        PREFIX "set_r5"
#define OBJ_SET_R10       PREFIX "set_r10"
#define OBJ_SET_R25       PREFIX "set_r25"
#define OBJ_SET_R50       PREFIX "set_r50"
#define OBJ_SET_R75       PREFIX "set_r75"
#define OBJ_SET_R100      PREFIX "set_r100"
#define OBJ_SET_ATR_LBL   PREFIX "set_atr_lbl"
#define OBJ_SET_ATR_EDT   PREFIX "set_atr_edt"
#define OBJ_SET_ATR_PLUS  PREFIX "set_aplus"
#define OBJ_SET_ATR_MINUS PREFIX "set_aminus"
#define OBJ_SET_A05       PREFIX "set_a05"
#define OBJ_SET_A10       PREFIX "set_a10"
#define OBJ_SET_A15       PREFIX "set_a15"
#define OBJ_SET_A20       PREFIX "set_a20"
#define OBJ_SET_A25       PREFIX "set_a25"
#define OBJ_SET_A30       PREFIX "set_a30"

#endif // PANEL_UI_MQH
