import asyncio,tempfile,unittest
from services.spatial.assets import AssetJobs,download_glb
class AssetTests(unittest.IsolatedAsyncioTestCase):
    async def test_idempotent_success_and_failures(self):
        with tempfile.TemporaryDirectory() as root:
            async def generate(data):return '/prepared/model.glb'
            async def stage(owner,data,path):return {'object_id':12,'owner':owner,'path':path}
            queue=AssetJobs(root,generate,stage);queue.start()
            first=queue.submit('owner','blue stage prop','camera','request-one')
            self.assertEqual(queue.submit('owner','blue stage prop','camera','request-one')['id'],first['id'])
            with self.assertRaises(ValueError):queue.submit('owner','different prop','camera','request-one')
            await queue.queue.join();self.assertEqual(queue.get(first['id'],'owner')['status'],'ready');self.assertIsNone(queue.get(first['id'],'stranger'))
            await queue.close()
    async def test_download_rejects_local_and_unapproved_urls(self):
        for url in ['http://127.0.0.1/model.glb','https://127.0.0.1/model.glb','https://unapproved.example/model.glb']:
            with self.assertRaises(ValueError):await download_glb(url,'/unwritten.glb',{'cdn.example'})
if __name__=='__main__':unittest.main()
