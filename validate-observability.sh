#!/bin/bash

# Observability Validation Script
# Tests OpenTelemetry, RED metrics, alerts, and trace correlation

set -e

# Configuration
APP_URL="http://localhost:5000"
PROMETHEUS_URL="http://localhost:9090"
GRAFANA_URL="http://localhost:3000"
JAEGER_URL="http://localhost:16686"
ALERTMANAGER_URL="http://localhost:9093"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Get server IPs from terraform if available
if [ -f "terraform/terraform.tfstate" ]; then
    APP_IP=$(cd terraform && terraform output -raw app_server_public_ip 2>/dev/null || echo "localhost")
    MONITORING_IP=$(cd terraform && terraform output -raw monitoring_server_public_ip 2>/dev/null || echo "localhost")
    APP_URL="http://$APP_IP:5000"
    PROMETHEUS_URL="http://$MONITORING_IP:9090"
    GRAFANA_URL="http://$MONITORING_IP:3000"
    JAEGER_URL="http://$MONITORING_IP:16686"
    ALERTMANAGER_URL="http://$MONITORING_IP:9093"
fi

echo -e "${BLUE}🔍 Observability Stack Validation${NC}"
echo -e "${YELLOW}App URL: $APP_URL${NC}"
echo -e "${YELLOW}Monitoring Stack: $MONITORING_IP${NC}"
echo ""

# Function to check service availability
check_service() {
    local name=$1
    local url=$2
    local expected_code=${3:-200}
    
    echo -n "Checking $name... "
    
    # Add timeout and better error handling
    local response_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 --max-time 30 "$url" 2>/dev/null)
    
    # Accept both expected code and common redirect codes for web services
    if [ "$response_code" = "$expected_code" ] || [ "$response_code" = "200" ] || [ "$response_code" = "302" ]; then
        echo -e "${GREEN}✓ Available (HTTP: $response_code)${NC}"
        return 0
    else
        echo -e "${RED}✗ Unavailable (HTTP: $response_code)${NC}"
        # For Prometheus, try alternative endpoints
        if [[ "$name" == "Prometheus" ]]; then
            echo -n "  Trying alternative endpoint... "
            local alt_response=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 15 "$url/-/healthy" 2>/dev/null)
            if [ "$alt_response" = "200" ]; then
                echo -e "${GREEN}✓ Available via /-/healthy${NC}"
                return 0
            else
                echo -e "${RED}✗ Also unavailable (HTTP: $alt_response)${NC}"
            fi
        fi
        return 1
    fi
}

# Function to validate metrics endpoint
validate_metrics() {
    echo -e "\n${BLUE}📊 Validating RED Metrics${NC}"
    
    # Check /metrics endpoint
    echo -n "Checking /metrics endpoint... "
    if curl -s "$APP_URL/metrics" | grep -q "http_request_duration_seconds"; then
        echo -e "${GREEN}✓ Available${NC}"
    else
        echo -e "${RED}✗ Missing${NC}"
        return 1
    fi
    
    # Check specific RED metrics
    local metrics_response=$(curl -s "$APP_URL/metrics")
    
    echo -n "Checking Rate metrics... "
    if echo "$metrics_response" | grep -q "http_requests_total"; then
        echo -e "${GREEN}✓ Found${NC}"
    else
        echo -e "${RED}✗ Missing${NC}"
    fi
    
    echo -n "Checking Error metrics... "
    if echo "$metrics_response" | grep -q "http_errors_total"; then
        echo -e "${GREEN}✓ Found${NC}"
    else
        echo -e "${RED}✗ Missing${NC}"
    fi
    
    echo -n "Checking Duration metrics... "
    if echo "$metrics_response" | grep -q "http_request_duration_seconds"; then
        echo -e "${GREEN}✓ Found${NC}"
    else
        echo -e "${RED}✗ Missing${NC}"
    fi
}

# Function to generate test traffic
generate_test_traffic() {
    echo -e "\n${BLUE}🚀 Generating Test Traffic${NC}"
    
    # Normal requests
    echo "Generating normal traffic..."
    for i in {1..10}; do
        curl -s "$APP_URL/" > /dev/null &
        curl -s "$APP_URL/health" > /dev/null &
        curl -s "$APP_URL/api/info" > /dev/null &
    done
    wait
    
    # Slow requests (should trigger latency alerts if threshold is low)
    echo "Generating slow requests..."
    for i in {1..5}; do
        curl -s "$APP_URL/api/test/slow?delay=500" > /dev/null &
    done
    wait
    
    # Error requests (should trigger error rate alerts)
    echo "Generating error requests..."
    for i in {1..15}; do
        curl -s "$APP_URL/api/test/error" > /dev/null &
    done
    wait
    
    echo -e "${GREEN}✓ Test traffic generated${NC}"
}

# Function to validate traces in Jaeger
validate_traces() {
    echo -e "\n${BLUE}🔍 Validating Distributed Tracing${NC}"
    
    # Check Jaeger API
    echo -n "Checking Jaeger API... "
    if curl -s "$JAEGER_URL/api/services" | grep -q "timesheet-app"; then
        echo -e "${GREEN}✓ Service found in Jaeger${NC}"
    else
        echo -e "${RED}✗ Service not found${NC}"
        return 1
    fi
    
    # Check for recent traces
    echo -n "Checking for recent traces... "
    local traces=$(curl -s "$JAEGER_URL/api/traces?service=timesheet-app&limit=10")
    if echo "$traces" | grep -q "traceID"; then
        echo -e "${GREEN}✓ Traces found${NC}"
        local trace_count=$(echo "$traces" | grep -o "traceID" | wc -l)
        echo "  Found $trace_count recent traces"
    else
        echo -e "${RED}✗ No traces found${NC}"
    fi
}

# Function to validate structured logging
validate_logging() {
    echo -e "\n${BLUE}📝 Validating Structured Logging${NC}"
    
    # Generate a request to create logs
    echo "Generating request to create logs..."
    curl -s "$APP_URL/api/info" > /dev/null
    
    # Check if logs directory exists
    if [ -d "logs" ]; then
        echo -n "Checking log files... "
        if [ -f "logs/combined.log" ]; then
            echo -e "${GREEN}✓ Log files exist${NC}"
            
            # Check for trace_id in logs
            echo -n "Checking for trace_id in logs... "
            if grep -q "trace_id" logs/combined.log 2>/dev/null; then
                echo -e "${GREEN}✓ Trace correlation found${NC}"
                echo "  Sample log entry:"
                tail -1 logs/combined.log | jq -r '. | \"  trace_id: \\(.trace_id // \"none\") | message: \\(.message)\"' 2>/dev/null || tail -1 logs/combined.log
            else
                echo -e "${RED}✗ No trace correlation${NC}"
            echo "  Note: Application is running remotely on $APP_IP"
            echo "  Trace correlation logs are written on the remote server"
            echo "  To verify: SSH to $APP_IP and check application logs"
            fi
        else
            echo -e "${RED}✗ Log files missing${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ Logs directory not found (may be in container)${NC}"
    fi
}

# Function to validate Prometheus metrics
validate_prometheus_metrics() {
    echo -e "\n${BLUE}📈 Validating Prometheus Integration${NC}"
    
    # Check if Prometheus can scrape the app
    echo -n "Checking Prometheus targets... "
    local targets=$(curl -s "$PROMETHEUS_URL/api/v1/targets")
    if echo "$targets" | grep -q "node-app"; then
        echo -e "${GREEN}✓ App target configured${NC}"
        
        # Check target health
        if echo "$targets" | grep -A5 -B5 "node-app" | grep -q '"health":"up"'; then
            echo -e "${GREEN}✓ App target is healthy${NC}"
        else
            echo -e "${RED}✗ App target is down${NC}"
        fi
    else
        echo -e "${RED}✗ App target not found${NC}"
    fi
    
    # Check for specific metrics in Prometheus
    echo -n "Checking RED metrics in Prometheus... "
    local query_result=$(curl -s "$PROMETHEUS_URL/api/v1/query?query=http_requests_total")
    if echo "$query_result" | grep -q '"status":"success"'; then
        echo -e "${GREEN}✓ Metrics available${NC}"
    else
        echo -e "${RED}✗ Metrics not available${NC}"
    fi
}

# Function to validate alerts
validate_alerts() {
    echo -e "\n${BLUE}🚨 Validating Alert Rules${NC}"
    
    # Check Prometheus rules
    echo -n "Checking Prometheus alert rules... "
    local rules=$(curl -s "$PROMETHEUS_URL/api/v1/rules")
    if echo "$rules" | grep -q "HighErrorRate"; then
        echo -e "${GREEN}✓ Alert rules loaded${NC}"
        
        # Check for firing alerts
        echo -n "Checking for active alerts... "
        local alerts=$(curl -s "$PROMETHEUS_URL/api/v1/alerts")
        local firing_count=$(echo "$alerts" | grep -o '"state":"firing"' | wc -l)
        local pending_count=$(echo "$alerts" | grep -o '"state":"pending"' | wc -l)
        
        if [ "$firing_count" -gt 0 ]; then
            echo -e "${RED}⚠ $firing_count alerts firing${NC}"
        elif [ "$pending_count" -gt 0 ]; then
            echo -e "${YELLOW}⚠ $pending_count alerts pending${NC}"
        else
            echo -e "${GREEN}✓ No active alerts${NC}"
        fi
    else
        echo -e "${RED}✗ Alert rules not found${NC}"
    fi
    
    # Check AlertManager with better error handling
    echo -n "Checking AlertManager... "
    local am_response=$(curl -s --connect-timeout 5 --max-time 10 "$ALERTMANAGER_URL/api/v1/status" 2>/dev/null)
    if echo "$am_response" | grep -q "ready"; then
        echo -e "${GREEN}✓ AlertManager ready${NC}"
    else
        echo -e "${RED}✗ AlertManager not ready${NC}"
        echo "  Checking alternative endpoint..."
        local am_health=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$ALERTMANAGER_URL/-/healthy" 2>/dev/null)
        if [ "$am_health" = "200" ]; then
            echo -e "  ${GREEN}✓ AlertManager service is running${NC}"
        else
            echo -e "  ${RED}✗ AlertManager service unavailable (HTTP: $am_health)${NC}"
        fi
    fi
}

# Function to validate Grafana dashboard
validate_grafana() {
    echo -e "\n${BLUE}📊 Validating Grafana Dashboard${NC}"
    
    # Check Grafana health
    echo -n "Checking Grafana health... "
    if curl -s "$GRAFANA_URL/api/health" | grep -q "ok"; then
        echo -e "${GREEN}✓ Grafana healthy${NC}"
        
        # Check for dashboards (requires auth, so just check if endpoint responds)
        echo -n "Checking dashboard endpoint... "
        local dash_response=$(curl -s -o /dev/null -w "%{http_code}" "$GRAFANA_URL/api/dashboards/uid/observability-complete")
        if [ "$dash_response" = "200" ] || [ "$dash_response" = "401" ]; then
            echo -e "${GREEN}✓ Dashboard endpoint accessible${NC}"
        else
            echo -e "${RED}✗ Dashboard endpoint not found${NC}"
        fi
    else
        echo -e "${RED}✗ Grafana not healthy${NC}"
    fi
}

# Function to simulate alert conditions
simulate_alert_conditions() {
    echo -e "\n${BLUE}⚠️  Simulating Alert Conditions${NC}"
    
    echo "Generating high error rate (>5%)..."
    # Generate 100 requests with 10+ errors to trigger >5% error rate
    for i in {1..90}; do
        curl -s "$APP_URL/" > /dev/null &
    done
    for i in {1..20}; do
        curl -s "$APP_URL/api/test/error" > /dev/null &
    done
    wait
    
    echo "Generating high latency requests (>300ms)..."
    for i in {1..10}; do
        curl -s "$APP_URL/api/test/slow?delay=500" > /dev/null &
    done
    wait
    
    echo -e "${YELLOW}⚠ Alert conditions simulated. Check Prometheus/AlertManager in 10+ minutes.${NC}"
}

# Function to debug connectivity issues
debug_connectivity() {
    local url=$1
    local name=$2
    
    echo -e "\n${BLUE}🔍 Debugging $name connectivity${NC}"
    
    # Extract host and port
    local host=$(echo "$url" | sed 's|http://||' | cut -d: -f1)
    local port=$(echo "$url" | sed 's|http://||' | cut -d: -f2 | cut -d/ -f1)
    
    echo "Host: $host, Port: $port"
    
    # Test basic connectivity
    echo -n "Testing basic connectivity... "
    if timeout 5 bash -c "</dev/tcp/$host/$port" 2>/dev/null; then
        echo -e "${GREEN}✓ Port is reachable${NC}"
    else
        echo -e "${RED}✗ Port is not reachable${NC}"
        echo "  This could indicate:"
        echo "  - Service is not running"
        echo "  - Firewall blocking the port"
        echo "  - Network connectivity issues"
        return 1
    fi
    
    # Test HTTP response
    echo -n "Testing HTTP response... "
    local full_response=$(curl -s -i --connect-timeout 5 --max-time 10 "$url" 2>&1)
    if echo "$full_response" | grep -q "HTTP/"; then
        local status_line=$(echo "$full_response" | head -1)
        echo -e "${GREEN}✓ HTTP response received${NC}"
        echo "  Status: $status_line"
    else
        echo -e "${RED}✗ No HTTP response${NC}"
        echo "  Error: $full_response"
    fi
}

# Main validation flow
main() {
    echo -e "${BLUE}Starting comprehensive observability validation...${NC}\n"
    
    # Check service availability
    echo -e "${BLUE}🔧 Service Availability Check${NC}"
    check_service "Application" "$APP_URL"
    check_service "Prometheus" "$PROMETHEUS_URL"
    check_service "Grafana" "$GRAFANA_URL"
    check_service "Jaeger" "$JAEGER_URL"
    check_service "AlertManager" "$ALERTMANAGER_URL"
    
    # Validate components
    validate_metrics
    generate_test_traffic
    sleep 5  # Wait for metrics to be scraped
    validate_traces
    validate_logging
    validate_prometheus_metrics
    validate_alerts
    validate_grafana
    
    # Optional: Simulate alert conditions
    echo -e "\n${YELLOW}Do you want to simulate alert conditions? (y/N)${NC}"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        simulate_alert_conditions
    fi
    
    echo -e "\n${GREEN}🎉 Observability validation completed!${NC}"
    echo -e "\n${BLUE}📋 Summary of URLs:${NC}"
    echo -e "Application:   $APP_URL"
    echo -e "Metrics:       $APP_URL/metrics"
    echo -e "Prometheus:    $PROMETHEUS_URL"
    echo -e "Grafana:       $GRAFANA_URL"
    echo -e "Jaeger:        $JAEGER_URL"
    echo -e "AlertManager:  $ALERTMANAGER_URL"
    
    echo -e "\n${BLUE}🔍 Next Steps:${NC}"
    echo -e "1. Check Grafana dashboard: $GRAFANA_URL/d/observability-complete"
    echo -e "2. View traces in Jaeger: $JAEGER_URL/search?service=timesheet-app"
    echo -e "3. Monitor alerts: $ALERTMANAGER_URL"
    echo -e "4. Run ./simulate-traffic.sh for continuous load testing"
}

# Run main function
main "$@"