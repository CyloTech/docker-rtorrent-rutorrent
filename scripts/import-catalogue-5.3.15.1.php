<?php
/** One-release guard around the deployed AppsTask importer; run on farm. */
namespace Cylo;

use Library\App\Constants\Services as AppServices;
use Symfony\Component\Yaml\Yaml;

function requireRelease(bool $ok, string $message): void
{
    if (!$ok) {
        throw new \RuntimeException($message);
    }
}

function releaseSnapshot($db): array
{
    $app = $db->fetchOne('SELECT to_jsonb(a)::text AS data FROM apps a WHERE id=66', \PDO::FETCH_ASSOC);
    requireRelease(is_array($app), 'App 66 missing');
    $app = json_decode($app['data'], true, 512, JSON_THROW_ON_ERROR);
    $versions = $db->fetchAll('SELECT to_jsonb(v)::text AS data FROM app_versions v WHERE app_id=66 ORDER BY id', \PDO::FETCH_ASSOC);
    $versions = array_map(static fn($v) => json_decode($v['data'], true, 512, JSON_THROW_ON_ERROR), $versions);
    // Hash catalogue definitions in the database; never print their values.
    $children = [];
    $targets = [
        'appbinds' => 'app_id=66', 'appmounts' => 'app_id=66',
        'appenvironmentvars' => 'app_id=66', 'appchains' => 'app_id=66',
        'appsysctl' => 'app_id=66', 'appcommands' => 'app_id=66',
        'appdevicecgrouprules' => 'app_id=66', 'appvolumesfrom' => 'app_id=66',
        'appdevices' => "type='app' AND relid=66",
        'appulimits' => "type='app' AND relid=66",
        'appblockio' => "type='app' AND relid=66",
        'customfields' => "type='app' AND relid=66",
        'links' => "type='appcategory' AND relid1=66",
        'app_typed_operations' => 'app_version_id IN (SELECT id FROM app_versions WHERE app_id=66)',
    ];
    foreach ($targets as $table => $predicate) {
        $children[$table] = $db->fetchOne("SELECT count(*) AS count, md5(COALESCE(jsonb_agg(to_jsonb(t) ORDER BY id)::text,'[]')) AS hash FROM $table t WHERE $predicate", \PDO::FETCH_ASSOC);
    }
    return compact('app', 'versions', 'children');
}

function releaseHash(array $value): string
{
    return hash('sha256', json_encode($value, JSON_THROW_ON_ERROR));
}

$mode = $argv[1] ?? '--preview';
requireRelease($mode === '--preview' || preg_match('/^--(?:apply|rehearse)=[a-f0-9]{64}$/D', $mode) === 1,
    'Usage: php import-catalogue-5.3.15.1.php [--preview|--rehearse=PLAN_SHA256|--apply=PLAN_SHA256]');
$api = '/usr/local/cylo-api';
$manifest = dirname(__DIR__) . '/appbox.yml';
requireRelease(hash_file('sha256', $api . '/app/tasks/AppsTask.php') === '177c3c94c4ba6f284c75feeaa39bfc2e608dd58353e5ecc9276dcfe37dd52736',
    'Deployed importer changed; review it again');
define('CLI', true);
define('VERSION', '1.0.0');
$di = new \Phalcon\Di\FactoryDefault\Cli();
require $api . '/app/bootstrap/loader.php';
$config = require $api . '/app/bootstrap/config.php';
require $api . '/app/bootstrap/services.php';
$db = $di->getShared(AppServices::DB);
$di->setShared(AppServices::DB, $db);
foreach ([new Models\App(), new Models\AppVersion(), new Models\AppEnvironmentVars()] as $model) {
    requireRelease($model->getReadConnection() === $db && $model->getWriteConnection() === $db,
        'Importer models must share the guarded transaction connection');
}
$definition = Yaml::parseFile($manifest);
$digest = $definition['image']['digest'] ?? '';
requireRelease(($definition['image']['version'] ?? '') === '5.3.15.1'
    && ($definition['image']['tag'] ?? '') === '5.3.15.1-0.16.23'
    && preg_match('/^repo\.cylo\.net\/rutorrent@sha256:[a-f0-9]{64}$/D', $digest) === 1,
    'Manifest does not describe the published release');
register_shutdown_function(static function () use ($db): void {
    if ($db->isUnderTransaction()) {
        $db->rollback();
        fwrite(STDERR, "Unfinished import rolled back\n");
        exit(1);
    }
});
try {
    $db->begin();
    $db->execute("SET LOCAL lock_timeout='5s'");
    $db->execute("SET LOCAL statement_timeout='30s'");
    // Lock concrete rows, never an aggregate query.
    $db->fetchAll('SELECT id FROM apps WHERE id=66 FOR UPDATE', \PDO::FETCH_ASSOC);
    $db->fetchAll('SELECT id FROM app_versions WHERE app_id=66 ORDER BY id FOR UPDATE', \PDO::FETCH_ASSOC);
    $before = releaseSnapshot($db);
    $defaults = array_values(array_filter($before['versions'], static fn($v) => $v['is_default'] === 1));
    requireRelease(count($before['versions']) === 51 && count($defaults) === 1 && $defaults[0]['id'] === 1324,
        'Expected 51 versions and sole default 1324');
    requireRelease($before['app']['version'] === '5.3.14-0.16.23-1'
        && $before['app']['tag'] === '5.3.14-0.16.23-1'
        && $before['app']['app_slots'] === 1 && $before['app']['allow_downgrade'] === 1,
        'Current app defaults changed');
    foreach ($before['versions'] as $v) {
        requireRelease($v['version'] !== '5.3.15.1' && $v['tag'] !== '5.3.15.1-0.16.23', 'Release already exists');
    }
    $planHash = releaseHash(['manifest' => hash_file('sha256', $manifest), 'before' => $before]);
    $preview = ['app_id' => 66, 'from' => '5.3.14-0.16.23-1', 'to' => '5.3.15.1',
        'tag' => '5.3.15.1-0.16.23', 'digest' => $digest, 'old_versions' => 51,
        'app_slots' => 1, 'allow_downgrade' => 1, 'plan_sha256' => $planHash,
        'definitions' => $before['children']];
    if ($mode === '--preview') {
        $db->rollback();
        echo json_encode($preview, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n";
        exit(0);
    }
    requireRelease(hash_equals($planHash, explode('=', $mode, 2)[1]), 'Catalogue or manifest changed since preview');
    $task = new Tasks\AppsTask();
    $task->setDI($di);
    ob_start();
    $task->importAppAction($manifest, '--import-version', '--app-id=66', '--set-default', []);
    $output = ob_get_clean();
    requireRelease(str_contains($output, 'Import complete!') && !str_contains($output, '[FAIL]'), 'Importer did not complete');
    $after = releaseSnapshot($db);
    requireRelease($after['children'] === $before['children'], 'Catalogue definitions changed');
    $oldApp = $before['app'];
    $newApp = $after['app'];
    foreach (['version', 'tag', 'updated_at'] as $field) {
        unset($oldApp[$field], $newApp[$field]);
    }
    $changed = array_keys(array_filter($newApp, static fn($value, $key) => $value !== $oldApp[$key], ARRAY_FILTER_USE_BOTH));
    requireRelease($oldApp === $newApp, 'Unexpected app changes: ' . implode(', ', $changed));
    requireRelease($after['app']['version'] === '5.3.15.1' && $after['app']['tag'] === '5.3.15.1-0.16.23', 'App default not updated');
    requireRelease(count($after['versions']) === 52, 'Expected exactly one new version');
    $new = array_pop($after['versions']);
    foreach ($before['versions'] as $index => $old) {
        $old['is_default'] = 0;
        requireRelease($after['versions'][$index] === $old, 'Previous version changed beyond its default flag');
    }
    foreach (['app_id' => 66, 'version' => '5.3.15.1', 'tag' => '5.3.15.1-0.16.23',
        'image' => 'rutorrent', 'installed_image_digest' => $digest, 'enabled' => 1,
        'is_default' => 1, 'admin_only' => 0, 'app_slots' => 1,
        'memory' => 0, 'memory_swap' => 0, 'memory_reservation' => 0, 'cpus' => 0,
        'pids_limit' => null, 'tcp_dynamic_ports' => 1, 'udp_dynamic_ports' => 1] as $key => $expected) {
        requireRelease($new[$key] === $expected, 'Unexpected new-version field: ' . $key);
    }
    $rehearsal = str_starts_with($mode, '--rehearse=');
    $rehearsal ? $db->rollback() : $db->commit();
    echo json_encode(['result' => $rehearsal ? 'rehearsed_and_rolled_back' : 'committed',
        'app_id' => 66, 'version_id' => $new['id'], 'version' => '5.3.15.1',
        'digest' => $digest, 'previous_versions_preserved' => 51,
        'definitions_preserved' => true, 'plan_sha256' => $planHash], JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n";
} catch (\Throwable $error) {
    if (ob_get_level() > 0) {
        ob_end_clean();
    }
    if ($db->isUnderTransaction()) {
        $db->rollback();
    }
    fwrite(STDERR, 'Release aborted: ' . $error->getMessage() . "\n");
    exit(1);
}
