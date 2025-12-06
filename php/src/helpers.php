<?php
/**
 * TunnelWatch Norway - Helper Functions
 */

// Language translations
$TRANSLATIONS = [
    'no' => [
        'site_title' => 'TunnelWatch Norge',
        'site_subtitle' => 'Sanntids status for norske tunneler',
        'status_open' => 'Åpen',
        'status_closed' => 'Stengt',
        'status_restricted' => 'Begrenset',
        'status_unknown' => 'Ukjent',
        'length' => 'Lengde',
        'meters' => 'meter',
        'updated' => 'Oppdatert',
        'just_now' => 'Akkurat nå',
        'minutes_ago' => 'minutter siden',
        'hours_ago' => 'timer siden',
        'days_ago' => 'dager siden',
        'auto_refresh' => 'Data oppdateres automatisk hvert minutt',
        'road' => 'Veg',
        'expected_change' => 'Forventet endring',
    ],
    'en' => [
        'site_title' => 'TunnelWatch Norway',
        'site_subtitle' => 'Real-time status for Norwegian tunnels',
        'status_open' => 'Open',
        'status_closed' => 'Closed',
        'status_restricted' => 'Restricted',
        'status_unknown' => 'Unknown',
        'length' => 'Length',
        'meters' => 'meters',
        'updated' => 'Updated',
        'just_now' => 'Just now',
        'minutes_ago' => 'minutes ago',
        'hours_ago' => 'hours ago',
        'days_ago' => 'days ago',
        'auto_refresh' => 'Data refreshes automatically every minute',
        'road' => 'Road',
        'expected_change' => 'Expected change',
    ],
];

/**
 * Get current language from cookie or default
 */
function getCurrentLanguage(): string
{
    return $_COOKIE['lang'] ?? 'no';
}

/**
 * Translate a key
 */
function t(string $key): string
{
    global $TRANSLATIONS;
    $lang = getCurrentLanguage();
    return $TRANSLATIONS[$lang][$key] ?? $TRANSLATIONS['no'][$key] ?? $key;
}

/**
 * Get status badge HTML
 */
function getStatusBadge(string $status): string
{
    $badges = [
        'open' => '<span class="badge badge-green">✅ ' . t('status_open') . '</span>',
        'closed' => '<span class="badge badge-red">🚫 ' . t('status_closed') . '</span>',
        'restricted' => '<span class="badge badge-yellow">⚠️ ' . t('status_restricted') . '</span>',
    ];
    return $badges[$status] ?? '<span class="badge badge-gray">❓ ' . t('status_unknown') . '</span>';
}

/**
 * Get CSS class for status
 */
function getStatusClass(string $status): string
{
    return "status-{$status}";
}

/**
 * Format tunnel length
 */
function formatLength(?int $length): string
{
    if (!$length) return '';
    return number_format($length, 0, ',', ' ') . ' ' . t('meters');
}

/**
 * Format datetime for display
 */
function formatDateTime(?string $datetime): string
{
    if (!$datetime) return '';
    $dt = new DateTime($datetime);
    $dt->setTimezone(new DateTimeZone('Europe/Oslo'));
    return $dt->format('d.m.Y H:i');
}

/**
 * Get relative time string
 */
function timeAgo(?string $datetime): string
{
    if (!$datetime) return '';
    
    $dt = new DateTime($datetime);
    $now = new DateTime();
    $diff = $now->diff($dt);

    if ($diff->d > 0) {
        return $diff->d . ' ' . t('days_ago');
    }
    if ($diff->h > 0) {
        return $diff->h . ' ' . t('hours_ago');
    }
    if ($diff->i > 0) {
        return $diff->i . ' ' . t('minutes_ago');
    }
    return t('just_now');
}

/**
 * Get message in current language
 */
function getMessage(array $tunnel): string
{
    $lang = getCurrentLanguage();
    $messageKey = $lang === 'en' ? 'message_en' : 'message_no';
    return $tunnel[$messageKey] ?? $tunnel['message_no'] ?? '';
}

/**
 * Format road info (e.g., "E39")
 */
function formatRoad(?string $category, ?string $number): string
{
    if (!$category || !$number) return '';
    return $category . $number;
}
