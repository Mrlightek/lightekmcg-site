#!/bin/bash
set -e
cd ~/Desktop/Development/dymond_kb

echo "Writing real KB view (real design, real data)..."
mkdir -p app/views/dymond_kb/kb
cat > app/views/dymond_kb/kb/index.html.erb << 'ERB_VIEW_EOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Lightek MCG — Knowledge Base</title>
<link href="https://fonts.googleapis.com/css2?family=Barlow+Condensed:wght@300;400;500;600;700;800;900&family=IBM+Plex+Mono:ital,wght@0,400;0,500;0,600;0,700;1,400&family=IBM+Plex+Sans:ital,wght@0,300;0,400;0,500;0,600;1,300;1,400&display=swap" rel="stylesheet">
<style>
*,*::before,*::after{margin:0;padding:0;box-sizing:border-box;cursor:none;}
:root{
  --bg:#030810;--bg2:#050C18;--bg3:#070F1E;
  --panel:#091220;--card:#0B1628;--lift:#0E1C34;
  --cyan:#00B4CC;--cyan2:#00D0EC;--cyan3:#40E8FF;
  --gold:#C09018;--gold2:#D8A828;
  --green:#18C870;--green2:#20E880;
  --red:#CC1818;--yellow:#C89010;--yellow2:#E8B020;
  --white:#E4EEF8;--off:#B0C4D8;--muted:#3C5068;--dim:#1A2840;
  /* topic colors */
  --start:#18A860;--start2:#20D878;
  --modules:#0060D0;--modules2:#2080F0;
  --deploy:#9820C8;--deploy2:#C030F8;
  --reseller:#C07010;--reseller2:#E09020;
  --billing:#0878A8;--billing2:#10A8D8;
  --ministry:#882010;--ministry2:#C03018;
  --api:#205880;--api2:#2880C0;
  --trouble:#604000;--trouble2:#907010;
  --fc:'Barlow Condensed',sans-serif;
  --fm:'IBM Plex Mono',monospace;
  --fb:'IBM Plex Sans',sans-serif;
}
html{scroll-behavior:smooth;}
body{background:var(--bg);color:var(--white);font-family:var(--fb);overflow-x:hidden;}
body::before{content:'';position:fixed;inset:0;background-image:linear-gradient(rgba(0,180,220,.007) 1px,transparent 1px),linear-gradient(90deg,rgba(0,180,220,.007) 1px,transparent 1px);background-size:28px 28px;pointer-events:none;z-index:0;}

#cur{width:7px;height:7px;background:var(--cyan2);position:fixed;z-index:9999;pointer-events:none;transform:translate(-50%,-50%);border-radius:50%;box-shadow:0 0 12px rgba(0,180,220,.8);transition:width .15s,height .15s;}
#cur2{width:28px;height:28px;border:1px solid rgba(0,180,220,.18);border-radius:50%;position:fixed;z-index:9998;pointer-events:none;transform:translate(-50%,-50%);transition:left .1s cubic-bezier(.16,1,.3,1),top .1s,width .18s,height .18s;}

@keyframes blink{0%,100%{opacity:1}50%{opacity:.1}}
@keyframes fadeUp{from{opacity:0;transform:translateY(16px)}to{opacity:1;transform:none}}
@keyframes slideIn{from{opacity:0;transform:translateX(-12px)}to{opacity:1;transform:none}}
@keyframes searchPulse{0%,100%{box-shadow:0 0 0 0 rgba(0,180,220,.3)}50%{box-shadow:0 0 0 6px rgba(0,180,220,0)}}
.fade-up{opacity:0;transform:translateY(16px);transition:opacity .75s cubic-bezier(.16,1,.3,1),transform .75s cubic-bezier(.16,1,.3,1);}
.fade-up.vis{opacity:1;transform:none;}

/* VIEWS */
.view{display:none;}.view.active{display:block;}

/* ═══════════════════════════════════════
   TOPNAV
═══════════════════════════════════════ */
.topnav{
  position:sticky;top:0;z-index:300;
  height:54px;background:rgba(3,8,16,.98);
  border-bottom:1px solid rgba(0,180,220,.07);
  display:flex;align-items:center;justify-content:space-between;
  padding:0 32px;
}
.topnav::after{content:'';position:absolute;bottom:0;left:0;right:0;height:1px;background:linear-gradient(to right,transparent,rgba(0,180,220,.3),rgba(0,180,220,.5),rgba(0,180,220,.3),transparent);}
.tn-left{display:flex;align-items:center;gap:12px;}
.tn-logo{display:flex;align-items:center;gap:8px;cursor:pointer;text-decoration:none;}
.tnl-mark{width:26px;height:26px;border:1.5px solid rgba(0,180,220,.4);display:flex;align-items:center;justify-content:center;font-family:var(--fc);font-size:15px;font-weight:800;color:var(--cyan);}
.tnl-name{font-family:var(--fc);font-size:13px;font-weight:800;letter-spacing:.12em;text-transform:uppercase;color:var(--white);}
.tn-sep{width:1px;height:16px;background:rgba(0,180,220,.12);}
.tn-section{font-family:var(--fm);font-size:6px;letter-spacing:.22em;text-transform:uppercase;color:var(--muted);}
/* inline search */
.tn-search-wrap{flex:1;max-width:480px;margin:0 32px;position:relative;}
.tn-search{width:100%;background:rgba(0,180,220,.05);border:1px solid rgba(0,180,220,.14);padding:8px 14px 8px 36px;font-family:var(--fm);font-size:10px;letter-spacing:.04em;color:var(--white);outline:none;transition:all .2s;}
.tn-search:focus{border-color:rgba(0,180,220,.38);background:rgba(0,180,220,.08);animation:searchPulse 1.5s ease-in-out;}
.tn-search::placeholder{color:rgba(228,238,248,.22);}
.tn-search-icon{position:absolute;left:12px;top:50%;transform:translateY(-50%);font-size:12px;color:var(--muted);pointer-events:none;}
/* search results dropdown */
.search-results{position:absolute;top:100%;left:0;right:0;background:rgba(5,12,24,.98);border:1px solid rgba(0,180,220,.18);border-top:none;z-index:500;max-height:380px;overflow-y:auto;display:none;}
.search-results.open{display:block;}
.sr-group-label{font-family:var(--fm);font-size:6px;letter-spacing:.2em;text-transform:uppercase;color:var(--muted);padding:10px 14px 5px;border-bottom:1px solid rgba(0,180,220,.06);}
.sr-item{display:flex;gap:10px;align-items:flex-start;padding:9px 14px;cursor:pointer;transition:background .15s;border-bottom:1px solid rgba(0,180,220,.04);}
.sr-item:hover{background:rgba(0,180,220,.07);}
.sri-icon{font-size:14px;flex-shrink:0;margin-top:1px;}
.sri-body{flex:1;}
.srib-title{font-family:var(--fb);font-size:12px;font-weight:500;color:rgba(228,238,248,.85);}
.srib-path{font-family:var(--fm);font-size:7px;letter-spacing:.06em;text-transform:uppercase;color:var(--muted);margin-top:1px;}
.sri-type{font-family:var(--fm);font-size:6px;letter-spacing:.1em;text-transform:uppercase;border:1px solid;padding:1px 5px;flex-shrink:0;margin-top:2px;}
.tn-right{display:flex;align-items:center;gap:8px;}
.tn-btn{font-family:var(--fm);font-size:7px;letter-spacing:.14em;text-transform:uppercase;border:1px solid rgba(0,180,220,.14);background:rgba(0,180,220,.04);color:rgba(228,238,248,.45);padding:6px 14px;cursor:pointer;transition:all .18s;}
.tn-btn:hover{border-color:rgba(0,180,220,.35);color:var(--cyan);background:rgba(0,180,220,.08);}
.tn-btn.primary{background:var(--cyan);color:var(--bg);border-color:var(--cyan);}
.tn-btn.primary:hover{background:var(--cyan2);}

/* ═══════════════════════════════════════
   VIEW: HOME
═══════════════════════════════════════ */
#view-home{padding-bottom:80px;}

/* hero search */
.kb-hero{
  padding:64px 48px 52px;
  text-align:center;
  background:linear-gradient(to bottom,rgba(0,180,220,.04),transparent);
  border-bottom:1px solid rgba(0,180,220,.07);
  position:relative;z-index:1;
}
.kbh-eyebrow{font-family:var(--fm);font-size:7px;letter-spacing:.3em;text-transform:uppercase;color:var(--cyan);margin-bottom:10px;}
.kbh-title{font-family:var(--fc);font-size:clamp(40px,6vw,80px);font-weight:900;letter-spacing:.04em;line-height:.88;margin-bottom:8px;}
.kbh-sub{font-family:var(--fb);font-weight:300;font-size:14px;color:rgba(228,238,248,.38);max-width:500px;margin:0 auto 28px;line-height:1.9;}
/* hero search bar */
.kbh-search-wrap{position:relative;max-width:640px;margin:0 auto 16px;}
.kbh-search{width:100%;background:rgba(0,180,220,.06);border:1px solid rgba(0,180,220,.2);padding:16px 20px 16px 52px;font-family:var(--fb);font-size:15px;color:var(--white);outline:none;transition:all .22s;}
.kbh-search:focus{border-color:rgba(0,180,220,.5);background:rgba(0,180,220,.09);animation:searchPulse 1.5s ease-in-out;}
.kbh-search::placeholder{color:rgba(228,238,248,.25);}
.kbh-search-icon{position:absolute;left:18px;top:50%;transform:translateY(-50%);font-size:18px;color:var(--muted);pointer-events:none;}
.kbh-search-btn{position:absolute;right:0;top:0;bottom:0;font-family:var(--fc);font-size:14px;font-weight:700;letter-spacing:.1em;text-transform:uppercase;background:var(--cyan);color:var(--bg);border:none;padding:0 24px;cursor:pointer;transition:background .18s;}
.kbh-search-btn:hover{background:var(--cyan2);}
/* search results */
.kbh-results{position:absolute;top:100%;left:0;right:0;background:rgba(5,12,24,.99);border:1px solid rgba(0,180,220,.2);border-top:none;z-index:500;display:none;max-height:420px;overflow-y:auto;}
.kbh-results.open{display:block;}
/* popular searches */
.kbh-popular{display:flex;align-items:center;gap:8px;justify-content:center;flex-wrap:wrap;}
.kbhp-label{font-family:var(--fm);font-size:7px;letter-spacing:.14em;text-transform:uppercase;color:var(--muted);}
.kbhp-tag{font-family:var(--fm);font-size:7px;letter-spacing:.08em;border:1px solid rgba(0,180,220,.14);background:rgba(0,180,220,.04);color:rgba(228,238,248,.45);padding:4px 11px;cursor:pointer;transition:all .18s;}
.kbhp-tag:hover{border-color:rgba(0,180,220,.35);color:var(--cyan);background:rgba(0,180,220,.08);}

/* topic grid */
.kb-topics{padding:40px 48px 0;}
.kt-label{font-family:var(--fm);font-size:7px;letter-spacing:.26em;text-transform:uppercase;color:var(--muted);margin-bottom:16px;}
.topic-grid{display:grid;grid-template-columns:repeat(4,1fr);gap:4px;margin-bottom:40px;}
@media(max-width:1100px){.topic-grid{grid-template-columns:repeat(2,1fr);}}

.topic-card{background:var(--panel);border:1px solid rgba(0,180,220,.07);padding:22px 20px;cursor:pointer;transition:all .25s;position:relative;overflow:hidden;}
.topic-card:hover{border-color:rgba(0,180,220,.22);transform:translateY(-2px);}
.topic-card::before{content:'';position:absolute;top:0;left:0;right:0;height:3px;}
.tc-icon{font-size:26px;display:block;margin-bottom:10px;}
.tc-name{font-family:var(--fc);font-size:clamp(16px,2vw,20px);font-weight:800;letter-spacing:.06em;margin-bottom:4px;}
.tc-desc{font-family:var(--fb);font-weight:300;font-size:11px;color:rgba(228,238,248,.38);line-height:1.65;margin-bottom:10px;}
.tc-count{font-family:var(--fm);font-size:6px;letter-spacing:.12em;text-transform:uppercase;color:var(--muted);}

/* featured articles */
.kb-featured{padding:0 48px 40px;}
.featured-grid{display:grid;grid-template-columns:2fr 1fr 1fr;gap:4px;}
@media(max-width:1000px){.featured-grid{grid-template-columns:1fr;}}
.feat-card{background:var(--panel);border:1px solid rgba(0,180,220,.07);padding:20px;cursor:pointer;transition:all .22s;position:relative;overflow:hidden;}
.feat-card:hover{border-color:rgba(0,180,220,.22);}
.feat-card.large{padding:28px;}
.fc-type{font-family:var(--fm);font-size:6px;letter-spacing:.16em;text-transform:uppercase;border:1px solid;padding:2px 7px;display:inline-block;margin-bottom:10px;}
.fc-title{font-family:var(--fc);font-size:clamp(16px,2.2vw,24px);font-weight:800;letter-spacing:.05em;line-height:1.15;margin-bottom:6px;}
.fc-excerpt{font-family:var(--fb);font-weight:300;font-size:12px;color:rgba(228,238,248,.42);line-height:1.65;margin-bottom:10px;}
.fc-meta{display:flex;align-items:center;gap:8px;font-family:var(--fm);font-size:6px;letter-spacing:.1em;text-transform:uppercase;color:var(--muted);}
.fc-meta-dot{width:3px;height:3px;border-radius:50%;background:var(--muted);}

/* recently updated */
.kb-recent{padding:0 48px 0;background:rgba(5,10,20,.6);padding-top:32px;padding-bottom:32px;}
.recent-list{display:flex;flex-direction:column;gap:2px;}
.recent-item{display:flex;gap:14px;align-items:center;padding:11px 14px;background:var(--panel);border:1px solid rgba(0,180,220,.06);cursor:pointer;transition:all .18s;}
.recent-item:hover{border-color:rgba(0,180,220,.2);}
.ri-icon{font-size:16px;flex-shrink:0;}
.ri-body{flex:1;}
.rib-title{font-family:var(--fb);font-size:13px;font-weight:500;color:rgba(228,238,248,.82);}
.rib-path{font-family:var(--fm);font-size:6px;letter-spacing:.1em;text-transform:uppercase;color:var(--muted);margin-top:2px;}
.ri-type{font-family:var(--fm);font-size:6px;letter-spacing:.1em;text-transform:uppercase;border:1px solid;padding:2px 6px;flex-shrink:0;}
.ri-time{font-family:var(--fm);font-size:7px;letter-spacing:.06em;color:var(--muted);flex-shrink:0;text-align:right;}

/* ═══════════════════════════════════════
   VIEW: TOPIC (article list)
═══════════════════════════════════════ */
#view-topic{padding-bottom:80px;}
.topic-layout{display:grid;grid-template-columns:240px 1fr;min-height:calc(100vh - 54px);}
@media(max-width:900px){.topic-layout{grid-template-columns:1fr;}}
/* topic sidebar nav */
.topic-sidenav{background:rgba(5,10,20,.98);border-right:1px solid rgba(0,180,220,.07);padding:20px 0;position:sticky;top:54px;height:calc(100vh - 54px);overflow-y:auto;}
.topic-sidenav::-webkit-scrollbar{width:0;}
.tsn-back{display:flex;align-items:center;gap:7px;padding:0 16px 14px;border-bottom:1px solid rgba(0,180,220,.07);margin-bottom:10px;cursor:pointer;}
.tsnb-arrow{font-family:var(--fm);font-size:9px;color:var(--cyan);}
.tsnb-text{font-family:var(--fm);font-size:7px;letter-spacing:.14em;text-transform:uppercase;color:var(--muted);transition:color .18s;}
.tsn-back:hover .tsnb-text{color:var(--cyan);}
.tsn-topic-hdr{padding:0 16px;margin-bottom:14px;}
.tsnth-icon{font-size:22px;display:block;margin-bottom:5px;}
.tsnth-name{font-family:var(--fc);font-size:16px;font-weight:800;letter-spacing:.07em;}
.tsn-section{margin-bottom:10px;}
.tsns-label{font-family:var(--fm);font-size:6px;letter-spacing:.22em;text-transform:uppercase;color:var(--muted);padding:0 16px;margin-bottom:4px;}
.tsn-item{display:flex;align-items:center;gap:8px;padding:7px 14px;border-left:2px solid transparent;cursor:pointer;transition:all .15s;}
.tsn-item:hover{background:rgba(0,180,220,.04);}
.tsn-item.on{background:rgba(0,180,220,.06);border-left-color:var(--cyan);}
.tsn-item.on .tsni-label{color:var(--cyan);}
.tsni-type{font-family:var(--fm);font-size:5px;letter-spacing:.1em;text-transform:uppercase;border:1px solid;padding:1px 4px;flex-shrink:0;}
.tsni-label{font-family:var(--fb);font-size:11px;color:rgba(228,238,248,.45);flex:1;line-height:1.3;}
/* topic main content */
.topic-main{padding:28px 36px;overflow-y:auto;}
.tm-header{margin-bottom:24px;}
.tmh-breadcrumb{display:flex;align-items:center;gap:5px;font-family:var(--fm);font-size:6px;letter-spacing:.12em;text-transform:uppercase;color:var(--muted);margin-bottom:10px;flex-wrap:wrap;}
.tmhb-sep{color:rgba(228,238,248,.2);}
.tmhb-link{cursor:pointer;transition:color .15s;}
.tmhb-link:hover{color:var(--cyan);}
.tmhb-current{color:rgba(228,238,248,.45);}
.tm-topic-title{font-family:var(--fc);font-size:clamp(28px,4vw,52px);font-weight:900;letter-spacing:.05em;margin-bottom:6px;}
.tm-topic-desc{font-family:var(--fb);font-weight:300;font-size:14px;color:rgba(228,238,248,.38);line-height:1.9;max-width:580px;margin-bottom:20px;}
/* article list */
.article-list{display:flex;flex-direction:column;gap:3px;}
.article-item{background:var(--panel);border:1px solid rgba(0,180,220,.07);padding:16px 18px;cursor:pointer;transition:all .22s;display:flex;gap:14px;align-items:flex-start;position:relative;}
.article-item:hover{border-color:rgba(0,180,220,.22);transform:translateX(3px);}
.article-item::before{content:'';position:absolute;top:0;left:0;bottom:0;width:3px;opacity:0;transition:opacity .2s;}
.article-item:hover::before{opacity:1;}
.ai-icon{font-size:20px;flex-shrink:0;margin-top:1px;}
.ai-body{flex:1;}
.aib-type{font-family:var(--fm);font-size:5px;letter-spacing:.14em;text-transform:uppercase;border:1px solid;padding:2px 6px;display:inline-block;margin-bottom:5px;}
.aib-title{font-family:var(--fb);font-size:14px;font-weight:500;color:rgba(228,238,248,.85);margin-bottom:3px;line-height:1.3;}
.aib-excerpt{font-family:var(--fb);font-weight:300;font-size:11px;color:rgba(228,238,248,.38);line-height:1.6;}
.ai-meta{text-align:right;flex-shrink:0;}
.aim-read{font-family:var(--fm);font-size:6px;letter-spacing:.1em;text-transform:uppercase;color:var(--muted);}
.aim-updated{font-family:var(--fm);font-size:6px;letter-spacing:.06em;color:var(--muted);margin-top:3px;}
.aim-arrow{font-family:var(--fc);font-size:18px;font-weight:900;color:rgba(0,180,220,.2);display:block;margin-top:4px;}

/* ═══════════════════════════════════════
   VIEW: ARTICLE
═══════════════════════════════════════ */
#view-article{padding-bottom:80px;}
.article-layout{display:grid;grid-template-columns:240px 1fr 220px;min-height:calc(100vh - 54px);}
@media(max-width:1200px){.article-layout{grid-template-columns:200px 1fr;}}
@media(max-width:900px){.article-layout{grid-template-columns:1fr;}}
/* article sidenav — same topic nav */
.art-sidenav{background:rgba(5,10,20,.98);border-right:1px solid rgba(0,180,220,.07);padding:20px 0;position:sticky;top:54px;height:calc(100vh - 54px);overflow-y:auto;}
.art-sidenav::-webkit-scrollbar{width:0;}
/* article body */
.article-body{padding:32px 40px;overflow-y:auto;max-width:780px;}
.article-body::-webkit-scrollbar{width:0;}
/* article header */
.art-header{margin-bottom:28px;padding-bottom:22px;border-bottom:1px solid rgba(0,180,220,.08);}
.arth-breadcrumb{display:flex;align-items:center;gap:5px;font-family:var(--fm);font-size:6px;letter-spacing:.12em;text-transform:uppercase;color:var(--muted);margin-bottom:12px;flex-wrap:wrap;}
.arthb-sep{color:rgba(228,238,248,.2);}
.arthb-link{cursor:pointer;transition:color .15s;}
.arthb-link:hover{color:var(--cyan);}
.arth-type-badge{display:inline-flex;align-items:center;gap:6px;border:1px solid;padding:4px 12px;margin-bottom:10px;}
.arth-title{font-family:var(--fc);font-size:clamp(28px,4vw,52px);font-weight:900;letter-spacing:.04em;line-height:.92;margin-bottom:8px;}
.arth-meta{display:flex;gap:14px;align-items:center;flex-wrap:wrap;}
.arthm-item{font-family:var(--fm);font-size:7px;letter-spacing:.1em;text-transform:uppercase;color:var(--muted);display:flex;align-items:center;gap:4px;}
/* article content */
.art-content{font-family:var(--fb);font-size:14px;line-height:1.95;color:rgba(228,238,248,.72);}
.art-content h2{font-family:var(--fc);font-size:clamp(18px,2.5vw,26px);font-weight:800;letter-spacing:.06em;color:var(--white);margin:28px 0 10px;padding-top:20px;border-top:1px solid rgba(0,180,220,.08);}
.art-content h3{font-family:var(--fc);font-size:clamp(14px,2vw,18px);font-weight:700;letter-spacing:.06em;color:rgba(228,238,248,.85);margin:20px 0 8px;}
.art-content p{margin-bottom:14px;}
.art-content strong{color:rgba(228,238,248,.9);font-weight:600;}
.art-content em{color:var(--cyan);font-style:normal;}
.art-content a{color:var(--cyan);text-decoration:underline;text-decoration-color:rgba(0,180,220,.3);cursor:pointer;}
/* step blocks */
.art-steps{display:flex;flex-direction:column;gap:4px;margin:16px 0;}
.art-step{display:flex;gap:14px;align-items:flex-start;padding:14px 16px;background:var(--panel);border:1px solid rgba(0,180,220,.08);}
.as-num{width:24px;height:24px;border-radius:50%;background:var(--cyan);color:var(--bg);font-family:var(--fm);font-size:9px;font-weight:700;display:flex;align-items:center;justify-content:center;flex-shrink:0;margin-top:1px;}
.as-body{flex:1;}
.asb-title{font-family:var(--fb);font-size:13px;font-weight:600;color:rgba(228,238,248,.9);margin-bottom:3px;}
.asb-desc{font-family:var(--fb);font-weight:300;font-size:12px;color:rgba(228,238,248,.5);line-height:1.65;}
/* callout blocks */
.art-callout{display:flex;gap:10px;align-items:flex-start;padding:12px 16px;margin:14px 0;border-left:3px solid;}
.art-callout.info{border-color:var(--cyan);background:rgba(0,180,220,.06);}
.art-callout.warn{border-color:var(--yellow2);background:rgba(200,144,16,.06);}
.art-callout.danger{border-color:var(--red);background:rgba(204,24,24,.06);}
.art-callout.tip{border-color:var(--green);background:rgba(24,200,112,.05);}
.ac-icon{font-size:14px;flex-shrink:0;margin-top:1px;}
.ac-body{flex:1;}
.acb-label{font-family:var(--fm);font-size:6px;letter-spacing:.2em;text-transform:uppercase;margin-bottom:3px;}
.art-callout.info .acb-label{color:var(--cyan);}
.art-callout.warn .acb-label{color:var(--yellow2);}
.art-callout.danger .acb-label{color:var(--red);}
.art-callout.tip .acb-label{color:var(--green);}
.acb-text{font-family:var(--fb);font-weight:300;font-size:12px;color:rgba(228,238,248,.6);line-height:1.65;}
/* code block */
.art-code{background:rgba(2,4,10,.95);border:1px solid rgba(0,180,220,.12);padding:14px 16px;margin:12px 0;overflow-x:auto;position:relative;}
.art-code pre{font-family:var(--fm);font-size:11px;line-height:1.7;color:rgba(228,238,248,.75);}
.art-code .kw{color:var(--cyan2);}
.art-code .str{color:rgba(130,210,130,.9);}
.art-code .num{color:rgba(210,160,80,.9);}
.art-code .cm{color:rgba(100,130,160,.7);}
.art-code .key{color:rgba(200,160,255,.9);}
.code-lang{position:absolute;top:8px;right:10px;font-family:var(--fm);font-size:6px;letter-spacing:.14em;text-transform:uppercase;color:var(--muted);}
.code-copy{position:absolute;top:6px;right:50px;font-family:var(--fm);font-size:6px;letter-spacing:.1em;text-transform:uppercase;border:1px solid rgba(0,180,220,.15);background:transparent;color:var(--muted);padding:3px 8px;cursor:pointer;transition:all .18s;}
.code-copy:hover{border-color:rgba(0,180,220,.35);color:var(--cyan);}
/* table */
.art-table{width:100%;border-collapse:collapse;margin:14px 0;}
.art-table th{font-family:var(--fm);font-size:7px;letter-spacing:.16em;text-transform:uppercase;color:var(--muted);padding:8px 12px;border-bottom:2px solid rgba(0,180,220,.12);text-align:left;}
.art-table td{font-family:var(--fb);font-size:12px;color:rgba(228,238,248,.6);padding:8px 12px;border-bottom:1px solid rgba(0,180,220,.05);vertical-align:top;line-height:1.55;}
.art-table tr:hover td{background:rgba(0,180,220,.03);}
/* article sidebar — on this page */
.article-onpage{background:rgba(5,10,20,.98);border-left:1px solid rgba(0,180,220,.07);padding:20px 16px;position:sticky;top:54px;height:calc(100vh - 54px);overflow-y:auto;}
.article-onpage::-webkit-scrollbar{width:0;}
.aop-section{margin-bottom:18px;padding-bottom:18px;border-bottom:1px solid rgba(0,180,220,.06);}
.aop-section:last-child{border-bottom:none;}
.aops-title{font-family:var(--fm);font-size:6px;letter-spacing:.2em;text-transform:uppercase;color:var(--muted);margin-bottom:9px;display:flex;align-items:center;gap:5px;}
.aops-title::before{content:'◈';color:var(--cyan);}
/* on this page nav */
.otp-item{font-family:var(--fb);font-weight:300;font-size:11px;color:rgba(228,238,248,.38);padding:4px 0;cursor:pointer;transition:color .15s;border-left:2px solid transparent;padding-left:8px;line-height:1.4;}
.otp-item:hover{color:rgba(228,238,248,.7);}
.otp-item.active{color:var(--cyan);border-left-color:var(--cyan);}
/* related articles */
.related-item{padding:8px 10px;background:var(--panel);border:1px solid rgba(0,180,220,.06);margin-bottom:3px;cursor:pointer;transition:all .18s;}
.related-item:hover{border-color:rgba(0,180,220,.2);}
.rl-title{font-family:var(--fb);font-size:11px;font-weight:500;color:rgba(228,238,248,.65);margin-bottom:2px;line-height:1.3;}
.rl-type{font-family:var(--fm);font-size:5px;letter-spacing:.1em;text-transform:uppercase;color:var(--muted);}
/* helpful / feedback */
.art-feedback{margin-top:32px;padding-top:22px;border-top:1px solid rgba(0,180,220,.08);display:flex;align-items:center;gap:12px;flex-wrap:wrap;}
.artf-label{font-family:var(--fm);font-size:8px;letter-spacing:.14em;text-transform:uppercase;color:var(--muted);}
.artf-btn{font-family:var(--fm);font-size:8px;letter-spacing:.1em;text-transform:uppercase;border:1px solid rgba(0,180,220,.14);background:transparent;color:rgba(228,238,248,.4);padding:6px 16px;cursor:pointer;transition:all .2s;}
.artf-btn:hover,.artf-btn.active{border-color:var(--cyan);color:var(--cyan);background:rgba(0,180,220,.07);}
.artf-btn.negative:hover,.artf-btn.negative.active{border-color:var(--red);color:var(--red);background:rgba(204,24,24,.06);}
/* ticket CTA */
.art-ticket-cta{background:rgba(0,180,220,.04);border:1px solid rgba(0,180,220,.14);padding:16px 18px;margin-top:16px;display:flex;gap:12px;align-items:center;}
.atc-icon{font-size:20px;flex-shrink:0;}
.atc-body{flex:1;}
.atcb-title{font-family:var(--fb);font-size:13px;font-weight:600;margin-bottom:2px;}
.atcb-sub{font-family:var(--fb);font-weight:300;font-size:11px;color:rgba(228,238,248,.4);line-height:1.55;}
.atc-btn{font-family:var(--fc);font-size:13px;font-weight:700;letter-spacing:.1em;text-transform:uppercase;border:1px solid rgba(0,180,220,.25);color:var(--cyan);background:rgba(0,180,220,.07);padding:9px 18px;cursor:pointer;transition:all .2s;white-space:nowrap;flex-shrink:0;}
.atc-btn:hover{background:rgba(0,180,220,.14);}
</style>
</head>
<body>
<div id="cur"></div>
<div id="cur2"></div>

<!-- TOP NAV -->
<nav class="topnav">
  <div class="tn-left">
    <div class="tn-logo" onclick="showHome()">
      <div class="tnl-mark">L</div>
      <div class="tnl-name">LIGHTEK MCG</div>
    </div>
    <div class="tn-sep"></div>
    <div class="tn-section">◈ KNOWLEDGE BASE</div>
  </div>
  <div class="tn-search-wrap">
    <span class="tn-search-icon">🔍</span>
    <input class="tn-search" type="text" placeholder="Search docs…" id="tn-search-input" oninput="handleNavSearch(this)" />
    <div class="search-results" id="tn-search-results"></div>
  </div>
  <div class="tn-right">
    <button class="tn-btn" onclick="showHome()">HOME</button>
    <button class="tn-btn" onclick="window.open('/supports','_blank')">SUPPORT TICKETS</button>
    <button class="tn-btn primary" onclick="window.open('/supports','_blank')">+ FILE TICKET</button>
  </div>
</nav>

<!-- ═══════ VIEW: HOME ═══════ -->
<div class="view active" id="view-home">

  <!-- HERO SEARCH -->
  <div class="kb-hero">
    <div class="kbh-eyebrow">◈ LIGHTEK MCG · KNOWLEDGE BASE · lightek.io/docs</div>
    <div class="kbh-title">HOW CAN WE<br>HELP YOU?</div>
    <div class="kbh-sub">Documentation, integration guides, and troubleshooting for Lightek resellers, partners, and deployed organizations.</div>
    <div class="kbh-search-wrap">
      <span class="kbh-search-icon">🔍</span>
      <input class="kbh-search" type="text" placeholder="Search — e.g. &quot;custom domain setup&quot; or &quot;Bank module auth&quot;" id="hero-search" oninput="handleHeroSearch(this)" />
      <button class="kbh-search-btn" onclick="doSearch()">SEARCH</button>
      <div class="kbh-results" id="hero-results"></div>
    </div>
    <div class="kbh-popular">
      <span class="kbhp-label">POPULAR:</span>
      <button class="kbhp-tag" onclick="quickSearch('custom domain setup')">Custom domain setup</button>
      <button class="kbhp-tag" onclick="quickSearch('commission override')">Commission override</button>
      <button class="kbhp-tag" onclick="quickSearch('Bank module auth')">Bank module auth</button>
      <button class="kbhp-tag" onclick="quickSearch('Ministry Engine')">Ministry Engine</button>
      <button class="kbhp-tag" onclick="quickSearch('API authentication')">API authentication</button>
      <button class="kbhp-tag" onclick="quickSearch('reseller certification')">Reseller certification</button>
    </div>
  </div>

  <!-- TOPICS -->
  <div class="kb-topics">
    <div class="kt-label">BROWSE BY TOPIC</div>
    <div class="topic-grid fade-up" id="topic-grid"></div>
  </div>

  <!-- FEATURED ARTICLES -->
  <div class="kb-featured fade-up">
    <div style="display:flex;justify-content:space-between;align-items:baseline;margin-bottom:14px;">
      <div class="kt-label" style="margin-bottom:0;">FEATURED ARTICLES</div>
      <button style="font-family:var(--fm);font-size:7px;letter-spacing:.14em;text-transform:uppercase;color:var(--muted);background:none;border:none;cursor:pointer;" onclick="showTopic('all')">ALL ARTICLES →</button>
    </div>
    <div class="featured-grid" id="featured-grid"></div>
  </div>

  <!-- RECENTLY UPDATED -->
  <div class="kb-recent fade-up">
    <div style="display:flex;justify-content:space-between;align-items:baseline;margin-bottom:14px;padding:0 48px;">
      <div class="kt-label" style="margin-bottom:0;">RECENTLY UPDATED</div>
      <span style="font-family:var(--fm);font-size:7px;letter-spacing:.12em;text-transform:uppercase;color:var(--muted);">DOCS ARE UPDATED WITH EVERY PLATFORM RELEASE</span>
    </div>
    <div style="padding:0 48px;" id="recent-list"></div>
  </div>

</div><!-- /view-home -->

<!-- ═══════ VIEW: TOPIC ═══════ -->
<div class="view" id="view-topic">
  <div class="topic-layout">
    <nav class="topic-sidenav" id="topic-sidenav"></nav>
    <main class="topic-main" id="topic-main"></main>
  </div>
</div>

<!-- ═══════ VIEW: ARTICLE ═══════ -->
<div class="view" id="view-article">
  <div class="article-layout">
    <nav class="art-sidenav" id="art-sidenav"></nav>
    <main class="article-body" id="article-body"></main>
    <aside class="article-onpage" id="article-onpage"></aside>
  </div>
</div>

<script>
// ── CURSOR ──────────────────────────────────
const cur=document.getElementById('cur'),cur2=document.getElementById('cur2');
let mx=0,my=0,rx=0,ry=0;
document.addEventListener('mousemove',e=>{mx=e.clientX;my=e.clientY;cur.style.left=mx+'px';cur.style.top=my+'px';});
(function l(){rx+=(mx-rx)*.12;ry+=(my-ry)*.12;cur2.style.left=rx+'px';cur2.style.top=ry+'px';requestAnimationFrame(l);})();
function bigCur(){cur.style.width='11px';cur.style.height='11px';cur2.style.width='38px';cur2.style.height='38px';}
function normCur(){cur.style.width='7px';cur.style.height='7px';cur2.style.width='28px';cur2.style.height='28px';}

// ── DATA ─────────────────────────────────────
// ── TOPIC DATA — real, from DymondKb::Topic, not hardcoded ─────────────────
const TOPICS = <%= raw @topics.map { |t|
  { id: t.topic_id, name: t.name, icon: t.icon, color: t.color, desc: t.description, count: t.article_count }
}.to_json %>;

// ── ARTICLE DATA — real, from DymondKb::Article, not hardcoded ─────────────
const ARTICLES = <%= raw @articles.group_by { |a| a.topic.topic_id }.transform_values { |arts|
  arts.map { |a| { id: a.article_id, title: a.title, type: a.type_label, excerpt: a.excerpt, read: a.read_label, updated: a.updated_label } }
}.to_json %>;
// All articles flat
const ALL_ARTICLES=Object.entries(ARTICLES).flatMap(([topicId,arts])=>
  arts.map(a=>({...a,topicId,topicName:TOPICS.find(t=>t.id===topicId)?.name||topicId}))
);

const FEATURED_IDS = <%= raw DymondKb::Article.featured.pluck(:article_id).to_json %>;
const RECENT_IDS = <%= raw DymondKb::Article.order(updated_at: :desc).limit(6).pluck(:article_id).to_json %>;

// Full article content — real, from DymondKb::Article, not hardcoded
const ARTICLE_CONTENT = <%= raw @articles.each_with_object({}) { |a, h|
  h[a.article_id] = {
    title: a.title, topic: a.topic.topic_id, topicName: a.topic.name,
    type: a.type_label, typeColor: a.topic.color,
    read: a.read_label, updated: a.updated_label, author: "Lightek Support Team",
    sections: a.sections, body: a.body,
    related: a.related_articles.pluck(:article_id)
  }
}.to_json %>;

// Type color/border helper
function typeStyle(type){
  const map={
    'GUIDE':'border-color:rgba(24,200,112,.3);color:var(--green)',
    'REFERENCE':'border-color:rgba(0,120,200,.3);color:var(--modules2)',
    'TROUBLESHOOTING':'border-color:rgba(200,144,16,.3);color:var(--yellow2)',
  };
  return map[type]||'border-color:rgba(0,180,220,.2);color:var(--cyan)';
}

// ── RENDER HOME ──────────────────────────────
let homeRendered=false;
function renderHome(){
  if(homeRendered)return;homeRendered=true;
  // topics
  const tg=document.getElementById('topic-grid');
  TOPICS.forEach(t=>{
    const d=document.createElement('div');
    d.className='topic-card fade-up';
    d.onclick=()=>showTopic(t.id);
    d.innerHTML=`
      <div style="position:absolute;top:0;left:0;right:0;height:3px;background:${t.color};"></div>
      <span class="tc-icon">${t.icon}</span>
      <div class="tc-name" style="color:${t.color};">${t.name}</div>
      <div class="tc-desc">${t.desc}</div>
      <div class="tc-count">${t.count} ARTICLES</div>`;
    tg.appendChild(d);
  });
  // featured
  const fg=document.getElementById('featured-grid');
  FEATURED_IDS.forEach((id,i)=>{
    const art=ALL_ARTICLES.find(a=>a.id===id);
    if(!art)return;
    const d=document.createElement('div');
    d.className='feat-card'+(i===0?' large':'');
    d.onclick=()=>showArticle(id);
    const topic=TOPICS.find(t=>t.id===art.topicId);
    d.innerHTML=`
      <div style="position:absolute;top:0;left:0;right:0;height:2px;background:${topic?.color||'var(--cyan)'};"></div>
      <div class="fc-type" style="${typeStyle(art.type)};">${art.type}</div>
      <div class="fc-title" style="color:${topic?.color||'var(--white)'};">${art.title}</div>
      <div class="fc-excerpt">${art.excerpt}</div>
      <div class="fc-meta"><span>${art.read} read</span><div class="fc-meta-dot"></div><span>Updated ${art.updated}</span><div class="fc-meta-dot"></div><span style="color:${topic?.color||'var(--cyan)'};">${topic?.name||''}</span></div>`;
    fg.appendChild(d);
  });
  // recent
  const rl=document.getElementById('recent-list');
  RECENT_IDS.forEach(id=>{
    const art=ALL_ARTICLES.find(a=>a.id===id);
    if(!art)return;
    const topic=TOPICS.find(t=>t.id===art.topicId);
    const d=document.createElement('div');
    d.className='recent-item fade-up';
    d.onclick=()=>showArticle(id);
    d.innerHTML=`
      <div class="ri-icon">${topic?.icon||'📄'}</div>
      <div class="ri-body">
        <div class="rib-title">${art.title}</div>
        <div class="rib-path">${topic?.name||''}</div>
      </div>
      <div class="ri-type" style="${typeStyle(art.type)};">${art.type}</div>
      <div class="ri-time">${art.read} · ${art.updated}</div>`;
    rl.appendChild(d);
  });
  addHoverFX();initReveal();
}

// ── SHOW TOPIC ───────────────────────────────
function showTopic(topicId){
  const topic=TOPICS.find(t=>t.id===topicId)||{name:'ALL ARTICLES',icon:'📄',color:'var(--cyan)',id:'all'};
  const arts=topicId==='all'?ALL_ARTICLES:(ARTICLES[topicId]||[]).map(a=>({...a,topicId}));
  // build sidenav
  const sidenav=document.getElementById('topic-sidenav');
  sidenav.innerHTML=`
    <div class="tsn-back" onclick="showHome()">
      <span class="tsnb-arrow">←</span>
      <span class="tsnb-text">ALL TOPICS</span>
    </div>
    <div class="tsn-topic-hdr">
      <span class="tsnth-icon">${topic.icon}</span>
      <div class="tsnth-name" style="color:${topic.color};">${topic.name}</div>
    </div>
    <div class="tsn-section">
      <div class="tsns-label">GUIDES</div>
      ${arts.filter(a=>a.type==='GUIDE').map(a=>`
      <div class="tsn-item" onclick="showArticle('${a.id}')">
        <div class="tsni-type" style="${typeStyle('GUIDE')};">G</div>
        <div class="tsni-label">${a.title}</div>
      </div>`).join('')}
    </div>
    <div class="tsn-section">
      <div class="tsns-label">REFERENCE</div>
      ${arts.filter(a=>a.type==='REFERENCE').map(a=>`
      <div class="tsn-item" onclick="showArticle('${a.id}')">
        <div class="tsni-type" style="${typeStyle('REFERENCE')};">R</div>
        <div class="tsni-label">${a.title}</div>
      </div>`).join('')}
    </div>
    ${arts.filter(a=>a.type==='TROUBLESHOOTING').length?`
    <div class="tsn-section">
      <div class="tsns-label">TROUBLESHOOTING</div>
      ${arts.filter(a=>a.type==='TROUBLESHOOTING').map(a=>`
      <div class="tsn-item" onclick="showArticle('${a.id}')">
        <div class="tsni-type" style="${typeStyle('TROUBLESHOOTING')};">T</div>
        <div class="tsni-label">${a.title}</div>
      </div>`).join('')}
    </div>`:''}`;
  // build main
  const main=document.getElementById('topic-main');
  main.innerHTML=`
    <div class="tm-header">
      <div class="tmh-breadcrumb">
        <span class="tmhb-link" onclick="showHome()">HOME</span>
        <span class="tmhb-sep">/</span>
        <span class="tmhb-current">${topic.name}</span>
      </div>
      <div class="tm-topic-title" style="color:${topic.color};">${topic.icon} ${topic.name}</div>
      <div class="tm-topic-desc">${topic.desc||'Browse all articles in this section.'}</div>
    </div>
    <div class="article-list">
      ${arts.map(a=>{
        const t=TOPICS.find(tp=>tp.id===a.topicId);
        return `<div class="article-item" onclick="showArticle('${a.id}')" style="cursor:pointer;">
          <div style="position:absolute;top:0;left:0;bottom:0;width:3px;background:${topic.color};opacity:0;transition:opacity .2s;"></div>
          <div class="ai-icon">${t?.icon||'📄'}</div>
          <div class="ai-body">
            <div class="aib-type" style="${typeStyle(a.type)};">${a.type}</div>
            <div class="aib-title">${a.title}</div>
            <div class="aib-excerpt">${a.excerpt}</div>
          </div>
          <div class="ai-meta">
            <div class="aim-read">${a.read}</div>
            <div class="aim-updated">Updated ${a.updated}</div>
            <span class="aim-arrow">→</span>
          </div>
        </div>`;
      }).join('')}
    </div>`;
  showView('topic');
  addHoverFX();
}

// ── SHOW ARTICLE ─────────────────────────────
function showArticle(id){
  const art=ARTICLE_CONTENT[id];
  if(!art){
    // Fallback for articles without full content
    const artMeta=ALL_ARTICLES.find(a=>a.id===id);
    if(!artMeta)return;
    showTopic(artMeta.topicId);
    return;
  }
  const topic=TOPICS.find(t=>t.id===art.topic);
  // build sidenav
  const sidenav=document.getElementById('art-sidenav');
  const topicArts=ARTICLES[art.topic]||[];
  sidenav.innerHTML=`
    <div class="tsn-back" onclick="showTopic('${art.topic}')">
      <span class="tsnb-arrow">←</span>
      <span class="tsnb-text">${art.topicName}</span>
    </div>
    <div class="tsn-topic-hdr">
      <span class="tsnth-icon">${topic?.icon||'📄'}</span>
      <div class="tsnth-name" style="color:${topic?.color||'var(--cyan)'};">${topic?.name||art.topicName}</div>
    </div>
    ${topicArts.map(a=>`
    <div class="tsn-item${a.id===id?' on':''}" onclick="showArticle('${a.id}')">
      <div class="tsni-type" style="${typeStyle(a.type)};">${a.type.charAt(0)}</div>
      <div class="tsni-label">${a.title}</div>
    </div>`).join('')}`;
  // build article body
  const body=document.getElementById('article-body');
  body.innerHTML=`
    <div class="art-header">
      <div class="arth-breadcrumb">
        <span class="arthb-link" onclick="showHome()">HOME</span>
        <span class="arthb-sep">/</span>
        <span class="arthb-link" onclick="showTopic('${art.topic}')">${art.topicName}</span>
        <span class="arthb-sep">/</span>
        <span style="color:rgba(228,238,248,.45);">${art.title}</span>
      </div>
      <div class="arth-type-badge" style="border-color:${art.typeColor}30;background:${art.typeColor}0D;">
        <span style="font-family:var(--fm);font-size:6px;letter-spacing:.18em;text-transform:uppercase;color:${art.typeColor};">${art.type}</span>
      </div>
      <div class="arth-title">${art.title}</div>
      <div class="arth-meta">
        <div class="arthm-item">🕐 ${art.read} read</div>
        <div class="arthm-item">📅 Updated ${art.updated}</div>
        <div class="arthm-item">✍️ ${art.author}</div>
      </div>
    </div>
    <div class="art-content">${art.body}</div>
    <div class="art-feedback">
      <span class="artf-label">WAS THIS HELPFUL?</span>
      <button class="artf-btn" onclick="this.classList.toggle('active');this.textContent='✓ YES'">YES</button>
      <button class="artf-btn negative" onclick="this.classList.toggle('active');this.textContent='✓ NO, FILED'">NO — SUGGEST EDIT</button>
    </div>
    <div class="art-ticket-cta">
      <div class="atc-icon">💬</div>
      <div class="atc-body">
        <div class="atcb-title">Still need help?</div>
        <div class="atcb-sub">This article didn't answer your question. File a support ticket and a Lightek specialist will respond within your SLA window.</div>
      </div>
      <button class="atc-btn" onclick="window.open('/supports','_blank')">FILE A TICKET →</button>
    </div>`;
  // build on-page nav
  const onpage=document.getElementById('article-onpage');
  const related=art.related?.map(rid=>{
    const ra=ALL_ARTICLES.find(a=>a.id===rid);
    return ra?`<div class="related-item" onclick="showArticle('${rid}')"><div class="rl-title">${ra.title}</div><div class="rl-type" style="${typeStyle(ra.type)};">${ra.type}</div></div>`:''}).join('')||'';
  onpage.innerHTML=`
    <div class="aop-section">
      <div class="aops-title">ON THIS PAGE</div>
      ${art.sections.map((s,i)=>`<div class="otp-item${i===0?' active':''}" onclick="document.querySelectorAll('.otp-item').forEach(x=>x.classList.remove('active'));this.classList.add('active')">${s}</div>`).join('')}
    </div>
    ${related?`<div class="aop-section"><div class="aops-title">RELATED ARTICLES</div>${related}</div>`:''}
    <div class="aop-section">
      <div class="aops-title">NEED MORE HELP?</div>
      <button style="width:100%;font-family:var(--fc);font-size:13px;font-weight:700;letter-spacing:.1em;text-transform:uppercase;border:1px solid rgba(0,180,220,.2);color:var(--cyan);background:rgba(0,180,220,.05);padding:10px;cursor:pointer;transition:all .2s;" onclick="window.open('/supports','_blank')">FILE A SUPPORT TICKET →</button>
    </div>`;
  showView('article');
  addHoverFX();
}

// ── VIEW MANAGER ─────────────────────────────
function showView(id){
  document.querySelectorAll('.view').forEach(v=>v.classList.remove('active'));
  document.getElementById('view-'+id).classList.add('active');
  window.scrollTo(0,0);
}
function showHome(){showView('home');renderHome();}

// ── SEARCH ───────────────────────────────────
const POPULAR_SEARCHES=['custom domain setup','commission override','Bank module auth','Ministry Engine protocols','API authentication','reseller certification','white-label branding','SSL certificate','webhook configuration','Reparations Fund'];

function buildResults(q){
  if(!q||q.length<2)return[];
  const ql=q.toLowerCase();
  return ALL_ARTICLES.filter(a=>
    a.title.toLowerCase().includes(ql)||
    a.excerpt.toLowerCase().includes(ql)||
    a.topicName.toLowerCase().includes(ql)||
    a.type.toLowerCase().includes(ql)
  ).slice(0,8);
}

function renderResultsHtml(results,query){
  if(!results.length)return`<div style="padding:16px 14px;font-family:var(--fb);font-size:12px;color:rgba(228,238,248,.35);">No results for "${query}" — <a onclick="window.open('/supports','_blank')" style="color:var(--cyan);cursor:pointer;">file a support ticket →</a></div>`;
  return results.map(r=>{
    const topic=TOPICS.find(t=>t.id===r.topicId);
    return `<div class="sr-item" onclick="showArticle('${r.id}')">
      <div class="sri-icon">${topic?.icon||'📄'}</div>
      <div class="sri-body">
        <div class="srib-title">${r.title}</div>
        <div class="srib-path">${topic?.name||r.topicName} · ${r.read}</div>
      </div>
      <div class="sri-type" style="${typeStyle(r.type)};">${r.type}</div>
    </div>`;
  }).join('');
}

function handleHeroSearch(input){
  const q=input.value.trim();
  const results=document.getElementById('hero-results');
  if(!q){results.classList.remove('open');return;}
  results.classList.add('open');
  results.innerHTML=renderResultsHtml(buildResults(q),q);
  addHoverFX();
}

function handleNavSearch(input){
  const q=input.value.trim();
  const results=document.getElementById('tn-search-results');
  if(!q){results.classList.remove('open');return;}
  results.classList.add('open');
  results.innerHTML=renderResultsHtml(buildResults(q),q);
  addHoverFX();
}

function quickSearch(q){
  document.getElementById('hero-search').value=q;
  handleHeroSearch(document.getElementById('hero-search'));
}

function doSearch(){
  const q=document.getElementById('hero-search').value.trim();
  if(!q)return;
  const results=buildResults(q);
  if(results.length===1){showArticle(results[0].id);}
  else if(results.length>0){
    // Show all results in topic view
    const main=document.getElementById('topic-main');
    const sidenav=document.getElementById('topic-sidenav');
    sidenav.innerHTML=`<div class="tsn-back" onclick="showHome()"><span class="tsnb-arrow">←</span><span class="tsnb-text">HOME</span></div><div class="tsn-topic-hdr"><span class="tsnth-icon">🔍</span><div class="tsnth-name" style="color:var(--cyan);">SEARCH RESULTS</div></div>`;
    main.innerHTML=`<div class="tm-header"><div class="tm-topic-title">RESULTS FOR<br>"${q}"</div><div class="tm-topic-desc">${results.length} articles found</div></div><div class="article-list">${results.map(r=>{const t=TOPICS.find(tp=>tp.id===r.topicId);return`<div class="article-item" onclick="showArticle('${r.id}')"><div class="ai-icon">${t?.icon||'📄'}</div><div class="ai-body"><div class="aib-type" style="${typeStyle(r.type)};">${r.type}</div><div class="aib-title">${r.title}</div><div class="aib-excerpt">${r.excerpt}</div></div><div class="ai-meta"><div class="aim-read">${r.read}</div><div class="aim-updated">${t?.name||''}</div><span class="aim-arrow">→</span></div></div>`;}).join('')}</div>`;
    showView('topic');addHoverFX();
  }
}

// Close search on click outside
document.addEventListener('click',e=>{
  if(!e.target.closest('.kbh-search-wrap'))document.getElementById('hero-results').classList.remove('open');
  if(!e.target.closest('.tn-search-wrap'))document.getElementById('tn-search-results').classList.remove('open');
});

// ── UTILS ────────────────────────────────────
function addHoverFX(){
  document.querySelectorAll('button,.topic-card,.feat-card,.recent-item,.article-item,.related-item,.tsn-item,.sr-item,.kbhp-tag,.otp-item,.art-step,.lean-row').forEach(el=>{
    if(!el._hb){
      el.addEventListener('mouseenter',bigCur);
      el.addEventListener('mouseleave',normCur);
      el._hb=true;
    }
  });
}
function initReveal(){
  const obs=new IntersectionObserver(es=>es.forEach(e=>{if(e.isIntersecting)e.target.classList.add('vis');}),{threshold:.04});
  document.querySelectorAll('.fade-up').forEach(el=>obs.observe(el));
}

// ── INIT ─────────────────────────────────────
renderHome();
</script>
</body>
</html>
ERB_VIEW_EOF

echo "Writing seed data (8 topics, 45 articles)..."
cat > /tmp/seed_kb.rb << 'RUBY_SEED_EOF'
# frozen_string_literal: true
# Seeds the Knowledge Base — 8 topics, 45 articles (4 with content carried over
# from the original design, 41 newly written to match). Idempotent.

TOPICS = [
  { topic_id: "start",    name: "GETTING STARTED",              icon: "🚀", color: "#18C878", description: "New to Lightek? Start here. Account setup, first deployment, reseller onboarding.", sort_order: 0 },
  { topic_id: "modules",  name: "MODULES & SKUs",                icon: "📦", color: "#0878C8", description: "Every DYMOND module in the Lightek catalog. Specs, requirements, what's included.", sort_order: 1 },
  { topic_id: "deploy",   name: "DEPLOYMENT & ONBOARDING",       icon: "⚙️", color: "#9820C8", description: "Configuring and launching your instance. Custom domains, white-label setup, go-live.", sort_order: 2 },
  { topic_id: "reseller", name: "RESELLER PROGRAM",              icon: "🤝", color: "#C87820", description: "Associate, Distributor, and Master Partner tiers. Certifications, sub-reseller networks.", sort_order: 3 },
  { topic_id: "billing",  name: "BILLING & COMMISSIONS",         icon: "💳", color: "#10A8D8", description: "Invoices, payment methods, commission structure, override earnings, dispute process.", sort_order: 4 },
  { topic_id: "ministry", name: "MINISTRY ENGINE & COMPLIANCE",  icon: "⚖️", color: "#E03050", description: "Constitutional Articles I–VIII, Ministry Engine protocols, violation handling.", sort_order: 5 },
  { topic_id: "api",      name: "API & INTEGRATIONS",            icon: "🔗", color: "#7030A8", description: "API reference, authentication, webhooks, SDK usage, module-to-module connections.", sort_order: 6 },
  { topic_id: "trouble",  name: "TROUBLESHOOTING",               icon: "🔧", color: "#C09018", description: "Diagnosing deployment issues, module errors, billing discrepancies, performance.", sort_order: 7 }
].freeze

TOPICS.each do |row|
  t = DymondKb::Topic.find_or_initialize_by(topic_id: row[:topic_id])
  t.assign_attributes(row)
  t.save!
  puts "topic: #{t.topic_id}"
end

ARTICLES = [
{
  article_id: "deploy-custom-domain", topic: "deploy", title: "Setting Up a Custom Domain",
  article_type: "guide", read_minutes: 7,
  excerpt: "Pointing your domain at your Lightek deployment. DNS configuration, SSL, propagation times, troubleshooting.",
  body: <<~HTML
    <h2>Overview</h2>
    <p>Every Lightek deployment ships with a default subdomain at your-org.lightek.app. For white-label deployments, you'll want to point your own domain at your instance. This guide covers the complete setup from DNS to live SSL.</p>
    <div class="art-callout info"><div class="ac-icon">ℹ️</div><div class="ac-body"><div class="acb-label">DISTRIBUTOR TIER REQUIRED</div><div class="acb-text">Custom domain setup requires Distributor or Master Partner tier. Associate resellers use the default .lightek.app subdomain.</div></div></div>
    <h2>DNS Configuration</h2>
    <p>You need to add a CNAME record to your domain's DNS settings, pointing your custom domain at your Lightek deployment endpoint.</p>
    <div class="art-steps">
      <div class="art-step"><div class="as-num">1</div><div class="as-body"><div class="asb-title">Log into your domain registrar</div><div class="asb-desc">Navigate to the DNS management panel for your domain.</div></div></div>
      <div class="art-step"><div class="as-num">2</div><div class="as-body"><div class="asb-title">Add a CNAME record</div><div class="asb-desc">Set the Name/Host to your desired subdomain, and the Value/Target to your Lightek deployment endpoint, found in your Reseller Portal under Instance Settings.</div></div></div>
      <div class="art-step"><div class="as-num">3</div><div class="as-body"><div class="asb-title">Set TTL to 300 seconds</div><div class="asb-desc">A lower TTL speeds up propagation.</div></div></div>
      <div class="art-step"><div class="as-num">4</div><div class="as-body"><div class="asb-title">Enter your domain in the Reseller Portal</div><div class="asb-desc">Instance Settings → Custom Domain. Enter your full domain and save.</div></div></div>
      <div class="art-step"><div class="as-num">5</div><div class="as-body"><div class="asb-title">Wait for propagation</div><div class="asb-desc">Typically 5–30 minutes, up to 24 hours.</div></div></div>
    </div>
    <h2>SSL Certificate</h2>
    <p>Lightek automatically provisions and renews SSL via Let's Encrypt once DNS is verified. Custom certificates for EV requirements can be uploaded manually if needed.</p>
    <h2>Verification</h2>
    <table class="art-table">
      <tr><th>CHECK</th><th>WHAT TO LOOK FOR</th></tr>
      <tr><td>HTTPS lock icon</td><td>Browser shows a padlock</td></tr>
      <tr><td>Domain resolves</td><td>Deployment loads at custom domain</td></tr>
      <tr><td>Portal status</td><td>Shows "VERIFIED"</td></tr>
    </table>
    <h2>Troubleshooting</h2>
    <div class="art-callout warn"><div class="ac-icon">⚠️</div><div class="ac-body"><div class="acb-label">COMMON MISTAKE</div><div class="acb-text">Using an A record instead of CNAME. Lightek deployments use dynamic IPs — always use CNAME.</div></div></div>
  HTML
},
{
  article_id: "tr-bank-auth", topic: "trouble", title: "Bank Module Authorization Stuck",
  article_type: "troubleshooting", read_minutes: 5,
  excerpt: "Why Bank module auth gets stuck, what the approval pathway looks like for government entities, escalation steps.",
  body: <<~HTML
    <h2>Why This Happens</h2>
    <p>The DYMOND BANK module requires a secondary authorization step from DYMOND Empire's banking compliance team before it can go live — separate from your Lightek order approval.</p>
    <div class="art-callout info"><div class="ac-icon">ℹ️</div><div class="ac-body"><div class="acb-label">TYPICAL TIMELINE</div><div class="acb-text">Standard authorization: 3–5 business days. Government entities: 7–12 business days.</div></div></div>
    <table class="art-table">
      <tr><th>CAUSE</th><th>RESOLUTION</th></tr>
      <tr><td>Missing documentation</td><td>Upload required docs</td></tr>
      <tr><td>Government entity review</td><td>Contact @partnership.dymond</td></tr>
      <tr><td>KYB in progress</td><td>Wait — typical 2–3 business days</td></tr>
    </table>
    <h2>The Approval Pathway</h2>
    <div class="art-steps">
      <div class="art-step"><div class="as-num">1</div><div class="as-body"><div class="asb-title">Order Confirmed</div><div class="asb-desc">Bank module SKU is on your instance but not active yet.</div></div></div>
      <div class="art-step"><div class="as-num">2</div><div class="as-body"><div class="asb-title">KYB Submitted</div><div class="asb-desc">Know Your Business verification submitted to compliance.</div></div></div>
      <div class="art-step"><div class="as-num">3</div><div class="as-body"><div class="asb-title">Compliance Review</div><div class="asb-desc">3–5 days standard, 7–12 days government.</div></div></div>
      <div class="art-step"><div class="as-num">4</div><div class="as-body"><div class="asb-title">Authorization Issued</div><div class="asb-desc">Module activates automatically.</div></div></div>
    </div>
    <h2>Government Entity Special Requirements</h2>
    <div class="art-callout warn"><div class="ac-icon">⚠️</div><div class="ac-body"><div class="acb-label">GOVERNMENT ENTITIES</div><div class="acb-text">Prepare all documentation before starting — incomplete submissions restart the review clock.</div></div></div>
    <h2>Escalation</h2>
    <div class="art-steps">
      <div class="art-step"><div class="as-num">1</div><div class="as-body"><div class="asb-title">Contact your account manager</div><div class="asb-desc">Fastest path for status queries.</div></div></div>
      <div class="art-step"><div class="as-num">2</div><div class="as-body"><div class="asb-title">File a Deployment ticket</div><div class="asb-desc">Category DEPLOYMENT, priority HIGH.</div></div></div>
      <div class="art-step"><div class="as-num">3</div><div class="as-body"><div class="asb-title">Contact DYMOND Empire directly</div><div class="asb-desc">Government entity cases only.</div></div></div>
    </div>
    <div class="art-callout danger"><div class="ac-icon">🚨</div><div class="ac-body"><div class="acb-label">DO NOT</div><div class="acb-text">Do not attempt to activate the Bank module manually. Unauthorized activation violates Article II and results in immediate suspension.</div></div></div>
  HTML
},
{
  article_id: "min-overview", topic: "ministry", title: "Ministry Engine — Full Protocol Reference",
  article_type: "reference", read_minutes: 14,
  excerpt: "All seven protocols. What each enforces, which modules it governs, how it interacts with citizen data.",
  body: <<~HTML
    <h2>What the Ministry Engine Is</h2>
    <p>The Ministry Engine is not a module — it is the faith-based ethical governance layer running beneath every DYMOND module deployed through Lightek. It cannot be removed. It can be configured, but core enforcement behaviors cannot be disabled.</p>
    <div class="art-callout info"><div class="ac-icon">ℹ️</div><div class="ac-body"><div class="acb-label">CONSTITUTIONAL REQUIREMENT</div><div class="acb-text">Mandated by DYMOND Empire's Constitutional framework. All resellers agreed to its operation via the Lightek Reseller Agreement.</div></div></div>
    <h2>The Seven Protocols</h2>
    <h3>1. Grace-First Matching</h3>
    <p>Applies to: MATCH, COMMUNITY. Prioritizes compatibility over engagement optimization; prohibits dark patterns.</p>
    <h3>2. Prayer Recovery Protocol</h3>
    <p>Applies to: WELLNESS, CHURCH. Routes distress patterns to human counselors and prayer resources. Never stored in analytics.</p>
    <h3>3. Cultural Sovereignty Filter</h3>
    <p>Applies to: SOCIAL, STUDIO, BARS. Enforces Article V and VI — prevents algorithmic suppression of cultural content.</p>
    <h3>4. Ownership Protection Layer</h3>
    <p>Applies to: CLOUD, STUDIO, BANK. Implements Article I — prevents platform operators from claiming citizen content ownership.</p>
    <h3>5. Economic Equity Override</h3>
    <p>Applies to: BANK, REAL ESTATE. Implements Articles II and VIII — maintains the zero-interest lending floor.</p>
    <h3>6. Body As Temple — FIT Protocol</h3>
    <p>Applies to: FIT, WELLNESS, CHURCH. Prevents promotion of extreme dietary/exercise behaviors without qualification review.</p>
    <h3>7. Restorative Justice Path</h3>
    <p>Applies to: JUSTICE, SETS, COMMUNITY. Routes conflict through restorative frameworks before punitive action.</p>
    <h2>Module Coverage Matrix</h2>
    <table class="art-table">
      <tr><th>MODULE</th><th>PROTOCOLS ACTIVE</th><th>CONFIGURABLE?</th></tr>
      <tr><td>BANK</td><td>Ownership Protection, Economic Equity Override</td><td>No</td></tr>
      <tr><td>CHURCH</td><td>Prayer Recovery, Body As Temple, Restorative Justice</td><td>Partial</td></tr>
      <tr><td>WELLNESS</td><td>Prayer Recovery, Body As Temple</td><td>Partial</td></tr>
      <tr><td>STUDIO</td><td>Cultural Sovereignty, Ownership Protection</td><td>No</td></tr>
    </table>
    <h2>Disabling or Modifying Protocols</h2>
    <div class="art-callout danger"><div class="ac-icon">🚨</div><div class="ac-body"><div class="acb-label">PROTOCOLS CANNOT BE FULLY DISABLED</div><div class="acb-text">Attempting to circumvent protocols triggers an automatic compliance violation and instance review.</div></div></div>
    <p>To request a configuration change for a partial protocol, file a Compliance ticket with the protocol, requested change, and business justification.</p>
  HTML
},
{
  article_id: "api-auth", topic: "api", title: "API Authentication",
  article_type: "reference", read_minutes: 6,
  excerpt: "API key generation, Bearer token flow, scopes, expiration, and rotation.",
  body: <<~HTML
    <h2>Overview</h2>
    <p>The Lightek API uses API key authentication for server-to-server requests. All calls must include an Authorization header with a valid Bearer token. Keys are scoped to specific modules.</p>
    <div class="art-callout warn"><div class="ac-icon">⚠️</div><div class="ac-body"><div class="acb-label">KEEP KEYS SECRET</div><div class="acb-text">Never expose API keys in client-side code or public repositories. Rotate immediately if compromised.</div></div></div>
    <h2>API Keys</h2>
    <p>Generate keys from Reseller Portal: Instance Settings → API Access → Generate Key. Copy immediately — only the last four characters remain visible afterward.</p>
    <h2>Bearer Token Flow</h2>
    <p>Exchange your API key for a short-lived Bearer token tied to a specific citizen session for on-behalf-of requests.</p>
    <h2>Scopes</h2>
    <table class="art-table">
      <tr><th>SCOPE</th><th>MODULE</th><th>DESCRIPTION</th></tr>
      <tr><td>bank:read</td><td>BANK</td><td>Read balances, history, loan status</td></tr>
      <tr><td>bank:write</td><td>BANK</td><td>Initiate transfers, create accounts</td></tr>
      <tr><td>stream:read</td><td>STREAMING</td><td>Read content library, sessions</td></tr>
      <tr><td>admin:*</td><td>ALL</td><td>Full administrative access</td></tr>
    </table>
    <h2>Key Rotation</h2>
    <p>Old keys remain valid for 15 minutes after a new key is generated, giving time to deploy the update with no downtime.</p>
  HTML
},
# ── GETTING STARTED ──
{
  article_id: "start-overview", topic: "start", title: "Lightek MCG Platform Overview",
  article_type: "guide", read_minutes: 4,
  excerpt: "What Lightek is, how the wholesale distribution model works, and where you fit in the four-layer architecture.",
  body: <<~HTML
    <h2>Overview</h2>
    <p>Lightek MCG is a wholesale distribution platform for the DYMOND Empire module ecosystem. Instead of building software from scratch, you deploy pre-built, production-ready modules — banking, streaming, community, faith, and more — under your own brand, at wholesale prices, and keep the margin when you resell to your own customers.</p>
    <div class="art-callout info"><div class="ac-icon">ℹ️</div><div class="ac-body"><div class="acb-label">THE FOUR-LAYER ARCHITECTURE</div><div class="acb-text">Lightek sits between DYMOND Empire (the module manufacturer) and your customers. You never touch DYMOND's internals directly — Lightek handles provisioning, billing, and support so you can focus on your own market.</div></div></div>
    <h2>Where You Fit</h2>
    <table class="art-table">
      <tr><th>LAYER</th><th>ROLE</th></tr>
      <tr><td>DYMOND Empire</td><td>Builds and maintains every module</td></tr>
      <tr><td>Lightek MCG</td><td>Wholesale distributor — you're here</td></tr>
      <tr><td>You (Reseller)</td><td>Deploy modules under your brand, set your own retail price</td></tr>
      <tr><td>Your Customers</td><td>Use the deployed platform day to day</td></tr>
    </table>
    <p>Every module you deploy includes Ministry Engine compliance and Constitutional Article coverage automatically — you don't configure governance separately, it ships built in.</p>
  HTML
},
{
  article_id: "start-account", topic: "start", title: "Setting Up Your Reseller Account",
  article_type: "guide", read_minutes: 6,
  excerpt: "Creating your account, completing certification, and accessing the warehouse catalog for the first time.",
  body: <<~HTML
    <h2>Overview</h2>
    <p>Your reseller account is the single login that gives you access to the module catalog, your deployment dashboard, billing, and support. Setup takes about 15 minutes, most of which is certification.</p>
    <div class="art-steps">
      <div class="art-step"><div class="as-num">1</div><div class="as-body"><div class="asb-title">Create your account</div><div class="asb-desc">Sign up with your organization's legal name and a business email address. Personal email domains (Gmail, Yahoo) will hold up certification review.</div></div></div>
      <div class="art-step"><div class="as-num">2</div><div class="as-body"><div class="asb-title">Complete certification</div><div class="asb-desc">A short training program covering the module catalog, pricing model, and Ministry Engine basics. Required before you can place your first order.</div></div></div>
      <div class="art-step"><div class="as-num">3</div><div class="as-body"><div class="asb-title">Access the catalog</div><div class="asb-desc">Once certified, the full module catalog unlocks with wholesale pricing and your markup calculator.</div></div></div>
    </div>
    <h2>Certification</h2>
    <p>Certification confirms you understand how wholesale pricing works, what Ministry Engine protocols your deployments will inherit, and how support tickets get routed. It's not a sales gate — it protects your customers from misconfigured deployments.</p>
  HTML
},
{
  article_id: "start-catalog", topic: "start", title: "Navigating the Module Catalog",
  article_type: "guide", read_minutes: 5,
  excerpt: "How SKUs work, how to read pricing, what the margin calculator shows, and how to build your first order.",
  body: <<~HTML
    <h2>Overview</h2>
    <p>Every module in the catalog has a SKU, a wholesale price, and a department. The catalog is filterable by department so you can find what you need without scrolling through the full list.</p>
    <h2>Reading a Module Card</h2>
    <table class="art-table">
      <tr><th>FIELD</th><th>MEANING</th></tr>
      <tr><td>SKU</td><td>Unique module identifier, e.g. SKU-001</td></tr>
      <tr><td>Wholesale Price</td><td>What you pay Lightek monthly per deployment</td></tr>
      <tr><td>Ministry Engine badge</td><td>Shown when the module ships with governance protocols active</td></tr>
    </table>
    <div class="art-callout tip"><div class="ac-icon">✅</div><div class="ac-body"><div class="acb-label">MARGIN CALCULATOR</div><div class="acb-text">Adjust your markup multiplier (2×, 2.5×, 3×) on any module and the catalog shows your retail price and margin live — no spreadsheet needed.</div></div></div>
    <h2>Building Your First Order</h2>
    <p>Add modules to your cart, review your markup, and submit. Orders are processed immediately and provisioning begins the same day for standard modules.</p>
  HTML
},
{
  article_id: "start-first-deploy", topic: "start", title: "Your First Deployment — End to End",
  article_type: "guide", read_minutes: 12,
  excerpt: "From placing a catalog order to your client going live. The complete 90-day onboarding path, week by week.",
  body: <<~HTML
    <h2>Overview</h2>
    <p>Your first deployment follows a structured 90-day onboarding path. It's longer than a simple software install because it includes branding, citizen migration, and a full go-live checklist — but most of that time is passive waiting on DNS and certification, not active work.</p>
    <div class="art-steps">
      <div class="art-step"><div class="as-num">1</div><div class="as-body"><div class="asb-title">Weeks 1–2: Order & Provision</div><div class="asb-desc">Place your catalog order. Standard modules provision within 3 business days; modules requiring compliance review (like BANK) take longer.</div></div></div>
      <div class="art-step"><div class="as-num">2</div><div class="as-body"><div class="asb-title">Weeks 3–5: Branding & Domain</div><div class="asb-desc">Apply your white-label branding and set up your custom domain. This is the stage most resellers spend the most active time on.</div></div></div>
      <div class="art-step"><div class="as-num">3</div><div class="as-body"><div class="asb-title">Weeks 6–8: Citizen Migration</div><div class="asb-desc">If you're migrating existing users, bulk import happens here. New deployments with no existing users can skip ahead.</div></div></div>
      <div class="art-step"><div class="as-num">4</div><div class="as-body"><div class="asb-title">Weeks 9–12: Go-Live Prep</div><div class="asb-desc">Run through the 24-point go-live checklist, confirm Ministry Engine protocols are active, and schedule your launch date.</div></div></div>
    </div>
    <div class="art-callout info"><div class="ac-icon">ℹ️</div><div class="ac-body"><div class="acb-label">MOST DEPLOYMENTS GO FASTER</div><div class="acb-text">90 days is the outside estimate for a full white-label build with migration. Simple single-module deployments with no existing users can go live in under 2 weeks.</div></div></div>
    <h2>What Lightek Handles vs. What You Handle</h2>
    <p>Lightek handles infrastructure, SSL, Ministry Engine configuration, and module updates. You handle branding decisions, your own customer relationships, and your retail pricing.</p>
  HTML
},
{
  article_id: "start-whitelabel", topic: "start", title: "White-Label Branding Guide",
  article_type: "guide", read_minutes: 8,
  excerpt: "Applying your brand to a deployed instance. Logo, colors, custom domain, and naming conventions.",
  body: <<~HTML
    <h2>Overview</h2>
    <p>White-label branding replaces every visible DYMOND/Lightek reference with your own organization's identity. Citizens using your deployment never see the underlying platform name.</p>
    <h2>What You Can Rebrand</h2>
    <table class="art-table">
      <tr><th>ELEMENT</th><th>REBRANDABLE</th></tr>
      <tr><td>Logo & favicon</td><td>Yes — upload your own assets</td></tr>
      <tr><td>Color scheme</td><td>Yes — full theme customization</td></tr>
      <tr><td>Domain</td><td>Yes — see the custom domain guide</td></tr>
      <tr><td>Platform name in emails/notifications</td><td>Yes</td></tr>
      <tr><td>Ministry Engine protocol names</td><td>No — Constitutional terminology stays consistent across all deployments</td></tr>
    </table>
    <div class="art-callout warn"><div class="ac-icon">⚠️</div><div class="ac-body"><div class="acb-label">ASSET REQUIREMENTS</div><div class="acb-text">Logo uploads need a transparent PNG at minimum 512×512px. Low-resolution logos will be rejected by the branding validator.</div></div></div>
    <h2>Naming Conventions</h2>
    <p>Your deployment can be called anything — most resellers use their own company name. Avoid names that could be confused with DYMOND Empire's own branded products, as this can slow down module authorization review.</p>
  HTML
},
{
  article_id: "start-ministry", topic: "start", title: "What is the Ministry Engine?",
  article_type: "reference", read_minutes: 5,
  excerpt: "The faith-based governance layer that runs beneath every DYMOND module. What it does, what it enforces.",
  body: <<~HTML
    <h2>Overview</h2>
    <p>The Ministry Engine is the governance layer running underneath every DYMOND module on every deployment. It enforces the Constitutional Articles (I through VIII) that define citizen rights, revenue attribution, and platform equity requirements — regardless of who deployed the instance or where.</p>
    <div class="art-callout info"><div class="ac-icon">ℹ️</div><div class="ac-body"><div class="acb-label">NOT OPTIONAL</div><div class="acb-text">Ministry Engine protocols cannot be disabled. They're part of what you're licensing when you deploy a DYMOND module — see the full protocol reference for details on each Article.</div></div></div>
    <h2>What It Enforces</h2>
    <table class="art-table">
      <tr><th>AREA</th><th>WHAT'S PROTECTED</th></tr>
      <tr><td>Citizen rights</td><td>Articles I–V — baseline protections for anyone using a deployment</td></tr>
      <tr><td>Revenue attribution</td><td>Article VI — cultural attribution enforcement</td></tr>
      <tr><td>Reparations</td><td>Article VII — mandatory allocation requirements</td></tr>
      <tr><td>Universal access</td><td>Article VIII — a permanent zero-cost tier for qualifying citizens</td></tr>
    </table>
    <p>For the complete protocol-by-protocol breakdown, see the full Ministry Engine Protocol Reference in the Compliance topic.</p>
  HTML
},
# ── MODULES & SKUs ──
{
  article_id: "mod-bank", topic: "modules", title: "DYMOND BANK Module — SKU-001",
  article_type: "reference", read_minutes: 9,
  excerpt: "Full neobank deployment specs. Account types, lending engine, Community Credit Pool, Article VIII access tier.",
  body: <<~HTML
    <h2>Overview</h2>
    <p>SKU-001 deploys a full neobank on your instance — checking, savings, lending, and a financial coaching layer. It's the most comprehensive financial module in the catalog and the one most often paired with other modules via the Community Credit Pool.</p>
    <table class="art-table">
      <tr><th>SPEC</th><th>VALUE</th></tr>
      <tr><td>Wholesale price</td><td>$840/month</td></tr>
      <tr><td>Deployment time</td><td>3 business days</td></tr>
      <tr><td>Uptime SLA</td><td>99.97%</td></tr>
      <tr><td>Ministry Engine</td><td>Included — Article VIII Economic Equity Override active</td></tr>
    </table>
    <h2>Account Types</h2>
    <p>Checking, savings, and lending accounts are all available out of the box. The lending engine draws from the Community Credit Pool — a shared liquidity model that lets qualifying citizens access credit even without traditional collateral.</p>
    <div class="art-callout info"><div class="ac-icon">ℹ️</div><div class="ac-body"><div class="acb-label">AUTHORIZATION REQUIRED</div><div class="acb-text">BANK module authorization is a separate compliance step from your Lightek order — see the Bank Module Authorization Stuck troubleshooting guide if activation is delayed.</div></div></div>
    <h2>Article VIII Access Tier</h2>
    <p>Every BANK deployment includes a zero-cost tier for qualifying citizens under Article VIII's universal access requirement. This isn't configurable — it's part of what makes a BANK deployment Constitutional.</p>
  HTML
},
{
  article_id: "mod-church", topic: "modules", title: "DYMOND CHURCH Module — SKU-008",
  article_type: "reference", read_minutes: 7,
  excerpt: "Faith community platform specs. Live streaming capacity, tithe integration, ordination network access.",
  body: <<~HTML
    <h2>Overview</h2>
    <p>SKU-008 deploys a complete faith community platform — live service streaming, sermon notes, a prayer wall, and tithe collection wired directly into a linked BANK module.</p>
    <table class="art-table">
      <tr><th>SPEC</th><th>VALUE</th></tr>
      <tr><td>Wholesale price</td><td>$480/month</td></tr>
      <tr><td>Concurrent viewers</td><td>Up to 50,000</td></tr>
      <tr><td>Deployment time</td><td>2 business days</td></tr>
    </table>
    <h2>Tithe Collection</h2>
    <p>Tithe and offering collection links directly to a BANK module deployment on the same instance — no separate payment processor needed. If BANK isn't deployed, tithe collection falls back to a standard payment link.</p>
    <h2>Ordination Network</h2>
    <p>Ministers on your deployment are bookable through the network if the BOOKING module is also active, enabling counseling and ceremony scheduling directly from the CHURCH module.</p>
  HTML
},
{
  article_id: "mod-streaming", topic: "modules", title: "DYMOND+ Streaming Module — SKU-014",
  article_type: "reference", read_minutes: 8,
  excerpt: "Content platform specs. Library limits, concurrent viewers, creator dashboard, royalty tracking.",
  body: <<~HTML
    <h2>Overview</h2>
    <p>SKU-014 deploys a full streaming platform for original content — video library, live broadcast, and a creator dashboard with built-in royalty tracking.</p>
    <table class="art-table">
      <tr><th>SPEC</th><th>VALUE</th></tr>
      <tr><td>Wholesale price</td><td>$1,200/month</td></tr>
      <tr><td>Video library</td><td>Unlimited, adaptive bitrate</td></tr>
      <tr><td>Live broadcast</td><td>Up to 100,000 concurrent viewers</td></tr>
    </table>
    <h2>Royalty Tracking</h2>
    <p>Every piece of content uploaded is tied to a creator record with full catalog ownership documented. Royalty payouts calculate automatically based on viewership and are payable through a linked BANK module.</p>
    <div class="art-callout info"><div class="ac-icon">ℹ️</div><div class="ac-body"><div class="acb-label">ARTICLE VI COMPLIANCE</div><div class="acb-text">Attribution enforcement is built into the module — creators are automatically credited per Article VI's cultural attribution requirement.</div></div></div>
  HTML
},
{
  article_id: "mod-connect", topic: "modules", title: "DYMOND CONNECT Module — SKU-004",
  article_type: "reference", read_minutes: 11,
  excerpt: "ISP infrastructure specs. Network requirements, VoIP configuration, TV bundle, equity access program.",
  body: <<~HTML
    <h2>Overview</h2>
    <p>SKU-004 is the most infrastructure-heavy module in the catalog — full ISP capability including VoIP, TV bundling, and no-throttling network access. It requires physical infrastructure setup and is not a same-day deployment.</p>
    <table class="art-table">
      <tr><th>SPEC</th><th>VALUE</th></tr>
      <tr><td>Wholesale price</td><td>$1,800/month</td></tr>
      <tr><td>Deployment time</td><td>Varies — requires infrastructure survey</td></tr>
      <tr><td>Throttling</td><td>None — Constitutional requirement</td></tr>
    </table>
    <div class="art-callout warn"><div class="ac-icon">⚠️</div><div class="ac-body"><div class="acb-label">INFRASTRUCTURE SURVEY REQUIRED</div><div class="acb-text">Because CONNECT deploys physical network infrastructure, deployment timelines depend on your region and existing infrastructure. File a ticket to request a survey before ordering.</div></div></div>
    <h2>Equity Access Program</h2>
    <p>CONNECT includes community equity access — a reduced-cost tier that keeps connectivity affordable for qualifying households, consistent with Article VIII's universal access floor.</p>
  HTML
},
{
  article_id: "mod-wellness", topic: "modules", title: "DYMOND WELLNESS Module — SKU-009",
  article_type: "reference", read_minutes: 6,
  excerpt: "Mental health and wellness platform. Provider directory, Body as Temple protocol, pastoral counseling bridge.",
  body: <<~HTML
    <h2>Overview</h2>
    <p>SKU-009 deploys a wellness platform combining mental health resources, meditation programs, and a faith-integrated fitness pathway called Body as Temple.</p>
    <table class="art-table">
      <tr><th>SPEC</th><th>VALUE</th></tr>
      <tr><td>Wholesale price</td><td>$360/month</td></tr>
      <tr><td>Uptime SLA</td><td>99.99%</td></tr>
    </table>
    <h2>Pastoral Counseling Bridge</h2>
    <p>If a CHURCH module is deployed on the same instance, WELLNESS surfaces a direct booking bridge for pastoral counseling alongside standard mental health provider listings.</p>
    <p>Mood and wellness tracking uses a privacy-first data model — citizen data is never shared across modules without explicit consent.</p>
  HTML
},
{
  article_id: "mod-twin", topic: "modules", title: "DYMOND TWIN Module — SKU-031 (NEW)",
  article_type: "reference", read_minutes: 10,
  excerpt: "Digital twin and avatar OS. Real-to-digital loop, virtual world deployment, AI character generation.",
  body: <<~HTML
    <h2>Overview</h2>
    <p>SKU-031 is the newest module in the catalog — a digital twin and avatar operating system that lets citizens generate and maintain an AI-driven digital counterpart, synced through a real-to-digital feedback loop.</p>
    <div class="art-callout info"><div class="ac-icon">ℹ️</div><div class="ac-body"><div class="acb-label">NEWLY RELEASED</div><div class="acb-text">TWIN is the most recently added module in the catalog. Documentation and best practices are still expanding — file a ticket if you hit something this article doesn't cover.</div></div></div>
    <h2>Real-to-Digital Loop</h2>
    <p>Citizen actions and preferences sync between their real-world profile and their digital twin, keeping the avatar's behavior and knowledge current without manual updates.</p>
    <h2>Virtual World Deployment</h2>
    <p>TWIN avatars can be deployed into virtual environments for events, meetings, or entertainment experiences, with AI character generation handling everything from appearance to conversational behavior.</p>
  HTML
},
# ── DEPLOYMENT & ONBOARDING (deploy-custom-domain already has real content) ──
{
  article_id: "deploy-bank-auth", topic: "deploy", title: "DYMOND BANK Module Authorization",
  article_type: "guide", read_minutes: 6,
  excerpt: "The authorization pathway for Bank module deployments. Government entities, special requirements, approval timeline.",
  body: <<~HTML
    <h2>Overview</h2>
    <p>Every BANK module deployment requires a separate compliance authorization step beyond your standard Lightek order — see the full Bank Module Authorization Stuck troubleshooting guide for what to do if this stalls.</p>
    <h2>Standard Timeline</h2>
    <table class="art-table">
      <tr><th>ORG TYPE</th><th>TYPICAL TIMELINE</th></tr>
      <tr><td>Standard business</td><td>3–5 business days</td></tr>
      <tr><td>Government entity</td><td>7–12 business days</td></tr>
    </table>
    <div class="art-callout info"><div class="ac-icon">ℹ️</div><div class="ac-body"><div class="acb-label">START EARLY</div><div class="acb-text">Submit your KYB documentation as soon as your order is confirmed — authorization runs in parallel with the rest of your deployment, so it doesn't need to block other setup work.</div></div></div>
    <h2>Government Entities</h2>
    <p>Municipal programs and public institutions go through additional compliance review. Have your organization's legal registration and beneficial ownership documentation ready before submitting.</p>
  HTML
},
{
  article_id: "deploy-bulk-import", topic: "deploy", title: "Citizen Bulk Import",
  article_type: "guide", read_minutes: 8,
  excerpt: "Importing existing user data into your deployment. File formats, field mapping, validation errors.",
  body: <<~HTML
    <h2>Overview</h2>
    <p>If you're migrating an existing user base into a new Lightek deployment, bulk import handles the transfer in one pass rather than requiring every citizen to re-register.</p>
    <h2>File Formats</h2>
    <p>Bulk import accepts CSV files with UTF-8 encoding. A template is available in your Reseller Portal under Instance Settings → Citizen Import.</p>
    <div class="art-callout warn"><div class="ac-icon">⚠️</div><div class="ac-body"><div class="acb-label">FIELD MAPPING MATTERS</div><div class="acb-text">Column headers must match the template exactly, or the importer will fail to map fields correctly. Download a fresh template rather than reusing an old export.</div></div></div>
    <h2>Validation Errors</h2>
    <p>Common causes: duplicate email addresses, malformed dates, and missing required fields. The importer reports failed rows individually so you can fix and re-upload just those records — see Citizen Import Errors for a full breakdown.</p>
  HTML
},
{
  article_id: "deploy-ssl", topic: "deploy", title: "SSL Certificate Configuration",
  article_type: "guide", read_minutes: 5,
  excerpt: "Automated SSL via Lightek, custom certificate upload, renewal, and common SSL errors.",
  body: <<~HTML
    <h2>Overview</h2>
    <p>Lightek automatically provisions SSL via Let's Encrypt once your custom domain's DNS is verified — see Setting Up a Custom Domain for the full DNS-to-SSL walkthrough.</p>
    <h2>Renewal</h2>
    <p>Certificates renew automatically 30 days before expiration. No action is needed unless renewal fails, in which case a support ticket is auto-created and you'll receive an email.</p>
    <h2>Custom Certificates</h2>
    <p>If you need an EV certificate or have a corporate PKI requirement, you can upload a custom certificate chain from Instance Settings → SSL. Standard deployments don't need this.</p>
  HTML
},
{
  article_id: "deploy-modules", topic: "deploy", title: "Activating Multiple Modules on One Instance",
  article_type: "guide", read_minutes: 6,
  excerpt: "Adding modules to an existing deployment, module-to-module integration, dependency order.",
  body: <<~HTML
    <h2>Overview</h2>
    <p>Modules can be added to an existing instance at any time — you don't need to redeploy from scratch. Many modules integrate directly with each other once both are active (CHURCH's tithe collection linking to BANK, for example).</p>
    <h2>Dependency Order</h2>
    <p>Some integrations only activate once both modules are live — order doesn't strictly matter, but integrations won't appear until both sides are provisioned.</p>
    <div class="art-callout tip"><div class="ac-icon">✅</div><div class="ac-body"><div class="acb-label">NO DOWNTIME</div><div class="acb-text">Adding a module to an existing instance doesn't interrupt service for citizens already using it.</div></div></div>
  HTML
},
{
  article_id: "deploy-go-live", topic: "deploy", title: "Go-Live Checklist",
  article_type: "guide", read_minutes: 4,
  excerpt: "Everything to verify before opening your deployment to citizens. 24-point checklist, Ministry Engine check.",
  body: <<~HTML
    <h2>Overview</h2>
    <p>Before opening your deployment to citizens, run through the go-live checklist in your Reseller Portal — it verifies branding, domain, SSL, and Ministry Engine status in one pass.</p>
    <table class="art-table">
      <tr><th>CATEGORY</th><th>WHAT'S CHECKED</th></tr>
      <tr><td>Domain & SSL</td><td>Custom domain resolves, certificate active</td></tr>
      <tr><td>Branding</td><td>Logo, colors, naming applied correctly</td></tr>
      <tr><td>Ministry Engine</td><td>All applicable protocols confirmed active</td></tr>
      <tr><td>Modules</td><td>Every ordered module shows ACTIVE status</td></tr>
    </table>
    <div class="art-callout warn"><div class="ac-icon">⚠️</div><div class="ac-body"><div class="acb-label">DON'T SKIP THE MINISTRY ENGINE CHECK</div><div class="acb-text">A deployment that goes live without confirmed Ministry Engine status risks a compliance violation on day one.</div></div></div>
  HTML
},
# ── RESELLER PROGRAM ──
{
  article_id: "res-tiers", topic: "reseller", title: "Reseller Tier Comparison — Associate, Distributor, Master",
  article_type: "reference", read_minutes: 8,
  excerpt: "Full comparison of what each tier includes, access rights, markup ceilings, and upgrade path.",
  body: <<~HTML
    <h2>Overview</h2>
    <p>Lightek's reseller program has three tiers. Each unlocks progressively more catalog access, markup flexibility, and network-building rights.</p>
    <table class="art-table">
      <tr><th>TIER</th><th>CATALOG ACCESS</th><th>CUSTOM DOMAIN</th><th>SUB-RESELLERS</th></tr>
      <tr><td>Associate</td><td>Standard modules</td><td>No — default subdomain</td><td>No</td></tr>
      <tr><td>Distributor</td><td>Full catalog</td><td>Yes</td><td>Yes — build your own network</td></tr>
      <tr><td>Master Partner</td><td>Full catalog + early access</td><td>Yes</td><td>Yes — unlimited depth</td></tr>
    </table>
    <h2>Upgrade Path</h2>
    <p>Tier upgrades are based on deployment volume and certification level. Contact @partnership.dymond to review your account for upgrade eligibility.</p>
  HTML
},
{
  article_id: "res-certification", topic: "reseller", title: "Lightek Certification Process",
  article_type: "guide", read_minutes: 10,
  excerpt: "The 10-day certification program. Training modules, exam format, passing criteria, credential issuance.",
  body: <<~HTML
    <h2>Overview</h2>
    <p>Certification is a 10-day self-paced program covering the module catalog, wholesale pricing, and Ministry Engine fundamentals. It's required before your first order and again for tier upgrades.</p>
    <div class="art-steps">
      <div class="art-step"><div class="as-num">1</div><div class="as-body"><div class="asb-title">Training modules</div><div class="asb-desc">Short video lessons covering catalog navigation, pricing, and compliance basics.</div></div></div>
      <div class="art-step"><div class="as-num">2</div><div class="as-body"><div class="asb-title">Exam</div><div class="asb-desc">A multiple-choice exam covering the training content. Passing score is 80%.</div></div></div>
      <div class="art-step"><div class="as-num">3</div><div class="as-body"><div class="asb-title">Credential issuance</div><div class="asb-desc">Your certification credential unlocks catalog access immediately upon passing.</div></div></div>
    </div>
    <p>You can retake the exam as many times as needed — there's no cooldown period between attempts.</p>
  HTML
},
{
  article_id: "res-sub-resellers", topic: "reseller", title: "Building a Sub-Reseller Network (Distributor+)",
  article_type: "guide", read_minutes: 12,
  excerpt: "How to recruit, certify, and manage Associates beneath you. Override structure, training responsibilities.",
  body: <<~HTML
    <h2>Overview</h2>
    <p>Distributor and Master Partner tiers can recruit Associate resellers into their own network, earning override commissions on everything those Associates sell.</p>
    <h2>Recruiting & Certifying</h2>
    <p>You invite Associates through your Reseller Portal. They complete the same certification process as any reseller, but their account is linked to yours for override tracking.</p>
    <h2>Training Responsibilities</h2>
    <p>While Lightek provides the certification curriculum, Distributors are expected to provide hands-on support to their Associates during onboarding — this is part of what the override commission compensates for.</p>
    <p>See Commission Override Structure Explained for how override earnings are calculated based on network depth.</p>
  HTML
},
{
  article_id: "res-override", topic: "reseller", title: "Commission Override Structure Explained",
  article_type: "reference", read_minutes: 6,
  excerpt: "How override commissions calculate, when they pay out, and how network depth affects your earnings.",
  body: <<~HTML
    <h2>Overview</h2>
    <p>Override commissions let Distributors and Master Partners earn a percentage of every sale made by resellers in their downline network.</p>
    <h2>Calculation</h2>
    <p>Override percentage depends on your tier and the depth of your network. Deeper networks (Master Partner) see smaller per-level percentages but compound across more levels.</p>
    <div class="art-callout info"><div class="ac-icon">ℹ️</div><div class="ac-body"><div class="acb-label">PAYOUT TIMING</div><div class="acb-text">Override commissions pay out on the same cycle as your regular commission statement — see Commission Statements Explained for cutoff and payment dates.</div></div></div>
  HTML
},
{
  article_id: "res-contract", topic: "reseller", title: "Reseller Agreement Terms — Key Clauses",
  article_type: "reference", read_minutes: 9,
  excerpt: "The most important clauses in the Lightek reseller agreement. What you can and cannot do.",
  body: <<~HTML
    <h2>Overview</h2>
    <p>This article summarizes the most-referenced clauses in the Lightek reseller agreement. It's not a substitute for reading the full agreement, but it covers what resellers ask about most.</p>
    <h2>Branding Restrictions</h2>
    <p>You can rebrand your deployment fully, but you cannot represent yourself as DYMOND Empire itself, and cannot use naming that implies you manufacture the modules you're reselling.</p>
    <h2>Territory & Exclusivity</h2>
    <p>Standard reseller agreements are non-exclusive — Lightek can certify other resellers in your market. Territory exclusivity is available at Master Partner tier by separate agreement.</p>
    <div class="art-callout warn"><div class="ac-icon">⚠️</div><div class="ac-body"><div class="acb-label">MINISTRY ENGINE CANNOT BE WAIVED</div><div class="acb-text">No clause in any reseller agreement permits disabling Ministry Engine protocols on a deployment, regardless of tier.</div></div></div>
  HTML
},
# ── BILLING & COMMISSIONS ──
{
  article_id: "bill-invoices", topic: "billing", title: "Understanding Your Invoice",
  article_type: "guide", read_minutes: 5,
  excerpt: "Reading a Lightek invoice. Line items, wholesale vs retail, module SKUs, billing cycle dates.",
  body: <<~HTML
    <h2>Overview</h2>
    <p>Lightek invoices you at wholesale — what you charge your own customers (retail) is entirely up to your markup, and never appears on the Lightek invoice itself.</p>
    <table class="art-table">
      <tr><th>LINE ITEM</th><th>MEANING</th></tr>
      <tr><td>Module SKU + wholesale price</td><td>What you owe Lightek for that module this cycle</td></tr>
      <tr><td>Setup fee (if any)</td><td>One-time deployment cost, first invoice only</td></tr>
      <tr><td>Billing cycle</td><td>Monthly, aligned to your original order date</td></tr>
    </table>
  HTML
},
{
  article_id: "bill-commissions", topic: "billing", title: "Commission Statements Explained",
  article_type: "guide", read_minutes: 7,
  excerpt: "How commission statements are generated, what each column means, cutoff dates vs payment dates.",
  body: <<~HTML
    <h2>Overview</h2>
    <p>If you earn commissions (through overrides or referral programs), your statement is generated monthly and shows every commission-eligible transaction from the prior cutoff period.</p>
    <h2>Cutoff vs Payment Dates</h2>
    <p>The cutoff date determines which transactions land on a given statement. The payment date is typically 15 days after cutoff, giving time for any disputes to be filed before funds move.</p>
    <div class="art-callout info"><div class="ac-icon">ℹ️</div><div class="ac-body"><div class="acb-label">DISPUTE WINDOW</div><div class="acb-text">You have until the payment date to dispute any line on your commission statement — see Disputing a Commission or Invoice for the process.</div></div></div>
  HTML
},
{
  article_id: "bill-override-calc", topic: "billing", title: "Override Commission Calculation",
  article_type: "reference", read_minutes: 5,
  excerpt: "The formula for override commissions at each tier. Example calculations, edge cases.",
  body: <<~HTML
    <h2>Overview</h2>
    <p>Override commissions are calculated as a percentage of your downline's wholesale spend, not their retail revenue — Lightek never has visibility into what you or your network charge customers.</p>
    <h2>Edge Cases</h2>
    <p>If an Associate in your network upgrades tiers mid-cycle, override calculations prorate based on the date of the tier change. Refunded or cancelled orders are excluded from override calculations entirely.</p>
  HTML
},
{
  article_id: "bill-dispute", topic: "billing", title: "Disputing a Commission or Invoice",
  article_type: "guide", read_minutes: 6,
  excerpt: "When to dispute, what documentation to prepare, how to file, and resolution timelines.",
  body: <<~HTML
    <h2>Overview</h2>
    <p>If a line item on an invoice or commission statement looks wrong, file a dispute before the payment date rather than waiting for the next cycle.</p>
    <div class="art-steps">
      <div class="art-step"><div class="as-num">1</div><div class="as-body"><div class="asb-title">Gather documentation</div><div class="asb-desc">Have the invoice or statement number, the specific line item, and what you believe it should be.</div></div></div>
      <div class="art-step"><div class="as-num">2</div><div class="as-body"><div class="asb-title">File a Billing ticket</div><div class="asb-desc">Submit through the support ticket system under the Billing category — response SLA is 24 hours.</div></div></div>
      <div class="art-step"><div class="as-num">3</div><div class="as-body"><div class="asb-title">Resolution</div><div class="asb-desc">Most disputes resolve within 3–5 business days. Confirmed errors are corrected on the same statement or the next one.</div></div></div>
    </div>
  HTML
},
{
  article_id: "bill-payment", topic: "billing", title: "Payment Methods and Net-15 Terms",
  article_type: "reference", read_minutes: 4,
  excerpt: "ACH, wire, DYMOND BANK transfer. What Net-15 means. Late payment policy.",
  body: <<~HTML
    <h2>Overview</h2>
    <p>Lightek invoices are Net-15 by default — payment is due 15 days from the invoice date. ACH, wire transfer, and DYMOND BANK-to-BANK transfer are all accepted.</p>
    <div class="art-callout warn"><div class="ac-icon">⚠️</div><div class="ac-body"><div class="acb-label">LATE PAYMENT</div><div class="acb-text">Invoices unpaid past Net-15 may result in modules entering a grace period, then suspension if payment isn't resolved. File a Billing ticket immediately if you anticipate a delay.</div></div></div>
  HTML
},
# ── MINISTRY ENGINE & COMPLIANCE (min-overview already has real content) ──
{
  article_id: "min-article-vi", topic: "ministry", title: "Article VI — Cultural Attribution Enforcement",
  article_type: "reference", read_minutes: 10,
  excerpt: "The 40% gross revenue attribution requirement. What triggers a violation. The dispute and exile process.",
  body: <<~HTML
    <h2>Overview</h2>
    <p>Article VI requires that creators and cultural contributors receive proper revenue attribution — a minimum 40% gross revenue share where their work generates income on a deployment.</p>
    <h2>What Triggers a Violation</h2>
    <p>Violations are flagged when content is monetized without the required attribution split being configured, most commonly on STREAMING or STUDIO module deployments.</p>
    <div class="art-callout warn"><div class="ac-icon">⚠️</div><div class="ac-body"><div class="acb-label">AUTOMATIC DETECTION</div><div class="acb-text">The Ministry Engine monitors attribution splits automatically — violations aren't manually reported, they're flagged by the system itself.</div></div></div>
    <h2>Dispute and Exile Process</h2>
    <p>A flagged deployment gets a resolution window to correct the attribution split. Deployments that don't resolve within the window face escalating restrictions, up to exile from the platform for repeated violations.</p>
  HTML
},
{
  article_id: "min-article-viii", topic: "ministry", title: "Article VIII — Universal Access Floor",
  article_type: "reference", read_minutes: 8,
  excerpt: "What must remain free for all citizens. Zero-cost tiers, equity lending, digital inclusion requirements.",
  body: <<~HTML
    <h2>Overview</h2>
    <p>Article VIII guarantees a baseline of access that must remain free to qualifying citizens on every deployment, regardless of the reseller's own pricing model.</p>
    <h2>What's Covered</h2>
    <table class="art-table">
      <tr><th>MODULE</th><th>ARTICLE VIII REQUIREMENT</th></tr>
      <tr><td>BANK</td><td>Zero-cost account tier + Community Credit Pool access</td></tr>
      <tr><td>CONNECT</td><td>Equity access program for qualifying households</td></tr>
      <tr><td>INSTITUTE</td><td>Minimum 20% grant seat allocation</td></tr>
    </table>
    <p>This isn't a configuration option — it's built into the module itself at the code level.</p>
  HTML
},
{
  article_id: "min-violations", topic: "ministry", title: "Handling a Ministry Engine Violation Alert",
  article_type: "guide", read_minutes: 7,
  excerpt: "What to do when you receive a violation alert. Response timeline, suspension risk, resolution path.",
  body: <<~HTML
    <h2>Overview</h2>
    <p>A Ministry Engine violation alert means the compliance system has detected a configuration on your deployment that conflicts with a Constitutional Article requirement.</p>
    <div class="art-steps">
      <div class="art-step"><div class="as-num">1</div><div class="as-body"><div class="asb-title">Read the alert carefully</div><div class="asb-desc">It specifies exactly which Article and clause was triggered, and which module.</div></div></div>
      <div class="art-step"><div class="as-num">2</div><div class="as-body"><div class="asb-title">File a Compliance ticket</div><div class="asb-desc">Response SLA for Compliance is 1 hour — this is the fastest-routed category in the support system.</div></div></div>
      <div class="art-step"><div class="as-num">3</div><div class="as-body"><div class="asb-title">Resolve before the window closes</div><div class="asb-desc">Unresolved violations escalate to suspension risk. Most are resolved same-day once flagged.</div></div></div>
    </div>
  HTML
},
{
  article_id: "min-rep-fund", topic: "ministry", title: "Reparations Fund — Article VII Implementation",
  article_type: "reference", read_minutes: 6,
  excerpt: "How the 2% mandatory allocation works. Tracking, disbursements, quarterly reporting.",
  body: <<~HTML
    <h2>Overview</h2>
    <p>Article VII requires a mandatory 2% allocation of qualifying deployment revenue into the Reparations Fund, tracked automatically at the platform level.</p>
    <h2>Tracking & Disbursement</h2>
    <p>The 2% allocation is calculated and set aside automatically — it's not something you configure or opt into. Disbursements from the fund happen on a quarterly basis, governed by the Ministry Engine's oversight process.</p>
    <h2>Quarterly Reporting</h2>
    <p>You can view your deployment's cumulative Reparations Fund contribution from your Reseller Portal under Compliance → Article VII Reporting.</p>
  HTML
},
# ── API & INTEGRATIONS (api-auth already has real content) ──
{
  article_id: "api-webhooks", topic: "api", title: "Webhook Configuration",
  article_type: "guide", read_minutes: 9,
  excerpt: "Setting up event webhooks, payload structure, signature verification, retry behavior.",
  body: <<~HTML
    <h2>Overview</h2>
    <p>Webhooks let your systems receive real-time notifications when events happen on a deployment — a new BANK transfer, a STREAMING upload, a citizen registration.</p>
    <h2>Setup</h2>
    <p>Configure webhook endpoints from your Reseller Portal under Instance Settings → API Access → Webhooks. You can subscribe to specific event types rather than receiving everything.</p>
    <h2>Signature Verification</h2>
    <p>Every webhook payload includes a signature header. Verify it against your webhook secret before trusting the payload — this confirms the request actually came from Lightek.</p>
    <div class="art-callout warn"><div class="ac-icon">⚠️</div><div class="ac-body"><div class="acb-label">RETRY BEHAVIOR</div><div class="acb-text">Failed webhook deliveries retry up to 5 times with exponential backoff. If your endpoint is down longer than that, you'll need to reconcile manually via the API.</div></div></div>
  HTML
},
{
  article_id: "api-bank", topic: "api", title: "Bank Module API Reference",
  article_type: "reference", read_minutes: 18,
  excerpt: "All Bank endpoints. Account creation, balance queries, transfer initiation, ledger access.",
  body: <<~HTML
    <h2>Overview</h2>
    <p>The BANK module API covers account management, balance queries, transfers, and ledger access. All requests require a token scoped to <code style="font-family:var(--fm);color:var(--cyan2);">bank:read</code> or <code style="font-family:var(--fm);color:var(--cyan2);">bank:write</code> — see API Authentication for the scope reference.</p>
    <h2>Core Endpoints</h2>
    <table class="art-table">
      <tr><th>ENDPOINT</th><th>SCOPE</th><th>PURPOSE</th></tr>
      <tr><td>GET /bank/accounts</td><td>bank:read</td><td>List accounts for a citizen</td></tr>
      <tr><td>POST /bank/accounts</td><td>bank:write</td><td>Create a new account</td></tr>
      <tr><td>GET /bank/accounts/:id/balance</td><td>bank:read</td><td>Current balance</td></tr>
      <tr><td>POST /bank/transfers</td><td>bank:write</td><td>Initiate a transfer</td></tr>
      <tr><td>GET /bank/ledger</td><td>bank:read</td><td>Full transaction ledger</td></tr>
    </table>
    <p>All monetary values are returned in cents to avoid floating-point rounding errors.</p>
  HTML
},
{
  article_id: "api-streaming", topic: "api", title: "Streaming Module API Reference",
  article_type: "reference", read_minutes: 14,
  excerpt: "Content ingestion, stream initiation, viewer session management, royalty webhooks.",
  body: <<~HTML
    <h2>Overview</h2>
    <p>The STREAMING module API covers content upload, live stream initiation, viewer session tracking, and royalty event webhooks.</p>
    <table class="art-table">
      <tr><th>ENDPOINT</th><th>PURPOSE</th></tr>
      <tr><td>POST /stream/content</td><td>Upload video content</td></tr>
      <tr><td>POST /stream/live/start</td><td>Initiate a live broadcast</td></tr>
      <tr><td>GET /stream/sessions</td><td>Active viewer session data</td></tr>
    </table>
    <h2>Royalty Webhooks</h2>
    <p>Subscribe to the <code style="font-family:var(--fm);color:var(--cyan2);">royalty.calculated</code> event to receive real-time notification whenever a creator's royalty is calculated from viewership data.</p>
  HTML
},
{
  article_id: "api-errors", topic: "api", title: "API Error Codes — Full Reference",
  article_type: "reference", read_minutes: 8,
  excerpt: "Every HTTP status code and Lightek error code. What each means, common causes, resolution.",
  body: <<~HTML
    <h2>Overview</h2>
    <p>Lightek API errors return a standard HTTP status plus a Lightek-specific error code for more precise diagnosis.</p>
    <table class="art-table">
      <tr><th>STATUS</th><th>LIGHTEK CODE</th><th>MEANING</th></tr>
      <tr><td>401</td><td>AUTH_INVALID</td><td>API key missing or invalid</td></tr>
      <tr><td>403</td><td>SCOPE_INSUFFICIENT</td><td>Key valid but lacks required scope</td></tr>
      <tr><td>404</td><td>RESOURCE_NOT_FOUND</td><td>The requested record doesn't exist</td></tr>
      <tr><td>429</td><td>RATE_LIMITED</td><td>Too many requests — see rate limit headers</td></tr>
      <tr><td>503</td><td>MODULE_UNAVAILABLE</td><td>Target module isn't active on this instance</td></tr>
    </table>
    <div class="art-callout tip"><div class="ac-icon">✅</div><div class="ac-body"><div class="acb-label">RATE LIMIT HEADERS</div><div class="acb-text">Every response includes X-RateLimit-Remaining and X-RateLimit-Reset headers so you can back off before hitting 429s.</div></div></div>
  HTML
},
{
  article_id: "api-sdk", topic: "api", title: "Lightek SDK — Installation and Quickstart",
  article_type: "guide", read_minutes: 10,
  excerpt: "Installing the Lightek SDK, authenticating, making your first call, handling responses.",
  body: <<~HTML
    <h2>Overview</h2>
    <p>The Lightek SDK wraps the raw API with typed methods and automatic retry handling, available for Ruby, Python, and Node.</p>
    <div class="art-code"><span class="code-lang">SHELL</span><button class="code-copy" onclick="this.textContent='✓ COPIED'">COPY</button><pre><span class="cm"># Node</span>
npm install @lightek/sdk

<span class="cm"># Python</span>
pip install lightek-sdk</pre></div>
    <h2>Quickstart</h2>
    <p>Initialize the client with your API key, then call methods directly — the SDK handles token exchange and retries automatically.</p>
    <div class="art-code"><span class="code-lang">JAVASCRIPT</span><button class="code-copy" onclick="this.textContent='✓ COPIED'">COPY</button><pre><span class="kw">const</span> lightek = <span class="kw">new</span> Lightek({ apiKey: <span class="str">process.env.LIGHTEK_KEY</span> });
<span class="kw">const</span> account = <span class="kw">await</span> lightek.bank.accounts.get(<span class="str">'acct_123'</span>);</pre></div>
  HTML
},
# ── TROUBLESHOOTING (tr-bank-auth already has real content) ──
{
  article_id: "tr-custom-domain", topic: "trouble", title: "Custom Domain Not Resolving",
  article_type: "troubleshooting", read_minutes: 6,
  excerpt: "DNS propagation diagnosis, common misconfiguration errors, how to verify SSL is active.",
  body: <<~HTML
    <h2>Overview</h2>
    <p>If your custom domain isn't resolving after setup, the two most common causes are DNS propagation delay and a misconfigured record type.</p>
    <div class="art-callout warn"><div class="ac-icon">⚠️</div><div class="ac-body"><div class="acb-label">COMMON MISTAKE</div><div class="acb-text">Using an A record instead of a CNAME is the #1 cause of domain resolution failure. Lightek deployments use dynamic IPs — always use CNAME.</div></div></div>
    <h2>Diagnosis Steps</h2>
    <div class="art-steps">
      <div class="art-step"><div class="as-num">1</div><div class="as-body"><div class="asb-title">Check propagation</div><div class="asb-desc">Use a DNS propagation checker to confirm your CNAME is live globally, not just from your own location.</div></div></div>
      <div class="art-step"><div class="as-num">2</div><div class="as-body"><div class="asb-title">Verify record value</div><div class="asb-desc">Confirm the CNAME target matches your Lightek endpoint exactly — copy-paste, don't retype.</div></div></div>
      <div class="art-step"><div class="as-num">3</div><div class="as-body"><div class="asb-title">Check SSL status</div><div class="asb-desc">SSL can't provision until DNS is verified — a stuck domain often means SSL is also still pending.</div></div></div>
    </div>
    <p>See Setting Up a Custom Domain for the complete configuration walkthrough.</p>
  HTML
},
{
  article_id: "tr-connect-lag", topic: "trouble", title: "CONNECT Module Response Lag",
  article_type: "troubleshooting", read_minutes: 7,
  excerpt: "Diagnosing ISP handoff timing issues, acceptable latency thresholds, when to file an incident.",
  body: <<~HTML
    <h2>Overview</h2>
    <p>Response lag on a CONNECT deployment usually traces back to the ISP handoff point rather than the Lightek platform itself, since CONNECT bridges to physical network infrastructure.</p>
    <h2>Acceptable Thresholds</h2>
    <table class="art-table">
      <tr><th>METRIC</th><th>ACCEPTABLE RANGE</th></tr>
      <tr><td>Handoff latency</td><td>Under 40ms</td></tr>
      <tr><td>Packet loss</td><td>Under 0.1%</td></tr>
    </table>
    <div class="art-callout info"><div class="ac-icon">ℹ️</div><div class="ac-body"><div class="acb-label">WHEN TO ESCALATE</div><div class="acb-text">If latency consistently exceeds the threshold for more than 15 minutes, file a Technical support ticket with your instance ID and a timestamp range.</div></div></div>
  HTML
},
{
  article_id: "tr-login", topic: "trouble", title: "Reseller Portal Login Issues",
  article_type: "troubleshooting", read_minutes: 4,
  excerpt: "2FA problems, session expiration, account lockout, SSO configuration.",
  body: <<~HTML
    <h2>Overview</h2>
    <p>Most login issues fall into one of three categories: 2FA delivery failure, expired sessions, or account lockout from repeated failed attempts.</p>
    <table class="art-table">
      <tr><th>ISSUE</th><th>FIX</th></tr>
      <tr><td>2FA code not arriving</td><td>Check spam folder; request a new code after 60 seconds</td></tr>
      <tr><td>Session keeps expiring</td><td>Sessions expire after 30 days of inactivity — sign in again</td></tr>
      <tr><td>Account locked</td><td>Locks clear automatically after 15 minutes, or file a ticket for immediate unlock</td></tr>
    </table>
  HTML
},
{
  article_id: "tr-import", topic: "trouble", title: "Citizen Import Errors",
  article_type: "troubleshooting", read_minutes: 8,
  excerpt: "Common CSV validation errors, field format requirements, duplicate handling, partial import recovery.",
  body: <<~HTML
    <h2>Overview</h2>
    <p>Bulk citizen imports validate every row before committing — malformed rows are rejected individually rather than failing the entire import.</p>
    <h2>Common Errors</h2>
    <table class="art-table">
      <tr><th>ERROR</th><th>CAUSE</th></tr>
      <tr><td>DUPLICATE_EMAIL</td><td>Email already exists on this instance</td></tr>
      <tr><td>INVALID_DATE_FORMAT</td><td>Dates must be YYYY-MM-DD</td></tr>
      <tr><td>MISSING_REQUIRED_FIELD</td><td>A required column was left blank</td></tr>
    </table>
    <h2>Partial Import Recovery</h2>
    <p>Successful rows commit even if others fail. Download the error report, fix just the failed rows, and re-upload only those — no need to redo the entire file.</p>
  HTML
},
{
  article_id: "tr-performance", topic: "trouble", title: "Instance Performance Degradation",
  article_type: "troubleshooting", read_minutes: 9,
  excerpt: "Diagnosing slow response times, CDN configuration, cache invalidation, when to escalate.",
  body: <<~HTML
    <h2>Overview</h2>
    <p>Slow response times are most often a CDN caching issue rather than a core platform problem, especially right after a branding or content update.</p>
    <div class="art-steps">
      <div class="art-step"><div class="as-num">1</div><div class="as-body"><div class="asb-title">Check recent changes</div><div class="asb-desc">Branding or content updates can take a few minutes to propagate through the CDN.</div></div></div>
      <div class="art-step"><div class="as-num">2</div><div class="as-body"><div class="asb-title">Force cache invalidation</div><div class="asb-desc">From Instance Settings → Performance, trigger a manual cache purge if degradation persists past 10 minutes.</div></div></div>
      <div class="art-step"><div class="as-num">3</div><div class="as-body"><div class="asb-title">Escalate if unresolved</div><div class="asb-desc">If performance doesn't recover after a cache purge, file a Technical ticket with the timeframe and affected pages.</div></div></div>
    </div>
  HTML
},
].freeze

ARTICLES.each do |row|
  topic = DymondKb::Topic.find_by!(topic_id: row[:topic]) 
  a = DymondKb::Article.find_or_initialize_by(article_id: row[:article_id])
  a.assign_attributes(
    topic: topic, title: row[:title], article_type: row[:article_type],
    excerpt: row[:excerpt], body: row[:body], read_minutes: row[:read_minutes],
    featured: %w[start-first-deploy tr-bank-auth deploy-custom-domain].include?(row[:article_id])
  )
  a.save!
  puts "article: #{a.article_id}"
end

puts ""
puts "Total topics: #{DymondKb::Topic.count}"
puts "Total articles: #{DymondKb::Article.count}"
RUBY_SEED_EOF

echo ""
echo "Done. Next:"
echo "  cd ~/Desktop/Development/dymond_kb"
echo "  git init && git add -A && git commit -m 'Real Knowledge Base — 8 topics, 45 articles, real design'"
echo "  Create the GitHub repo first: github.com/lightekmcg/dymond_kb"
echo "  git remote add origin git@github.com:lightekmcg/dymond_kb.git"
echo "  git push -u origin master"
echo ""
echo "  cd ~/Desktop/Development/lightekmcg-site"
echo "  bundle install"
echo "  bin/rails db:migrate"
echo "  bin/rails runner /tmp/seed_kb.rb"
echo "  rm -rf tmp/cache/bootsnap*"
echo "  bin/rails server"
echo ""
echo "Visit /kb (public) and the Knowledge Base tab in /dashboard"
