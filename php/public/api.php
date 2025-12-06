<?php
/**
 * TunnelWatch Norway - JSON API
 */

require_once __DIR__ . '/../vendor/autoload.php';

use TunnelWatch\Tunnel;

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET');

try {
    $tunnelModel = new Tunnel();
    $tunnels = $tunnelModel->getAllActive();

    // Transform data for API response
    $data = array_map(function ($tunnel) {
        return [
            'id' => $tunnel['id'],
            'name' => $tunnel['name'],
            'vegvesen_id' => $tunnel['vegvesen_id'],
            'status' => $tunnel['status'],
            'status_heavy_vehicle' => $tunnel['status_heavy_vehicle'],
            'message' => [
                'no' => $tunnel['message_no'],
                'en' => $tunnel['message_en'],
            ],
            'severity' => $tunnel['severity'],
            'location' => [
                'latitude' => (float)$tunnel['latitude'],
                'longitude' => (float)$tunnel['longitude'],
            ],
            'road' => [
                'category' => $tunnel['road_category'],
                'number' => $tunnel['road_number'],
            ],
            'length' => $tunnel['length'] ? (int)$tunnel['length'] : null,
            'region' => $tunnel['region'],
            'expected_change' => $tunnel['expected_change'],
            'expected_status' => $tunnel['expected_status'],
            'updated_at' => $tunnel['status_updated_at'],
        ];
    }, $tunnels);

    echo json_encode([
        'success' => true,
        'count' => count($data),
        'data' => $data,
        'generated_at' => date('c'),
    ], JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'error' => $e->getMessage(),
    ]);
}
