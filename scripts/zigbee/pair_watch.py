import asyncio, os, json, aiohttp, time
async def main():
    async with aiohttp.ClientSession() as s:
        async with s.ws_connect('http://supervisor/core/websocket') as ws:
            await ws.receive_json(); await ws.send_json({'type':'auth','access_token':os.environ['SUPERVISOR_TOKEN']}); await ws.receive_json()
            for i,t in enumerate(['zigbee2mqtt_1/bridge/event','zigbee2mqtt_1/bridge/response/permit_join']):
                await ws.send_json({'id':10+i,'type':'mqtt/subscribe','topic':t}); await ws.receive_json()
            await ws.send_json({'id':20,'type':'call_service','domain':'mqtt','service':'publish','service_data':{'topic':'zigbee2mqtt_1/bridge/request/permit_join','payload':json.dumps({'time':254})}})
            end=time.time()+500
            renewed=False
            while time.time()<end:
                if not renewed and time.time()>end-260:
                    renewed=True
                    await ws.send_json({'id':21,'type':'call_service','domain':'mqtt','service':'publish','service_data':{'topic':'zigbee2mqtt_1/bridge/request/permit_join','payload':json.dumps({'time':254})}})
                try: m=await asyncio.wait_for(ws.receive_json(), timeout=min(10,end-time.time()))
                except asyncio.TimeoutError: continue
                if m.get('type')=='event':
                    print(time.strftime('%H:%M:%S'), m['event']['topic'].split('/')[-1], m['event']['payload'][:400], flush=True)
asyncio.run(main())
