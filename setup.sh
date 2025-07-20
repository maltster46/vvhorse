#!/bin/bash

# Request user input
read -p "Enter domain name (e.g., example.com): " domain
read -s -p "Enter password for Trojan: " trojan_password
read -s -p "Enter your email for certificate expiration notifications: " email
echo ""

# Validate input
if [[ -z "$domain" || -z "$trojan_password" || -z "$email" ]]; then
    echo "Error: Domain and password and email cannot be empty!"
    exit 1
fi

echo "Starting installation Trojan server with certificates auto updating and Nginx for masking of Trojan work"

# System update
echo "Updating packages..."
sudo apt update -y
sudo apt upgrade -y

# Install Certbot and get SSL certificates
echo "Installing Certbot..."
sudo apt install certbot -y

echo "Obtaining SSL certificates..."
sudo certbot certonly --standalone --agree-tos --no-eff-email --email "$email" -d "$domain" --non-interactive

# Install and configure Trojan
echo "Installing Trojan..."
sudo apt install trojan -y

echo "Creating Trojan configuration..."
sudo bash -c "cat > /etc/trojan/config.json" <<EOF
{
    "run_type": "server",
    "local_addr": "0.0.0.0",
    "local_port": 443,
    "remote_addr": "127.0.0.1",
    "remote_port": 80,
    "password": [
        "$trojan_password"
    ],
    "log_level": 1,
    "ssl": {
        "cert": "/etc/letsencrypt/live/$domain/fullchain.pem",
        "key": "/etc/letsencrypt/live/$domain/privkey.pem",
        "key_password": "",
        "cipher": "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384",
        "cipher_tls13": "TLS_AES_128_GCM_SHA256:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_256_GCM_SHA384",
        "prefer_server_cipher": true,
        "alpn": [
            "http/1.1"
        ],
        "reuse_session": true,
        "session_ticket": false,
        "session_timeout": 600,
        "plain_http_response": "",
        "curves": "",
        "dhparam": ""
    },
    "tcp": {
        "prefer_ipv4": false,
        "no_delay": true,
        "keep_alive": true,
        "reuse_port": false,
        "fast_open": false,
        "fast_open_qlen": 20
    },
    "mysql": {
        "enabled": false,
        "server_addr": "127.0.0.1",
        "server_port": 3306,
        "database": "trojan",
        "username": "trojan",
        "password": ""
    }
}
EOF

# Configure user and permissions
echo "Configuring user and permissions..."
sudo cp /lib/systemd/system/trojan.service /etc/systemd/system/
sudo useradd -r -M -s /usr/sbin/nologin trojan
sudo chown -R trojan:trojan /etc/trojan/

sudo groupadd sslaccess
sudo usermod -aG sslaccess trojan

sudo chown -R root:sslaccess /etc/letsencrypt/live/
sudo chown -R root:sslaccess /etc/letsencrypt/archive/
sudo chmod -R 750 /etc/letsencrypt/live/
sudo chmod -R 750 /etc/letsencrypt/archive/

sudo chmod 640 /etc/letsencrypt/live/"$domain"/*.pem
sudo chmod 640 /etc/letsencrypt/archive/"$domain"/*.pem

# Configure Trojan service
echo "Configuring Trojan service..."
sudo sed -i 's/User=nobody/User=trojan/g' /etc/systemd/system/trojan.service
# Add or replace Group line
if grep -q "^Group=" /etc/systemd/system/trojan.service; then
    sudo sed -i 's/^Group=.*/Group=trojan/g' /etc/systemd/system/trojan.service
else
    # Insert Group line after User line if it doesn't exist
    sudo sed -i '/^User=/a Group=trojan' /etc/systemd/system/trojan.service
fi

sudo systemctl daemon-reload
sudo systemctl enable trojan
sudo systemctl start trojan

# Install and configure Nginx
echo "Installing Nginx..."
sudo apt install nginx -y

echo "Creating Nginx configuration..."
sudo bash -c "cat > /etc/nginx/sites-available/$domain" <<EOF
server {
    listen 80;
    server_name $domain;
    return 301 https://\$host\$request_uri;
}

server {
    listen 127.0.0.1:80;
    server_name $domain;
    root /var/www/html;
    index index.html;
}
EOF

sudo ln -s /etc/nginx/sites-available/"$domain" /etc/nginx/sites-enabled/
sudo systemctl restart nginx

# Configure certificate auto-renewal
echo "Configuring certificate auto-renewal..."
(sudo crontab -l 2>/dev/null; echo "0 3 * * * /usr/bin/certbot renew --quiet --pre-hook \"systemctl stop nginx\" --post-hook \"systemctl restart trojan && systemctl start nginx\"") | sudo crontab -

echo "Installation completed successfully!"
