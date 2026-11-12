/* Lightek owns save/leave warnings; keep the embedded editor's settings scoped. */
(() => {
  let settings={};
  try{const raw=document.cookie.split(';').map(value=>value.trim()).find(value=>value.startsWith('config='));if(raw)settings=JSON.parse(raw.slice(7));}catch{}
  settings.exit_confirm=false;settings.enable_autoresize=false;
  document.cookie=`config=${JSON.stringify(settings)};path=/lightek/editors/photo/;SameSite=Lax`;
})();
