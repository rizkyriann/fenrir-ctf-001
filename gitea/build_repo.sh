#!/bin/bash
set -e

USER="fenrir-corp"
PASS='%.M8Q61*i+tykaCm}Y3$FPYiNb9/D6'
REPO="/tmp/fenrir-deploy"
BASE="http://127.0.0.1:3000"
PLAIN="thismachinemadebyrizkyfebrianafif"
B64=$(printf '%s' "$PLAIN" | base64)
AUTH=$(printf '%s:%s' "$USER" "$PASS" | base64 | tr -d '\n')

rm -rf "$REPO"
mkdir -p "$REPO"
cd "$REPO"
git init -q -b main
git config user.name "Mara Ops"
git config user.email "mara@fenrir.local"

commit() { # msg, date
  git add -A
  GIT_AUTHOR_DATE="$2" GIT_COMMITTER_DATE="$2" git commit -q -m "$1"
}

# ---------- c1 ----------
mkdir -p roles/common/tasks
cat > README.md <<'EOF'
# fenrir-deploy

Ansible playbooks used to provision and maintain the `fenrir` fleet.

```
ansible-playbook -i inventory.ini site.yml
```

See `docs/onboarding.md` before making changes.
EOF

cat > ansible.cfg <<'EOF'
[defaults]
inventory = inventory.ini
host_key_checking = False
retry_files_enabled = False
EOF

cat > inventory.ini <<EOF
[fenrir_hosts]
fenrir-host ansible_host=10.10.10.10

[fenrir_hosts:vars]
ansible_user=fenrir
ansible_ssh_pass=${PLAIN}
ansible_python_interpreter=/usr/bin/python3
EOF

cat > roles/common/tasks/main.yml <<'EOF'
---
- name: ensure base packages
  apt:
    name:
      - curl
      - vim
    state: present
EOF

commit "Initial import of ops provisioning repo" "2023-05-12T09:14:00+00:00"

# ---------- c2 ----------
cat > roles/common/tasks/main.yml <<'EOF'
---
- name: ensure base packages
  apt:
    name:
      - curl
      - vim
      - htop
    state: present

- name: ensure ops user
  user:
    name: fenrir
    shell: /bin/bash
    groups: sudo
    append: yes
EOF

mkdir -p roles/common/defaults
cat > roles/common/defaults/main.yml <<'EOF'
---
ops_user: fenrir
ops_groups: [sudo]
EOF

commit "common: add ops user and extra packages" "2023-05-20T16:42:00+00:00"

# ---------- c3 ----------
mkdir -p roles/nginx/tasks roles/php/tasks
cat > roles/nginx/tasks/main.yml <<'EOF'
---
- name: install nginx
  apt:
    name: nginx
    state: present
EOF

cat > roles/php/tasks/main.yml <<'EOF'
---
- name: install php
  apt:
    name:
      - php-fpm
      - php-mysql
    state: present
EOF

commit "add nginx and php roles" "2023-06-02T11:05:00+00:00"

# ---------- c4 ----------
mkdir -p group_vars
cat > group_vars/all.yml <<'EOF'
---
env: staging
ssh_port: 22
# SSH credentials are managed via Ansible Vault (group_vars/all/vault.yml)
EOF

cat > group_vars/staging.yml <<'EOF'
---
deploy_branch: main
EOF

commit "group_vars for staging" "2023-06-15T08:31:00+00:00"

# ---------- c5 ----------
cat > inventory.ini <<'EOF'
[fenrir_hosts]
fenrir-host ansible_host=10.10.10.10

[fenrir_hosts:vars]
ansible_user=fenrir
ansible_ssh_pass={{ vault_ssh_pass }}
ansible_python_interpreter=/usr/bin/python3
EOF

mkdir -p group_vars/all
cat > group_vars/all/vault.yml <<'EOF'
$ANSIBLE_VAULT;1.1;AES256
6338643537333966363661313837306130613833353033356232376466653234643039353138323235
393036626537356635623638353961336136303864303962316666333734623934323432340a393636
34326561373332663231326564633835333066393366376164663837373738633565306166663631
3831386537653733666566343065626634356338336635660a333464383838383662663030633634
38316434323862666139656438633365306430633930333130316539373839363862323837663363
EOF

cat > group_vars/all.yml <<'EOF'
---
env: staging
ssh_port: 22
vault_ssh_pass: "{{ lookup('file', 'group_vars/all/vault.yml') }}"
EOF

commit "rotate SSH credentials into Ansible Vault" "2024-01-08T14:20:00+00:00"

# ---------- c6 ----------
mkdir -p docs
cat > docs/onboarding.md <<'EOF'
# Ops onboarding

## Secrets

All secrets (SSH passwords, DB credentials) live in **Ansible Vault**.
The vault password itself is kept in the team password manager — ping `#ops-tools`.

Never commit plaintext secrets to this repository. If you spot one, rotate it
immediately and rewrite history.

## Deployment

1. `ansible-vault edit group_vars/all/vault.yml`
2. `ansible-playbook -i inventory.ini site.yml --ask-vault-pass`
EOF

cat > README.md <<'EOF'
# fenrir-deploy

Ansible playbooks used to provision and maintain the `fenrir` fleet.

```
ansible-playbook -i inventory.ini site.yml --ask-vault-pass
```

See `docs/onboarding.md` before making changes.
EOF

commit "document vault usage and onboarding" "2024-01-09T10:12:00+00:00"

# ---------- c7 ----------
mkdir -p scripts
cat > .pre-commit-config.yaml <<'EOF'
repos:
  - repo: local
    hooks:
      - id: scan-secrets
        name: scan for accidentally committed secrets
        entry: scripts/scan_secrets.sh
        language: script
EOF

cat > scripts/scan_secrets.sh <<'EOF'
#!/bin/bash
# naive secret scanner for CI
if git diff --cached | grep -qiE 'ansible_ssh_pass=[^ {]|password\s*[:=]\s*[^ {]'; then
  echo "possible plaintext secret detected" >&2
  exit 1
fi
EOF
chmod +x scripts/scan_secrets.sh

commit "add secret-scanner pre-commit hook" "2024-02-01T09:45:00+00:00"

# ---------- c8 ----------
mkdir -p roles/logrotate/tasks
cat > roles/logrotate/tasks/main.yml <<'EOF'
---
- name: install logrotate
  apt:
    name: logrotate
    state: present
EOF

cat > ansible.cfg <<'EOF'
[defaults]
inventory = inventory.ini
host_key_checking = False
retry_files_enabled = False

[privilege_escalation]
become = True
become_method = sudo
EOF

commit "add logrotate role and become defaults" "2024-03-01T13:00:00+00:00"

C5=$(git rev-parse HEAD~3)

# ---------- hidden debug commit (NOT on main) ----------
git checkout -q -b debug/vars-dump "$C5"
mkdir -p dump scripts
cat > dump/all_vars.json <<EOF
{
  "host": "fenrir-host",
  "ansible_user": "fenrir",
  "ansible_ssh_pass": "${B64}",
  "note": "temporary dump to debug the vault lookup - DO NOT COMMIT"
}
EOF

cat > scripts/dump_vars.sh <<'EOF'
#!/bin/bash
# dump the resolved ansible hostvars for a single host (debugging aid)
ansible-inventory -i inventory.ini --host fenrir-host --list > dump/all_vars.json
EOF
chmod +x scripts/dump_vars.sh

git add -A
GIT_AUTHOR_DATE="2024-01-08T15:02:00+00:00" GIT_COMMITTER_DATE="2024-01-08T15:02:00+00:00" \
  git commit -q -m "debug: dump all vars for fenrir-host"
DBG=$(git rev-parse HEAD)

git checkout -q main
git branch -D debug/vars-dump >/dev/null
git update-ref refs/archive/legacy-dbg "$DBG"

# ---------- push ----------
git remote add origin "${BASE}/${USER}/fenrir-deploy.git"
git -c credential.helper= -c http.extraHeader="Authorization: Basic ${AUTH}" push -q "${BASE}/${USER}/fenrir-deploy.git" main

if git -c credential.helper= -c http.extraHeader="Authorization: Basic ${AUTH}" push -q "${BASE}/${USER}/fenrir-deploy.git" refs/archive/legacy-dbg:refs/archive/legacy-dbg 2>/tmp/hidden_push.err; then
  echo "HIDDEN REF: pushed refs/archive/legacy-dbg"
else
  echo "HIDDEN REF: custom ref rejected, falling back to branch"
  cat /tmp/hidden_push.err
  git -c credential.helper= -c http.extraHeader="Authorization: Basic ${AUTH}" push -q "${BASE}/${USER}/fenrir-deploy.git" "$DBG:refs/heads/archive/legacy-dbg"
fi

echo "--- main commits ---"
git log --oneline main
echo "--- ls-remote ---"
git -c credential.helper= -c http.extraHeader="Authorization: Basic ${AUTH}" ls-remote "${BASE}/${USER}/fenrir-deploy.git"
