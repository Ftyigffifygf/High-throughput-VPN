#!/bin/bash

# VPN Performance Optimization Script
# This script applies various performance optimizations for high-throughput VPN servers

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

print_optimization() {
    echo -e "${BLUE}[OPTIMIZATION]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root"
   exit 1
fi

print_status "Starting VPN performance optimization..."

# Backup original configurations
backup_configs() {
    print_status "Backing up original configurations..."
    
    # Backup sysctl.conf
    if [[ ! -f /etc/sysctl.conf.backup ]]; then
        cp /etc/sysctl.conf /etc/sysctl.conf.backup
    fi
    
    # Backup limits.conf
    if [[ ! -f /etc/security/limits.conf.backup ]]; then
        cp /etc/security/limits.conf /etc/security/limits.conf.backup
    fi
    
    print_status "Configuration backups created"
}

# Optimize kernel network parameters
optimize_network_kernel() {
    print_status "Optimizing kernel network parameters..."
    
    cat >> /etc/sysctl.conf << 'EOF'

# VPN High-Throughput Network Optimizations
# ==========================================

# Increase network buffer sizes
net.core.rmem_default = 262144
net.core.rmem_max = 134217728
net.core.wmem_default = 262144
net.core.wmem_max = 134217728

# TCP buffer sizes
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728

# Increase maximum number of packets in receive queue
net.core.netdev_max_backlog = 30000

# Increase maximum number of connections
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535

# TCP congestion control (BBR for better performance)
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# TCP window scaling
net.ipv4.tcp_window_scaling = 1

# TCP timestamps
net.ipv4.tcp_timestamps = 1

# TCP SACK (Selective Acknowledgment)
net.ipv4.tcp_sack = 1

# Reduce TIME_WAIT connections
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1

# Increase local port range
net.ipv4.ip_local_port_range = 1024 65535

# Increase maximum number of open files
fs.file-max = 2097152

# Virtual memory settings
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5

# Security settings (while maintaining performance)
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# IPv6 optimizations
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# Netfilter optimizations
net.netfilter.nf_conntrack_max = 1048576
net.netfilter.nf_conntrack_tcp_timeout_established = 7200
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 120
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 60
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 120

EOF

    print_optimization "Network kernel parameters optimized"
}

# Optimize system limits
optimize_system_limits() {
    print_status "Optimizing system limits..."
    
    cat >> /etc/security/limits.conf << 'EOF'

# VPN High-Throughput System Limits
# ==================================

# Increase file descriptor limits
* soft nofile 1048576
* hard nofile 1048576
root soft nofile 1048576
root hard nofile 1048576

# Increase process limits
* soft nproc 1048576
* hard nproc 1048576
root soft nproc 1048576
root hard nproc 1048576

# Memory limits
* soft memlock unlimited
* hard memlock unlimited

EOF

    # Also set limits in systemd
    mkdir -p /etc/systemd/system.conf.d
    cat > /etc/systemd/system.conf.d/limits.conf << 'EOF'
[Manager]
DefaultLimitNOFILE=1048576
DefaultLimitNPROC=1048576
DefaultLimitMEMLOCK=infinity
EOF

    print_optimization "System limits optimized"
}

# Optimize CPU performance
optimize_cpu() {
    print_status "Optimizing CPU performance..."
    
    # Set CPU governor to performance
    if [[ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]]; then
        echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor > /dev/null
        print_optimization "CPU governor set to performance mode"
        
        # Make it persistent
        cat > /etc/systemd/system/cpu-performance.service << 'EOF'
[Unit]
Description=Set CPU Performance Governor
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
        
        systemctl enable cpu-performance.service
    else
        print_warning "CPU frequency scaling not available"
    fi
    
    # Disable CPU power saving features for maximum performance
    if command -v cpupower >/dev/null 2>&1; then
        cpupower frequency-set -g performance 2>/dev/null || print_warning "Could not set CPU frequency"
    fi
}

# Optimize I/O scheduler
optimize_io() {
    print_status "Optimizing I/O scheduler..."
    
    # Set I/O scheduler to deadline or mq-deadline for better performance
    for disk in /sys/block/*/queue/scheduler; do
        if [[ -f "$disk" ]]; then
            if grep -q "mq-deadline" "$disk"; then
                echo mq-deadline > "$disk"
                print_optimization "I/O scheduler set to mq-deadline for $(basename $(dirname $(dirname $disk)))"
            elif grep -q "deadline" "$disk"; then
                echo deadline > "$disk"
                print_optimization "I/O scheduler set to deadline for $(basename $(dirname $(dirname $disk)))"
            fi
        fi
    done
    
    # Make I/O scheduler changes persistent
    cat > /etc/udev/rules.d/60-io-scheduler.rules << 'EOF'
# Set I/O scheduler for better VPN performance
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/scheduler}="mq-deadline"
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="mq-deadline"
EOF
}

# Optimize network interface settings
optimize_network_interface() {
    print_status "Optimizing network interface settings..."
    
    # Get primary network interface
    PRIMARY_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
    
    if [[ -n "$PRIMARY_INTERFACE" ]]; then
        print_status "Optimizing interface: $PRIMARY_INTERFACE"
        
        # Increase ring buffer sizes if supported
        ethtool -G "$PRIMARY_INTERFACE" rx 4096 tx 4096 2>/dev/null || print_warning "Could not increase ring buffer sizes"
        
        # Enable TCP segmentation offload if supported
        ethtool -K "$PRIMARY_INTERFACE" tso on 2>/dev/null || print_warning "Could not enable TSO"
        
        # Enable generic segmentation offload if supported
        ethtool -K "$PRIMARY_INTERFACE" gso on 2>/dev/null || print_warning "Could not enable GSO"
        
        # Enable generic receive offload if supported
        ethtool -K "$PRIMARY_INTERFACE" gro on 2>/dev/null || print_warning "Could not enable GRO"
        
        print_optimization "Network interface optimizations applied"
    else
        print_warning "Could not determine primary network interface"
    fi
}

# Optimize WireGuard specific settings
optimize_wireguard() {
    print_status "Applying WireGuard-specific optimizations..."
    
    # Create WireGuard optimization script
    cat > /usr/local/bin/optimize-wireguard << 'EOF'
#!/bin/bash

# WireGuard Performance Optimization

# Set optimal MTU for WireGuard interfaces
for interface in $(wg show interfaces 2>/dev/null); do
    if ip link show "$interface" >/dev/null 2>&1; then
        ip link set dev "$interface" mtu 1420
        echo "Set MTU to 1420 for $interface"
    fi
done

# Optimize WireGuard kernel module parameters if available
if [[ -d /sys/module/wireguard ]]; then
    echo "WireGuard kernel module loaded"
fi
EOF
    
    chmod +x /usr/local/bin/optimize-wireguard
    
    # Create systemd service for WireGuard optimization
    cat > /etc/systemd/system/wireguard-optimize.service << 'EOF'
[Unit]
Description=WireGuard Performance Optimization
After=wg-quick@wg0.service
Wants=wg-quick@wg0.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/optimize-wireguard
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl enable wireguard-optimize.service
    print_optimization "WireGuard optimizations configured"
}

# Optimize OpenVPN specific settings
optimize_openvpn() {
    print_status "Applying OpenVPN-specific optimizations..."
    
    # Create OpenVPN optimization configuration
    mkdir -p /etc/openvpn/optimization
    
    cat > /etc/openvpn/optimization/performance.conf << 'EOF'
# OpenVPN Performance Optimization Settings
# Include this file in your OpenVPN server configuration with:
# config /etc/openvpn/optimization/performance.conf

# Fast I/O
fast-io

# Optimize buffer sizes
sndbuf 0
rcvbuf 0

# TCP MSS fix
mssfix 1450

# Disable LZO compression on fast networks (can cause CPU overhead)
# compress lz4-v2

# Use UDP for better performance
proto udp

# Optimize keepalive
keepalive 10 60

# Reduce verbosity for better performance
verb 1

# Optimize TLS
tls-version-min 1.2
tls-cipher TLS-ECDHE-RSA-WITH-AES-256-GCM-SHA384

# Use AES-NI if available
cipher AES-256-GCM
auth SHA256

# Optimize threading
# management-client-user nobody
# management-client-group nogroup
EOF

    print_optimization "OpenVPN optimization configuration created"
    print_status "Include /etc/openvpn/optimization/performance.conf in your OpenVPN server config"
}

# Install performance monitoring tools
install_monitoring_tools() {
    print_status "Installing performance monitoring tools..."
    
    # Install essential monitoring tools
    apt update
    apt install -y \
        htop \
        iotop \
        nethogs \
        iftop \
        nload \
        bmon \
        vnstat \
        iperf3 \
        ethtool \
        tcpdump \
        ss \
        dstat
    
    print_optimization "Performance monitoring tools installed"
}

# Create performance test script
create_performance_test() {
    print_status "Creating performance test script..."
    
    cat > /usr/local/bin/vpn-performance-test << 'EOF'
#!/bin/bash

# VPN Performance Test Script

echo "VPN Performance Test"
echo "==================="
echo ""

# System information
echo "System Information:"
echo "-------------------"
echo "CPU: $(lscpu | grep 'Model name' | cut -d: -f2 | xargs)"
echo "Memory: $(free -h | awk '/^Mem:/ {print $2}')"
echo "Kernel: $(uname -r)"
echo "Load Average: $(uptime | awk -F'load average:' '{print $2}')"
echo ""

# Network performance
echo "Network Performance:"
echo "-------------------"
echo "Network interfaces:"
ip -br addr show | grep -v lo
echo ""

# Test network throughput if iperf3 is available
if command -v iperf3 >/dev/null 2>&1; then
    echo "iperf3 is available for throughput testing"
    echo "Run 'iperf3 -s' on server and 'iperf3 -c SERVER_IP' on client"
else
    echo "Install iperf3 for throughput testing: apt install iperf3"
fi
echo ""

# VPN status
echo "VPN Status:"
echo "-----------"
if systemctl is-active --quiet wg-quick@wg0; then
    echo "WireGuard: ACTIVE"
    wg show 2>/dev/null || echo "No WireGuard peers"
else
    echo "WireGuard: INACTIVE"
fi

if systemctl is-active --quiet openvpn@server; then
    echo "OpenVPN: ACTIVE"
    if [[ -f /etc/openvpn/openvpn-status.log ]]; then
        echo "Connected clients: $(grep -c "^CLIENT_LIST" /etc/openvpn/openvpn-status.log 2>/dev/null || echo "0")"
    fi
else
    echo "OpenVPN: INACTIVE"
fi
echo ""

# System performance
echo "System Performance:"
echo "------------------"
echo "CPU Usage: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//')%"
echo "Memory Usage: $(free | awk 'NR==2{printf "%.1f%%", $3*100/$2}')"
echo "Disk Usage: $(df -h / | awk 'NR==2{print $5}')"
echo ""

# Network statistics
echo "Network Statistics:"
echo "------------------"
cat /proc/net/dev | grep -E "(wg0|tun0)" | head -5
echo ""

echo "Performance test completed!"
echo "For detailed monitoring, use: htop, iotop, nethogs, or iftop"
EOF

    chmod +x /usr/local/bin/vpn-performance-test
    print_optimization "Performance test script created: /usr/local/bin/vpn-performance-test"
}

# Apply all optimizations
apply_optimizations() {
    backup_configs
    optimize_network_kernel
    optimize_system_limits
    optimize_cpu
    optimize_io
    optimize_network_interface
    optimize_wireguard
    optimize_openvpn
    install_monitoring_tools
    create_performance_test
    
    # Apply sysctl changes
    sysctl -p
    
    print_status "All optimizations applied successfully!"
}

# Revert optimizations function
revert_optimizations() {
    print_status "Reverting optimizations..."
    
    if [[ -f /etc/sysctl.conf.backup ]]; then
        cp /etc/sysctl.conf.backup /etc/sysctl.conf
        print_status "Reverted sysctl.conf"
    fi
    
    if [[ -f /etc/security/limits.conf.backup ]]; then
        cp /etc/security/limits.conf.backup /etc/security/limits.conf
        print_status "Reverted limits.conf"
    fi
    
    # Remove custom configurations
    rm -f /etc/systemd/system.conf.d/limits.conf
    rm -f /etc/systemd/system/cpu-performance.service
    rm -f /etc/udev/rules.d/60-io-scheduler.rules
    rm -f /etc/systemd/system/wireguard-optimize.service
    rm -rf /etc/openvpn/optimization
    
    systemctl daemon-reload
    sysctl -p
    
    print_status "Optimizations reverted. Reboot recommended."
}

# Main menu
case "${1:-apply}" in
    apply)
        apply_optimizations
        print_status ""
        print_status "Optimizations applied! Reboot recommended for all changes to take effect."
        print_status "Run 'vpn-performance-test' to check performance after reboot."
        ;;
    revert)
        revert_optimizations
        ;;
    test)
        if command -v vpn-performance-test >/dev/null 2>&1; then
            vpn-performance-test
        else
            print_error "Performance test script not found. Run with 'apply' first."
        fi
        ;;
    *)
        echo "Usage: $0 {apply|revert|test}"
        echo "  apply  - Apply all performance optimizations (default)"
        echo "  revert - Revert all optimizations to original state"
        echo "  test   - Run performance test"
        exit 1
        ;;
esac

