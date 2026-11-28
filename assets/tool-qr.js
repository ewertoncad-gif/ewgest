/* QR Code Model 2, version 3-L, byte mode, mask 0. Fixed payload: EWTOOL:UUID.
   No network, tracking, credentials or personal information in label. */
(()=>{
'use strict';
function matrix(id){
 if(typeof id!=='string'||!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id))throw Error('Identificador inválido.');
 const data='EWTOOL:'+id.toLowerCase(),bits=[],put=(v,n)=>{for(let i=n-1;i>=0;i--)bits.push((v>>>i)&1);};
 put(4,4);put(data.length,8);for(const c of data)put(c.charCodeAt(0),8);
 put(0,Math.min(4,440-bits.length));while(bits.length%8)bits.push(0);
 const words=[];for(let i=0;i<bits.length;i+=8)words.push(bits.slice(i,i+8).reduce((a,b)=>a*2+b,0));for(let p=0;words.length<55;p++)words.push(p%2?17:236);
 const mul=(a,b)=>{let z=0;for(let i=7;i>=0;i--){z=(z<<1)^((z>>>7)*285);z^=((b>>>i)&1)*a;}return z;};
 const gen=Array(15).fill(0);gen[14]=1;let root=1;
 for(let i=0;i<15;i++){for(let j=0;j<15;j++){gen[j]=mul(gen[j],root);if(j<14)gen[j]^=gen[j+1];}root=mul(root,2);}
 const rem=Array(15).fill(0);for(const b of words){const k=b^rem.shift();rem.push(0);for(let j=0;j<15;j++)rem[j]^=mul(gen[j],k);}
 const all=words.concat(rem),n=29,m=Array.from({length:n},()=>Array(n).fill(false)),fixed=Array.from({length:n},()=>Array(n).fill(false));
 const set=(x,y,v)=>{if(x>=0&&y>=0&&x<n&&y<n){m[y][x]=!!v;fixed[y][x]=true;}};
 for(let i=0;i<n;i++){set(6,i,i%2===0);set(i,6,i%2===0);}
 for(const [cx,cy] of [[3,3],[n-4,3],[3,n-4]])for(let y=-4;y<=4;y++)for(let x=-4;x<=4;x++){const d=Math.max(Math.abs(x),Math.abs(y));set(cx+x,cy+y,d!==2&&d!==4);}
 for(let y=-2;y<=2;y++)for(let x=-2;x<=2;x++)set(22+x,22+y,Math.max(Math.abs(x),Math.abs(y))!==1);
 const fmt=0x77c4,b=i=>((fmt>>>i)&1)!==0;
 for(let i=0;i<=5;i++)set(8,i,b(i));set(8,7,b(6));set(8,8,b(7));set(7,8,b(8));for(let i=9;i<15;i++)set(14-i,8,b(i));
 for(let i=0;i<8;i++)set(n-1-i,8,b(i));for(let i=8;i<15;i++)set(8,n-15+i,b(i));set(8,n-8,true);
 let pos=0;
 for(let right=n-1;right>=1;right-=2){if(right===6)right=5;for(let k=0;k<n;k++){const y=((right+1)&2)===0?n-1-k:k;for(let j=0;j<2;j++){const x=right-j;if(!fixed[y][x]){const v=pos<all.length*8?((all[pos>>>3]>>>(7-(pos&7)))&1):0;m[y][x]=!!(v^((x+y)%2===0?1:0));pos++;}}}}
 if(pos!==567)throw Error('QR inconsistente.');
 return m;
}
function svg(id){const m=matrix(id);let d='';for(let y=0;y<m.length;y++)for(let x=0;x<m.length;x++)if(m[y][x])d+='M'+(x+4)+' '+(y+4)+'h1v1h-1z';return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 37 37" width="140" height="140" role="img" aria-label="QR Code da ferramenta" shape-rendering="crispEdges"><rect width="37" height="37" fill="white"/><path d="'+d+'" fill="black"/></svg>';}
window.ewToolQR=Object.freeze({matrix,svg});
})();
