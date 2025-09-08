#!/bin/bash

# Test script for fuzzy matching functionality

echo "=== Testing SR Fuzzy Matching ==="

# Setup test environment
TEST_DIR="/tmp/sr_fuzzy_test"
TEST_DATA="$TEST_DIR/.sr"

# Clean up and create test directory
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"

# Create test data with various commands
cat > "$TEST_DATA" << 'EOF'
/tmp/sr_fuzzy_test|git status|5|1234567890
/tmp/sr_fuzzy_test|git commit -m "test"|3|1234567891
/tmp/sr_fuzzy_test|git push origin main|2|1234567892
/tmp/sr_fuzzy_test|npm install|4|1234567893
/tmp/sr_fuzzy_test|npm run build|3|1234567894
/tmp/sr_fuzzy_test|docker build -t app .|2|1234567895
/tmp/sr_fuzzy_test|docker run -p 3000:3000 app|1|1234567896
/tmp/sr_fuzzy_test|python manage.py runserver|3|1234567897
/tmp/sr_fuzzy_test|python -m pytest|2|1234567898
EOF

echo "Test data created:"
cat "$TEST_DATA"
echo ""

# Test cases
echo "=== Test Case 1: Exact Match ==="
_SR_DATA="$TEST_DATA" bash -c 'source /home/alex/autorun/sr.sh && _sr -p "git status"'
echo ""

echo "=== Test Case 2: Partial Match ==="
_SR_DATA="$TEST_DATA" bash -c 'source /home/alex/autorun/sr.sh && _sr -p "git"'
echo ""

echo "=== Test Case 3: Fuzzy Match (typo) ==="
_SR_DATA="$TEST_DATA" bash -c 'source /home/alex/autorun/sr.sh && _sr -p "git statu"'
echo ""

echo "=== Test Case 4: Fuzzy Match (missing letter) ==="
_SR_DATA="$TEST_DATA" bash -c 'source /home/alex/autorun/sr.sh && _sr -p "git stat"'
echo ""

echo "=== Test Case 5: Fuzzy Match (extra letter) ==="
_SR_DATA="$TEST_DATA" bash -c 'source /home/alex/autorun/sr.sh && _sr -p "git statuss"'
echo ""

echo "=== Test Case 6: Different command ==="
_SR_DATA="$TEST_DATA" bash -c 'source /home/alex/autorun/sr.sh && _sr -p "npm"'
echo ""

echo "=== Test Case 7: Complex fuzzy match ==="
_SR_DATA="$TEST_DATA" bash -c 'source /home/alex/autorun/sr.sh && _sr -p "docker bild"'
echo ""

echo "=== Test Case 8: No match ==="
_SR_DATA="$TEST_DATA" bash -c 'source /home/alex/autorun/sr.sh && _sr -p "nonexistent"'
echo ""

# Clean up
rm -rf "$TEST_DIR"
echo "Test completed!"