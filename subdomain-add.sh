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

# --- CREATE DIRECTORY ---
echo "📁 Creating subdomain directory: $SUB_DIR"
mkdir -p "$SUB_DIR"
echo "<h1>$SUBDOMAIN is live!</h1>" > "$SUB_DIR/index.html"
chown -R "$APP_USER:$APP_USER" "$SUB_DIR"
chmod -R 755 "$SUB_DIR"

# --- APACHE VIRTUAL HOST ---
echo "🌐 Creating Apache VirtualHost for $SUBDOMAIN"
cat <<EOF > /etc/apache2/sites-available/$SUBDOMAIN.conf
<VirtualHost *:80>
    ServerName $SUBDOMAIN
EOF

# Add ServerAlias if alias domains were entered
if [[ -n "$ALIAS_DOMAINS" ]]; then
    echo "    ServerAlias $ALIAS_DOMAINS" >> /etc/apache2/sites-available/$SUBDOMAIN.conf
fi

cat <<EOF >> /etc/apache2/sites-available/$SUBDOMAIN.conf
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

read -p "Use staging mode for SSL (for testing)? [y/N]: " USE_STAGING
STAGING_FLAG=""
if [[ "$USE_STAGING" == "y" || "$USE_STAGING" == "Y" ]]; then
    STAGING_FLAG="--staging"
fi

# --- INSTALL SSL CERT ---
echo "🔒 Installing SSL certificate for $SUBDOMAIN"
certbot --apache --non-interactive --agree-tos --redirect -m admin@$SUBDOMAIN -d $SUBDOMAIN $STAGING_FLAG

# --- DONE ---
echo "✅ Subdomain is live: https://$SUBDOMAIN"
