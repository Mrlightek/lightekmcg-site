#!/usr/bin/env python3
"""Install the CPU workflow controller using the existing bounded root helper."""
import argparse
import json
import re
import secrets
import subprocess
import uuid

def install(domain):
    if not re.fullmatch(r'[a-z0-9](?:[a-z0-9.-]{1,251})[a-z0-9]',domain) or '.' not in domain:
        raise ValueError('Use the existing HTTPS application hostname')
    payload={'action':'install','domain':domain,'owner_domain':domain,'request_id':str(uuid.uuid4()),
             'package_id':'workflow','device':'cpu','api_token':secrets.token_hex(32)}
    command=['sudo','-n','/usr/bin/timeout','--signal=TERM','--kill-after=30s','7200s',
             '/usr/bin/python3','/usr/local/lib/lightek/install_studio_ai.py']
    result=subprocess.run(command,input=json.dumps(payload),text=True,capture_output=True,timeout=7235)
    try: receipt=json.loads(result.stdout)
    except (ValueError,TypeError):
        return {'status':'failed','message':'The installed helper could not run. Deploy this release and check its existing sudo policy.'},1
    safe={key:receipt[key] for key in ('status','reason','phase','readiness') if key in receipt}
    if receipt.get('reason')=='insufficient_memory':
        safe['message']='The workflow controller requires 1536 MiB total and 1024 MiB available RAM. Free capacity or select another worker.'
    if receipt.get('reason')=='insufficient_disk': safe['message']='The workflow controller requires 6 GiB free disk for its engine/build.'
    return safe,result.returncode

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--domain',required=True)
    args=parser.parse_args()
    receipt,code=install(args.domain)
    print(json.dumps(receipt))
    raise SystemExit(code)
