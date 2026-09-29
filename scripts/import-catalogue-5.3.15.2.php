<?php
/** Guarded import of Appbox ruTorrent 5.3.15.2; run on farm from cylo-api. */
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

$mode = $argv[1] ?? '--preview';
requireRelease($mode === '--preview' || preg_match('/^--(?:apply|rehearse)=[a-f0-9]{64}$/D', $mode) === 1,
    'Usage: php import-catalogue-5.3.15.2.php [--preview|--rehearse=PLAN_SHA256|--apply=PLAN_SHA256]');
$api = '/usr/local/cylo-api';
$manifest = dirname(__DIR__) . '/appbox.yml';
$notes = 'rTorrent and libtorrent 0.16.24 fix DHT, tracker and metadata issues. ruTorrent stays at 5.3.15. If your custom config uses an ip%device bind address, switch to the new network.bind_device settings before updating.';
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
requireRelease(($definition['image']['version'] ?? '') === '5.3.15.2'
    && ($definition['image']['tag'] ?? '') === '5.3.15.2-0.16.24'
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
    $db->fetchAll('SELECT id FROM apps WHERE id=66 FOR UPDATE', \PDO::FETCH_ASSOC);
    $db->fetchAll('SELECT id FROM app_versions WHERE app_id=66 ORDER BY id FOR UPDATE', \PDO::FETCH_ASSOC);
    $before = releaseSnapshot($db);
    $defaults = array_values(array_filter($before['versions'], static fn($v) => $v['is_default'] === 1));
    requireRelease(count($before['versions']) === 52 && count($defaults) === 1 && $defaults[0]['id'] === 1335,
        'Expected 52 versions and sole default 1335');
    $oldDefault = $defaults[0];
    requireRelease($before['app']['version'] === '5.3.15.1'
        && $before['app']['tag'] === '5.3.15.1-0.16.23'
        && $before['app']['app_slots'] === 1 && $before['app']['allow_downgrade'] === 1,
        'Current app defaults changed');
    requireRelease($oldDefault['installed_image_digest'] === 'repo.cylo.net/rutorrent@sha256:fc8a15f0b42d7368b06cf1dd7d16dcb0b1d20d5a2a096f1a3dbfb9d9573e4644',
        'Previous image digest changed');
    foreach ($before['versions'] as $v) {
        requireRelease($v['version'] !== '5.3.15.2' && $v['tag'] !== '5.3.15.2-0.16.24', 'Release already exists');
    }
    $resourceFields = ['app_slots', 'min_memory', 'min_cpus', 'memory', 'memory_swap',
        'memory_reservation', 'cpus', 'pids_limit', 'init', 'privileged', 'cap_add',
        'cap_drop', 'tcp_port_range', 'udp_port_range', 'tcp_dynamic_ports',
        'udp_dynamic_ports', 'combined_port_range', 'combined_dynamic_ports'];
    $resources = array_intersect_key($oldDefault, array_flip($resourceFields));
    $planHash = hash('sha256', json_encode(['manifest' => hash_file('sha256', $manifest),
        'before' => $before, 'notes' => $notes], JSON_THROW_ON_ERROR));
    $preview = ['app_id' => 66, 'from_id' => 1335, 'from' => '5.3.15.1',
        'to' => '5.3.15.2', 'tag' => '5.3.15.2-0.16.24', 'digest' => $digest,
        'changes' => $notes, 'resource_baseline' => $resources, 'old_versions' => 52,
        'app_slots' => 1, 'allow_downgrade' => 1, 'plan_sha256' => $planHash,
        'definitions' => $before['children']];
    if ($mode === '--preview') {
        $db->rollback();
        echo json_encode($preview, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR) . "\n";
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
    requireRelease($oldApp === $newApp, 'App settings changed beyond the version and tag');
    requireRelease($after['app']['version'] === '5.3.15.2' && $after['app']['tag'] === '5.3.15.2-0.16.24',
        'App default not updated');
    requireRelease(count($after['versions']) === 53, 'Expected exactly one new version');
    $new = array_pop($after['versions']);
    foreach ($before['versions'] as $index => $old) {
        if ($old['id'] === 1335) {
            $old['is_default'] = 0;
        }
        requireRelease($after['versions'][$index] === $old, 'Previous version changed unexpectedly');
    }
    requireRelease($new['app_id'] === 66 && $new['version'] === '5.3.15.2'
        && $new['tag'] === '5.3.15.2-0.16.24' && $new['image'] === 'rutorrent'
        && $new['installed_image_digest'] === $digest && $new['enabled'] === 1
        && $new['is_default'] === 1 && $new['admin_only'] === 0,
        'New version identity or availability changed');
    foreach ($resources as $field => $value) {
        requireRelease($new[$field] === $value, 'Resource changed: ' . $field);
    }
    requireRelease($new['changes'] === null, 'Importer unexpectedly wrote changes');
    $db->execute('UPDATE app_versions SET changes=:changes WHERE id=:id AND app_id=66 AND changes IS NULL',
        ['changes' => $notes, 'id' => $new['id']]);
    requireRelease($db->affectedRows() === 1, 'Expected one release-notes row');
    $verified = $db->fetchOne('SELECT changes FROM app_versions WHERE id=:id AND app_id=66',
        \PDO::FETCH_ASSOC, ['id' => $new['id']]);
    requireRelease(($verified['changes'] ?? null) === $notes, 'Release notes failed readback');
    $rehearsal = str_starts_with($mode, '--rehearse=');
    $rehearsal ? $db->rollback() : $db->commit();
    echo json_encode(['result' => $rehearsal ? 'rehearsed_and_rolled_back' : 'committed',
        'app_id' => 66, 'version_id' => $new['id'], 'version' => '5.3.15.2',
        'digest' => $digest, 'previous_versions_preserved' => 52,
        'resources_preserved' => true, 'changes_saved' => true,
        'definitions_preserved' => true, 'plan_sha256' => $planHash],
        JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR) . "\n";
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
