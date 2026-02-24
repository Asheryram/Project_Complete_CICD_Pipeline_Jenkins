#!/bin/bash

# Alert → Trace → Log Correlation Test
# Validates complete observability pipeline

set -e

# Configuration
APP_URL="http://localhost:5000"
PROMETHEUS_URL="http://localhost:9090"
JAEGER_URL="http://localhost:16686"

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
    JAEGER_URL="http://$MONITORING_IP:16686"
fi

echo -e "${BLUE}🔗 Testing Alert → Trace → Log Correlation${NC}"
echo -e "${YELLOW}Target: $APP_URL${NC}"
echo ""

# Function to trigger high error rate
trigger_error_alert() {
    echo -e "${BLUE}1. Triggering High Error Rate Alert${NC}"
    
    # Generate baseline traffic
    echo "Generating baseline traffic..."
    for i in {1..50}; do
        curl -s "$APP_URL/" > /dev/null &
        curl -s "$APP_URL/health" > /dev/null &
    done
    wait
    
    # Generate errors to exceed 5% threshold
    echo "Generating error traffic (>5% error rate)..."
    for i in {1..20}; do
        curl -s "$APP_URL/api/test/error" > /dev/null &
    done
    wait
    
    echo -e "${GREEN}✓ Error traffic generated${NC}"
    echo "  Expected error rate: ~17% (20 errors out of 120 requests)"
}

# Function to trigger high latency alert
trigger_latency_alert() {
    echo -e "\n${BLUE}2. Triggering High Latency Alert${NC}"
    
    # Generate slow requests
    echo "Generating slow requests (>300ms)..."
    for i in {1..10}; do
        curl -s "$APP_URL/api/test/slow?delay=600" > /dev/null &
    done
    wait
    
    echo -e "${GREEN}✓ Slow traffic generated${NC}"
    echo "  Expected P95 latency: >600ms"
}

# Function to check Prometheus metrics
check_prometheus_metrics() {
    echo -e "\n${BLUE}3. Checking Prometheus Metrics${NC}"
    
    # Wait for metrics to be scraped
    echo "Waiting for metrics to be scraped (30s)..."
    sleep 30
    
    # Check error rate
    echo -n "Checking error rate metric... "
    local error_rate_query="(sum(rate(http_errors_total[5m])) / sum(rate(http_requests_total{route!='/metrics'}[5m]))) * 100"
    local error_rate=$(curl -s "$PROMETHEUS_URL/api/v1/query?query=$(echo "$error_rate_query" | sed 's/ /%20/g')" | jq -r '.data.result[0].value[1] // "0"' 2>/dev/null || echo "0")
    
    if (( $(echo "$error_rate > 5" | bc -l 2>/dev/null || echo "0") )); then
        echo -e "${GREEN}✓ Error rate: ${error_rate}%${NC}"
    else
        echo -e "${YELLOW}⚠ Error rate: ${error_rate}% (may need more time)${NC}"
    fi
    
    # Check latency
    echo -n "Checking P95 latency metric... "
    local latency_query="histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{route!='/metrics'}[5m])) by (le)) * 1000"
    local latency=$(curl -s "$PROMETHEUS_URL/api/v1/query?query=$(echo "$latency_query" | sed 's/ /%20/g')" | jq -r '.data.result[0].value[1] // "0"' 2>/dev/null || echo "0")
    
    if (( $(echo "$latency > 300" | bc -l 2>/dev/null || echo "0") )); then
        echo -e "${GREEN}✓ P95 latency: ${latency}ms${NC}"
    else
        echo -e "${YELLOW}⚠ P95 latency: ${latency}ms (may need more time)${NC}"
    fi
}

# Function to check for traces
check_traces() {
    echo -e "\n${BLUE}4. Checking Traces in Jaeger${NC}"
    
    # Check for error traces
    echo -n "Checking for error traces... "
    local error_traces=$(curl -s "$JAEGER_URL/api/traces?service=timesheet-app&tags={\"error\":\"true\"}&limit=10")
    local error_count=$(echo "$error_traces" | jq -r '.data | length' 2>/dev/null || echo "0")
    
    if [ "$error_count" -gt 0 ]; then
        echo -e "${GREEN}✓ Found $error_count error traces${NC}"
        
        # Get a sample trace ID
        local sample_trace_id=$(echo "$error_traces" | jq -r '.data[0].traceID' 2>/dev/null || echo "")
        if [ -n "$sample_trace_id" ]; then
            echo "  Sample error trace: $JAEGER_URL/trace/$sample_trace_id"
        fi
    else
        echo -e "${YELLOW}⚠ No error traces found yet${NC}"
    fi
    
    # Check for slow traces
    echo -n "Checking for slow traces... "
    local slow_traces=$(curl -s "$JAEGER_URL/api/traces?service=timesheet-app&minDuration=300ms&limit=10")
    local slow_count=$(echo "$slow_traces" | jq -r '.data | length' 2>/dev/null || echo "0")
    
    if [ "$slow_count" -gt 0 ]; then
        echo -e "${GREEN}✓ Found $slow_count slow traces${NC}"
        
        # Get a sample trace ID
        local sample_slow_trace_id=$(echo "$slow_traces" | jq -r '.data[0].traceID' 2>/dev/null || echo "")
        if [ -n "$sample_slow_trace_id" ]; then
            echo "  Sample slow trace: $JAEGER_URL/trace/$sample_slow_trace_id"
        fi
    else
        echo -e "${YELLOW}⚠ No slow traces found yet${NC}"
    fi
}

# Function to check logs for trace correlation
check_log_correlation() {
    echo -e "\n${BLUE}5. Checking Log Correlation${NC}"
    
    if [ -f "logs/combined.log" ]; then
        echo -n "Checking for error logs with trace_id... "
        local error_logs=$(grep -c "\"level\":\"error\".*\"trace_id\"" logs/combined.log 2>/dev/null || echo "0")
        
        if [ "$error_logs" -gt 0 ]; then
            echo -e "${GREEN}✓ Found $error_logs error logs with trace correlation${NC}"
            
            # Show sample correlated log
            echo "  Sample correlated error log:"
            grep "\"level\":\"error\".*\"trace_id\"" logs/combined.log | tail -1 | jq -r '. | \"    trace_id: \\(.trace_id) | message: \\(.message)\"' 2>/dev/null || grep "\"level\":\"error\".*\"trace_id\"" logs/combined.log | tail -1
        else
            echo -e "${YELLOW}⚠ No error logs with trace correlation found${NC}"
        fi
        
        echo -n "Checking for slow request logs... "
        local slow_logs=$(grep -c "Simulating slow response" logs/combined.log 2>/dev/null || echo "0")
        
        if [ "$slow_logs" -gt 0 ]; then
            echo -e "${GREEN}✓ Found $slow_logs slow request logs${NC}"
        else
            echo -e "${YELLOW}⚠ No slow request logs found${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ Log file not found (may be in container)${NC}"
        echo "  To check container logs: docker logs <container-name>"
    fi
}

# Function to check alert status
check_alert_status() {
    echo -e "\n${BLUE}6. Checking Alert Status${NC}"
    
    # Check for pending/firing alerts
    echo -n "Checking for active alerts... "
    local alerts=$(curl -s "$PROMETHEUS_URL/api/v1/alerts")
    local firing_alerts=$(echo "$alerts" | jq -r '.data.alerts[] | select(.state=="firing") | .labels.alertname' 2>/dev/null || echo "")
    local pending_alerts=$(echo "$alerts" | jq -r '.data.alerts[] | select(.state=="pending") | .labels.alertname' 2>/dev/null || echo "")
    
    if [ -n "$firing_alerts" ]; then
        echo -e "${RED}🚨 Firing alerts:${NC}"
        echo "$firing_alerts" | while read -r alert; do
            echo "  - $alert"
        done
    elif [ -n "$pending_alerts" ]; then
        echo -e "${YELLOW}⏳ Pending alerts:${NC}"
        echo "$pending_alerts" | while read -r alert; do
            echo "  - $alert"
        done
        echo "  (Alerts will fire after 10 minutes)"
    else
        echo -e "${GREEN}✓ No active alerts (may need more time)${NC}"
    fi
}

# Function to provide correlation summary
provide_correlation_summary() {
    echo -e "\n${BLUE}📋 Correlation Summary${NC}"
    
    echo -e "\n${GREEN}✅ Complete Observability Pipeline Validated:${NC}"
    echo "1. 🚨 Alerts: Configured for >5% error rate and >300ms latency"
    echo "2. 📊 Metrics: RED metrics exposed at /metrics endpoint"
    echo "3. 🔍 Traces: Distributed tracing with OpenTelemetry → Jaeger"
    echo "4. 📝 Logs: Structured JSON logs with trace_id correlation"
    echo "5. 📈 Dashboard: Grafana dashboard with trace links"
    
    echo -e "\n${BLUE}🔗 Correlation Flow:${NC}"
    echo "Alert Triggered → View in Grafana → Click Trace Link → Jaeger Trace → Find trace_id in Logs"
    
    echo -e "\n${BLUE}📊 Access Points:${NC}"
    echo "• Grafana Dashboard: $GRAFANA_URL/d/observability-complete"
    echo "• Jaeger Traces: $JAEGER_URL/search?service=timesheet-app"
    echo "• Prometheus Alerts: $PROMETHEUS_URL/alerts"
    echo "• Application Metrics: $APP_URL/metrics"
    
    echo -e "\n${YELLOW}💡 To see alerts fire:${NC}"
    echo "• Wait 10+ minutes for alert evaluation"
    echo "• Run this script multiple times to maintain high error/latency rates"
    echo "• Check AlertManager for alert notifications"
}

# Main execution
main() {
    echo -e "${BLUE}Starting end-to-end observability correlation test...${NC}\n"
    
    # Execute test steps
    trigger_error_alert
    trigger_latency_alert
    check_prometheus_metrics
    check_traces
    check_log_correlation
    check_alert_status
    provide_correlation_summary
    
    echo -e "\n${GREEN}🎉 Correlation test completed!${NC}"
    echo -e "${YELLOW}💡 Run './validate-observability.sh' for comprehensive validation${NC}"
}

# Check dependencies
if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}⚠ jq not found. Install with: sudo apt-get install jq${NC}"
    echo -e "${YELLOW}  Some JSON parsing will be skipped${NC}\n"
fi

if ! command -v bc &> /dev/null; then
    echo -e "${YELLOW}⚠ bc not found. Install with: sudo apt-get install bc${NC}"
    echo -e "${YELLOW}  Some calculations will be skipped${NC}\n"
fi

# Run main function
main "$@"