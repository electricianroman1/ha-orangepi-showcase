import asyncio, os, json, aiohttp, time, sys
DUR=int(sys.argv[1])
async def main():
    async with aiohttp.ClientSession() as s:
        async with s.ws_connect('http://supervisor/core/websocket') as ws:
            await ws.receive_json(); await ws.send_json({'type':'auth','access_token':os.environ['SUPERVISOR_TOKEN']}); await ws.receive_json()
            await ws.send_json({'id':1,'type':'mqtt/subscribe','topic':'zigbee2mqtt_1/+'}); await ws.receive_json()
            await ws.send_json({'id':2,'type':'mqtt/subscribe','topic':'zigbee2mqtt_1/bridge/event'}); await ws.receive_json()
            print('listening', flush=True)
            end=time.time()+DUR
            while time.time()<end:
                try: m=await asyncio.wait_for(ws.receive_json(), timeout=end-time.time())
                except asyncio.TimeoutError: break
                if m.get('type')=='event':
                    t=m['event']['topic']; p=m['event']['payload']
                    if t.endswith('/bridge') : continue
                    print(time.strftime('%H:%M:%S'), t.split('/',1)[1], p[:160], flush=True)
asyncio.run(main())
