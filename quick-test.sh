#!/bin/bash

# Quick Jaeger Test Script
# Generates immediate traces for testing

# Get app server IP
if [ -f "terraform/terraform.tfstate" ]; then
    APP_IP=$(cd terraform && terraform output -raw app_server_public_ip 2>/dev/null)
    MONITORING_IP=$(cd terraform && terraform output -raw monitoring_server_public_ip 2>/dev/null)
else
    echo "Enter your app server IP:"
    read APP_IP
    echo "Enter your monitoring server IP:"
    read MONITORING_IP
fi

APP_URL="http://$APP_IP:5000"

echo "🚀 Generating traces for Jaeger..."
echo "Target: $APP_URL"

# 1. Basic health checks
echo "📋 Health checks..."
curl -s "$APP_URL/health" > /dev/null
curl -s "$APP_URL/api/info" > /dev/null

# 2. Submit sample timesheets
echo "📝 Creating timesheets..."
for i in {1..5}; do
    curl -s -X POST "$APP_URL/api/timesheets" \
        -H "Content-Type: application/json" \
        -d "{
            \"name\":\"Employee$i\",
            \"date\":\"2024-01-1$i\",
            \"hours\":$((RANDOM % 8 + 1)),
            \"project\":\"Project$((RANDOM % 3 + 1))\"
        }" > /dev/null
done

# 3. View timesheets
echo "👀 Viewing timesheets..."
curl -s "$APP_URL/api/timesheets" > /dev/null

# 4. Generate slow traces
echo "🐌 Slow operations..."
curl -s "$APP_URL/api/test/slow?delay=1000" > /dev/null
curl -s "$APP_URL/api/test/slow?delay=2500" > /dev/null

# 5. Generate error traces
echo "❌ Error simulation..."
curl -s "$APP_URL/api/test/error" > /dev/null

# 6. CPU load test
echo "🔥 CPU load test..."
curl -s "$APP_URL/api/test/load?iterations=2000000" > /dev/null

# 7. Browse homepage
echo "🏠 Homepage visits..."
for i in {1..3}; do
    curl -s "$APP_URL/" > /dev/null
done

echo ""
echo "✅ Traces generated successfully!"
echo "🔍 Check Jaeger UI: http://$MONITORING_IP:16686"
echo "📊 Service: timesheet-app"
echo "⏰ Time range: Last 5 minutes"