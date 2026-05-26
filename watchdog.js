const{spawn}=require('child_process');const http=require('http');
let p=null;
function start(){p=spawn('bun',['static-server.js'],{cwd:'/home/z/my-project',stdio:'ignore'});}
function check(){http.get('http://localhost:3000/',{timeout:2000},()=>{}).on('error',()=>{if(p)try{p.kill()}catch(e){};start();});}
start();setInterval(check,3000);
