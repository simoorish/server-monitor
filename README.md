
# 🖥️ Server Monitoring Script

A secure and lightweight **Bash script** for monitoring Linux servers. It tracks suspicious activity and system health, sending email alerts to an administrator when thresholds are exceeded. Designed to run safely as a **non-root user** with minimal `sudo` privileges.

---

## 🚀 Features

- **Failed Login Detection**: Monitors `/var/log/auth.log` or `/var/log/secure` for repeated failed logins.
- **CPU Usage**: Alerts when CPU exceeds 80% (configurable).
- **Disk Usage**: Sends alerts when disk usage surpasses 90%.
- **Memory Usage**: Notifies if memory consumption goes over 80%.
- **Process Count**: Alerts if total processes exceed 500.
- **Network Activity**: Detects unusually high number of established connections.
- **File Integrity Monitoring**: Tracks changes in critical directories like `/etc`.
- **User Monitoring**: Detects newly created or modified user accounts.
- **Cron Changes**: Tracks changes in system and user cron jobs.
- **Suspicious Processes**: Flags processes using excessive resources or running from temp directories (e.g., `/tmp`).

---

## 📋 Requirements

- Linux system (Ubuntu/Debian or CentOS/RHEL recommended)
- Installed tools:
  - `mail`, `postfix` or any SMTP setup
  - `iproute2` (`ss`)
  - `procps` (`top`, `ps`, `free`)
  - `coreutils` (`md5sum`, `df`)
  - `sudo`

---

## 🛠️ Installation

### 1. Create a Dedicated User

```bash
sudo useradd -r -s /bin/false server-monitor
```

### 2. Install the Script

Save the script as:

```bash
/usr/local/bin/server_monitor.sh
```

Set permissions:

```bash
sudo chown server-monitor:server-monitor /usr/local/bin/server_monitor.sh
sudo chmod 750 /usr/local/bin/server_monitor.sh
```

---

### 3. Create the Configuration File

Create `/etc/server_monitor.conf`:

```bash
# Server Monitoring Configuration
ADMIN_EMAIL="admin@example.com"
LOG_FILE="/var/log/server_monitor.log"
ALERT_SUBJECT="Server Alert"

THRESHOLD_CPU=80
THRESHOLD_FAILED_LOGINS=5
THRESHOLD_NETWORK_CONNECTIONS=100
THRESHOLD_DISK=90
THRESHOLD_MEMORY=80
THRESHOLD_PROCESSES=500

CRITICAL_DIR="/etc"
SNAPSHOT_FILE="/var/lib/server_monitor/etc_snapshot.md5"
USER_SNAPSHOT_FILE="/var/lib/server_monitor/user_snapshot.md5"
CRON_SNAPSHOT_FILE="/var/lib/server_monitor/cron_snapshot.md5"
```

Set permissions:

```bash
sudo chown server-monitor:server-monitor /etc/server_monitor.conf
sudo chmod 640 /etc/server_monitor.conf
```

---

### 4. Set Up Snapshot Directory

```bash
sudo mkdir -p /var/lib/server_monitor
sudo chown server-monitor:server-monitor /var/lib/server_monitor
sudo chmod 750 /var/lib/server_monitor
```

---

### 5. Configure Sudo Access

Create sudoers file:

```bash
sudo visudo -f /etc/sudoers.d/server-monitor
```

Add the following rules:

```bash
server-monitor ALL=(root) NOPASSWD: \
/bin/grep -i "fail\|authentication failure" /var/log/auth.log, \
/bin/grep -i "fail\|authentication failure" /var/log/secure, \
/usr/bin/find /etc -type f -exec md5sum {} \;, \
/bin/cat /var/lib/server_monitor/*.md5, \
/usr/bin/tee /var/lib/server_monitor/*.md5, \
/usr/bin/getent passwd, \
/usr/bin/find /etc/cron.* /var/spool/cron -type f
```

Verify:

```bash
sudo visudo -cf /etc/sudoers.d/server-monitor
```

---

### 6. Install Dependencies

**Ubuntu/Debian:**

```bash
sudo apt update
sudo apt install mailutils iproute2 procps coreutils sudo postfix
```

**CentOS/RHEL:**

```bash
sudo yum install mailx iproute procps-ng coreutils sudo postfix
```

---

### 7. Set Up Email

Make sure `postfix` is properly configured or use an external SMTP relay. Test email sending:

```bash
echo "Test" | mail -s "Test Alert" admin@example.com
```

---

### 8. Set Up Logging

```bash
sudo touch /var/log/server_monitor.log
sudo chown server-monitor:server-monitor /var/log/server_monitor.log
sudo chmod 640 /var/log/server_monitor.log
```

---

### 9. Schedule with Cron

Edit crontab for `server-monitor`:

```bash
sudo -u server-monitor crontab -e
```

Add:

```bash
*/5 * * * * /usr/local/bin/server_monitor.sh /etc/server_monitor.conf
```

---

## 📈 Usage

- Runs every 5 minutes via cron.
- Logs saved to `/var/log/server_monitor.log`.
- Alerts sent via email on threshold breaches.

Manual test:

```bash
sudo -u server-monitor /usr/local/bin/server_monitor.sh /etc/server_monitor.conf
```

Monitor logs:

```bash
tail -f /var/log/server_monitor.log
```

---

## ⚙️ Configuration Overview

Edit `/etc/server_monitor.conf`:

- `ADMIN_EMAIL`: Set alert recipient.
- Thresholds: `THRESHOLD_CPU`, `THRESHOLD_DISK`, etc.
- `CRITICAL_DIR`: Directory for integrity monitoring.
- `*_SNAPSHOT_FILE`: MD5 snapshot paths.

---

## 🔐 Security Notes

- Runs as a **restricted user** (`server-monitor`) with minimal `sudo` access.
- Validates inputs to prevent injection or traversal.
- Uses **secure permissions** on sensitive files and logs.
- Sudo access is tightly scoped to essential read-only commands.

---

## 🛠️ Troubleshooting

- **No emails?**
  - Check mail logs: `/var/log/mail.log`
  - Test email delivery manually.
- **Permission errors?**
  - Review `sudoers` file and file ownerships.
- **False positives?**
  - Adjust thresholds in the config.

---

## 📬 License

MIT — use freely and contribute!

---

## 🤝 Contributions

Pull requests and issue reports are welcome!
