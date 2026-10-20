# VendorLedger — CTF build bundle (no OVA)

```
============================================================
        UNAUTHORIZED ACCESS IS JUST THE BEGINNING.
       Every service hides a secret. Every secret has a cost.
============================================================

████████╗████████╗██╗     ██╗██████╗  ██████╗██████╗
██╔═════╝██╔═════╝████╗   ██║██╔═══██╗╚═██╔═╝██╔═══██╗     ██████╗  ████╗  ██╗ ████╗██████╗
██████╗  ██████╗  ██╔═██╗ ██║██████╔═╝  ██║  ██████╔═╝   ██╔═════╝██╔═══██╗████╔═══╝██╔═══██╗
██╔═══╝  ██╔═══╝  ██║  ╚═████║██╔═██║    ██║  ██╔═██║     ██║      ██║   ██║██╔═╝    ██║   ██║
██║      ████████╗██║   ╚═██║██║ ╚═██╗██████╗██║ ╚═██╗██╗╚═██████╗╚═████╔═╝██║      ██████╔═╝
╚═╝      ╚═══════╝╚═╝     ╚═╝╚═╝   ╚═╝╚═════╝╚═╝   ╚═╝╚═╝  ╚═════╝  ╚═══╝  ╚═╝      ██╔═══╝
                                                                                     ██║
                                                                                     ╚═╝

------------------------------------------------------------
  [ SYSTEM ]   CTF ENVIRONMENT
  [ STATUS ]   ONLINE
  [ MISSION ]  ENUMERATE. EXPLOIT. ESCALATE.
  [ IP MACHINE ]
------------------------------------------------------------

  "The deeper you dig, the darker it gets."
  "Trust nothing. Verify everything. Leave no stone unturned."

============================================================
```

Everything needed to stand up the **VendorLedger** challenge on a fresh
**Ubuntu Server 22.04** box. Copy this folder in, run one script, and the whole
multi-host challenge is live — no OVA/VM image required.

> **Network isolation (required).** This box is *intentionally* vulnerable and
> hands out **root** (MySQL UDF). Use a VM network that is **Host-Only** (or
> **NAT** with explicit port-forwards). **Never** attach it with a **Bridged**
> adapter on a shared/home LAN — anyone on that network could reach SSH/HTTP and
> escalate to root.

```
vendorledger-build/
├─ provision.sh                # one-shot deploy (run as root in the VM)
├─ banner.txt                  # login banner template (IP injected at boot)
├─ webapp/                     # -> /var/www/vendorledger                (main app)
├─ maintenance/                # -> /var/www/maintenance_v001noreleased-debug-mode
│  └─ files/mainpage_check.zip #    tool served to players via download.php
├─ dev-mainpage/               # -> /var/www/dev-mainpage0080812569927  (JSON leak)
├─ gitea/
│  └─ build_repo.sh            # seeds the private forensics repo
├─ config/
│  ├─ apache/                  # vhosts: vendorledger, zz-maintenance-debug,
│  │                           #         zz-dev-mainpage, zz-gitea
│  ├─ gitea-app.ini.template   # filled with generated secrets at deploy time
│  ├─ gitea.service            # systemd unit for Gitea
│  ├─ 99-vendorledger.cnf      # bind loopback + secure_file_priv=''
│  ├─ mysql-root-override.conf # run mariadbd as root (UDF privesc)
│  ├─ vendorledger-banner.sh   # regenerate /etc/issue(.net) with the machine IP
│  ├─ vendorledger-banner.service # systemd oneshot: inject IP at boot
│  ├─ ufw.sh                   # allow 22 + 80 only
│  └─ hosts.sample             # example attacker /etc/hosts entries
├─ db/{schema,seed,grants}.sql
├─ tool/                       # mainpage_check.py + PyArmor/PyInstaller .exe + bundle
├─ exploits/                   # attacker-side assets (do NOT deploy)
├─ flags/                      # replace with your own before publishing
├─ writeup-progress.md         # current chain (this build)
└─ writeup.md                  # original intended chain (historical)
```

## 1. Deploy

On the target VM (fresh Ubuntu Server 22.04, root, internet access for the Gitea
binary):

```bash
# copy the bundle to the VM
scp -r vendorledger-build user@vm-ip:/tmp/

# deploy
ssh user@vm-ip
sudo bash /tmp/vendorledger-build/provision.sh
```

Then snapshot the VM so you can reset between runs.

## 2. Point the attacker at the box

Players add these names to their own `/etc/hosts` (use the box IP):

```bash
sudo tee -a /etc/hosts >/dev/null <<'EOF'
<box-ip> vendor.fenrir vendorledger.local
<box-ip> maintenance_v001noreleased-debug-mode.vendor.fenrir
<box-ip> dev-mainpage0080812569927.vendor.fenrir
<box-ip> gitea-developmentfenrir-corp-unittesting-alphabeta.vendor.fenrir
EOF
```

The vhost name is discoverable from a plain scan — `nmap -sV <box-ip>` reports
`http-title: VendorLedger - vendor.fenrir` and the response carries the header
`X-Vendor-Host: vendor.fenrir`.

## 3. Challenge chain

```
vendor.fenrir
  -> blind (time-based) SQLi on /search.php        (dump admin hash)
  -> crack -> login as admin
  -> /export.php "debug" trigger                   (leak maintenance subdomain)
  -> maintenance host: guest login (no password)
  -> crack weak JWT secret, forge role=technician
  -> technician console -> download mainpage_check.zip
  -> run the tool (mainpage_check.exe) -> sniff its POST     [dev-mainpage creds]
  -> login dev-mainpage -> JSON leaks gitea target + creds
  -> Gitea: private repo -> git forensics -> recover SSH creds
  -> ssh fenrir@<box> (unprivileged: no sudo/lxd)
  -> MySQL UDF privesc (dbops/sunshine, mariadbd-as-root) -> root.txt
```

Full step-by-step: see `writeup-progress.md`.

## 4. Credentials & intentional misconfigs

| What | Value | Where |
|---|---|---|
| Web admin | `admin` / `sunshine` (md5 `0571749e...`) | `db/seed.sql` |
| App DB user | `vledger` / `vledger_runtime_pw` (SELECT + read `mysql.*`) | `db/grants.sql` |
| MySQL ops user | `dbops` / `sunshine` (ALL incl. `FILE`) | `db/grants.sql` |
| Maintenance JWT secret | `maintenance` (weak, crackable) | `maintenance/index.php` |
| dev-mainpage login | `72364591234` / `ZSr2Wf{ifj[:7-5Uxq9LKSBn([v!ME` | `dev-mainpage/index.php` (bcrypt) |
| Gitea login | `fenrir-corp` / `%.M8Q61*i+tykaCm}Y3$FPYiNb9/D6` | leaked by dev-mainpage |
| SSH target (fenrir) | `fenrir` / `thismachinemadebyrizkyfebrianafif` | set on the box; leaked via git repo |
| Root | `root` / `4f1$Rvm4WYaK6W)q}{S1fu.PRL:pe(` | set explicitly by `provision.sh` (`ROOT_PASS`); reach via MySQL UDF privesc (`dbops`/`sunshine`, mariadbd-as-root) — `fenrir` is **not** in `sudo`/`lxd` |
| `secure_file_priv` | `''` (empty = no restriction; file I/O allowed) | `config/99-vendorledger.cnf` |
| DB process user | `root` | `config/mysql-root-override.conf` |
| Firewall | 22 + 80 only | `config/ufw.sh` |

> Note: the git-repo leak (`gitea/build_repo.sh`) and `provision.sh`
> (`FENRIR_PASS`) must carry the **same** `fenrir` password as the box, otherwise
> the final `ssh fenrir@<box>` step won't authenticate.

## 5. Reset / re-deploy

`provision.sh` is safe to re-run; it resets the `fenrir`/`root` passwords,
rotates the Gitea password, and creates the Gitea account/repo only if missing.
To fully rebuild the Gitea repo from scratch:

```bash
sudo -u git env HOME=/home/git GITEA_WORK_DIR=/var/lib/gitea USER=git \
  /usr/local/bin/gitea admin user delete --config /etc/gitea/app.ini \
  --username fenrir-corp
sudo systemctl restart gitea
sudo bash /tmp/vendorledger-build/provision.sh
```

## 6. Database engine note

Targets MySQL 5.5/5.6 behaviour; the provisioner installs **MariaDB 10.6** from
the stock Ubuntu 22.04 repo because it keeps the classic grant tables
(`mysql.user.File_priv` visible), supports the file-based UDF
(`CREATE FUNCTION ... SONAME`), and installs/runs cleanly under systemd. The
web hosts and the git-forensics stage do not depend on the DB engine.

## 7. Before you publish

- [ ] Replace `flags/user.txt` and `flags/root.txt` with unique values.
- [ ] Confirm no unintended paths (`find / -perm -4000` for stray SUIDs, extra sudo rules).
- [ ] Remove the bundle copy and shell history from the VM.
- [ ] Snapshot the clean state.
