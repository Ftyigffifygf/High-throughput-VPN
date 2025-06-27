#!/bin/bash

# VPN Security Hardening Script
# This script implements security best practices for VPN servers

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

print_security() {
    echo -e "${BLUE}[SECURITY]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root"
   exit 1
fi

print_status "Starting VPN security hardening..."

# Update system packages
update_system() {
    print_status "Updating system packages..."
    apt update && apt upgrade -y
    apt autoremove -y
    print_security "System packages updated"
}

# Configure SSH security
secure_ssh() {
    print_status "Securing SSH configuration..."
    
    # Backup original SSH config
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
    
    # Apply SSH security settings
    cat >> /etc/ssh/sshd_config << 'EOF'

# VPN Server SSH Security Settings
# ================================

# Disable root login
PermitRootLogin no

# Use SSH protocol version 2 only
Protocol 2

# Change default port (uncomment and modify as needed)
# Port 2222

# Disable password authentication (use key-based auth only)
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no

# Disable X11 forwarding
X11Forwarding no

# Disable unused authentication methods
UsePAM yes
KerberosAuthentication no
GSSAPIAuthentication no

# Set login grace time
LoginGraceTime 30

# Maximum authentication attempts
MaxAuthTries 3

# Client alive settings
ClientAliveInterval 300
ClientAliveCountMax 2

# Restrict users (uncomment and modify as needed)
# AllowUsers vpnadmin

# Disable unused features
AllowAgentForwarding no
AllowTcpForwarding no
GatewayPorts no
PermitTunnel no

EOF

    # Restart SSH service
    systemctl restart sshd
    print_security "SSH configuration hardened"
}

# Configure firewall with fail2ban
setup_firewall_protection() {
    print_status "Setting up advanced firewall protection..."
    
    # Install fail2ban
    apt install -y fail2ban
    
    # Configure fail2ban for SSH
    cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
# Ban time (in seconds)
bantime = 3600

# Find time (in seconds)
findtime = 600

# Maximum retry attempts
maxretry = 3

# Ignore local IPs
ignoreip = 127.0.0.1/8 ::1 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600

[wireguard]
enabled = true
port = 51820
protocol = udp
filter = wireguard
logpath = /var/log/syslog
maxretry = 5
bantime = 1800

[openvpn]
enabled = true
port = 1194
protocol = udp
filter = openvpn
logpath = /var/log/openvpn.log
maxretry = 5
bantime = 1800
EOF

    # Create WireGuard filter
    cat > /etc/fail2ban/filter.d/wireguard.conf << 'EOF'
[Definition]
failregex = ^.*wg0: Invalid handshake initiation from <HOST>:\d+$
            ^.*wg0: Packet has unallowed src IP <HOST>$
ignoreregex =
EOF

    # Create OpenVPN filter
    cat > /etc/fail2ban/filter.d/openvpn.conf << 'EOF'
[Definition]
failregex = ^.*TLS Error: TLS handshake failed.*,\s*<HOST>:\d+$
            ^.*VERIFY ERROR:.*,\s*<HOST>:\d+$
            ^.*TLS_ERROR:.*,\s*<HOST>:\d+$
ignoreregex =
EOF

    # Enable and start fail2ban
    systemctl enable fail2ban
    systemctl start fail2ban
    
    print_security "Fail2ban configured for SSH, WireGuard, and OpenVPN protection"
}

# Install and configure intrusion detection
setup_intrusion_detection() {
    print_status "Setting up intrusion detection system..."
    
    # Install AIDE (Advanced Intrusion Detection Environment)
    apt install -y aide
    
    # Initialize AIDE database
    print_status "Initializing AIDE database (this may take a while)..."
    aideinit
    cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db
    
    # Create AIDE check script
    cat > /usr/local/bin/aide-check << 'EOF'
#!/bin/bash
# AIDE integrity check script

AIDE_LOG="/var/log/aide-check.log"
AIDE_REPORT="/tmp/aide-report.txt"

echo "AIDE Integrity Check - $(date)" > "$AIDE_REPORT"
echo "=================================" >> "$AIDE_REPORT"
echo "" >> "$AIDE_REPORT"

# Run AIDE check
aide --check >> "$AIDE_REPORT" 2>&1

# Check if there are any changes
if grep -q "found differences" "$AIDE_REPORT"; then
    echo "WARNING: AIDE detected file system changes!" | tee -a "$AIDE_LOG"
    cat "$AIDE_REPORT" >> "$AIDE_LOG"
    
    # Send alert (configure email/notification as needed)
    echo "File integrity check failed on $(hostname) at $(date)" | logger -t AIDE-ALERT
else
    echo "AIDE check passed - no unauthorized changes detected" | tee -a "$AIDE_LOG"
fi

# Clean up
rm -f "$AIDE_REPORT"
EOF

    chmod +x /usr/local/bin/aide-check
    
    # Schedule daily AIDE checks
    cat > /etc/cron.daily/aide-check << 'EOF'
#!/bin/bash
/usr/local/bin/aide-check
EOF
    
    chmod +x /etc/cron.daily/aide-check
    
    print_security "AIDE intrusion detection system configured"
}

# Configure system auditing
setup_system_auditing() {
    print_status "Setting up system auditing..."
    
    # Install auditd
    apt install -y auditd audispd-plugins
    
    # Configure audit rules
    cat > /etc/audit/rules.d/vpn-audit.rules << 'EOF'
# VPN Server Audit Rules
# ======================

# Monitor VPN configuration files
-w /etc/wireguard/ -p wa -k vpn_config
-w /etc/openvpn/ -p wa -k vpn_config

# Monitor system configuration changes
-w /etc/passwd -p wa -k user_modification
-w /etc/group -p wa -k group_modification
-w /etc/shadow -p wa -k password_modification
-w /etc/sudoers -p wa -k sudo_modification

# Monitor network configuration
-w /etc/network/ -p wa -k network_config
-w /etc/hosts -p wa -k network_config
-w /etc/resolv.conf -p wa -k network_config

# Monitor firewall changes
-w /etc/ufw/ -p wa -k firewall_config
-w /etc/iptables/ -p wa -k firewall_config

# Monitor SSH configuration
-w /etc/ssh/sshd_config -p wa -k ssh_config

# Monitor system calls
-a always,exit -F arch=b64 -S adjtimex -S settimeofday -k time_change
-a always,exit -F arch=b32 -S adjtimex -S settimeofday -S stime -k time_change

# Monitor file permission changes
-a always,exit -F arch=b64 -S chmod -S fchmod -S fchmodat -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b32 -S chmod -S fchmod -S fchmodat -F auid>=1000 -F auid!=4294967295 -k perm_mod

# Monitor file ownership changes
-a always,exit -F arch=b64 -S chown -S fchown -S fchownat -S lchown -F auid>=1000 -F auid!=4294967295 -k perm_mod
-a always,exit -F arch=b32 -S chown -S fchown -S fchownat -S lchown -F auid>=1000 -F auid!=4294967295 -k perm_mod

# Make audit configuration immutable
-e 2
EOF

    # Restart auditd
    systemctl enable auditd
    systemctl restart auditd
    
    print_security "System auditing configured"
}

# Secure kernel parameters
secure_kernel() {
    print_status "Applying kernel security hardening..."
    
    cat >> /etc/sysctl.conf << 'EOF'

# VPN Server Security Hardening
# ==============================

# IP Spoofing protection
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.rp_filter = 1

# Ignore ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# Ignore send redirects
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Disable source packet routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# Log Martians
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# Ignore ICMP ping requests
net.ipv4.icmp_echo_ignore_all = 0

# Ignore Directed pings
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Disable IPv6 if not needed
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0

# TCP SYN flood protection
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 5

# Control buffer overflow attacks
kernel.exec-shield = 1
kernel.randomize_va_space = 2

# Restrict core dumps
fs.suid_dumpable = 0

# Hide kernel pointers
kernel.kptr_restrict = 1

# Restrict dmesg access
kernel.dmesg_restrict = 1

# Restrict ptrace
kernel.yama.ptrace_scope = 1

EOF

    sysctl -p
    print_security "Kernel security parameters applied"
}

# Configure log monitoring
setup_log_monitoring() {
    print_status "Setting up log monitoring..."
    
    # Install logwatch
    apt install -y logwatch
    
    # Configure logwatch
    cat > /etc/logwatch/conf/logwatch.conf << 'EOF'
# Logwatch configuration for VPN server
LogDir = /var/log
TmpDir = /var/cache/logwatch
MailTo = root
MailFrom = logwatch@localhost
Print = Yes
Save = /var/cache/logwatch
Range = yesterday
Detail = Med
Service = All
mailer = "/usr/sbin/sendmail -t"
EOF

    # Create VPN-specific log monitoring script
    cat > /usr/local/bin/vpn-log-monitor << 'EOF'
#!/bin/bash

# VPN Log Monitoring Script

LOG_FILE="/var/log/vpn-security.log"
DATE=$(date)

echo "VPN Security Log Analysis - $DATE" >> "$LOG_FILE"
echo "=======================================" >> "$LOG_FILE"

# Check for failed VPN connections
echo "Failed VPN Connection Attempts:" >> "$LOG_FILE"
grep -i "failed\|error\|denied" /var/log/syslog | grep -E "(wireguard|openvpn)" | tail -10 >> "$LOG_FILE" 2>/dev/null || echo "No failed attempts found" >> "$LOG_FILE"

# Check fail2ban activity
echo "" >> "$LOG_FILE"
echo "Fail2ban Activity:" >> "$LOG_FILE"
grep "Ban\|Unban" /var/log/fail2ban.log | tail -10 >> "$LOG_FILE" 2>/dev/null || echo "No fail2ban activity" >> "$LOG_FILE"

# Check for unusual network activity
echo "" >> "$LOG_FILE"
echo "Network Connection Summary:" >> "$LOG_FILE"
ss -tuln | grep -E "(51820|1194)" >> "$LOG_FILE" 2>/dev/null || echo "No VPN ports listening" >> "$LOG_FILE"

echo "" >> "$LOG_FILE"
echo "Analysis completed at $DATE" >> "$LOG_FILE"
echo "=========================================" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"
EOF

    chmod +x /usr/local/bin/vpn-log-monitor
    
    # Schedule log monitoring
    cat > /etc/cron.hourly/vpn-log-monitor << 'EOF'
#!/bin/bash
/usr/local/bin/vpn-log-monitor
EOF
    
    chmod +x /etc/cron.hourly/vpn-log-monitor
    
    print_security "Log monitoring configured"
}

# Create security status script
create_security_status() {
    print_status "Creating security status script..."
    
    cat > /usr/local/bin/vpn-security-status << 'EOF'
#!/bin/bash

# VPN Security Status Script

echo "VPN Server Security Status"
echo "========================="
echo ""

# System updates
echo "System Updates:"
echo "---------------"
if apt list --upgradable 2>/dev/null | grep -q upgradable; then
    echo "⚠️  Updates available:"
    apt list --upgradable 2>/dev/null | grep upgradable | head -5
else
    echo "✅ System is up to date"
fi
echo ""

# SSH Security
echo "SSH Security:"
echo "-------------"
if grep -q "PermitRootLogin no" /etc/ssh/sshd_config; then
    echo "✅ Root login disabled"
else
    echo "⚠️  Root login may be enabled"
fi

if grep -q "PasswordAuthentication no" /etc/ssh/sshd_config; then
    echo "✅ Password authentication disabled"
else
    echo "⚠️  Password authentication may be enabled"
fi
echo ""

# Firewall Status
echo "Firewall Status:"
echo "----------------"
if systemctl is-active --quiet ufw; then
    echo "✅ UFW firewall is active"
    ufw status | head -10
else
    echo "⚠️  UFW firewall is not active"
fi
echo ""

# Fail2ban Status
echo "Fail2ban Status:"
echo "----------------"
if systemctl is-active --quiet fail2ban; then
    echo "✅ Fail2ban is active"
    fail2ban-client status | head -5
else
    echo "⚠️  Fail2ban is not active"
fi
echo ""

# Audit System
echo "Audit System:"
echo "-------------"
if systemctl is-active --quiet auditd; then
    echo "✅ Audit system is active"
    echo "Recent audit events: $(ausearch -ts today | wc -l)"
else
    echo "⚠️  Audit system is not active"
fi
echo ""

# VPN Services Security
echo "VPN Services:"
echo "-------------"
if systemctl is-active --quiet wg-quick@wg0; then
    echo "✅ WireGuard is running"
    echo "   Active peers: $(wg show wg0 peers 2>/dev/null | wc -l)"
else
    echo "ℹ️  WireGuard is not running"
fi

if systemctl is-active --quiet openvpn@server; then
    echo "✅ OpenVPN is running"
    if [[ -f /etc/openvpn/openvpn-status.log ]]; then
        echo "   Connected clients: $(grep -c "^CLIENT_LIST" /etc/openvpn/openvpn-status.log 2>/dev/null || echo "0")"
    fi
else
    echo "ℹ️  OpenVPN is not running"
fi
echo ""

# Recent Security Events
echo "Recent Security Events:"
echo "----------------------"
echo "Last 5 authentication failures:"
grep "authentication failure" /var/log/auth.log | tail -5 | cut -d' ' -f1-3,9- 2>/dev/null || echo "No recent failures"
echo ""

echo "Security status check completed at $(date)"
EOF

    chmod +x /usr/local/bin/vpn-security-status
    print_security "Security status script created: /usr/local/bin/vpn-security-status"
}

# Main hardening function
apply_security_hardening() {
    update_system
    secure_ssh
    setup_firewall_protection
    setup_intrusion_detection
    setup_system_auditing
    secure_kernel
    setup_log_monitoring
    create_security_status
    
    print_status "Security hardening completed successfully!"
    print_status ""
    print_status "Security recommendations:"
    print_status "1. Change default SSH port in /etc/ssh/sshd_config"
    print_status "2. Set up key-based SSH authentication"
    print_status "3. Configure email alerts for security events"
    print_status "4. Regularly run 'vpn-security-status' to check security posture"
    print_status "5. Review logs in /var/log/vpn-security.log"
    print_status ""
    print_status "⚠️  IMPORTANT: Test SSH access before logging out!"
}

# Security check function
security_check() {
    if command -v vpn-security-status >/dev/null 2>&1; then
        vpn-security-status
    else
        print_error "Security status script not found. Run with 'apply' first."
    fi
}

# Main menu
case "${1:-apply}" in
    apply)
        apply_security_hardening
        ;;
    check)
        security_check
        ;;
    *)
        echo "Usage: $0 {apply|check}"
        echo "  apply - Apply all security hardening measures (default)"
        echo "  check - Check current security status"
        exit 1
        ;;
esac

