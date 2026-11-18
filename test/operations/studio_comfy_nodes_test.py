import asyncio
import importlib.util
import json
import os
from pathlib import Path
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('lightek_comfy_nodes',ROOT/'lib/comfyui/lightek_studio/__init__.py')
nodes=importlib.util.module_from_spec(spec);spec.loader.exec_module(nodes)
spec=importlib.util.spec_from_file_location('local_comfy_setup',ROOT/'script/studio/install_local_workflow.py')
local_setup=importlib.util.module_from_spec(spec);spec.loader.exec_module(local_setup)
class StudioComfyNodesTest(unittest.TestCase):
    def test_local_install_uses_existing_privileged_helper_without_printing_credentials(self):
        result=type('Result',(),{'stdout':json.dumps({'status':'failed','reason':'insufficient_memory','api_token':'private'}),'returncode':1})()
        with patch.object(local_setup.subprocess,'run',return_value=result) as command:
            receipt,code=local_setup.install('studio.example.test')
        self.assertEqual(1,code)
        self.assertNotIn('private',json.dumps(receipt))
        self.assertEqual('/usr/local/lib/lightek/install_studio_ai.py',command.call_args.args[0][-1])
        payload=json.loads(command.call_args.kwargs['input'])
        self.assertEqual(('workflow','cpu'),(payload['package_id'],payload['device']))
        self.assertEqual(64,len(payload['api_token']))
        with self.assertRaises(ValueError): local_setup.install('studio.test; rm -rf /')
    def test_context_only_accepts_configured_origin_and_job_route(self):
        with patch.dict(os.environ,{'LIGHTEK_STUDIO_ORIGIN':'https://studio.example.test'}):
            for url in ('http://169.254.169.254/latest/meta-data','https://other.test/api/lightek/pwa/studio/workflows/1/mcp',
                        'https://studio.example.test/admin','https://studio.example.test/api/lightek/pwa/studio/workflows/1/mcp?token=other'):
                with self.assertRaises(ValueError): nodes.Job(json.dumps({'url':url,'token':'secret'}))
            job=nodes.Job(json.dumps({'url':'https://studio.example.test/api/lightek/pwa/studio/workflows/1/mcp','token':'secret'}))
            self.assertEqual('secret',job.token)
    def test_redirects_are_refused_instead_of_forwarding_credentials(self):
        with self.assertRaisesRegex(ValueError,'redirects'):
            nodes.NoRedirect().redirect_request(None,None,None,None,None,None)
    def test_mcp_tool_error_stops_the_graph(self):
        with patch.dict(os.environ,{'LIGHTEK_STUDIO_ORIGIN':'http://127.0.0.1:18466'}):
            job=nodes.Job(json.dumps({'url':'http://127.0.0.1:18466/api/lightek/pwa/studio/workflows/1/mcp','token':'secret'}))
        calls=[]
        def request(method,params,notification=False):
            calls.append((method,params,notification))
            return {'isError':True} if method=='tools/call' else {}
        job.request=request
        with self.assertRaisesRegex(ValueError,'studio_render'):
            asyncio.run(job.step('studio_render'))
        self.assertEqual('initialize',calls[0][0])
        self.assertEqual(('notifications/initialized',{},True),calls[1])
        self.assertEqual({},calls[2][1]['arguments'])
if __name__=='__main__': unittest.main()
