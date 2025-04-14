#!/bin/bash

# Server Monitoring Script
# Monitors server for suspicious activities and sends email alerts

# Usage: server_monitor.sh [config_file]
# Default config file: /etc/server_monitor.conf

CONFIG_FILE="${1:-/etc/server_monitor.conf}"

# Validate config file
if [ ! -f "$CONFIG_FILE" ] || [ ! -r "$CONFIG_FILE" ]; then
    echo "Error: Config file not found or unreadable: $CONFIG_FILE" >&2
    exit 1
fi

# Source configuration
source "$CONFIG_FILE"

# Validate critical variables
: "${ADMIN_EMAIL:?Error: ADMIN_EMAIL not set}"
: "${LOG_FILE:?Error: LOG_FILE not set}"
: "${ALERT_SUBJECT:?Error: ALERT_SUBJECT not set}"
: "${CRITICAL_DIR:?Error: CRITICAL_DIR not set}"
: "${SNAPSHOT_FILE:?Error: SNAPSHOT_FILE not set}"
: "${THRESHOLD_CPU:=80}"
: "${THRESHOLD_FAILED_LOGINS:=5}"
: "${THRESHOLD_NETWORK_CONNECTIONS:=100}"
: "${THRESHOLD_DISK:=90}"
: "${THRESHOLD_MEMORY:=80}"
: "${THRESHOLD_PROCESSES:=500}"

# Ensure log file is writable
touch "$LOG_FILE" 2>/dev/null || {
    echo "Error: Cannot write to log file: $LOG_FILE" >&2
    exit 1
}

# Function to log messages
log_message() {
    local level="$1" message="$2"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $level: $message" >> "$LOG_FILE"
}

# Function to send email alert and log it
send_alert() {
    local message="$1"
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
        failed_attempts=$(sudo grep -i "fail\|authentication failure" /var/log/auth.log | wc -l)
    elif [ -r /var/log/secure ]; then
        failed_attempts=$(sudo grep -i "fail\|authentication failure" /var/log/secure | wc -l)
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

# Main execution
log_message "INFO" "Starting server checks"

check_failed_logins
check_cpu_usage
check_file_changes
check_network
check_disk_usage
check_memory_usage
check_process_count

log_message "INFO" "Checks completed"
