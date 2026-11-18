"""Trusted ComfyUI nodes: job-scoped MCP calls; no shell, graphs or model loads."""
import asyncio
import json
import os
import re
import time
import urllib.parse
import urllib.request

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        raise ValueError('MCP redirects are not permitted')

class Job:
    def __init__(self, context):
        data=json.loads(context)
        url=urllib.parse.urlsplit(data['url'])
        origin=os.environ.get('LIGHTEK_STUDIO_ORIGIN','').rstrip('/')
        if not origin or f'{url.scheme}://{url.netloc}'!=origin or url.username or url.password or url.query or url.fragment or not re.fullmatch(r'/api/lightek/pwa/studio/workflows/[1-9]\d*/mcp',url.path):
            raise ValueError('Unapproved Studio MCP address')
        if url.scheme!='https' and not (url.scheme=='http' and url.hostname in ('127.0.0.1','localhost')):
            raise ValueError('Studio MCP requires HTTPS')
        if not isinstance(data.get('token'),str) or len(data['token'])>4096:
            raise ValueError('Invalid job credential')
        self.url,self.token=data['url'],data['token']
        self.opener=urllib.request.build_opener(urllib.request.ProxyHandler({}),NoRedirect())
    def request(self, method, params, notification=False):
        payload={'jsonrpc':'2.0','method':method,'params':params}
        if not notification: payload['id']=1
        request=urllib.request.Request(self.url,data=json.dumps(payload).encode(),headers={
            'Content-Type':'application/json','Accept':'application/json, text/event-stream',
            'MCP-Protocol-Version':'2025-06-18','Authorization':'Bearer '+self.token})
        with self.opener.open(request,timeout=45) as response:
            if notification and response.status==202: return {}
            body=response.read(65537)
        if len(body)>65536: raise ValueError('Oversized MCP response')
        response=json.loads(body)
        if response.get('error') or 'result' not in response: raise ValueError('Studio MCP request failed')
        return response['result']
    async def step(self, name):
        await asyncio.to_thread(self.request,'initialize',{'protocolVersion':'2025-06-18','capabilities':{},'clientInfo':{'name':'lightek-comfyui','version':'1.0.0'}})
        await asyncio.to_thread(self.request,'notifications/initialized',{},True)
        deadline=time.monotonic()+3300
        while time.monotonic()<deadline:
            result=await asyncio.to_thread(self.request,'tools/call',{'name':name,'arguments':{}})
            if result.get('isError'): raise ValueError('Studio worker could not complete '+name)
            receipt=result.get('structuredContent',{})
            if receipt.get('status')=='completed': return receipt
            if receipt.get('status') not in ('pending','running'): raise ValueError('Invalid Studio worker status')
            await asyncio.sleep(2)
        raise TimeoutError('Studio workflow exceeded its execution window')

class LightekStudioJob:
    CATEGORY='Lightek/Studio'
    RETURN_TYPES=('LIGHTEK_STUDIO_JOB',)
    FUNCTION='create'
    @classmethod
    def INPUT_TYPES(cls): return {'required':{'context':('STRING',{'default':'','multiline':False})}}
    def create(self, context): return (Job(context),)

class LightekBlenderRender:
    CATEGORY='Lightek/Studio'
    RETURN_TYPES=('LIGHTEK_STUDIO_JOB',)
    FUNCTION='render'
    @classmethod
    def INPUT_TYPES(cls): return {'required':{'job':('LIGHTEK_STUDIO_JOB',)}}
    async def render(self, job):
        await job.step('studio_render')
        return (job,)

class LightekFFmpegAssembly(LightekBlenderRender):
    FUNCTION='assemble'
    async def assemble(self, job):
        await job.step('studio_assemble')
        return (job,)

class LightekStudioResult(LightekBlenderRender):
    FUNCTION='save'
    RETURN_TYPES=()
    OUTPUT_NODE=True
    async def save(self, job):
        result=await job.step('studio_result')
        return {'ui':{'lightek_studio':[result]},'result':()}

NODE_CLASS_MAPPINGS={cls.__name__:cls for cls in (LightekStudioJob,LightekBlenderRender,LightekFFmpegAssembly,LightekStudioResult)}
NODE_DISPLAY_NAME_MAPPINGS={name:name.replace('Lightek','Lightek ') for name in NODE_CLASS_MAPPINGS}
