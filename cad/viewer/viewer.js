/* Dependency-free display of the exported meshes. No sensor or hardware input. */
'use strict';
(() => {
  const canvas=document.getElementById('view'), error=document.getElementById('error');
  const gl=canvas.getContext('webgl',{antialias:true});
  if(!gl || !window.FEEL_LAYERS){ error.textContent='Run cad/viewer/build.sh first, then open this page in a browser with WebGL.';return; }
  function shader(type,source){const s=gl.createShader(type);gl.shaderSource(s,source);gl.compileShader(s);if(!gl.getShaderParameter(s,gl.COMPILE_STATUS))throw Error(gl.getShaderInfoLog(s));return s;}
  const program=gl.createProgram();
  gl.attachShader(program,shader(gl.VERTEX_SHADER,'attribute vec3 aPosition; attribute vec3 aNormal; uniform mat4 uView; uniform mat4 uProjection; uniform float uLift; varying float shade; void main(){vec3 p=aPosition+vec3(0.,0.,uLift);gl_Position=uProjection*uView*vec4(p,1.);shade=.45+.55*max(dot(normalize(aNormal),normalize(vec3(-.4,-.6,1.))),0.);}'));
  gl.attachShader(program,shader(gl.FRAGMENT_SHADER,'precision mediump float;uniform vec3 uColor;varying float shade;void main(){gl_FragColor=vec4(uColor*shade,1.);}'));
  gl.linkProgram(program);if(!gl.getProgramParameter(program,gl.LINK_STATUS)){error.textContent=gl.getProgramInfoLog(program);return;}gl.useProgram(program);
  const locations={}; for(const n of ['aPosition','aNormal'])locations[n]=gl.getAttribLocation(program,n);
  for(const n of ['uView','uProjection','uLift','uColor'])locations[n]=gl.getUniformLocation(program,n);
  const norm=v=>{const l=Math.hypot(...v)||1;return v.map(x=>x/l);};
  const cross=(a,b)=>[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]];
  const dot=(a,b)=>a.reduce((s,x,i)=>s+x*b[i],0);
  function buffer(values){const b=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,b);gl.bufferData(gl.ARRAY_BUFFER,values,gl.STATIC_DRAW);return b;}
  const meshes=window.FEEL_LAYERS.map(layer=>{
    const bytes=Uint8Array.from(atob(layer.data),c=>c.charCodeAt(0)),v=new Float32Array(bytes.buffer),n=new Float32Array(v.length);
    for(let i=0;i<v.length;i+=9){const a=[v[i+3]-v[i],v[i+4]-v[i+1],v[i+5]-v[i+2]],b=[v[i+6]-v[i],v[i+7]-v[i+1],v[i+8]-v[i+2]],normal=norm(cross(a,b));for(let k=0;k<3;k++)n.set(normal,i+k*3);}
    const item={...layer,positions:buffer(v),normals:buffer(n),count:v.length/3};delete item.data;
    const label=document.createElement('label'),box=document.createElement('input');box.type='checkbox';box.checked=item.visible;box.addEventListener('change',()=>{item.visible=box.checked;draw();});label.append(box,document.createTextNode(' '+item.label));document.getElementById('layers').append(label);return item;
  });
  let yaw=-.8,pitch=.75,zoom=1,lift=0,drag=null;
  function draw(){
    const dpr=Math.min(window.devicePixelRatio||1,2),w=Math.max(1,Math.round(canvas.clientWidth*dpr)),h=Math.max(1,Math.round(canvas.clientHeight*dpr));if(canvas.width!==w||canvas.height!==h){canvas.width=w;canvas.height=h;}
    gl.viewport(0,0,w,h);gl.clearColor(.067,.09,.118,1);gl.clear(gl.COLOR_BUFFER_BIT|gl.DEPTH_BUFFER_BIT);gl.enable(gl.DEPTH_TEST);gl.enable(gl.CULL_FACE);
    const eye=[220*Math.cos(pitch)*Math.cos(yaw),220*Math.cos(pitch)*Math.sin(yaw),220*Math.sin(pitch)],target=[0,8,22+lift*.4];
    const z=norm(eye.map((x,i)=>x-target[i])),x=norm(cross([0,0,1],z)),y=cross(z,x);
    const view=new Float32Array([x[0],y[0],z[0],0,x[1],y[1],z[1],0,x[2],y[2],z[2],0,-dot(x,eye),-dot(y,eye),-dot(z,eye),1]);
    const extent=86/zoom,aspect=w/h,projection=new Float32Array([1/(extent*aspect),0,0,0,0,1/extent,0,0,0,0,-2/1000,0,0,0,-1,1]);
    gl.uniformMatrix4fv(locations.uView,false,view);gl.uniformMatrix4fv(locations.uProjection,false,projection);
    for(const m of meshes){if(!m.visible)continue;for(const [name,b] of [['aPosition',m.positions],['aNormal',m.normals]]){gl.bindBuffer(gl.ARRAY_BUFFER,b);gl.enableVertexAttribArray(locations[name]);gl.vertexAttribPointer(locations[name],3,gl.FLOAT,false,0,0);}gl.uniform1f(locations.uLift,lift*m.explode);gl.uniform3fv(locations.uColor,m.color);gl.drawArrays(gl.TRIANGLES,0,m.count);}
  }
  canvas.addEventListener('pointerdown',e=>{drag=[e.clientX,e.clientY];canvas.setPointerCapture(e.pointerId);});
  canvas.addEventListener('pointermove',e=>{if(!drag)return;yaw-=(e.clientX-drag[0])*.008;pitch=Math.max(.08,Math.min(1.5,pitch+(e.clientY-drag[1])*.008));drag=[e.clientX,e.clientY];draw();});
  canvas.addEventListener('pointerup',()=>{drag=null;});canvas.addEventListener('pointercancel',()=>{drag=null;});
  canvas.addEventListener('wheel',e=>{e.preventDefault();zoom=Math.max(.35,Math.min(4,zoom*Math.exp(-e.deltaY*.001)));draw();},{passive:false});
  document.getElementById('explode').addEventListener('input',e=>{lift=Number(e.target.value);draw();});
  document.getElementById('reset').addEventListener('click',()=>{yaw=-.8;pitch=.75;zoom=1;lift=0;document.getElementById('explode').value='0';draw();});
  new ResizeObserver(draw).observe(canvas);draw();
})();
