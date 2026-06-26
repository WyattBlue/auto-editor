#!/bin/bash
# Unit tests for Turkish transcribe functionality
# These tests validate the prompt building logic without API calls

set -e

echo "=== Turkish Transcribe Unit Tests ==="
echo ""

PASS=0
FAIL=0

run_test() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"
    
    if [ "$expected" = "$actual" ]; then
        echo "✓ $test_name"
        PASS=$((PASS + 1))
    else
        echo "✗ $test_name"
        echo "  Expected: $expected"
        echo "  Actual:   $actual"
        FAIL=$((FAIL + 1))
    fi
}

# Test 1: Turkish SRT prompt
echo "Test 1: Turkish SRT prompt"
PROMPT=$(grep -A5 "buildTranscriptPrompt" src/cmds/transcribe.nim | grep -o "Ses Türkçe'dir" | head -1)
run_test "Turkish hint present" "Ses Türkçe'dir" "$PROMPT"

# Test 2: Turkish topic prompt
echo ""
echo "Test 2: Turkish topic prompt"
TOPIC_PROMPT=$(grep -A10 "buildTopicPrompt" src/cmds/transcribe.nim | grep -o "Aşağıdaki Türkçe transkripte dayanarak" | head -1)
run_test "Turkish topic prompt present" "Aşağıdaki Türkçe transkripte dayanarak" "$TOPIC_PROMPT"

# Test 3: Language detection
echo ""
echo "Test 3: Language detection logic"
TR_CHECK=$(grep -o 'language == "tr" or language == "tur"' src/cmds/transcribe.nim | head -1)
run_test "Turkish language check exists" 'language == "tr" or language == "tur"' "$TR_CHECK"

# Test 4: Provider support
echo ""
echo "Test 4: Provider support"
GROQ_CHECK=$(grep -c '"groq"' src/cmds/transcribe.nim)
OPENAI_CHECK=$(grep -c '"openai"' src/cmds/transcribe.nim)
GEMINI_CHECK=$(grep -c '"gemini"' src/cmds/transcribe.nim)
if [ "$GROQ_CHECK" -gt 0 ]; then
    run_test "Groq provider" "1" "1"
else
    run_test "Groq provider" "1" "0"
fi
if [ "$OPENAI_CHECK" -gt 0 ]; then
    run_test "OpenAI provider" "1" "1"
else
    run_test "OpenAI provider" "1" "0"
fi
if [ "$GEMINI_CHECK" -gt 0 ]; then
    run_test "Gemini provider" "1" "1"
else
    run_test "Gemini provider" "1" "0"
fi

# Test 5: detect-topics option
echo ""
echo "Test 5: detect-topics option"
DETECT_TOPICS=$(grep -o "detectTopics" src/cmds/transcribe.nim | head -1)
run_test "detect-topics option exists" "detectTopics" "$DETECT_TOPICS"

# Test 6: Turkish Gemini prompt
echo ""
echo "Test 6: Turkish Gemini prompt"
GEMINI_PROMPT=$(grep -c "Bu Türkçe sesi önce transkribe et" src/cmds/transcribe.nim)
if [ "$GEMINI_PROMPT" -gt 0 ]; then
    run_test "Turkish Gemini prompt exists" "1" "1"
else
    run_test "Turkish Gemini prompt exists" "1" "0"
fi

# Test 7: JSON format validation
echo ""
echo "Test 7: JSON format in prompts"
JSON_FORMAT=$(grep -c '"topics"' src/cmds/transcribe.nim)
if [ "$JSON_FORMAT" -gt 0 ]; then
    run_test "JSON topics format exists" "1" "1"
else
    run_test "JSON topics format exists" "1" "0"
fi

# Test 8: Time format
echo ""
echo "Test 8: Time format in prompts"
TIME_FORMAT=$(grep -o "HH:MM:SS" src/cmds/transcribe.nim | head -1)
run_test "HH:MM:SS format exists" "HH:MM:SS" "$TIME_FORMAT"

# Test 9: Default models
echo ""
echo "Test 9: Default models"
WHISPER_MODEL=$(grep -o "whisper-large-v3" src/cmds/transcribe.nim | head -1)
run_test "Whisper model defined" "whisper-large-v3" "$WHISPER_MODEL"

# Test 10: Chat model for topic detection
echo ""
echo "Test 10: Chat model for topic detection"
CHAT_MODEL=$(grep -o "llama-3.3-70b-versatile" src/cmds/transcribe.nim | head -1)
run_test "Chat model defined" "llama-3.3-70b-versatile" "$CHAT_MODEL"

# Test 11: CLI options
echo ""
echo "Test 11: CLI options"
PROVIDER_OPT=$(grep -o "provider" src/cli.nim | head -1)
run_test "Provider CLI option exists" "provider" "$PROVIDER_OPT"

API_KEY_OPT=$(grep -o "api-key" src/cli.nim | head -1)
run_test "API key CLI option exists" "api-key" "$API_KEY_OPT"

LANGUAGE_OPT=$(grep -o "language" src/cli.nim | head -1)
run_test "Language CLI option exists" "language" "$LANGUAGE_OPT"

# Test 12: Test file exists
echo ""
echo "Test 12: Test file exists"
TEST_FILE=$(ls -la resources/test_turkish.mp3 2>/dev/null | wc -l)
if [ "$TEST_FILE" -gt 0 ]; then
    run_test "Test file created" "1" "1"
else
    run_test "Test file created" "1" "0"
fi

# Test 13: summarize option exists
echo ""
echo "Test 13: summarize option"
SUMMARIZE_OPTION=$(grep -c "summarize" src/cli.nim)
if [ "$SUMMARIZE_OPTION" -gt 0 ]; then
    run_test "summarize CLI option exists" "1" "1"
else
    run_test "summarize CLI option exists" "1" "0"
fi

# Test 14: buildSummaryPrompt function exists
echo ""
echo "Test 14: buildSummaryPrompt function"
SUMMARY_PROMPT_FUNC=$(grep -c "buildSummaryPrompt" src/cmds/transcribe.nim)
if [ "$SUMMARY_PROMPT_FUNC" -gt 0 ]; then
    run_test "buildSummaryPrompt function exists" "1" "1"
else
    run_test "buildSummaryPrompt function exists" "1" "0"
fi

# Test 15: Turkish summary prompt
echo ""
echo "Test 15: Turkish summary prompt"
TURKISH_SUMMARY=$(grep -c "özetini çıkar" src/cmds/transcribe.nim)
if [ "$TURKISH_SUMMARY" -gt 0 ]; then
    run_test "Turkish summary prompt exists" "1" "1"
else
    run_test "Turkish summary prompt exists" "1" "0"
fi

# Test 16: Summary JSON format
echo ""
echo "Test 16: Summary JSON format"
SUMMARY_JSON=$(grep -c "\"summary\"" src/cmds/transcribe.nim)
if [ "$SUMMARY_JSON" -gt 0 ]; then
    run_test "Summary JSON format exists" "1" "1"
else
    run_test "Summary JSON format exists" "1" "0"
fi

# Test 17: convertTopicsToSRT function
echo ""
echo "Test 17: convertTopicsToSRT function"
CONVERT_SRT=$(grep -c "convertTopicsToSRT" src/cmds/transcribe.nim)
if [ "$CONVERT_SRT" -gt 0 ]; then
    run_test "convertTopicsToSRT function exists" "1" "1"
else
    run_test "convertTopicsToSRT function exists" "1" "0"
fi

# Test 18: convertTopicsToTimelineJSON function
echo ""
echo "Test 18: convertTopicsToTimelineJSON function"
CONVERT_TIMELINE=$(grep -c "convertTopicsToTimelineJSON" src/cmds/transcribe.nim)
if [ "$CONVERT_TIMELINE" -gt 0 ]; then
    run_test "convertTopicsToTimelineJSON function exists" "1" "1"
else
    run_test "convertTopicsToTimelineJSON function exists" "1" "0"
fi

# Test 19: convertSummaryToJSON function
echo ""
echo "Test 19: convertSummaryToJSON function"
CONVERT_SUMMARY=$(grep -c "convertSummaryToJSON" src/cmds/transcribe.nim)
if [ "$CONVERT_SUMMARY" -gt 0 ]; then
    run_test "convertSummaryToJSON function exists" "1" "1"
else
    run_test "convertSummaryToJSON function exists" "1" "0"
fi

# Test 20: Format conversion in main function
echo ""
echo "Test 20: Format conversion in main"
FORMAT_CONV=$(grep -c "convertTopicsToSRT(result)" src/cmds/transcribe.nim)
if [ "$FORMAT_CONV" -gt 0 ]; then
    run_test "Format conversion implemented" "1" "1"
else
    run_test "Format conversion implemented" "1" "0"
fi

# Summary
echo ""
echo "=== Test Summary ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo "Total:  $((PASS + FAIL))"

if [ $FAIL -eq 0 ]; then
    echo ""
    echo "All tests passed! ✓"
    exit 0
else
    echo ""
    echo "Some tests failed! ✗"
    exit 1
fi
