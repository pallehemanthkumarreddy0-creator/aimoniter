#!/bin/bash
# get_metrics.sh — outputs system metrics as JSON

# CPU usage (%) — average over 1 second
cpu=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}')

# Memory usage
mem_total=$(free -m | awk '/Mem:/ {print $2}')
mem_used=$(free -m | awk '/Mem:/ {print $3}')
mem_percent=$(awk "BEGIN {printf \"%.1f\", ($mem_used/$mem_total)*100}")

# Disk usage (root partition)
disk_percent=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')

# Top 10 processes by CPU
processes=$(ps -eo pid,comm,%cpu,%mem --sort=-%cpu | awk 'NR>1 && NR<=11 {
  printf "{\"pid\":%s,\"name\":\"%s\",\"cpu\":%s,\"mem\":%s},", $1, $2, $3, $4
}' | sed 's/,$//')

# Uptime
uptime_str=$(uptime -p)

# Timestamp
timestamp=$(date '+%Y-%m-%d %H:%M:%S')

# Build JSON
cat <<EOF
{
  "timestamp": "$timestamp",
  "cpu": $cpu,
  "mem_percent": $mem_percent,
  "mem_used_mb": $mem_used,
  "mem_total_mb": $mem_total,
  "disk_percent": $disk_percent,
  "uptime": "$uptime_str",
  "processes": [$processes]
}
EOF
