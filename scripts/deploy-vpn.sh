#!/bin/bash

# High-Throughput VPN Master Deployment Script
# This script orchestrates the complete deployment of the VPN solution

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

print_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                High-Throughput VPN Deployment                ║"
    echo "║                     Version 1.0                             ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

# Check system requirements
check_requirements() {
    print_step "Checking system requirements..."
    
    # Check OS
    if [[ ! -f /etc/os-release ]]; then
        print_error "Cannot determine operating system"
        exit 1
    fi
    
    source /etc/os-release
    if [[ "$ID" != "ubuntu" ]] && [[ "$ID" != "debian" ]]; then
        print_warning "This script is optimized for Ubuntu/Debian. Proceed with caution."
    fi
    
    # Check available memory
    MEMORY_GB=$(free -g | awk '/^Mem:/{print $2}')
    if [[ $MEMORY_GB -lt 1 ]]; then
        print_warning "Low memory detected (${MEMORY_GB}GB). VPN performance may be affected."
    fi
    
    # Check available disk space
    DISK_SPACE=$(df -BG / | awk 'NR==2{print $4}' | sed 's/G//')
    if [[ $DISK_SPACE -lt 5 ]]; then
        print_warning "Low disk space detected (${DISK_SPACE}GB available). Consider freeing up space."
    fi
    
    print_status "System requirements check completed"
}

# Display deployment menu
show_menu() {
    echo ""
    echo "Select deployment option:"
    echo "========================"
    echo "1) Full VPN Server Setup (WireGuard + OpenVPN + Security + Monitoring)"
    echo "2) WireGuard Only"
    echo "3) OpenVPN Only"
    echo "4) Load Balancer Setup"
    echo "5) Performance Optimization Only"
    echo "6) Security Hardening Only"
    echo "7) Monitoring Setup Only"
    echo "8) Custom Installation"
    echo "9) Status Check"
    echo "0) Exit"
    echo ""
    read -p "Enter your choice [1-9, 0]: " choice
}

# Full VPN server setup
full_setup() {
    print_step "Starting full VPN server setup..."
    
    # Performance optimization
    print_status "Applying performance optimizations..."
    "$SCRIPT_DIR/optimize-performance.sh" apply
    
    # Security hardening
    print_status "Applying security hardening..."
    "$SCRIPT_DIR/security-hardening.sh" apply
    
    # WireGuard setup
    print_status "Setting up WireGuard..."
    "$SCRIPT_DIR/setup-wireguard-server.sh"
    
    # OpenVPN setup
    print_status "Setting up OpenVPN..."
    "$SCRIPT_DIR/setup-openvpn-server.sh"
    
    # Load balancer setup
    read -p "Do you want to set up load balancer? (y/N): " setup_lb
    if [[ "$setup_lb" =~ ^[Yy]$ ]]; then
        print_status "Setting up load balancer..."
        "$SCRIPT_DIR/setup-load-balancer.sh"
    fi
    
    print_status "Full VPN server setup completed!"
    show_post_install_info
}

# WireGuard only setup
wireguard_setup() {
    print_step "Setting up WireGuard VPN server..."
    
    # Performance optimization
    "$SCRIPT_DIR/optimize-performance.sh" apply
    
    # WireGuard setup
    "$SCRIPT_DIR/setup-wireguard-server.sh"
    
    print_status "WireGuard setup completed!"
    show_wireguard_info
}

# OpenVPN only setup
openvpn_setup() {
    print_step "Setting up OpenVPN server..."
    
    # Performance optimization
    "$SCRIPT_DIR/optimize-performance.sh" apply
    
    # OpenVPN setup
    "$SCRIPT_DIR/setup-openvpn-server.sh"
    
    print_status "OpenVPN setup completed!"
    show_openvpn_info
}

# Load balancer setup
load_balancer_setup() {
    print_step "Setting up load balancer..."
    "$SCRIPT_DIR/setup-load-balancer.sh"
    print_status "Load balancer setup completed!"
}

# Performance optimization only
performance_setup() {
    print_step "Applying performance optimizations..."
    "$SCRIPT_DIR/optimize-performance.sh" apply
    print_status "Performance optimization completed!"
}

# Security hardening only
security_setup() {
    print_step "Applying security hardening..."
    "$SCRIPT_DIR/security-hardening.sh" apply
    print_status "Security hardening completed!"
}

# Monitoring setup only
monitoring_setup() {
    print_step "Setting up monitoring..."
    
    # Install monitoring dependencies
    apt update
    apt install -y python3 python3-pip python3-venv
    
    # Create monitoring service
    create_monitoring_service
    
    print_status "Monitoring setup completed!"
}

# Custom installation
custom_setup() {
    echo ""
    echo "Custom Installation Options:"
    echo "============================"
    
    read -p "Apply performance optimizations? (Y/n): " opt_perf
    read -p "Apply security hardening? (Y/n): " opt_security
    read -p "Install WireGuard? (Y/n): " opt_wireguard
    read -p "Install OpenVPN? (Y/n): " opt_openvpn
    read -p "Setup load balancer? (y/N): " opt_lb
    read -p "Setup monitoring? (Y/n): " opt_monitoring
    
    if [[ ! "$opt_perf" =~ ^[Nn]$ ]]; then
        print_status "Applying performance optimizations..."
        "$SCRIPT_DIR/optimize-performance.sh" apply
    fi
    
    if [[ ! "$opt_security" =~ ^[Nn]$ ]]; then
        print_status "Applying security hardening..."
        "$SCRIPT_DIR/security-hardening.sh" apply
    fi
    
    if [[ ! "$opt_wireguard" =~ ^[Nn]$ ]]; then
        print_status "Setting up WireGuard..."
        "$SCRIPT_DIR/setup-wireguard-server.sh"
    fi
    
    if [[ ! "$opt_openvpn" =~ ^[Nn]$ ]]; then
        print_status "Setting up OpenVPN..."
        "$SCRIPT_DIR/setup-openvpn-server.sh"
    fi
    
    if [[ "$opt_lb" =~ ^[Yy]$ ]]; then
        print_status "Setting up load balancer..."
        "$SCRIPT_DIR/setup-load-balancer.sh"
    fi
    
    if [[ ! "$opt_monitoring" =~ ^[Nn]$ ]]; then
        print_status "Setting up monitoring..."
        monitoring_setup
    fi
    
    print_status "Custom installation completed!"
}

# Create monitoring service
create_monitoring_service() {
    print_status "Creating monitoring service..."
    
    # Create monitoring user
    useradd -r -s /bin/false -d /var/lib/vpn-monitor vpn-monitor 2>/dev/null || true
    
    # Create monitoring directories
    mkdir -p /var/lib/vpn-monitor
    mkdir -p /var/log/vpn-monitor
    chown vpn-monitor:vpn-monitor /var/lib/vpn-monitor /var/log/vpn-monitor
    
    # Create systemd service for monitoring
    cat > /etc/systemd/system/vpn-monitor.service << 'EOF'
[Unit]
Description=VPN Performance Monitor
After=network.target

[Service]
Type=simple
User=vpn-monitor
Group=vpn-monitor
WorkingDirectory=/var/lib/vpn-monitor
ExecStart=/usr/local/bin/vpn-monitor-daemon
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF

    # Create monitoring daemon
    cat > /usr/local/bin/vpn-monitor-daemon << 'EOF'
#!/bin/bash

# VPN Monitoring Daemon

LOG_FILE="/var/log/vpn-monitor/monitor.log"
INTERVAL=300  # 5 minutes

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

while true; do
    # Run monitoring script
    /usr/local/bin/vpn-monitor.sh >> "$LOG_FILE" 2>&1
    
    log_message "Monitoring cycle completed"
    
    # Wait for next cycle
    sleep $INTERVAL
done
EOF

    chmod +x /usr/local/bin/vpn-monitor-daemon
    
    # Enable and start monitoring service
    systemctl daemon-reload
    systemctl enable vpn-monitor.service
    systemctl start vpn-monitor.service
    
    print_status "Monitoring service created and started"
}

# Status check
status_check() {
    print_step "Checking VPN server status..."
    
    echo ""
    echo "System Status:"
    echo "=============="
    echo "Hostname: $(hostname)"
    echo "Public IP: $(curl -s ifconfig.me 2>/dev/null || echo "Unable to determine")"
    echo "Uptime: $(uptime -p)"
    echo "Load Average: $(uptime | awk -F'load average:' '{print $2}')"
    echo ""
    
    echo "VPN Services:"
    echo "============="
    
    # WireGuard status
    if systemctl is-active --quiet wg-quick@wg0; then
        echo "✅ WireGuard: RUNNING"
        echo "   Port: 51820/UDP"
        echo "   Peers: $(wg show wg0 peers 2>/dev/null | wc -l)"
    else
        echo "❌ WireGuard: NOT RUNNING"
    fi
    
    # OpenVPN status
    if systemctl is-active --quiet openvpn@server; then
        echo "✅ OpenVPN: RUNNING"
        echo "   Port: 1194/UDP"
        if [[ -f /etc/openvpn/openvpn-status.log ]]; then
            echo "   Clients: $(grep -c "^CLIENT_LIST" /etc/openvpn/openvpn-status.log 2>/dev/null || echo "0")"
        fi
    else
        echo "❌ OpenVPN: NOT RUNNING"
    fi
    
    # Load balancer status
    if systemctl is-active --quiet haproxy; then
        echo "✅ Load Balancer: RUNNING"
        echo "   Stats: http://$(hostname -I | awk '{print $1}'):8404/stats"
    else
        echo "ℹ️  Load Balancer: NOT CONFIGURED"
    fi
    
    # Monitoring status
    if systemctl is-active --quiet vpn-monitor; then
        echo "✅ Monitoring: RUNNING"
    else
        echo "ℹ️  Monitoring: NOT CONFIGURED"
    fi
    
    echo ""
    echo "Security Status:"
    echo "================"
    
    # Firewall status
    if systemctl is-active --quiet ufw; then
        echo "✅ Firewall: ACTIVE"
    else
        echo "⚠️  Firewall: INACTIVE"
    fi
    
    # Fail2ban status
    if systemctl is-active --quiet fail2ban; then
        echo "✅ Fail2ban: ACTIVE"
    else
        echo "⚠️  Fail2ban: INACTIVE"
    fi
    
    echo ""
    
    # Run security status if available
    if command -v vpn-security-status >/dev/null 2>&1; then
        echo "Detailed Security Status:"
        echo "========================"
        vpn-security-status
    fi
}

# Show post-install information
show_post_install_info() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗"
    echo -e "║                    Installation Complete!                   ║"
    echo -e "╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    
    echo "Server Information:"
    echo "==================="
    echo "Public IP: $SERVER_IP"
    echo "WireGuard Port: 51820/UDP"
    echo "OpenVPN Port: 1194/UDP"
    echo ""
    
    echo "Management Commands:"
    echo "==================="
    echo "Add WireGuard client: wg-client-manager add <name> <ip>"
    echo "Add OpenVPN client: ovpn-client-manager add <name>"
    echo "Check VPN status: $0 status"
    echo "Monitor performance: vpn-monitor.sh"
    echo "Security status: vpn-security-status"
    echo ""
    
    echo "Next Steps:"
    echo "==========="
    echo "1. Add VPN clients using the management commands"
    echo "2. Test VPN connections from client devices"
    echo "3. Monitor performance and security regularly"
    echo "4. Configure backup and disaster recovery"
    echo ""
    
    print_warning "IMPORTANT: Reboot the server to ensure all optimizations take effect"
}

# Show WireGuard specific info
show_wireguard_info() {
    echo ""
    echo "WireGuard Server Ready!"
    echo "======================="
    
    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    SERVER_PUBLIC_KEY=$(cat /etc/wireguard/server_public_key 2>/dev/null || echo "Check /etc/wireguard/server_public_key")
    
    echo "Server IP: $SERVER_IP"
    echo "Server Port: 51820"
    echo "Server Public Key: $SERVER_PUBLIC_KEY"
    echo ""
    echo "Add clients with: wg-client-manager add <name> <ip>"
    echo "Example: wg-client-manager add john 10.0.0.2"
}

# Show OpenVPN specific info
show_openvpn_info() {
    echo ""
    echo "OpenVPN Server Ready!"
    echo "====================="
    
    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    
    echo "Server IP: $SERVER_IP"
    echo "Server Port: 1194"
    echo ""
    echo "Add clients with: ovpn-client-manager add <name>"
    echo "Example: ovpn-client-manager add john"
}

# Main execution
main() {
    print_banner
    check_root
    check_requirements
    
    # If arguments provided, run directly
    case "${1:-menu}" in
        full)
            full_setup
            ;;
        wireguard|wg)
            wireguard_setup
            ;;
        openvpn|ovpn)
            openvpn_setup
            ;;
        loadbalancer|lb)
            load_balancer_setup
            ;;
        performance|perf)
            performance_setup
            ;;
        security|sec)
            security_setup
            ;;
        monitoring|mon)
            monitoring_setup
            ;;
        status)
            status_check
            ;;
        menu)
            while true; do
                show_menu
                case $choice in
                    1) full_setup; break ;;
                    2) wireguard_setup; break ;;
                    3) openvpn_setup; break ;;
                    4) load_balancer_setup; break ;;
                    5) performance_setup; break ;;
                    6) security_setup; break ;;
                    7) monitoring_setup; break ;;
                    8) custom_setup; break ;;
                    9) status_check; break ;;
                    0) echo "Goodbye!"; exit 0 ;;
                    *) print_error "Invalid option. Please try again." ;;
                esac
            done
            ;;
        *)
            echo "Usage: $0 {full|wireguard|openvpn|loadbalancer|performance|security|monitoring|status|menu}"
            echo ""
            echo "Options:"
            echo "  full         - Complete VPN server setup"
            echo "  wireguard    - WireGuard server only"
            echo "  openvpn      - OpenVPN server only"
            echo "  loadbalancer - Load balancer setup"
            echo "  performance  - Performance optimization only"
            echo "  security     - Security hardening only"
            echo "  monitoring   - Monitoring setup only"
            echo "  status       - Check server status"
            echo "  menu         - Interactive menu (default)"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"

