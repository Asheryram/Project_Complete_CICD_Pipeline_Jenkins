#!/bin/bash

# Jaeger Traffic Simulation Script
# Generates realistic API traffic to create meaningful traces

set -e

# Configuration
APP_URL="http://localhost:5000"
DURATION=300  # 5 minutes
CONCURRENT_USERS=3

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get app server IP from terraform if available
if [ -f "terraform/terraform.tfstate" ]; then
    APP_IP=$(cd terraform && terraform output -raw app_server_public_ip 2>/dev/null || echo "localhost")
    APP_URL="http://$APP_IP:5000"
fi

echo -e "${BLUE}🚀 Starting Jaeger Traffic Simulation${NC}"
echo -e "${YELLOW}Target: $APP_URL${NC}"
echo -e "${YELLOW}Duration: ${DURATION}s with ${CONCURRENT_USERS} concurrent users${NC}"
echo ""

# Function to simulate a user session
simulate_user() {
    local user_id=$1
    local session_start=$(date +%s)
    local session_end=$((session_start + DURATION))
    
    echo -e "${GREEN}👤 User $user_id started${NC}"
    
    while [ $(date +%s) -lt $session_end ]; do
        # Random delay between requests (1-10 seconds)
        sleep $((RANDOM % 10 + 1))
        
        # Random action selection
        action=$((RANDOM % 100))
        
        if [ $action -lt 30 ]; then
            # 30% - Browse homepage
            echo -e "${BLUE}User $user_id: Browsing homepage${NC}"
            curl -s "$APP_URL/" > /dev/null 2>&1 || echo "❌ Homepage failed"
            
        elif [ $action -lt 50 ]; then
            # 20% - Check health/info
            echo -e "${BLUE}User $user_id: Checking system info${NC}"
            curl -s "$APP_URL/health" > /dev/null 2>&1 || echo "❌ Health check failed"
            curl -s "$APP_URL/api/info" > /dev/null 2>&1 || echo "❌ Info API failed"
            
        elif [ $action -lt 70 ]; then
            # 20% - Submit timesheet
            echo -e "${GREEN}User $user_id: Submitting timesheet${NC}"
            curl -s -X POST "$APP_URL/api/timesheets" \
                -H "Content-Type: application/json" \
                -d "{
                    \"name\":\"User$user_id\",
                    \"date\":\"$(date +%Y-%m-%d)\",
                    \"hours\":$((RANDOM % 8 + 1)),
                    \"project\":\"Project$((RANDOM % 5 + 1))\"
                }" > /dev/null 2>&1 || echo "❌ Timesheet submission failed"
                
        elif [ $action -lt 85 ]; then
            # 15% - View timesheets
            echo -e "${BLUE}User $user_id: Viewing timesheets${NC}"
            curl -s "$APP_URL/api/timesheets" > /dev/null 2>&1 || echo "❌ Timesheets view failed"
            
        elif [ $action -lt 95 ]; then
            # 10% - Slow operation
            delay=$((RANDOM % 3000 + 500))
            echo -e "${YELLOW}User $user_id: Slow operation (${delay}ms)${NC}"
            curl -s "$APP_URL/api/test/slow?delay=$delay" > /dev/null 2>&1 || echo "❌ Slow operation failed"
            
        else
            # 5% - Error simulation
            echo -e "${RED}User $user_id: Triggering error${NC}"
            curl -s "$APP_URL/api/test/error" > /dev/null 2>&1 || echo "❌ Error simulation failed"
        fi
    done
    
    echo -e "${GREEN}✅ User $user_id session completed${NC}"
}

# Function to simulate load testing
simulate_load_burst() {
    echo -e "${YELLOW}⚡ Load burst: 20 concurrent requests${NC}"
    for i in {1..20}; do
        curl -s "$APP_URL/api/info" > /dev/null 2>&1 &
    done
    wait
    echo -e "${GREEN}✅ Load burst completed${NC}"
}

# Function to simulate CPU intensive operations
simulate_cpu_load() {
    echo -e "${YELLOW}🔥 CPU load test${NC}"
    for iterations in 1000000 5000000 10000000; do
        echo -e "${BLUE}CPU test: $iterations iterations${NC}"
        curl -s "$APP_URL/api/test/load?iterations=$iterations" > /dev/null 2>&1 &
    done
    wait
    echo -e "${GREEN}✅ CPU load tests completed${NC}"
}

# Start background user sessions
for i in $(seq 1 $CONCURRENT_USERS); do
    simulate_user $i &
done

# Periodic load bursts and CPU tests
burst_interval=60  # Every 60 seconds
next_burst=$(($(date +%s) + burst_interval))
next_cpu_test=$(($(date +%s) + 30))

# Monitor and create periodic load
end_time=$(($(date +%s) + DURATION))
while [ $(date +%s) -lt $end_time ]; do
    current_time=$(date +%s)
    
    # Load burst
    if [ $current_time -ge $next_burst ]; then
        simulate_load_burst &
        next_burst=$((current_time + burst_interval))
    fi
    
    # CPU test
    if [ $current_time -ge $next_cpu_test ]; then
        simulate_cpu_load &
        next_cpu_test=$((current_time + 120))  # Every 2 minutes
    fi
    
    sleep 10
done

# Wait for all background processes
wait

echo ""
echo -e "${GREEN}🎉 Traffic simulation completed!${NC}"
echo -e "${BLUE}📊 Check Jaeger UI for traces:${NC}"

# Try to get monitoring server IP
if [ -f "terraform/terraform.tfstate" ]; then
    MONITORING_IP=$(cd terraform && terraform output -raw monitoring_server_public_ip 2>/dev/null || echo "your-monitoring-server-ip")
    echo -e "${YELLOW}   Jaeger UI: http://$MONITORING_IP:16686${NC}"
else
    echo -e "${YELLOW}   Jaeger UI: http://your-monitoring-server-ip:16686${NC}"
fi

echo -e "${BLUE}🔍 Look for service: timesheet-app${NC}"
echo -e "${BLUE}📈 Traces generated: ~$((DURATION / 3 * CONCURRENT_USERS)) traces${NC}"