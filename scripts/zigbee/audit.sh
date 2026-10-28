H=/usr/share/hassio/homeassistant
get() { docker exec app_core_configurator sh -c "curl -s -m 20 -H \"Authorization: Bearer \$SUPERVISOR_TOKEN\" http://supervisor/core/api$1"; }
get /states > /tmp/st.json
echo "== versions / updates"
python3 - <<'P'
import json
S=json.load(open('/tmp/st.json'))
for s in S:
    if s['entity_id'].startswith('update.') and s['state']=='on':
        a=s['attributes']; print(' UPDATE', a.get('friendly_name'), a.get('installed_version'),'->',a.get('latest_version'))
P
echo "== integrations not loaded"
python3 - <<'P'
import json
d=json.load(open('/usr/share/hassio/homeassistant/.storage/core.config_entries'))['data']['entries']
for e in d:
    if e.get('disabled_by'): print(' disabled:', e['domain'], e['title'])
P
docker logs --since 2h homeassistant 2>&1 | grep -E "Setup failed|Error setting up|Config entry .* not ready|retrying" | sed -E 's/^.{0,24}//' | cut -c1-200 | sort | uniq -c | sort -rn | head -n 10
echo "== repairs"
python3 -c "
import json
d=json.load(open('$H/.storage/repairs.issue_registry'))['data']['issues']
for i in d:
  if not i.get('dismissed_version') and i.get('is_persistent',True) is not None: print(' ',i.get('domain'),i.get('issue_id'))
" 2>&1 | head -n 20
echo "== HA log errors/warnings (2h) by source"
docker logs --since 2h homeassistant 2>&1 | grep -E " (ERROR|WARNING) " | sed -E 's/.* (ERROR|WARNING) \([^)]*\) \[([^]]*)\] (.{0,110}).*/\1 [\2] \3/' | sort | uniq -c | sort -rn | head -n 15
echo "== unavailable entities by integration"
python3 - <<'P'
import json,collections
S={s['entity_id']:s for s in json.load(open('/tmp/st.json'))}
reg=json.load(open('/usr/share/hassio/homeassistant/.storage/core.entity_registry'))['data']['entities']
dev={d['id']:d for d in json.load(open('/usr/share/hassio/homeassistant/.storage/core.device_registry'))['data']['devices']}
c=collections.defaultdict(set)
for e in reg:
    s=S.get(e['entity_id'])
    if s and s['state']=='unavailable' and not e.get('disabled_by'):
        d=dev.get(e.get('device_id'))
        c[e['platform']].add((d.get('name_by_user') or d.get('name')) if d else e['entity_id'])
for p,v in sorted(c.items(),key=lambda x:-len(x[1])): print(f' {p}: {len(v)} ->', ', '.join(sorted(map(str,v)))[:300])
P
echo "== batteries <=25%"
python3 - <<'P'
import json
for s in json.load(open('/tmp/st.json')):
    a=s['attributes']
    if a.get('device_class')=='battery' and s['entity_id'].startswith('sensor.'):
        try:
            if float(s['state'])<=25: print(' ',a.get('friendly_name'),s['state'],'%')
        except: pass
P
echo "== zigbee LQI <60 and stale devices (z2m state.json / database)"
python3 - <<'P'
import json,time
db=[json.loads(l) for l in open('/usr/share/hassio/homeassistant/zigbee2mqtt/database.db') if l.strip()]
cfg=open('/usr/share/hassio/homeassistant/zigbee2mqtt/configuration.yaml',encoding='utf-8').read()
st=json.load(open('/usr/share/hassio/homeassistant/zigbee2mqtt/state.json'))
now=time.time()*1000
import re
names=dict(re.findall(r"'(0x[0-9a-f]{16})':\s*\n\s*friendly_name:\s*(.+)",cfg))
for d in db:
    if d.get('type')=='Coordinator': continue
    ieee=d.get('ieeeAddr'); n=names.get(ieee,ieee).strip().strip("'")
    ls=d.get('lastSeen'); age=(now-ls)/3600000 if ls else None
    lqi=st.get(ieee,{}).get('linkquality')
    flag=[]
    if age is None or age>24: flag.append('last_seen=%s' % ('never' if age is None else f'{age:.0f}h ago'))
    if lqi is not None and lqi<60: flag.append(f'lqi={lqi}')
    if flag: print(f"  {n} ({d.get('type')}, {d.get('modelId')}): {', '.join(flag)}")
print('  total devices:',sum(1 for d in db if d.get('type')!='Coordinator'), '| routers:',sum(1 for d in db if d.get('type')=='Router'))
P
echo "== automations: state + last_triggered, missing entities"
python3 - <<'P'
import json,re
S={s['entity_id']:s for s in json.load(open('/tmp/st.json'))}
for e,s in S.items():
    if e.startswith('automation.'):
        print(f"  {s['state']:4} {str(s['attributes'].get('last_triggered'))[:10]:10} {s['attributes'].get('friendly_name')}")
y=open('/usr/share/hassio/homeassistant/automations.yaml',encoding='utf-8').read()
ids=set(re.findall(r'\b((?:light|switch|sensor|binary_sensor|input_boolean|cover|fan|climate|media_player|scene|script)\.[a-z0-9_]+)',y))
miss=[i for i in ids if i not in S]
print('  referenced but missing:',miss)
P
echo "== system"
uptime; df -h / | tail -1; free -h | sed -n 2p; cat /sys/class/thermal/thermal_zone0/temp
docker exec hassio_cli ha resolution info --raw-json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)['data']
print(' unsupported:',d.get('unsupported'),'| unhealthy:',d.get('unhealthy'))
print(' issues:',[(i['type'],i['context'],i.get('reference')) for i in d.get('issues',[])])
print(' suggestions:',[(i['type'],i['context'],i.get('reference')) for i in d.get('suggestions',[])])"
echo "== ports listening on all interfaces"; ss -tlnp 2>/dev/null | awk 'NR>1 && ($4 ~ /^0.0.0.0|^\[::\]|^\*/){print $4}' | sort -u | tr "\n" " "; echo
echo "== ssh config"; grep -E "^(PermitRootLogin|PasswordAuthentication)" /etc/ssh/sshd_config /etc/ssh/sshd_config.d/* 2>/dev/null
echo "== apt updates"; apt list --upgradable 2>/dev/null | grep -c upgradable
rm -f /tmp/st.json
