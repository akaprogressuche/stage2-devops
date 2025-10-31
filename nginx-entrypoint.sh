#!/bin/sh
set -e

# Remove symlinks if they exist
rm -f /var/log/nginx/access.log /var/log/nginx/error.log

# Create real log files with proper permissions
touch /var/log/nginx/access.log /var/log/nginx/error.log
chmod 666 /var/log/nginx/access.log /var/log/nginx/error.log

# Test nginx config
nginx -t

# Start nginx
exec nginx -g 'daemon off;'
EOF