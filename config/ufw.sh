#!/usr/bin/env bash
# External firewall: only SSH + HTTP reachable from the outside.
# MySQL (3306) stays loopback-only, forcing the attacker to pivot through the app.
set -euo pipefail

ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
# deliberately NOT: ufw allow 3306
ufw --force enable
ufw status verbose
