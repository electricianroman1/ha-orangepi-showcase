# usage: bash -s <version>
V=$1
cfg() { docker exec app_core_configurator sh -c "curl -s -m 5 -H \"Authorization: Bearer \$SUPERVISOR_TOKEN\" http://supervisor/core/api/config" 2>/dev/null; }
echo "== core update to $V $(date +%T)"
docker exec hassio_cli ha core update --version "$V" 2>&1 | tail -n 2
until cfg | grep -q '"state": *"RUNNING"'; do sleep 10; done
echo "HA RUNNING $(date +%T): $(cfg | python3 -c "import json,sys;print(json.load(sys.stdin)['version'])")"
sleep 30
echo "== integrations not loaded (excluding known-offline)"
docker exec app_core_configurator sh -c "curl -s -m 10 -H \"Authorization: Bearer \$SUPERVISOR_TOKEN\" http://supervisor/core/api/config/config_entries/entry" | python3 -c "
import json,sys
known={'xiaomi_miio','homekit_controller','zha','upnp','androidtv_remote','keenetic_ndms2','telegram_bot','xiaomi_gateway3'}
for e in json.load(sys.stdin):
  if e['state']!='loaded' and e['domain'] not in known: print('  ',e['domain'],e['title'],e['state'],e.get('reason'))
print('  done')"
docker logs --since 10m homeassistant 2>&1 | sed -E 's/\x1b\[[0-9;]*m//g' | grep -iE "Setup failed|Error setting up entry|Unable to install|ModuleNotFound|ImportError" | cut -c1-200 | sort -u | head -n 8
