# pwrstat-node-exporter

Prometheus exporter for CyberPower UPS. One command to install.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/simran2491/pwrstat-node-exporter/main/install.sh | sudo bash
```

That's it. The installer will:
- ✅ Download the exporter from this repo
- ✅ Install it to `/opt/pwrstat-node-exporter/`
- ✅ Set up a systemd service
- ✅ Enable it to start on boot
- ✅ Verify metrics are working

### Install Specific Version

```bash
curl -fsSL https://raw.githubusercontent.com/simran2491/pwrstat-node-exporter/main/install.sh | sudo bash -s -- --version v1.0.0
```

## Prerequisites

1. **CyberPower UPS** connected via USB
2. **PowerPanel for Linux** installed (provides `pwrstat` command)
   - Download: https://www.cyberpowersystems.com/products/software/powerpanel-linux/
3. **Python 3** (usually pre-installed)

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/simran2491/pwrstat-node-exporter/main/uninstall.sh | sudo bash
```

## What It Monitors

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
| `pwrstat_test_result` | Last self-test result (1=Pass, 0=Fail) |
| `pwrstat_last_power_event_info` | Last power event info |

## Configure Prometheus Scrape

Add to your `kube-prometheus-stack` Helm values:

```yaml
prometheus:
  prometheusSpec:
    additionalScrapeConfigs:
      - job_name: 'pwrstat-exporter'
        scrape_interval: 30s
        static_configs:
          - targets: ['<NODE_IP>:9182']
            labels:
              instance: 'master-ups'
```

Replace `<NODE_IP>` with your host IP (e.g., `10.0.0.219`).

## Verify

```bash
# Check service
systemctl status pwrstat-exporter

# View metrics
curl http://localhost:9182/metrics

# Logs
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

Import this JSON into Grafana:

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
  "tags": ["ups", "pwrstat"],
  "time": {"from": "now-6h", "to": "now"},
  "title": "UPS Status"
}
```

## Alerting Rules

Add to Prometheus stack:

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

          - alert: UPSBatteryLow
            expr: pwrstat_battery_capacity_percent < 20
            for: 5m
            labels:
              severity: critical
            annotations:
              summary: "UPS battery at {{ $value }}%"

          - alert: UPSHighLoad
            expr: pwrstat_load_percent > 80
            for: 10m
            labels:
              severity: warning
            annotations:
              summary: "UPS load at {{ $value }}%"
```

## Troubleshooting

```bash
# Service not starting
systemctl status pwrstat-exporter
journalctl -u pwrstat-exporter -f

# pwrstat not found
which pwrstat
sudo pwrstat -status

# Check metrics endpoint
curl http://localhost:9182/metrics
curl http://localhost:9182/health
```

## Architecture

```
Linux Host (UPS via USB)        Kubernetes Cluster
┌──────────────────────┐        ┌──────────────────────┐
│ pwrstat CLI          │ scrape │ Prometheus Server    │
│      ↑               │◄───────│  :9182               │
│ pwrstat_exporter.py │        └──────────────────────┘
│ (systemd service)    │
└──────────────────────┘
```

## License

MIT
