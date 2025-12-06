<?php
/**
 * TunnelWatch Norway - Health Check
 */

require_once __DIR__ . '/../vendor/autoload.php';

use TunnelWatch\Database;

header('Content-Type: application/json');

$health = [
    'status' => 'healthy',
    'checks' => [],
    'timestamp' => date('c'),
];

$httpStatus = 200;

// Check database connection
try {
    $db = Database::getInstance();
    $result = $db->fetchOne("SELECT 1 as ok");
    $health['checks']['database'] = [
        'status' => 'ok',
        'message' => 'Connected to PostgreSQL',
    ];
} catch (Exception $e) {
    $health['status'] = 'unhealthy';
    $health['checks']['database'] = [
        'status' => 'error',
        'message' => $e->getMessage(),
    ];
    $httpStatus = 500;
}

// Check last status update
try {
    $db = Database::getInstance();
    $result = $db->fetchOne("
        SELECT MAX(created_at) as last_update 
        FROM status_updates
    ");
    
    $lastUpdate = $result['last_update'] ?? null;
    $minutesAgo = null;
    
    if ($lastUpdate) {
        $dt = new DateTime($lastUpdate);
        $now = new DateTime();
        $diff = $now->getTimestamp() - $dt->getTimestamp();
        $minutesAgo = round($diff / 60);
    }
    
    $health['checks']['last_update'] = [
        'status' => $minutesAgo !== null && $minutesAgo < 5 ? 'ok' : 'warning',
        'last_update' => $lastUpdate,
        'minutes_ago' => $minutesAgo,
    ];
} catch (Exception $e) {
    $health['checks']['last_update'] = [
        'status' => 'error',
        'message' => $e->getMessage(),
    ];
}

// Check tunnel count
try {
    $db = Database::getInstance();
    $result = $db->fetchOne("SELECT COUNT(*) as count FROM tunnels WHERE active = true");
    $health['checks']['tunnels'] = [
        'status' => 'ok',
        'active_count' => (int)$result['count'],
    ];
} catch (Exception $e) {
    $health['checks']['tunnels'] = [
        'status' => 'error',
        'message' => $e->getMessage(),
    ];
}

http_response_code($httpStatus);
echo json_encode($health, JSON_PRETTY_PRINT);
