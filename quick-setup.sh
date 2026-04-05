#!/bin/bash

# Interactive First-Time Setup Script

echo "Welcome to the interactive setup script!"

# Bot Token Configuration
read -p "Enter your bot token: " BOT_TOKEN
echo "Bot token entered: $BOT_TOKEN"

# Admin ID Setup
read -p "Enter your admin ID: " ADMIN_ID
echo "Admin ID entered: $ADMIN_ID"

# ZIVPN Password Configuration
read -p "Enter your ZIVPN password: " ZIVPN_PASSWORD
echo "ZIVPN password entered: $ZIVPN_PASSWORD"

# QRIS Payment Setup
read -p "Enter your QRIS payment information: " QRIS_PAYMENT_INFO
echo "QRIS payment information entered: $QRIS_PAYMENT_INFO"

# Save Configuration to File
cat <<EOL > config.sh
BOT_TOKEN="$BOT_TOKEN"
ADMIN_ID="$ADMIN_ID"
ZIVPN_PASSWORD="$ZIVPN_PASSWORD"
QRIS_PAYMENT_INFO="$QRIS_PAYMENT_INFO"
EOL

echo "Setup Complete! Configuration saved to 'config.sh'"