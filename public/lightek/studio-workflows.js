/* Visible outcomes for the existing Studio authoring and saved preset APIs. */
(() => {
  const ui = window.LightekStudioApp;
  const title = value => String(value ?? '').replaceAll('_', ' ').replace(/\b\w/g, c => c.toUpperCase());
  const bibles = scene => (scene.settings?.blender_presets || []).filter(item =>
    (item.definition?.kind || item.definition?.type) === 'show_bible');
  const lines = (value, prefix = '') => {
    if (value == null || value === '') return [];
    if (Array.isArray(value)) return value.flatMap(item => lines(item, prefix));
    if (typeof value === 'object') return Object.entries(value).flatMap(([key, item]) =>
      ['key', 'kind', 'type', 'version', 'inherits', 'title'].includes(key) ? [] : lines(item, prefix ? `${prefix} / ${title(key)}` : title(key)));
    return [`${prefix}: ${String(value).replaceAll('_', ' ')}`];
  };
  const outline = (scene, bible) => {
    const data = bible.definition;
    const content = data.body || data.config || data;
    return [`SCENE OUTLINE · ${scene.name}`, `Based on ${bible.title || data.title || bible.key}`,
      'Starter outline — develop the action and dialogue before production.', '', ...lines(content)].join('\n');
  };
  let preparedScene = null, bibleSignature = '';
  const prepare = ui.prepare;
  ui.prepare = record => {
    prepare(record);
    const scene = record.scene, applied = bibles(scene), signature = JSON.stringify(applied);
    if (preparedScene !== scene.id || signature !== bibleSignature) {
      preparedScene = scene.id; bibleSignature = signature;
      // Older deployments already saved the resolved bible here. Recover it without reapplying
      // the preset, creating duplicate geometry, or overwriting an author's existing draft.
      if (!STUDIO_WAVE2_STATE.scriptDraft?.trim() && applied.length) {
        STUDIO_WAVE2_STATE.scriptDraft = outline(scene, applied.at(-1));
        STUDIO_WAVE2_STATE.templateSource = applied.at(-1).key;
      }
    }
  };
  const story = ui.story;
  ui.story = (record, mode) => {
    const html = story(record, mode);
    if (mode !== 'script') return html;
    const applied = bibles(record.scene);
    const reference = applied.length ? `<section class="pwa-post" data-show-bible><h3>Applied show bible</h3>${applied.map(item => `<details open><summary>${E(item.title || item.definition.title || item.key)}</summary>${lines(item.definition.body || item.definition.config || item.definition).map(line => `<p>${E(line)}</p>`).join('')}</details>`).join('')}<p>The bible provides creative direction. The editable scene outline below is the starting point for your action and dialogue.</p></section>` : '<p>No show bible applied. Write a scene or choose a show bible from Library → Presets.</p>';
    return reference + html.replace('placeholder="Write the scene…"', 'placeholder="Describe what happens, who speaks, and the camera coverage…"');
  };
  const oldMode = A.studioWorkspaceMode;
  A.studioWorkspaceMode = button => {
    if (button.dataset.mode === 'production') {
      ST.workspaceMode = '3d'; render(1); return;
    }
    return oldMode(button);
  };
  let outcome = null;
  ui.applied = (result, {key, preset, mode, beforeIds = []} = {}) => {
    const record = studioSceneRecord(result.scene_id);
    if (!record) return;
    ui.prepare(record);
    const added = result.object_ids || record.scene.objects.filter(object => object.definition?.json_preset_key === key && !beforeIds.includes(object.id)).map(object => object.id);
    if (added.length) ST.selectedObjectId = added[0];
    const bible = preset && bibles(record.scene).some(item => item.key === key);
    ST.workspaceMode = bible ? 'script' : mode || (result.asset_ids?.length && !added.length ? 'timeline' : '3d');
    outcome = {sceneId: record.scene.id, text: bible ? 'Show bible applied. Its creative direction and starter scene outline are shown below. Save workspace to keep your edits.' : added.length ? `${added.length} scene elements added. See them in the viewport; select a shape to edit its saved properties.` : result.asset_ids?.length ? 'Media added to your timeline. Play preview to see or hear it.' : 'Preset applied. Review the selected element and camera settings; render a draft frame to inspect Blender effects.'};
    // A new application should be framed, rather than using a stale zoom from another object.
    window.dispatchEvent(new CustomEvent('lightek:frame-objects', {detail: {ids: added}}));
    render(1);
    toast(bible ? 'Show bible ready in Script' : 'Library changes ready to inspect');
  };
  const tools = ui.tools;
  ui.tools = record => {
    const html = tools(record);
    // Keep the actual workspace visible above the fold. Advanced controls remain available.
    const marker = html.indexOf('<section class="pwa-post">');
    const controls = marker < 0 ? html : html.slice(0, marker) + `<details class="studio-authoring-options"><summary>Add a preset or render a Blender camera preview</summary>${html.slice(marker)}</details>`;
    return `<section class="pwa-post studio-start-guide"><b>Build your scene</b><p>Add a character or set from <a href="#/studio/library">Library</a> → see it in <button class="btn sm" data-a="studioWorkspaceMode" data-mode="3d">3D Layout</button> → select a visible shape and edit its Inspector → save the element. Use Script for the show bible and scene writing, then render a draft camera frame before exporting.</p><p>Library characters are geometric blocking mannequins. Import a rigged .blend project for a finished character.</p>${outcome?.sceneId === record.scene.id ? `<p role="status" data-studio-outcome>${E(outcome.text)}</p>` : ''}</section>${controls}`;
  };
  const inspector = ui.inspector;
  ui.inspector = scene => {
    const object = studioWorkspaceSelectedObject(scene), d = object?.definition;
    const note = d?.body_part ? `<p class="pwa-empty">Editing ${E(title(d.character_key))} · ${E(d.body_part)}. This shape is highlighted in the viewport. Location moves this part; rotation changes its pose; scale changes its size. Save element to apply the change.</p>` : '';
    return note + inspector(scene);
  };
  const outliner = ui.outliner;
  ui.outliner = scene => {
    if (scene.settings?.native_blender_asset_id) return outliner(scene);
    const groups = new Map();
    for (const object of scene.objects || []) {
      const d = object.definition || {}, key = d.character_key ? `${title(d.character_key)} · mannequin ${d.library_instance || d.preset_instance || ''}` : object.object_type === 'camera' ? 'Cameras' : object.object_type.endsWith('_light') ? 'Lights' : 'Set & objects';
      if (!groups.has(key)) groups.set(key, []);
      groups.get(key).push(object);
    }
    return `<section class="studio-semantic-graph" aria-label="Scene Outliner">${[...groups].map(([key, objects]) => `<details open><summary>${E(key.replace(/ · mannequin .*/, ' · blocking mannequin'))} · ${objects.length}</summary>${objects.map(object => `<button class="btn sm ${Number(ST.selectedObjectId) === object.id ? 'p' : ''}" data-a="studioSelectObject" data-id="${object.id}" aria-pressed="${Number(ST.selectedObjectId) === object.id}">${E(object.definition?.body_part || object.name)}</button>`).join('')}</details>`).join('') || '<p>Your scene is empty. Add a character, set or Blender project from Library.</p>'}</section>`;
  };
})();
