#!/bin/bash
set -eu -o pipefail

echo "Instaling gcc..."
sudo yum install -y gcc

echo "Instaling virtualenv (python 2.7) ..."
sudo pip install virtualenv