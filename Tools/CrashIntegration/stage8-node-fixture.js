'use strict';
// Original local-only Contract A acceptance fixture; no remote requests or credentials.
const http = require('http');
let server;
module.exports = {
  start() {
    return new Promise(resolve => {
      server = http.createServer((request, response) => {
        response.setHeader('Content-Type','application/json');
        if (request.url === '/health') response.end(JSON.stringify({ok:true,name:'CatVodSpiderios'}));
        else if (request.url === '/config') response.end(JSON.stringify({sites:[{key:'nodejs_crash_stage8',name:'Stage 8 Local Node',type:3,api:'/spider/stage8/3',searchable:1}]}));
        else if (request.url.endsWith('/home')) response.end(JSON.stringify({class:[],list:[{vod_id:'local-1',vod_name:'Node lifecycle fixture',vod_remarks:'Original local test'}]}));
        else if (request.url.endsWith('/init')) response.end(JSON.stringify({ok:true}));
        else {response.statusCode=404;response.end(JSON.stringify({error:'fixture-not-found'}));}
      });
      server.listen(0,'127.0.0.1',() => {console.log(`fixture listening http://127.0.0.1:${server.address().port}`);resolve();});
    });
  },
  stop() {return new Promise(resolve => server ? server.close(resolve) : resolve());}
};
