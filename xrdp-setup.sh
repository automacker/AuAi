#!/bin/bash

# XRDP Server Setup Script for Ubuntu 24.04.3 LTS
# This script automates XRDP server installation and configuration
# It uses existing system users instead of creating a default one

set -e  # Exit on any error

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
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "Please run as root or with sudo"
    exit 1
fi

print_header "XRDP Server Setup for Ubuntu 24.04.3 LTS"

# Update system
print_status "Updating system packages..."
apt update && apt upgrade -y

# Install XRDP and required packages
print_status "Installing XRDP and required packages..."
apt install -y xrdp xorgxrdp xauth xorg dbus-x11

# Get system information
HOSTNAME=$(hostname)
PUBLIC_IP=$(curl -s https://api.ipify.org || echo "Unable to determine")
LOCAL_IP=$(hostname -I | awk '{print $1}')

# Configure XRDP
print_status "Configuring XRDP..."

# Backup original config
cp /etc/xrdp/xrdp.ini /etc/xrdp/xrdp.ini.backup

# Configure XRDP to use hostname and local IP
cat > /etc/xrdp/xrdp.ini << EOF
[globals]
bitmap_cache=yes
bitmap_compression=yes
port=3389
crypt_level=low
channel_code=1
max_bpp=24
security_layer=negotiate
ssl_protocols=TLSv1.2, TLSv1.3
certificate=
key_file=
allow_channels=true
allow_multimon=true
bitmap_cache=true
bitmap_compression=true
bulk_compression=true
max_bandwidth=auto
use_compression=yes

[xrdp1]
name=XRDP Session
lib=libvnc.so
username=ask
password=ask
ip=${LOCAL_IP}
port=-1
code=20

EOF

# Configure sesman.ini
cat > /etc/xrdp/sesman.ini << EOF
[Globals]
ListenAddress=${LOCAL_IP}
ListenPort=3350
EnableUserWindowManager=true
UserWindowManager=startwm.sh
DefaultWindowManager=startwm.sh

[Security]
AllowRootLogin=false
MaxLoginRetry=4
TerminalServerUsers=tsusers
TerminalServerAdmins=tsadmin
AlwaysGroupCheck=false

[Sessions]
X11DisplayOffset=10
MaxSessions=50
KillDisconnected=false
IdleTimeLimit=0
DisconnectedTimeLimit=0

[Logging]
LogFile=/var/log/xrdp-sesman.log
LogLevel=INFO
EnableSyslog=true
SyslogLevel=INFO

EOF

# Create startup script for XRDP session
cat > /etc/xrdp/startwm.sh << 'EOF'
#!/bin/sh
if [ -r /etc/default/locale ]; then
    . /etc/default/locale
    export LANG LANGUAGE
fi

# Start the session
if [ -f /etc/X11/Xsession ]; then
    . /etc/X11/Xsession
else
    . /usr/bin/x-session-manager
fi
EOF

chmod +x /etc/xrdp/startwm.sh

# Enable and start XRDP service
print_status "Enabling and starting XRDP service..."
systemctl enable xrdp
systemctl restart xrdp
systemctl enable xrdp-sesman
systemctl restart xrdp-sesman

# Configure firewall
print_status "Configuring firewall..."
if command -v ufw &> /dev/null; then
    ufw allow 3389/tcp
    ufw reload
    print_status "Firewall configured to allow XRDP connections (port 3389)"
fi

# Get available system users
print_header "Available System Users"
echo "The following users can access the system via XRDP:"
echo "----------------------------------------"

# List all regular users (UID >= 1000, not /usr/nologin or /bin/false)
getent passwd | awk -F: '$3 >= 1000 && $7 != "/usr/sbin/nologin" && $7 != "/bin/false" {print $1}' | while read user; do
    # Check if user has a home directory
    if [ -d "/home/$user" ]; then
        echo "- $user"
    fi
done

echo "----------------------------------------"
print_warning "Note: Users must have a password set to login via XRDP"
print_warning "Set a password with: sudo passwd username"

# Create connection information file in /tmp
INFO_FILE="/tmp/xrdp_connection_info.txt"
cat > "$INFO_FILE" << EOF
XRDP Connection Information
===========================

Server Details:
- Hostname: $HOSTNAME
- Public IP: $PUBLIC_IP
- Local IP: $LOCAL_IP
- XRDP Port: 3389

Available Users:
$(getent passwd | awk -F: '$3 >= 1000 && $7 != "/usr/sbin/nologin" && $7 != "/bin/false" {print $1}' | while read user; do
    if [ -d "/home/$user" ]; then
        echo "- $user"
    fi
done)

Connection Instructions:
1. Use Remote Desktop Client (Windows) or Remmina (Linux)
2. Connect to: $PUBLIC_IP (or $LOCAL_IP if on local network)
3. Port: 3389
4. Use your system username and password

Security Notes:
- Only users with password authentication can connect
- Consider setting up SSH keys for more secure access
- Keep your system updated regularly

Generated on: $(date)
EOF

# Display connection information
print_header "XRDP SERVER SETUP COMPLETE"
print_status "Hostname: $HOSTNAME"
print_status "Public IP: $PUBLIC_IP"
print_status "Local IP: $LOCAL_IP"
print_status "XRDP Port: 3389"
print_status ""
print_status "Available users for XRDP access:"
getent passwd | awk -F: '$3 >= 1000 && $7 != "/usr/sbin/nologin" && $7 != "/bin/false" {print $1}' | while read user; do
    if [ -d "/home/$user" ]; then
        print_status "  - $user"
    fi
done
print_status ""
print_status "Connection information saved to: $INFO_FILE"

# Test XRDP service
print_status "Testing XRDP service..."
if systemctl is-active --quiet xrdp; then
    print_status "XRDP service is running successfully"
else
    print_error "XRDP service is not running. Check logs: journalctl -u xrdp"
fi

print_header "SETUP COMPLETED SUCCESSFULLY"
print_status "You can now connect using any RDP client to: $PUBLIC_IP"
print_status ""
print_warning "Important: Users must have a password set to login via XRDP"
print_warning "Set a password for a user with: sudo passwd username"
