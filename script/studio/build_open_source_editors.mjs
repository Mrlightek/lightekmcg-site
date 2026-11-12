// Rebuild locally served upstream code. Run npm ci --prefix vendor/studio-editors first.
import {createRequire} from 'node:module';
import fs from 'node:fs';import path from 'node:path';import os from 'node:os';
import {execFileSync} from 'node:child_process';import {createHash} from 'node:crypto';
const root=path.resolve(path.dirname(new URL(import.meta.url).pathname),'../..');
const require=createRequire(path.join(root,'vendor/studio-editors/package.json'));
const {buildSync}=require('esbuild'),deps=path.join(root,'vendor/studio-editors/node_modules');
const work=process.env.STUDIO_EDITOR_BUILD_ROOT||fs.mkdtempSync(path.join(os.tmpdir(),'lightek-editors-'));
const sources={photo:['viliusle/miniPaint','c9192c15918eb61f7dd89e362cf8065a276b89e9'],video:['moviemasher/moviemasher.js','d87af5622290fdccedeaad2334b2cd16b0d7cd06']};
for(const [kind,[repository,sha]] of Object.entries(sources)){
 const folder=path.join(work,kind);
 if(!fs.existsSync(path.join(folder,'.git'))){fs.mkdirSync(folder,{recursive:true});execFileSync('git',['init','--quiet',folder]);execFileSync('git',['-C',folder,'fetch','--depth','1',`https://github.com/${repository}.git`,sha],{stdio:'inherit'});execFileSync('git',['-C',folder,'checkout','--quiet','FETCH_HEAD']);}
 if(execFileSync('git',['-C',folder,'rev-parse','HEAD'],{encoding:'utf8'}).trim()!==sha)throw Error(`Wrong ${kind} upstream revision`);
}
const destination=path.join(root,'public/lightek/editors'),photo=path.join(work,'photo');
fs.mkdirSync(path.join(destination,'photo'),{recursive:true});fs.mkdirSync(path.join(destination,'video'),{recursive:true});
const copy=(source,target)=>{fs.mkdirSync(path.dirname(target),{recursive:true});fs.copyFileSync(source,target);};
let html=fs.readFileSync(path.join(photo,'index.html'),'utf8').replace('<script src="dist/bundle.js"></script>','<script src="setup.js"></script><script src="editor.js"></script>').replace('miniPaint - image editor','Lightek Photo Studio').replace('href="#">miniPaint</a>','href="#">LIGHTEK</a>').replace(/<meta[^>]+(?:https:\/\/|name="description")[^>]*>/g,'').replace(/<link[^>]+manifest[^>]*>/g,'');
html=html.replace('</head>','<style>.submenu .logo{width:130px;padding:0 8px;background:none;color:#e6bd6a;font-weight:800;font-size:16px;letter-spacing:3px}</style></head>');
fs.writeFileSync(path.join(destination,'photo/index.html'),html);
copy(path.join(root,'app/javascript/studio_editors/photo-setup.js'),path.join(destination,'photo/setup.js'));
// Upstream demo integrations include public API keys. Lightek serves its own
// library and does not ship those credentials or depend on those services.
let photoBundle=fs.readFileSync(path.join(photo,'dist/bundle.js'),'utf8');
photoBundle=photoBundle.replace(/((?:\.google_webfonts_key\s*=|pixabay_key\s*:)\s*)"(?:\\.|[^"])*"(?:\s*\+\s*"(?:\\.|[^"])*")*(?:\.replace\([^)]*\))?/g,'$1""');
fs.writeFileSync(path.join(destination,'photo/editor.js'),photoBundle);
copy(path.join(photo,'dist/bundle.js.LICENSE.txt'),path.join(destination,'photo/bundle.js.LICENSE.txt'));
copy(path.join(photo,'MIT-LICENSE.txt'),path.join(destination,'photo/LICENSE.txt'));
const imageRoot=path.join(photo,'images');
function walk(folder,callback){for(const entry of fs.readdirSync(folder,{withFileTypes:true})){const file=path.join(folder,entry.name);entry.isDirectory()?walk(file,callback):callback(file);}}
walk(imageRoot,file=>{if(file.endsWith('.svg')||['checker.png','transparent.png','favicon.png','color-picker.png'].includes(path.basename(file)))copy(file,path.join(destination,'photo/images',path.relative(imageRoot,file)));});
for(const css of fs.readdirSync(path.join(photo,'src/css'))){if(!css.endsWith('.css'))continue;const content=fs.readFileSync(path.join(photo,'src/css',css),'utf8');for(const match of content.matchAll(/url\(['"]?(images\/[^)'" ]+)/g)){const source=path.join(photo,match[1]);if(fs.existsSync(source))copy(source,path.join(destination,'photo',match[1]));}}
fs.writeFileSync(path.join(destination,'photo/images/logo.svg'),'<svg xmlns="http://www.w3.org/2000/svg" width="150" height="40" viewBox="0 0 150 40"><text x="6" y="28" fill="#e6bd6a" font-family="sans-serif" font-size="22" font-weight="700" letter-spacing="3">LIGHTEK</text></svg>');
const browser=buildSync({absWorkingDir:root,entryPoints:['app/javascript/studio_editors/video.jsx'],bundle:true,mainFields:['module','main'],minify:true,legalComments:'eof',outfile:path.join(destination,'video/editor.js'),nodePaths:[deps],define:{'process.env.NODE_ENV':'"production"'},metafile:true});
const renderer=buildSync({absWorkingDir:root,entryPoints:['lib/studio_editors/render.ts'],bundle:true,platform:'node',minify:true,legalComments:'eof',outfile:path.join(root,'docker/studio-media/movie-render.cjs'),nodePaths:[deps],alias:{'@lightek/moviemasher-renderer':path.join(work,'video/packages/server-express/src/Server/RenderingServer/RenderingProcess/RenderingProcessFactory.ts')},metafile:true});
copy(path.join(deps,'@moviemasher/theme-default/moviemasher.css'),path.join(destination,'video/editor.css'));
copy(path.join(work,'video/LICENSE'),path.join(destination,'video/LICENSE.txt'));
copy(process.env.STUDIO_EDITOR_FONT||'/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',path.join(destination,'video/font.ttf'));
copy(process.env.STUDIO_EDITOR_FONT_LICENSE||'/usr/share/doc/fonts-dejavu-core/copyright',path.join(destination,'video/FONT-LICENSE.txt'));
let notices='Lightek Studio locally serves miniPaint (MIT) and Movie Masher 5.1.1 (MPL-2.0).\nUpstream Source Code Form and licenses:\n'+Object.values(sources).map(([repo,sha])=>`https://github.com/${repo}/tree/${sha}`).join('\n')+'\nLightek integration sources: app/javascript/studio_editors, lib/studio_editors and script/studio/build_open_source_editors.mjs in this repository.\n\n';
const packages=new Set();
for(const input of [...Object.keys(browser.metafile.inputs),...Object.keys(renderer.metafile.inputs)]){
 let folder=path.dirname(path.resolve(root,input));while(folder!==path.dirname(folder)){if(fs.existsSync(path.join(folder,'package.json'))){if(folder.includes('node_modules'))packages.add(folder);break;}folder=path.dirname(folder);}
}
for(const folder of [...packages].sort()){
 const pkg=JSON.parse(fs.readFileSync(path.join(folder,'package.json'),'utf8'));notices+=`\n===== ${pkg.name} ${pkg.version} (${pkg.license||'See upstream'}) =====\n`;
 for(const name of ['LICENSE','LICENSE.txt','LICENSE.md','LICENSE-MIT','LICENSE-MIT.txt','COPYING']){const file=path.join(folder,name);if(fs.existsSync(file)){notices+=fs.readFileSync(file,'utf8')+'\n';break;}}
}
fs.writeFileSync(path.join(destination,'THIRD_PARTY_NOTICES.txt'),notices);
walk(destination,file=>{if(/\.(?:txt|svg|css|html)$/.test(file)){const content=fs.readFileSync(file,'utf8').split(/\r?\n/).map(line=>line.trimEnd()).join('\n').trimEnd()+'\n';fs.writeFileSync(file,content);}});
const files={};walk(destination,file=>{if(!file.endsWith('manifest.json'))files[path.relative(destination,file)]=createHash('sha256').update(fs.readFileSync(file)).digest('hex');});
fs.writeFileSync(path.join(destination,'manifest.json'),JSON.stringify({upstream:sources,files,renderer_sha256:createHash('sha256').update(fs.readFileSync(path.join(root,'docker/studio-media/movie-render.cjs'))).digest('hex')},null,2)+'\n');
console.log(`Built ${Object.keys(files).length} local editor assets. No runtime CDN or npm install is required.`);
