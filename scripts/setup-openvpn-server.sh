#!/bin/bash

# OpenVPN Server Setup Script
# This script sets up a high-throughput OpenVPN server

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

print_status "Starting OpenVPN server setup..."

# Update system packages
print_status "Updating system packages..."
apt update && apt upgrade -y

# Install OpenVPN and Easy-RSA
print_status "Installing OpenVPN and Easy-RSA..."
apt install -y openvpn easy-rsa

# Enable IP forwarding
print_status "Enabling IP forwarding..."
echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
sysctl -p

# Set up the Certificate Authority
print_status "Setting up Certificate Authority..."
make-cadir /etc/openvpn/easy-rsa
cd /etc/openvpn/easy-rsa

# Configure Easy-RSA variables
cat > vars << EOF
export KEY_COUNTRY="US"
export KEY_PROVINCE="CA"
export KEY_CITY="SanFrancisco"
export KEY_ORG="HighThroughputVPN"
export KEY_EMAIL="admin@htvpn.com"
export KEY_OU="HighThroughputVPN"
export KEY_NAME="server"
EOF

# Source the vars file
source ./vars

# Clean and build CA
./clean-all
./build-ca --batch

# Generate server certificate and key
print_status "Generating server certificate and key..."
./build-key-server --batch server

# Generate Diffie-Hellman parameters
print_status "Generating Diffie-Hellman parameters..."
./build-dh

# Generate HMAC key for additional security
print_status "Generating HMAC key..."
openvpn --genkey --secret keys/ta.key

# Copy certificates and keys to OpenVPN directory
print_status "Copying certificates and keys..."
cp keys/ca.crt keys/server.crt keys/server.key keys/dh2048.pem keys/ta.key /etc/openvpn/

# Get server public IP
SERVER_IP=$(curl -s ifconfig.me || curl -s ipinfo.io/ip || echo "YOUR_SERVER_IP")

# Create OpenVPN server configuration
print_status "Creating OpenVPN server configuration..."
cat > /etc/openvpn/server.conf << EOF
# OpenVPN Server Configuration - High Throughput
port 1194
proto udp
dev tun

ca ca.crt
cert server.crt
key server.key
dh dh2048.pem

# Network configuration
server 10.8.0.0 255.255.255.0
ifconfig-pool-persist ipp.txt

# Push routes to clients
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"

# Client configuration
client-to-client
duplicate-cn

# Keep alive
keepalive 10 120

# Cryptographic options
tls-auth ta.key 0
cipher AES-256-CBC
auth SHA256

# Compression for performance (use with caution on newer versions)
compress lz4-v2
push "compress lz4-v2"

# Performance optimizations
fast-io
sndbuf 0
rcvbuf 0
mssfix 1450

# Privileges
user nobody
group nogroup

# Persistence
persist-key
persist-tun

# Logging
status openvpn-status.log
log-append /var/log/openvpn.log
verb 3
mute 20

# Explicit exit notify
explicit-exit-notify 1
EOF

# Configure firewall rules
print_status "Configuring firewall..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 1194/udp

# Add NAT rules
iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o $(ip route | awk '/default/ {print $5; exit}') -j MASQUERADE
iptables -A FORWARD -i tun0 -j ACCEPT
iptables -A FORWARD -o tun0 -j ACCEPT

# Make iptables rules persistent
apt install -y iptables-persistent
iptables-save > /etc/iptables/rules.v4

ufw --force enable

# Performance optimizations
print_status "Applying performance optimizations..."

# Network performance tuning
cat >> /etc/sysctl.conf << EOF

# OpenVPN performance optimizations
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

# Enable and start OpenVPN service
print_status "Enabling and starting OpenVPN service..."
systemctl enable openvpn@server
systemctl start openvpn@server

# Create client management script
print_status "Creating client management script..."
cat > /usr/local/bin/ovpn-client-manager << 'EOF'
#!/bin/bash

# OpenVPN Client Management Script

set -e

EASY_RSA_DIR="/etc/openvpn/easy-rsa"
CLIENTS_DIR="/etc/openvpn/clients"
mkdir -p "$CLIENTS_DIR"

add_client() {
    local client_name="$1"
    
    if [[ -z "$client_name" ]]; then
        echo "Usage: $0 add <client_name>"
        echo "Example: $0 add john"
        exit 1
    fi
    
    cd "$EASY_RSA_DIR"
    source ./vars
    
    # Generate client certificate and key
    ./build-key --batch "$client_name"
    
    # Get server IP
    SERVER_IP=$(curl -s ifconfig.me || curl -s ipinfo.io/ip)
    
    # Create client configuration
    cat > "$CLIENTS_DIR/${client_name}.ovpn" << EOL
client
dev tun
proto udp
remote $SERVER_IP 1194
resolv-retry infinite
nobind
user nobody
group nogroup
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-CBC
auth SHA256
compress lz4-v2
verb 3
mute 20
fast-io
sndbuf 0
rcvbuf 0
mssfix 1450

<ca>
$(cat keys/ca.crt)
</ca>

<cert>
$(cat keys/${client_name}.crt)
</cert>

<key>
$(cat keys/${client_name}.key)
</key>

<tls-auth>
$(cat keys/ta.key)
</tls-auth>
key-direction 1
EOL
    
    echo "Client '$client_name' added successfully!"
    echo "Client configuration saved to: $CLIENTS_DIR/${client_name}.ovpn"
}

remove_client() {
    local client_name="$1"
    
    if [[ -z "$client_name" ]]; then
        echo "Usage: $0 remove <client_name>"
        exit 1
    fi
    
    cd "$EASY_RSA_DIR"
    source ./vars
    
    if [[ ! -f "keys/${client_name}.crt" ]]; then
        echo "Client '$client_name' not found!"
        exit 1
    fi
    
    # Revoke client certificate
    ./revoke-full "$client_name"
    
    # Remove client files
    rm -f "$CLIENTS_DIR/${client_name}.ovpn"
    
    # Restart OpenVPN to apply changes
    systemctl restart openvpn@server
    
    echo "Client '$client_name' removed successfully!"
}

list_clients() {
    echo "OpenVPN Server Status:"
    systemctl status openvpn@server --no-pager -l
    echo ""
    echo "Connected clients:"
    if [[ -f /etc/openvpn/openvpn-status.log ]]; then
        cat /etc/openvpn/openvpn-status.log
    else
        echo "No status log available"
    fi
}

case "$1" in
    add)
        add_client "$2"
        ;;
    remove)
        remove_client "$2"
        ;;
    list)
        list_clients
        ;;
    *)
        echo "Usage: $0 {add|remove|list}"
        echo "  add <client_name>     - Add a new client"
        echo "  remove <client_name>  - Remove a client"
        echo "  list                  - List server status and clients"
        exit 1
        ;;
esac
EOF

chmod +x /usr/local/bin/ovpn-client-manager

print_status "OpenVPN server setup completed successfully!"
print_status "Server public IP: $SERVER_IP"
print_status ""
print_status "To add a client, run: ovpn-client-manager add <client_name>"
print_status "Example: ovpn-client-manager add john"
print_status ""
print_status "To check server status, run: systemctl status openvpn@server"
print_status "To view connected clients, run: ovpn-client-manager list"

