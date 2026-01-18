#!/bin/bash
set -e

echo "🚀 HushLane Installation Script"
echo "================================"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
   echo "Please run as root (sudo ./install.sh)"
   exit 1
fi

# Prompt for customer ID
read -p "Enter Customer ID (e.g., 'acme' for acme.hushlane.app): " CUSTOMER_ID
if [ -z "$CUSTOMER_ID" ]; then
    echo "Error: Customer ID cannot be empty"
    exit 1
fi

# Prompt for license key
echo ""
read -p "Enter License Key (press Enter to skip for testing): " LICENSE_KEY
if [ -z "$LICENSE_KEY" ]; then
    LICENSE_KEY="test-license-key"
    echo "⚠️  No license key provided - using test mode"
    echo "   License validation will be disabled"
fi

APP_URL="https://${CUSTOMER_ID}.hushlane.app"

echo ""
echo "📋 Configuration:"
echo "   Customer ID: $CUSTOMER_ID"
echo "   App URL: $APP_URL"
echo "   Admin URL: $APP_URL/admin"
echo ""
read -p "Continue with installation? (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ]; then
    echo "Installation cancelled"
    exit 0
fi

# Check system requirements
echo ""
echo "✅ Checking system requirements..."
if ! command -v docker &> /dev/null; then
    echo "Docker not found. Installing..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    systemctl enable docker
    systemctl start docker
    rm get-docker.sh
fi

if ! command -v docker-compose &> /dev/null; then
    echo "Docker Compose not found. Installing..."
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
fi

# Create installation directory
INSTALL_DIR="/opt/hushlane"
echo "📁 Creating installation directory: $INSTALL_DIR"
mkdir -p $INSTALL_DIR
cd $INSTALL_DIR

# Download docker-compose.yml and .env.template
echo "📦 Downloading application files..."
curl -sSL https://raw.githubusercontent.com/Parvj26/hushlane-deployment/main/docker-compose.yml -o docker-compose.yml
curl -sSL https://raw.githubusercontent.com/Parvj26/hushlane-deployment/main/.env.template -o .env

# Generate SECRET_KEY
SECRET_KEY=$(openssl rand -hex 32)

# Configure .env file
echo "⚙️ Configuring environment..."
sed -i "s/CUSTOMER_ID=.*/CUSTOMER_ID=$CUSTOMER_ID/" .env
sed -i "s|APP_URL=.*|APP_URL=$APP_URL|" .env
sed -i "s/SECRET_KEY=.*/SECRET_KEY=$SECRET_KEY/" .env
sed -i "s|CORS_ORIGINS=.*|CORS_ORIGINS=$APP_URL,https://www.$CUSTOMER_ID.hushlane.app|" .env
sed -i "s/LICENSE_KEY=.*/LICENSE_KEY=$LICENSE_KEY/" .env

# Create data directories
mkdir -p data media backups

# Setup Cloudflare Tunnel
echo ""
echo "🌐 Cloudflare Tunnel Setup"
echo "=========================="
echo "Please follow these steps:"
echo ""
echo "1. Go to: https://one.dash.cloudflare.com/"
echo "2. Navigate to: Networks > Tunnels"
echo "3. Create a new tunnel (or use existing)"
echo "4. Add public hostname:"
echo "   - Subdomain: $CUSTOMER_ID"
echo "   - Domain: hushlane.app"
echo "   - Service: http://hushlane_app:8000"
echo "5. Copy the tunnel token"
echo ""
read -p "Paste your Cloudflare Tunnel Token: " TUNNEL_TOKEN

if [ -z "$TUNNEL_TOKEN" ]; then
    echo "Error: Tunnel token cannot be empty"
    exit 1
fi

sed -i "s/CLOUDFLARE_TUNNEL_TOKEN=.*/CLOUDFLARE_TUNNEL_TOKEN=$TUNNEL_TOKEN/" .env

# Pull Docker images
echo ""
echo "📥 Pulling Docker images..."
docker-compose pull

# Start services
echo "🚀 Starting HushLane..."
docker-compose up -d

# Wait for services to be healthy
echo "⏳ Waiting for services to start..."
sleep 10

# Check health
if curl -sf http://localhost:8000/health > /dev/null; then
    echo "✅ HushLane is running!"
else
    echo "⚠️ Warning: Health check failed. Check logs with: docker-compose logs"
fi

# Extract admin invite code
echo ""
echo "🔑 Admin Setup"
echo "=============="
echo "Your HushLane instance is ready!"
echo ""
echo "📍 Access URL: $APP_URL"
echo "🔐 Admin Panel: $APP_URL/admin"
echo ""
echo "First user to register will become admin."
echo "Create invite code from admin panel after first login."
echo ""

# Create systemd service for auto-start
echo "🔧 Setting up auto-start service..."
cat > /etc/systemd/system/hushlane.service <<EOF
[Unit]
Description=HushLane Messaging App
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/local/bin/docker-compose up -d
ExecStop=/usr/local/bin/docker-compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable hushlane.service

echo ""
echo "✅ Installation Complete!"
echo ""
echo "📚 Next Steps:"
echo "   1. Visit: $APP_URL"
echo "   2. Register first user (becomes admin)"
echo "   3. Generate invite codes from admin panel"
echo ""
echo "📖 Useful Commands:"
echo "   - View logs: cd $INSTALL_DIR && docker-compose logs -f"
echo "   - Restart: cd $INSTALL_DIR && docker-compose restart"
echo "   - Stop: cd $INSTALL_DIR && docker-compose down"
echo "   - Update: cd $INSTALL_DIR && ./update.sh"
echo ""
