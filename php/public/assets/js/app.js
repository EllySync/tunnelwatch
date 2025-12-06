/**
 * TunnelWatch Norway - Frontend JavaScript
 */

(function() {
    'use strict';

    const REFRESH_INTERVAL = 60000; // 60 seconds
    let refreshTimer = null;

    /**
     * Set language preference
     */
    window.setLanguage = function(lang) {
        document.cookie = `lang=${lang};path=/;max-age=31536000`; // 1 year
        window.location.reload();
    };

    /**
     * Refresh tunnel data
     */
    async function refreshData() {
        try {
            const response = await fetch('/api.php');
            if (response.ok) {
                // For MVP, just reload the page
                // In future: update DOM without reload
                window.location.reload();
            }
        } catch (error) {
            console.error('Error refreshing data:', error);
        }
    }

    /**
     * Start auto-refresh timer
     */
    function startAutoRefresh() {
        if (refreshTimer) {
            clearInterval(refreshTimer);
        }
        refreshTimer = setInterval(refreshData, REFRESH_INTERVAL);
        console.log(`Auto-refresh enabled: every ${REFRESH_INTERVAL / 1000} seconds`);
    }

    /**
     * Stop auto-refresh when page is hidden
     */
    function handleVisibilityChange() {
        if (document.hidden) {
            if (refreshTimer) {
                clearInterval(refreshTimer);
                refreshTimer = null;
            }
        } else {
            // Refresh immediately when page becomes visible
            refreshData();
            startAutoRefresh();
        }
    }

    /**
     * Initialize
     */
    function init() {
        // Start auto-refresh
        startAutoRefresh();

        // Handle page visibility
        document.addEventListener('visibilitychange', handleVisibilityChange);

        // Log startup
        console.log('TunnelWatch Norway initialized');
    }

    // Run on DOM ready
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
})();
