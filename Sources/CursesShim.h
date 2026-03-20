#include <ncurses.h>
#include <locale.h>

// ncurses attribute macros use NCURSES_BITS() which Swift can't import.
// Re-export them as static constants.
static const unsigned long CURSES_A_BOLD      = 1U << (8 + 13);
static const unsigned long CURSES_A_DIM       = 1U << (8 + 12);
static const unsigned long CURSES_A_UNDERLINE = 1U << (8 + 9);
static const unsigned long CURSES_A_REVERSE   = 1U << (8 + 10);
static const unsigned long CURSES_A_NORMAL    = 0;
