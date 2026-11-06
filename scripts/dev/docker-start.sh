#!/bin/sh
set -eu

# Keep Phoenix and Tidewave on loopback; Docker reaches this forwarding port.
socat TCP-LISTEN:4001,fork,reuseaddr TCP:127.0.0.1:4000 &
mix setup
exec mix phx.server
