#!/bin/bash
# Animated crab banner for container startup

COLS=$(tput cols 2>/dev/null || echo 80)
CRAB='(\/) (o o) (\/)'
CRAB_WIDTH=${#CRAB}
MAX_POS=$((COLS - CRAB_WIDTH - 1))

if [ "$MAX_POS" -lt 1 ]; then
    MAX_POS=40
fi

# Cap travel distance so the animation stays under ~3 seconds
if [ "$MAX_POS" -gt 50 ]; then
    MAX_POS=50
fi

DELAY=0.03

# Hide cursor during animation
tput civis 2>/dev/null

# Walk right
for ((i = 0; i <= MAX_POS; i++)); do
    printf "\r%*s%s" "$i" "" "$CRAB"
    sleep "$DELAY"
done

# Walk left (flip the crab)
CRAB_FLIP='(\/) (o o) (\/)'
for ((i = MAX_POS; i >= 0; i--)); do
    printf "\r%*s%*s" 0 "" "$((COLS))" ""
    printf "\r%*s%s" "$i" "" "$CRAB_FLIP"
    sleep "$DELAY"
done

# Clear the animation line
printf "\r%*s\r" "$COLS" ""

# Show cursor again
tput cnorm 2>/dev/null

# Print static banner
cat << 'BANNER'

    +============================+
    |  ////  ////  ////  ////    |
    |============================|
    |  _,,_         _,,_         |
    | (o  o)  \./  (o  o)        |
    |  \_/  --( )-- \_/          |
    | /|||\ / | \ /|||\          |
    |============================|
    |  ////  ////  ////  ////    |
    +============================+
      ISOLATED CRUSTACEAN
      Network-isolated Claude Code

BANNER
