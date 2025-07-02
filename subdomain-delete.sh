#!/bin/bash

# --- INPUT ---
read -p "Enter your main domain (e.g. butechbd.com): " MAIN_DOMAIN
read -p "Enter subdomain to remove (e.g. api): " SUB
SUBDOMAIN="$SUB.$MAIN_DOMAIN"
APP_USER=$(echo "$MAIN_DOMAIN" | cut -d'.' -f1)
SUB_DIR="/home/$APP_USER/public_html/$SUBDOMAIN"
VHOST_FILE="/etc/apache2/sites-available/$SUBDOMAIN.conf"

# --- DISABLE SITE ---
echo "🚫 Disabling Apache site for $SUBDOMAIN"
a2dissite "$SUBDOMAIN.conf"

# --- DELETE VHOST CONFIG ---
echo "🗑️ Removing virtual host config: $VHOST_FILE"
rm -f "$VHOST_FILE"

# --- DELETE DIRECTORY ---
echo "🗑️ Deleting subdomain directory: $SUB_DIR"
rm -rf "$SUB_DIR"

# --- REMOVE SSL CERTIFICATE (optional) ---
echo "🧹 Deleting SSL certificate for $SUBDOMAIN"
certbot delete --cert-name "$SUBDOMAIN"

# --- RELOAD APACHE ---
echo "🔄 Reloading Apache"
systemctl reload apache2

# --- DONE ---
echo "✅ Subdomain $SUBDOMAIN has been removed."
