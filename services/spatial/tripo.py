"""Tripo v3 adapter. Paid generation is invoked only by an explicit backend job."""
import asyncio
from aiohttp import ClientSession,ClientTimeout
class Tripo:
    def __init__(self,key,model='v3.1-20260211'):self.key=key;self.model=model
    async def __call__(self,data):
        async with ClientSession(headers={'Authorization':'Bearer '+self.key},timeout=ClientTimeout(total=30)) as http:
            async with http.post('https://openapi.tripo3d.ai/v3/generation/text-to-model',json={'prompt':data['prompt'],'model':self.model,'texture':True,'pbr':True},allow_redirects=False) as response:
                result=await response.json()
                if response.status!=200 or result.get('code')!=0:raise ValueError('Text-to-3D provider rejected generation')
                task=result['data']['task_id']
            # Provider task IDs are path components, never URLs.
            if not isinstance(task,str) or not task.replace('-','').replace('_','').isalnum():raise ValueError('Invalid provider task identifier')
            for _ in range(150):
                await asyncio.sleep(2)
                async with http.get('https://openapi.tripo3d.ai/v3/tasks/'+task,allow_redirects=False) as response:
                    result=await response.json()
                    if response.status!=200 or result.get('code')!=0:raise ValueError('Unable to query generation')
                    state=result['data']
                if state['status']=='success':return state['output']['model_url']
                if state['status'] in {'failed','cancelled','banned'}:raise ValueError('Generation did not complete')
        raise TimeoutError('Text-to-3D generation exceeded five minutes')
