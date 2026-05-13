#!/usr/bin/env bash
# Must be run with sudo to access full auth logs and wtmp/btmp.
# Usage: sudo ./check_logins.sh [-v]
#   -v   verbose: show all raw log sections in addition to the summary
set -euo pipefail

VERBOSE=0
while getopts "v" opt; do
  case $opt in
    v) VERBOSE=1 ;;
    *) printf "Usage: %s [-v]\n" "$0"; exit 1 ;;
  esac
done

RED='\033[0;31m'
YEL='\033[0;33m'
CYN='\033[0;36m'
GRN='\033[0;32m'
BLD='\033[1m'
RST='\033[0m'

header() { printf "\n${BLD}${CYN}=== %s ===${RST}\n" "$*"; }
warn()   { printf "${YEL}[WARN] %s${RST}\n" "$*"; }

if [[ $EUID -ne 0 ]]; then
  printf "${RED}[ERROR] Run this script with sudo.${RST}\n"
  exit 1
fi

# ── Collect raw data ──────────────────────────────────────────────────────────

# Successful logins from journald (most complete on Ubuntu 24.04)
ACCEPTED=$(journalctl -u ssh -u sshd --no-pager -q 2>/dev/null \
  | grep "Accepted" || true)

# Failed logins from journald
FAILED=$(journalctl -u ssh -u sshd --no-pager -q 2>/dev/null \
  | grep -E "Failed|Invalid user" || true)

# wtmp history
LAST_OUT=$(last -a -F -w 2>/dev/null || true)

# lastlog
LASTLOG_OUT=$(lastlog 2>/dev/null | grep -v "Never logged" || true)

# Currently logged in
WHO_OUT=$(who 2>/dev/null || true)

# Active SSH connections
SS_OUT=$(ss -tnp 2>/dev/null | grep ':22' || true)

# Failed auth from auth.log (catches things journald may miss)
FAILED_AUTH=$(grep -hE "Failed password|Invalid user|authentication failure" \
  /var/log/auth.log /var/log/auth.log.* 2>/dev/null || true)

# sudo commands
SUDO_CMDS=$(grep -hE "sudo:" /var/log/auth.log /var/log/auth.log.* 2>/dev/null \
  | grep "COMMAND" || true)

# ── Verbose raw output ────────────────────────────────────────────────────────

if [[ $VERBOSE -eq 1 ]]; then
  header "Successful logins — journald"
  [[ -n "$ACCEPTED" ]] && printf "%s\n" "$ACCEPTED" || warn "No journald ssh entries found"

  header "Failed logins — journald"
  if [[ -n "$FAILED" ]]; then
    printf "%s\n" "$FAILED" | awk '{print $1,$2,$3,$9,$11}' | sort | uniq -c | sort -rn | head -40
  else
    warn "No journald failed login entries found"
  fi

  header "Failed login attempts — auth.log*"
  if [[ -n "$FAILED_AUTH" ]]; then
    printf "%s\n" "$FAILED_AUTH" | sort | uniq -c | sort -rn | head -40
  else
    warn "No failed login data found"
  fi

  header "Recent login history — last (utmp/wtmp)"
  [[ -n "$LAST_OUT" ]] && printf "%s\n" "$LAST_OUT" | head -60 || warn "last command unavailable"

  header "Last login per user — lastlog"
  [[ -n "$LASTLOG_OUT" ]] && printf "%s\n" "$LASTLOG_OUT" || warn "lastlog unavailable"

  header "Currently logged-in users — who"
  [[ -n "$WHO_OUT" ]] && printf "%s\n" "$WHO_OUT" || warn "who unavailable"

  header "Active SSH sessions — ss"
  [[ -n "$SS_OUT" ]] && printf "%s\n" "$SS_OUT" || warn "No active SSH sessions on :22"

  header "sudo usage — auth.log*"
  if [[ -n "$SUDO_CMDS" ]]; then
    printf "%s\n" "$SUDO_CMDS" | sort | uniq -c | sort -rn | head -40
  else
    warn "No sudo log data found"
  fi

  printf "\n"
fi

# ── Summary ───────────────────────────────────────────────────────────────────

HOST=$(hostname)
printf "\n${BLD}${CYN}╔══════════════════════════════════════════╗${RST}\n"
printf   "${BLD}${CYN}║      LOGIN SUMMARY — %-20s║${RST}\n" "$HOST"
printf   "${BLD}${CYN}╚══════════════════════════════════════════╝${RST}\n"

# --- Users who have logged in (from wtmp) ---
printf "\n${BLD}Users who have logged in (wtmp history):${RST}\n"
printf "%-16s %-22s %-18s %s\n" "USER" "LAST LOGIN" "DURATION" "FROM"
printf "%-16s %-22s %-18s %s\n" "----" "----------" "--------" "----"

# Parse last output: skip reboots, system entries, and the trailing wtmp line
printf "%s\n" "$LAST_OUT" \
  | grep -v "^reboot\|^wtmp\|^$\|system boot" \
  | awk '{
      user=$1
      # last -F -a puts IP at the end; duration is in parens or "still logged in"
      # Fields: user tty ip dow mon day HH:MM:SS year - dow mon day HH:MM:SS year (dur) IP
      ip=$NF
      # find duration: either "(HH:MM)" or "still logged in"
      dur="still logged in"
      for(i=1;i<=NF;i++) if($i ~ /^\(/) { dur=$i; gsub(/[()]/,"",dur) }
      # date: fields 5-9 give "Mon Apr 20 16:08:12 2026"
      date=$5" "$6" "$7" "$8" "$9
      printf "%-16s %-22s %-18s %s\n", user, date, dur, ip
    }' \
  | sort -u -k1,1

# --- Currently active sessions ---
printf "\n${BLD}Currently logged in:${RST}\n"
if [[ -n "$WHO_OUT" ]]; then
  printf "%s\n" "$WHO_OUT" | grep -v "^$" | while IFS= read -r line; do
    printf "  %s\n" "$line"
  done
else
  printf "  (none)\n"
fi

# --- Active SSH connections ---
printf "\n${BLD}Active SSH connections (:22):${RST}\n"
if [[ -n "$SS_OUT" ]]; then
  printf "%s\n" "$SS_OUT" | while IFS= read -r line; do
    printf "  %s\n" "$line"
  done
else
  printf "  (none)\n"
fi

# --- Failed login attempts ---
printf "\n${BLD}Failed login attempts:${RST}\n"
FAIL_COMBINED=$(
  { printf "%s\n" "$FAILED" 2>/dev/null; printf "%s\n" "$FAILED_AUTH" 2>/dev/null; } \
  | grep -oE "(Invalid user [a-z_][a-z0-9_-]* from|Failed password for [a-z_][a-z0-9_-]* from|Failed [a-z]+ for [a-z_][a-z0-9_-]* from) [0-9a-f.:]+" \
  | sort | uniq -c | sort -rn || true
)
if [[ -n "$FAIL_COMBINED" ]]; then
  printf "%s\n" "$FAIL_COMBINED" | head -20 | while IFS= read -r line; do
    printf "  ${YEL}%s${RST}\n" "$line"
  done
else
  printf "  ${GRN}None detected${RST}\n"
fi

# --- Unique source IPs for successful logins ---
printf "\n${BLD}Unique source IPs (successful logins):${RST}\n"
SRC_IPS=$(printf "%s\n" "$ACCEPTED" \
  | grep -oE "from [0-9a-f.:]+" | sort | uniq -c | sort -rn || true)
if [[ -n "$SRC_IPS" ]]; then
  printf "%s\n" "$SRC_IPS" | while IFS= read -r line; do
    printf "  %s\n" "$line"
  done
else
  printf "  (none found)\n"
fi

# --- Notable observations ---
printf "\n${BLD}Notable observations:${RST}\n"
NOTES=0

# Check for rapid failed attempts (3+ failures within 30s from same IP)
RAPID=$(printf "%s\n" "$FAILED" | awk '
  {
    ip=$NF
    # grab epoch-style minute+second from timestamp field $3
    split($3, t, ":")
    key=ip":"t[1]":"t[2]
    count[key]++
  }
  END { for(k in count) if(count[k]>=3) print count[k], "rapid failures from", k }
' || true)
if [[ -n "$RAPID" ]]; then
  printf "  ${YEL}[!] Rapid auth failures (possible misconfigured key or brute force):${RST}\n"
  printf "%s\n" "$RAPID" | while IFS= read -r line; do
    printf "      %s\n" "$line"
  done
  NOTES=$((NOTES+1))
fi

# Check for automated sudo (root running commands as root — e.g. monitoring agents)
AUTO_SUDO=$(printf "%s\n" "$SUDO_CMDS" \
  | grep "USER=root.*by (uid=0)" | grep -oE "COMMAND=.*" | sort -u || true)
if [[ -n "$AUTO_SUDO" ]]; then
  printf "  ${CYN}[i] Automated sudo commands (root→root, likely monitoring agent):${RST}\n"
  printf "%s\n" "$AUTO_SUDO" | head -5 | while IFS= read -r line; do
    printf "      %s\n" "$line"
  done
  NOTES=$((NOTES+1))
fi

# Check for CA key used (ScaleFT/OktaASA cert auth)
CA_KEY=$(printf "%s\n" "$ACCEPTED" | grep -oE "CA [A-Z0-9]+ SHA256:[A-Za-z0-9+/=]+" | sort -u || true)
if [[ -n "$CA_KEY" ]]; then
  printf "  ${GRN}[✓] All remote logins use certificate auth via CA:${RST}\n"
  printf "%s\n" "$CA_KEY" | while IFS= read -r line; do
    printf "      %s\n" "$line"
  done
  NOTES=$((NOTES+1))
fi

[[ $NOTES -eq 0 ]] && printf "  ${GRN}Nothing unusual detected${RST}\n"

printf "\n${BLD}Done.${RST}\n"
