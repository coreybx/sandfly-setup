#!/usr/bin/env bash
# Sandfly Security LTD www.sandflysecurity.com
# Copyright (c) 2021 Sandfly Security LTD, All Rights Reserved.

if [ !$(which docker >/dev/null 2>&1 ) ]; then
    which podman >/dev/null 2>&1 || { echo "Unable to locate docker or podman binary; please install Docker or Podman."; exit 1; }
    CONTAINER_BINARY=podman
else
    CONTAINER_BINARY=docker
fi

# Make sure we run from the correct directory so relative paths work
cd "$( dirname "${BASH_SOURCE[0]}" )"

if [ ! -f ../setup/setup_data/config.server.json ]; then
    echo ""
    echo "********************************** ERROR **********************************"
    echo "*                                                                         *"
    echo "* Sandfly does not appear to be configured. Please use install.sh to      *"
    echo "* perform a new installation of Sandfly Server on this host.              *"
    echo "*                                                                         *"
    echo "* If this system is a node, not a server, use start_node.sh.              *"
    echo "*                                                                         *"
    echo "********************************** ERROR **********************************"
    echo ""
    exit 1
fi

# Determine if we need to use the sudo command to control Docker
SUDO=""
if [ $(id -u) -ne 0 ]; then
    $CONTAINER_BINARY version >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        SUDO="sudo"
    fi
fi

### Start Postgres if not already running
esresult=$($SUDO $CONTAINER_BINARY inspect --format="{{.State.Running}}" sandfly-postgres 2> /dev/null)
if [ "${esresult}z" != "truez" ]; then
    echo "*** Starting Postgres."
    $SUDO ./start_postgres.sh
    if [ $? -ne 0 ]; then
        echo "*** ERROR: Error starting Postgres container; cannot proceed."
        exit 2
    fi
else
    echo "*** Postgres container already running."
fi

### Start RabbitMQ if not already running
esresult=$($SUDO $CONTAINER_BINARY inspect --format="{{.State.Running}}" sandfly-rabbit 2> /dev/null)
if [ "${esresult}z" != "truez" ]; then
    echo "*** Starting RabbitMQ server."
    $SUDO ./start_rabbit.sh
    if [ $? -ne 0 ]; then
        echo "*** ERROR: Error starting RabbitMQ container; cannot proceed."
        exit 2
    fi
    echo "Waiting for RabbitMQ to configure and start. This will take about 45 seconds."
    # Wait a maximum of 3 minutes
    TIMER=180
    while true; do
        $SUDO $CONTAINER_BINARY logs sandfly-rabbit 2>&1 | grep "Server startup complete" > /dev/null
        if [ $? -eq 0 ]; then
            echo
            break
        fi
        TIMER=$(expr $TIMER - 5)
        if [ $TIMER -le 0 ]; then
            echo "*** ERROR: the sandfly-rabbit container took too long to configure and start."
            echo "*** Automatic startup could not complete."
            exit 2
        fi
        echo -n "."
        sleep 5
    done
else
    echo "*** RabbitMQ container already running."
fi

### Start sandfly-server if not already running
esresult=$($SUDO $CONTAINER_BINARY inspect --format="{{.State.Running}}" sandfly-server 2> /dev/null)
if [ "${esresult}z" != "truez" ]; then
    echo "*** Starting Sandfly Server."
    $SUDO ./start_server.sh
else
    echo "*** Sandfly Server container already running."
fi
