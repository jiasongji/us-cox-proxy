# US-COX 代理服务器部署方案

> 一套面向低配 NAT VPS（Alpine Linux / LXC / 200MB RAM）的轻量级 SOCKS5 代理管理方案。

## 特性

| 组件 | 程序 | 内存 | 说明 |
|------|------|------|------|
| SOCKS5 代理 | [Microsocks](https://github.com/rofl0r/microsocks) | ~600 KB | 18KB 二进制，epoll 单线程 |
| 防火墙 | iptables | 0 | 白名单 + SSH 防暴力 |
| 管理面板 | socks 脚本 | 0 | Shell 交互菜单 |

**总资源占用：磁盘 ~77MB，内存 ~600KB，空闲 CPU 0%**

## 快速部署

```bash
git clone https://github.com/yourname/us-cox-proxy.git
cd us-cox-proxy

# 一键部署
ssh -p <SSH端口> root@<IP> 'sh -s' < deploy.sh
```

## 管理面板

```
╔══════════════════════════════════════════╗
║  US-COX  代理管理  v6                    ║
╠══════════════════════════════════════════╣
║  [ 1 ] 服务管理                          ║
║  [ 2 ] SOCKS5 代理                       ║
║  [ 3 ] 防火墙                            ║
║  [ 4 ] 维护工具                          ║
╚══════════════════════════════════════════╝
```

**所有子菜单按回车即可返回上级。**

### 命令行速查

```bash
socks status     # 查看状态
socks start      # 启动
socks stop       # 停止
socks restart    # 重启
socks health     # 健康检查
socks update     # 更新 Microsocks
```

## 端口规划

| 端口 | 服务 | 说明 |
|------|------|------|
| &lt;SSH端口&gt; | SSH | 远程管理（由 NAT 映射） |
| &lt;SOCKS5端口&gt; | SOCKS5 | Microsocks 代理 |

## 防火墙

### 代理白名单 (SOCKS5 端口)

- 白名单为空 = 允许所有 IP 连接
- 添加 IP 后启用 = 仅白名单 IP 可用代理
- SSH 端口 **不受白名单影响**

```bash
socks → [3] 防火墙 → [2] 添加 IP → 输入 IP → [5] 启用
```

### SSH 防暴力破解

- 阈值：60 秒内 8 次新连接 → 触发封禁
- 惩罚递增：5min → 10min → 20min → 30min

## 项目结构

```
us-cox-proxy/
├── README.md                  # 本文件
├── LICENSE                    # MIT
├── deploy.sh                  # 一键部署脚本
├── scripts/
│   ├── socks                  # 管理面板脚本 → /usr/local/bin/socks
│   └── firewall.sh            # 防火墙引擎 → /etc/proxy-whitelist/
├── init.d/
│   └── microsocks             # SOCKS5 服务 → /etc/init.d/
└── config/
    ├── sysctl.conf            # 内核网络参数
    ├── sshd_config            # SSH 安全配置
    ├── profile                # 全局 Profile
    ├── bash.bashrc            # Bashrc
    ├── resolv.conf            # DNS 配置
    ├── syslog.conf            # Syslog 精简
    ├── logrotate.conf         # 日志轮替
    ├── motd                   # 登录横幅
    ├── hostname               # 主机名
    ├── hosts                  # Hosts
    ├── microsocks.config.example   # SOCKS5 配置模板
    ├── ips.conf.example            # 白名单模板
    └── crontab.example             # 定时任务模板
```

## 系统优化清单

### 网络参数 (sysctl)
- BBR 拥塞控制 + TCP Fast Open
- TCP Keepalive 5 分钟 (适配 NAT 超时)
- TIME_WAIT 复用 + 端口范围 1024-65535
- 禁用慢启动重启
- ICMP 重定向阻断 + 反 IP 欺骗

### 安全加固
- SSH 仅 Ed25519 + ChaCha20/AES-GCM
- SSH `MaxAuthTries 3` + `UseDNS no`
- IPv6 禁用（NAT 无 IPv6）

### 磁盘优化
- Syslog 仅记录 warning 级别
- Logrotate 每日轮替，保留 1 份，最大 1MB
- Crontab 每 3 天清理旧日志
- 最终磁盘占用：**77MB / 625MB (14%)**

### 自动保活
- Cron 每分钟检测代理进程，崩溃自动拉起

## 适用环境

- Alpine Linux 3.19 (LXC/Incus 容器)
- 1 CPU / 200MB RAM / 625MB 磁盘
- NAT VPS (共享宿主机，有限端口映射)

## License

MIT
