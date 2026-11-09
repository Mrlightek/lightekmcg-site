export function text(value,limit=1000){return String(value??'').replace(/<[^>]*>/g,'').replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g,'').slice(0,limit);}
function count(value){const n=Number(value);return value!==undefined&&value!==null&&Number.isSafeInteger(n)&&n>=0?n:null;}
export function tiktokEvent(type,data){const user=data.user||{},name=text(user.nickname||user.uniqueId||user.displayId||'TikTok viewer',80),handle=text(user.uniqueId||user.displayId,80),id=text(data.common?.msgId||data.msgId||'',100);const event={source:'tiktok',type,name,handle,id};
 if(type==='chat')return {...event,text:text(data.comment)};
 if(type==='member')return {...event,viewer_count:count(data.memberCount),text:'Joined the LIVE'};
 if(type==='viewers')return {...event,viewer_count:count(data.viewerCount??data.userCount)};
 if(type==='gift')return {...event,text:'Gift received',gift:text(data.giftDetails?.giftName||data.giftName||data.giftId,80),repeat_count:count(data.repeatCount),repeat_end:data.repeatEnd===true};
 if(type==='like')return {...event,total_likes:count(data.totalLikeCount)};
 if(type==='social')return {...event,text:text(data.displayType||'Social activity',200)};
 return null;
}
export function ssnEvent(payload){const data=payload.data||payload;if(!data||typeof data!=='object'||Array.isArray(data))return null;if(!data.chatname&&!data.chatmessage&&!data.event)return null;
 return {source:'ssn',platform:text(data.type||'social',40),type:data.event?'activity':'chat',name:text(data.chatname||'Viewer',80),handle:text(data.userid||data.chatname,80),id:text(data.id||data.mid,100),text:text(data.chatmessage||data.event)};
}
