#!/usr/bin/env bash

set -e

. ~/.nix-profile/etc/profile.d/nix.sh
dapp --use solc:0.8.17 --verbose --extract build
