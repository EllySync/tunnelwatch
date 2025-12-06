<?php
/**
 * TunnelWatch Norway - Homepage
 */

require_once __DIR__ . '/../vendor/autoload.php';

use TunnelWatch\Tunnel;

$tunnelModel = new Tunnel();
$tunnels = $tunnelModel->getAllActive();
$lang = getCurrentLanguage();
?>
<!DOCTYPE html>
<html lang="<?= $lang ?>">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?= t('site_title') ?></title>
    <meta name="description" content="<?= t('site_subtitle') ?>">
    <script src="https://cdn.tailwindcss.com"></script>
    <link rel="stylesheet" href="/assets/css/style.css">
    <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>🚇</text></svg>">
</head>
<body class="bg-gray-100 min-h-screen">
    <header class="bg-blue-600 text-white shadow-lg">
        <div class="container mx-auto px-4 py-6">
            <div class="flex justify-between items-center">
                <div>
                    <h1 class="text-3xl font-bold">🚇 <?= t('site_title') ?></h1>
                    <p class="text-blue-100 mt-2"><?= t('site_subtitle') ?></p>
                </div>
                <div class="flex items-center space-x-2">
                    <button onclick="setLanguage('no')" class="px-3 py-1 rounded <?= $lang === 'no' ? 'bg-white text-blue-600' : 'bg-blue-500 text-white hover:bg-blue-400' ?>">
                        🇳🇴 NO
                    </button>
                    <button onclick="setLanguage('en')" class="px-3 py-1 rounded <?= $lang === 'en' ? 'bg-white text-blue-600' : 'bg-blue-500 text-white hover:bg-blue-400' ?>">
                        🇬🇧 EN
                    </button>
                </div>
            </div>
        </div>
    </header>

    <main class="container mx-auto px-4 py-8">
        <?php if (empty($tunnels)): ?>
            <div class="bg-yellow-100 border-l-4 border-yellow-500 text-yellow-700 p-4 rounded">
                <p>No tunnels configured yet.</p>
            </div>
        <?php else: ?>
            <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
                <?php foreach ($tunnels as $tunnel): ?>
                    <?php $statusClass = getStatusClass($tunnel['status'] ?? 'unknown'); ?>
                    
                    <div class="bg-white rounded-lg shadow-md hover:shadow-xl transition-shadow overflow-hidden">
                        <div class="h-2 <?= $statusClass ?>-bar"></div>
                        
                        <div class="p-6">
                            <div class="flex justify-between items-start mb-4">
                                <div>
                                    <h3 class="text-xl font-semibold text-gray-800"><?= htmlspecialchars($tunnel['name']) ?></h3>
                                    <?php if ($road = formatRoad($tunnel['road_category'], $tunnel['road_number'])): ?>
                                        <span class="text-sm text-gray-500"><?= t('road') ?>: <?= $road ?></span>
                                    <?php endif; ?>
                                </div>
                                <?= getStatusBadge($tunnel['status'] ?? 'unknown') ?>
                            </div>

                            <?php $message = getMessage($tunnel); ?>
                            <?php if (!empty($message)): ?>
                                <div class="mb-4 p-3 bg-gray-50 rounded text-sm text-gray-700">
                                    <?= htmlspecialchars($message) ?>
                                </div>
                            <?php endif; ?>

                            <?php if (!empty($tunnel['expected_change']) && !empty($tunnel['expected_status'])): ?>
                                <div class="mb-4 p-3 bg-orange-50 border-l-4 border-orange-400 text-sm">
                                    <strong><?= t('expected_change') ?>:</strong><br>
                                    <?= ucfirst($tunnel['expected_status']) ?> - <?= formatDateTime($tunnel['expected_change']) ?>
                                </div>
                            <?php endif; ?>

                            <div class="text-sm text-gray-600 space-y-1">
                                <?php if ($tunnel['length']): ?>
                                    <div><?= t('length') ?>: <?= formatLength($tunnel['length']) ?></div>
                                <?php endif; ?>
                            </div>

                            <div class="mt-4 pt-4 border-t border-gray-100 text-xs text-gray-400">
                                <?= t('updated') ?>: <?= !empty($tunnel['status_updated_at']) ? timeAgo($tunnel['status_updated_at']) : '-' ?>
                            </div>
                        </div>
                    </div>
                <?php endforeach; ?>
            </div>
        <?php endif; ?>

        <div class="mt-8 text-center text-sm text-gray-500">
            <p><?= t('auto_refresh') ?></p>
        </div>
    </main>

    <footer class="mt-auto py-6 text-center text-sm text-gray-400">
        <p>Data: Statens vegvesen (NLOD)</p>
    </footer>

    <script src="/assets/js/app.js"></script>
</body>
</html>
