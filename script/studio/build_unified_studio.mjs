import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {readFileSync} from 'node:fs';
const root = fileURLToPath(new URL('../../', import.meta.url));
const packages = path.join(root,'vendor/studio-editors');
const {build} = createRequire(path.join(packages,'package.json'))('esbuild');
const notices = ['react','react-dom','scheduler','lucide-react'].map(name =>
  name+'\n'+readFileSync(path.join(packages,'node_modules',name,'LICENSE'),'utf8').trim()
);
await build({
  absWorkingDir:root,entryPoints:['app/javascript/lightek_studio/unified.jsx'],
  banner:{js:'/*!\n'+notices.join('\n\n')+'\n*/'},
  target:['safari14','chrome90','firefox90'],
  bundle:true,minify:true,legalComments:'eof',define:{'process.env.NODE_ENV':'"production"'},
  nodePaths:[path.join(packages,'node_modules')],outfile:'public/lightek/studio-unified.js'
});
