<?php
/**
 * MacCMS 工具公共引导（读库配置、PDO）
 * PHP 7.2+
 */
declare(strict_types=1);

/** @return string|null */
function macFindRoot($start)
{
    $dir = realpath($start);
    for ($i = 0; $i < 6; $i++) {
        if ($dir && is_file($dir . '/application/database.php')) {
            return $dir;
        }
        $parent = dirname($dir);
        if ($parent === $dir) {
            break;
        }
        $dir = $parent;
    }
    foreach ([dirname($start), dirname(dirname($start)), '/www/wwwroot/154.12.29.28'] as $g) {
        if (is_file($g . '/application/database.php')) {
            return $g;
        }
    }
    return null;
}

/** @return array|null */
function macLoadDbConfig($root)
{
    $file = $root . '/application/database.php';
    if (!is_file($file)) {
        return null;
    }
    $cfg = include $file;
    if (!is_array($cfg)) {
        return null;
    }
    return [
        'hostname' => isset($cfg['hostname']) ? $cfg['hostname'] : '127.0.0.1',
        'database' => isset($cfg['database']) ? $cfg['database'] : '',
        'username' => isset($cfg['username']) ? $cfg['username'] : '',
        'password' => isset($cfg['password']) ? $cfg['password'] : '',
        'hostport' => isset($cfg['hostport']) ? $cfg['hostport'] : '3306',
        'charset' => isset($cfg['charset']) ? $cfg['charset'] : 'utf8mb4',
        'prefix' => isset($cfg['prefix']) ? $cfg['prefix'] : 'mac_',
    ];
}

/** @return PDO */
function macPdo($root)
{
    $dbCfg = macLoadDbConfig($root);
    if ($dbCfg === null) {
        throw new RuntimeException('读取 database.php 失败');
    }
    $pdo = new PDO(
        sprintf(
            'mysql:host=%s;port=%s;dbname=%s;charset=%s',
            $dbCfg['hostname'],
            $dbCfg['hostport'] ? $dbCfg['hostport'] : '3306',
            $dbCfg['database'],
            $dbCfg['charset'] ? $dbCfg['charset'] : 'utf8mb4'
        ),
        $dbCfg['username'],
        $dbCfg['password'],
        [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        ]
    );
    return $pdo;
}

/** @return array{prefix:string,table:string} */
function macTypeTable($root)
{
    $dbCfg = macLoadDbConfig($root);
    $prefix = $dbCfg && $dbCfg['prefix'] ? $dbCfg['prefix'] : 'mac_';
    return ['prefix' => $prefix, 'table' => $prefix . 'type'];
}

/** @return list<string> */
function macTypeColumns(PDO $pdo, $table)
{
    $cols = [];
    $st = $pdo->query('SHOW COLUMNS FROM `' . str_replace('`', '', $table) . '`');
    foreach ($st->fetchAll() as $row) {
        $cols[] = $row['Field'];
    }
    return $cols;
}
