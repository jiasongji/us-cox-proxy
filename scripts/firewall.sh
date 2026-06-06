#!/bin/sh
# ============================================================
#  US-COX 防火墙规则
#  1. 代理白名单 (SOCKS_PORT / HTTP_PORT) - 可选
#  2. SSH 防暴力破解 (端口 22) - 可选
# ============================================================

WL_FILE="/etc/proxy-whitelist/ips.conf"
PROXY_CHAIN="PROXY_WL"
SSH_CHAIN="SSH_GUARD"

# 从配置文件读取端口
load_ports() {
    local CONF="/etc/microsocks/config"
    [ -f "$CONF" ] && . "$CONF"
    SOCKS_PORT="${SOCKS_PORT:-25022}"
    HTTP_PORT="${HTTP_PORT:-25023}"
}

# ── SSH 防暴力破解 ──
# 阈值: 60秒内 8 次新连接 → 触发
# 惩罚: 5min → 10min → 20min → 30min 递增

ssh_guard_on() {
    iptables -N "$SSH_CHAIN" 2>/dev/null
    iptables -F "$SSH_CHAIN" 2>/dev/null

    # Level 3 → DROP 30min
    iptables -A "$SSH_CHAIN" -p tcp --dport 22 -m recent --rcheck --seconds 1800 --rttl --name ssh_ban3 -j DROP
    # Level 2 → 升级到 Level 3
    iptables -A "$SSH_CHAIN" -p tcp --dport 22 -m recent --rcheck --seconds 1200 --rttl --name ssh_ban2 -m recent --set --name ssh_ban3 -j DROP
    # Level 1 → 升级到 Level 2
    iptables -A "$SSH_CHAIN" -p tcp --dport 22 -m recent --rcheck --seconds 600 --rttl --name ssh_ban1 -m recent --set --name ssh_ban2 -j DROP

    # 记录新连接
    iptables -A "$SSH_CHAIN" -p tcp --dport 22 -m conntrack --ctstate NEW -m recent --set --name ssh_track
    # 60秒内 8 次 → ban Level 1
    iptables -A "$SSH_CHAIN" -p tcp --dport 22 -m conntrack --ctstate NEW \
        -m recent --rcheck --seconds 60 --hitcount 8 --rttl --name ssh_track \
        -m recent --set --name ssh_ban1 -j DROP

    # 放行正常 SSH
    iptables -A "$SSH_CHAIN" -p tcp --dport 22 -j ACCEPT

    iptables -C INPUT -j "$SSH_CHAIN" 2>/dev/null || iptables -I INPUT 1 -j "$SSH_CHAIN"
}

ssh_guard_off() {
    iptables -D INPUT -j "$SSH_CHAIN" 2>/dev/null
    iptables -F "$SSH_CHAIN" 2>/dev/null
    iptables -X "$SSH_CHAIN" 2>/dev/null
}

ssh_guard_status() {
    iptables -L "$SSH_CHAIN" -n 2>/dev/null | grep -q "ssh_track" && echo "ON" || echo "OFF"
}

# ── 代理白名单 ──

wl_apply() {
    load_ports
    iptables -N "$PROXY_CHAIN" 2>/dev/null
    iptables -F "$PROXY_CHAIN" 2>/dev/null

    IPS=""
    if [ -f "$WL_FILE" ]; then
        IPS=$(grep -v '^#\|^$\|^[[:space:]]*#' "$WL_FILE" | tr -d ' ' | grep -E '^[0-9]')
    fi

    if [ -z "$IPS" ]; then
        iptables -D INPUT -j "$PROXY_CHAIN" 2>/dev/null
        return 0
    fi

    echo "$IPS" | while read ip; do
        [ -z "$ip" ] && continue
        iptables -A "$PROXY_CHAIN" -s "$ip" -p tcp -m multiport --dports "$SOCKS_PORT,$HTTP_PORT" -j ACCEPT 2>/dev/null
    done
    iptables -A "$PROXY_CHAIN" -p tcp -m multiport --dports "$SOCKS_PORT,$HTTP_PORT" -j DROP 2>/dev/null

    iptables -C INPUT -j "$PROXY_CHAIN" 2>/dev/null || iptables -A INPUT -j "$PROXY_CHAIN"
}

wl_off() {
    iptables -D INPUT -j "$PROXY_CHAIN" 2>/dev/null
    iptables -F "$PROXY_CHAIN" 2>/dev/null
    iptables -X "$PROXY_CHAIN" 2>/dev/null
}

wl_status() {
    load_ports
    iptables -L "$PROXY_CHAIN" -n 2>/dev/null | grep -q "$SOCKS_PORT" && echo "ON" || echo "OFF"
}

wl_list() {
    if [ -f "$WL_FILE" ]; then
        grep -v '^#\|^$\|^[[:space:]]*#' "$WL_FILE" | tr -d ' ' | grep -E '^[0-9]'
    fi
}

case "$1" in
    ssh-on)    ssh_guard_on ;;
    ssh-off)   ssh_guard_off ;;
    ssh-status) ssh_guard_status ;;
    wl-apply)  wl_apply ;;
    wl-off)    wl_off ;;
    wl-status) wl_status ;;
    wl-list)   wl_list ;;
    all-on)    ssh_guard_on; wl_apply ;;
    all-off)   wl_off; ssh_guard_off ;;
    status)
        echo "SSH: $(ssh_guard_status)"
        echo "WL:  $(wl_status)"
        ;;
    *) echo "usage: $0 {ssh-on|ssh-off|ssh-status|wl-apply|wl-off|wl-status|wl-list|all-on|all-off|status}"; exit 1 ;;
esac
