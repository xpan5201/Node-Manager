#!/usr/bin/env bash
# RemnaNode Panel - bilingual automation panel for Remnawave Node on Debian 13
# Public-safe: no embedded secrets. Runtime secrets are collected interactively and stored under /etc/remnanode-panel with mode 600.

set -Eeuo pipefail
IFS=$'\n\t'

APP_NAME="RemnaNode Panel"
APP_VERSION="0.1.1"
BASE_DIR="/opt/remnanode"
CONF_DIR="/etc/remnanode-panel"
CONF_FILE="${CONF_DIR}/config.env"
RUNTIME_DIR="/run/remnanode-panel"
LOG_DIR="/var/log/remnanode-panel"
PANEL_LOG="${LOG_DIR}/panel.log"
BACKUP_DIR="${BASE_DIR}/backups"
COMPOSE_FILE="${BASE_DIR}/docker-compose.yml"
NODE_LOG_DIR="/var/log/remnanode"
LOCK_FILE="/run/remnanode-panel.lock"

LANG_CODE="zh"
NONINTERACTIVE="0"
ASSUME_YES="0"
LAST_ERROR=""

# ---------- UI ----------
if command -v tput >/dev/null 2>&1 && [ -t 1 ]; then
  BOLD="$(tput bold || true)"; DIM="$(tput dim || true)"; RESET="$(tput sgr0 || true)"
  RED="$(tput setaf 1 || true)"; GREEN="$(tput setaf 2 || true)"; YELLOW="$(tput setaf 3 || true)"
  BLUE="$(tput setaf 4 || true)"; MAGENTA="$(tput setaf 5 || true)"; CYAN="$(tput setaf 6 || true)"
else
  BOLD=""; DIM=""; RESET=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; MAGENTA=""; CYAN=""
fi

msg() {
  local key="$1"
  case "${LANG_CODE}:${key}" in
    zh:press_enter) echo "按 Enter 返回...";;
    en:press_enter) echo "Press Enter to return...";;
    zh:need_root) echo "请使用 root 运行本面板。";;
    en:need_root) echo "Please run this panel as root.";;
    zh:not_debian) echo "警告：当前系统不是 Debian 13，本脚本仅按 Debian 13 设计。";;
    en:not_debian) echo "Warning: this system is not Debian 13; this script is designed for Debian 13 only.";;
    zh:menu_title) echo "RemnaNode 自动化部署与维护面板";;
    en:menu_title) echo "RemnaNode Automation and Maintenance Panel";;
    zh:menu_subtitle) echo "Debian 13 · IPv4/IPv6 双栈 · 不修改 SSH 配置 · 低配置节点优化";;
    en:menu_subtitle) echo "Debian 13 · IPv4/IPv6 dual-stack · SSH config untouched · Low-spec node optimized";;
    zh:invalid_choice) echo "无效选项。";;
    en:invalid_choice) echo "Invalid choice.";;
    zh:done) echo "完成。";;
    en:done) echo "Done.";;
    zh:cancelled) echo "已取消。";;
    en:cancelled) echo "Cancelled.";;
    zh:confirm_danger) echo "这是危险操作，请确认。";;
    en:confirm_danger) echo "This is a dangerous operation. Please confirm.";;
    zh:config_missing) echo "尚未完成初始配置，请先运行：初始配置向导。";;
    en:config_missing) echo "Initial configuration is missing. Run the initial configuration wizard first.";;
    zh:ssh_untouched) echo "本面板不会修改 sshd_config；只会在防火墙中保留当前 SSH 监听端口。";;
    en:ssh_untouched) echo "This panel never edits sshd_config; it only keeps current SSH listening ports allowed in firewall.";;
    zh:provider_fw) echo "提醒：还需要在服务商安全组/防火墙中放行 Xray 端口，并限制 Node API 端口仅主控访问。";;
    en:provider_fw) echo "Reminder: also configure your provider security group/firewall to allow Xray port and restrict Node API port to the panel IPs only.";;
    *) echo "$key";;
  esac
}

log() {
  mkdir -p "$LOG_DIR"
  printf '[%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" >> "$PANEL_LOG"
}

say() { echo -e "${CYAN}==>${RESET} $*"; log "$*"; }
warn() { echo -e "${YELLOW}WARN:${RESET} $*"; log "WARN: $*"; }
fail() { echo -e "${RED}ERROR:${RESET} $*"; log "ERROR: $*"; }
ok() { echo -e "${GREEN}OK:${RESET} $*"; log "OK: $*"; }

pause() {
  [ "$NONINTERACTIVE" = "1" ] && return 0
  echo
  read -r -p "$(msg press_enter) " _ || true
}

header() {
  clear || true
  echo -e "${BOLD}${MAGENTA}"
  cat <<'BANNER'
  ____                         _   _           _      
 |  _ \ ___ _ __ ___  _ __    | \ | | ___   __| | ___ 
 | |_) / _ \ '_ ` _ \| '_ \   |  \| |/ _ \ / _` |/ _ \
 |  _ <  __/ | | | | | | | |  | |\  | (_) | (_| |  __/
 |_| \_\___|_| |_| |_|_| |_|  |_| \_|\___/ \__,_|\___|
BANNER
  echo -e "${RESET}${BOLD}$(msg menu_title)${RESET}  ${DIM}v${APP_VERSION}${RESET}"
  echo -e "${DIM}$(msg menu_subtitle)${RESET}"
  echo -e "${DIM}Config: ${CONF_FILE} · Logs: ${PANEL_LOG}${RESET}"
  echo
}

# ---------- error handling / locking ----------
on_error() {
  local exit_code=$?
  local line_no=${BASH_LINENO[0]:-unknown}
  LAST_ERROR="line=${line_no} exit=${exit_code} cmd=${BASH_COMMAND}"
  fail "异常捕获 / exception captured: ${LAST_ERROR}"
  fail "日志 / log: ${PANEL_LOG}"
  exit "$exit_code"
}
trap on_error ERR

acquire_lock() {
  mkdir -p "$RUNTIME_DIR"
  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    fail "Another instance is running: ${LOCK_FILE}"
    exit 1
  fi
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    fail "$(msg need_root)"
    exit 1
  fi
}

load_config() {
  if [ -f "$CONF_FILE" ]; then
    # shellcheck disable=SC1090
    source "$CONF_FILE"
    LANG_CODE="${LANG_CODE:-zh}"
  fi
}

save_config_var() {
  local key="$1" value="$2"
  mkdir -p "$CONF_DIR"
  chmod 700 "$CONF_DIR"
  touch "$CONF_FILE"
  chmod 600 "$CONF_FILE"
  if grep -qE "^${key}=" "$CONF_FILE"; then
    sed -i "s|^${key}=.*|${key}=$(printf '%q' "$value")|" "$CONF_FILE"
  else
    printf '%s=%q\n' "$key" "$value" >> "$CONF_FILE"
  fi
}

write_config() {
  mkdir -p "$CONF_DIR"
  chmod 700 "$CONF_DIR"
  umask 077
  cat >"$CONF_FILE" <<EOF2
# RemnaNode Panel configuration. Do not publish.
LANG_CODE=${LANG_CODE}
MAIN_IPV4=${MAIN_IPV4:-}
MAIN_IPV6=${MAIN_IPV6:-}
NODE_DOMAIN=${NODE_DOMAIN:-}
NODE_NAME=${NODE_NAME:-}
NODE_HOSTNAME=${NODE_HOSTNAME:-}
NODE_PORT=${NODE_PORT:-2222}
XRAY_REALITY_PORT=${XRAY_REALITY_PORT:-443}
AUTO_SWAP=${AUTO_SWAP:-yes}
SWAP_SIZE_MB=${SWAP_SIZE_MB:-512}
DOCKER_LOG_MAX_SIZE=${DOCKER_LOG_MAX_SIZE:-20m}
DOCKER_LOG_MAX_FILE=${DOCKER_LOG_MAX_FILE:-3}
JOURNAL_MAX_USE=${JOURNAL_MAX_USE:-128M}
EOF2
  chmod 600 "$CONF_FILE"
}

ensure_config_or_return() {
  load_config
  if [ ! -f "$CONF_FILE" ]; then
    fail "$(msg config_missing)"
    pause
    return 1
  fi
  return 0
}

is_placeholder_or_empty() {
  local v="${1:-}"
  [ -z "$v" ] || [[ "$v" == \<*\> ]]
}

validate_config() {
  load_config
  local errors=0
  for k in MAIN_IPV4 MAIN_IPV6 NODE_PORT XRAY_REALITY_PORT; do
    if is_placeholder_or_empty "${!k:-}"; then
      fail "$k is empty or placeholder"
      errors=$((errors+1))
    fi
  done
  if ! [[ "${NODE_PORT:-}" =~ ^[0-9]+$ ]] || [ "${NODE_PORT:-0}" -lt 1 ] || [ "${NODE_PORT:-0}" -gt 65535 ]; then
    fail "NODE_PORT invalid: ${NODE_PORT:-}"
    errors=$((errors+1))
  fi
  if ! [[ "${XRAY_REALITY_PORT:-}" =~ ^[0-9]+$ ]] || [ "${XRAY_REALITY_PORT:-0}" -lt 1 ] || [ "${XRAY_REALITY_PORT:-0}" -gt 65535 ]; then
    fail "XRAY_REALITY_PORT invalid: ${XRAY_REALITY_PORT:-}"
    errors=$((errors+1))
  fi
  if [ "${NODE_PORT:-}" = "${XRAY_REALITY_PORT:-}" ]; then
    fail "NODE_PORT and XRAY_REALITY_PORT must not be the same."
    errors=$((errors+1))
  fi
  return "$errors"
}

ask() {
  local prompt="$1" default="${2:-}" secret="${3:-no}" value
  if [ "$secret" = "yes" ]; then
    read -r -s -p "$prompt${default:+ [$default]}: " value || true
    echo
  else
    read -r -p "$prompt${default:+ [$default]}: " value || true
  fi
  if [ -z "$value" ]; then value="$default"; fi
  printf '%s' "$value"
}

confirm() {
  local prompt="$1" default="${2:-n}" ans
  if [ "$ASSUME_YES" = "1" ]; then return 0; fi
  read -r -p "$prompt [$default]: " ans || true
  ans="${ans:-$default}"
  case "$ans" in
    y|Y|yes|YES|Yes|是|确认) return 0;;
    *) return 1;;
  esac
}

# ---------- system helpers ----------
preflight() {
  say "Preflight checks"
  require_root
  mkdir -p "$LOG_DIR" "$RUNTIME_DIR"
  touch "$PANEL_LOG"; chmod 600 "$PANEL_LOG"
  if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    if [ "${ID:-}" != "debian" ] || [ "${VERSION_CODENAME:-}" != "trixie" ]; then
      warn "$(msg not_debian) ID=${ID:-unknown} VERSION_CODENAME=${VERSION_CODENAME:-unknown}"
    else
      ok "Debian 13 trixie detected"
    fi
  fi
  msg ssh_untouched
}


# ---------- apt/dpkg lock handling ----------
# Debian cloud images often start unattended-upgrades right after boot. Removing lock files is unsafe.
# These helpers wait for the real lock holders and then retry apt operations.
APT_LOCK_WAIT_SECONDS="${APT_LOCK_WAIT_SECONDS:-1800}"
APT_LOCK_POLL_SECONDS="${APT_LOCK_POLL_SECONDS:-10}"
APT_RETRY_MAX="${APT_RETRY_MAX:-3}"

apt_lock_pids() {
  local locks=(
    /var/lib/dpkg/lock-frontend
    /var/lib/dpkg/lock
    /var/cache/apt/archives/lock
    /var/lib/apt/lists/lock
  )

  if command -v fuser >/dev/null 2>&1; then
    (fuser "${locks[@]}" 2>/dev/null || true) | tr ' ' '\n' | awk 'NF' | sort -nu
    return 0
  fi

  # Fallback without psmisc/fuser. Walk /proc fd links and find processes holding apt/dpkg locks.
  local pid fd target lock
  for pid_dir in /proc/[0-9]*; do
    [ -d "$pid_dir" ] || continue
    pid="${pid_dir##*/}"
    for fd in "$pid_dir"/fd/*; do
      [ -e "$fd" ] || continue
      target="$(readlink "$fd" 2>/dev/null || true)"
      [ -n "$target" ] || continue
      for lock in "${locks[@]}"; do
        if [ "$target" = "$lock" ]; then
          echo "$pid"
        fi
      done
    done
  done | sort -nu
}

show_apt_lock_holders() {
  local pids="$1"
  [ -n "$pids" ] || return 0
  echo "$pids" | while read -r pid; do
    [ -n "$pid" ] || continue
    if [ -r "/proc/${pid}/cmdline" ]; then
      local cmd
      cmd="$(tr '\0' ' ' <"/proc/${pid}/cmdline" 2>/dev/null || true)"
      warn "dpkg/apt lock holder: pid=${pid} cmd=${cmd:-unknown}"
    else
      warn "dpkg/apt lock holder: pid=${pid}"
    fi
  done
}

wait_for_apt_locks() {
  local purpose="${1:-apt operation}"
  local start now elapsed pids last_report=0
  start="$(date +%s)"

  while true; do
    pids="$(apt_lock_pids || true)"
    if [ -z "$pids" ]; then
      return 0
    fi

    now="$(date +%s)"
    elapsed=$((now - start))

    if [ "$elapsed" -eq 0 ] || [ $((elapsed - last_report)) -ge 30 ]; then
      warn "apt/dpkg is busy during ${purpose}. Waiting safely; do NOT remove lock files. elapsed=${elapsed}s timeout=${APT_LOCK_WAIT_SECONDS}s"
      show_apt_lock_holders "$pids"
      last_report="$elapsed"
    fi

    if [ "$elapsed" -ge "$APT_LOCK_WAIT_SECONDS" ]; then
      fail "Timeout waiting for apt/dpkg locks during ${purpose}. Re-run later or set APT_LOCK_WAIT_SECONDS=3600. Do not delete dpkg lock files."
      return 1
    fi

    sleep "$APT_LOCK_POLL_SECONDS"
  done
}

apt_safe() {
  local action="$1"; shift
  local attempt=1
  while [ "$attempt" -le "$APT_RETRY_MAX" ]; do
    wait_for_apt_locks "apt-get ${action}" || return 1
    if apt-get "$action" "$@"; then
      return 0
    fi
    local rc=$?
    warn "apt-get ${action} failed with exit=${rc}; attempt=${attempt}/${APT_RETRY_MAX}"
    wait_for_apt_locks "apt retry after failed apt-get ${action}" || return 1
    apt-get -f install -y >/dev/null 2>&1 || true
    dpkg --configure -a >/dev/null 2>&1 || true
    attempt=$((attempt + 1))
    sleep 5
  done
  fail "apt-get ${action} failed after ${APT_RETRY_MAX} attempts"
  return 1
}

install_base_packages() {
  say "Installing base packages"
  export DEBIAN_FRONTEND=noninteractive
  apt_safe update
  apt_safe install -y --no-install-recommends \
    ca-certificates curl wget gnupg lsb-release apt-transport-https \
    iproute2 iptables conntrack dnsutils net-tools \
    cron logrotate rsyslog unattended-upgrades apt-listchanges \
    openssl tar zstd nano less procps htop
}

configure_unattended_upgrades() {
  say "Configuring unattended security upgrades"
  cat >/etc/apt/apt.conf.d/20auto-upgrades <<'EOF2'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF2
  systemctl enable --now unattended-upgrades >/dev/null 2>&1 || true
}

configure_journald() {
  load_config
  say "Configuring journald limits"
  mkdir -p /etc/systemd/journald.conf.d /var/log/journal
  cat >/etc/systemd/journald.conf.d/10-remnanode-panel.conf <<EOF2
[Journal]
Storage=persistent
SystemMaxUse=${JOURNAL_MAX_USE:-128M}
RuntimeMaxUse=64M
MaxRetentionSec=7day
RateLimitIntervalSec=30s
RateLimitBurst=5000
Compress=yes
EOF2
  systemctl restart systemd-journald || true
}

configure_sysctl() {
  say "Applying kernel/network tuning"
  cat >/etc/modules-load.d/remnanode-panel.conf <<'EOF2'
nf_conntrack
tcp_bbr
EOF2
  modprobe nf_conntrack || true
  modprobe tcp_bbr || true
  cat >/etc/sysctl.d/99-remnanode-panel.conf <<'EOF2'
# RemnaNode Panel node baseline. SSH config is not modified.
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 32768
net.core.somaxconn = 32768
net.core.netdev_max_backlog = 65536
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_max_tw_buckets = 500000
net.netfilter.nf_conntrack_max = 131072
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF2
  if ! sysctl --system; then
    warn "sysctl failed; retrying without BBR"
    sed -i '/net.ipv4.tcp_congestion_control = bbr/d' /etc/sysctl.d/99-remnanode-panel.conf
    sysctl --system
  fi
}

ensure_swap_for_low_memory() {
  load_config
  [ "${AUTO_SWAP:-yes}" = "yes" ] || return 0
  local mem_mb swap_mb
  mem_mb=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
  swap_mb=$(awk '/SwapTotal/ {print int($2/1024)}' /proc/meminfo)
  if [ "$mem_mb" -le 1536 ] && [ "$swap_mb" -eq 0 ]; then
    local size="${SWAP_SIZE_MB:-512}"
    say "Low RAM detected (${mem_mb}MB). Creating ${size}MB swapfile"
    if [ -f /swapfile ]; then
      warn "/swapfile exists; skipping swap creation"
      return 0
    fi
    fallocate -l "${size}M" /swapfile || dd if=/dev/zero of=/swapfile bs=1M count="$size"
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    ok "Swap enabled"
  else
    ok "Swap check passed: RAM=${mem_mb}MB SWAP=${swap_mb}MB"
  fi
}

install_docker() {
  say "Installing Docker Engine from official apt repository"
  export DEBIAN_FRONTEND=noninteractive
  for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
    apt_safe remove -y "$pkg" >/dev/null 2>&1 || true
  done
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  local codename arch
  codename=$(. /etc/os-release && echo "${VERSION_CODENAME}")
  arch=$(dpkg --print-architecture)
  cat >/etc/apt/sources.list.d/docker.sources <<EOF2
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: ${codename}
Components: stable
Architectures: ${arch}
Signed-By: /etc/apt/keyrings/docker.asc
EOF2
  apt_safe update
  apt_safe install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
}

configure_docker_daemon() {
  load_config
  say "Configuring Docker log rotation and live-restore"
  mkdir -p /etc/docker
  cat >/etc/docker/daemon.json <<EOF2
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "${DOCKER_LOG_MAX_SIZE:-20m}",
    "max-file": "${DOCKER_LOG_MAX_FILE:-3}"
  },
  "live-restore": true,
  "iptables": true,
  "ip6tables": true
}
EOF2
  systemctl restart docker
}

create_dirs() {
  say "Creating directories"
  install -d -m 700 "$BASE_DIR" "$BACKUP_DIR" "${BASE_DIR}/secrets"
  install -d -m 755 "${BASE_DIR}/scripts" "$NODE_LOG_DIR"
  install -d -m 700 "$CONF_DIR"
  chmod 700 "$BASE_DIR" "$BACKUP_DIR" "${BASE_DIR}/secrets" "$CONF_DIR"
}

configure_logrotate() {
  say "Configuring logrotate"
  cat >/etc/logrotate.d/remnanode <<'EOF2'
/var/log/remnanode/*.log /var/log/remnanode-panel/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
    maxsize 50M
}
EOF2
}

copy_compose_from_prompt() {
  create_dirs
  echo
  echo -e "${YELLOW}Paste docker-compose.yml copied from Remnawave Panel. End with a single line: __EOF__${RESET}"
  echo -e "${DIM}请粘贴 Panel 复制的 docker-compose.yml，最后单独输入一行：__EOF__${RESET}"
  local tmp
  tmp=$(mktemp)
  while IFS= read -r line; do
    [ "$line" = "__EOF__" ] && break
    printf '%s\n' "$line" >> "$tmp"
  done
  if grep -qE '^services:' "$tmp" && grep -qE 'remnawave/node|remnanode' "$tmp"; then
    cp "$tmp" "$COMPOSE_FILE"
    chmod 600 "$COMPOSE_FILE"
    ok "docker-compose.yml saved to ${COMPOSE_FILE}"
  else
    fail "Pasted content does not look like a Remnawave Node docker-compose.yml"
    rm -f "$tmp"
    return 1
  fi
  rm -f "$tmp"
}

copy_compose_from_path() {
  local path
  path=$(ask "Path to docker-compose.yml / compose 文件路径")
  if [ ! -f "$path" ]; then fail "File not found: $path"; return 1; fi
  create_dirs
  cp "$path" "$COMPOSE_FILE"
  chmod 600 "$COMPOSE_FILE"
  docker compose -f "$COMPOSE_FILE" config >/dev/null
  ok "Compose imported"
}

compose_exists() { [ -s "$COMPOSE_FILE" ]; }

start_node() {
  if ! compose_exists; then
    warn "${COMPOSE_FILE} not found. Import compose first."
    return 1
  fi
  say "Starting Remnawave Node"
  cd "$BASE_DIR"
  docker compose config >/dev/null
  docker compose pull
  docker compose up -d
  docker compose ps
}

stop_node() {
  if compose_exists; then
    say "Stopping Remnawave Node"
    cd "$BASE_DIR"
    docker compose down || true
  fi
}

update_node() {
  if ! compose_exists; then fail "Compose missing"; return 1; fi
  say "Updating Remnawave Node"
  cd "$BASE_DIR"
  docker compose pull
  docker compose up -d
  docker compose ps
}

# ---------- firewall ----------
detect_ssh_ports() {
  local f="$1"
  : > "$f"
  if [ -n "${SSH_CONNECTION:-}" ]; then
    echo "${SSH_CONNECTION}" | awk '{print $4}' >> "$f" || true
  fi
  ss -H -ltnp 2>/dev/null | awk '/sshd/ { n=split($4,a,":"); print a[n] }' >> "$f" || true
  echo 22 >> "$f"
  sort -nu "$f"
}

write_firewall_script() {
  say "Writing firewall script"
  cat >/usr/local/sbin/remnanode-panel-firewall.sh <<'EOF2'
#!/usr/bin/env bash
set -Eeuo pipefail
CONF_FILE="/etc/remnanode-panel/config.env"
[ -f "$CONF_FILE" ] || { echo "Missing $CONF_FILE"; exit 1; }
# shellcheck disable=SC1090
source "$CONF_FILE"
for v in MAIN_IPV4 MAIN_IPV6 NODE_PORT XRAY_REALITY_PORT; do
  if [ -z "${!v:-}" ] || [[ "${!v}" == \<* ]]; then echo "Invalid $v"; exit 1; fi
done
EXT_IF="$(ip -4 route show default | awk '{print $5; exit}')"
[ -n "$EXT_IF" ] || EXT_IF="$(ip -6 route show default | awk '{print $5; exit}')"
[ -n "$EXT_IF" ] || { echo "Cannot detect external interface"; exit 1; }
SSH_PORTS_FILE="$(mktemp)"; trap 'rm -f "$SSH_PORTS_FILE"' EXIT
if [ -n "${SSH_CONNECTION:-}" ]; then echo "${SSH_CONNECTION}" | awk '{print $4}' >> "$SSH_PORTS_FILE" || true; fi
ss -H -ltnp 2>/dev/null | awk '/sshd/ { n=split($4,a,":"); print a[n] }' >> "$SSH_PORTS_FILE" || true
echo 22 >> "$SSH_PORTS_FILE"
mapfile -t SSH_PORTS < <(grep -E '^[0-9]+$' "$SSH_PORTS_FILE" | sort -nu)
iptables -P INPUT DROP; iptables -P FORWARD DROP; iptables -P OUTPUT ACCEPT
ip6tables -P INPUT DROP; ip6tables -P FORWARD DROP; ip6tables -P OUTPUT ACCEPT
iptables -F INPUT; ip6tables -F INPUT
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
ip6tables -A INPUT -i lo -j ACCEPT
ip6tables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -p icmp -m limit --limit 10/second --limit-burst 20 -j ACCEPT
ip6tables -A INPUT -p ipv6-icmp -m limit --limit 10/second --limit-burst 20 -j ACCEPT
for p in "${SSH_PORTS[@]}"; do
  iptables -A INPUT -p tcp --dport "$p" -m conntrack --ctstate NEW -j ACCEPT
  ip6tables -A INPUT -p tcp --dport "$p" -m conntrack --ctstate NEW -j ACCEPT
done
iptables -A INPUT -i "$EXT_IF" -p tcp -s "$MAIN_IPV4" --dport "$NODE_PORT" -m conntrack --ctstate NEW -j ACCEPT
ip6tables -A INPUT -i "$EXT_IF" -p tcp -s "$MAIN_IPV6" --dport "$NODE_PORT" -m conntrack --ctstate NEW -j ACCEPT
iptables -A INPUT -i "$EXT_IF" -p tcp --dport "$XRAY_REALITY_PORT" -m conntrack --ctstate NEW -j ACCEPT
ip6tables -A INPUT -i "$EXT_IF" -p tcp --dport "$XRAY_REALITY_PORT" -m conntrack --ctstate NEW -j ACCEPT
iptables -N DOCKER-USER 2>/dev/null || true; ip6tables -N DOCKER-USER 2>/dev/null || true
iptables -F DOCKER-USER; ip6tables -F DOCKER-USER
iptables -A DOCKER-USER -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
ip6tables -A DOCKER-USER -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
iptables -A DOCKER-USER -i "$EXT_IF" -p tcp -s "$MAIN_IPV4" --dport "$NODE_PORT" -j RETURN
ip6tables -A DOCKER-USER -i "$EXT_IF" -p tcp -s "$MAIN_IPV6" --dport "$NODE_PORT" -j RETURN
iptables -A DOCKER-USER -i "$EXT_IF" -p tcp --dport "$XRAY_REALITY_PORT" -j RETURN
ip6tables -A DOCKER-USER -i "$EXT_IF" -p tcp --dport "$XRAY_REALITY_PORT" -j RETURN
iptables -A DOCKER-USER -i "$EXT_IF" -m conntrack --ctstate NEW -j DROP
ip6tables -A DOCKER-USER -i "$EXT_IF" -m conntrack --ctstate NEW -j DROP
iptables -A DOCKER-USER -j RETURN; ip6tables -A DOCKER-USER -j RETURN
iptables -A INPUT -m limit --limit 5/min --limit-burst 20 -j LOG --log-prefix "DROP_RWNODE_V4 " --log-level 4
ip6tables -A INPUT -m limit --limit 5/min --limit-burst 20 -j LOG --log-prefix "DROP_RWNODE_V6 " --log-level 4
iptables -A INPUT -j DROP; ip6tables -A INPUT -j DROP
echo "Firewall applied. SSH ports: ${SSH_PORTS[*]}; NODE_PORT=${NODE_PORT}; XRAY=${XRAY_REALITY_PORT}; IF=${EXT_IF}"
EOF2
  chmod 700 /usr/local/sbin/remnanode-panel-firewall.sh
}

apply_firewall() {
  if ! validate_config; then return 1; fi
  write_firewall_script
  say "Applying firewall"
  /usr/local/sbin/remnanode-panel-firewall.sh
  cat >/etc/systemd/system/remnanode-panel-firewall.service <<'EOF2'
[Unit]
Description=Apply RemnaNode Panel firewall
Wants=network-online.target docker.service
After=network-online.target docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/remnanode-panel-firewall.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF2
  systemctl daemon-reload
  systemctl enable remnanode-panel-firewall.service >/dev/null
  ok "Firewall service enabled"
}

# ---------- backup / maintenance ----------
backup_all() {
  create_dirs
  local ts out archive
  ts=$(date -u +%Y%m%d-%H%M%S)
  out="${BACKUP_DIR}/${ts}"
  archive="${BACKUP_DIR}/remnanode-backup-${ts}.tar.zst"
  mkdir -p "$out"
  chmod 700 "$out"
  [ -f "$CONF_FILE" ] && cp -a "$CONF_FILE" "$out/config.env"
  [ -f "$COMPOSE_FILE" ] && cp -a "$COMPOSE_FILE" "$out/docker-compose.yml"
  [ -f /usr/local/sbin/remnanode-panel-firewall.sh ] && cp -a /usr/local/sbin/remnanode-panel-firewall.sh "$out/firewall.sh"
  iptables -S > "$out/iptables.v4.txt" 2>/dev/null || true
  ip6tables -S > "$out/iptables.v6.txt" 2>/dev/null || true
  docker ps -a > "$out/docker-ps.txt" 2>/dev/null || true
  tar -C "$BACKUP_DIR" -I 'zstd -10 -T0' -cf "$archive" "$ts"
  rm -rf "$out"
  chmod 600 "$archive"
  find "$BACKUP_DIR" -type f -name 'remnanode-backup-*.tar.zst' -mtime +14 -delete
  ok "Backup: $archive"
}

restore_backup() {
  local latest restore_dir
  latest=$(ls -1t "$BACKUP_DIR"/remnanode-backup-*.tar.zst 2>/dev/null | head -n1 || true)
  if [ -z "$latest" ]; then fail "No backup found"; return 1; fi
  echo "Latest backup: $latest"
  confirm "Restore latest backup? / 恢复最新备份？" "n" || return 0
  restore_dir="${BACKUP_DIR}/restore-$(date -u +%Y%m%d-%H%M%S)"
  mkdir -p "$restore_dir"
  tar -I zstd -xf "$latest" -C "$restore_dir"
  local extracted
  extracted=$(find "$restore_dir" -mindepth 1 -maxdepth 1 -type d | head -n1)
  [ -f "$extracted/config.env" ] && cp -a "$extracted/config.env" "$CONF_FILE" && chmod 600 "$CONF_FILE"
  [ -f "$extracted/docker-compose.yml" ] && cp -a "$extracted/docker-compose.yml" "$COMPOSE_FILE" && chmod 600 "$COMPOSE_FILE"
  ok "Restored config and compose. Re-run firewall/install if needed."
}

cleanup_system() {
  say "Cleaning low-disk node safely"
  wait_for_apt_locks "apt-get clean" || true
  apt-get clean || true
  journalctl --vacuum-size=100M || true
  find /var/log -type f -name '*.gz' -mtime +7 -delete 2>/dev/null || true
  find /var/log -type f -name '*.1' -mtime +7 -delete 2>/dev/null || true
  if command -v docker >/dev/null 2>&1; then
    docker image prune -af || true
    docker builder prune -af || true
  fi
  ok "Cleanup completed"
}

health_report() {
  load_config
  header
  echo -e "${BOLD}Health / 健康状态${RESET}"
  echo
  echo "System: $(uname -a)"
  [ -f /etc/os-release ] && . /etc/os-release && echo "OS: ${PRETTY_NAME:-unknown}"
  echo
  echo "Memory:"
  free -h || true
  echo
  echo "Disk:"
  df -h / /var /opt 2>/dev/null || df -h
  echo
  echo "Network addresses:"
  ip -br addr || true
  echo
  echo "Listening ports:"
  ss -lntup | grep -E ":(${NODE_PORT:-2222}|${XRAY_REALITY_PORT:-443})\b" || true
  echo
  echo "Docker:"
  systemctl is-active docker || true
  docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}' 2>/dev/null || true
  echo
  echo "Firewall rules summary:"
  iptables -S INPUT | sed -n '1,20p' || true
  ip6tables -S INPUT | sed -n '1,20p' || true
  echo
  local disk_use mem_avail
  disk_use=$(df / | awk 'NR==2 {gsub("%", "", $5); print $5}')
  mem_avail=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo)
  if [ "${disk_use:-0}" -ge 85 ]; then warn "Disk usage >=85%; run cleanup."; fi
  if [ "${mem_avail:-999}" -lt 128 ]; then warn "Available memory <128MB; ensure swap is enabled."; fi
}

self_repair() {
  say "Running self-repair"
  create_dirs
  configure_journald
  configure_sysctl
  ensure_swap_for_low_memory
  if ! systemctl is-active docker >/dev/null 2>&1; then
    warn "Docker inactive; trying restart"
    systemctl restart docker || install_docker
  fi
  configure_docker_daemon
  configure_logrotate
  if validate_config; then apply_firewall; else warn "Firewall skipped because config is invalid"; fi
  cleanup_system
  if compose_exists; then
    cd "$BASE_DIR"
    docker compose config >/dev/null && docker compose up -d || warn "Compose start failed; check logs"
  fi
  ok "Self-repair finished"
}

show_logs() {
  echo "1) Panel log"
  echo "2) Remnawave Node docker logs"
  echo "3) Kernel firewall drops"
  local c; c=$(ask "Choose / 选择" "1")
  case "$c" in
    1) tail -n 200 "$PANEL_LOG" 2>/dev/null || true;;
    2) cd "$BASE_DIR" 2>/dev/null && docker compose logs -t --tail=200 || true;;
    3) journalctl -k --no-pager | grep -E 'DROP_RWNODE_V4|DROP_RWNODE_V6' | tail -n 200 || true;;
    *) msg invalid_choice;;
  esac
}

view_config() {
  load_config
  echo -e "${BOLD}Config / 配置${RESET}"
  if [ ! -f "$CONF_FILE" ]; then fail "$(msg config_missing)"; return 1; fi
  awk -F= '{print $1"="$2}' "$CONF_FILE" | sed -E 's/(SECRET|KEY|TOKEN|PASS|PASSWORD)=.*/\1=<redacted>/I'
  echo
  [ -f "$COMPOSE_FILE" ] && echo "Compose: $COMPOSE_FILE" || echo "Compose: missing"
}

edit_config_menu() {
  ensure_config_or_return || return 0
  while true; do
    header
    view_config || true
    cat <<EOF2

1) Change language / 修改语言
2) Change main panel IPs / 修改主控 IP
3) Change node ports / 修改节点端口
4) Change node domain/name/hostname / 修改节点域名/名称/主机名
5) Import docker-compose.yml by paste / 粘贴导入 compose
6) Import docker-compose.yml from file / 从文件导入 compose
7) Back / 返回
EOF2
    local c; c=$(ask "Choose / 选择" "7")
    case "$c" in
      1) choose_language; write_config;;
      2) MAIN_IPV4=$(ask "MAIN_IPV4" "${MAIN_IPV4:-}"); MAIN_IPV6=$(ask "MAIN_IPV6" "${MAIN_IPV6:-}"); write_config;;
      3) NODE_PORT=$(ask "NODE_PORT" "${NODE_PORT:-2222}"); XRAY_REALITY_PORT=$(ask "XRAY_REALITY_PORT" "${XRAY_REALITY_PORT:-443}"); write_config;;
      4) NODE_DOMAIN=$(ask "NODE_DOMAIN" "${NODE_DOMAIN:-}"); NODE_NAME=$(ask "NODE_NAME" "${NODE_NAME:-}"); NODE_HOSTNAME=$(ask "NODE_HOSTNAME" "${NODE_HOSTNAME:-}"); write_config;;
      5) copy_compose_from_prompt; pause;;
      6) copy_compose_from_path; pause;;
      7) break;;
      *) msg invalid_choice; pause;;
    esac
  done
}

choose_language() {
  echo "1) 中文"
  echo "2) English"
  local c; c=$(ask "Language / 语言" "1")
  case "$c" in
    2|en|EN|English|english) LANG_CODE="en";;
    *) LANG_CODE="zh";;
  esac
}

initial_wizard() {
  header
  choose_language
  echo
  echo -e "${BOLD}Initial configuration wizard / 初始配置向导${RESET}"
  msg ssh_untouched
  echo
  MAIN_IPV4=$(ask "Main panel IPv4 / 主控 IPv4" "${MAIN_IPV4:-}")
  MAIN_IPV6=$(ask "Main panel IPv6 / 主控 IPv6" "${MAIN_IPV6:-}")
  NODE_DOMAIN=$(ask "Node domain, DNS only / 节点域名，必须灰云" "${NODE_DOMAIN:-}")
  NODE_NAME=$(ask "Node display name / 节点显示名" "${NODE_NAME:-}")
  NODE_HOSTNAME=$(ask "Linux hostname / Linux 主机名" "${NODE_HOSTNAME:-rw-node}")
  NODE_PORT=$(ask "Remnawave Node API port / Node API 端口，仅主控访问" "${NODE_PORT:-2222}")
  XRAY_REALITY_PORT=$(ask "Xray REALITY public port / Xray REALITY 公网端口" "${XRAY_REALITY_PORT:-443}")
  AUTO_SWAP=$(ask "Create swap automatically on <=1.5GB RAM? yes/no / 低内存自动创建 swap？" "${AUTO_SWAP:-yes}")
  SWAP_SIZE_MB=$(ask "Swap size MB / Swap 大小 MB" "${SWAP_SIZE_MB:-512}")
  DOCKER_LOG_MAX_SIZE=$(ask "Docker log max-size / Docker 日志单文件上限" "${DOCKER_LOG_MAX_SIZE:-20m}")
  DOCKER_LOG_MAX_FILE=$(ask "Docker log max-file / Docker 日志文件数" "${DOCKER_LOG_MAX_FILE:-3}")
  JOURNAL_MAX_USE=$(ask "journald max use / 系统日志上限" "${JOURNAL_MAX_USE:-128M}")
  write_config
  ok "Config saved: $CONF_FILE"
  echo
  if confirm "Import Remnawave Panel generated docker-compose.yml now? / 现在导入 Panel 生成的 compose？" "y"; then
    copy_compose_from_prompt || true
  fi
  echo
  msg provider_fw
  pause
}

one_click_install() {
  ensure_config_or_return || return 0
  if ! validate_config; then pause; return 1; fi
  header
  say "One-click install/update started"
  msg provider_fw
  if [ -n "${NODE_HOSTNAME:-}" ]; then hostnamectl set-hostname "$NODE_HOSTNAME" || true; fi
  preflight
  create_dirs
  install_base_packages
  configure_unattended_upgrades
  configure_journald
  configure_sysctl
  ensure_swap_for_low_memory
  install_docker
  configure_docker_daemon
  configure_logrotate
  apply_firewall
  if compose_exists; then start_node; else warn "Compose missing; install skipped Node start. Import compose later."; fi
  health_report
  pause
}

reinstall_menu() {
  ensure_config_or_return || return 0
  header
  msg confirm_danger
  echo "This will backup, stop the node, reinstall base components, reapply firewall, then start node."
  echo "这会备份、停止节点、重装基础组件、重应用防火墙、再启动节点。"
  confirm "Continue? / 继续？" "n" || { msg cancelled; pause; return 0; }
  backup_all
  stop_node
  one_click_install
}

uninstall_menu() {
  header
  msg confirm_danger
  cat <<'EOF2'
1) Stop containers only / 仅停止容器
2) Remove node files but keep config backups / 删除节点文件但保留配置备份
3) Purge all panel-managed files / 清空本面板管理的所有文件
4) Back / 返回
EOF2
  local c; c=$(ask "Choose / 选择" "4")
  case "$c" in
    1) stop_node; pause;;
    2)
      confirm "Remove ${BASE_DIR} except backups? / 删除节点目录但保留备份？" "n" || return 0
      stop_node
      backup_all || true
      rm -rf "${BASE_DIR}/docker-compose.yml" "${BASE_DIR}/scripts" "${BASE_DIR}/secrets"
      ok "Removed node files; config kept: $CONF_FILE"; pause;;
    3)
      confirm "Type yes to purge all / 输入 yes 确认清空" "n" || return 0
      stop_node || true
      rm -rf "$BASE_DIR" "$CONF_DIR" "$LOG_DIR" /usr/local/sbin/remnanode-panel-firewall.sh
      systemctl disable --now remnanode-panel-firewall.service >/dev/null 2>&1 || true
      rm -f /etc/systemd/system/remnanode-panel-firewall.service /etc/logrotate.d/remnanode
      systemctl daemon-reload
      ok "Purged. SSH config was not modified."; pause;;
    4) return 0;;
    *) msg invalid_choice; pause;;
  esac
}

maintenance_menu() {
  while true; do
    header
    cat <<'EOF2'
1) Health report / 健康报告
2) Self-repair / 自修复
3) Safe cleanup / 安全清理
4) Backup / 备份
5) Restore latest backup / 恢复最新备份
6) Update Remnawave Node / 更新节点
7) Show logs / 查看日志
8) Reapply firewall / 重应用防火墙
9) Back / 返回
EOF2
    local c; c=$(ask "Choose / 选择" "9")
    case "$c" in
      1) health_report; pause;;
      2) self_repair; pause;;
      3) cleanup_system; pause;;
      4) backup_all; pause;;
      5) restore_backup; pause;;
      6) update_node; pause;;
      7) show_logs; pause;;
      8) ensure_config_or_return && apply_firewall; pause;;
      9) break;;
      *) msg invalid_choice; pause;;
    esac
  done
}

main_menu() {
  while true; do
    load_config
    header
    cat <<'EOF2'
1) Initial configuration wizard / 初始配置
2) One-click install or update / 一条龙安装或更新
3) Reinstall / 重装
4) Delete or uninstall / 删除或卸载
5) View or change information / 查看或修改信息
6) Maintenance / 维护
7) Import docker-compose.yml / 导入 compose
8) Exit / 退出
EOF2
    local c; c=$(ask "Choose / 选择" "8")
    case "$c" in
      1) initial_wizard;;
      2) one_click_install;;
      3) reinstall_menu;;
      4) uninstall_menu;;
      5) edit_config_menu;;
      6) maintenance_menu;;
      7) copy_compose_from_prompt; pause;;
      8) exit 0;;
      *) msg invalid_choice; pause;;
    esac
  done
}

usage() {
  cat <<EOF2
${APP_NAME} v${APP_VERSION}
Usage: $0 [command] [--yes]

Commands:
  menu              interactive menu (default)
  init              initial wizard
  install           one-click install/update
  reinstall         backup + stop + install
  uninstall         uninstall menu
  health            print health report
  repair            run self-repair
  cleanup           safe cleanup
  backup            create backup
  restore           restore latest backup
  update            update Remnawave Node container
  firewall          reapply firewall
  logs              show log menu

EOF2
}

parse_args() {
  COMMAND="menu"
  while [ $# -gt 0 ]; do
    case "$1" in
      --yes|-y) ASSUME_YES="1";;
      --noninteractive) NONINTERACTIVE="1";;
      help|-h|--help) COMMAND="help";;
      menu|init|install|reinstall|uninstall|health|repair|cleanup|backup|restore|update|firewall|logs) COMMAND="$1";;
      *) fail "Unknown argument: $1"; usage; exit 1;;
    esac
    shift
  done
}

main() {
  parse_args "$@"
  require_root
  acquire_lock
  mkdir -p "$LOG_DIR" "$RUNTIME_DIR"
  touch "$PANEL_LOG"; chmod 600 "$PANEL_LOG"
  load_config
  case "$COMMAND" in
    help) usage;;
    menu) main_menu;;
    init) initial_wizard;;
    install) one_click_install;;
    reinstall) reinstall_menu;;
    uninstall) uninstall_menu;;
    health) health_report;;
    repair) self_repair;;
    cleanup) cleanup_system;;
    backup) backup_all;;
    restore) restore_backup;;
    update) update_node;;
    firewall) ensure_config_or_return && apply_firewall;;
    logs) show_logs;;
  esac
}

main "$@"
