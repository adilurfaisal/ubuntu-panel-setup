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

# --- APACHE VIRTUAL HOST CONFIG (HTTP & HTTPS) ---
echo "🌐 Creating Apache VirtualHost for $SUBDOMAIN"

CONF_PATH="/etc/apache2/sites-available/$SUBDOMAIN.conf"
cat <<EOF > "$CONF_PATH"
<VirtualHost *:80>
    ServerName $SUBDOMAIN
EOF

# Add ServerAlias if alias domains were entered
if [[ -n "$ALIAS_DOMAINS" ]]; then
    echo "    ServerAlias $ALIAS_DOMAINS" >> "$CONF_PATH"
fi

cat <<EOF >> "$CONF_PATH"
    ServerAdmin webmaster@$SUBDOMAIN
    DocumentRoot "$SUB_DIR"

    <Directory "$SUB_DIR">
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/$SUBDOMAIN-error.log
    CustomLog \${APACHE_LOG_DIR}/$SUBDOMAIN-access.log combined
</VirtualHost>

<VirtualHost *:443>
    ServerName $SUBDOMAIN
EOF

if [[ -n "$ALIAS_DOMAINS" ]]; then
    echo "    ServerAlias $ALIAS_DOMAINS" >> "$CONF_PATH"
fi

cat <<EOF >> "$CONF_PATH"
    ServerAdmin webmaster@$SUBDOMAIN
    DocumentRoot "$SUB_DIR"

    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/$SUBDOMAIN/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/$SUBDOMAIN/privkey.pem
    Include /etc/letsencrypt/options-ssl-apache.conf

    <Directory "$SUB_DIR">
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/$SUBDOMAIN-ssl-error.log
    CustomLog \${APACHE_LOG_DIR}/$SUBDOMAIN-ssl-access.log combined
</VirtualHost>
EOF

# --- ENABLE SITE & RELOAD APACHE ---
a2ensite "$SUBDOMAIN.conf"
systemctl reload apache2

# --- INSTALL SSL CERT ---
echo "🔒 Installing SSL certificate for $SUBDOMAIN and aliases"
apt install -y certbot python3-certbot-apache

# Combine subdomain and aliases into certbot -d flags
CERT_DOMAINS="-d $SUBDOMAIN"
for alias in $ALIAS_DOMAINS; do
    CERT_DOMAINS="$CERT_DOMAINS -d $alias"
done

certbot certonly --apache --non-interactive --agree-tos -m admin@$SUBDOMAIN $CERT_DOMAINS

# --- FINAL RELOAD ---
systemctl reload apache2

# --- DONE ---
echo "✅ Subdomain is live: https://$SUBDOMAIN"