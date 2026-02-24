const http = require('http');

const endpoints = [
  '/',
  '/api/timesheets',
  '/api/test/slow?delay=500',
  '/api/test/error',
  '/health'
];

const baseUrl = process.env.APP_URL || 'http://localhost:5000';

console.log('Testing OpenTelemetry tracing...');

endpoints.forEach((endpoint, i) => {
  setTimeout(() => {
    const url = baseUrl + endpoint;
    console.log(`Testing: ${url}`);
    
    http.get(url, (res) => {
      console.log(`✓ ${endpoint}: ${res.statusCode}`);
    }).on('error', (err) => {
      console.log(`✗ ${endpoint}: ${err.message}`);
    });
  }, i * 1000);
});

console.log('\nAfter running, check Jaeger UI for traces from service "timesheet-app"');