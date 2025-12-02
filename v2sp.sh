#!/bin/bash
#
# v2sp management script - Simplified wrapper
# All functionality is now in the Go binary
#

# Just pass all arguments to the v2sp binary
if command -v /usr/local/v2sp/v2sp &> /dev/null; then
    exec /usr/local/v2sp/v2sp "$@"
elif command -v v2sp &> /dev/null; then
    exec v2sp "$@"
else
    echo "Error: v2sp not found"
    echo "Install with: curl -fsSL https://get.v2sp.io | bash"
    exit 1
fi
