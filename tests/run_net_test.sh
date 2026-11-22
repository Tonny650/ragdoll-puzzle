#!/usr/bin/env bash
# Lanza la prueba de red: un anfitrion y un cliente headless en este PC.
# Uso: tests/run_net_test.sh [ruta_godot] [args extra, p. ej. --lag=150 --loss=0.05]
GODOT="${1:-godot}"
shift || true
cd "$(dirname "$0")/.." || exit 1
"$GODOT" --headless --path . res://tests/test_net.tscn -- --role=host "$@" > net_host.log 2>&1 &
HOST=$!
"$GODOT" --headless --path . res://tests/test_net.tscn -- --role=client "$@" > net_client.log 2>&1
wait $HOST
grep -hE "ASSERT|SCRIPT ERROR|^ERROR" net_host.log net_client.log
rm -f net_host.log net_client.log
