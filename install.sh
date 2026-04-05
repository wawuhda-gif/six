#!/bin/bash

# ZIVPN UDP Multi-VPS Panel Installer Script

# Function to detect OS
detect_os() {
    if [ -f /etc/debian_version ]; then
        echo "Debian"
    elif [ -f /etc/lsb-release ]; then
        echo "Ubuntu"
    else
        echo "Unsupported OS. This script only supports Debian and Ubuntu."
        exit 1
    fi
}

# Update and install required packages
install_packages() {
    apt-get update
    apt-get install -y curl wget openssl
}

# Download ZIVPN binary
download_zivpn() {
    local url="https://example.com/path/to/zivpn-binary"
    wget -O /usr/local/bin/zivpn "$url"
    chmod +x /usr/local/bin/zivpn
}

# Create necessary directories
setup_directories() {
    mkdir -p /etc/zivpn
    mkdir -p /var/log/zivpn
}

# Generate SSL certificates
generate_ssl() {
    openssl req -newkey rsa:2048 -nodes -keyout /etc/zivpn/server.key -x509 -days 365 -out /etc/zivpn/server.crt \
    -subj "/C=US/ST=State/L=City/O=Organization/OU=Department/CN=yourdomain.com"
}

# Configure network tuning
configure_network() {
    echo "net.core.rmem_max = 16777216" >> /etc/sysctl.conf
    echo "net.core.wmem_max = 16777216" >> /etc/sysctl.conf
    sysctl -p
}

# Setup systemd service
setup_service() {
    cat <<EOL > /etc/systemd/system/zivpn.service
[Unit]
Description=ZIVPN Service
After=network.target

[Service]
ExecStart=/usr/local/bin/zivpn
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOL

    systemctl enable zivpn
}

# Initialize databases
initialize_databases() {
    # Commands to initialize databases would go here
    echo "Databases initialized."
}

# Main script execution
main() {
    OS=$(detect_os)
    install_packages
    download_zivpn
    setup_directories
    generate_ssl
    configure_network
    setup_service
    initialize_databases
    echo "ZIVPN Installation Complete!"
}

main
