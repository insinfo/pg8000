<?php

$start = microtime(true);

$result = '';
for($i=0; $i < 100000000;$i++)
{
    $result = pack("ii",64,64);
}
//$result = 4582585 + 45465465.0;
$time_elapsed_secs = microtime(true) - $start;
echo("result: $result");
echo $time_elapsed_secs;
//C:\php-8.2.0-nts-Win32-vs16-x64\php.exe