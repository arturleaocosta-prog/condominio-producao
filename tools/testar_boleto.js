// Teste dos boletos de teste: node tools/testar_boleto.js
const path=require('path');const BOL=require(path.join(__dirname,'..','boleto.js'));const COB=require(path.join(__dirname,'..','cobranca.js'));const FIN=require(path.join(__dirname,'..','data','financeiro.json'));
let falhas=0;const ok=(c,m)=>{if(!c){falhas++;console.log('FALHOU:',m)}};
// 1) Algoritmos contra exemplo público (linha 00190.50095 40144.816069 06809.350314 3 37370000000100)
const cb='00193373700000001000500940144816060680935031';
ok(BOL.linhaDigitavel(cb)==='00190.50095 40144.816069 06809.350314 3 37370000000100','linha digitável do exemplo público');
ok(BOL.barrasDaLinha('00190.50095 40144.816069 06809.350314 3 37370000000100')===cb,'linha -> código de barras');
ok(BOL.mod11(cb.slice(0,4)+cb.slice(5))===3,'DV geral do exemplo');
// 2) Fator de vencimento nos limites do ciclo
ok(BOL.fator('2025-02-21')===9999&&BOL.fator('2025-02-22')===1000&&BOL.fator('2000-07-03')===1000,'fator de vencimento');
// 3) Todos os boletos de Nov-2026 conferem e somam o total da cobrança
const res=COB.build(FIN,'2026-11',{vencimento:'2026-11-10'});
const benef={nome:'CONDOMINIO DE TESTE',cnpj:'00.000.000/0000-00',agencia:'0000',codigo:'000000'};
const bs=res.rows.map((r,i)=>BOL.build(res,r,{benef,pagador:'Pagador teste '+r.unidade,seq:i+1}));
bs.forEach((b,i)=>{const p=BOL.validar(b,res.rows[i].total);ok(!p.length,'boleto '+b.unidade+': '+p.join('; '));ok(b.linhaDigitavel.replace(/\D/g,'').length===47,'47 dígitos '+b.unidade);ok(/<svg/.test(BOL.boletoHTML(b)),'html '+b.unidade)});
ok(bs.reduce((s,b)=>s+b.valor,0)===res.totalCentavos,'soma dos boletos = total');
ok(new Set(bs.map(b=>b.nossoNumero)).size===bs.length,'nosso número único');
// 4) Adulteração é detectada
const x=Object.assign({},bs[0],{valor:bs[0].valor+1});ok(BOL.validar(x).length>0,'valor adulterado deve ser detectado');
const y=Object.assign({},bs[0],{linhaDigitavel:bs[0].linhaDigitavel.replace(/\d(?=\D*$)/,d=>(+d+1)%10)});ok(BOL.validar(y).length>0,'linha adulterada deve ser detectada');
// 5) ITF: nº de barras
const svg=BOL.itfSVG('0'.repeat(44));ok((svg.match(/<rect/g)||[]).length===2+22*5+2,'barras ITF');
console.log(falhas?falhas+' falha(s)':'Todos os testes de boleto passaram.');process.exit(falhas?1:0);
