<?php
/*
 * On-demand TLS authorization endpoint for Caddy / FrankenPHP.
 *
 * Caddy queries this with ?domain=<host> before issuing a Let's Encrypt
 * certificate for an unknown hostname (the self-served custom domains feature).
 * 200 = allow issuance, 403 = deny.
 *
 * This is stack-owned (mounted into the container, NOT part of the app release)
 * so the TLS gate never depends on whether an app release is deployed. It reads
 * DB credentials from the environment (the same MYSQL_* the db service uses) and
 * connects over the shared UNIX socket. It FAILS CLOSED on any error.
 */

declare(strict_types=1);

namespace Hypebun\Tls;

use PDO;

final class TlsAuthorizer
{
    /** First-party hosts that are always allowed (no DB lookup). */
    private const FIRST_PARTY_HOSTS = [
        'bio.hypebun.com',
        'bio-test.hypebun.com',
        'web3.eu.sqrd-dns.com',
    ];

    private bool $verifyDns;
    private array $serverIps;
    private ?PDO $pdo = null;

    public function __construct()
    {
        $this->verifyDns = getenv('HYPEBUN_TLS_VERIFY_DNS') !== '0';
        $this->serverIps = $this->resolveServerIps();
    }

    public function process(): void
    {
        $domain = $this->normalizeDomain($_GET['domain'] ?? '');

        if ($domain === null) {
            $this->deny();
        }

        if (in_array($domain, self::FIRST_PARTY_HOSTS, true)) {
            $this->allow();
        }

        if (!$this->isRegisteredDomain($domain)) {
            $this->deny();
        }

        if ($this->verifyDns && !$this->pointsToThisServer($domain)) {
            $this->deny();
        }

        $this->allow();
    }

    /** Validate and canonicalize the requested hostname; null if invalid. */
    private function normalizeDomain(string $raw): ?string
    {
        $host = strtolower(trim($raw));

        if ($host === '' || strlen($host) > 253) {
            return null;
        }

        // Reject IP literals — certificates are only issued for DNS names.
        if (filter_var($host, FILTER_VALIDATE_IP) !== false) {
            return null;
        }

        // Valid DNS hostname: labels of [a-z0-9-], dots between, no leading or
        // trailing hyphen per label. Rejects IPs, ports, paths, wildcards.
        if (!preg_match('/^(?=.{1,253}$)([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)(\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$/', $host)) {
            return null;
        }

        return $host;
    }

    private function isRegisteredDomain(string $host): bool
    {
        $stmt = $this->db()->prepare(
            'SELECT 1 FROM `domains` WHERE `host` = :host AND `is_enabled` = 1 LIMIT 1'
        );
        $stmt->execute([':host' => $host]);

        return (bool) $stmt->fetchColumn();
    }

    /** True if any A/AAAA record for $host matches one of our server IPs. */
    private function pointsToThisServer(string $host): bool
    {
        if ($this->serverIps === []) {
            // Could not determine our own IPs; do not block issuance on that.
            return true;
        }

        $records = @dns_get_record($host, DNS_A + DNS_AAAA) ?: [];

        foreach ($records as $record) {
            $ip = $record['ip'] ?? ($record['ipv6'] ?? null);
            if ($ip !== null && in_array($ip, $this->serverIps, true)) {
                return true;
            }
        }

        return false;
    }

    /**
     * This server's public IPs for the DNS check. Prefer the explicit
     * HYPEBUN_SERVER_IPS override (comma-separated) over hostname resolution.
     */
    private function resolveServerIps(): array
    {
        $override = getenv('HYPEBUN_SERVER_IPS');
        if ($override !== false && trim($override) !== '') {
            return array_values(array_filter(array_map('trim', explode(',', $override))));
        }

        $ips = [];
        $hostname = gethostname();
        if ($hostname !== false) {
            foreach (gethostbynamel($hostname) ?: [] as $ip) {
                if (!str_starts_with($ip, '127.')) {
                    $ips[] = $ip;
                }
            }
        }

        return array_values(array_unique($ips));
    }

    private function db(): PDO
    {
        if ($this->pdo instanceof PDO) {
            return $this->pdo;
        }

        $socket = ini_get('pdo_mysql.default_socket') ?: '/sockets/mysqld.sock';
        $dbName = getenv('MYSQL_DATABASE') ?: 'hypebun_bio_prod';
        $user = getenv('MYSQL_USER') ?: 'root';
        $pass = getenv('MYSQL_USER') ? (getenv('MYSQL_PASSWORD') ?: '') : (getenv('MYSQL_ROOT_PASSWORD') ?: '');

        $dsn = sprintf('mysql:unix_socket=%s;dbname=%s;charset=utf8mb4', $socket, $dbName);

        $this->pdo = new PDO($dsn, $user, $pass, [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
        ]);

        return $this->pdo;
    }

    private function allow(): never
    {
        http_response_code(200);
        header('Content-Type: text/plain');
        echo 'yes';
        exit;
    }

    private function deny(): never
    {
        http_response_code(403);
        header('Content-Type: text/plain');
        echo 'no';
        exit;
    }
}

try {
    (new TlsAuthorizer())->process();
} catch (\Throwable $e) {
    // Fail closed: never issue a certificate if authorization cannot be checked.
    error_log('tls-check: ' . $e->getMessage());
    http_response_code(403);
    header('Content-Type: text/plain');
    echo 'no';
    exit;
}
