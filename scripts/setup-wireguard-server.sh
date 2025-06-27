#!/bin/bash

# WireGuard Server Setup Script
# This script sets up a high-throughput WireGuard VPN server

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root"
   exit 1
fi

print_status "Starting WireGuard server setup..."

# Update system packages
print_status "Updating system packages..."
apt update && apt upgrade -y

# Install WireGuard
print_status "Installing WireGuard..."
apt install -y wireguard wireguard-tools

# Enable IP forwarding
print_status "Enabling IP forwarding..."
echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
echo 'net.ipv6.conf.all.forwarding=1' >> /etc/sysctl.conf
sysctl -p

# Generate server keys
print_status "Generating server keys..."
cd /etc/wireguard
wg genkey | tee server_private_key | wg pubkey > server_public_key
chmod 600 server_private_key

# Get server private key
SERVER_PRIVATE_KEY=$(cat server_private_key)
SERVER_PUBLIC_KEY=$(cat server_public_key)

# Get server public IP
SERVER_IP=$(curl -s ifconfig.me || curl -s ipinfo.io/ip || echo "YOUR_SERVER_IP")

print_status "Server public key: $SERVER_PUBLIC_KEY"
print_status "Server public IP: $SERVER_IP"

# Create WireGuard configuration
print_status "Creating WireGuard server configuration..."
cat > /etc/wireguard/wg0.conf << EOF
[Interface]
PrivateKey = $SERVER_PRIVATE_KEY
Address = 10.0.0.1/24
ListenPort = 51820
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o \$(ip route | awk '/default/ {print \$5; exit}') -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o \$(ip route | awk '/default/ {print \$5; exit}') -j MASQUERADE
SaveConfig = true
MTU = 1420
EOF

# Set proper permissions
chmod 600 /etc/wireguard/wg0.conf

# Enable and start WireGuard service
print_status "Enabling and starting WireGuard service..."
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

# Configure firewall (UFW)
print_status "Configuring firewall..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 51820/udp
ufw --force enable

# Performance optimizations
print_status "Applying performance optimizations..."

# Network performance tuning
cat >> /etc/sysctl.conf << EOF

# WireGuard performance optimizations
net.core.rmem_default = 262144
net.core.rmem_max = 16777216
net.core.wmem_default = 262144
net.core.wmem_max = 16777216
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_rmem = 4096 65536 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
EOF

sysctl -p

# Create client management script
print_status "Creating client management script..."
cat > /usr/local/bin/wg-client-manager << 'EOF'
#!/bin/bash

# WireGuard Client Management Script

set -e

CLIENTS_DIR="/etc/wireguard/clients"
mkdir -p "$CLIENTS_DIR"

add_client() {
    local client_name="$1"
    local client_ip="$2"
    
    if [[ -z "$client_name" || -z "$client_ip" ]]; then
        echo "Usage: $0 add <client_name> <client_ip>"
        echo "Example: $0 add john 10.0.0.2"
        exit 1
    fi
    
    # Generate client keys
    cd "$CLIENTS_DIR"
    wg genkey | tee "${client_name}_private_key" | wg pubkey > "${client_name}_public_key"
    chmod 600 "${client_name}_private_key"
    
    CLIENT_PRIVATE_KEY=$(cat "${client_name}_private_key")
    CLIENT_PUBLIC_KEY=$(cat "${client_name}_public_key")
    SERVER_PUBLIC_KEY=$(cat /etc/wireguard/server_public_key)
    SERVER_IP=$(curl -s ifconfig.me || curl -s ipinfo.io/ip)
    
    # Create client configuration
    cat > "${client_name}.conf" << EOL
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = $client_ip/32
DNS = 8.8.8.8, 8.8.4.4
MTU = 1420

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
Endpoint = $SERVER_IP:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOL
    
    # Add client to server configuration
    wg set wg0 peer "$CLIENT_PUBLIC_KEY" allowed-ips "$client_ip/32"
    wg-quick save wg0
    
    echo "Client '$client_name' added successfully!"
    echo "Client configuration saved to: $CLIENTS_DIR/${client_name}.conf"
    echo "Client public key: $CLIENT_PUBLIC_KEY"
}

remove_client() {
    local client_name="$1"
    
    if [[ -z "$client_name" ]]; then
        echo "Usage: $0 remove <client_name>"
        exit 1
    fi
    
    if [[ ! -f "$CLIENTS_DIR/${client_name}_public_key" ]]; then
        echo "Client '$client_name' not found!"
        exit 1
    fi
    
    CLIENT_PUBLIC_KEY=$(cat "$CLIENTS_DIR/${client_name}_public_key")
    
    # Remove client from server
    wg set wg0 peer "$CLIENT_PUBLIC_KEY" remove
    wg-quick save wg0
    
    # Remove client files
    rm -f "$CLIENTS_DIR/${client_name}"*
    
    echo "Client '$client_name' removed successfully!"
}

list_clients() {
    echo "Active clients:"
    wg show wg0
}

case "$1" in
    add)
        add_client "$2" "$3"
        ;;
    remove)
        remove_client "$2"
        ;;
    list)
        list_clients
        ;;
    *)
        echo "Usage: $0 {add|remove|list}"
        echo "  add <client_name> <client_ip>  - Add a new client"
        echo "  remove <client_name>           - Remove a client"
        echo "  list                           - List all clients"
        exit 1
        ;;
esac
EOF

chmod +x /usr/local/bin/wg-client-manager

print_status "WireGuard server setup completed successfully!"
print_status "Server public key: $SERVER_PUBLIC_KEY"
print_status "Server public IP: $SERVER_IP"
print_status ""
print_status "To add a client, run: wg-client-manager add <client_name> <client_ip>"
print_status "Example: wg-client-manager add john 10.0.0.2"
print_status ""
print_status "To check server status, run: wg show"
print_status "To check service status, run: systemctl status wg-quick@wg0"

