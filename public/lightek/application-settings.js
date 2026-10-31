/* Apply the selected hostname's PWA configuration to the existing client. */
(() => {
  const state=()=>window.LightekStorefront?.state;
  const brand=()=>state()?.bootstrap?.application;
  const aliases={post:'home',saved:'home',community:'communities',susu:'money'};
  const esc=value=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  function applyBrand(){
    const app=brand();if(!app)return;
    document.title=app.name||'Lightek';
    const logo=document.querySelector('#top .logo');
    if(logo){logo.style.cssText='max-width:min(44vw,260px);display:block;overflow:hidden;text-overflow:ellipsis;white-space:nowrap';logo.replaceChildren();if(app.logo_url){const img=document.createElement('img');img.src=app.logo_url;img.alt=app.name;img.style.cssText='max-height:38px;max-width:190px;object-fit:contain';logo.append(img);}else logo.textContent=app.name||'Lightek';}
    if(/^#[\da-f]{6}$/i.test(app.theme_color||''))document.documentElement.style.setProperty('--gd',app.theme_color);
    if(/^#[\da-f]{6}$/i.test(app.background_color||''))document.documentElement.style.setProperty('--bg',app.background_color);
    const theme=document.querySelector('meta[name="theme-color"]');if(theme&&app.theme_color)theme.content=app.theme_color;
    const manifest=document.querySelector('link[rel=manifest]');if(manifest&&app.manifest_url)manifest.href=app.manifest_url;
    const icon=document.querySelector('link[rel="apple-touch-icon"]');if(icon&&app.icon_url)icon.href=app.icon_url;
    let footer=document.getElementById('pwa-configured-footer');
    if(!footer){footer=document.createElement('footer');footer.id='pwa-configured-footer';footer.className='wrap';footer.style.cssText='padding:30px 24px 90px';document.body.append(footer);}
    footer.innerHTML=(state().navigation||[]).filter(item=>item.placement==='footer').map(item=>`<a class="btn sm" href="${esc(item.href)}">${esc(item.label)}</a>`).join(' ') + (app.support_email?` <a class="btn sm" href="mailto:${esc(app.support_email)}">Contact support</a>`:'');
  }
  for(const key of Object.keys(R)){
    const original=R[key];if(typeof original!=='function')continue;
    R[key]=(...args)=>{
      const app=brand(),current=state();
      if(app&&current?.ready&&!app.administration?.super_admin){
        if(app.status==='maintenance'||app.access_suspended)return `<div class="wrap pwa-page"><h1>${esc(app.access_suspended?'Application access suspended':app.name+' is under maintenance')}</h1><p>${esc(app.welcome_message||'Please contact the application team.')}</p>${app.administration?.can_manage?'<a class="btn" href="/dashboard/pwa">Open PWA Administration</a>':''}</div>`;
        if(!current.surfaces.has(aliases[key]||key)&&!['auth','blocked'].includes(key))return `<div class="wrap pwa-page"><h1>This feature is unavailable</h1><p>The application administrator has disabled this section.</p><a class="btn" href="#/${esc(app.start_surface||'home')}">Return to the application</a></div>`;
      }
      const html=original(...args),surface=window.LightekStorefront?.surface(aliases[key]||key);
      if(typeof html!=='string'||!surface)return html;
      const template=document.createElement('template');template.innerHTML=html;
      const heading=template.content.querySelector('h1');
      if(heading&&surface.configuration?.heading)heading.textContent=surface.configuration.heading;
      if(heading&&surface.configuration?.intro){const p=heading.parentElement.querySelector('p');if(p)p.textContent=surface.configuration.intro;}
      if(surface.configuration?.layout_configured){
        const modules=new Map((surface.modules||[]).map(mod=>[mod.key,mod]));
        const groups=new Map();
        for(const node of template.content.querySelectorAll('[data-pwa-module]')){
          const mod=modules.get(node.dataset.pwaModule);
          if(!mod){node.remove();continue;}
          const title=node.querySelector('h2');if(title&&mod.label)title.textContent=mod.label;
          const siblings=groups.get(node.parentElement)||[];siblings.push({node,position:mod.position||0});groups.set(node.parentElement,siblings);
        }
        for(const [parent,nodes] of groups)for(const item of nodes.sort((a,b)=>a.position-b.position))parent.append(item.node);
      }
      return template.innerHTML;
    };
  }
  function ready(){applyBrand();const app=brand();if(app?.start_surface&&location.hash==='#/home'&&app.start_surface!=='home')location.hash='#/'+app.start_surface;else render(1);}
  addEventListener('lightek.bootstrap.ready',ready);
  if(state()?.ready)ready();
})();
