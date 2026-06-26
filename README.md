# RemnaNode Panel

> Remnawave Node 自动化部署与维护命令行面板  
> Automated CLI panel for deploying and maintaining Remnawave Node servers.

适用场景：低配 Debian 13 双栈节点机，例如 `1C / 1G RAM / 10G SSD`，用于部署和维护 Remnawave Node + Xray 节点。

本项目的目标不是替代 Remnawave Panel，而是让节点机部署、重装、删除、维护、防火墙、自修复、备份等操作尽量自动化，减少重复手工替换配置的痛苦。

当前版本：`v0.1.1`

---

## 本次修复 / v0.1.1

### 修复内容

修复全新 Debian 节点上安装 Docker 时可能遇到的 dpkg 锁问题：

```text
E: Could not get lock /var/lib/dpkg/lock-frontend. It is held by process ... unattended-upgr
```

原因通常是新服务器刚启动后，系统自带的 `unattended-upgrades` 正在自动安装安全更新，占用了 apt/dpkg 锁。**不能删除 lock 文件**，否则可能破坏 dpkg 数据库。

v0.1.1 已加入：

```text
apt/dpkg 锁检测
锁持有进程显示
安全等待，不删除 lock 文件
apt 操作自动重试
dpkg --configure -a / apt-get -f install 修复尝试
可通过环境变量调整等待时间
```

默认最多等待：

```text
APT_LOCK_WAIT_SECONDS=1800
```

也就是 30 分钟。需要更久可以这样运行：

```bash
APT_LOCK_WAIT_SECONDS=3600 remnanode-panel install
```

---

## 目录 / Table of Contents

- [本次修复 / v0.1.1](#本次修复--v011)
- [特性](#特性)
- [安全边界](#安全边界)
- [系统要求](#系统要求)
- [快速安装：新服务器无 git 推荐方式](#快速安装新服务器无-git-推荐方式)
- [备用安装方式：wget](#备用安装方式wget)
- [开发者安装方式：git clone](#开发者安装方式git-clone)
- [首次使用流程](#首次使用流程)
- [面板功能树](#面板功能树)
- [配置文件与敏感信息](#配置文件与敏感信息)
- [端口说明](#端口说明)
- [Cloudflare DNS 要求](#cloudflare-dns-要求)
- [常用命令](#常用命令)
- [维护建议](#维护建议)
- [备份与恢复](#备份与恢复)
- [卸载与重装](#卸载与重装)
- [故障排查](#故障排查)
- [Windows PowerShell 推送更新到 GitHub](#windows-powershell-推送更新到-github)
- [English Quick Start](#english-quick-start)
- [免责声明](#免责声明)

---

## 特性

- 中 / 英双语界面。
- 新服务器不要求预装 `git`。
- 支持交互式初始化，不需要手工批量替换占位符。
- 自动保存节点配置到本地受保护配置文件。
- 支持一条龙安装 Docker、Docker Compose plugin、Remnawave Node。
- 支持导入 Remnawave Panel 生成的 `docker-compose.yml`。
- 支持 IPv4 / IPv6 双栈防火墙。
- 不修改 SSH 配置，只在防火墙中保留当前 SSH 端口。
- `NODE_PORT` 只允许主控机 IPv4 / IPv6 访问。
- Xray REALITY 入口端口对公网开放。
- 低配机器保护：Docker 日志限制、journald 限制、logrotate、可选 swap、安全清理、自修复。
- apt/dpkg 锁安全等待与重试，不删除 lock 文件。
- 支持健康检查、自修复、备份、恢复、日志查看、重装、删除。

---

## 安全边界

本面板只负责节点机自动化部署和维护，不负责主控机 Remnawave Panel 的部署。

节点机安全模型：

```text
允许：
  SSH 当前端口
  MAIN_IPV4 -> NODE_PORT/tcp
  MAIN_IPV6 -> NODE_PORT/tcp
  public -> XRAY_REALITY_PORT/tcp

拒绝：
  其他所有入站连接
```

重要说明：

1. 本项目不会修改 `/etc/ssh/sshd_config`。
2. 本项目不会修改 SSH 端口。
3. 本项目会检测当前 SSH 连接和 sshd 监听端口，并在防火墙中保留。
4. `NODE_PORT` 是 Remnawave Panel 连接 Remnawave Node 的内部 API 端口，不应该对公网开放。
5. 节点域名必须是 Cloudflare `DNS only`，不要开启橙云代理。

---

## 系统要求

推荐环境：

```text
OS: Debian 13
User: root
CPU: 1 core or higher
RAM: 1 GB or higher
Disk: 10 GB SSD or higher
Network: IPv4 + IPv6 dual stack
```

最低建议：

```text
1C / 1G RAM / 10G SSD
```

新服务器至少需要能使用：

```bash
apt-get
bash
```

如果服务器没有 `curl`、`wget`、`git`，没有关系，推荐安装命令会先用 `apt-get` 安装必要依赖。

---

## 快速安装：新服务器无 git 推荐方式

适用于全新 Debian 13 节点机。

> 该方式不要求服务器预装 git。

```bash
apt-get update && apt-get install -y ca-certificates curl bash

RAW_BASE="https://raw.githubusercontent.com/xpan5201/RemnaNode-Panel"
INSTALL_PATH="/usr/local/bin/remnanode-panel"

for BRANCH in main master; do
  if curl -fsSL "${RAW_BASE}/${BRANCH}/remnanode-panel.sh" -o "${INSTALL_PATH}"; then
    echo "Downloaded from branch: ${BRANCH}"
    chmod +x "${INSTALL_PATH}"
    break
  fi
done

test -x "${INSTALL_PATH}" || {
  echo "Download failed. Please check repository branch or network."
  exit 1
}

remnanode-panel
```

如果你只想先下载到当前目录测试：

```bash
apt-get update && apt-get install -y ca-certificates curl bash

RAW_BASE="https://raw.githubusercontent.com/xpan5201/RemnaNode-Panel"

for BRANCH in main master; do
  if curl -fsSL "${RAW_BASE}/${BRANCH}/remnanode-panel.sh" -o ./remnanode-panel.sh; then
    echo "Downloaded from branch: ${BRANCH}"
    chmod +x ./remnanode-panel.sh
    break
  fi
done

./remnanode-panel.sh
```

---

## 备用安装方式：wget

```bash
apt-get update && apt-get install -y ca-certificates wget bash

RAW_BASE="https://raw.githubusercontent.com/xpan5201/RemnaNode-Panel"
INSTALL_PATH="/usr/local/bin/remnanode-panel"

for BRANCH in main master; do
  if wget -qO "${INSTALL_PATH}" "${RAW_BASE}/${BRANCH}/remnanode-panel.sh"; then
    echo "Downloaded from branch: ${BRANCH}"
    chmod +x "${INSTALL_PATH}"
    break
  fi
done

test -x "${INSTALL_PATH}" || {
  echo "Download failed. Please check repository branch or network."
  exit 1
}

remnanode-panel
```

---

## 开发者安装方式：git clone

该方式只适合已经安装 `git` 的服务器，或者你想参与开发、提交 PR、查看完整仓库内容时使用。

```bash
apt-get update && apt-get install -y git ca-certificates bash

git clone https://github.com/xpan5201/RemnaNode-Panel.git
cd RemnaNode-Panel

chmod +x remnanode-panel.sh
./remnanode-panel.sh
```

安装为系统命令：

```bash
chmod +x install.sh
./install.sh

remnanode-panel
```

---

## 首次使用流程

推荐顺序：

```text
1. 在 Remnawave Panel 创建节点
2. 记录 Node Port
3. 复制 Panel 生成的 docker-compose.yml
4. 在节点机安装并运行 remnanode-panel
5. 选择语言
6. 进入 Initial configuration wizard / 初始配置
7. 输入主控 IPv4 / IPv6、节点域名、端口等信息
8. 导入 docker-compose.yml
9. 执行 One-click install or update / 一条龙安装或更新
10. 回到 Remnawave Panel 检查节点在线
```

---

## 面板功能树

```text
RemnaNode Panel
├── 1. Initial configuration wizard / 初始配置
├── 2. One-click install or update / 一条龙安装或更新
├── 3. Reinstall / 重装
├── 4. Delete or uninstall / 删除或卸载
├── 5. View or change information / 查看或修改信息
├── 6. Maintenance / 维护
│   ├── 1. Health report / 健康报告
│   ├── 2. Self-repair / 自修复
│   ├── 3. Safe cleanup / 安全清理
│   ├── 4. Backup / 备份
│   ├── 5. Restore latest backup / 恢复最新备份
│   ├── 6. Update Remnawave Node / 更新节点
│   ├── 7. Show logs / 查看日志
│   ├── 8. Reapply firewall / 重应用防火墙
│   └── 9. Back / 返回
├── 7. Import docker-compose.yml / 导入 compose
└── 8. Exit / 退出
```

---

## 配置文件与敏感信息

面板会把本机节点配置保存到：

```text
/etc/remnanode-panel/config.env
```

权限：

```text
600
```

Remnawave Panel 生成的节点 compose 文件保存到：

```text
/opt/remnanode/docker-compose.yml
```

它可能包含节点密钥，不能公开。

请不要上传以下内容到 GitHub：

```text
/etc/remnanode-panel/config.env
/opt/remnanode/docker-compose.yml
/opt/remnanode/backups/
/var/log/remnanode/
/var/log/remnanode-panel/
```

推荐 `.gitignore`：

```gitignore
config.env
docker-compose.yml
*.bak
*.backup
*.tar
*.tar.gz
*.tar.zst
.env
secrets/
backups/
logs/
```

---

## 端口说明

默认建议：

```text
NODE_PORT=2222
XRAY_REALITY_PORT=443
```

| 端口 | 用途 | 访问范围 |
|---|---|---|
| SSH 当前端口 | 服务器管理 | 保持原样 |
| NODE_PORT | Remnawave Panel 连接 Node 的内部 API | 仅允许主控 IPv4 / IPv6 |
| XRAY_REALITY_PORT | 用户连接 Xray REALITY 入站 | 公网 IPv4 / IPv6 |

不要把 `NODE_PORT` 和 `XRAY_REALITY_PORT` 设置成同一个端口。

---

## Cloudflare DNS 要求

节点域名必须使用 `DNS only`。

示例：

```text
us01.example.com A     <NODE_IPV4>  DNS only
us01.example.com AAAA  <NODE_IPV6>  DNS only
```

不要开启橙云代理。

---

## 常用命令

```bash
remnanode-panel              # 启动面板
remnanode-panel init         # 初始化配置
remnanode-panel install      # 一条龙安装或更新
remnanode-panel health       # 健康检查
remnanode-panel repair       # 自修复
remnanode-panel cleanup      # 安全清理
remnanode-panel backup       # 备份
remnanode-panel restore      # 恢复最新备份
remnanode-panel update       # 更新节点容器
remnanode-panel firewall     # 重应用防火墙
remnanode-panel logs         # 查看日志
remnanode-panel uninstall    # 卸载
remnanode-panel --help       # 帮助
```

---

## 维护建议

低配节点建议：

```text
Docker 日志限制：20m x 3
journald 限制：128M
swap：512M
备份保留：3 ~ 7 份
日志保留：7 ~ 14 天
```

日常维护频率：

```text
每天：
  查看 Remnawave Panel 节点在线状态

每周：
  remnanode-panel health
  remnanode-panel cleanup

更新前：
  remnanode-panel backup

异常后：
  remnanode-panel repair
  remnanode-panel logs
```

---

## 备份与恢复

创建备份：

```bash
remnanode-panel backup
```

恢复最新备份：

```bash
remnanode-panel restore
```

注意：恢复操作可能覆盖当前节点配置。恢复前请确认你确实要回退到最近一次备份状态。

---

## 卸载与重装

重装：

```bash
remnanode-panel reinstall
```

卸载：

```bash
remnanode-panel uninstall
```

卸载前建议先执行：

```bash
remnanode-panel backup
```

---

## 故障排查

### 1. apt/dpkg 锁被 unattended-upgrades 占用

现象：

```text
E: Could not get lock /var/lib/dpkg/lock-frontend. It is held by process ... unattended-upgr
```

v0.1.1 起，脚本会自动等待锁释放，不会删除 lock 文件。

手动查看：

```bash
ps -ef | grep -E 'apt|dpkg|unattended' | grep -v grep
systemctl status unattended-upgrades --no-pager
```

耐心等待即可。不要执行：

```bash
rm -f /var/lib/dpkg/lock-frontend
rm -f /var/lib/dpkg/lock
```

如果等待时间不够：

```bash
APT_LOCK_WAIT_SECONDS=3600 remnanode-panel install
```

### 2. 命令不存在

```bash
which remnanode-panel
```

如果没有输出，重新安装：

```bash
apt-get update && apt-get install -y ca-certificates curl bash

curl -fsSL https://raw.githubusercontent.com/xpan5201/RemnaNode-Panel/main/remnanode-panel.sh \
  -o /usr/local/bin/remnanode-panel

chmod +x /usr/local/bin/remnanode-panel

remnanode-panel
```

如果仓库默认分支不是 `main`，把 `main` 改成 `master`。

### 3. Panel 显示节点离线

在主控机测试：

```bash
nc -vz -4 <NODE_DOMAIN> <NODE_PORT>
nc -vz -6 <NODE_DOMAIN> <NODE_PORT>
```

在节点机检查：

```bash
remnanode-panel health
remnanode-panel logs
remnanode-panel firewall
```

常见原因：

```text
MAIN_IPV4 / MAIN_IPV6 写错
NODE_PORT 与 Remnawave Panel 中不一致
docker-compose.yml 不是从对应节点复制的
服务商安全组没放行 NODE_PORT
IPv6 路由不可用
```

### 4. 用户连不上节点 443

检查 DNS：

```bash
dig +short A <NODE_DOMAIN>
dig +short AAAA <NODE_DOMAIN>
```

检查端口：

```bash
nc -vz -4 <NODE_DOMAIN> 443
nc -vz -6 <NODE_DOMAIN> 443
```

节点机检查：

```bash
ss -lntup | grep ':443'
remnanode-panel logs
```

常见原因：

```text
Cloudflare 节点域名开了橙云
XRAY_REALITY_PORT 配置错误
REALITY 参数错误
Xray 没有正常启动
服务商安全组没放行 443/tcp
```

### 5. 磁盘快满

```bash
df -h
du -xh /var/lib/docker --max-depth=1 2>/dev/null | sort -h
du -xh /var/log --max-depth=1 2>/dev/null | sort -h
```

执行：

```bash
remnanode-panel cleanup
```

### 6. 内存不足

```bash
free -h
swapon --show
```

如果没有 swap，重新进入面板并启用 swap：

```bash
remnanode-panel
```

---

## Windows PowerShell 推送更新到 GitHub

本节用于你以后在 Windows PowerShell 里把修复后的文件推送到仓库：

```text
https://github.com/xpan5201/RemnaNode-Panel.git
```

### 1. 克隆仓库

```powershell
git clone https://github.com/xpan5201/RemnaNode-Panel.git
cd RemnaNode-Panel
```

如果已经克隆过：

```powershell
cd RemnaNode-Panel
git pull
```

### 2. 覆盖文件

假设你从 ChatGPT 下载的文件在 Windows 下载目录：

```powershell
Copy-Item "$env:USERPROFILE\Downloads\remnanode-panel.sh" ".\remnanode-panel.sh" -Force
Copy-Item "$env:USERPROFILE\Downloads\README.md" ".\README.md" -Force
```

如果下载的 README 文件名是 `README_RemnaNode-Panel.md`：

```powershell
Copy-Item "$env:USERPROFILE\Downloads\README_RemnaNode-Panel.md" ".\README.md" -Force
```

### 3. 检查差异

```powershell
git status
git diff -- remnanode-panel.sh README.md
```

确认没问题后提交：

```powershell
git add remnanode-panel.sh README.md
git commit -m "fix: wait for apt dpkg lock during install"
```

### 4. 推送到当前分支

推荐写法：

```powershell
git push origin HEAD
```

如果你明确知道分支是 `main`：

```powershell
git push origin main
```

如果分支是 `master`：

```powershell
git push origin master
```

查看当前分支：

```powershell
git branch --show-current
```

### 5. 在新节点上拉取最新脚本

新节点无 git 推荐：

```bash
apt-get update && apt-get install -y ca-certificates curl bash
curl -fsSL https://raw.githubusercontent.com/xpan5201/RemnaNode-Panel/main/remnanode-panel.sh -o /usr/local/bin/remnanode-panel
chmod +x /usr/local/bin/remnanode-panel
remnanode-panel
```

如果你的仓库默认分支是 `master`，把上面的 `main` 改成 `master`。

---

## English Quick Start

### Install without git

For a fresh Debian 13 server, `git` is not required.

```bash
apt-get update && apt-get install -y ca-certificates curl bash

RAW_BASE="https://raw.githubusercontent.com/xpan5201/RemnaNode-Panel"
INSTALL_PATH="/usr/local/bin/remnanode-panel"

for BRANCH in main master; do
  if curl -fsSL "${RAW_BASE}/${BRANCH}/remnanode-panel.sh" -o "${INSTALL_PATH}"; then
    echo "Downloaded from branch: ${BRANCH}"
    chmod +x "${INSTALL_PATH}"
    break
  fi
done

test -x "${INSTALL_PATH}" || {
  echo "Download failed. Please check repository branch or network."
  exit 1
}

remnanode-panel
```

### Recommended workflow

```text
1. Create a node in Remnawave Panel.
2. Copy the generated docker-compose.yml.
3. Run remnanode-panel on the node server.
4. Complete the initial configuration wizard.
5. Import docker-compose.yml.
6. Run one-click install or update.
7. Check node status in Remnawave Panel.
```

### Security model

```text
Allow:
  current SSH port
  MAIN_IPV4 -> NODE_PORT/tcp
  MAIN_IPV6 -> NODE_PORT/tcp
  public -> XRAY_REALITY_PORT/tcp

Drop:
  all other inbound traffic
```

---

## 免责声明

本项目用于 Remnawave Node 节点机的自动化部署与维护。使用者应遵守所在地区法律法规、服务商条款以及网络使用规范。

本项目不会保证节点免受所有攻击，也不能替代服务商级别的 DDoS 防护。对于公益服务，建议始终采用：

```text
主控稳定优先
节点轻量可替换
定期备份
最小暴露面
及时更新
异常节点快速下线
```
