#!/bin/bash

gen_pass() {
	matrix=$1
	length=$2
	if [ -z "$matrix" ]; then
		matrix="A-Za-z0-9"
	fi
	if [ -z "$length" ]; then
		length=16
	fi
	head /dev/urandom | tr -dc $matrix | head -c$length
}

# --- GET INPUT ---
read -p "Enter your APP_DOMAIN (e.g. butechbd.com): " APP_DOMAIN

# --- DERIVED VALUES ---
APP_USER=$(echo "$APP_DOMAIN" | cut -d'.' -f1)
APP_DIR="/home/$APP_USER/public_html/$APP_DOMAIN"
PHP_VERSION="8.3"
DB_USER="root"
APACHE_ENVVARS="/etc/apache2/envvars"
MYSQL_CONFIG="/etc/mysql/mariadb.conf.d/50-server.cnf"

# --- CREATE SYSTEM USER ---
USER_PASSWORD=$(openssl rand -base64 12)
if id "$APP_USER" &>/dev/null; then
    echo "✅ User '$APP_USER' already exists"
else
    echo "➕ Creating Linux user: $APP_USER"
    useradd -m -s /bin/bash "$APP_USER"
    echo "$APP_USER:$USER_PASSWORD" | chpasswd
    echo "✅ User '$APP_USER' created with password"
fi

# --- ENABLE SSH PASSWORD LOGIN ---
echo "🔧 Ensuring SSH allows password authentication..."
SSHD_CONFIG="/etc/ssh/sshd_config"
if grep -q "^PasswordAuthentication no" $SSHD_CONFIG; then
    sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' $SSHD_CONFIG
elif ! grep -q "^PasswordAuthentication" $SSHD_CONFIG; then
    echo "PasswordAuthentication yes" >> $SSHD_CONFIG
fi
systemctl reload sshd

# --- PACKAGE INSTALLATION ---
echo "🔄 Updating system and installing dependencies..."
apt update && apt upgrade -y
apt install -y software-properties-common curl unzip git
sudo apt install openjdk-8-jdk -y

if dpkg -l | grep -q mariadb-server; then
    echo "✅ MariaDB is already installed"
else
    echo "📦 Installing MariaDB Server..."
    apt install -y mariadb-server
    systemctl enable mariadb
    systemctl start mariadb
fi

echo "➕ Adding PHP repository..."
add-apt-repository ppa:ondrej/php -y
apt update

echo "📦 Installing PHP $PHP_VERSION and Apache..."
apt install -y apache2 libapache2-mod-php$PHP_VERSION \
php$PHP_VERSION php$PHP_VERSION-cli php$PHP_VERSION-fpm \
php$PHP_VERSION-mbstring php$PHP_VERSION-xml php$PHP_VERSION-mysql \
php$PHP_VERSION-curl php$PHP_VERSION-zip php$PHP_VERSION-bcmath \
php$PHP_VERSION-gd php$PHP_VERSION-soap php$PHP_VERSION-intl

a2enmod rewrite ssl
systemctl restart apache2

# --- CREATE APP DIRECTORY ---
echo "📁 Creating app directory at: $APP_DIR"
mkdir -p "$APP_DIR"
chown -R "$APP_USER:$APP_USER" "/home/$APP_USER"
chmod -R 755 "/home/$APP_USER"


echo "🔧 Updating Apache user to: $APP_USER"

# --- BACKUP ENVVARS FILE ---
sudo cp "$APACHE_ENVVARS" "${APACHE_ENVVARS}.bak"

# --- REPLACE APACHE USER & GROUP IN ENVVARS ---
sudo sed -i "s/^export APACHE_RUN_USER=.*/export APACHE_RUN_USER=$APP_USER/" "$APACHE_ENVVARS"
sudo sed -i "s/^export APACHE_RUN_GROUP=.*/export APACHE_RUN_GROUP=$APP_USER/" "$APACHE_ENVVARS"

# --- RESTART APACHE ---
echo "🔁 Restarting Apache..."
sudo systemctl restart apache2

# --- CREATE DB USER ONLY ---
DB_PASSWORD=$(gen_pass)
echo "🔐 Creating MariaDB user '$DB_USER' (no database)..."
mysql -e "CREATE USER IF NOT EXISTS '$DB_USER'@'%' IDENTIFIED BY '$DB_PASSWORD';"
mysql -e "FLUSH PRIVILEGES;"

# --- UPDATE MYSQL BIND ADDRESS ---
echo "🌐 Updating MariaDB bind-address to 0.0.0.0"

# BACKUP MySQL config file
sudo cp "$MYSQL_CONFIG" "${MYSQL_CONFIG}.bak"

# Change bind-address
sudo sed -i "s/^bind-address\s*=.*/bind-address = 0.0.0.0/" "$MYSQL_CONFIG"

# --- RESTART MYSQL ---
echo "🔁 Restarting MariaDB..."
sudo systemctl restart mariadb

# --- COMPOSER ---
echo "🎼 Installing Composer..."
curl -sS https://getcomposer.org/installer | php
mv composer.phar /usr/local/bin/composer


# --- Apache VirtualHost ---
echo "🌐 Creating Apache virtual host: $APP_DOMAIN"
cat <<EOF > /etc/apache2/sites-available/$APP_DOMAIN.conf
<VirtualHost *:80>
    ServerName $APP_DOMAIN
    ServerAdmin webmaster@$APP_DOMAIN
    DocumentRoot "$APP_DIR/public"

    <Directory "$APP_DIR/public">
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/$APP_DOMAIN-error.log
    CustomLog \${APACHE_LOG_DIR}/$APP_DOMAIN-access.log combined
</VirtualHost>
EOF

a2ensite "$APP_DOMAIN.conf"
a2dissite 000-default.conf
systemctl reload apache2

# --- SSL INSTALL ---
echo "🔒 Installing Certbot and SSL for $APP_DOMAIN"
apt install -y certbot python3-certbot-apache
certbot --apache --non-interactive --agree-tos --redirect -m admin@$APP_DOMAIN -d $APP_DOMAIN

# --- DONE ---
echo "✅ Laravel site is ready at: https://$APP_DOMAIN"
echo "🔐 SSH login: $APP_USER"
echo "🔐 SSH password: $USER_PASSWORD"
echo "🔐 MariaDB user: $DB_USER"
echo "🔐 MariaDB password: $DB_PASSWORD"
