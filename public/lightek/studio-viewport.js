import * as THREE from "./vendor/three/three.module.js";
import {
  OrbitControls
} from "./vendor/three/addons/controls/OrbitControls.js";
import {
  TransformControls
} from "./vendor/three/addons/controls/TransformControls.js";

THREE.Object3D.DEFAULT_UP.set(0, 0, 1);

const cameraMemory = new Map();
const toolMemory = new Map();

let active = null;
let reconcileQueued = false;

const bridge = () =>
  window.LightekStudioViewportBridge || null;

const studioRouteSceneId = () => {
  const match =
    location.hash.match(
      /^#\/studio\/(\d+)/
    );

  return match
    ? Number(match[1])
    : null;
};

const finite = (value, fallback = 0) => {
  const number =
    Number(value);

  return Number.isFinite(number)
    ? number
    : fallback;
};

const vector = (
  definition,
  key,
  fallback
) => {
  const value =
    definition?.[key];

  if (
    !Array.isArray(value) ||
    value.length < 3
  ) {
    return [...fallback];
  }

  return [
    finite(value[0], fallback[0]),
    finite(value[1], fallback[1]),
    finite(value[2], fallback[2])
  ];
};

const round = value =>
  Math.round(
    finite(value) * 1000
  ) / 1000;

const degrees = radians =>
  round(
    THREE.MathUtils.radToDeg(
      radians
    )
  );

const radians = degreesValue =>
  THREE.MathUtils.degToRad(
    finite(degreesValue)
  );

const objectIdFor = object =>
  Number(
    object?.id || 0
  );

const objectTypeFor = object =>
  String(
    object?.object_type ||
    object?.type ||
    "cube"
  );

const objectNameFor = object =>
  String(
    object?.name ||
    `${objectTypeFor(object)} ${objectIdFor(object)}`
  );

const materialFor = type => {
  const colors = {
    cube: 0x4f8bc9,
    sphere: 0x3fa77a,
    cylinder: 0xb387d6,
    plane: 0x7f8995,
    camera: 0xd6a94a,
    point_light: 0xf1cc58,
    sun_light: 0xf49b45,
    area_light: 0xe37b68
  };

  return new THREE.MeshStandardMaterial({
    color:
      colors[type] ||
      0x72849a,
    roughness: 0.58,
    metalness: 0.08
  });
};

const markRoot = (
  root,
  object
) => {
  root.userData.sceneObjectId =
    objectIdFor(object);

  root.userData.sceneObjectName =
    objectNameFor(object);

  root.userData.sceneObjectType =
    objectTypeFor(object);

  return root;
};

const cameraObject = object => {
  const root =
    markRoot(
      new THREE.Group(),
      object
    );

  const material =
    materialFor("camera");

  const body =
    new THREE.Mesh(
      new THREE.BoxGeometry(
        0.9,
        0.55,
        0.6
      ),
      material
    );

  const lensGeometry =
    new THREE.CylinderGeometry(
      0.17,
      0.28,
      0.4,
      20
    );

  lensGeometry.rotateX(
    Math.PI / 2
  );

  const lens =
    new THREE.Mesh(
      lensGeometry,
      material.clone()
    );

  lens.position.z = -0.48;

  root.add(
    body,
    lens
  );

  return root;
};

const pointLightObject = object => {
  const root =
    markRoot(
      new THREE.Group(),
      object
    );

  const material =
    materialFor("point_light");

  material.emissive.setHex(
    0x5b470d
  );

  const body =
    new THREE.Mesh(
      new THREE.SphereGeometry(
        0.24,
        20,
        12
      ),
      material
    );

  const light =
    new THREE.PointLight(
      0xffffff,
      1.6,
      14
    );

  root.add(
    body,
    light
  );

  return root;
};

const sunLightObject = object => {
  const root =
    markRoot(
      new THREE.Group(),
      object
    );

  const material =
    materialFor("sun_light");

  material.emissive.setHex(
    0x593611
  );

  const body =
    new THREE.Mesh(
      new THREE.SphereGeometry(
        0.27,
        20,
        12
      ),
      material
    );

  const light =
    new THREE.DirectionalLight(
      0xffffff,
      1.2
    );

  const arrow =
    new THREE.ArrowHelper(
      new THREE.Vector3(
        0,
        0,
        -1
      ),
      new THREE.Vector3(
        0,
        0,
        0
      ),
      1.6,
      0xf49b45,
      0.28,
      0.16
    );

  root.add(
    body,
    light,
    arrow
  );

  return root;
};

const areaLightObject = object => {
  const root =
    markRoot(
      new THREE.Group(),
      object
    );

  const material =
    materialFor("area_light");

  material.emissive.setHex(
    0x49251f
  );

  const panel =
    new THREE.Mesh(
      new THREE.BoxGeometry(
        1.15,
        0.75,
        0.08
      ),
      material
    );

  const light =
    new THREE.PointLight(
      0xffffff,
      1.2,
      10
    );

  light.position.z = -0.25;

  root.add(
    panel,
    light
  );

  return root;
};

const meshObject = object => {
  const type =
    objectTypeFor(object);

  const material =
    materialFor(type);

  let geometry;

  switch (type) {
    case "sphere":
      geometry =
        new THREE.SphereGeometry(
          0.65,
          32,
          18
        );
      break;

    case "cylinder":
      geometry =
        new THREE.CylinderGeometry(
          0.55,
          0.55,
          1.3,
          32
        );

      /*
       * Blender is Z-up.
       * Three's CylinderGeometry
       * is Y-up by default.
       */
      geometry.rotateX(
        Math.PI / 2
      );
      break;

    case "plane":
      /*
       * Give the Blender-style XY
       * plane a little editor thickness
       * so it is easy to see/pick.
       */
      geometry =
        new THREE.BoxGeometry(
          2,
          2,
          0.04
        );
      break;

    case "cube":
    default:
      geometry =
        new THREE.BoxGeometry(
          1,
          1,
          1
        );
      break;
  }

  const mesh =
    new THREE.Mesh(
      geometry,
      material
    );

  mesh.castShadow = true;
  mesh.receiveShadow = true;

  const root =
    markRoot(
      new THREE.Group(),
      object
    );

  root.add(mesh);

  return root;
};

const buildObject = object => {
  const type =
    objectTypeFor(object);

  let root;

  switch (type) {
    case "camera":
      root =
        cameraObject(object);
      break;

    case "point_light":
      root =
        pointLightObject(object);
      break;

    case "sun_light":
      root =
        sunLightObject(object);
      break;

    case "area_light":
      root =
        areaLightObject(object);
      break;

    default:
      root =
        meshObject(object);
      break;
  }

  const definition =
    object?.definition || {};

  const location =
    vector(
      definition,
      "location",
      [0, 0, 0]
    );

  const rotation =
    vector(
      definition,
      "rotation",
      [0, 0, 0]
    );

  const scale =
    vector(
      definition,
      "scale",
      [1, 1, 1]
    );

  root.position.set(
    location[0],
    location[1],
    location[2]
  );

  /*
   * SceneObject rotation values are
   * editor-facing degrees. Three.js
   * stores Euler values in radians.
   */
  root.rotation.order = "XYZ";

  root.rotation.set(
    radians(rotation[0]),
    radians(rotation[1]),
    radians(rotation[2])
  );

  root.scale.set(
    scale[0],
    scale[1],
    scale[2]
  );

  return root;
};

const selectedRoot = state => {
  if (
    !active ||
    !state?.selectedObjectId
  ) {
    return null;
  }

  return active.objects.get(
    Number(
      state.selectedObjectId
    )
  ) || null;
};

const setHighlighted = (
  root,
  selected
) => {
  root.traverse(child => {
    if (
      !child.isMesh ||
      !child.material
    ) {
      return;
    }

    const materials =
      Array.isArray(child.material)
        ? child.material
        : [child.material];

    materials.forEach(material => {
      if (
        !material.userData
          .studioBaseColor
      ) {
        material.userData
          .studioBaseColor =
            material.color
              ?.getHex?.();
      }

      if (
        selected &&
        material.emissive
      ) {
        material.emissive
          .setHex(
            0x4b3607
          );
      } else if (
        material.emissive
      ) {
        material.emissive
          .setHex(
            material.userData
              .studioBaseEmissive ||
            0x000000
          );
      }
    })
  })
};

const updateHighlights = state => {
  if (!active) return;

  active.objects.forEach(
    (root, id) => {
      setHighlighted(
        root,
        Number(id) ===
          Number(
            state?.selectedObjectId
          )
      )
    }
  )
};

const transformPayload = root => ({
  location: [
    round(root.position.x),
    round(root.position.y),
    round(root.position.z)
  ],

  rotation: [
    degrees(root.rotation.x),
    degrees(root.rotation.y),
    degrees(root.rotation.z)
  ],

  scale: [
    round(root.scale.x),
    round(root.scale.y),
    round(root.scale.z)
  ]
});

const syncInspector = root => {
  if (!root) return;

  const payload =
    transformPayload(root);

  const values = {
    Location:
      payload.location,

    Rotation:
      payload.rotation,

    Scale:
      payload.scale
  };

  document
    .querySelectorAll(
      ".studio-axis-group"
    )
    .forEach(group => {
      const heading =
        group.querySelector(
          ":scope > span"
        )?.textContent?.trim();

      const next =
        values[heading];

      if (!next) return;

      group
        .querySelectorAll(
          "input"
        )
        .forEach(
          (input, index) => {
            if (
              index < 3 &&
              document.activeElement !==
                input
            ) {
              input.value =
                String(
                  next[index]
                )
            }
          }
        )
    })
};

const statusFor = (
  state,
  mode
) => {
  if (!active) return;

  const root =
    selectedRoot(state);

  const status =
    active.status;

  if (!root) {
    status.textContent =
      "Select an object in the viewport or Scene graph.";
    return;
  }

  const data =
    transformPayload(root);

  status.textContent =
    `${root.userData.sceneObjectName} · ` +
    `${mode.toUpperCase()} · ` +
    `X ${data.location[0]} · ` +
    `Y ${data.location[1]} · ` +
    `Z ${data.location[2]}`
};

const rememberCamera = () => {
  if (!active) return;

  cameraMemory.set(
    active.sceneId,
    {
      position:
        active.camera.position
          .toArray(),

      target:
        active.orbit.target
          .toArray()
    }
  )
};

const restoreCamera = () => {
  if (!active) return;

  const memory =
    cameraMemory.get(
      active.sceneId
    );

  if (memory) {
    active.camera.position
      .fromArray(
        memory.position
      );

    active.orbit.target
      .fromArray(
        memory.target
      );

    active.orbit.update();

    return
  }

  active.camera.position.set(
    8,
    -10,
    8
  );

  active.orbit.target.set(
    0,
    0,
    0
  );

  active.orbit.update()
};

const frameObject = root => {
  if (
    !active ||
    !root
  ) {
    return
  }

  const box =
    new THREE.Box3()
      .setFromObject(root);

  const size =
    new THREE.Vector3();

  const center =
    new THREE.Vector3();

  box.getSize(size);
  box.getCenter(center);

  const radius =
    Math.max(
      size.length(),
      1.5
    );

  const direction =
    active.camera.position
      .clone()
      .sub(
        active.orbit.target
      )
      .normalize();

  if (
    direction.lengthSq() <
    0.001
  ) {
    direction.set(
      1,
      -1,
      0.7
    ).normalize()
  }

  const destination =
    center
      .clone()
      .add(
        direction.multiplyScalar(
          radius * 2.3
        )
      );

  const current = {
    px:
      active.camera.position.x,
    py:
      active.camera.position.y,
    pz:
      active.camera.position.z,

    tx:
      active.orbit.target.x,
    ty:
      active.orbit.target.y,
    tz:
      active.orbit.target.z
  };

  const apply = () => {
    if (!active) return;

    active.camera.position.set(
      current.px,
      current.py,
      current.pz
    );

    active.orbit.target.set(
      current.tx,
      current.ty,
      current.tz
    );

    active.orbit.update();
    rememberCamera()
  };

  active.cameraTween
    ?.kill?.();

  if (window.gsap) {
    active.cameraTween =
      window.gsap.to(
        current,
        {
          px:
            destination.x,
          py:
            destination.y,
          pz:
            destination.z,

          tx:
            center.x,
          ty:
            center.y,
          tz:
            center.z,

          duration: 0.42,
          ease: "power2.out",
          overwrite: true,
          onUpdate: apply
        }
      );

    return
  }

  current.px =
    destination.x;
  current.py =
    destination.y;
  current.pz =
    destination.z;

  current.tx =
    center.x;
  current.ty =
    center.y;
  current.tz =
    center.z;

  apply()
};

const resolveObjectId = object => {
  let current = object;

  while (current) {
    if (
      current.userData
        ?.sceneObjectId
    ) {
      return Number(
        current.userData
          .sceneObjectId
      )
    }

    current =
      current.parent
  }

  return null
};

const applyTool = (
  mode,
  state
) => {
  if (!active) return;

  const allowed =
    new Set([
      "select",
      "move",
      "rotate",
      "scale"
    ]);

  const next =
    allowed.has(mode)
      ? mode
      : "select";

  active.mode = next;

  toolMemory.set(
    active.sceneId,
    next
  );

  active.toolbar
    .querySelectorAll(
      "[data-studio-tool]"
    )
    .forEach(button => {
      button.classList.toggle(
        "on",
        button.dataset
          .studioTool === next
      )
    });

  const root =
    selectedRoot(state);

  if (
    next === "select" ||
    !root
  ) {
    active.transform.detach();

    statusFor(
      state,
      next
    );

    return
  }

  active.transform.attach(
    root
  );

  active.transform.setMode(
    next === "move"
      ? "translate"
      : next
  );

  active.transform.setSpace(
    next === "scale"
      ? "local"
      : "world"
  );

  statusFor(
    state,
    next
  )
};

const persistTransform = async () => {
  if (
    !active ||
    active.persisting
  ) {
    return
  }

  const state =
    bridge()?.snapshot?.();

  const root =
    selectedRoot(state);

  if (!root) return;

  active.persisting = true;

  rememberCamera();

  const payload =
    transformPayload(root);

  syncInspector(root);

  if (
    active.status
  ) {
    active.status.textContent =
      `${root.userData.sceneObjectName} · saving through Nevaeh…`
  }

  try {
    await bridge()
      ?.commitTransform?.(
        root.userData
          .sceneObjectId,
        payload
      );

    if(active){
      const current=
        bridge()?.snapshot?.();

      const selected=
        selectedRoot(
          current
        );

      syncInspector(
        selected
      );

      active.status.textContent =
        `${root.userData.sceneObjectName} · Saved`;

      clearTimeout(
        active.savedStatusTimer
      );

      const savedSceneId=
        active.sceneId;

      active.savedStatusTimer=
        setTimeout(
          ()=>{
            if(
              !active ||
              Number(active.sceneId)!==
                Number(savedSceneId)
            ){
              return
            }

            statusFor(
              bridge()?.snapshot?.(),
              active.mode
            )
          },
          700
        )
    }
  } catch (error) {
    console.error(
      "[Lightek Studio] viewport transform failed",
      error
    );

    if (
      active?.status
    ) {
      active.status.textContent =
        error?.message ||
        "Transform could not be saved."
    }
  } finally {
    if (active) {
      active.persisting = false
    }
  }
};

const selectFromViewport = id => {
  const state =
    bridge()?.snapshot?.();

  if (
    Number(
      state?.selectedObjectId
    ) ===
    Number(id)
  ) {
    return
  }

  rememberCamera();

  bridge()
    ?.selectObject?.(
      id
    )
};

const pointerToNdc = event => {
  const rect =
    active.renderer.domElement
      .getBoundingClientRect();

  return new THREE.Vector2(
    (
      (
        event.clientX -
        rect.left
      ) /
      rect.width
    ) * 2 - 1,

    -(
      (
        event.clientY -
        rect.top
      ) /
      rect.height
    ) * 2 + 1
  )
};

const installPicking = () => {
  const canvas =
    active.renderer.domElement;

  const raycaster =
    new THREE.Raycaster();

  let start = null;

  canvas.addEventListener(
    "pointerdown",
    event => {
      start = {
        x:
          event.clientX,
        y:
          event.clientY
      }
    }
  );

  canvas.addEventListener(
    "pointerup",
    event => {
      if (
        !start ||
        active?.transform
          ?.dragging
      ) {
        start = null;
        return
      }

      const distance =
        Math.hypot(
          event.clientX -
            start.x,
          event.clientY -
            start.y
        );

      start = null;

      if (distance > 5) return;

      raycaster.setFromCamera(
        pointerToNdc(event),
        active.camera
      );

      const hits =
        raycaster.intersectObjects(
          active.pickables,
          true
        );

      for (const hit of hits) {
        const id =
          resolveObjectId(
            hit.object
          );

        if (id) {
          selectFromViewport(id);
          break
        }
      }
    }
  )
};

const installToolbar = state => {
  active.toolbar
    .querySelectorAll(
      "[data-studio-tool]"
    )
    .forEach(button => {
      button.addEventListener(
        "click",
        () => {
          applyTool(
            button.dataset
              .studioTool,
            bridge()
              ?.snapshot?.()
          )
        }
      )
    });

  active.toolbar
    .querySelector(
      "[data-studio-frame]"
    )
    ?.addEventListener(
      "click",
      () => {
        const current =
          bridge()
            ?.snapshot?.();

        frameObject(
          selectedRoot(current)
        )
      }
    );

  active.canvasHost
    .addEventListener(
      "keydown",
      event => {
        const key =
          event.key
            .toLowerCase();

        const map = {
          q: "select",
          w: "move",
          e: "rotate",
          r: "scale"
        };

        if (map[key]) {
          event.preventDefault();

          applyTool(
            map[key],
            bridge()
              ?.snapshot?.()
          );

          return
        }

        if (key === "f") {
          event.preventDefault();

          frameObject(
            selectedRoot(
              bridge()
                ?.snapshot?.()
            )
          )
        }
      }
    );

  applyTool(
    toolMemory.get(
      active.sceneId
    ) || "select",
    state
  )
};

const createViewportDom = (
  grid,
  state
) => {
  const shell =
    document.createElement(
      "section"
    );

  shell.className =
    "studio-live-layout";

  shell.dataset
    .studioViewportMounted =
      "true";

  shell.innerHTML = `
    <div class="studio-viewport">
      <div class="studio-viewport-toolbar">
        <div class="studio-viewport-tools">
          <button
            type="button"
            data-studio-tool="select"
            title="Select / orbit (Q)"
          >
            Select
          </button>

          <button
            type="button"
            data-studio-tool="move"
            title="Move (W)"
          >
            Move
          </button>

          <button
            type="button"
            data-studio-tool="rotate"
            title="Rotate (E)"
          >
            Rotate
          </button>

          <button
            type="button"
            data-studio-tool="scale"
            title="Scale (R)"
          >
            Scale
          </button>

          <span class="studio-viewport-divider"></span>

          <button
            type="button"
            data-studio-frame
            title="Frame selected (F)"
          >
            Frame
          </button>
        </div>

        <div
          class="studio-viewport-status"
          aria-live="polite"
        ></div>
      </div>

      <div
        class="studio-viewport-canvas"
        tabindex="0"
        aria-label="Lightek Studio 3D viewport"
      ></div>

      <div class="studio-viewport-hint">
        Drag to orbit · right-drag to pan · wheel to zoom ·
        Q Select · W Move · E Rotate · R Scale · F Frame
      </div>
    </div>
  `;

  const panels =
    Array.from(
      grid.children
    );

  const parent =
    grid.parentNode;

  parent.insertBefore(
    shell,
    grid
  );

  const viewport =
    shell.querySelector(
      ".studio-viewport"
    );

  if (
    panels.length === 2
  ) {
    panels[0].classList.add(
      "studio-live-outliner"
    );

    panels[1].classList.add(
      "studio-live-inspector"
    );

    shell.insertBefore(
      panels[0],
      viewport
    );

    shell.appendChild(
      panels[1]
    );

    grid.remove()
  } else {
    shell.classList.add(
      "studio-live-layout-fallback"
    );

    parent.insertBefore(
      grid,
      shell
        .nextSibling
    )
  }

  return {
    shell,

    viewport,

    toolbar:
      shell.querySelector(
        ".studio-viewport-toolbar"
      ),

    status:
      shell.querySelector(
        ".studio-viewport-status"
      ),

    canvasHost:
      shell.querySelector(
        ".studio-viewport-canvas"
      )
  }
};

const mount = (
  grid,
  state
) => {
  destroyActive();

  const dom =
    createViewportDom(
      grid,
      state
    );

  const scene =
    new THREE.Scene();

  scene.background =
    new THREE.Color(
      0x08090d
    );

  const camera =
    new THREE.PerspectiveCamera(
      50,
      1,
      0.05,
      2000
    );

  camera.up.set(
    0,
    0,
    1
  );

  const renderer =
    new THREE.WebGLRenderer({
      antialias: true
    });

  renderer.setPixelRatio(
    Math.min(
      window.devicePixelRatio ||
        1,
      2
    )
  );

  renderer.outputColorSpace =
    THREE.SRGBColorSpace;

  renderer.shadowMap.enabled =
    true;

  dom.canvasHost
    .appendChild(
      renderer.domElement
    );

  const orbit =
    new OrbitControls(
      camera,
      renderer.domElement
    );

  orbit.enableDamping = true;
  orbit.dampingFactor = 0.08;

  const transform =
    new TransformControls(
      camera,
      renderer.domElement
    );

  transform.size = 0.85;

  scene.add(
    transform.getHelper()
  );

  const gridHelper =
    new THREE.GridHelper(
      40,
      40,
      0x38414e,
      0x202630
    );

  /*
   * Three GridHelper is XZ/Y-up.
   * Lightek Studio follows Blender:
   * XY ground plane, Z up.
   */
  gridHelper.rotation.x =
    Math.PI / 2;

  gridHelper.material.opacity =
    0.62;

  gridHelper.material.transparent =
    true;

  scene.add(gridHelper);

  const axes =
    new THREE.AxesHelper(
      3
    );

  scene.add(axes);

  const editorAmbient =
    new THREE.HemisphereLight(
      0xffffff,
      0x121722,
      1.7
    );

  const editorKey =
    new THREE.DirectionalLight(
      0xffffff,
      1.7
    );

  editorKey.position.set(
    6,
    -8,
    10
  );

  scene.add(
    editorAmbient,
    editorKey
  );

  active = {
    ...dom,

    sceneId:
      Number(
        state.sceneId
      ),

    scene,
    camera,
    renderer,
    orbit,
    transform,

    objects:
      new Map(),

    pickables: [],

    mode:
      toolMemory.get(
        Number(
          state.sceneId
        )
      ) || "select",

    persisting:
      false,

    resize:
      null,

    cameraTween:
      null
  };

  restoreCamera();

  (
    state.objects ||
    []
  ).forEach(object => {
    const root =
      buildObject(object);

    active.objects.set(
      objectIdFor(object),
      root
    );

    root.traverse(child => {
      if (child.isMesh) {
        active.pickables.push(
          child
        )
      }
    });

    scene.add(root)
  });

  updateHighlights(state);

  const resize = () => {
    if (!active) return;

    const width =
      Math.max(
        active.canvasHost
          .clientWidth,
        1
      );

    const height =
      Math.max(
        active.canvasHost
          .clientHeight,
        1
      );

    active.camera.aspect =
      width / height;

    active.camera
      .updateProjectionMatrix();

    active.renderer.setSize(
      width,
      height,
      false
    )
  };

  active.resize =
    new ResizeObserver(
      resize
    );

  active.resize.observe(
    dom.canvasHost
  );

  resize();

  orbit.addEventListener(
    "change",
    rememberCamera
  );

  transform.addEventListener(
    "dragging-changed",
    event => {
      orbit.enabled =
        !event.value
    }
  );

  transform.addEventListener(
    "objectChange",
    () => {
      const current =
        bridge()
          ?.snapshot?.();

      const root =
        selectedRoot(current);

      syncInspector(root);

      statusFor(
        current,
        active.mode
      )
    }
  );

  transform.addEventListener(
    "mouseUp",
    () => {
      persistTransform()
    }
  );

  installPicking();
  installToolbar(state);

  const initiallySelected =
    selectedRoot(state);

  if (initiallySelected) {
    syncInspector(
      initiallySelected
    )
  }

  statusFor(
    state,
    active.mode
  );

  renderer.setAnimationLoop(
    () => {
      if (!active) return;

      active.orbit.update();

      active.renderer.render(
        active.scene,
        active.camera
      )
    }
  )
};

function destroyActive() {
  if (!active) return;

  rememberCamera();

  clearTimeout(
    active.savedStatusTimer
  );

  active.cameraTween
    ?.kill?.();

  active.resize
    ?.disconnect?.();

  active.transform
    ?.detach?.();

  active.transform
    ?.dispose?.();

  active.orbit
    ?.dispose?.();

  active.renderer
    ?.setAnimationLoop?.(
      null
    );

  active.renderer
    ?.dispose?.();

  active = null
}

const reconcile = () => {
  const api =
    bridge();

  const routeSceneId =
    studioRouteSceneId();

  const state =
    api?.snapshot?.();

  if (
    !routeSceneId ||
    !state ||
    Number(state.sceneId) !==
      Number(routeSceneId) ||
    state.workspaceMode !==
      "3d"
  ) {
    if (
      active &&
      !active.shell
        ?.isConnected
    ) {
      destroyActive()
    }

    return
  }

  if (
    active &&
    active.shell
      ?.isConnected &&
    Number(active.sceneId) ===
      Number(state.sceneId)
  ) {
    return
  }

  if (
    active &&
    !active.shell
      ?.isConnected
  ) {
    destroyActive()
  }

  const existing =
    document.querySelector(
      "[data-studio-viewport-mounted]"
    );

  if (existing) return;

  const grid =
    document.querySelector(
      ".studio-work-grid"
    );

  if (!grid) return;

  mount(
    grid,
    state
  )
};

const queueReconcile = () => {
  if (reconcileQueued) return;

  reconcileQueued = true;

  requestAnimationFrame(
    () => {
      reconcileQueued = false;
      reconcile()
    }
  )
};

const observer =
  new MutationObserver(
    queueReconcile
  );

observer.observe(
  document.body,
  {
    childList: true,
    subtree: true
  }
);

window.addEventListener(
  "hashchange",
  queueReconcile
);

window.addEventListener(
  "lightek:bootstrap",
  queueReconcile
);

queueReconcile();

console.info(
  "[Lightek Studio] Three.js viewport runtime ready"
);
