#!/bin/bash

set -eu -o pipefail

echo "Mounting volume do /data..."
sudo mkdir /data
sudo mount /dev/sdb /data
