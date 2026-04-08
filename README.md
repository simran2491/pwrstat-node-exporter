# pwrstat-node-exporter

Prometheus exporter for CyberPower UPS via `pwrstat` command. Runs on your Linux host and exposes UPS metrics for Prometheus scraping.

## Quick Install

One command to install everything:

```bash
git clone https://github.com/simran2491/pwrstat-node-exporter.git
cd pwrstat-node-exporter
sudo ./install.sh
```

That's it! The exporter will:
- ✅ Install as a systemd service
- ✅ Start automatically on boot
- ✅ Serve metrics on `http://<host-ip>:9182/metrics`
- ✅ Restart on failure

## Uninstall

```bash
sudo ./uninstall.sh
```

## Prerequisites

1. **CyberPower UPS** connected via USB
2. **PowerPanel for Linux** installed (provides `pwrstat` command)
   - Download: https://www.cyberpowersystems.com/products/software/powerpanel-linux/
3. **Python 3** (usually pre-installed)

## What It Monitors

Exports these UPS metrics:

| Metric | Description |
|--------|-------------|
| `pwrstat_state` | UPS state (1=Normal, 0=On Battery, -1=Unknown) |
| `pwrstat_battery_capacity_percent` | Battery charge percentage |
| `pwrstat_remaining_runtime_minutes` | Estimated runtime on battery |
| `pwrstat_load_watts` | Current load in watts |
| `pwrstat_load_percent` | Load as percentage of capacity |
| `pwrstat_utility_voltage_volts` | Input voltage from utility |
| `pwrstat_output_voltage_volts` | UPS output voltage |
| `pwrstat_power_source` | Power source (1=Utility, 0=Battery) |
| `pwrstat_rating_voltage_volts` | UPS rated voltage |
| `pwrstat_rating_power_watts` | UPS rated power capacity |
| `pwrstat_test_result` | Last self-test result (1=Pass, 0=Fail) |
| `pwrstat_last_power_event_info` | Last power event info |

## Configure Prometheus Scrape

Add this to your `kube-prometheus-stack` Helm values:

```yaml
prometheus:
  prometheusSpec:
    additionalScrapeConfigs:
      - job_name: 'pwrstat-exporter'
        scrape_interval: 30s
        scrape_timeout: 10s
        static_configs:
          - targets: ['<NODE_IP>:9182']
            labels:
              instance: 'master-ups'
              job: 'ups-monitoring'
```

Replace `<NODE_IP>` with your host IP (e.g., `10.0.0.219`).

## Verify Installation

```bash
# Check service status
systemctl status pwrstat-exporter

# View metrics
curl http://localhost:9182/metrics

# Check logs
journalctl -u pwrstat-exporter -f
```

## Example Metrics

```prometheus
# HELP pwrstat_state UPS state (1=Normal, 0=On Battery, -1=Unknown)
# TYPE pwrstat_state gauge
pwrstat_state 1

# HELP pwrstat_battery_capacity_percent Battery charge percentage
# TYPE pwrstat_battery_capacity_percent gauge
pwrstat_battery_capacity_percent 100

# HELP pwrstat_load_watts Current load in watts
# TYPE pwrstat_load_watts gauge
pwrstat_load_watts 127
```

## Grafana Dashboard

Import this JSON into Grafana for a complete UPS dashboard:

```json
{
  "annotations": {"list": []},
  "editable": true,
  "panels": [
    {
      "title": "UPS State",
      "type": "stat",
      "datasource": "Prometheus",
      "targets": [{"expr": "pwrstat_state"}],
      "fieldConfig": {
        "defaults": {
          "mappings": [
            {"options": {"1": {"text": "Normal"}}, "type": "value"},
            {"options": {"0": {"text": "On Battery"}}, "type": "value"}
          ],
          "thresholds": {
            "mode": "absolute",
            "steps": [
              {"color": "green", "value": null},
              {"color": "red", "value": 0}
            ]
          }
        }
      },
      "gridPos": {"h": 4, "w": 6, "x": 0, "y": 0}
    },
    {
      "title": "Battery Capacity",
      "type": "gauge",
      "datasource": "Prometheus",
      "targets": [{"expr": "pwrstat_battery_capacity_percent"}],
      "fieldConfig": {
        "defaults": {
          "unit": "percent",
          "min": 0,
          "max": 100,
          "thresholds": {
            "mode": "absolute",
            "steps": [
              {"color": "red", "value": 0},
              {"color": "yellow", "value": 20},
              {"color": "green", "value": 50}
            ]
          }
        }
      },
      "gridPos": {"h": 4, "w": 6, "x": 6, "y": 0}
    },
    {
      "title": "Remaining Runtime",
      "type": "stat",
      "datasource": "Prometheus",
      "targets": [{"expr": "pwrstat_remaining_runtime_minutes"}],
      "fieldConfig": {"defaults": {"unit": "m"}},
      "gridPos": {"h": 4, "w": 6, "x": 12, "y": 0}
    },
    {
      "title": "Load %",
      "type": "gauge",
      "datasource": "Prometheus",
      "targets": [{"expr": "pwrstat_load_percent"}],
      "fieldConfig": {
        "defaults": {
          "unit": "percent",
          "min": 0,
          "max": 100,
          "thresholds": {
            "mode": "absolute",
            "steps": [
              {"color": "green", "value": null},
              {"color": "yellow", "value": 60},
              {"color": "red", "value": 80}
            ]
          }
        }
      },
      "gridPos": {"h": 4, "w": 6, "x": 18, "y": 0}
    },
    {
      "title": "Voltage",
      "type": "timeseries",
      "datasource": "Prometheus",
      "targets": [
        {"expr": "pwrstat_utility_voltage_volts", "legendFormat": "Utility"},
        {"expr": "pwrstat_output_voltage_volts", "legendFormat": "Output"}
      ],
      "fieldConfig": {"defaults": {"unit": "volt"}},
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 4}
    },
    {
      "title": "Load (Watts)",
      "type": "timeseries",
      "datasource": "Prometheus",
      "targets": [{"expr": "pwrstat_load_watts", "legendFormat": "Load"}],
      "fieldConfig": {"defaults": {"unit": "watt"}},
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 4}
    }
  ],
  "refresh": "30s",
  "schemaVersion": 38,
  "tags": ["ups", "pwrstat", "cyberpower"],
  "time": {"from": "now-6h", "to": "now"},
  "title": "UPS Status"
}
```

## Alerting Rules

Add to your Prometheus stack values:

```yaml
additionalPrometheusRulesMap:
  ups-alerts:
    groups:
      - name: ups_alerts
        rules:
          - alert: UPSOnBattery
            expr: pwrstat_power_source == 0
            for: 1m
            labels:
              severity: warning
            annotations:
              summary: "UPS running on battery"
              description: "UPS has switched to battery power."

          - alert: UPSBatteryLow
            expr: pwrstat_battery_capacity_percent < 20
            for: 5m
            labels:
              severity: critical
            annotations:
              summary: "UPS battery critically low"
              description: "UPS battery at {{ $value }}%."

          - alert: UPSHighLoad
            expr: pwrstat_load_percent > 80
            for: 10m
            labels:
              severity: warning
            annotations:
              summary: "UPS load high"
              description: "UPS load at {{ $value }}%."
```

## File Structure

```
pwrstat-node-exporter/
├── install.sh                 # One-command installer (run with sudo)
├── uninstall.sh               # Clean uninstaller (run with sudo)
├── pwrstat_exporter.py        # Main exporter script
└── pwrstat-exporter.service   # systemd unit file
```

## Troubleshooting

### Service not starting

```bash
systemctl status pwrstat-exporter
journalctl -u pwrstat-exporter -f
```

### pwrstat not found

```bash
# Check if installed
which pwrstat

# Test it
sudo pwrstat -status
```

### Metrics not available

```bash
# Check if exporter is running
curl http://localhost:9182/metrics
curl http://localhost:9182/health

# Check firewall
sudo firewall-cmd --list-ports
```

### Prometheus not scraping

```bash
# Check Prometheus targets
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090
# Open http://localhost:9090/targets

# Query metrics
curl -s 'http://localhost:9090/api/v1/query?query=pwrstat_battery_capacity_percent'
```

## Manual Installation

If you prefer to install manually instead of using `install.sh`:

```bash
# 1. Create directory
sudo mkdir -p /opt/pwrstat-node-exporter

# 2. Copy files
sudo cp pwrstat_exporter.py /opt/pwrstat-node-exporter/
sudo cp pwrstat-exporter.service /etc/systemd/system/
sudo chmod +x /opt/pwrstat-node-exporter/pwrstat_exporter.py

# 3. Configure sudo
echo 'ALL ALL=(ALL) NOPASSWD: /usr/bin/pwrstat' | sudo tee /etc/sudoers.d/pwrstat
sudo chmod 440 /etc/sudoers.d/pwrstat

# 4. Start service
sudo systemctl daemon-reload
sudo systemctl enable pwrstat-exporter
sudo systemctl start pwrstat-exporter
```

## Architecture

```
Linux Host (with USB UPS)          Kubernetes Cluster
┌────────────────────────┐         ┌──────────────────────┐
│ pwrstat CLI            │         │ Prometheus Server    │
│      ↑                 │ scrape  │  (monitoring ns)     │
│      │                 │◄────────│                      │
│ pwrstat_exporter.py   │ :9182   │ additionalScrapeConfigs│
│ (systemd service)      │         │ → static_config       │
└────────────────────────┘         └──────────────────────┘
```

## Security

- **Minimal privileges**: Exporter only has sudo access to `/usr/bin/pwrstat`
- **Network isolation**: Metrics endpoint should only be accessible from your cluster nodes
- **No authentication**: Relies on network isolation (internal network)

## License

MIT

## Author

Simranjeet Singh
