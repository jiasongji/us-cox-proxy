# US-COX 代理服务器部署方案

> 面向低配 NAT VPS（Alpine Linux / LXC / 200MB RAM）的轻量级多账号 SOCKS5 代理管理方案。

## 特性

| 组件 | 程序 | 内存/实例 | 说明 |
|------|------|-----------|------|
| SOCKS5 代理 | [Microsocks](https://github.com/rofl0r/microsocks) | ~600 KB | 18KB 二进制，epoll 单线程 |
| 防火墙 | iptables | 0 | 白名单 + SSH 防暴力 |
| 管理面板 | socks 脚本 | 0 | Shell 交互菜单 |

**支持多账号：每个端口独立用户名/密码，增删改查。**

## 快速部署

```bash
git clone https://github.com/yourname/us-cox-proxy.git
cd us-cox-proxy
ssh -p <SSH端口> root@<IP> 'sh -s' < deploy.sh
```

## 管理面板

```
+------------------------------------------+
|  US-COX  代理管理  v7                    |
+------------------------------------------+
|  [ 1 ] 服务管理                          |
|  [ 2 ] SOCKS5 账号                       |
|  [ 3 ] 防火墙                            |
|  [ 4 ] 维护工具                          |
+------------------------------------------+

SOCKS5 账号管理:
  端口    用户       密码            状态
  25022   uscox      b3be44ed...     * 运行
  25023   guest      abc123...       * 运行

  1) 添加账号  2) 删除账号  3) 修改用户名
  4) 修改密码  5) 随机生成  6) 查看连接信息
```

**所有子菜单按回车即可返回上级。**

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
# 端口 用户名 密码
1080 user1 pass1
1081 user2 pass2
```

每个账号 = 一个独立的 Microsocks 进程，占用 ~600KB 内存。

通过 `socks` 管理面板的 SOCKS5 菜单可以：
- **添加**：指定端口、用户名、密码（或自动生成）
- **删除**：选择端口删除
- **修改**：修改用户名或密码
- **查看**：显示完整的连接信息（curl/环境变量/SwitchyOmega）

## 防火墙

### 代理白名单 (所有 SOCKS5 端口)

- 白名单为空 = 允许所有 IP 连接
- 添加 IP 后启用 = 仅白名单 IP 可用代理
- SSH 端口 **不受白名单影响**

### SSH 防暴力破解

- 阈值：60 秒内 8 次新连接 → 触发
- 惩罚递增：5min → 10min → 20min → 30min

## 项目结构

```
us-cox-proxy/
├── README.md
├── LICENSE
├── deploy.sh                  # 一键部署
├── scripts/
│   ├── socks                  # 管理面板 → /usr/local/bin/socks
│   └── firewall.sh            # 防火墙引擎
├── init.d/
│   └── microsocks             # 多实例 OpenRC 服务
└── config/                    # 配置模板
```

## 适用环境

- Alpine Linux 3.19 (LXC/Incus 容器)
- 1 CPU / 200MB RAM / 625MB 磁盘
- NAT VPS (共享宿主机，有限端口映射)

## License

MIT
