# Shared live HTTPS, customer authentication and full-dashboard acceptance.
import http.cookiejar
import json
import sys
import urllib.error
import urllib.parse
import urllib.request
from html.parser import HTMLParser

class PublicVerificationError(Exception):
    pass

class TokenParser(HTMLParser):
    def __init__(self):super().__init__();self.token=None
    def handle_starttag(self,tag,attrs):
        d=dict(attrs)
        if tag=='input' and d.get('name')=='authenticity_token':self.token=d.get('value')

def verify_public(c):
    base='https://'+c['domain']
    opener=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
    def request(path,data=None):
        req=urllib.request.Request(base+path,data=data,headers={'User-Agent':'Mozilla/5.0 (X11; Linux x86_64; rv:155.0) Gecko/20100101 Firefox/155.0','Accept':'text/html,application/json'})
        with opener.open(req,timeout=30) as r:return r.geturl(),r.read().decode(),r.status
    _,body,_=request('/__lightek/website-health');h=json.loads(body)
    if h.get('release')!=c['release'] or h.get('domain')!=c['domain'] or h.get('sections',0)<3:raise PublicVerificationError('Public website health does not match this release')
    _,html,_=request('/')
    if 'name="lightek-release" content="'+c['release']+'"' not in html:raise PublicVerificationError('Public homepage is not this deployed template')
    _,login,_=request('/session/new');parser=TokenParser();parser.feed(login)
    if not parser.token:raise PublicVerificationError('Sign-in form has no CSRF token')
    data=urllib.parse.urlencode(dict(authenticity_token=parser.token,email_address=c['owner_email'],password=c['owner_password'])).encode()
    request('/session',data)
    final,body,status=request('/dashboard/pages')
    if status!=200 or urllib.parse.urlparse(final).path.rstrip('/')!='/dashboard/pages':raise PublicVerificationError('Owner cannot open website management after sign-in')
    # Website acceptance alone is not sufficient for a paid full-application
    # installation. Probe other mounted Lightek dashboards using the same
    # authenticated session and reject redirects to sign-in.
    checks=('/dashboard/business','/dashboard/settings',
            '/dashboard/commerce/orders?site_id='+str(h['site_id']))
    for path in checks:
        final,body,status=request(path)
        dest=urllib.parse.urlparse(final).path
        expected=urllib.parse.urlparse(path).path
        if status!=200 or dest.rstrip('/')!=expected:
            raise PublicVerificationError('Full Lightek dashboard acceptance failed: '+path)
    h['full_application_dashboard_verified']=True
    return h

if __name__ == "__main__":
    try:
        health = verify_public(json.load(sys.stdin))
        print(json.dumps(health))
    except Exception as error:
        # HTTP libraries may include URLs or request details in exception text.
        print("Live application verification failed: " + type(error).__name__, file=sys.stderr)
        sys.exit(1)
