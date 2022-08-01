#!/bin/bash

# Sandfly Security LTD www.sandflysecurity.com
# Copyright (c) 2021-2022 Sandfly Security LTD, All Rights Reserved.

if [ !$(which docker >/dev/null 2>&1 ) ]; then
    which podman >/dev/null 2>&1 || { echo "Unable to locate docker or podman binary; please install Docker or Podman."; exit 1; }
    CONTAINER_BINARY=podman
else
    CONTAINER_BINARY=docker
fi

# Make sure we run from the correct directory so relative paths work
cd "$( dirname "${BASH_SOURCE[0]}" )"

# After the first time Postgres starts, the admin password will be set in the
# database in the Docker volume we use, and setting the password through the
# $CONTAINER_BINARY run command will have no effect (e.g. it doesn't try to change it if
# a database already exists). If this is an initial install, the password we
# want to use should be in setup_data courtesy of the install.sh script.
POSTGRES_ADMIN_PASSWORD="unknown"
if [ -f ../setup/setup_data/postgres.admin.password.txt ]; then
    POSTGRES_ADMIN_PASSWORD=$(cat ../setup/setup_data/postgres.admin.password.txt)
fi

#############################################################################
### POSTGRES TUNING CALCULATIONS ############################################
### Roughly following 'pgtune' project calculations #########################
#############################################################################

cpu_count=$(grep -c '^processor' /proc/cpuinfo)
ram_total=$(free -k | grep Mem | awk '{print $2}')
max_connections=35

# We will calculate based on 70% of system RAM for postgres, leaving
# 30% for Sandfly, Rabbit, etc.
ram_postgres=$(( $ram_total / 10 * 7 ))

shared_buffers=$(( $ram_postgres / 4 ))
effective_cache_size=$(( $ram_postgres / 4 * 3 ))
maintenance_work_mem=$(( $ram_postgres / 16 ))
wal_buffer=$(( $shared_buffers * 3 / 100)) # 3% of shared_buffers
if [[ $wal_buffer -gt 14336 ]]; then
    # If at or above 14MB, set to 16MB
    wal_buffer=16384
fi
if [[ $wal_buffer -lt 32 ]]; then
    # Minimum 32kB
    wal_buffer=32
fi
if [[ $maintenance_work_mem -gt 2097152 ]]; then
    # 2GB cap for maintenance_work_mem
    maintenance_work_mem=2097152
fi
parallel_workers=$(( $cpu_count / 2))
if [[ $parallel_workers -lt 1 ]]; then
    parallel_workers=1
fi
if [[ $parallel_workers -gt 4 ]]; then
    # cap parallel_workers (per task) at 4
    parallel_workers=4
fi
work_mem=$(( ($ram_postgres - $shared_buffers) / ($max_connections * 3) / $parallel_workers ))
if [[ $work_mem -lt 64 ]]; then
    # minimum of 64kB for work_mem
    work_mem=64
fi

echo ""
echo "Based on $cpu_count CPUs and ${ram_total}kB total RAM, we will start"
echo "Postgres with the following settings:"
echo ""
echo "max_connections                  = $max_connections"
echo "shared_buffers                   = ${shared_buffers}kB"
echo "effective_cache_size             = ${effective_cache_size}kB"
echo "maintenance_work_mem             = ${maintenance_work_mem}kB"
echo "checkpoint_completion_target     = 0.9"
echo "wal_buffers                      = ${wal_buffer}kB"
echo "default_statistics_target        = 100"
echo "random_page_cost                 = 1.1 [SSD or SAN storage]"
echo "effective_io_concurrency         = 200 [SSD or SAN storage]"
echo "work_mem                         = ${work_mem}kB"
echo "min_wal_size                     = 2GB"
echo "max_wal_size                     = 8GB"
echo "max_worker_processes             = $cpu_count"
echo "max_parallel_workers             = $cpu_count"
echo "max_parallel_workers_per_gather  = $parallel_workers"
echo "max_parallel_maintenance_workers = $parallel_workers"
echo ""

#############################################################################
### END OF POSTGRES TUNING CALCULATIONS #####################################
#############################################################################

# If the volume already exists (e.g. this isn't the first startup during
# initial installation), print a warning if the volume is on a disk that is
# more than 85% full.
$CONTAINER_BINARY inspect sandfly-pg14-db-vol >/dev/null 2>/dev/null && \
diskuse=$(df --output=pcent \
    $($CONTAINER_BINARY inspect sandfly-pg14-db-vol -f '{{json .Mountpoint}}' | \
    tr -d \" ) | grep -v "Use%"|tr -d " %") && \
if [[ $diskuse -gt 85 ]]; then
    echo ""
    echo "********************************* WARNING ***********************************"
    echo "*                                                                           *"
    echo "* The disk holding the Sandfly Postgres Docker volume, sandfly-pg14-db-vol, *"
    echo "* is using more than 85% of available space. If the disk fills during       *"
    echo "* Sandfly operation, it will become impossible to log in, delete results,   *"
    echo "* etc.                                                                      *"
    echo "*                                                                           *"
    echo "* Please free up disk space, or increase the size of the disk, before       *"
    echo "* starting Sandfly.                                                         *"
    echo "*                                                                           *"
    echo "* If you wish to continue anyway with low disk space, enter YES at the      *"
    echo "* prompt.                                                                   *"
    echo "********************************* WARNING ***********************************"
    echo ""
    echo "The disk is currently ${diskuse}% full."
    echo "Do you wish to start the database despite having low free disk space?"
    read -p "Type YES if you're sure. [NO]: " RESPONSE
    if [ "$RESPONSE" != "YES" ]; then
        echo "Halting database start."
        exit 1
    fi
fi

$CONTAINER_BINARY network create sandfly-net 2>/dev/null
$CONTAINER_BINARY rm sandfly-postgres 2>/dev/null

$CONTAINER_BINARY run \
$( if [ $CONTAINER_BINARY == "podman" ]; then echo "-v sandfly-pg14-db-vol:/var/lib/postgresql/data "; else echo "--mount source=sandfly-pg14-db-vol,target=/var/lib/postgresql/data "; fi) \
-d \
-e POSTGRES_PASSWORD="$POSTGRES_ADMIN_PASSWORD" \
-e PGDATA=/var/lib/postgresql/data \
--shm-size=${ram_total}k \
--restart=always \
--security-opt="no-new-privileges$( if [ $CONTAINER_BINARY == "podman" ]; then echo ""; else echo ":true"; fi)" \
--network sandfly-net \
--name sandfly-postgres \
-t \
postgres:14.4 \
-c shared_buffers=${shared_buffers}kB \
-c effective_cache_size=${effective_cache_size}kB \
-c maintenance_work_mem=${maintenance_work_mem}kB \
-c checkpoint_completion_target=0.9 \
-c wal_buffers=${wal_buffer}kB \
-c default_statistics_target=100 \
-c random_page_cost=1.1 \
-c effective_io_concurrency=200 \
-c work_mem=${work_mem}kB \
-c min_wal_size=2GB \
-c max_wal_size=8GB \
-c max_worker_processes=$cpu_count \
-c max_parallel_workers_per_gather=$parallel_workers \
-c max_parallel_workers=$cpu_count \
-c max_parallel_maintenance_workers=$parallel_workers

exit $?
