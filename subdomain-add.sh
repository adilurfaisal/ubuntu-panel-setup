#!/bin/bash

# --- INPUTS ---
read -p "Enter your main domain (e.g. butechbd.com): " MAIN_DOMAIN
read -p "Enter subdomain to create (e.g. api): " SUB
read -p "Enter alias domain(s) (space-separated, optional): " ALIAS_DOMAINS

SUBDOMAIN="$SUB.$MAIN_DOMAIN"
APP_USER=$(echo "$MAIN_DOMAIN" | cut -d'.' -f1)

read -p "Enter custom directory path (e.g. api.butechbd.com) (default: /home/$APP_USER/public_html/$SUBDOMAIN): " CUSTOM_DIR

# Use default directory if not specified
if [[ -n "$CUSTOM_DIR" ]]; then
    SUB_DIR="/home/$APP_USER/public_html/$CUSTOM_DIR"
else
    SUB_DIR="/home/$APP_USER/public_html/$SUBDOMAIN"
fi

# --- VERIFY DNS RESOLUTION ---
echo "🌐 Verifying DNS resolution for $SUBDOMAIN..."
RESOLVED_IP=$(dig +short "$SUBDOMAIN" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n1)
SERVER_IP=$(curl -s ifconfig.me)

if [[ "$RESOLVED_IP" != "$SERVER_IP" ]]; then
    echo "❌ ERROR: $SUBDOMAIN does not resolve to this server ($SERVER_IP)."
    echo "Resolved IP: $RESOLVED_IP"
    echo "Please update your CNAME or A record and try again."
    exit 1
fi

# --- CREATE DIRECTORY ---
echo "📁 Creating subdomain directory: $SUB_DIR"
mkdir -p "$SUB_DIR"
if [[ ! -f "$SUB_DIR/index.html" ]]; then
    echo "<h1>$SUBDOMAIN is live!</h1>" > "$SUB_DIR/index.html"
fi
chown -R "$APP_USER:$APP_USER" "$SUB_DIR"
chmod -R 755 "$SUB_DIR"

# --- APACHE VIRTUAL HOST ---
VHOST_PATH="/etc/apache2/sites-available/$SUBDOMAIN.conf"
echo "🌐 Creating Apache VirtualHost for $SUBDOMAIN"

cat <<EOF > "$VHOST_PATH"
<VirtualHost *:80>
    ServerName $SUBDOMAIN
EOF

if [[ -n "$ALIAS_DOMAINS" ]]; then
    echo "    ServerAlias $ALIAS_DOMAINS" >> "$VHOST_PATH"
fi

cat <<EOF >> "$VHOST_PATH"
    ServerAdmin webmaster@$SUBDOMAIN
    DocumentRoot "$SUB_DIR"

    <Directory "$SUB_DIR">
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/$SUBDOMAIN-error.log
    CustomLog \${APACHE_LOG_DIR}/$SUBDOMAIN-access.log combined
</VirtualHost>
EOF

# --- ENABLE SITE & RELOAD APACHE ---
a2ensite "$SUBDOMAIN.conf"
systemctl reload apache2

# --- CERTBOT STAGING/PRODUCTION ---
read -p "Use staging mode for SSL (for testing)? [y/N]: " USE_STAGING
STAGING_FLAG=""
if [[ "$USE_STAGING" == "y" || "$USE_STAGING" == "Y" ]]; then
    STAGING_FLAG="--staging"
fi

# --- INSTALL SSL CERT ---
echo "🔒 Installing SSL certificate for $SUBDOMAIN"
certbot --apache --non-interactive --agree-tos --redirect \
  -m "admin@$MAIN_DOMAIN" \
  -d "$SUBDOMAIN" $STAGING_FLAG

# --- DONE ---
echo "✅ Subdomain is live with SSL: https://$SUBDOMAIN"
