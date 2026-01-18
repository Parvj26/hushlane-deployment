#!/bin/bash
set -e

echo "🔄 HushLane Manual Update Script"
echo "================================="

INSTALL_DIR="/opt/hushlane"
cd $INSTALL_DIR

# Check if installation exists
if [ ! -f "docker-compose.yml" ]; then
    echo "Error: HushLane installation not found in $INSTALL_DIR"
    exit 1
fi

# Get current version
echo "📊 Checking current version..."
CURRENT_VERSION=$(docker-compose exec -T hushlane python -c "from app.config import settings; print(settings.APP_VERSION)" 2>/dev/null || echo "unknown")
echo "Current version: $CURRENT_VERSION"

# Create backup before update
echo ""
echo "💾 Creating pre-update backup..."
BACKUP_FILE="backups/pre-update-$(date +%Y%m%d-%H%M%S).tar.gz"
tar -czf $BACKUP_FILE data/ media/ .env 2>/dev/null || echo "Warning: Backup creation failed, continuing anyway..."

if [ -f "$BACKUP_FILE" ]; then
    echo "✅ Backup created: $BACKUP_FILE"
else
    echo "⚠️ Warning: Could not create backup file"
    read -p "Continue without backup? (y/n): " CONTINUE
    if [ "$CONTINUE" != "y" ]; then
        echo "Update cancelled"
        exit 1
    fi
fi

# Pull latest images
echo ""
echo "📥 Pulling latest version..."
docker-compose pull

# Stop and restart services
echo ""
echo "🔄 Restarting services..."
docker-compose down
docker-compose up -d

# Wait for health check
echo ""
echo "⏳ Waiting for services to start..."
sleep 15

# Verify health
MAX_RETRIES=6
RETRY_COUNT=0
HEALTH_OK=false

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -sf http://localhost:8000/health > /dev/null; then
        HEALTH_OK=true
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo "Health check attempt $RETRY_COUNT/$MAX_RETRIES..."
    sleep 5
done

if [ "$HEALTH_OK" = true ]; then
    NEW_VERSION=$(docker-compose exec -T hushlane python -c "from app.config import settings; print(settings.APP_VERSION)" 2>/dev/null || echo "unknown")
    echo ""
    echo "✅ Update Complete!"
    echo "   Previous version: $CURRENT_VERSION"
    echo "   New version: $NEW_VERSION"
    echo ""
    echo "📖 View logs: docker-compose logs -f"
else
    echo ""
    echo "❌ Update failed! Health check not passing."
    echo ""
    echo "📖 Check logs: docker-compose logs -f"
    echo ""
    echo "🔄 To rollback, run:"
    echo "   docker-compose down"
    echo "   tar -xzf $BACKUP_FILE"
    echo "   docker-compose up -d"
    exit 1
fi
