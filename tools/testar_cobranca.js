// Teste do cálculo da cobrança mensal: node tools/testar_cobranca.js
const path=require('path');const COB=require(path.join(__dirname,'..','cobranca.js'));const FIN=require(path.join(__dirname,'..','data','financeiro.json'));
let falhas=0;const ok=(c,m)=>{if(!c){falhas++;console.log('FALHOU:',m)}};
// Valores conferidos contra a função SQL gerar_cobranca_mensal (PostgreSQL 16) com a previsão de Nov-2026, vencimento 10/11/2026.
const esperado={'01':94588,'02':93918,'101':94321,'102':92460,'201':96113,'202':96081,'301':97272,'302':106649};
const r=COB.build(FIN,'2026-11',{vencimento:'2026-11-10'});
r.rows.forEach(x=>ok(x.total===esperado[x.unidade],'total da unidade '+x.unidade+': '+x.total));
ok(r.totalCentavos===771402,'total do ciclo');
ok(!r.temErro,'Nov-2026 não deve ter erro');
// Em todos os meses: a água fecha exatamente na fatura e não há erro de cálculo (com vencimento informado).
FIN.meses.forEach(m=>{const x=COB.build(FIN,m.id,{vencimento:m.id+'-28'});const a=x.rows.reduce((s,q)=>s+q.itens.filter(i=>i.tipo==='agua').reduce((z,i)=>z+i.centavos,0),0);ok(a===Math.round(m.previsao.agua.fatura*100),'água '+m.id);ok(!x.temErro,'erro em '+m.id)});
ok(COB.build(FIN,'2026-11',{}).temErro,'sem vencimento deve dar erro');
ok(COB.ratear(10001,[{id:'a',f7:5000000},{id:'b',f7:5000000}]).a===5001,'desempate do maior resto');
console.log(falhas?falhas+' falha(s)':'Todos os testes passaram.');process.exit(falhas?1:0);
