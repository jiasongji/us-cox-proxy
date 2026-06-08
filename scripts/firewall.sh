#!/bin/sh
WL_FILE="/etc/proxy-whitelist/ips.conf"
ACC_CONF="/etc/microsocks/accounts.conf"
PROXY_CHAIN="PROXY_WL"
SSH_CHAIN="SSH_GUARD"

get_ports() {
    local PORTS=""
    [ -f "$ACC_CONF" ] || return
    while IFS=' ' read -r PORT U P; do
        [ -z "$PORT" ] && continue
        echo "$PORT" | grep -q '^#' && continue
        PORTS="${PORTS},${PORT}"
    done < "$ACC_CONF"
    printf '%s' "${PORTS#,}"
}

ssh_guard_on() {
    iptables -N "$SSH_CHAIN" 2>/dev/null; iptables -F "$SSH_CHAIN" 2>/dev/null
    iptables -A "$SSH_CHAIN" -p tcp --dport 22 -m recent --rcheck --seconds 1800 --rttl --name ssh_ban3 -j DROP
    iptables -A "$SSH_CHAIN" -p tcp --dport 22 -m recent --rcheck --seconds 1200 --rttl --name ssh_ban2 -m recent --set --name ssh_ban3 -j DROP
    iptables -A "$SSH_CHAIN" -p tcp --dport 22 -m recent --rcheck --seconds 600 --rttl --name ssh_ban1 -m recent --set --name ssh_ban2 -j DROP
    iptables -A "$SSH_CHAIN" -p tcp --dport 22 -m conntrack --ctstate NEW -m recent --set --name ssh_track
    iptables -A "$SSH_CHAIN" -p tcp --dport 22 -m conntrack --ctstate NEW -m recent --rcheck --seconds 60 --hitcount 8 --rttl --name ssh_track -m recent --set --name ssh_ban1 -j DROP
    iptables -A "$SSH_CHAIN" -p tcp --dport 22 -j ACCEPT
    iptables -C INPUT -j "$SSH_CHAIN" 2>/dev/null || iptables -I INPUT 1 -j "$SSH_CHAIN"
}
ssh_guard_off() { iptables -D INPUT -j "$SSH_CHAIN" 2>/dev/null; iptables -F "$SSH_CHAIN" 2>/dev/null; iptables -X "$SSH_CHAIN" 2>/dev/null; }
ssh_guard_status() { iptables -L "$SSH_CHAIN" -n 2>/dev/null | grep -q "ssh_track" && echo "ON" || echo "OFF"; }

wl_apply() {
    local PORTS=$(get_ports)
    [ -z "$PORTS" ] && return 1
    iptables -N "$PROXY_CHAIN" 2>/dev/null; iptables -F "$PROXY_CHAIN" 2>/dev/null
    local IPS=""
    [ -f "$WL_FILE" ] && IPS=$(grep -v '^#\|^$\|^[[:space:]]*#' "$WL_FILE" | tr -d ' ' | grep -E '^[0-9]')
    [ -z "$IPS" ] && { iptables -D INPUT -j "$PROXY_CHAIN" 2>/dev/null; return 0; }
    echo "$IPS" | while read ip; do
        [ -z "$ip" ] && continue
        iptables -A "$PROXY_CHAIN" -s "$ip" -p tcp -m multiport --dports "$PORTS" -j ACCEPT 2>/dev/null
    done
    iptables -A "$PROXY_CHAIN" -p tcp -m multiport --dports "$PORTS" -j DROP 2>/dev/null
    iptables -C INPUT -j "$PROXY_CHAIN" 2>/dev/null || iptables -A INPUT -j "$PROXY_CHAIN"
}
wl_off() { iptables -D INPUT -j "$PROXY_CHAIN" 2>/dev/null; iptables -F "$PROXY_CHAIN" 2>/dev/null; iptables -X "$PROXY_CHAIN" 2>/dev/null; }
wl_status() { iptables -L "$PROXY_CHAIN" -n 2>/dev/null | grep -qE "dpt|dports" && echo "ON" || echo "OFF"; }
wl_list() { [ -f "$WL_FILE" ] && grep -v '^#\|^$\|^[[:space:]]*#' "$WL_FILE" | tr -d ' ' | grep -E '^[0-9]'; }

case "$1" in
    ssh-on) ssh_guard_on ;; ssh-off) ssh_guard_off ;; ssh-status) ssh_guard_status ;;
    wl-apply) wl_apply ;; wl-off) wl_off ;; wl-status) wl_status ;; wl-list) wl_list ;;
    all-on) ssh_guard_on; wl_apply ;; all-off) wl_off; ssh_guard_off ;;
    status) echo "SSH: $(ssh_guard_status)"; echo "WL:  $(wl_status)" ;;
    *) echo "usage: $0 {ssh-on|ssh-off|ssh-status|wl-apply|wl-off|wl-status|wl-list|all-on|all-off|status}"; exit 1 ;;
esac
