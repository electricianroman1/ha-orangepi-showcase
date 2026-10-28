B=http://192.168.1.20
URL=https://github.com/xyzroe/XZG/releases/download/20240914/XZG_20240914.ota.bin
st() { docker exec app_core_configurator sh -c 'curl -s -m 5 -H "Authorization: Bearer $SUPERVISOR_TOKEN" http://supervisor/core/api/states/binary_sensor.zigbee2mqtt_bridge_connection_state' | python3 -c "import json,sys;print(json.load(sys.stdin)['state'])" 2>/dev/null; }
info() { curl -s -m 3 "$B/api?action=1&param=root" | python3 -c "import json,sys;d=json.load(sys.stdin);print('ver='+d['VERSION']+' up='+str(d['uptime']//1000)+'s sock='+str(d['connectedSocketStatus']))" 2>/dev/null || echo "no-answer"; }
echo "before: $(info) bridge=$(st)"
curl -s -m 10 "$B/api?action=8&cmd=9&url=$URL"; echo " <- update started $(date +%T)"
for i in $(seq 1 30); do
  sleep 15
  x=$(info); s=$(st)
  echo "$(date +%T) $x bridge=$s"
  case "$x" in ver=20240914*) [ "$s" = "on" ] && { echo "DONE"; break; } ;; esac
done
echo "== z2m"; docker inspect -f 'started={{.State.StartedAt}} running={{.State.Running}}' app_45df7312_zigbee2mqtt; docker logs --since 10m app_45df7312_zigbee2mqtt 2>&1 | grep -iE "error|disconnect|started|Coordinator" | cut -c1-160 | tail -n 8
