#!/usr/bin/env bash
#
# VendorLedger CTF - full one-shot provisioner
# ---------------------------------------------------------------------------
# Stands up the ENTIRE challenge on a fresh Ubuntu Server 22.04 box (no OVA).
# Run as root inside the VM:
#
#     sudo bash provision.sh
#
# It deploys four HTTP hosts on port 80 + Gitea, and prepares the SSH target:
#
#   vendor.fenrir                                   -> main PHP app (SQLi entry)
#   maintenance_v001noreleased-debug-mode.vendor.fenrir
#                                                   -> maintenance node (JWT)
#   dev-mainpage0080812569927.vendor.fenrir         -> leaks gitea creds (JSON)
#   gitea-developmentfenrir-corp-unittesting-alphabeta.vendor.fenrir
#                                                   -> private repo (forensics)
#
#   ssh fenrir@<box>  (password recovered from the git repo)
#
# Default DB engine: MariaDB 10.6 (Ubuntu repo). See README.md notes.
# ---------------------------------------------------------------------------
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ $EUID -eq 0 ]] || { echo "run as root (sudo bash provision.sh)"; exit 1; }

GITEA_VER="1.22.6"
GITEA_HOST="gitea-developmentfenrir-corp-unittesting-alphabeta.vendor.fenrir"
GITEA_USER="fenrir-corp"
GITEA_PASS='%.M8Q61*i+tykaCm}Y3$FPYiNb9/D6'
FENRIR_PASS="thismachinemadebyrizkyfebrianafif"
ROOT_PASS='4f1$Rvm4WYaK6W)q}{S1fu.PRL:pe('

HOSTS_NAMES=(
  "vendor.fenrir"
  "vendorledger.local"
  "maintenance_v001noreleased-debug-mode.vendor.fenrir"
  "dev-mainpage0080812569927.vendor.fenrir"
  "$GITEA_HOST"
)

echo "[*] 1/9 installing packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y apache2 libapache2-mod-php php-mysql \
                   mariadb-server mariadb-client ufw gcc git curl
a2enmod php8.1 >/dev/null 2>&1 || true
a2enmod proxy proxy_http >/dev/null 2>&1 || true
a2enmod headers >/dev/null 2>&1 || true

echo "[*] 2/9 adding host entries"
for h in "${HOSTS_NAMES[@]}"; do
  grep -q "[[:space:]]${h}\\([[:space:]]\\|$\\)" /etc/hosts || \
    echo "127.0.0.1 ${h}" >> /etc/hosts
done

echo "[*] 3/9 deploying web apps"
deploy_app() {
  local src="$1" dst="$2"
  mkdir -p "$dst"
  cp -r "$src"/. "$dst"/
  find "$dst" -type d -exec chmod 755 {} \;
  find "$dst" -type f -exec chmod 644 {} \;
  chown -R www-data:www-data "$dst"
}
deploy_app "$HERE/webapp"     /var/www/vendorledger
deploy_app "$HERE/maintenance" /var/www/maintenance_v001noreleased-debug-mode
deploy_app "$HERE/dev-mainpage" /var/www/dev-mainpage0080812569927

echo "[*] 4/9 configuring apache vhosts"
cp "$HERE"/config/apache/vendorledger.conf          /etc/apache2/sites-available/vendorledger.conf
cp "$HERE"/config/apache/zz-maintenance-debug.conf  /etc/apache2/sites-available/zz-maintenance-debug.conf
cp "$HERE"/config/apache/zz-dev-mainpage.conf       /etc/apache2/sites-available/zz-dev-mainpage.conf
cp "$HERE"/config/apache/zz-gitea.conf              /etc/apache2/sites-available/zz-gitea.conf
a2ensite vendorledger zz-maintenance-debug zz-dev-mainpage zz-gitea >/dev/null
a2dissite 000-default >/dev/null 2>&1 || true
systemctl enable --now apache2
apache2ctl configtest
systemctl reload apache2

echo "[*] 5/9 configuring database (MariaDB as root, secure_file_priv off)"
systemctl enable --now mariadb
cp "$HERE"/config/99-vendorledger.cnf /etc/mysql/mariadb.conf.d/99-vendorledger.cnf
mkdir -p /etc/systemd/system/mariadb.service.d
cp "$HERE"/config/mysql-root-override.conf /etc/systemd/system/mariadb.service.d/override.conf
systemctl daemon-reload
systemctl restart mariadb
for i in $(seq 1 15); do mysqladmin ping >/dev/null 2>&1 && break; sleep 1; done
mysql < "$HERE"/db/schema.sql
mysql < "$HERE"/db/seed.sql
mysql < "$HERE"/db/grants.sql

echo "[*] 6/9 installing Gitea $GITEA_VER"
if ! id git >/dev/null 2>&1; then
  adduser --system --shell /bin/bash --gecos 'Git Version Control' \
          --group --disabled-password --home /home/git git
fi
install -d -o git  -g git  -m 750 /var/lib/gitea/custom /var/lib/gitea/data /var/lib/gitea/log
install -d -o root -g git  -m 770 /etc/gitea

if [ ! -x /usr/local/bin/gitea ]; then
  curl -fsSL -o /tmp/gitea "https://dl.gitea.com/gitea/${GITEA_VER}/gitea-${GITEA_VER}-linux-amd64"
  install -m 0755 /tmp/gitea /usr/local/bin/gitea
  rm -f /tmp/gitea
fi

SECRET_KEY=$(/usr/local/bin/gitea generate secret SECRET_KEY)
INTERNAL_TOKEN=$(/usr/local/bin/gitea generate secret INTERNAL_TOKEN)
JWT_SECRET=$(/usr/local/bin/gitea generate secret JWT_SECRET)
sed -e "s#__HOST__#${GITEA_HOST}#g" \
    -e "s#__SECRET_KEY__#${SECRET_KEY}#g" \
    -e "s#__INTERNAL_TOKEN__#${INTERNAL_TOKEN}#g" \
    -e "s#__JWT_SECRET__#${JWT_SECRET}#g" \
    "$HERE"/config/gitea-app.ini.template > /etc/gitea/app.ini
chown root:git /etc/gitea/app.ini
chmod 640 /etc/gitea/app.ini

cp "$HERE"/config/gitea.service /etc/systemd/system/gitea.service
systemctl daemon-reload
systemctl enable --now gitea
for i in $(seq 1 40); do curl -sf -o /dev/null http://127.0.0.1:3000/ && break; sleep 1; done

echo "[*] 7/9 seeding Gitea account + private repo"
if ! sudo -u git env HOME=/home/git GITEA_WORK_DIR=/var/lib/gitea USER=git \
       /usr/local/bin/gitea admin user list --config /etc/gitea/app.ini 2>/dev/null \
       | grep -qw "$GITEA_USER"; then
  sudo -u git env HOME=/home/git GITEA_WORK_DIR=/var/lib/gitea USER=git \
    /usr/local/bin/gitea admin user create --config /etc/gitea/app.ini \
    --username "$GITEA_USER" --password "$GITEA_PASS" \
    --email "fenrir-corp@fenrir.local" --must-change-password=false
else
  sudo -u git env HOME=/home/git GITEA_WORK_DIR=/var/lib/gitea USER=git \
    /usr/local/bin/gitea admin user change-password --config /etc/gitea/app.ini \
    --username "$GITEA_USER" --password "$GITEA_PASS" --must-change-password=false
fi

if ! curl -sf -u "${GITEA_USER}:${GITEA_PASS}" \
       "http://127.0.0.1:3000/api/v1/repos/${GITEA_USER}/fenrir-deploy" -o /dev/null; then
  curl -sf -u "${GITEA_USER}:${GITEA_PASS}" -H 'Content-Type: application/json' \
    -X POST http://127.0.0.1:3000/api/v1/user/repos \
    -d '{"name":"fenrir-deploy","private":true,"auto_init":false,"default_branch":"main"}' \
    -o /dev/null
  bash "$HERE"/gitea/build_repo.sh
fi

echo "[*] 8/9 placing flags + SSH target user"
if ! id fenrir >/dev/null 2>&1; then
  useradd -m -s /bin/bash fenrir
fi
chmod 750 /home/fenrir
install -m 640 -o fenrir -g fenrir "$HERE"/flags/user.txt /home/fenrir/user.txt
install -m 600 -o root -g root "$HERE"/flags/root.txt /root/root.txt

# root password is set explicitly so the README does not lie about it.
# (root SSH login stays blocked by the default PermitRootLogin prohibit-password;
#  the intended path to root is still the MySQL UDF privesc below.)
echo "root:${ROOT_PASS}" | chpasswd

# fenrir is an unprivileged foothold: no root-granting groups (sudo/lxd).
deluser fenrir sudo 2>/dev/null || true
deluser fenrir lxd  2>/dev/null || true
echo "fenrir:${FENRIR_PASS}" | chpasswd
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
echo "PasswordAuthentication yes" > /etc/ssh/sshd_config.d/99-ctf.conf
systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true

echo "[*] 8b/9 installing login banner (console + SSH, IP injected at boot)"
install -d -m 755 /etc/vendorledger
install -m 644 "$HERE"/banner.txt /etc/vendorledger/banner.tmpl
install -m 755 "$HERE"/config/vendorledger-banner.sh /usr/local/sbin/vendorledger-banner
install -m 644 "$HERE"/config/vendorledger-banner.service /etc/systemd/system/vendorledger-banner.service
printf 'Banner /etc/issue.net\n' > /etc/ssh/sshd_config.d/99-ctf-banner.conf
chmod 644 /etc/ssh/sshd_config.d/99-ctf-banner.conf
# quiet the default Ubuntu MOTD noise
rm -f /etc/update-motd.d/50-landscape-sysinfo
chmod -x /etc/update-motd.d/10-help-text /etc/update-motd.d/50-motd-news 2>/dev/null || true
systemctl daemon-reload
systemctl enable --now vendorledger-banner.service
systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true

echo "[*] 9/9 applying firewall"
bash "$HERE"/config/ufw.sh

echo
echo "[+] Done. Challenge hosts (add these to your attacker /etc/hosts -> <box-ip>):"
for h in "${HOSTS_NAMES[@]}"; do echo "      $h"; done
echo
echo "    start:      http://vendor.fenrir/"
echo "    ssh target: ssh fenrir@<box-ip>   (recover the password via git forensics)"
echo "    mysql:      127.0.0.1:3306 only (blocked externally)"
