import fs from 'fs';
import path from 'path';
import {execFileSync} from 'child_process';
import {renderingProcessInstance} from '@lightek/moviemasher-renderer';
import {outputDefaultVideo,Defined} from '@moviemasher/moviemasher.js';
if(process.argv[2]==='--health'){console.log('LIGHTEK_MOVIEMASHER_READY=5.1.1');process.exit(0);}
const root=path.resolve(process.argv[2]);
const doc=JSON.parse(fs.readFileSync(path.join(root,'project.json'),'utf8'));
for(const definition of doc.definitions||[]){
  if(!['video','audio'].includes(definition.type))continue;
  const filename=path.join(root,'media',definition.source);
  const info=JSON.parse(execFileSync('ffprobe',['-v','error','-protocol_whitelist','file,pipe','-show_streams','-of','json',filename],{encoding:'utf8',timeout:20000,maxBuffer:1048576}));
  if(!info.streams.some(stream=>stream.codec_type==='audio')){definition.audio=false;delete definition.audioUrl;}
}
const font=Defined.fromId("com.moviemasher.font.default") as any; fs.mkdirSync(path.join(root,"media"),{recursive:true}); fs.copyFileSync("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",path.join(root,"media","font.ttf")); font.source="font.ttf"; font.url=font.source;
const args={mash:doc.mash,definitions:doc.definitions||[],upload:false,outputs:[outputDefaultVideo({width:doc.mash.width||1280,height:doc.mash.height||720,videoRate:doc.mash.quantize||30,options:{...outputDefaultVideo().options,threads:2,filter_complex_threads:1,filter_threads:1}})],temporaryDirectory:path.join(root,'tmp'),cacheDirectory:path.join(root,'cache'),outputDirectory:path.join(root,'output'),filePrefix:path.join(root,'media')+'/',defaultDirectory:'.',validDirectories:[path.join(root,'media')]};
for(const name of ['tmp','cache','output','media'])fs.mkdirSync(path.join(root,name),{recursive:true});
renderingProcessInstance(args).runPromise().then(result=>{if(result.results.some(r=>r.error))throw new Error(JSON.stringify(result));console.log(JSON.stringify(result));}).catch(error=>{console.error(error);process.exitCode=1;});
