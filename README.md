# US-COX 代理服务器部署方案

> 面向低配 NAT VPS（Alpine Linux / LXC / 200MB RAM）的轻量级多账号 SOCKS5 代理管理方案。

## 特性

| 组件 | 程序 | 内存/实例 | 说明 |
|------|------|-----------|------|
| SOCKS5 代理 | [Microsocks](https://github.com/rofl0r/microsocks) | ~600 KB | 18KB 二进制，epoll 单线程 |
| 防火墙 | iptables | 0 | 白名单 + SSH 防暴力 |
| 管理面板 | socks 脚本 | 0 | Shell 交互菜单，多账号 CRUD |

**支持多账号：每个端口独立用户名/密码，增删改查。**

## 快速部署

```bash
git clone https://github.com/jiasongji/us-cox-proxy.git
cd us-cox-proxy
ssh -p <SSH端口> root@<IP> 'sh -s' < deploy.sh
```

部署完成后登录：
```
ssh -i ~/.ssh/us-cox/id_ed25519 -p <SSH端口> root@<IP>
socks    # 进入管理面板
```

## 管理面板

```
==========================================
  US-COX 代理管理 v7.1
==========================================

  1) 服务管理
  2) SOCKS5 账号
  3) 防火墙
  4) 维护工具
```

### SOCKS5 账号管理

```
  ##   端口   用户         密码               状态
  --------------------------------------------
  1    25022  用户A        xxxxx...        运行
  2    25023  guest        abc123...          运行

  1) 添加账号
  2) 删除 (选序号)
  3) 改用户名 (选序号)
  4) 改密码   (选序号)
  5) 随机密码 (选序号)
  6) 连接信息 (选序号)
```

### 命令行

```bash
socks status     # 查看所有账号状态
socks start      # 启动全部
socks stop       # 停止全部
socks restart    # 重启全部
socks health     # 健康检查
socks update     # 更新 Microsocks
```

## 多账号

配置文件 `/etc/microsocks/accounts.conf`：

```
# 端口 用户 密码
1080 user1 pass1
1081 user2 pass2
```

每个账号 = 一个独立的 Microsocks 进程，占用 ~600KB 内存。

管理面板支持：添加 / 删除 / 改用户名 / 改密码 / 随机生成密码 / 查看连接信息

## 安全

### SSH：公钥登录（密码已禁用）

- `PasswordAuthentication no`
- 仅 Ed25519 公钥认证
- 私钥路径：`~/.ssh/us-cox/id_ed25519`

### 防火墙

**代理白名单（所有 SOCKS5 端口）：**
- 白名单为空 = 允许所有 IP 连接
- 添加 IP 后启用 = 仅白名单 IP 可用代理
- SSH 端口不受白名单影响

**SSH 防暴力破解：**
- 阈值：60 秒内 8 次新连接 → 触发
- 惩罚递增：5min → 10min → 20min → 30min
- `--rttl` TTL 校验防止 NAT 误判

## 项目结构

```
us-cox-proxy/
├── README.md
├── LICENSE
├── deploy.sh                      # 一键部署
├── scripts/
│   ├── socks                      # 管理面板 v7.1 → /usr/local/bin/socks
│   └── firewall.sh                # 防火墙引擎
├── init.d/
│   └── microsocks                 # 多实例 OpenRC 服务
└── config/                        # 配置模板
    ├── accounts.conf.example      # 多账号模板
    ├── ips.conf.example           # 白名单模板
    ├── sshd_config                # SSH (公钥登录, 密码禁用)
    ├── sysctl.conf                # 内核网络优化
    ├── crontab.example            # 健康检查 + 日志清理
    ├── syslog.conf                # 日志精简
    ├── logrotate.conf             # 日志轮替
    ├── resolv.conf                # DNS
    ├── profile                    # 全局 Profile
    ├── bash.bashrc                # Bashrc
    ├── motd                       # 登录横幅
    ├── hostname                   # 主机名
    └── hosts                      # Hosts
```

## 系统优化清单

### 网络参数 (sysctl)
- BBR 拥塞控制 + TCP Fast Open
- TCP Keepalive 5 分钟 (适配 NAT 超时)
- TIME_WAIT 复用 + 端口范围 1024-65535
- ICMP 重定向阻断 + 反 IP 欺骗
- IPv6 禁用

### 安全加固
- SSH Ed25519 公钥登录，密码登录已禁用
- SSH `MaxAuthTries 3` + `UseDNS no`
- SSH 仅 ChaCha20/AES-GCM 加密
- PVE 后门密钥已清除
- 商家脚本/品牌信息已清除

### 磁盘优化
- Syslog 仅记录 warning 级别
- Logrotate 每日轮替，保留 1 份，最大 1MB
- Crontab 每 3 天清理旧日志
- 卸载不必要包（ruby/python/nano/figlet 等）
- 磁盘占用：**77MB / 625MB (14%)**

### 自动保活
- Cron 每分钟检测代理进程，崩溃自动拉起

## 版本历史

| 版本 | 变更 |
|------|------|
| v7.1 | 简洁界面（去侧边框）+ 序号操作 + BusyBox 兼容 |
| v7 | 多账号 SOCKS5 管理（增删改查） |
| v6 | 移除 HTTP 代理，仅保留 SOCKS5 |
| v5 | 增强连接信息展示，防火墙独立 |
| v4 | 两级菜单管理面板 |
| v1-v3 | 初始部署，安全审计，系统优化 |

## 适用环境

- Alpine Linux 3.19 (LXC/Incus 容器)
- 1 CPU / 200MB RAM / 625MB 磁盘
- NAT VPS (共享宿主机，有限端口映射)

## License

MIT
