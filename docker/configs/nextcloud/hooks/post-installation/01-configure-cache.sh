#!/bin/sh
# ===========================================
# Post-Installation Cache Configuration
# ===========================================
# Nextcloud kurulumundan sonra Redis memcache ayarlarını otomatik ekler.

set -e

echo "Configuring Redis memcache settings..."

# Wait for Nextcloud to be fully installed
sleep 5

# Configure Redis memcache via occ commands
php /var/www/html/occ config:system:set redis host --value="${REDIS_HOST:-redis}"
php /var/www/html/occ config:system:set redis port --value="${REDIS_HOST_PORT:-6379}" --type=integer

if [ -n "$REDIS_HOST_PASSWORD" ]; then
    php /var/www/html/occ config:system:set redis password --value="$REDIS_HOST_PASSWORD"
fi

# Set memcache configuration
php /var/www/html/occ config:system:set memcache.local --value="\\OC\\Memcache\\APCu"
php /var/www/html/occ config:system:set memcache.distributed --value="\\OC\\Memcache\\Redis"
php /var/www/html/occ config:system:set memcache.locking --value="\\OC\\Memcache\\Redis"

# Set default phone region if specified
if [ -n "$DEFAULT_PHONE_REGION" ]; then
    php /var/www/html/occ config:system:set default_phone_region --value="$DEFAULT_PHONE_REGION"
fi

# Set maintenance window start (3 AM UTC)
php /var/www/html/occ config:system:set maintenance_window_start --value="3" --type=integer

echo "Post-installation configuration completed."
