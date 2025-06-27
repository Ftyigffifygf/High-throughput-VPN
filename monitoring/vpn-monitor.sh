#!/bin/bash

# VPN Performance Monitoring Script
# This script monitors VPN server performance and generates reports

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_metric() {
    echo -e "${BLUE}[METRIC]${NC} $1"
}

# Configuration
LOG_DIR="/var/log/vpn-monitoring"
REPORT_FILE="$LOG_DIR/vpn-performance-$(date +%Y%m%d-%H%M%S).log"
ALERT_THRESHOLD_CPU=80
ALERT_THRESHOLD_MEMORY=80
ALERT_THRESHOLD_DISK=90

# Create log directory
mkdir -p "$LOG_DIR"

# Function to get system metrics
get_system_metrics() {
    print_status "Collecting system metrics..."
    
    # CPU usage
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')
    print_metric "CPU Usage: ${CPU_USAGE}%"
    
    # Memory usage
    MEMORY_INFO=$(free -m | awk 'NR==2{printf "%.1f", $3*100/$2}')
    print_metric "Memory Usage: ${MEMORY_INFO}%"
    
    # Disk usage
    DISK_USAGE=$(df -h / | awk 'NR==2{print $5}' | sed 's/%//')
    print_metric "Disk Usage: ${DISK_USAGE}%"
    
    # Network statistics
    print_metric "Network Interface Statistics:"
    cat /proc/net/dev | grep -E "(wg0|tun0)" | while read line; do
        if [[ -n "$line" ]]; then
            print_metric "  $line"
        fi
    done
    
    # Load average
    LOAD_AVG=$(uptime | awk -F'load average:' '{print $2}')
    print_metric "Load Average:$LOAD_AVG"
}

# Function to monitor WireGuard
monitor_wireguard() {
    if systemctl is-active --quiet wg-quick@wg0; then
        print_status "WireGuard is running"
        
        # Get WireGuard status
        WG_STATUS=$(wg show 2>/dev/null || echo "No WireGuard interfaces found")
        print_metric "WireGuard Status:"
        echo "$WG_STATUS" | while read line; do
            if [[ -n "$line" ]]; then
                print_metric "  $line"
            fi
        done
        
        # Count active peers
        PEER_COUNT=$(wg show wg0 peers 2>/dev/null | wc -l || echo "0")
        print_metric "Active WireGuard Peers: $PEER_COUNT"
        
    else
        print_warning "WireGuard service is not running"
    fi
}

# Function to monitor OpenVPN
monitor_openvpn() {
    if systemctl is-active --quiet openvpn@server; then
        print_status "OpenVPN is running"
        
        # Check OpenVPN status log
        if [[ -f /etc/openvpn/openvpn-status.log ]]; then
            CONNECTED_CLIENTS=$(grep "^CLIENT_LIST" /etc/openvpn/openvpn-status.log | wc -l)
            print_metric "Connected OpenVPN Clients: $CONNECTED_CLIENTS"
            
            print_metric "OpenVPN Client Details:"
            grep "^CLIENT_LIST" /etc/openvpn/openvpn-status.log | while read line; do
                print_metric "  $line"
            done
        else
            print_warning "OpenVPN status log not found"
        fi
        
    else
        print_warning "OpenVPN service is not running"
    fi
}

# Function to check network connectivity
check_connectivity() {
    print_status "Testing network connectivity..."
    
    # Test DNS resolution
    if nslookup google.com >/dev/null 2>&1; then
        print_metric "DNS Resolution: OK"
    else
        print_error "DNS Resolution: FAILED"
    fi
    
    # Test internet connectivity
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        print_metric "Internet Connectivity: OK"
    else
        print_error "Internet Connectivity: FAILED"
    fi
    
    # Test specific ports
    if ss -tuln | grep -q ":51820"; then
        print_metric "WireGuard Port (51820/UDP): LISTENING"
    else
        print_warning "WireGuard Port (51820/UDP): NOT LISTENING"
    fi
    
    if ss -tuln | grep -q ":1194"; then
        print_metric "OpenVPN Port (1194/UDP): LISTENING"
    else
        print_warning "OpenVPN Port (1194/UDP): NOT LISTENING"
    fi
}

# Function to generate performance report
generate_report() {
    print_status "Generating performance report..."
    
    {
        echo "VPN Performance Report - $(date)"
        echo "========================================"
        echo ""
        
        echo "System Metrics:"
        echo "---------------"
        echo "CPU Usage: ${CPU_USAGE}%"
        echo "Memory Usage: ${MEMORY_INFO}%"
        echo "Disk Usage: ${DISK_USAGE}%"
        echo "Load Average:$LOAD_AVG"
        echo ""
        
        echo "VPN Services Status:"
        echo "-------------------"
        if systemctl is-active --quiet wg-quick@wg0; then
            echo "WireGuard: RUNNING"
            echo "WireGuard Peers: $PEER_COUNT"
        else
            echo "WireGuard: NOT RUNNING"
        fi
        
        if systemctl is-active --quiet openvpn@server; then
            echo "OpenVPN: RUNNING"
            if [[ -f /etc/openvpn/openvpn-status.log ]]; then
                echo "OpenVPN Clients: $CONNECTED_CLIENTS"
            fi
        else
            echo "OpenVPN: NOT RUNNING"
        fi
        echo ""
        
        echo "Network Statistics:"
        echo "------------------"
        cat /proc/net/dev | grep -E "(wg0|tun0)" || echo "No VPN interfaces found"
        echo ""
        
        echo "Firewall Status:"
        echo "---------------"
        ufw status || echo "UFW not available"
        echo ""
        
        echo "Recent System Logs:"
        echo "------------------"
        journalctl --since "1 hour ago" -u wg-quick@wg0 -u openvpn@server --no-pager -n 20 || echo "No recent logs"
        
    } > "$REPORT_FILE"
    
    print_status "Report saved to: $REPORT_FILE"
}

# Function to check alerts
check_alerts() {
    print_status "Checking alert thresholds..."
    
    # CPU alert
    if (( $(echo "$CPU_USAGE > $ALERT_THRESHOLD_CPU" | bc -l) )); then
        print_error "ALERT: High CPU usage detected: ${CPU_USAGE}%"
    fi
    
    # Memory alert
    if (( $(echo "$MEMORY_INFO > $ALERT_THRESHOLD_MEMORY" | bc -l) )); then
        print_error "ALERT: High memory usage detected: ${MEMORY_INFO}%"
    fi
    
    # Disk alert
    if (( DISK_USAGE > ALERT_THRESHOLD_DISK )); then
        print_error "ALERT: High disk usage detected: ${DISK_USAGE}%"
    fi
    
    # Service alerts
    if ! systemctl is-active --quiet wg-quick@wg0 && ! systemctl is-active --quiet openvpn@server; then
        print_error "ALERT: No VPN services are running!"
    fi
}

# Function to run performance tests
run_performance_tests() {
    print_status "Running performance tests..."
    
    # Test network throughput using iperf3 if available
    if command -v iperf3 >/dev/null 2>&1; then
        print_metric "Network throughput test available (iperf3 installed)"
        print_status "To test throughput, run: iperf3 -s (on server) and iperf3 -c SERVER_IP (on client)"
    else
        print_warning "iperf3 not installed. Install with: apt install iperf3"
    fi
    
    # Test latency
    if ping -c 5 8.8.8.8 >/dev/null 2>&1; then
        LATENCY=$(ping -c 5 8.8.8.8 | tail -1 | awk -F'/' '{print $5}')
        print_metric "Average latency to 8.8.8.8: ${LATENCY}ms"
    fi
}

# Main execution
main() {
    print_status "Starting VPN performance monitoring..."
    echo ""
    
    get_system_metrics
    echo ""
    
    monitor_wireguard
    echo ""
    
    monitor_openvpn
    echo ""
    
    check_connectivity
    echo ""
    
    run_performance_tests
    echo ""
    
    generate_report
    echo ""
    
    check_alerts
    echo ""
    
    print_status "Monitoring completed. Check $REPORT_FILE for detailed report."
}

# Check if bc is installed (needed for floating point comparisons)
if ! command -v bc >/dev/null 2>&1; then
    print_warning "Installing bc for calculations..."
    apt update && apt install -y bc
fi

# Run main function
main

