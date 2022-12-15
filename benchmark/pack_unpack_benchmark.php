<?php

$start = microtime(true);

$result = '';
for($i=0; $i < 100000000;$i++)
{
    $result = pack("iiii",64,65,66,67);
}

$time_elapsed_secs = microtime(true) - $start;
echo("result: $result\r\n");
echo $time_elapsed_secs;
//C:\php-8.2.0-nts-Win32-vs16-x64\php.exe