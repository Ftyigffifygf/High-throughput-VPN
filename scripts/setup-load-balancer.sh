#!/bin/bash

# HAProxy Load Balancer Setup Script for VPN
# This script sets up HAProxy to load balance VPN connections

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root"
   exit 1
fi

print_status "Setting up HAProxy load balancer for VPN..."

# Install HAProxy
print_status "Installing HAProxy..."
apt update
apt install -y haproxy

# Backup original configuration
cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.backup

# Create HAProxy configuration for VPN load balancing
print_status "Creating HAProxy configuration..."
cat > /etc/haproxy/haproxy.cfg << 'EOF'
global
    log         127.0.0.1 local0
    chroot      /var/lib/haproxy
    stats       socket /run/haproxy/admin.sock mode 660 level admin
    stats       timeout 30s
    user        haproxy
    group       haproxy
    daemon

defaults
    mode        tcp
    log         global
    option      tcplog
    option      dontlognull
    option      tcp-check
    timeout connect 5000
    timeout client  50000
    timeout server  50000
    errorfile 400 /etc/haproxy/errors/400.http
    errorfile 403 /etc/haproxy/errors/403.http
    errorfile 408 /etc/haproxy/errors/408.http
    errorfile 500 /etc/haproxy/errors/500.http
    errorfile 502 /etc/haproxy/errors/502.http
    errorfile 503 /etc/haproxy/errors/503.http
    errorfile 504 /etc/haproxy/errors/504.http

# Statistics page
frontend stats
    bind *:8404
    mode http
    stats enable
    stats uri /stats
    stats refresh 30s
    stats admin if TRUE

# WireGuard Load Balancer
frontend wireguard_frontend
    bind *:51820
    mode tcp
    default_backend wireguard_servers

backend wireguard_servers
    mode tcp
    balance roundrobin
    option tcp-check
    # Add your WireGuard servers here
    # server wg1 10.0.1.10:51820 check
    # server wg2 10.0.1.11:51820 check
    # server wg3 10.0.1.12:51820 check

# OpenVPN Load Balancer
frontend openvpn_frontend
    bind *:1194
    mode tcp
    default_backend openvpn_servers

backend openvpn_servers
    mode tcp
    balance roundrobin
    option tcp-check
    # Add your OpenVPN servers here
    # server ovpn1 10.0.1.10:1194 check
    # server ovpn2 10.0.1.11:1194 check
    # server ovpn3 10.0.1.12:1194 check
EOF

# Create server management script
print_status "Creating server management script..."
cat > /usr/local/bin/vpn-lb-manager << 'EOF'
#!/bin/bash

# VPN Load Balancer Management Script

set -e

HAPROXY_CONFIG="/etc/haproxy/haproxy.cfg"

add_wireguard_server() {
    local server_name="$1"
    local server_ip="$2"
    local server_port="${3:-51820}"
    
    if [[ -z "$server_name" || -z "$server_ip" ]]; then
        echo "Usage: $0 add-wg <server_name> <server_ip> [port]"
        echo "Example: $0 add-wg wg1 10.0.1.10 51820"
        exit 1
    fi
    
    # Check if server already exists
    if grep -q "server $server_name" "$HAPROXY_CONFIG"; then
        echo "Server '$server_name' already exists!"
        exit 1
    fi
    
    # Add server to WireGuard backend
    sed -i "/backend wireguard_servers/,/^backend\|^frontend\|^$/ {
        /# Add your WireGuard servers here/a\\
    server $server_name $server_ip:$server_port check
    }" "$HAPROXY_CONFIG"
    
    # Reload HAProxy
    systemctl reload haproxy
    
    echo "WireGuard server '$server_name' ($server_ip:$server_port) added successfully!"
}

add_openvpn_server() {
    local server_name="$1"
    local server_ip="$2"
    local server_port="${3:-1194}"
    
    if [[ -z "$server_name" || -z "$server_ip" ]]; then
        echo "Usage: $0 add-ovpn <server_name> <server_ip> [port]"
        echo "Example: $0 add-ovpn ovpn1 10.0.1.10 1194"
        exit 1
    fi
    
    # Check if server already exists
    if grep -q "server $server_name" "$HAPROXY_CONFIG"; then
        echo "Server '$server_name' already exists!"
        exit 1
    fi
    
    # Add server to OpenVPN backend
    sed -i "/backend openvpn_servers/,/^backend\|^frontend\|^$/ {
        /# Add your OpenVPN servers here/a\\
    server $server_name $server_ip:$server_port check
    }" "$HAPROXY_CONFIG"
    
    # Reload HAProxy
    systemctl reload haproxy
    
    echo "OpenVPN server '$server_name' ($server_ip:$server_port) added successfully!"
}

remove_server() {
    local server_name="$1"
    
    if [[ -z "$server_name" ]]; then
        echo "Usage: $0 remove <server_name>"
        exit 1
    fi
    
    # Remove server from configuration
    sed -i "/server $server_name/d" "$HAPROXY_CONFIG"
    
    # Reload HAProxy
    systemctl reload haproxy
    
    echo "Server '$server_name' removed successfully!"
}

list_servers() {
    echo "HAProxy Configuration:"
    echo "====================="
    grep -A 10 "backend.*_servers" "$HAPROXY_CONFIG" | grep -E "(backend|server)"
    echo ""
    echo "HAProxy Status:"
    echo "==============="
    systemctl status haproxy --no-pager -l
}

show_stats() {
    echo "HAProxy statistics are available at: http://$(hostname -I | awk '{print $1}'):8404/stats"
    echo ""
    echo "Current server status:"
    echo "====================="
    echo "show stat" | socat stdio /run/haproxy/admin.sock | column -t -s ','
}

case "$1" in
    add-wg)
        add_wireguard_server "$2" "$3" "$4"
        ;;
    add-ovpn)
        add_openvpn_server "$2" "$3" "$4"
        ;;
    remove)
        remove_server "$2"
        ;;
    list)
        list_servers
        ;;
    stats)
        show_stats
        ;;
    *)
        echo "Usage: $0 {add-wg|add-ovpn|remove|list|stats}"
        echo "  add-wg <name> <ip> [port]   - Add WireGuard server"
        echo "  add-ovpn <name> <ip> [port] - Add OpenVPN server"
        echo "  remove <name>               - Remove server"
        echo "  list                        - List all servers"
        echo "  stats                       - Show statistics"
        exit 1
        ;;
esac
EOF

chmod +x /usr/local/bin/vpn-lb-manager

# Install socat for HAProxy stats
apt install -y socat

# Enable and start HAProxy
print_status "Enabling and starting HAProxy..."
systemctl enable haproxy
systemctl start haproxy

# Configure firewall
print_status "Configuring firewall for load balancer..."
ufw allow 51820/tcp
ufw allow 1194/tcp
ufw allow 8404/tcp

print_status "HAProxy load balancer setup completed!"
print_status ""
print_status "Management commands:"
print_status "  Add WireGuard server: vpn-lb-manager add-wg <name> <ip> [port]"
print_status "  Add OpenVPN server: vpn-lb-manager add-ovpn <name> <ip> [port]"
print_status "  Remove server: vpn-lb-manager remove <name>"
print_status "  List servers: vpn-lb-manager list"
print_status "  View stats: vpn-lb-manager stats"
print_status ""
print_status "Statistics web interface: http://$(hostname -I | awk '{print $1}'):8404/stats"

