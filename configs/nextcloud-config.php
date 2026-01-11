<?php
/**
 * Nextcloud Configuration File
 * Optimized for 60TB TrueNAS Storage
 * 
 * This file should be placed at: /var/www/html/config/config.php
 * Or mounted via Docker to config directory
 */

$CONFIG = array (

  // ===========================================
  // BASIC SETTINGS
  // ===========================================
  
  'instanceid' => 'GENERATE_ME',  // Auto-generated on install
  'passwordsalt' => 'GENERATE_ME',
  'secret' => 'GENERATE_ME',
  
  // Trusted domains - UPDATE THESE
  'trusted_domains' => array (
    0 => 'localhost',
    1 => 'cloud.yourdomain.com',
    2 => '192.168.1.10',
  ),
  
  // Data directory (NFS mount from TrueNAS)
  'datadirectory' => '/var/www/html/data',
  
  // Database configuration
  'dbtype' => 'pgsql',
  'dbname' => 'nextcloud',
  'dbhost' => 'postgres',
  'dbport' => '',
  'dbuser' => 'nextcloud',
  'dbpassword' => 'YOUR_DB_PASSWORD',
  'dbtableprefix' => 'oc_',
  
  // ===========================================
  // CACHE CONFIGURATION (Critical for 60TB)
  // ===========================================
  
  // Local cache (APCu)
  'memcache.local' => '\\OC\\Memcache\\APCu',
  
  // Distributed cache (Redis)
  'memcache.distributed' => '\\OC\\Memcache\\Redis',
  
  // Locking cache (Redis) - Important for file locking
  'memcache.locking' => '\\OC\\Memcache\\Redis',
  
  // Redis server configuration
  'redis' => array (
    'host' => 'redis',
    'port' => 6379,
    'password' => 'YOUR_REDIS_PASSWORD',
    'timeout' => 1.5,
    'read_timeout' => 1.5,
    'dbindex' => 0,
  ),
  
  // ===========================================
  // PERFORMANCE SETTINGS (60TB Optimization)
  // ===========================================
  
  // File locking (Required for NFS)
  'filelocking.enabled' => true,
  
  // Disable filesystem check on every request
  // Important for large storage - reduces I/O
  'filesystem_check_changes' => 0,
  
  // Preview settings
  'enable_previews' => true,
  'preview_max_x' => 2048,
  'preview_max_y' => 2048,
  'preview_max_filesize_image' => 50,
  'preview_max_memory' => 512,
  
  // Enabled preview providers
  'enabledPreviewProviders' => array (
    'OC\\Preview\\PNG',
    'OC\\Preview\\JPEG',
    'OC\\Preview\\GIF',
    'OC\\Preview\\BMP',
    'OC\\Preview\\XBitmap',
    'OC\\Preview\\MP3',
    'OC\\Preview\\TXT',
    'OC\\Preview\\MarkDown',
    'OC\\Preview\\OpenDocument',
    'OC\\Preview\\PDF',
    'OC\\Preview\\Movie',
    'OC\\Preview\\HEIC',
  ),
  
  // Chunked file upload (for large files)
  'upload_max_filesize' => '16G',
  'post_max_size' => '16G',
  
  // ===========================================
  // SECURITY SETTINGS
  // ===========================================
  
  // Force HTTPS
  'overwrite.cli.url' => 'https://cloud.yourdomain.com',
  'overwriteprotocol' => 'https',
  
  // Trusted proxies (if using reverse proxy)
  'trusted_proxies' => array (
    0 => '172.20.0.0/16',  // Docker network
    1 => '10.0.0.0/8',     // Private networks
    2 => '192.168.0.0/16', // Private networks
    3 => '172.16.0.0/12',  // Private networks
  ),
  
  // Forwarded for headers (for real IP detection behind proxy)
  'forwarded_for_headers' => array (
    0 => 'HTTP_X_FORWARDED_FOR',
    1 => 'HTTP_X_REAL_IP',
  ),
  
  // Brute force protection
  'auth.bruteforce.protection.enabled' => true,
  
  // Default phone region
  'default_phone_region' => 'TR',
  
  // Token auth enforced
  'token_auth_enforced' => false,
  
  // ===========================================
  // LOGGING
  // ===========================================
  
  'loglevel' => 2,  // 0=DEBUG, 1=INFO, 2=WARN, 3=ERROR
  'log_type' => 'file',
  'logfile' => '/var/www/html/data/nextcloud.log',
  'log_rotate_size' => 104857600,  // 100MB
  'logdateformat' => 'Y-m-d H:i:s',
  
  // ===========================================
  // MAINTENANCE
  // ===========================================
  
  // Maintenance window (for background jobs)
  'maintenance_window_start' => 1,  // 01:00 UTC
  
  // Background jobs
  'backgroundjobs_mode' => 'cron',
  
  // ===========================================
  // APPS & FEATURES
  // ===========================================
  
  // Default apps
  'defaultapp' => 'files',
  
  // App store
  'appstoreenabled' => true,
  
  // Skeleton directory (for new users)
  'skeletondirectory' => '',
  
  // Template directory
  'templatedirectory' => '',
  
  // Trash bin retention (days, 0 = auto)
  'trashbin_retention_obligation' => 'auto',
  
  // Version retention
  'versions_retention_obligation' => 'auto',
  
  // ===========================================
  // SHARING SETTINGS
  // ===========================================
  
  // Allow public links
  'sharing.enable_public_link' => true,
  
  // Enforce password on public links
  'sharing.enable_public_link_require_password' => false,
  
  // Default expire days for public links (0 = disabled)
  'sharing.public_link_expire_days' => 0,
  
  // ===========================================
  // EMAIL CONFIGURATION
  // ===========================================
  
  'mail_smtpmode' => 'smtp',
  'mail_smtpsecure' => 'tls',
  'mail_sendmailmode' => 'smtp',
  'mail_from_address' => 'nextcloud',
  'mail_domain' => 'yourdomain.com',
  'mail_smtphost' => 'smtp.gmail.com',
  'mail_smtpport' => '587',
  'mail_smtpauth' => 1,
  'mail_smtpname' => 'your-email@gmail.com',
  'mail_smtppassword' => 'your-app-password',
  
  // ===========================================
  // ADVANCED SETTINGS
  // ===========================================
  
  // Enable LDAP (if needed)
  // 'ldapIgnoreNamingRules' => false,
  // 'ldapProviderFactory' => '\\OCA\\User_LDAP\\LDAPProviderFactory',
  
  // Activity settings
  'activity_expire_days' => 365,
  
  // Session lifetime (seconds)
  'session_lifetime' => 86400,
  'session_keepalive' => true,
  
  // Auto logout on window close
  'auto_logout' => false,
  
  // Remember login
  'remember_login_cookie_lifetime' => 1296000,
  
  // Installed flag
  'installed' => true,
);
