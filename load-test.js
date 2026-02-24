#!/usr/bin/env node

const http = require('http');
const https = require('https');

const APP_URL = process.env.APP_URL || 'http://localhost:5000';
const DURATION_MINUTES = parseInt(process.env.DURATION_MINUTES) || 5;
const CONCURRENT_USERS = parseInt(process.env.CONCURRENT_USERS) || 10;

console.log(`🚀 Starting load test against ${APP_URL}`);
console.log(`⏱️  Duration: ${DURATION_MINUTES} minutes`);
console.log(`👥 Concurrent users: ${CONCURRENT_USERS}`);

const stats = {
    requests: 0,
    errors: 0,
    latencies: []
};

// Test scenarios
const scenarios = [
    { path: '/', weight: 40, method: 'GET' },
    { path: '/api/timesheets', weight: 20, method: 'GET' },
    { path: '/api/info', weight: 15, method: 'GET' },
    { path: '/health', weight: 10, method: 'GET' },
    { path: '/api/timesheets', weight: 10, method: 'POST', body: {
        name: 'Load Test User',
        date: new Date().toISOString().split('T')[0],
        hours: Math.floor(Math.random() * 8) + 1,
        project: ['CI/CD Pipeline', 'Web Development', 'DevOps', 'Testing'][Math.floor(Math.random() * 4)]
    }},
    // Error scenarios (5% of traffic)
    { path: '/api/test/error', weight: 3, method: 'GET' },
    // Slow scenarios (2% of traffic)
    { path: '/api/test/slow?delay=500', weight: 2, method: 'GET' }
];

// Build weighted scenario list
const weightedScenarios = [];
scenarios.forEach(scenario => {
    for (let i = 0; i < scenario.weight; i++) {
        weightedScenarios.push(scenario);
    }
});

function makeRequest() {
    const scenario = weightedScenarios[Math.floor(Math.random() * weightedScenarios.length)];
    const url = new URL(scenario.path, APP_URL);
    
    const options = {
        hostname: url.hostname,
        port: url.port || (url.protocol === 'https:' ? 443 : 80),
        path: url.pathname + url.search,
        method: scenario.method,
        headers: {
            'User-Agent': 'LoadTest/1.0',
            'Content-Type': 'application/json'
        }
    };

    const startTime = Date.now();
    const client = url.protocol === 'https:' ? https : http;
    
    const req = client.request(options, (res) => {
        let data = '';
        res.on('data', chunk => data += chunk);
        res.on('end', () => {
            const latency = Date.now() - startTime;
            stats.requests++;
            stats.latencies.push(latency);
            
            if (res.statusCode >= 400) {
                stats.errors++;
            }
            
            if (stats.requests % 100 === 0) {
                const avgLatency = stats.latencies.reduce((a, b) => a + b, 0) / stats.latencies.length;
                const errorRate = (stats.errors / stats.requests * 100).toFixed(2);
                console.log(`📊 Requests: ${stats.requests}, Avg Latency: ${avgLatency.toFixed(0)}ms, Error Rate: ${errorRate}%`);
            }
        });
    });

    req.on('error', (err) => {
        stats.errors++;
        console.error(`❌ Request error: ${err.message}`);
    });

    if (scenario.body) {
        req.write(JSON.stringify(scenario.body));
    }
    
    req.end();
}

function runLoadTest() {
    const endTime = Date.now() + (DURATION_MINUTES * 60 * 1000);
    
    // Start concurrent users
    for (let i = 0; i < CONCURRENT_USERS; i++) {
        const runUser = () => {
            if (Date.now() < endTime) {
                makeRequest();
                // Random delay between 100ms - 2s
                setTimeout(runUser, Math.random() * 1900 + 100);
            }
        };
        setTimeout(runUser, Math.random() * 1000); // Stagger start
    }
    
    // Print final stats
    setTimeout(() => {
        console.log('\n🏁 Load test completed!');
        console.log('📈 Final Statistics:');
        console.log(`   Total Requests: ${stats.requests}`);
        console.log(`   Total Errors: ${stats.errors}`);
        console.log(`   Error Rate: ${(stats.errors / stats.requests * 100).toFixed(2)}%`);
        
        if (stats.latencies.length > 0) {
            stats.latencies.sort((a, b) => a - b);
            const p50 = stats.latencies[Math.floor(stats.latencies.length * 0.5)];
            const p95 = stats.latencies[Math.floor(stats.latencies.length * 0.95)];
            const p99 = stats.latencies[Math.floor(stats.latencies.length * 0.99)];
            const avg = stats.latencies.reduce((a, b) => a + b, 0) / stats.latencies.length;
            
            console.log(`   Avg Latency: ${avg.toFixed(0)}ms`);
            console.log(`   P50 Latency: ${p50}ms`);
            console.log(`   P95 Latency: ${p95}ms`);
            console.log(`   P99 Latency: ${p99}ms`);
        }
        
        console.log('\n🔍 Check your dashboards:');
        console.log('   Grafana: http://localhost:3000');
        console.log('   Jaeger: http://localhost:16686');
        console.log('   Prometheus: http://localhost:9090');
        
    }, DURATION_MINUTES * 60 * 1000 + 1000);
}

runLoadTest();