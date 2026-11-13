# Shared live HTTPS, primary owner authentication and staged Dashboard acceptance.
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

class SameOriginRedirect(urllib.request.HTTPRedirectHandler):
    def __init__(self, origin):self.origin=origin
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        parsed=urllib.parse.urlparse(newurl)
        if parsed.scheme!='https' or parsed.netloc!=self.origin or parsed.username or parsed.password:
            raise PublicVerificationError('Installation redirected to another origin')
        return super().redirect_request(req,fp,code,msg,headers,newurl)

def verify_public(c):
    base='https://'+c['domain']
    opener=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()),SameOriginRedirect(c['domain']))
    def request(path,data=None):
        headers={'User-Agent':'Mozilla/5.0 (X11; Linux x86_64; rv:155.0) Gecko/20100101 Firefox/155.0','Accept':'text/html,application/json'}
        if data is not None:headers['Origin']=base
        req=urllib.request.Request(base+path,data=data,headers=headers)
        with opener.open(req,timeout=30) as r:
            final=r.geturl();parsed=urllib.parse.urlparse(final)
            if parsed.scheme!='https' or parsed.netloc!=c['domain']:raise PublicVerificationError('Wrong installation origin')
            body=r.read(1_000_001)
            if len(body)>1_000_000:raise PublicVerificationError('Oversized installation response')
            return final,body.decode(),r.status
    _,body,_=request('/__lightek/website-health');h=json.loads(body)
    if h.get('release')!=c['release'] or h.get('domain')!=c['domain'] or h.get('sections',0)<3:raise PublicVerificationError('Public website health does not match this release')
    _,html,_=request('/')
    if 'name="lightek-release" content="'+c['release']+'"' not in html:raise PublicVerificationError('Public homepage is not this deployed template')
    _,login,_=request('/session/new');parser=TokenParser();parser.feed(login)
    if not parser.token:raise PublicVerificationError('Sign-in form has no CSRF token')
    data=urllib.parse.urlencode(dict(authenticity_token=parser.token,email_address=c['owner_email'],password=c['owner_password'])).encode()
    request('/session',data)
    checks=('/dashboard/pages','/dashboard/business','/dashboard/settings',
            '/dashboard/commerce/orders?site_id='+str(h['site_id']))
    paths=[];gated=None
    for path in checks:
        final,body,status=request(path)
        dest=urllib.parse.urlparse(final).path.rstrip('/')
        expected=urllib.parse.urlparse(path).path
        this_gated=dest=='/identity/security'
        if status!=200 or (dest!=expected and not this_gated):raise PublicVerificationError('Owner Dashboard acceptance failed: '+expected)
        if gated is not None and this_gated!=gated:raise PublicVerificationError('Inconsistent owner MFA gate')
        gated=this_gated;paths.append(expected)
    if not gated:
        h['full_application_dashboard_verified']=True
        return h
    # A page that looks like MFA is not evidence. Prove a real owner-scoped,
    # enrollment-only session exists, and keep the full-Dashboard flag false.
    final,body,status=request('/identity/onboarding-status');proof=json.loads(body)
    if status!=200 or urllib.parse.urlparse(final).path!='/identity/onboarding-status' or not (
        proof.get('version')==1 and proof.get('domain')==c['domain'] and proof.get('release')==c['release'] and
        proof.get('site_id')==h['site_id'] and proof.get('owner_email')==c['owner_email'] and
        proof.get('password_authenticated') is True and proof.get('mfa_required') is True and
        proof.get('mfa_enabled') is False and proof.get('mfa_verified') is False and
        proof.get('session_scope')=='mfa_enrollment_only'):
        raise PublicVerificationError('Owner MFA enrollment evidence missing')
    h.update(verification_schema=2,owner_email=proof['owner_email'],owner_authentication_verified=True,
        owner_onboarding_required=True,owner_mfa_state='enrollment_required',
        dashboard_mfa_gate_verified=True,verified_dashboard_paths=paths,full_application_dashboard_verified=False)
    return h

if __name__ == '__main__':
    try:print(json.dumps(verify_public(json.load(sys.stdin))))
    except Exception as error:
        print('Live application verification failed: '+type(error).__name__,file=sys.stderr)
        sys.exit(1)
