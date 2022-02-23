<?php
/* 
   1) Create pwshare directory
   2) Create a .htaccess in it with the following content:
 
   Options -Indexes
   RewriteEngine On
   RewriteCond %{QUERY_STRING} (^$)
   RewriteRule ^$ http://YOUR-DOMAIN/pwshare.php [L,R=301]
 
 * */


if (isset($_GET['code']))
{
    # http://openbiomaps.org/pwshare.php?code=Ahshai9Ia4ohPh0cadak8aekueth8ier

    $file = basename($_GET['code']).'.txt';
    if (file_exists('pwshare/'.$file)) {
        $txt = file_get_contents('pwshare/'.$file);
        echo "<h2>$txt</h2>";
        unlink('pwshare/'.$file);
        exit;
    } 

}
elseif (isset($_POST['code'])) 
{
    #  curl -F 'code=Ahshai9Ia4ohPh0cadak8aekueth8ier' -F 'data=sulya<br>ksdfae5eiB0keiN' http://openbiomaps.org/pwshare.php

    if ($_POST['code']=='') {
        $key = bin2hex(openssl_random_pseudo_bytes(8));
    } else 
        $key = substr($_POST['code'],0,32);

    if (!file_exists('pwshare/'.$key)) {
        file_put_contents('pwshare/'.basename($key).".txt",$_POST['data']);
        echo "http://".$_SERVER['SERVER_NAME']."/pwshare.php?code=".$key."\n";
    }
}
else {
    echo "<form method='post'>One click link generation for the following text:<br><textarea name='data' rows=3 cols=45></textarea><br><input type='submit'></form>";
}
?>
