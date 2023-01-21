<?php
//;charset=latin1
$dsn = 'pgsql:dbname=siamweb;host=localhost';
$user = 'postgres';
$password = 's1sadm1n';

$pdo = new PDO($dsn, $user, $password);

//statement: DEALLOCATE pdo_stmt_00000001
// $st = $pdo->prepare('select "nome" from esic.lda_solicitante where "idsolicitante" = ? limit 1');
// $st->execute([3]);
// $result = $st->fetch(PDO::FETCH_NUM);



 setInterval(function() use ($pdo){
    $result = $pdo->query("
    SELECT
        DISTINCT a.ordem,
        m.cod_modulo,
        m.nom_modulo,
        f.cod_funcionalidade,
        f.nom_funcionalidade,
        a.nom_acao,
        a.nom_arquivo,
        a.parametro,
        a.complemento_acao,
        f.nom_diretorio as func_dir,
        m.nom_diretorio as mod_dir,
        g.nom_diretorio as gest_dir,
        a.cod_acao,
        a.habilitada
    FROM
        administracao.gestao as g,
        administracao.modulo as m,
        administracao.funcionalidade as f,
        administracao.acao as a,
        administracao.permissao as p
    WHERE
        g.cod_gestao = m.cod_gestao AND
        m.cod_modulo = f.cod_modulo AND
        f.cod_funcionalidade = a.cod_funcionalidade AND
        a.cod_acao = p.cod_acao AND
        a.cod_funcionalidade in (8,109,266,13,7,9,40,1,3,4,5,6,26,58,59,126,212,164,298,10) AND
        p.numcgm='0' AND
        p.ano_exercicio = '2019'
    ORDER by
        a.ordem
    
    ")->fetch(PDO::FETCH_NUM);
    print_r($result);
}, 1000);
 // Create and start timer firing after 2 seconds
// $w1 = new EvTimer(2, 0, function () {
//     echo "2 seconds elapsed\n";
// });

function setInterval($f, $milliseconds)
{
    $seconds=(int)$milliseconds/1000;
    while(true)
    {
        $f();
        sleep($seconds);
    }
}