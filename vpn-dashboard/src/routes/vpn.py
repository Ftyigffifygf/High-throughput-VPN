from flask import Blueprint, jsonify, request
import subprocess
import json
import os
import re
from datetime import datetime

vpn_bp = Blueprint('vpn', __name__)

def run_command(command, shell=False):
    """Execute a system command and return the result"""
    try:
        if shell:
            result = subprocess.run(command, shell=True, capture_output=True, text=True, timeout=30)
        else:
            result = subprocess.run(command, capture_output=True, text=True, timeout=30)
        return {
            'success': result.returncode == 0,
            'stdout': result.stdout,
            'stderr': result.stderr,
            'returncode': result.returncode
        }
    except subprocess.TimeoutExpired:
        return {
            'success': False,
            'stdout': '',
            'stderr': 'Command timed out',
            'returncode': -1
        }
    except Exception as e:
        return {
            'success': False,
            'stdout': '',
            'stderr': str(e),
            'returncode': -1
        }

@vpn_bp.route('/status', methods=['GET'])
def get_vpn_status():
    """Get overall VPN server status"""
    status = {
        'timestamp': datetime.now().isoformat(),
        'services': {},
        'system': {},
        'network': {}
    }
    
    # Check WireGuard status
    wg_status = run_command(['systemctl', 'is-active', 'wg-quick@wg0'])
    status['services']['wireguard'] = {
        'active': wg_status['success'] and wg_status['stdout'].strip() == 'active',
        'status': wg_status['stdout'].strip()
    }
    
    if status['services']['wireguard']['active']:
        # Get WireGuard peers
        wg_show = run_command(['wg', 'show', 'wg0'])
        if wg_show['success']:
            peer_count = len([line for line in wg_show['stdout'].split('\n') if line.startswith('peer:')])
            status['services']['wireguard']['peers'] = peer_count
    
    # Check OpenVPN status
    ovpn_status = run_command(['systemctl', 'is-active', 'openvpn@server'])
    status['services']['openvpn'] = {
        'active': ovpn_status['success'] and ovpn_status['stdout'].strip() == 'active',
        'status': ovpn_status['stdout'].strip()
    }
    
    if status['services']['openvpn']['active']:
        # Get OpenVPN clients
        if os.path.exists('/etc/openvpn/openvpn-status.log'):
            try:
                with open('/etc/openvpn/openvpn-status.log', 'r') as f:
                    content = f.read()
                    client_count = len([line for line in content.split('\n') if line.startswith('CLIENT_LIST')])
                    status['services']['openvpn']['clients'] = client_count
            except:
                status['services']['openvpn']['clients'] = 0
    
    # Check HAProxy status
    haproxy_status = run_command(['systemctl', 'is-active', 'haproxy'])
    status['services']['haproxy'] = {
        'active': haproxy_status['success'] and haproxy_status['stdout'].strip() == 'active',
        'status': haproxy_status['stdout'].strip()
    }
    
    # System information
    uptime_result = run_command(['uptime', '-p'])
    if uptime_result['success']:
        status['system']['uptime'] = uptime_result['stdout'].strip()
    
    load_result = run_command("uptime | awk -F'load average:' '{print $2}'", shell=True)
    if load_result['success']:
        status['system']['load_average'] = load_result['stdout'].strip()
    
    # Memory usage
    memory_result = run_command("free | awk 'NR==2{printf \"%.1f\", $3*100/$2}'", shell=True)
    if memory_result['success']:
        status['system']['memory_usage'] = memory_result['stdout'].strip() + '%'
    
    # CPU usage
    cpu_result = run_command("top -bn1 | grep 'Cpu(s)' | awk '{print $2}' | sed 's/%us,//'", shell=True)
    if cpu_result['success']:
        status['system']['cpu_usage'] = cpu_result['stdout'].strip() + '%'
    
    # Network interfaces
    interfaces_result = run_command(['ip', '-br', 'addr', 'show'])
    if interfaces_result['success']:
        interfaces = []
        for line in interfaces_result['stdout'].split('\n'):
            if line.strip() and not line.startswith('lo'):
                parts = line.split()
                if len(parts) >= 3:
                    interfaces.append({
                        'name': parts[0],
                        'status': parts[1],
                        'ip': parts[2] if len(parts) > 2 else 'N/A'
                    })
        status['network']['interfaces'] = interfaces
    
    return jsonify(status)

@vpn_bp.route('/wireguard/peers', methods=['GET'])
def get_wireguard_peers():
    """Get WireGuard peer information"""
    wg_show = run_command(['wg', 'show', 'wg0'])
    
    if not wg_show['success']:
        return jsonify({'error': 'Failed to get WireGuard status'}), 500
    
    peers = []
    current_peer = None
    
    for line in wg_show['stdout'].split('\n'):
        line = line.strip()
        if line.startswith('peer:'):
            if current_peer:
                peers.append(current_peer)
            current_peer = {
                'public_key': line.split('peer: ')[1],
                'endpoint': None,
                'allowed_ips': None,
                'latest_handshake': None,
                'transfer': {'received': 0, 'sent': 0}
            }
        elif current_peer and line.startswith('endpoint:'):
            current_peer['endpoint'] = line.split('endpoint: ')[1]
        elif current_peer and line.startswith('allowed ips:'):
            current_peer['allowed_ips'] = line.split('allowed ips: ')[1]
        elif current_peer and line.startswith('latest handshake:'):
            current_peer['latest_handshake'] = line.split('latest handshake: ')[1]
        elif current_peer and line.startswith('transfer:'):
            transfer_info = line.split('transfer: ')[1]
            # Parse transfer info (e.g., "1.23 KiB received, 2.34 KiB sent")
            parts = transfer_info.split(', ')
            if len(parts) >= 2:
                received = parts[0].split(' received')[0]
                sent = parts[1].split(' sent')[0]
                current_peer['transfer'] = {'received': received, 'sent': sent}
    
    if current_peer:
        peers.append(current_peer)
    
    return jsonify({'peers': peers})

@vpn_bp.route('/openvpn/clients', methods=['GET'])
def get_openvpn_clients():
    """Get OpenVPN client information"""
    if not os.path.exists('/etc/openvpn/openvpn-status.log'):
        return jsonify({'clients': []})
    
    try:
        with open('/etc/openvpn/openvpn-status.log', 'r') as f:
            content = f.read()
        
        clients = []
        for line in content.split('\n'):
            if line.startswith('CLIENT_LIST'):
                parts = line.split(',')
                if len(parts) >= 5:
                    clients.append({
                        'name': parts[1],
                        'real_address': parts[2],
                        'virtual_address': parts[3],
                        'bytes_received': parts[4],
                        'bytes_sent': parts[5],
                        'connected_since': parts[6] if len(parts) > 6 else 'N/A'
                    })
        
        return jsonify({'clients': clients})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@vpn_bp.route('/system/performance', methods=['GET'])
def get_system_performance():
    """Get system performance metrics"""
    performance = {}
    
    # CPU usage
    cpu_result = run_command("top -bn1 | grep 'Cpu(s)' | awk '{print $2}' | sed 's/%us,//'", shell=True)
    if cpu_result['success']:
        performance['cpu_usage'] = float(cpu_result['stdout'].strip())
    
    # Memory usage
    memory_result = run_command("free | awk 'NR==2{printf \"%.1f\", $3*100/$2}'", shell=True)
    if memory_result['success']:
        performance['memory_usage'] = float(memory_result['stdout'].strip())
    
    # Disk usage
    disk_result = run_command("df -h / | awk 'NR==2{print $5}' | sed 's/%//'", shell=True)
    if disk_result['success']:
        performance['disk_usage'] = float(disk_result['stdout'].strip())
    
    # Network statistics
    network_stats = {}
    net_result = run_command("cat /proc/net/dev | grep -E '(wg0|tun0)'", shell=True)
    if net_result['success']:
        for line in net_result['stdout'].split('\n'):
            if line.strip():
                parts = line.split()
                if len(parts) >= 10:
                    interface = parts[0].rstrip(':')
                    network_stats[interface] = {
                        'bytes_received': int(parts[1]),
                        'bytes_transmitted': int(parts[9])
                    }
    
    performance['network'] = network_stats
    
    return jsonify(performance)

@vpn_bp.route('/logs', methods=['GET'])
def get_logs():
    """Get recent VPN logs"""
    log_type = request.args.get('type', 'system')
    lines = int(request.args.get('lines', 50))
    
    logs = []
    
    if log_type == 'wireguard':
        log_result = run_command(['journalctl', '-u', 'wg-quick@wg0', '--no-pager', '-n', str(lines)])
        if log_result['success']:
            logs = log_result['stdout'].split('\n')
    elif log_type == 'openvpn':
        if os.path.exists('/var/log/openvpn.log'):
            log_result = run_command(['tail', '-n', str(lines), '/var/log/openvpn.log'])
            if log_result['success']:
                logs = log_result['stdout'].split('\n')
    elif log_type == 'system':
        log_result = run_command(['journalctl', '--no-pager', '-n', str(lines)])
        if log_result['success']:
            logs = log_result['stdout'].split('\n')
    elif log_type == 'security':
        if os.path.exists('/var/log/vpn-security.log'):
            log_result = run_command(['tail', '-n', str(lines), '/var/log/vpn-security.log'])
            if log_result['success']:
                logs = log_result['stdout'].split('\n')
    
    return jsonify({'logs': [log for log in logs if log.strip()]})

@vpn_bp.route('/config/backup', methods=['POST'])
def backup_config():
    """Create a backup of VPN configurations"""
    try:
        backup_dir = '/tmp/vpn-backup-' + datetime.now().strftime('%Y%m%d-%H%M%S')
        os.makedirs(backup_dir, exist_ok=True)
        
        # Backup WireGuard config
        if os.path.exists('/etc/wireguard'):
            run_command(['cp', '-r', '/etc/wireguard', backup_dir + '/wireguard'])
        
        # Backup OpenVPN config
        if os.path.exists('/etc/openvpn'):
            run_command(['cp', '-r', '/etc/openvpn', backup_dir + '/openvpn'])
        
        # Create tar archive
        archive_name = backup_dir + '.tar.gz'
        tar_result = run_command(['tar', '-czf', archive_name, '-C', '/tmp', os.path.basename(backup_dir)])
        
        if tar_result['success']:
            # Clean up temporary directory
            run_command(['rm', '-rf', backup_dir])
            return jsonify({'success': True, 'backup_file': archive_name})
        else:
            return jsonify({'success': False, 'error': 'Failed to create backup archive'}), 500
    
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500

@vpn_bp.route('/security/status', methods=['GET'])
def get_security_status():
    """Get security status"""
    security_status = {}
    
    # Check fail2ban status
    fail2ban_result = run_command(['systemctl', 'is-active', 'fail2ban'])
    security_status['fail2ban'] = {
        'active': fail2ban_result['success'] and fail2ban_result['stdout'].strip() == 'active'
    }
    
    if security_status['fail2ban']['active']:
        # Get fail2ban status
        fail2ban_status = run_command(['fail2ban-client', 'status'])
        if fail2ban_status['success']:
            security_status['fail2ban']['jails'] = fail2ban_status['stdout']
    
    # Check UFW status
    ufw_result = run_command(['ufw', 'status'])
    security_status['ufw'] = {
        'active': 'Status: active' in ufw_result['stdout'] if ufw_result['success'] else False,
        'rules': ufw_result['stdout'] if ufw_result['success'] else ''
    }
    
    # Check for recent authentication failures
    auth_failures = run_command("grep 'authentication failure' /var/log/auth.log | tail -5", shell=True)
    if auth_failures['success']:
        security_status['recent_auth_failures'] = auth_failures['stdout'].split('\n')
    
    return jsonify(security_status)

