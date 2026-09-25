<?php
/** One-time, notes-only ruTorrent catalogue backfill; run on farm from cylo-api. */
namespace Cylo;

use Library\App\Constants\Services as AppServices;

function requireNotes(bool $ok, string $message): void
{
    if (!$ok) {
        throw new \RuntimeException($message);
    }
}

function notesSnapshot($db): array
{
    return $db->fetchAll(
        "SELECT id, version, tag, changes, md5((to_jsonb(v)-'changes')::text) AS unchanged_hash
         FROM app_versions v WHERE app_id=66 ORDER BY id",
        \PDO::FETCH_ASSOC
    );
}

$mode = $argv[1] ?? '--preview';
requireNotes($mode === '--preview' || preg_match('/^--(?:apply|rehearse)=[a-f0-9]{64}$/D', $mode) === 1,
    'Usage: php backfill-catalogue-notes-20260925.php [--preview|--rehearse=PLAN_SHA256|--apply=PLAN_SHA256]');
$planPath = __DIR__ . '/catalogue-notes-20260925.json';
$plan = json_decode(file_get_contents($planPath), true, 512, JSON_THROW_ON_ERROR);
requireNotes(array_column($plan, 'id') === [1302, 1308, 1321, 1322, 1324, 1335], 'Unexpected target IDs');
$planHash = hash_file('sha256', $planPath);
if ($mode !== '--preview') {
    requireNotes(hash_equals($planHash, explode('=', $mode, 2)[1]), 'Plan differs from the reviewed preview');
}

$api = '/usr/local/cylo-api';
define('CLI', true);
define('VERSION', '1.0.0');
$di = new \Phalcon\Di\FactoryDefault\Cli();
require $api . '/app/bootstrap/loader.php';
$config = require $api . '/app/bootstrap/config.php';
require $api . '/app/bootstrap/services.php';
$db = $di->getShared(AppServices::DB);
register_shutdown_function(static function () use ($db): void {
    if ($db->isUnderTransaction()) {
        $db->rollback();
        fwrite(STDERR, "Unfinished backfill rolled back\n");
        exit(1);
    }
});

try {
    $db->begin();
    $db->execute("SET LOCAL lock_timeout='5s'");
    $db->execute("SET LOCAL statement_timeout='30s'");
    // Lock concrete rows before taking the snapshot, never an aggregate query.
    $db->fetchAll('SELECT id FROM apps WHERE id=66 FOR UPDATE', \PDO::FETCH_ASSOC);
    $db->fetchAll('SELECT id FROM app_versions WHERE app_id=66 ORDER BY id FOR UPDATE', \PDO::FETCH_ASSOC);
    $appSql = 'SELECT md5(to_jsonb(a)::text) AS hash FROM apps a WHERE id=66';
    $appBefore = $db->fetchOne($appSql, \PDO::FETCH_ASSOC);
    requireNotes(($appBefore['hash'] ?? '') === '914a01900982cc2270e1165dd0c6d9d6', 'App settings changed');
    $before = notesSnapshot($db);
    requireNotes(count($before) === 52, 'Expected 52 existing ruTorrent versions');
    $byId = array_column($before, null, 'id');
    foreach ($plan as $entry) {
        $row = $byId[$entry['id']] ?? null;
        requireNotes($row !== null && $row['version'] === $entry['version'] && $row['tag'] === $entry['tag']
            && $row['unchanged_hash'] === $entry['unchanged_hash'] && $row['changes'] === null,
            'Version state changed: ' . $entry['id']);
        requireNotes(is_string($entry['changes']) && trim($entry['changes']) !== '', 'Empty release notes');
    }
    $preview = ['app_id' => 66, 'target_count' => 6, 'plan_sha256' => $planHash,
        'only_updated_column' => 'changes', 'previous_changes' => null, 'entries' => $plan];
    if ($mode === '--preview') {
        $db->rollback();
        echo json_encode($preview, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR) . "\n";
        exit(0);
    }
    $expected = $before;
    foreach ($plan as $entry) {
        $db->execute('UPDATE app_versions SET changes=:notes WHERE id=:id AND app_id=66 AND changes IS NULL',
            ['notes' => $entry['changes'], 'id' => $entry['id']]);
        requireNotes($db->affectedRows() === 1, 'Expected one updated row: ' . $entry['id']);
        foreach ($expected as &$row) {
            if ((int) $row['id'] === $entry['id']) {
                $row['changes'] = $entry['changes'];
            }
        }
        unset($row);
    }
    requireNotes(notesSnapshot($db) === $expected, 'Unexpected version changes after backfill');
    requireNotes($db->fetchOne($appSql, \PDO::FETCH_ASSOC) === $appBefore, 'App settings changed');
    $rehearsal = str_starts_with($mode, '--rehearse=');
    $rehearsal ? $db->rollback() : $db->commit();
    echo json_encode(['result' => $rehearsal ? 'rehearsed_and_rolled_back' : 'committed',
        'app_id' => 66, 'updated_versions' => array_column($plan, 'id'), 'plan_sha256' => $planHash,
        'all_other_version_fields_preserved' => true, 'other_versions_preserved' => 46,
        'app_settings_preserved' => true], JSON_PRETTY_PRINT | JSON_THROW_ON_ERROR) . "\n";
} catch (\Throwable $error) {
    if ($db->isUnderTransaction()) {
        $db->rollback();
    }
    fwrite(STDERR, 'Backfill aborted: ' . $error->getMessage() . "\n");
    exit(1);
}
