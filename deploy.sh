#!/bin/sh
# ============================================================
#  US-COX 一键部署脚本
#  适用于: Alpine Linux 3.19 (LXC/NAT VPS)
#
#  用法:
#    ssh -p <端口> root@<IP> 'sh -s' < deploy.sh
#    或复制到 VPS 后直接运行: sh deploy.sh
# ============================================================

set -e

R='\033[0;31m' G='\033[0;32m' Y='\033[0;33m' C='\033[0;36m' B='\033[1m' N='\033[0m'

HOSTNAME="US-COX"
SOCKS_USER="uscox"
SOCKS_PASS=$(openssl rand -hex 8 2>/dev/null || cat /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 16)
SOCKS_PORT=1080
PUBLIC_IP="${1:-$(curl -s --connect-timeout 5 https://httpbin.org/ip 2>/dev/null | grep -o '"origin": *"[^"]*"' | cut -d'"' -f4)}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

printf "${C}${B}"
echo "╔══════════════════════════════════════════╗"
echo "║     US-COX VPS 一键部署                  ║"
echo "║     Alpine Linux 3.19 / LXC / NAT        ║"
echo "╚══════════════════════════════════════════╝"
printf "${N}\n"

# ── 1. 基础系统 ──

printf "${C}[1/6] 系统基础优化...${N}\n"
echo "$HOSTNAME" > /etc/hostname
hostname "$HOSTNAME" 2>/dev/null || true
grep -q "127.0.1.1.*$HOSTNAME" /etc/hosts || echo "127.0.1.1 $HOSTNAME" >> /etc/hosts

cat > /etc/resolv.conf << EOF
nameserver 1.1.1.1
nameserver 8.8.8.8
options ndots:5 attempts:2 timeout:1 rotate
EOF

cat > /etc/sysctl.conf << 'EOF'
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_max_tw_buckets = 2000
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 512
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_dsack = 1
net.ipv4.tcp_retries2 = 8
net.ipv4.tcp_early_retrans = 3
net.core.optmem_max = 32768
net.ipv4.tcp_rmem = 4096 32768 4194304
net.ipv4.tcp_wmem = 4096 16384 4194304
net.ipv4.udp_rmem_min = 2048
net.ipv4.udp_wmem_min = 2048
net.ipv4.ip_local_port_range = 1024 65535
net.core.somaxconn = 2048
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF
sysctl -p 2>/dev/null || true
printf "  ${G}✔${N} 主机名、DNS、sysctl\n"

# ── 2. 日志精简 ──

printf "${C}[2/6] 日志精简...${N}\n"
cat > /etc/conf.d/syslog << 'EOF'
SYSLOGD_OPTS="-t -D -l warning"
KLOGD_OPTS="-c 3"
EOF
cat > /etc/logrotate.conf << 'EOF'
daily
rotate 1
create
compress
delaycompress
missingok
notifempty
minsize 100k
maxsize 1M
tabooext + .apk-new
include /etc/logrotate.d
EOF
rc-service syslog restart >/dev/null 2>&1 || true
printf "  ${G}✔${N} syslog/logrotate\n"

# ── 3. SSH 加固 ──

printf "${C}[3/6] SSH 加固...${N}\n"
cat > /etc/ssh/sshd_config << 'EOF'
Port 22
ListenAddress 0.0.0.0
HostKey /etc/ssh/ssh_host_ed25519_key
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org
Ciphers chacha20-poly1305@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
PermitRootLogin yes
PasswordAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
MaxSessions 3
LoginGraceTime 30
ClientAliveInterval 60
ClientAliveCountMax 3
TCPKeepAlive yes
AllowTcpForwarding no
GatewayPorts no
X11Forwarding no
PermitTunnel no
AllowAgentForwarding no
PermitUserEnvironment no
Compression no
UseDNS no
SyslogFacility AUTH
LogLevel INFO
AcceptEnv LANG LC_*
Subsystem sftp internal-sftp
EOF
mkdir -p /root/.ssh
: > /root/.ssh/authorized_keys
chmod 700 /root/.ssh
chmod 600 /root/.ssh/authorized_keys
rc-service sshd restart >/dev/null 2>&1 || true
printf "  ${G}✔${N} SSH 配置\n"

# ── 4. Microsocks ──

printf "${C}[4/6] 编译安装 Microsocks...${N}\n"
apk add --no-cache build-base git >/dev/null 2>&1
TMPD=$(mktemp -d); cd "$TMPD"
git clone --depth 1 https://github.com/rofl0r/microsocks.git . >/dev/null 2>&1
make -j1 >/dev/null 2>&1
strip microsocks
cp microsocks /usr/local/bin/microsocks
chmod 755 /usr/local/bin/microsocks
cd /; rm -rf "$TMPD"

mkdir -p /etc/microsocks
cat > /etc/microsocks/config << EOF
SOCKS_USER="$SOCKS_USER"
SOCKS_PASS="$SOCKS_PASS"
SOCKS_PORT="$SOCKS_PORT"
EOF
chmod 600 /etc/microsocks/config

cat > /etc/init.d/microsocks << 'EOF'
#!/sbin/openrc-run
name="microsocks"
description="Lightweight SOCKS5 Proxy"
command="/usr/local/bin/microsocks"
command_background="yes"
pidfile="/run/${name}.pid"
start_stop_daemon_args="--make-pidfile"
depend() { need net; after firewall; }
start_pre() {
    local CONF="/etc/microsocks/config"
    local PORT USER PASS
    PORT=$(grep "^SOCKS_PORT=" "$CONF" 2>/dev/null | cut -d'"' -f2)
    USER=$(grep "^SOCKS_USER=" "$CONF" 2>/dev/null | cut -d'"' -f2)
    PASS=$(grep "^SOCKS_PASS=" "$CONF" 2>/dev/null | cut -d'"' -f2)
    : ${PORT:=1080}; : ${USER:=uscox}; : ${PASS:=changeme}
    command_args="-q -p ${PORT} -u ${USER} -P ${PASS}"
}
EOF
chmod 755 /etc/init.d/microsocks
rc-update add microsocks default >/dev/null 2>&1
rc-service microsocks start >/dev/null 2>&1
printf "  ${G}✔${N} Microsocks SOCKS5 → 端口 %s\n" "$SOCKS_PORT"

# ── 5. 防火墙 ──

printf "${C}[5/6] 部署防火墙...${N}\n"
apk add --no-cache iptables >/dev/null 2>&1
mkdir -p /etc/proxy-whitelist

cat > /etc/proxy-whitelist/ips.conf << 'EOF'
# US-COX 代理白名单
# 每行一个 IP 或 CIDR, # 开头为注释
# 留空 = 允许所有 IP 连接
EOF

if [ -f "$SCRIPT_DIR/scripts/firewall.sh" ]; then
    cp "$SCRIPT_DIR/scripts/firewall.sh" /etc/proxy-whitelist/firewall.sh
fi
chmod +x /etc/proxy-whitelist/firewall.sh 2>/dev/null
/bin/sh /etc/proxy-whitelist/firewall.sh ssh-on 2>/dev/null || true
printf "  ${G}✔${N} iptables + SSH 防暴力\n"

# ── 6. 管理脚本 ──

printf "${C}[6/6] 安装管理脚本...${N}\n"
if [ -f "$SCRIPT_DIR/scripts/socks" ]; then
    cp "$SCRIPT_DIR/scripts/socks" /usr/local/bin/socks
fi
chmod +x /usr/local/bin/socks 2>/dev/null

apk del build-base git >/dev/null 2>&1 || true
rm -rf /var/cache/apk/* /root/.cache/* /tmp/*

crontab - << CRON
*/15	*	*	*	*	run-parts /etc/periodic/15min
0	*	*	*	*	run-parts /etc/periodic/hourly
0	2	*	*	*	run-parts /etc/periodic/daily
0	3	*	*	6	run-parts /etc/periodic/weekly
0	5	1	*	*	run-parts /etc/periodic/monthly
0 0 */3 * * rm -rf /var/log/journal 2>/dev/null; truncate -s 0 /var/log/messages.0 /var/log/messages.1 /var/log/wtmp 2>/dev/null
* * * * * /bin/sh /usr/local/bin/socks health-cron
CRON

printf "  ${G}✔${N} socks 管理脚本 + cron\n"

# ── 完成 ──

printf "\n"
printf "${C}${B}╔══════════════════════════════════════════╗${N}\n"
printf "${C}${B}║${N}  ${G}✔ 部署完成!${N}                              ${C}${B}║${N}\n"
printf "${C}${B}╠══════════════════════════════════════════╣${N}\n"
printf "${C}${B}║${N}  SOCKS5:  ${G}%s:%s@%s:%s${N}          ${C}${B}║${N}\n" "$SOCKS_USER" "$SOCKS_PASS" "${PUBLIC_IP:-<公网IP>}" "$SOCKS_PORT"
printf "${C}${B}║${N}                                          ${C}${B}║${N}\n"
printf "${C}${B}║${N}  ${Y}请立即保存以上信息!${N}                    ${C}${B}║${N}\n"
printf "${C}${B}║${N}  ${D}登录后输入 socks 进入管理面板${N}            ${C}${B}║${N}\n"
printf "${C}${B}║${N}                                          ${C}${B}║${N}\n"
printf "${C}${B}╚══════════════════════════════════════════╝${N}\n"
