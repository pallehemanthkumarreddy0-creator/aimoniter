# System Metrics Dashboard — Full Setup Guide (WSL Ubuntu + Nginx)

## Architecture
```
[your bash script] --loop every 5s--> metrics.json --> [nginx serves it] --> [browser polls it via JS]
```
No backend server needed. Nginx just serves a JSON file that a background loop keeps updating.

---

## Step 1: Install nginx in WSL

Open your WSL Ubuntu terminal:

```bash
sudo apt update
sudo apt install nginx -y
sudo service nginx start
```

Check it's running:
```bash
sudo service nginx status
```

Test it — open a **Windows browser** and go to `http://localhost/`
You should see the default "Welcome to nginx!" page. (WSL2 auto-forwards localhost to Windows, so this just works.)

> Note: WSL usually doesn't run systemd by default, so use `sudo service nginx start` instead of `systemctl`. If you've enabled systemd in WSL (`/etc/wsl.conf` has `systemd=true`), `sudo systemctl start nginx` works too.

---

## Step 2: Set up the web root

We'll use nginx's default root: `/var/www/html/`

```bash
sudo chown -R $USER:$USER /var/www/html
```
(This lets you write files there without `sudo` every time — fine for a local project.)

---

## Step 3: Your metrics script (outputs JSON)

Save this as `~/metrics/get_metrics.sh`:

```bash
mkdir -p ~/metrics
```

```bash
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
```

Make it executable and test it:
```bash
chmod +x ~/metrics/get_metrics.sh
~/metrics/get_metrics.sh
```

You should see valid JSON printed. If `mem` or `cpu` looks wrong, run each `awk`/`free`/`top` line separately to debug — output formats vary slightly across systems.

---

## Step 4: Loop script to keep metrics.json updated

Save as `~/metrics/run_loop.sh`:

```bash
#!/bin/bash
while true; do
  ~/metrics/get_metrics.sh > /var/www/html/metrics.json
  sleep 5
done
```

```bash
chmod +x ~/metrics/run_loop.sh
```

Run it in the background:
```bash
nohup ~/metrics/run_loop.sh > ~/metrics/loop.log 2>&1 &
```

Check it's working:
```bash
cat /var/www/html/metrics.json
```
It should update every time you re-run that command (wait 5s between checks).

> To stop it later: `pkill -f run_loop.sh`
> To make it survive WSL restarts, add the `nohup` line to `~/.bashrc`, or better — set it up as a proper systemd service (Step 7, optional).

---

## Step 5: The dashboard (HTML + JS)

Save as `/var/www/html/index.html`:

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>System Metrics Dashboard</title>
<style>
  body { font-family: 'Segoe UI', sans-serif; background: #0f172a; color: #e2e8f0; margin: 0; padding: 24px; }
  h1 { font-size: 22px; margin-bottom: 4px; }
  .timestamp { color: #94a3b8; font-size: 13px; margin-bottom: 20px; }
  .cards { display: flex; gap: 16px; flex-wrap: wrap; margin-bottom: 24px; }
  .card { background: #1e293b; border-radius: 10px; padding: 16px 20px; min-width: 140px; }
  .card .label { color: #94a3b8; font-size: 13px; }
  .card .value { font-size: 28px; font-weight: 600; margin-top: 4px; }
  .bar-bg { background: #334155; border-radius: 6px; height: 8px; margin-top: 8px; overflow: hidden; }
  .bar-fill { height: 100%; background: #38bdf8; transition: width 0.4s; }
  table { width: 100%; border-collapse: collapse; background: #1e293b; border-radius: 10px; overflow: hidden; }
  th, td { text-align: left; padding: 10px 14px; font-size: 14px; }
  th { background: #273449; color: #94a3b8; font-weight: 500; }
  tr:nth-child(even) { background: #23324a; }
</style>
</head>
<body>

<h1>📊 System Metrics Dashboard</h1>
<div class="timestamp" id="timestamp">Loading...</div>

<div class="cards">
  <div class="card">
    <div class="label">CPU Usage</div>
    <div class="value" id="cpu-val">--%</div>
    <div class="bar-bg"><div class="bar-fill" id="cpu-bar" style="width:0%"></div></div>
  </div>
  <div class="card">
    <div class="label">Memory Usage</div>
    <div class="value" id="mem-val">--%</div>
    <div class="bar-bg"><div class="bar-fill" id="mem-bar" style="width:0%"></div></div>
  </div>
  <div class="card">
    <div class="label">Disk Usage</div>
    <div class="value" id="disk-val">--%</div>
    <div class="bar-bg"><div class="bar-fill" id="disk-bar" style="width:0%"></div></div>
  </div>
  <div class="card">
    <div class="label">Uptime</div>
    <div class="value" id="uptime-val" style="font-size:16px;">--</div>
  </div>
</div>

<h2>Top Processes</h2>
<table>
  <thead>
    <tr><th>PID</th><th>Name</th><th>CPU %</th><th>MEM %</th></tr>
  </thead>
  <tbody id="process-table"></tbody>
</table>

<script>
async function updateMetrics() {
  try {
    const res = await fetch('metrics.json?_=' + Date.now()); // cache-bust
    const data = await res.json();

    document.getElementById('timestamp').innerText = 'Last updated: ' + data.timestamp;

    document.getElementById('cpu-val').innerText = data.cpu + '%';
    document.getElementById('cpu-bar').style.width = data.cpu + '%';

    document.getElementById('mem-val').innerText = data.mem_percent + '%';
    document.getElementById('mem-bar').style.width = data.mem_percent + '%';

    document.getElementById('disk-val').innerText = data.disk_percent + '%';
    document.getElementById('disk-bar').style.width = data.disk_percent + '%';

    document.getElementById('uptime-val').innerText = data.uptime;

    const tbody = document.getElementById('process-table');
    tbody.innerHTML = '';
    data.processes.forEach(p => {
      const row = `<tr><td>${p.pid}</td><td>${p.name}</td><td>${p.cpu}%</td><td>${p.mem}%</td></tr>`;
      tbody.innerHTML += row;
    });
  } catch (err) {
    document.getElementById('timestamp').innerText = 'Error loading metrics: ' + err;
  }
}

updateMetrics();
setInterval(updateMetrics, 5000);
</script>

</body>
</html>
```

---

## Step 6: View it

With nginx running and the loop script active:

Open your Windows browser → `http://localhost/`

You should see the dashboard, auto-refreshing every 5 seconds.

---

## Step 7 (Optional): Make it survive reboots with systemd

If you've enabled systemd in WSL (`/etc/wsl.conf`):
```ini
[boot]
systemd=true
```
(then restart WSL fully with `wsl --shutdown` from PowerShell, then reopen)

Create a service file:
```bash
sudo nano /etc/systemd/system/metrics-loop.service
```

```ini
[Unit]
Description=System Metrics Loop
After=network.target

[Service]
ExecStart=/home/YOUR_USERNAME/metrics/run_loop.sh
Restart=always
User=YOUR_USERNAME

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable metrics-loop
sudo systemctl start metrics-loop
```

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `localhost` doesn't load in Windows browser | Check `sudo service nginx status`; restart with `sudo service nginx restart` |
| `metrics.json` shows old data | Confirm loop is running: `ps aux \| grep run_loop` |
| `Permission denied` writing to `/var/www/html` | Re-run the `chown` command from Step 2 |
| CPU/mem values look off | Run `top -bn1`, `free -m` manually and adjust the `awk` column numbers — they vary slightly by distro |
| Process names are cut off | `ps -eo comm` truncates to 15 chars; swap to `-eo pid,args,%cpu,%mem` for full command lines |

---

## Ideas to extend (for extra marks in a viva)
- Add a line chart (Chart.js) showing CPU history over the last few minutes
- Add network I/O and per-core CPU stats
- Add a "kill process" button (careful — needs auth + backend, good discussion point on security)
- Swap static JSON for a WebSocket push instead of polling
