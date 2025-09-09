const http = require('http');

const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ 
    status: 'working',
    url: req.url,
    method: req.method,
    timestamp: new Date().toISOString()
  }));
});

server.listen(3001, '127.0.0.1', () => {
  console.log('Simple test server running on http://127.0.0.1:3001/');
});
