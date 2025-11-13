<?php
// Comprehensive error logging
error_reporting(E_ALL);
ini_set('display_errors', 0);
ini_set('log_errors', 1);
ini_set('error_log', '/var/log/apache2/ocr-proxy-error.log');

error_log("PROXY REQUEST STARTED - " . date('Y-m-d H:i:s'));

// CORS headers (must come first)
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Content-Type: application/json; charset=utf-8');

// Handle OPTIONS request
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    error_log("PROXY: Handling OPTIONS request");
    http_response_code(200);
    exit;
}

// Get raw input
$rawInput = file_get_contents('php://input');
error_log("PROXY: Raw input: " . substr($rawInput, 0, 200));

// Parse JSON with error handling
$data = json_decode($rawInput, true);
$jsonError = json_last_error();

if ($jsonError !== JSON_ERROR_NONE) {
    $errorMsg = "JSON Parse Error: " . json_last_error_msg();
    error_log("PROXY ERROR: $errorMsg - Input: " . substr($rawInput, 0, 100));
    http_response_code(400);
    echo json_encode(['error' => $errorMsg, 'received_input' => substr($rawInput, 0, 100)]);
    exit;
}

// Validate input
if (empty($data['ocr_text'])) {
    $errorMsg = "Missing ocr_text parameter";
    error_log("PROXY ERROR: $errorMsg");
    http_response_code(400);
    echo json_encode(['error' => $errorMsg]);
    exit;
}

$ocrText = trim($data['ocr_text']);
if (strlen($ocrText) < 5) {
    $errorMsg = "OCR text too short";
    error_log("PROXY ERROR: $errorMsg (length: " . strlen($ocrText) . ")");
    http_response_code(400);
    echo json_encode(['error' => $errorMsg]);
    exit;
}

error_log("PROXY: Valid text received (length: " . strlen($ocrText) . " chars)");

// Configure curl
$ch = curl_init();
curl_setopt_array($ch, [
    CURLOPT_URL => 'http://localhost:11434/api/generate',
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_POST => true,
    CURLOPT_POSTFIELDS => json_encode([
        // 'model' => 'qwen3:8b', // no Latin
        // 'model' => 'qwen3:14b',
        // 'model' => 'gemma3:latest',
        'model' => 'mistral-small3.2', // Make sure this model exists
        'prompt' => "You are an expert translator. Translate this OCR text which might be German, Latin, French or some other language to English completely. Correct OCR errors while preserving structure. Do not summarize or truncate. Translate every single word:\n\n" . $ocrText,
        'stream' => false,
        'options' => [
            'temperature' => 0.3,
            'num_ctx' => 8192,        // Larger context window (8K tokens)
            'num_predict' => 4096,    // Allow longer responses (4K tokens)
            'repeat_penalty' => 1.1,  // Prevent repetition
            'top_k' => 40,           // Diversity in generation
            'top_p' => 0.95          // Nucleus sampling
        ]
    ]),
    CURLOPT_HTTPHEADER => ['Content-Type: application/json'],
    CURLOPT_TIMEOUT => 60, // Increased timeout
    CURLOPT_CONNECTTIMEOUT => 15,
    CURLOPT_NOSIGNAL => true,
    CURLOPT_FOLLOWLOCATION => true,
    CURLOPT_MAXREDIRS => 3,
]);

// Execute request
$start = microtime(true);
$response = curl_exec($ch);
$end = microtime(true);
$totalTime = $end - $start;

$curlError = curl_error($ch);
$httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);

error_log("PROXY: Ollama request completed - HTTP: $httpCode, Time: {$totalTime}s");

if ($curlError) {
    $errorMsg = "CURL Error: $curlError";
    error_log("PROXY ERROR: $errorMsg");
    http_response_code(500);
    echo json_encode(['error' => $errorMsg, 'request_time' => $totalTime]);
    curl_close($ch);
    exit;
}

curl_close($ch);

// Handle HTTP errors
if ($httpCode >= 400) {
    error_log("PROXY ERROR: Ollama returned HTTP $httpCode - Response preview: " . substr($response, 0, 300));
    http_response_code($httpCode);
    
    // Try to parse error response
    $errorData = json_decode($response, true);
    if (json_last_error() === JSON_ERROR_NONE && isset($errorData['error'])) {
        echo json_encode(['error' => 'Ollama error: ' . $errorData['error']]);
    } else {
        echo json_encode([
            'error' => "Ollama returned HTTP $httpCode",
            'response_preview' => substr($response, 0, 300)
        ]);
    }
    exit;
}

// Handle empty response
if (empty($response)) {
    $errorMsg = "Empty response from Ollama";
    error_log("PROXY ERROR: $errorMsg");
    http_response_code(500);
    echo json_encode(['error' => $errorMsg]);
    exit;
}

// Parse Ollama response with robust error handling
error_log("PROXY: Raw Ollama response length: " . strlen($response));
error_log("PROXY: First 500 chars: " . substr($response, 0, 500));

$ollamaData = json_decode($response, true);
$jsonParseError = json_last_error();

if ($jsonParseError !== JSON_ERROR_NONE) {
    $errorMsg = "Invalid JSON from Ollama: " . json_last_error_msg();
    error_log("PROXY ERROR: $errorMsg");
    error_log("PROXY: Response that failed to parse: " . substr($response, 0, 500));
    
    // Try to extract response manually if it's malformed
    if (preg_match('/"response"\s*:\s*"([^"]+)"/', $response, $matches)) {
        error_log("PROXY: Found response in malformed JSON");
        echo json_encode(['translation' => str_replace('\n', "\n", $matches[1])]);
        exit;
    }
    
    http_response_code(500);
    echo json_encode([
        'error' => $errorMsg,
        'raw_response_preview' => substr($response, 0, 500),
        'response_length' => strlen($response)
    ]);
    exit;
}

// Check for Ollama-specific errors
if (isset($ollamaData['error'])) {
    $errorMsg = 'Ollama error: ' . $ollamaData['error'];
    error_log("PROXY ERROR: $errorMsg");
    http_response_code(500);
    echo json_encode(['error' => $errorMsg]);
    exit;
}

// Success - return translation
if (isset($ollamaData['response'])) {
    error_log("PROXY: Translation successful - response length: " . strlen($ollamaData['response']));
    echo json_encode(['translation' => $ollamaData['response']]);
} else {
    $errorMsg = 'Unexpected response format from Ollama';
    error_log("PROXY ERROR: $errorMsg - Available keys: " . implode(', ', array_keys($ollamaData)));
    http_response_code(500);
    echo json_encode([
        'error' => $errorMsg,
        'available_keys' => array_keys($ollamaData),
        'response_preview' => substr($response, 0, 300)
    ]);
}
