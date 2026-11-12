/* Testes do leitor de OFX (ofx.js). Uso: node tools/testar_ofx.js */
const O = require('../ofx.js'); const nodeCrypto = require('crypto');
let ok = 0, bad = 0; const check = (n, c, i) => { if (c) ok++; else { bad++; console.log('FALHOU:', n, i || ''); } };
const erro = (n, txt, trecho) => { try { O.parse(txt); check(n, false, 'não deu erro'); } catch (e) { check(n, e.message.includes(trecho), e.message); } };
const sgml = (movs, extra) => 'OFXHEADER:100\r\nDATA:OFXSGML\r\nVERSION:102\r\nSECURITY:NONE\r\nENCODING:USASCII\r\nCHARSET:1252\r\nCOMPRESSION:NONE\r\nOLDFILEUID:NONE\r\nNEWFILEUID:NONE\r\n\r\n<OFX><SIGNONMSGSRSV1><SONRS><STATUS><CODE>0<SEVERITY>INFO</STATUS><DTSERVER>20261021125018.767<LANGUAGE>POR</SONRS></SIGNONMSGSRSV1>' +
  '<BANKMSGSRSV1><STMTTRNRS><TRNUID>1001<STATUS><CODE>0<SEVERITY>INFO</STATUS><STMTRS><CURDEF>BRL<BANKACCTFROM><BANKID>104<BRANCHID>0001<ACCTID>999999999<ACCTTYPE>CHECKING</BANKACCTFROM><BANKTRANLIST><DTSTART>20261001030000.000<DTEND>20261021030000.000' +
  movs + '</BANKTRANLIST>' + (extra === undefined ? '<LEDGERBAL><BALAMT>4122.32<DTASOF>20261021030000.000</LEDGERBAL>' : extra) + '</STMTRS></STMTTRNRS></BANKMSGSRSV1></OFX>';
const mov = (dt, v, memo, fit) => '<STMTTRN><TRNTYPE>' + (v < 0 ? 'DEBIT' : 'CREDIT') + '<DTPOSTED>' + dt + '030000.000<TRNAMT>' + v + '<FITID>' + (fit || '090101') + '<CHECKNUM>1<MEMO>' + memo + '</STMTTRN>';
// 1) SGML sem tags de fechamento, valores com ponto, FITID repetido
let r = O.parse(sgml(mov('20261001', 1179.18, 'COB COMPE', '290926') + mov('20261001', -6.3, 'COB COMPE', '290926') + mov('20261008', -1310.38, 'DEB PIX CHAVE', '081045')));
check('SGML: 3 movimentos', r.movimentos.length === 3);
check('SGML: valores em centavos com sinal', r.movimentos.map(m => m.valor_centavos).join() === '117918,-630,-131038');
check('SGML: datas', r.movimentos.map(m => m.data).join() === '2026-10-01,2026-10-01,2026-10-08');
check('SGML: período e saldo', r.periodo_ini === '2026-10-01' && r.periodo_fim === '2026-10-21' && r.saldo_final_centavos === 412232 && r.saldo_data === '2026-10-21');
check('SGML: entradas, saídas e saldo inicial implícito', r.entradas_centavos === 117918 && r.saidas_centavos === 131668 && r.saldo_inicial_implicito_centavos === 412232 - (117918 - 131668));
check('SGML: FITID repetido não atrapalha', r.movimentos[0].fitid === r.movimentos[1].fitid);
check('o resultado NÃO contém número de conta nem agência', !/999999999|ACCTID|BRANCHID/.test(JSON.stringify(r)));
check('ordem 1..n preservada', r.movimentos.map(m => m.ordem).join() === '1,2,3');
// 2) codificação Windows-1252 (acentos)
const buf = Buffer.from(sgml(mov('20261002', -50, 'PAGAMENTO DE SERVIÇO À VISTA – AÇÃO'), ''), 'latin1');
check('CP1252: acentos decodificados', O.parse(O.decodificar(buf)).movimentos[0].memo.startsWith('PAGAMENTO DE SERVIÇO À VISTA'));
// 3) XML 2.x em UTF-8, NAME no lugar de MEMO, entidades
const xml = '<?xml version="1.0" encoding="UTF-8"?><OFX><BANKMSGSRSV1><STMTTRNRS><STMTRS><CURDEF>BRL</CURDEF><BANKTRANLIST><DTSTART>20260901</DTSTART><DTEND>20260930</DTEND><STMTTRN><TRNTYPE>DEBIT</TRNTYPE><DTPOSTED>20260915120000[-3:BRT]</DTPOSTED><TRNAMT>-12.50</TRNAMT><FITID>1</FITID><NAME>A &amp; B   Ltda</NAME></STMTTRN></BANKTRANLIST><LEDGERBAL><BALAMT>100.00</BALAMT><DTASOF>20260930</DTASOF></LEDGERBAL></STMTRS></STMTTRNRS></BANKMSGSRSV1></OFX>';
r = O.parse(O.decodificar(Buffer.from(xml, 'utf8')));
check('XML: NAME, entidade e espaços normalizados', r.movimentos[0].memo === 'A & B Ltda' && r.movimentos[0].data === '2026-09-15' && r.movimentos[0].valor_centavos === -1250);
// 4) vírgula decimal e milhar
r = O.parse(sgml(mov('20261003', '-1.310,38', 'X') + mov('20261003', '2.500,5', 'Y') + mov('20261003', '100,00', 'Z')));
check('vírgula decimal e ponto de milhar', r.movimentos.map(m => m.valor_centavos).join() === '-131038,250050,10000');
// 5) sem LEDGERBAL e sem DTSTART
r = O.parse(sgml(mov('20261005', -1, 'A') + mov('20261004', 2, 'B'), '').replace('<DTSTART>20261001030000.000<DTEND>20261021030000.000', ''));
check('sem saldo: saldo nulo e período pelos movimentos', r.saldo_final_centavos === null && r.saldo_inicial_implicito_centavos === null && r.periodo_ini === '2026-10-04' && r.periodo_fim === '2026-10-05');
// 6) chave de duplicidade normaliza espaços e caixa
check('chave ignora caixa e espaços repetidos', O.chave({ data: '2026-10-01', valor_centavos: -630, memo: 'cob   compe ' }) === O.chave({ data: '2026-10-01', valor_centavos: -630, memo: 'COB COMPE' }));
check('chave distingue valor e data', O.chave({ data: '2026-10-01', valor_centavos: -630, memo: 'A' }) !== O.chave({ data: '2026-10-02', valor_centavos: -630, memo: 'A' }));
// 7) erros claros
erro('não é OFX', 'qualquer coisa', 'não parece ser um extrato OFX');
erro('sem movimentos', sgml(''), 'nenhum movimento');
erro('data inválida', sgml(mov('20261340', -1, 'A')), 'inexistente');
erro('data ilegível', sgml('<STMTTRN><DTPOSTED>abc<TRNAMT>-1<MEMO>A</STMTTRN>'), 'inválida');
erro('valor inválido', sgml('<STMTTRN><DTPOSTED>20261001<TRNAMT>abc<MEMO>A</STMTTRN>'), 'Valor inválido');
erro('valor zero', sgml(mov('20261001', 0, 'A')), 'valor zero');
erro('cartão de crédito', sgml(mov('20261001', -1, 'A')).replace('<STMTRS>', '<CCSTMTRS>'), 'cartão de crédito');
erro('duas contas', sgml(mov('20261001', -1, 'A')).replace('<BANKTRANLIST>', '</STMTRS><STMTRS><BANKTRANLIST>'), 'mais de uma conta');
erro('moeda diferente', sgml(mov('20261001', -1, 'A')).replace('<CURDEF>BRL', '<CURDEF>USD'), 'não é BRL');
erro('arquivo grande demais', sgml(Array.from({ length: 2001 }, (_, i) => mov('20261001', -(i + 1), 'M' + i)).join('')), 'mais de 2000');
// 8) SHA-256
(async () => {
  const h = await O.sha256(Buffer.from('abc'));
  check('SHA-256 do arquivo', h === nodeCrypto.createHash('sha256').update('abc').digest('hex'));
  console.log('Leitor de OFX: ' + ok + ' passaram, ' + bad + ' falharam.'); process.exit(bad ? 1 : 0);
})();
