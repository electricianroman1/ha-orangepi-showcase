import asyncio, os, sys, json, aiohttp, time
TOPIC=sys.argv[1]; DUR=int(sys.argv[2])
async def main():
    async with aiohttp.ClientSession() as s:
        async with s.ws_connect('http://supervisor/core/websocket') as ws:
            await ws.receive_json(); await ws.send_json({'type':'auth','access_token':os.environ['SUPERVISOR_TOKEN']}); await ws.receive_json()
            await ws.send_json({'id':1,'type':'mqtt/subscribe','topic':TOPIC}); print('sub', (await ws.receive_json()).get('success'), flush=True)
            end=time.time()+DUR
            while time.time()<end:
                try: m=await asyncio.wait_for(ws.receive_json(), timeout=end-time.time())
                except asyncio.TimeoutError: break
                if m.get('type')=='event': e=m['event']; print(time.strftime('%H:%M:%S'), e['topic'], e['payload'][:200], flush=True)
asyncio.run(main())
