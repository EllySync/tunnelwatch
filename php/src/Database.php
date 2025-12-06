<?php
/**
 * TunnelWatch Norway - Database Connection
 * 
 * Singleton pattern for database connection management
 */

namespace TunnelWatch;

class Database
{
    private static ?Database $instance = null;
    private ?\PDO $connection = null;

    private function __construct()
    {
        $host = getenv('DB_HOST') ?: 'postgres';
        $db = getenv('DB_NAME') ?: 'tunnelwatch';
        $user = getenv('DB_USER') ?: 'tunnelwatch';
        $pass = getenv('DB_PASSWORD') ?: '';

        $dsn = "pgsql:host={$host};dbname={$db}";

        $this->connection = new \PDO($dsn, $user, $pass, [
            \PDO::ATTR_ERRMODE => \PDO::ERRMODE_EXCEPTION,
            \PDO::ATTR_DEFAULT_FETCH_MODE => \PDO::FETCH_ASSOC,
            \PDO::ATTR_EMULATE_PREPARES => false,
        ]);
    }

    public static function getInstance(): Database
    {
        if (self::$instance === null) {
            self::$instance = new Database();
        }
        return self::$instance;
    }

    public function getConnection(): \PDO
    {
        return $this->connection;
    }

    public function query(string $sql, array $params = []): \PDOStatement
    {
        $stmt = $this->connection->prepare($sql);
        $stmt->execute($params);
        return $stmt;
    }

    public function fetchOne(string $sql, array $params = []): ?array
    {
        $result = $this->query($sql, $params)->fetch();
        return $result ?: null;
    }

    public function fetchAll(string $sql, array $params = []): array
    {
        return $this->query($sql, $params)->fetchAll();
    }
}
