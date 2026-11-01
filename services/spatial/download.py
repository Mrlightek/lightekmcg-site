"""Private worker CLI: URLs/config arrive on stdin, never command-line credentials."""
import asyncio,json,sys
from .assets import download_glb
async def main():
    data=json.load(sys.stdin);await download_glb(data['url'],data['output'],set(data['allowed_hosts']))
if __name__=='__main__':asyncio.run(main())
