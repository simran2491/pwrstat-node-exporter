#!/usr/bin/env python3
"""
pwrstat Prometheus Exporter

Exports CyberPower UPS status metrics via the `pwrstat` command line utility.
Runs as a systemd service and exposes Prometheus metrics on port 9182.
"""

import subprocess
import re
import time
from http.server import HTTPServer, BaseHTTPRequestHandler
from datetime import datetime
import sys
import signal

EXPORTER_PORT = 9182
PWRSTAT_COMMAND = ['sudo', 'pwrstat', '-status']
VERSION = "1.0.0"


class PwrstatCollector:
    """Collects and parses pwrstat output into Prometheus metrics."""

    def collect(self):
        """Run pwrstat and yield Prometheus metrics."""
        try:
            output = subprocess.check_output(
                PWRSTAT_COMMAND,
                stderr=subprocess.STDOUT,
                timeout=10,
                text=True
            )
            yield from self.parse_output(output)
        except subprocess.CalledProcessError as e:
            yield '# HELP pwrstat_scrape_error Whether there was an error collecting metrics'
            yield '# TYPE pwrstat_scrape_error gauge'
            yield 'pwrstat_scrape_error 1'
        except FileNotFoundError:
            yield '# HELP pwrstat_scrape_error Whether pwrstat command is not found'
            yield '# TYPE pwrstat_scrape_error gauge'
            yield 'pwrstat_scrape_error 2'
        except subprocess.TimeoutExpired:
            yield '# HELP pwrstat_scrape_error Whether pwrstat command timed out'
            yield '# TYPE pwrstat_scrape_error gauge'
            yield 'pwrstat_scrape_error 3'

    def parse_output(self, output):
        """Parse pwrstat output and yield Prometheus metrics."""
        lines = output.strip().split('\n')
        data = {}

        for line in lines:
            match = re.match(r'\s*([\w\s]+?)\s*\.+\s*(.+)', line)
            if match:
                key = match.group(1).strip()
                value = match.group(2).strip()
                data[key] = value

        # UPS Info metric
        yield '# HELP pwrstat_info UPS information'
        yield '# TYPE pwrstat_info gauge'
        model_name = data.get('Model Name', 'unknown').replace(' ', '_').replace('-', '_')
        firmware = data.get('Firmware Number', 'unknown')
        yield f'pwrstat_info{{model="{model_name}",firmware="{firmware}"}} 1'

        # Rating metrics
        try:
            rating_voltage = int(re.search(r'(\d+)', data.get('Rating Voltage', '0')).group(1))
            yield '# HELP pwrstat_rating_voltage_volts UPS rated voltage'
            yield '# TYPE pwrstat_rating_voltage_volts gauge'
            yield f'pwrstat_rating_voltage_volts {rating_voltage}'
        except (ValueError, AttributeError):
            pass

        try:
            rating_power = int(re.search(r'(\d+)', data.get('Rating Power', '0')).group(1))
            yield '# HELP pwrstat_rating_power_watts UPS rated power capacity'
            yield '# TYPE pwrstat_rating_power_watts gauge'
            yield f'pwrstat_rating_power_watts {rating_power}'
        except (ValueError, AttributeError):
            pass

        # State metric
        state = data.get('State', 'Unknown')
        state_map = {'Normal': 1, 'On Battery': 0, 'Unknown': -1}
        state_value = state_map.get(state, -1)
        yield '# HELP pwrstat_state UPS state (1=Normal, 0=On Battery, -1=Unknown)'
        yield '# TYPE pwrstat_state gauge'
        yield f'pwrstat_state {state_value}'

        # Power source
        power_source = data.get('Power Supply by', 'Unknown')
        power_source_value = 1 if power_source == 'Utility Power' else 0
        yield '# HELP pwrstat_power_source Power source (1=Utility, 0=Battery)'
        yield '# TYPE pwrstat_power_source gauge'
        yield f'pwrstat_power_source{{source="{power_source}"}} {power_source_value}'

        # Utility voltage
        try:
            utility_voltage = float(re.search(r'([\d.]+)', data.get('Utility Voltage', '0')).group(1))
            yield '# HELP pwrstat_utility_voltage_volts Utility input voltage'
            yield '# TYPE pwrstat_utility_voltage_volts gauge'
            yield f'pwrstat_utility_voltage_volts {utility_voltage}'
        except (ValueError, AttributeError):
            pass

        # Output voltage
        try:
            output_voltage = float(re.search(r'([\d.]+)', data.get('Output Voltage', '0')).group(1))
            yield '# HELP pwrstat_output_voltage_volts UPS output voltage'
            yield '# TYPE pwrstat_output_voltage_volts gauge'
            yield f'pwrstat_output_voltage_volts {output_voltage}'
        except (ValueError, AttributeError):
            pass

        # Battery capacity
        try:
            battery_capacity = float(re.search(r'([\d.]+)', data.get('Battery Capacity', '0')).group(1))
            yield '# HELP pwrstat_battery_capacity_percent Battery charge percentage'
            yield '# TYPE pwrstat_battery_capacity_percent gauge'
            yield f'pwrstat_battery_capacity_percent {battery_capacity}'
        except (ValueError, AttributeError):
            pass

        # Remaining runtime
        try:
            runtime_match = re.search(r'([\d.]+)', data.get('Remaining Runtime', '0'))
            if runtime_match:
                remaining_runtime = float(runtime_match.group(1))
                yield '# HELP pwrstat_remaining_runtime_minutes Estimated remaining runtime'
                yield '# TYPE pwrstat_remaining_runtime_minutes gauge'
                yield f'pwrstat_remaining_runtime_minutes {remaining_runtime}'
        except (ValueError, AttributeError):
            pass

        # Load in watts
        try:
            load_match = re.search(r'([\d.]+)\s*Watt', data.get('Load', '0'))
            if load_match:
                load_watts = float(load_match.group(1))
                yield '# HELP pwrstat_load_watts Current load in watts'
                yield '# TYPE pwrstat_load_watts gauge'
                yield f'pwrstat_load_watts {load_watts}'
        except (ValueError, AttributeError):
            pass

        # Load percentage
        try:
            load_percent_match = re.search(r'\((\d+)\s*%\)', data.get('Load', '0'))
            if load_percent_match:
                load_percent = float(load_percent_match.group(1))
                yield '# HELP pwrstat_load_percent Current load as percentage of capacity'
                yield '# TYPE pwrstat_load_percent gauge'
                yield f'pwrstat_load_percent {load_percent}'
        except (ValueError, AttributeError):
            pass

        # Test result
        test_result = data.get('Test Result', 'Unknown')
        test_result_map = {'Pass': 1, 'Fail': 0, 'Unknown': -1}
        test_result_value = test_result_map.get(test_result, -1)
        yield '# HELP pwrstat_test_result Last self-test result (1=Pass, 0=Fail, -1=Unknown)'
        yield '# TYPE pwrstat_test_result gauge'
        yield f'pwrstat_test_result{{result="{test_result}"}} {test_result_value}'

        # Last power event
        last_event = data.get('Last Power Event', 'None')
        yield '# HELP pwrstat_last_power_event_info Last power event information'
        yield '# TYPE pwrstat_last_power_event_info gauge'
        yield f'pwrstat_last_power_event_info{{event="{last_event}"}} 1'

        # Exporter metadata
        yield '# HELP pwrstat_exporter_build_info Exporter version'
        yield '# TYPE pwrstat_exporter_build_info gauge'
        yield f'pwrstat_exporter_build_info{{version="{VERSION}"}} 1'

        yield '# HELP pwrstat_last_scrape_timestamp UNIX timestamp of last scrape'
        yield '# TYPE pwrstat_last_scrape_timestamp gauge'
        yield f'pwrstat_last_scrape_timestamp {int(time.time())}'


class MetricsHandler(BaseHTTPRequestHandler):
    """HTTP handler that serves Prometheus metrics."""

    def do_GET(self):
        if self.path == '/metrics':
            collector = PwrstatCollector()
            metrics = '\n'.join(collector.collect()) + '\n'

            self.send_response(200)
            self.send_header('Content-Type', 'text/plain; version=0.0.4; charset=utf-8')
            self.end_headers()
            self.wfile.write(metrics.encode('utf-8'))
        elif self.path == '/health':
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'OK\n')
        elif self.path == '/':
            self.send_response(200)
            self.send_header('Content-Type', 'text/html')
            self.end_headers()
            html = f"""
            <html>
            <head><title>pwrstat Exporter</title></head>
            <body>
                <h1>pwrstat Exporter v{VERSION}</h1>
                <p>Exports CyberPower UPS status via pwrstat command.</p>
                <ul>
                    <li><a href="/metrics">Metrics</a></li>
                    <li><a href="/health">Health Check</a></li>
                </ul>
            </body>
            </html>
            """
            self.wfile.write(html.encode('utf-8'))
        else:
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b'Not Found\n')

    def log_message(self, format, *args):
        """Override to add timestamps."""
        print(f"[{datetime.now().isoformat()}] {format % args}")


def signal_handler(sig, frame):
    """Handle graceful shutdown on SIGTERM/SIGINT."""
    print("\nShutting down exporter...")
    sys.exit(0)


def main():
    """Start the Prometheus exporter."""
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)

    server = HTTPServer(('0.0.0.0', EXPORTER_PORT), MetricsHandler)
    print(f"pwrstat Prometheus Exporter v{VERSION} starting on port {EXPORTER_PORT}")
    print(f"Metrics: http://<host-ip>:{EXPORTER_PORT}/metrics")
    print(f"Health:  http://<host-ip>:{EXPORTER_PORT}/health")
    print(f"Press Ctrl+C to stop")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down exporter...")
        server.shutdown()


if __name__ == '__main__':
    main()
