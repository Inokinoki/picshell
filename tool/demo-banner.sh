#!/bin/bash
# Demo banner for picshell screenshots and test sessions.
# Printed on login when a test wants some colorful terminal content
# (see docs/screenshots/). Install into the test container as
# /usr/local/bin/banner.
C1="\033[38;5;39m"
C2="\033[38;5;44m"
C3="\033[38;5;213m"
G="\033[38;5;114m"
Y="\033[38;5;221m"
R="\033[0m"

printf "%b" "$C1"
cat <<'ART'
 ____  _          _          _ _
|  _ \(_) ___ ___| |__   ___| | |
| |_) | |/ __/ __| '_ \ / _ \ | |
|  __/| | (__\__ \ | | |  __/ | |
|_|   |_|\___|___/_| |_|\___|_|_|
ART
printf "%b" "$R"
printf "%b" "$G   SSH  |  SFTP  |  port forwarding  |  inline graphics$R\n"
printf "\n"
printf "%b" "$C2   System$R\n"
printf "   Host     %s\n" "$(hostname)"
printf "   Kernel   %s %s\n" "$(uname -r)" "$(uname -m)"
printf "   Shell    bash %s\n" "${BASH_VERSION%%(*}"
printf "\n"
printf "%b" "$Y   Try:$R ls --color=always  •  bash /tmp/graphics.sh  •  Ctrl+Shift+F to search\n"
printf "\n"
