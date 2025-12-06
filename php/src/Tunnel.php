<?php
/**
 * TunnelWatch Norway - Tunnel Model
 */

namespace TunnelWatch;

class Tunnel
{
    private Database $db;

    public function __construct()
    {
        $this->db = Database::getInstance();
    }

    /**
     * Get all active tunnels with current status
     */
    public function getAllActive(): array
    {
        $sql = "SELECT * FROM tunnel_current_status ORDER BY name";
        return $this->db->fetchAll($sql);
    }

    /**
     * Get a single tunnel by ID
     */
    public function getById(string $id): ?array
    {
        $sql = "SELECT * FROM tunnel_current_status WHERE id = :id";
        return $this->db->fetchOne($sql, ['id' => $id]);
    }

    /**
     * Get a tunnel by Vegvesen ID
     */
    public function getByVegvesenId(string $vegvesenId): ?array
    {
        $sql = "SELECT * FROM tunnel_current_status WHERE vegvesen_id = :vegvesen_id";
        return $this->db->fetchOne($sql, ['vegvesen_id' => $vegvesenId]);
    }

    /**
     * Get status history for a tunnel
     */
    public function getStatusHistory(string $tunnelId, int $limit = 50): array
    {
        $sql = "
            SELECT * FROM status_updates
            WHERE tunnel_id = :tunnel_id
            ORDER BY created_at DESC
            LIMIT :limit
        ";
        $stmt = $this->db->getConnection()->prepare($sql);
        $stmt->bindValue(':tunnel_id', $tunnelId, \PDO::PARAM_STR);
        $stmt->bindValue(':limit', $limit, \PDO::PARAM_INT);
        $stmt->execute();
        return $stmt->fetchAll();
    }

    /**
     * Get count of tunnels by status
     */
    public function getStatusCounts(): array
    {
        $sql = "
            SELECT status, COUNT(*) as count
            FROM tunnel_current_status
            GROUP BY status
        ";
        $results = $this->db->fetchAll($sql);
        
        $counts = ['open' => 0, 'closed' => 0, 'restricted' => 0, 'unknown' => 0];
        foreach ($results as $row) {
            $counts[$row['status']] = (int)$row['count'];
        }
        return $counts;
    }
}
