#!/bin/bash

# Exit on any error
set -e

echo "Starting UFW setup script..."

# Install required packages
echo "Installing required packages..."
apt-get update -y && apt-get install ufw

# Configure UFW
echo "Configuring UFW ports..."
ufw allow 22/tcp comment 'ssh'
ufw allow 80/tcp comment 'http'
ufw allow 443/tcp comment 'https'

# Get SSH port from sshd_config
SSH_PORT=$(grep -E "^Port\s+[0-9]+" /etc/ssh/sshd_config | awk '{print $2}')

# If no Port is specified in sshd_config, use default port 22
if [ -z "$SSH_PORT" ]; then
    echo "No SSH port specified in sshd_config, using default port 22"
    SSH_PORT=22
fi

echo "Allowing SSH port: $SSH_PORT"
ufw allow ${SSH_PORT}/tcp comment 'ssh'

# Add Docker rules to after.rules
echo "Adding Docker rules to UFW configuration..."
cat << 'EOF' >> /etc/ufw/after.rules

# BEGIN UFW AND DOCKER
*filter
:ufw-user-forward - [0:0]
:ufw-docker-logging-deny - [0:0]
:DOCKER-USER - [0:0]
-A DOCKER-USER -j ufw-user-forward
-A DOCKER-USER -j RETURN -s 10.0.0.0/8
-A DOCKER-USER -j RETURN -s 172.16.0.0/12
-A DOCKER-USER -j RETURN -s 192.168.0.0/16
-A DOCKER-USER -p udp -m udp --sport 53 --dport 1024:65535 -j RETURN
-A DOCKER-USER -j ufw-docker-logging-deny -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -d 192.168.0.0/16
-A DOCKER-USER -j ufw-docker-logging-deny -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -d 10.0.0.0/8
-A DOCKER-USER -j ufw-docker-logging-deny -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -d 172.16.0.0/12
-A DOCKER-USER -j ufw-docker-logging-deny -p udp -m udp --dport 0:32767 -d 192.168.0.0/16
-A DOCKER-USER -j ufw-docker-logging-deny -p udp -m udp --dport 0:32767 -d 10.0.0.0/8
-A DOCKER-USER -j ufw-docker-logging-deny -p udp -m udp --dport 0:32767 -d 172.16.0.0/12
-A DOCKER-USER -j RETURN
-A ufw-docker-logging-deny -m limit --limit 3/min --limit-burst 10 -j LOG --log-prefix "[UFW DOCKER BLOCK] "
-A ufw-docker-logging-deny -j DROP
COMMIT
# END UFW AND DOCKER
EOF

# Check if nginx container exists
echo "Checking nginx container..."
if ! docker ps | grep -q nginx; then
    echo "Error: nginx container not found!"
    exit 1
fi

# Get nginx container IP and configure UFW rules
echo "Configuring UFW rules for nginx container..."
NGINX_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' nginx)

if [ -z "$NGINX_IP" ]; then
    echo "Error: Could not get nginx container IP!"
    exit 1
fi

echo "Nginx container IP: $NGINX_IP"

# Configure UFW rules for nginx
ufw route allow proto tcp from any to $NGINX_IP port 80 comment 'docker nginx bridge'
ufw route allow proto tcp from any to $NGINX_IP port 443 comment 'docker nginx bridge'
ufw allow from $NGINX_IP to any comment 'allow docker nginx ip'

# Enable UFW
echo "Enabling UFW..."
echo "y" | ufw enable

echo "UFW setup completed successfully!"
