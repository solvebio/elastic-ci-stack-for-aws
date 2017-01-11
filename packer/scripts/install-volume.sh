#!/bin/bash

set -eu -o pipefail

echo "Setting up /data mount point..."
mkdir /data
echo "/dev/xvdb   /data       ext4    defaults,nofail 0   2" >> /etc/fstab
