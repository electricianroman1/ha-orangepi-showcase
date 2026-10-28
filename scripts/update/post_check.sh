get() { docker exec app_core_configurator sh -c "curl -s -m 20 -H \"Authorization: Bearer \$SUPERVISOR_TOKEN\" http://supervisor/core/api$1"; }
api() { docker exec app_core_configurator sh -c "curl -s -m 30 -X POST -H \"Authorization: Bearer \$SUPERVISOR_TOKEN\" -H 'Content-Type: application/json' -d '$2' http://supervisor/core/api$1" > /dev/null; }
T=$(date -u -d "-30 min" +%Y-%m-%dT%H:%M:%S)
echo "== switches/lights that went ON in last 30 min (logbook)"
get "/logbook/${T}Z" | python3 -c "
import json,sys
L=json.load(sys.stdin)
on=[e for e in L if (e.get('entity_id') or '').split('.')[0] in ('switch','light','climate','fan','cover') and e.get('state') in ('on','heat','open')]
for e in on: print('  ',e['when'][11:19],'UTC',e['entity_id'],e.get('name'),'->',e.get('state'),'| by:',e.get('context_domain'),e.get('context_service'),e.get('context_event_type'),e.get('context_entity_id'))
print('  total ON events:',len(on))
"
echo "== current ON switches/lights"
get /states | python3 -c "
import json,sys
S=json.load(sys.stdin)
print('  ', [(s['entity_id'],s['last_changed'][11:19]) for s in S if s['entity_id'].split('.')[0] in ('switch','light') and s['state']=='on' and not any(x in s['entity_id'] for x in ('child_lock','do_not_disturb','permit_join','_enable','detection','auto_lock','away_mode'))])
"
echo "== integrations failed to load"
docker logs --since 10m homeassistant 2>&1 | sed -E 's/\x1b\[[0-9;]*m//g' | grep -iE "Setup failed|Error setting up|Unable to install|requirements|ImportError|ModuleNotFound" | cut -c1-220 | sort -u | head -n 10
python3 - <<'P'
import json
E=json.load(open('/usr/share/hassio/homeassistant/.storage/core.config_entries'))['data']['entries']
P
echo "== yandex / cloud"
docker logs --since 10m homeassistant 2>&1 | sed -E 's/\x1b\[[0-9;]*m//g' | grep -i yandex | grep -v 503 | cut -c1-200 | tail -n 3
echo "cloud conn: $(awk 'NR>1 && $4=="01" && $3 ~ /CA5AFA33:01BB/' /proc/net/tcp | wc -l)"
echo "== zigbee test"
echo "  bridge: $(get /states/binary_sensor.zigbee2mqtt_bridge_connection_state | python3 -c "import json,sys;print(json.load(sys.stdin)['state'])")"
api /services/mqtt/publish '{"topic":"zigbee2mqtt_1/Ptichka/get","payload":"{\"state\":\"\"}"}'
sleep 8
docker logs --since 20s app_45df7312_zigbee2mqtt 2>&1 | sed -E 's/\x1b\[[0-9;]*m//g' | grep -iE "error|fail" | grep -v "sync time" | cut -c1-200 | tail -n 3
echo "  (no lines above = OK)"
echo "== automations"
get /states | python3 -c "
import json,sys
print('  ', {s['attributes'].get('friendly_name'):s['state'] for s in json.load(sys.stdin) if s['entity_id'].startswith('automation.')})"
