#!/bin/bash

# Server Monitoring Script
# Monitors server for suspicious activities and sends email alerts securely

# Usage: server_monitor.sh [config_file]
# Default config file: /etc/server_monitor.conf

# Exit on any error
set -e

CONFIG_FILE="${1:-/etc/server_monitor.conf}"

# Validate config file
if [ ! -f "$CONFIG_FILE" ] || [ ! -r "$CONFIG_FILE" ]; then
    echo "Error: Config file not found or unreadable: $CONFIG_FILE" >&2
    exit 1
fi

# Sanitize config file path (prevent directory traversal)
CONFIG_FILE=$(realpath "$CONFIG_FILE" 2>/dev/null) || {
    echo "Error: Invalid config file path" >&2
    exit 1
}

# Source configuration
source "$CONFIG_FILE"

# Validate critical variables
: "${ADMIN_EMAIL:?Error: ADMIN_EMAIL not set}"
: "${LOG_FILE:?Error: LOG_FILE not set}"
: "${ALERT_SUBJECT:?Error: ALERT_SUBJECT not set}"
: "${CRITICAL_DIR:?Error: CRITICAL_DIR not set}"
: "${SNAPSHOT_FILE:?Error: SNAPSHOT_FILE not set}"
: "${USER_SNAPSHOT_FILE:?Error: USER_SNAPSHOT_FILE not set}"
: "${CRON_SNAPSHOT_FILE:?Error: CRON_SNAPSHOT_FILE not set}"
: "${THRESHOLD_CPU:=80}"
: "${THRESHOLD_FAILED_LOGINS:=5}"
: "${THRESHOLD_NETWORK_CONNECTIONS:=100}"
: "${THRESHOLD_DISK:=90}"
: "${THRESHOLD_MEMORY:=80}"
: "${THRESHOLD_PROCESSES:=500}"

# Validate email format (basic check)
if ! [[ "$ADMIN_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    echo "Error: Invalid ADMIN_EMAIL format" >&2
    exit 1
fi

# Ensure log file is writable
touch "$LOG_FILE" 2>/dev/null || {
    echo "Error: Cannot write to log file: $LOG_FILE" >&2
    exit 1
}

# Create secure temporary directory
TEMP_DIR=$(mktemp -d -t server_monitor.XXXXXX) || {
    echo "Error: Failed to create temporary directory" >&2
    exit 1
}
chmod 700 "$TEMP_DIR"
trap 'rm -rf "$TEMP_DIR"' EXIT

# Function to log messages
log_message() {
    local level="$1" message="$2"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $level: $message" >> "$LOG_FILE"
}

# Function to send email alert and log it
send_alert() {
    local message="$1"
    # Sanitize message to prevent injection
    message=$(printf '%s' "$message" | tr -d '\n\r')
    if ! echo "$message" | mail -s "$ALERT_SUBJECT" "$ADMIN_EMAIL" 2>/dev/null; then
        log_message "ERROR" "Failed to send email alert: $message"
    else
        log_message "ALERT" "$message"
    fi
}

# Function to check failed login attempts
check_failed_logins() {
    local failed_attempts=0
    if [ -r /var/log/auth.log ]; then
        failed_attempts=$(sudo grep -i "fail\|authentication failure" /var/log/auth.log 2>/dev/null | wc -l)
    elif [ -r /var/log/secure ]; then
        failed_attempts=$(sudo grep -i "fail\|authentication failure" /var/log/secure 2>/dev/null | wc -l)
    else
        log_message "ERROR" "Cannot access login logs"
        return
    fi
    if [ "$failed_attempts" -gt "$THRESHOLD_FAILED_LOGINS" ]; then
        send_alert "High number of failed login attempts detected: $failed_attempts"
    fi
}

# Function to check CPU usage
check_cpu_usage() {
    local cpu_usage
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed 's/.*: \([0-9.]*\)%us, \([0-9.]*\)%sy.*/\1 \2/' | awk '{print int($1 + $2)}')
    if [ -z "$cpu_usage" ]; then
        log_message "ERROR" "Failed to retrieve CPU usage"
        return
    fi
    if [ "$cpu_usage" -gt "$THRESHOLD_CPU" ]; then
        send_alert "High CPU usage detected: ${cpu_usage}%"
    fi
}

# Function to check for unauthorized file changes
check_file_changes() {
    if [ ! -d "$CRITICAL_DIR" ]; then
        log_message "ERROR" "Directory not found: $CRITICAL_DIR"
        return
    fi
    local current_md5
    current_md5=$(sudo find "$CRITICAL_DIR" -type f -exec md5sum {} \; 2>/dev/null | sort | md5sum | awk '{print $1}')
    if [ -z "$current_md5" ]; then
        log_message "ERROR" "Failed to compute MD5 for $CRITICAL_DIR"
        return
    fi
    if [ ! -f "$SNAPSHOT_FILE" ]; then
        echo "$current_md5" | sudo tee "$SNAPSHOT_FILE" >/dev/null
        log_message "INFO" "Created initial snapshot for $CRITICAL_DIR"
        return
    fi
    local previous_md5
    previous_md5=$(sudo cat "$SNAPSHOT_FILE" 2>/dev/null)
    if [ "$current_md5" != "$previous_md5" ]; then
        send_alert "Unauthorized changes detected in $CRITICAL_DIR"
        echo "$current_md5" | sudo tee "$SNAPSHOT_FILE" >/dev/null
    fi
}

# Function to check unusual network connections
check_network() {
    local suspicious_connections
    suspicious_connections=$(ss -tn state established 2>/dev/null | wc -l)
    suspicious_connections=$((suspicious_connections - 1))  # Subtract header
    if [ "$suspicious_connections" -gt "$THRESHOLD_NETWORK_CONNECTIONS" ]; then
        send_alert "Unusual number of network connections detected: $suspicious_connections"
    fi
}

# Function to check disk usage
check_disk_usage() {
    local disk_usage
    disk_usage=$(df -h / | tail -1 | awk '{print $5}' | tr -d '%')
    if [ -z "$disk_usage" ]; then
        log_message "ERROR" "Failed to retrieve disk usage"
        return
    fi
    if [ "$disk_usage" -gt "$THRESHOLD_DISK" ]; then
        send_alert "High disk usage detected: ${disk_usage}%"
    fi
}

# Function to check memory usage
check_memory_usage() {
    local mem_usage
    mem_usage=$(free | grep Mem | awk '{print int($3/$2 * 100)}')
    if [ -z "$mem_usage" ]; then
        log_message "ERROR" "Failed to retrieve memory usage"
        return
    fi
    if [ "$mem_usage" -gt "$THRESHOLD_MEMORY" ]; then
        send_alert "High memory usage detected: ${mem_usage}%"
    fi
}

# Function to check process count
check_process_count() {
    local process_count
    process_count=$(ps aux | wc -l)
    process_count=$((process_count - 1))  # Subtract header
    if [ "$process_count" -gt "$THRESHOLD_PROCESSES" ]; then
        send_alert "High process count detected: $process_count"
    fi
}

# Function to check for new user accounts
check_new_users() {
    local current_users
    current_users=$(sudo getent passwd | md5sum | awk '{print $1}')
    if [ -z "$current_users" ]; then
        log_message "ERROR" "Failed to retrieve user list"
        return
    fi
    if [ ! -f "$USER_SNAPSHOT_FILE" ]; then
        echo "$current_users" | sudo tee "$USER_SNAPSHOT_FILE" >/dev/null
        log_message "INFO" "Created initial user snapshot"
        return
    fi
    local previous_users
    previous_users=$(sudo cat "$USER_SNAPSHOT_FILE" 2>/dev/null)
    if [ "$current_users" != "$previous_users" ]; then
        send_alert "New or modified user accounts detected"
        echo "$current_users" | sudo tee "$USER_SNAPSHOT_FILE" >/dev/null
    fi
}

# Function to check for unexpected cron jobs
check_cron_jobs() {
    local current_cron
    current_cron=$(sudo find /etc/cron.* /var/spool/cron -type f 2>/dev/null | sort | md5sum | awk '{print $1}')
    if [ -z "$current_cron" ]; then
        log_message "ERROR" "Failed to retrieve cron job list"
        return
    fi
    if [ ! -f "$CRON_SNAPSHOT_FILE" ]; then
        echo "$current_cron" | sudo tee "$CRON_SNAPSHOT_FILE" >/dev/null
        log_message "INFO" "Created initial cron snapshot"
        return
    fi
    local previous_cron
    previous_cron=$(sudo cat "$CRON_SNAPSHOT_FILE" 2>/dev/null)
    if [ "$current_cron" != "$previous_cron" ]; then
        send_alert "Unexpected cron job changes detected"
        echo "$current_cron" | sudo tee "$CRON_SNAPSHOT_FILE" >/dev/null
    fi
}

# Function to check for suspicious processes
check_suspicious_processes() {
    local suspicious
    # Check for processes running from /tmp or consuming high CPU
    suspicious=$(ps aux --sort=-%cpu | awk '$6 > 1000000 || $4 > 50 || $11 ~ /^\/tmp\// {print $2, $11}' | head -n 5)
    if [ -n "$suspicious" ]; then
        send_alert "Suspicious processes detected: $(echo "$suspicious" | tr '\n' ';')"
    fi
}

# Main execution
log_message "INFO" "Starting server checks"

check_failed_logins
check_cpu_usage
check_file_changes
check_network
check_disk_usage
check_memory_usage
check_process_count
check_new_users
check_cron_jobs
check_suspicious_processes

log_message "INFO" "Checks completed"
