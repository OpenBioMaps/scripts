<?php

$f = $argv[1];

$obm_backup_file = file($f);

## Creating valid JSON
$j = json_decode($obm_backup_file[0],true);
$jo = array();
foreach ($j as $key=>$value) {
    $v = json_decode($value,true);
    $jo[$key] = $v;
}

## Pretty print of JSON
$je = json_encode($jo,JSON_PRETTY_PRINT|JSON_UNESCAPED_SLASHES|JSON_UNESCAPED_UNICODE);
file_put_contents($f.".json", $je); 

?>
