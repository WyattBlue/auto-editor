#!/bin/bash
# Turkish Transcribe Test Script
# This script tests the transcribe command with Turkish content support

set -e

echo "=== Turkish Transcribe Tests ==="
echo ""

# Test 1: Check if transcribe command exists
echo "Test 1: Checking transcribe command..."
if command -v auto-editor &> /dev/null; then
    echo "✓ auto-editor found"
else
    echo "✗ auto-editor not found, building..."
    nimble build -d:release
fi

# Test 2: Test help output
echo ""
echo "Test 2: Testing help output..."
auto-editor transcribe --help > /dev/null 2>&1
echo "✓ Help output works"

# Test 3: Test with test file (without API key - should show error)
echo ""
echo "Test 3: Testing without API key (should show error)..."
if auto-editor transcribe resources/test_turkish.mp3 --language tr 2>&1 | grep -q "API Key required"; then
    echo "✓ Correctly shows API key error"
else
    echo "✗ Did not show expected API key error"
fi

# Test 4: Test provider validation
echo ""
echo "Test 4: Testing invalid provider..."
if auto-editor transcribe resources/test_turkish.mp3 --provider invalid 2>&1 | grep -q "Invalid provider"; then
    echo "✓ Correctly shows invalid provider error"
else
    echo "✗ Did not show expected provider error"
fi

# Test 5: Test format validation
echo ""
echo "Test 5: Testing invalid format..."
if auto-editor transcribe resources/test_turkish.mp3 --format invalid 2>&1 | grep -q "Invalid format"; then
    echo "✓ Correctly shows invalid format error"
else
    echo "✗ Did not show expected format error"
fi

# Test 6: Test language option
echo ""
echo "Test 6: Testing language option..."
if auto-editor transcribe resources/test_turkish.mp3 --language tr 2>&1 | grep -q "API Key required"; then
    echo "✓ Language option accepted"
else
    echo "✗ Language option not working"
fi

# Test 7: Test detect-topics option
echo ""
echo "Test 7: Testing detect-topics option..."
if auto-editor transcribe resources/test_turkish.mp3 --language tr --detect-topics 2>&1 | grep -q "API Key required"; then
    echo "✓ detect-topics option accepted"
else
    echo "✗ detect-topics option not working"
fi

echo ""
echo "=== All basic tests completed ==="
echo ""
echo "Note: To run full tests with API, set environment variables:"
echo "  export GROQ_API_KEY='your-key'"
echo "  export OPENAI_API_KEY='your-key'"
echo "  export GEMINI_API_KEY='your-key'"
echo ""
echo "Then run:"
echo "  auto-editor transcribe resources/test_turkish.mp3 --language tr"
