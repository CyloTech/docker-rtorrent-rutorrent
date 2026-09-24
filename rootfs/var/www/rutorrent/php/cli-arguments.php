<?php

function ruTorrentPhpCliHasArguments($php)
{
	// PHP 8.5 reports register_argc_argv=0 even when CLI arguments work.
	$probe = 'if (isset($argv[1]) && $argv[1] === "rutorrent-argv-check") echo "rutorrent-argv-ok";';
	$output = array();
	$status = 1;
	exec(escapeshellarg($php).' -r '.escapeshellarg($probe).' -- rutorrent-argv-check 2>/dev/null', $output, $status);
	return($status === 0 && $output === array('rutorrent-argv-ok'));
}
