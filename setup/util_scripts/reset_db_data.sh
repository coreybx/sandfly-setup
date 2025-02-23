#!/usr/bin/env bash
# Sandfly Security LTD www.sandflysecurity.com
# Copyright (c) 2016-2022 Sandfly Security LTD, All Rights Reserved.

# This will delete all the results, errors, and audit log data from the
# Sandfly server. This is useful if the system got flooded with alarms or
# other data and you want to quickly get rid of all of it and start fresh. All
# other config data will remain untouched.

# Make sure we run from the correct directory so relative paths work
cd "$( dirname "${BASH_SOURCE[0]}" )"

SETUP_DATA=../setup_data
VERSION=${SANDFLY_VERSION:-$(cat ../../VERSION)}
IMAGE_BASE=${SANDFLY_IMAGE_BASE:-quay.io/sandfly}

# Populate env variables.
CONFIG_JSON=$(cat $SETUP_DATA/config.server.json)
export CONFIG_JSON

docker network create sandfly-net 2>/dev/null
docker rm sandfly-server-mgmt

docker run --name sandfly-server-mgmt \
--network sandfly-net \
-e CONFIG_JSON \
-it $IMAGE_BASE/sandfly-server${IMAGE_SUFFIX}:"$VERSION" /opt/sandfly/utils/init_data_db.sh



