#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${DATA_PLANE_KEY:-}" ]]; then
  echo "DATA_PLANE_KEY is required" >&2
  exit 1
fi

sudo mkdir -p /etc/ssl/nginx /etc/nginx /etc/apt/keyrings

sudo mv /tmp/nginx-repo.crt /etc/ssl/nginx/nginx-repo.crt
sudo mv /tmp/nginx-repo.key /etc/ssl/nginx/nginx-repo.key
sudo mv /tmp/license.jwt /etc/nginx/license.jwt
sudo mv /tmp/license.key /etc/nginx/license.key

sudo chown root:root /etc/ssl/nginx/nginx-repo.crt /etc/ssl/nginx/nginx-repo.key
sudo chmod 600 /etc/ssl/nginx/nginx-repo.key
sudo chmod 644 /etc/ssl/nginx/nginx-repo.crt

sudo chown root:root /etc/nginx/license.jwt /etc/nginx/license.key
sudo chmod 600 /etc/nginx/license.key
sudo chmod 644 /etc/nginx/license.jwt

sudo tee /etc/apt/apt.conf.d/90nginx >/dev/null <<'EOF'
Acquire::https::pkgs.nginx.com::SslCert "/etc/ssl/nginx/nginx-repo.crt";
Acquire::https::pkgs.nginx.com::SslKey  "/etc/ssl/nginx/nginx-repo.key";
EOF

sudo tee /etc/apt/apt.conf.d/99nginx-sandbox >/dev/null <<'EOF'
APT::Sandbox::User "root";
EOF

sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg lsb-release

codename="$(lsb_release -cs)"

# FIX-02: Use cs.nginx.com key (signs pkgs.nginx.com/plus), NOT nginx.org key
curl -fsSL https://cs.nginx.com/static/keys/nginx_signing.key | sudo gpg --yes --dearmor -o /usr/share/keyrings/nginx-archive-keyring.gpg
curl -fsSL https://cs.nginx.com/static/keys/app-protect-security-updates.key | \
  gpg --yes --dearmor | sudo tee /usr/share/keyrings/app-protect-security-updates.gpg > /dev/null

echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] https://pkgs.nginx.com/plus/ubuntu ${codename} nginx-plus" | \
  sudo tee /etc/apt/sources.list.d/nginx-plus.list

echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] https://pkgs.nginx.com/app-protect/ubuntu ${codename} nginx-plus" | \
  sudo tee /etc/apt/sources.list.d/nginx-app-protect.list

echo "deb [signed-by=/usr/share/keyrings/app-protect-security-updates.gpg] https://pkgs.nginx.com/app-protect-security-updates/ubuntu ${codename} nginx-plus" | \
  sudo tee /etc/apt/sources.list.d/app-protect-security-updates.list

sudo apt-get update
sudo apt-get install -y nginx-plus app-protect

if ! sudo grep -q '^load_module modules/ngx_http_app_protect_module.so;$' /etc/nginx/nginx.conf; then
  sudo sed -i '1iload_module modules/ngx_http_app_protect_module.so;' /etc/nginx/nginx.conf
fi

sudo tee /etc/nginx/conf.d/nginx-one-api.conf >/dev/null <<'EOF'
server {
    listen 127.0.0.1:8080;
    access_log off;

    location /api {
        api write=on;
    }
}
EOF

sudo nginx -t
sudo systemctl enable --now nginx
sudo systemctl reload nginx

curl https://agent.connect.nginx.com/nginx-agent/install | \
  sudo DATA_PLANE_KEY="$DATA_PLANE_KEY" sh -s -- -y

sudo systemctl enable --now nginx-agent
