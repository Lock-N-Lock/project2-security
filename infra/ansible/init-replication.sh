#!/bin/bash
set -e

# Allow replication connections from anywhere (trust for testing)
echo "host replication all 0.0.0.0/0 trust" >> "$PGDATA/pg_hba.conf"
