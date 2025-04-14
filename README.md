# Server Monitoring Script
This  script monitors a Linux server for suspicious activities and resource issues, sending email alerts to an administrator when thresholds are exceeded. It runs securely as a non-root user with `sudo` for specific tasks, minimizing security risks.
## Features
- **Failed Login Attempts**: Detects excessive failed logins from `/var/log/auth.log` or `/var/log/secure`.
- **CPU Usage**: Alerts on high CPU usage (default: >80%).
- **File Changes**: Monitors critical directories (e.g., `/etc`) for unauthorized changes.
- **Network Connections**: Detects unusual numbers of established connections.
- **Disk Usage**: Alerts on high disk usage (default: >90%).
- **Memory Usage**: Monitors memory consumption (default: >80%).
- **Process Count**: Detects excessive processes (default: >500).
- **New Users**: Alerts on new or modified user accounts.
- **Cron Jobs**: Detects changes to cron schedules.
- **Suspicious Processes**: Identifies processes with high resource usage or running from suspicious locations (e.g., `/tmp`).

## Requirements

- Linux server (Ubuntu/Debian or CentOS/RHEL recommended).
- Tools: `mail`, `iproute2` (`ss`), `procps` (`top`, `ps`, `free`), `coreutils` (`md5sum`, `df`), `sudo`.
- Configured mail server (e.g., `postfix`) for sending alerts.

## Installation

1. **Create a Dedicated User**:
sudo useradd -r -s /bin/false server-monitor

Install the Script:
Save the script as /usr/local/bin/server_monitor.sh.

Set permissions:
sudo chown server-monitor:server-monitor /usr/local/bin/server_monitor.sh
sudo chmod 750 /usr/local/bin/server_monitor.sh

place /etc/server_monitor.conf
Set permissions:
sudo chown server-monitor:server-monitor /etc/server_monitor.conf
sudo chmod 640 /etc/server_monitor.conf

Set Up Snapshot Directory:
sudo mkdir -p /var/lib/server_monitor
sudo chown server-monitor:server-monitor /var/lib/server_monitor
sudo chmod 750 /var/lib/server_monitor

Configure Sudo:
Create /etc/sudoers.d/server-monitor:
sudo visudo -f /etc/sudoers.d/server-monitor
Add:
server-monitor ALL=(root) NOPASSWD: /bin/grep -i "fail\|authentication failure" /var/log/auth.log, /bin/grep -i "fail\|authentication failure" /var/log/secure, /usr/bin/find /etc -type f -exec md5sum {} \;, /bin/cat /var/lib/server_monitor/*.md5, /usr/bin/tee /var/lib/server_monitor/*.md5, /usr/bin/getent passwd, /usr/bin/find /etc/cron.* /var/spool/cron -type f

Verify:
sudo visudo -cf /etc/sudoers.d/server-monitor

Install Dependencies:
Ubuntu/Debian:
sudo apt update
sudo apt install mailutils iproute2 procps coreutils sudo postfix

CentOS/RHEL:
sudo yum install mailx iproute procps-ng coreutils sudo postfix
Set Up Email:
Configure postfix or an SMTP relay.
Test:
echo "Test" | mail -s "Test Alert" admin@example.com

Set Up Logging:
sudo touch /var/log/server_monitor.log
sudo chown server-monitor:server-monitor /var/log/server_monitor.log
sudo chmod 640 /var/log/server_monitor.log

Schedule with Cron:
Edit crontab for server-monitor:
sudo -u server-monitor crontab -e
Add:
*/5 * * * * /usr/local/bin/server_monitor.sh /etc/server_monitor.conf

Usage
The script runs every 5 minutes via cron, checking for issues and sending alerts.
Logs are stored in /var/log/server_monitor.log.

Test manually:
sudo -u server-monitor /usr/local/bin/server_monitor.sh /etc/server_monitor.conf

Monitor logs:
tail -f /var/log/server_monitor.log

Configuration
Edit /etc/server_monitor.conf to adjust:
ADMIN_EMAIL: Recipient for alerts.
Thresholds: THRESHOLD_* for CPU, disk, memory, etc.
CRITICAL_DIR: Directory to monitor for changes.
Snapshot files: Paths for storing MD5 checksums.

Security Notes
Runs as server-monitor user, using sudo for minimal privileged tasks.
Validates inputs to prevent injection or traversal attacks.
Uses secure temporary files and restricted permissions.
Restrict sudo to specific commands only.

Troubleshooting
No emails: Check postfix logs (/var/log/mail.log) and test email delivery.
Permission errors: Verify sudoers file and file ownership.
Missing tools: Ensure all dependencies are installed.
False positives: Adjust thresholds in the config file.

License
MIT License. Use and modify freely, at your own risk.
