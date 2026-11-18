import React, {useEffect,useState} from 'react';
import {Download, Globe, Send} from 'lucide-react';
import {progressLabel,requestKey} from './api';
import {Preview} from './create';

const tiktokSettings = [
  ['disable_comment','Disable comments'],['disable_duet','Disable duets'],['disable_stitch','Disable stitches'],
  ['brand_content_toggle','Branded content'],['brand_organic_toggle','Promotes my own brand'],['is_aigc','Contains AI-generated content']
];
const ticker = status => (status || '').replace(/_/g,' ');

export function Publish({api,project,scene,active,clips,operations,publications,selected,onSelect,timeline,save,run,busy,refresh}) {
  const [accounts,setAccounts]=useState(null);
  const [accountError,setAccountError]=useState('');
  const [choices,setChoices]=useState({});
  const [options,setOptions]=useState(null);
  const [tiktok,setTiktok]=useState({});
  const [caption,setCaption]=useState('');
  const [date,setDate]=useState('');
  const [reviewed,setReviewed]=useState(false);
  const [youtubeConsent,setYoutubeConsent]=useState(false);
  const [youtubeKids,setYoutubeKids]=useState('');
  const [receipts,setReceipts]=useState({});
  const [quote,setQuote]=useState(null);
  const [quoteSource,setQuoteSource]=useState('timeline');
  const [keys,setKeys]=useState({});
  const [preparation,setPreparation]=useState(null);
  const completed=operations.filter(item=>item.status==='completed'&&item.scene_id===scene.id);
  const videoArtifacts=operation=>operation.artifacts.filter(artifact=>artifact.kind==='video'&&artifact.filename.toLowerCase().endsWith('.mp4'))
    .map(artifact=>({...artifact,id:'render-'+artifact.id,artifact_id:artifact.id,kind:'video',proxy_url:artifact.url,
      metadata:operation.output,name:operation.campaign_draft?'Campaign draft':artifact.filename,campaign:operation.campaign_draft}));
  const rendered=completed.filter(item=>!item.social_source&&(!item.draft_preview||(!api.dashboard&&item.campaign_draft))).flatMap(videoArtifacts);
  const videos=[...rendered.filter(item=>item.campaign),...clips.filter(item=>item.kind==='video'&&item.status==='ready'&&item.proxy_url),...rendered.filter(item=>!item.campaign)];
  const intended=operations.find(item=>item.scene_id===scene.id&&item.social_source);
  const asset=videos.find(item=>item.id===selected) || videos.find(item=>String(item.id)===intended?.social_source) || videos[0];
  const selection=asset?.id;
  const dimensions=asset?.metadata;
  const needsCrop=!api.dashboard&&asset&&(asset.campaign||Number(dimensions?.width)*16!==Number(dimensions?.height)*9);
  const crop=operations.find(item=>item.scene_id===scene.id&&item.social_source===String(selection));
  const deliver=needsCrop ? (crop?.status==='completed'?videoArtifacts(crop)[0]:null) : asset;
  const cropQuote=crop?.status==='awaiting_payment'?crop:preparation?.selection===selection&&preparation.status==='awaiting_payment'?preparation:null;
  const channels=accounts?.connections || [];
  const ytReceipt=publications.find(row=>row.id===receipts.youtube?.publication_id);
  const marks=Object.keys(choices).filter(provider=>choices[provider]);
  const tiktokComplete=!choices.tiktok || (options&&tiktok.privacy_level&&tiktokSettings.every(([option])=>tiktok[option]!==undefined));
  const fingerprint=JSON.stringify(timeline);
  const canPublish=deliver&&marks.length&&reviewed===deliver.id&&tiktokComplete&&(!choices.youtube||(youtubeConsent&&(api.dashboard||youtubeKids!=='')));

  useEffect(()=>{
    let alive=true;
    api.call('social.accounts',{project_id:project.id}).then(value=>{if(alive)setAccounts(value);}).catch(error=>{if(alive)setAccountError(error.message);});
    return ()=>{alive=false;};
  },[api,project.id]);

  useEffect(()=>{
    if (!choices.tiktok) return;
    let alive=true;
    setOptions(null);
    api.call('social.options',{project_id:project.id,connection_id:Number(choices.tiktok)}).then(({options:result})=>{
      if(!alive)return;
      setOptions(result);
      setTiktok(Object.fromEntries(['comment','duet','stitch'].filter(name=>result[name+'_disabled']).map(name=>['disable_'+name,true])));
      setAccountError('');
    }).catch(error=>{if(alive)setAccountError(error.message);});
    return ()=>{alive=false;};
  },[api,project.id,choices.tiktok]);

  const cropStatus=crop?.status;
  const cropId=crop?.id;
  const sourceArtifact=asset?.artifact_id;
  useEffect(()=>{
    if(!active||!needsCrop||cropId)return;
    let alive=true,timer;
    async function prepare(){
      try {
        const input=sourceArtifact?{source_artifact_id:sourceArtifact}:{source_asset_id:selection};
        const result=await api.call('timeline.quote',{scene_id:scene.id,social_prepare:true,...input});
        if(!alive)return;
        setPreparation({...result,selection});
        if(result.status==='failed')throw Error('The source clip needs attention in the Media Library.');
        if(!result.operation_id)timer=setTimeout(prepare,4000);
        else refresh();
      } catch(problem){if(alive)setPreparation({selection,error:problem.message});}
    }
    prepare();
    return ()=>{alive=false;clearTimeout(timer);};
  },[active,api,cropId,needsCrop,scene.id,selection,sourceArtifact,refresh]);

  async function pay(operationId){
    const checkout=await api.call('render.checkout',{operation_id:operationId});
    location.assign(checkout.checkout_url);
  }

  function revise(){
    setReviewed(null);setYoutubeConsent(false);setKeys({});
  }

  async function publish() {
    const publishAt=date?new Date(date).toISOString():undefined;
    if(date&&new Date(date).getTime()<=Date.now())throw Error('Choose a future publishing time.');
    const nextKeys={...keys};
    marks.forEach(channel=>{nextKeys[channel] ||= requestKey();});
    setKeys(nextKeys);
    await Promise.all(marks.map(async channel=>{
      const payload={
        scene_id:scene.id, project_id:project.id,request_key:nextKeys[channel],
        platform:channel==='youtube'?'lightek_social':channel,
        title:asset.name,content:caption,audience:'everyone',reviewed:true,
        ...(channel==='youtube'?{youtube_preparation:true,...(api.dashboard?{}:{youtube_consent:true,youtube_made_for_kids:youtubeKids==='true',publish_at:publishAt})}:{connection_id:Number(choices[channel]),publish_at:publishAt}),
        ...(channel==='tiktok'?{tiktok_settings:tiktok}:{})
      };
      try {
        const result=await api.call(deliver.artifact_id?'artifact.publish':'asset.publish',{
          ...payload,...(deliver.artifact_id?{artifact_id:deliver.artifact_id}:{asset_id:deliver.id})
        });
        setReceipts(previous=>({...previous,[channel]:result}));
      } catch(error) {
        setReceipts(previous=>({...previous,[channel]:{error:error.message}}));
      }
    }));
    await refresh();
  }

  async function price() {
    const kind=quoteSource;
    if(kind==='timeline') await save();
    const action=kind==='scene'?'render.quote':'timeline.quote';
    const input=kind==='scene'?{output:'movie'}:kind==='portrait'?{source_asset_id:asset.id}:{};
    const result=await api.call(action,{scene_id:scene.id,...input});
    setQuote({...result,kind,fingerprint,selection});
  }

  function statusOf(channel) {
    const receipt=receipts[channel];
    if(!receipt)return '';
    if(receipt.error)return receipt.error;
    const row=publications.find(item=>item.id===receipt.publication_id);
    return row?.error || ticker(row?.youtube_status || row?.status || receipt.status);
  }

  const youtubeOrigin=accounts?.youtube_origin;
  const youtubeUrl=ytReceipt?.post_id&&!ytReceipt.youtube_submitted&&youtubeOrigin ? new URL('/lightek/index.html#/youtube/'+ytReceipt.post_id,youtubeOrigin).href : null;

  return <div className="ls-publish">
    <div className="ls-row ls-section-title"><h2>Multi-Platform Social Publisher</h2><span>{accounts ? channels.length+' connected accounts' : 'Checking connected accounts…'}</span></div>
    {accountError&&<p role="alert" className="ls-error">{accountError}</p>}
    <div className="ls-publish-grid">
      <form className="ls-card ls-compose" onSubmit={event=>{event.preventDefault();run(publish);}}>
        <strong>Target channels</strong>
        {[[ 'tiktok','TikTok'],['instagram','Instagram Reels']].map(([provider,label])=>{
          const rows=channels.filter(account=>account.provider===provider);
          return <label key={provider}><span><Globe size={15}/> {label}</span><select aria-label={label} disabled={!rows.length} value={choices[provider] || ''} onChange={event=>{revise();setChoices({...choices,[provider]:event.target.value});}}>
            <option value="">{rows.length?'Skip this channel':'No connected account'}</option>
            {rows.map(row=><option key={row.id} value={row.id}>{row.label}</option>)}
          </select>{statusOf(provider)&&<small role="status">{statusOf(provider)}</small>}</label>;
        })}
        <a href={'/dashboard/agency/social'+(api.site?'?site_id='+encodeURIComponent(api.site):'')}>Manage connected accounts</a>
        <label className="ls-check"><input type="checkbox" disabled={!accounts?.youtube_enabled} checked={!!choices.youtube} onChange={event=>{revise();setChoices({...choices,youtube:event.target.checked});}}/> YouTube Shorts via Lightek</label>
        {!accounts?.youtube_enabled&&<small>YouTube submission is unavailable for this site.</small>}
        {choices.youtube&&<label className="ls-check"><input type="checkbox" checked={youtubeConsent} onChange={event=>setYoutubeConsent(event.target.checked)}/> {api.dashboard?'Publish this clip to the public Lightek feed to prepare it for YouTube.':'I own the distribution rights and authorize public publishing to Lightek and YouTube.'}</label>}
        {choices.youtube&&!api.dashboard&&<label>YouTube audience<select aria-label="YouTube audience" value={youtubeKids} onChange={event=>{setYoutubeKids(event.target.value);revise();}}>
          <option value="">Choose an audience</option><option value="false">Not made for kids</option><option value="true">Made for kids</option>
        </select></label>}
        {statusOf('youtube')&&<small role="status">{api.dashboard?'YouTube preparation':'YouTube'} · {statusOf('youtube')}</small>}
        {youtubeUrl&&<a href={youtubeUrl}>Review and submit to Lightek YouTube</a>}
        {choices.tiktok&&options&&<fieldset><legend>TikTok · {options.creator_nickname || options.creator_username}</legend>
          <label>Privacy<select aria-label="Privacy" required value={tiktok.privacy_level || ''} onChange={event=>{revise();setTiktok({...tiktok,privacy_level:event.target.value});}}><option value="">Choose visibility</option>{(options.privacy_level_options||[]).map(item=><option key={item} value={item}>{ticker(item)}</option>)}</select></label>
          {tiktokSettings.map(([key,label])=><label key={key}>{label}<select aria-label={label} required value={tiktok[key]===undefined?'':String(tiktok[key])} disabled={!!options[key.replace('disable_','')+'_disabled']} onChange={event=>{revise();setTiktok({...tiktok,[key]:event.target.value==='true'});}}><option value="">Choose</option><option value="false">No</option><option value="true">Yes</option></select></label>)}
        </fieldset>}
        <label>Post caption &amp; hashtags<textarea rows="4" maxLength="2200" value={caption} onChange={event=>{revise();setCaption(event.target.value);}}/></label>
        {(choices.tiktok||choices.instagram||(!api.dashboard&&choices.youtube))&&<label>{api.dashboard?'Schedule TikTok and Instagram (optional)':'Schedule publishing (optional)'}<input type="datetime-local" value={date} onChange={event=>{revise();setDate(event.target.value);}}/></label>}
        <label className="ls-check"><input type="checkbox" checked={!!deliver&&reviewed===deliver.id} disabled={!deliver} onChange={event=>setReviewed(event.target.checked?deliver.id:null)}/> I reviewed this clip and its destinations.</label>
        <button className="ls-primary" disabled={!canPublish||busy}><Send size={16}/>{date?'Submit scheduled post':'Submit to selected channels'}</button>
      </form>
      <section className="ls-card"><div className="ls-row"><strong>Publish queue</strong><span>{videos.length} available</span></div>
        <div className="ls-strip">{videos.map(item=><button key={item.id} aria-pressed={item.id===selection} onClick={()=>{revise();setReceipts({});onSelect(item.id);}}>{item.name}</button>)}</div>
        {!asset&&<p>Generate or import a video, or export your timeline.</p>}
        <Preview asset={deliver || asset} title="Video to publish"/>
        {needsCrop&&!deliver&&<p role="status">{preparation?.selection===selection&&preparation.error ? preparation.error : cropStatus==='failed'?'Crop needs attention. Choose the clip again to retry.':cropQuote?'9:16 crop is ready for checkout.':'Preparing 9:16 clip…'}</p>}
        {needsCrop&&cropQuote&&!deliver&&<button onClick={()=>run(()=>pay(cropQuote.operation_id || cropQuote.id))} disabled={busy}>
          Approve crop · {new Intl.NumberFormat(undefined,{style:'currency',currency:cropQuote.quote.currency||'USD'}).format(cropQuote.quote.total_cents/100)}
        </button>}
        {(cropStatus==='failed'||(preparation?.selection===selection&&preparation.error))&&<button disabled={busy} onClick={()=>run(async()=>{
          const input=sourceArtifact?{source_artifact_id:sourceArtifact}:{source_asset_id:selection};
          const result=await api.call('timeline.quote',{scene_id:scene.id,social_prepare:true,...input});
          setPreparation({...result,selection});await refresh();
        })}>Retry clip preparation</button>}
        {deliver&&<a href={deliver.url || deliver.proxy_url} download><Download size={16}/> Download clip</a>}
      </section>
    </div>
    {!!publications.length&&<section className="ls-card"><h3>Publishing activity</h3>
      {publications.map(item=><div className="ls-row" key={item.id}><span>{item.youtube_preparation?'YouTube preparation':ticker(item.platform)} · {ticker(item.youtube_status || item.status)}{item.error?' · '+item.error:''}</span>
        {item.youtube_preparation&&!item.youtube_submitted&&item.post_id&&youtubeOrigin&&item.id!==ytReceipt?.id&&<a href={new URL('/lightek/index.html#/youtube/'+item.post_id,youtubeOrigin).href}>Review and submit to Lightek YouTube</a>}</div>)}
    </section>}
    <section className="ls-card ls-export" id="ls-export"><h3>Export MP4</h3>
      <label>Source<select aria-label="Source" value={quoteSource} onChange={event=>{setQuoteSource(event.target.value);setQuote(null);}}><option value="timeline">Timeline edit</option><option value="scene">Full 3D scene</option><option value="portrait">Selected library clip · 9:16</option></select></label>
      {quoteSource==='portrait'&&(!asset||asset.artifact_id)&&<p>Choose a video from the Media Library to crop it.</p>}
      <button disabled={busy||(quoteSource==='timeline'&&!timeline.clips.length)||(quoteSource==='portrait'&&(!asset||asset.artifact_id))} onClick={()=>run(price)}>Get export price</button>
      {quote&&<div className="ls-row"><span>{new Intl.NumberFormat(undefined,{style:'currency',currency:quote.quote.currency||'USD'}).format(quote.quote.total_cents/100)}</span>
        <button disabled={busy||(quote.kind==='timeline'&&quote.fingerprint!==fingerprint)||(quote.kind==='portrait'&&quote.selection!==selection)} onClick={()=>run(async()=>{location.assign((await api.call('render.checkout',{operation_id:quote.operation_id})).checkout_url);})}>Continue to payment</button></div>}
      {operations.filter(item=>!item.draft_preview&&item.scene_id===scene.id).map(item=><div key={item.id} className="ls-row"><span>{item.output?.fit==='cover'?'9:16 clip':'Studio export'} · {progressLabel(item.status)}</span>
        {item.artifacts.filter(row=>row.kind==='video').map(row=><a key={row.id} href={row.url} download>Download {row.filename}</a>)}</div>)}
    </section>
  </div>;
}
