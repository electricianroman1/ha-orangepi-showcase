# usage: bash -s <slug> [<slug>...]
api() { docker exec app_core_configurator sh -c "curl -s -m 30 -X POST -H \"Authorization: Bearer \$SUPERVISOR_TOKEN\" -H 'Content-Type: application/json' -d '$2' http://supervisor/core/api$1" > /dev/null; }
st() { docker exec app_core_configurator sh -c "curl -s -m 10 -H \"Authorization: Bearer \$SUPERVISOR_TOKEN\" http://supervisor/core/api/states/$1" | python3 -c "import json,sys;d=json.load(sys.stdin);print(d['state'],d['last_reported'][11:19])" 2>/dev/null; }
info() { docker exec hassio_cli ha apps info "$1" --raw-json | python3 -c "import json,sys;d=json.load(sys.stdin)['data'];print(d['name']+' | '+d['version']+' -> '+str(d['version_latest'])+' | '+d['state'])"; }

zb_test() {
  echo "  bridge: $(st binary_sensor.zigbee2mqtt_bridge_connection_state)"
  before=$(st switch.rozetka)
  api /services/mqtt/publish '{"topic":"zigbee2mqtt_1/Ptichka/get","payload":"{\"state\":\"\"}"}'
  sleep 6
  echo "  rozetka before=[$before] after=[$(st switch.rozetka)]"
  docker logs --since 1m app_45df7312_zigbee2mqtt 2>&1 | sed -E 's/\x1b\[[0-9;]*m//g' | grep -iE "error|fail" | grep -v "sync time" | cut -c1-200 | tail -n 3
}

for slug in "$@"; do
  echo "== $(info $slug)  $(date +%T)"
  docker exec hassio_cli ha apps update "$slug" --backup 2>&1 | tail -n 2
  for i in $(seq 1 24); do sleep 5; s=$(docker exec hassio_cli ha apps info "$slug" --raw-json | python3 -c "import json,sys;print(json.load(sys.stdin)['data']['state'])"); [ "$s" = "started" ] && break; done
  sleep 10
  echo "   now: $(info $slug)"
  case "$slug" in *mosquitto*|*zigbee2mqtt*) sleep 20; zb_test ;; esac
  docker logs --since 2m "app_${slug}" 2>&1 | sed -E 's/\x1b\[[0-9;]*m//g' | grep -iE "error|fatal" | cut -c1-200 | tail -n 3
done
