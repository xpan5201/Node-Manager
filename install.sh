#!/usr/bin/env bash
set -Eeuo pipefail
if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root. / 请使用 root 运行。"
  exit 1
fi
install -m 755 remnanode-panel.sh /usr/local/bin/remnanode-panel
mkdir -p /etc/remnanode-panel /opt/remnanode /var/log/remnanode-panel
chmod 700 /etc/remnanode-panel /opt/remnanode
chmod 700 /var/log/remnanode-panel
printf 'Installed: /usr/local/bin/remnanode-panel\nRun: remnanode-panel\n'
