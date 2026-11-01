import * as THREE from '../vendor/three/three.module.js';
/** Color and normalized OpenGL depth must come from the same render, camera and RTP frame.
 * The host copies the server projection/view into its Three camera and renders this pass first.
 * A flat video alone cannot supply these depths. Never call with the latest unrelated mask.
 */
export function createServerDepthLayer(){
  const geometry=new THREE.PlaneGeometry(2,2);
  const material=new THREE.ShaderMaterial({depthTest:true,depthWrite:true,toneMapped:false,
    uniforms:{colorFrame:{value:null},depthFrame:{value:null}},
    vertexShader:'varying vec2 frameUV;void main(){frameUV=uv;gl_Position=vec4(position.xy,0.0,1.0);}',
    fragmentShader:`uniform sampler2D colorFrame;uniform sampler2D depthFrame;varying vec2 frameUV;
      void main(){vec4 color=texture2D(colorFrame,frameUV);float z=texture2D(depthFrame,frameUV).r;
        if(z<0.0||z>1.0)discard;gl_FragColor=sRGBTransferEOTF(color);gl_FragDepth=z;
        #include <colorspace_fragment>
        }`});
  const mesh=new THREE.Mesh(geometry,material);mesh.frustumCulled=false;mesh.renderOrder=-1000;mesh.visible=false;let color,depth;
  return {mesh,
    update({bitmap,depthValues,width,height,colorFrameId,depthFrameId,camera,projectionMatrix,viewMatrix}){
      if(colorFrameId!==depthFrameId||depthValues.length!==width*height)throw Error('Unmatched server color/depth frame');
      if(depthValues.some(v=>!Number.isFinite(v)||v<0||v>1))throw Error('Invalid normalized server depth');
      color?.image?.close?.();color?.dispose();depth?.dispose();color=new THREE.Texture(bitmap);color.needsUpdate=true;
      depth=new THREE.DataTexture(depthValues,width,height,THREE.RedFormat,THREE.FloatType);depth.needsUpdate=true;depth.flipY=false;
      material.uniforms.colorFrame.value=color;material.uniforms.depthFrame.value=depth;
      camera.projectionMatrix.fromArray(projectionMatrix);camera.projectionMatrixInverse.copy(camera.projectionMatrix).invert();
      camera.matrixWorldInverse.fromArray(viewMatrix);camera.matrixWorld.copy(camera.matrixWorldInverse).invert();camera.matrix.copy(camera.matrixWorld);camera.matrixAutoUpdate=false;mesh.visible=true;
    },hide(){mesh.visible=false;},dispose(){color?.image?.close?.();color?.dispose();depth?.dispose();geometry.dispose();material.dispose();}};
}
