B=http://192.168.1.20
st() { docker exec app_core_configurator sh -c 'curl -s -m 5 -H "Authorization: Bearer $SUPERVISOR_TOKEN" http://supervisor/core/api/states/binary_sensor.zigbee2mqtt_bridge_connection_state' | python3 -c "import json,sys;print(json.load(sys.stdin)['state'])" 2>/dev/null; }
z2m_start() { docker inspect -f '{{.State.StartedAt}}' app_45df7312_zigbee2mqtt 2>/dev/null | cut -c12-19; }
echo "before: bridge=$(st) z2m_started=$(z2m_start)"
curl -s -m 5 "$B/api?action=8&cmd=3"; echo " <- reboot sent $(date +%T)"
seen_off=0
for i in $(seq 1 18); do
  sleep 30
  up=$(curl -s -m 3 "$B/api?action=1&param=root" | python3 -c "import json,sys;d=json.load(sys.stdin);print(str(d['uptime']//1000)+'s sock='+str(d['connectedSocketStatus']))" 2>/dev/null || echo down)
  s=$(st)
  echo "$(date +%T) coord=$up bridge=$s z2m_started=$(z2m_start)"
  [ "$s" != "on" ] && seen_off=1
  if [ $seen_off = 1 ] && [ "$s" = "on" ]; then echo "RECOVERED"; break; fi
done
echo "== z2m log tail"; docker logs --tail 8 app_45df7312_zigbee2mqtt 2>&1 | cut -c1-160
