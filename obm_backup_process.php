<?php

if (count($argv) == 2) backup_parse($argv[1]);
elseif (count($argv) == 3) form_parse($argv[2],$argv[1]);

function backup_parse($file) {
    $obm_backup_file = file($file);

    ## Creating valid JSON
    $j = json_decode($obm_backup_file[0],true);
    $jo = array();
    foreach ($j as $key=>$value) {
        $v = json_decode($value,true);
        $jo[$key] = $v;
    }

    ## Pretty print of JSON
    $je = json_encode($jo,JSON_PRETTY_PRINT|JSON_UNESCAPED_SLASHES|JSON_UNESCAPED_UNICODE);
    file_put_contents($file.".json", $je); 


}

function form_parse($file,$formId) {
    $json_file = file($file);
    $n = 0;
    // only on line
    $json = json_decode($json_file[0],true);
    foreach ($json as $j) {
        if (isset($j['data'])) {
            $header = array_keys($j['data']);
            $d = array_values($j['data']);
            $data = array();
            foreach ($j['data'] as $key=>$value) {
                if (is_array($value)) {
                    $data[] = implode_recursive(",",$value);
                } else {
                    $data[] = $value;
                }   
            }   
            $csv_data = sprintf("'%s'\n'%s'\n", implode("','",$header), implode("','",$data));
            $csv_file = sprintf("form_%d_row_%d.csv",$formId,$n);
            file_put_contents($csv_file, $csv_data);
        }
        $n++;
    }
}

function implode_recursive(string $separator, array $array): string
{
    $string = '';
    foreach ($array as $i => $a) {
        if (is_array($a)) {
            $string .= implode_recursive($separator, $a);
        } else {
            $string .= $a;
            if ($i < count($array) - 1) {
                $string .= $separator;
            }
        }
    }

    return $string;
}
?>
