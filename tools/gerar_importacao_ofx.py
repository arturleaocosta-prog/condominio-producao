#!/usr/bin/env python3
"""Gera o SQL de importação de um extrato OFX (conta corrente) para o livro-caixa.
Uso:  python3 tools/gerar_importacao_ofx.py extrato.ofx saida.sql [--propor] [--palpites]
  --propor    só mostra a classificação proposta e o que falta confirmar (não escreve o SQL)
  --palpites  usa os palpites para itens ainda não confirmados (SOMENTE para teste local; nunca entregar)
Falha fechado: movimento sem classificação confirmada impede a geração. Não faz chamada de rede.
O SQL gerado contém dados reais: NÃO publicar. O OFX não identifica o morador: cotas entram agregadas por dia."""
import sys, re, hashlib
from decimal import Decimal as D

# ---- confirmações do síndico (chave: AAAA-MM-DD|centavos|MEMO) -> (tipo, categoria, descricao, fornecedor)
CONFIRMADOS = {   # confirmados pelo síndico em 28/10/2026 (os três primeiros por padrão de meses anteriores; os dois últimos informados por ele)
    '2026-10-08|131038|DEB PIX CHAVE': ('despesa', 'Obras', 'Reembolso Lilian - Obra Interna 4ª parcela', None),
    '2026-10-08|108202|PAGAMENTO DE BOLETO': ('despesa', 'Limpeza', 'Ideal Assessoria Ltda', 'Ideal Assessoria Ltda'),
    '2026-10-19|372674|PAGAMENTO DE BOLETO': ('despesa', 'Obras', '2M Construtora Ltda', '2M Construtora Ltda'),
    '2026-10-19|30840|PAGAMENTO DE BOLETO': ('despesa', 'Honorários', 'Contabilidade (Wramos Gerenciamento Contábil)', 'Wramos Gerenciamento Contábil Ltda'),
    '2026-10-19|44500|PAGAMENTO DE BOLETO': ('despesa', 'Gás', 'Aquisição de botijão de gás', None),
}
PALPITES = {}   # (vazio) itens ainda não confirmados entram aqui; sem confirmação o gerador recusa
def sql(s): return 'null' if s is None else "'" + s.replace("'", "''") + "'"

def le_ofx(caminho):
    t = open(caminho, encoding='cp1252', errors='replace').read()
    lin = []
    for x in re.findall(r'<STMTTRN>(.*?)</STMTTRN>', t, re.S):
        g = lambda k: (re.search(r'<' + k + r'>([^<\r\n]*)', x) or [None, ''])[1].strip()
        v = D(g('TRNAMT'))
        d = g('DTPOSTED')[:8]
        lin.append((f'{d[:4]}-{d[4:6]}-{d[6:8]}', int((v * 100).to_integral_value()), (g('MEMO') or g('NAME')).upper()))
    bal = re.search(r'<LEDGERBAL>.*?<BALAMT>([-\d.]+).*?<DTASOF>(\d{8})', t, re.S)
    ini = re.search(r'<DTSTART>(\d{8})', t).group(1); fim = re.search(r'<DTEND>(\d{8})', t).group(1)
    return lin, int((D(bal.group(1)) * 100).to_integral_value()), bal.group(2), ini, fim

def classifica(dt, cent, memo, palpites):
    chave = f'{dt}|{abs(cent)}|{memo}'
    if chave in CONFIRMADOS: return CONFIRMADOS[chave], 'confirmado'
    dd = f'{dt[8:10]}/{dt[5:7]}'
    if memo == 'COB COMPE' and cent > 0: return ('receita', 'Taxa condominial', f'Cotas recebidas por boleto — liquidação de {dd}', None), 'regra'
    if memo == 'COB COMPE' and cent < 0:
        n = abs(cent) // 630
        return ('despesa', 'Outras despesas', f'Tarifa de cobrança bancária ({n} boleto{"s" if n > 1 else ""})', None), 'regra'
    if memo == 'TAR PIX': return ('despesa', 'Outras despesas', 'Tarifa PIX', None), 'regra'
    if memo == 'AGUA': return ('despesa', 'Água e esgoto', 'Copasa — água e esgoto', 'Copasa'), 'regra'
    if memo == 'LUZ': return ('despesa', 'Energia das áreas comuns', 'Cemig — energia das áreas comuns', 'Cemig'), 'regra'
    if memo == 'PAGAMENTO ORGAO GOVERNO': return ('despesa', 'Taxas e impostos', 'DARF — conservadora (Ideal)', None), 'regra'
    if chave in PALPITES: return (PALPITES[chave], 'palpite') if palpites else (None, 'pendente')
    return None, 'pendente'

def main(argv):
    ofx, saida = argv[1], argv[2]; propor = '--propor' in argv; palpites = '--palpites' in argv
    lin, saldo, dt_saldo, ini, fim = le_ofx(ofx)
    itens, pend = [], []
    print(f'Período do extrato: {ini[6:]}/{ini[4:6]} a {fim[6:]}/{fim[4:6]} | {len(lin)} movimentos | saldo final {saldo/100:,.2f} em {dt_saldo[6:]}/{dt_saldo[4:6]}')
    for dt, cent, memo in lin:
        c, origem = classifica(dt, cent, memo, palpites)
        print(f'  {dt[8:10]}/{dt[5:7]} {cent/100:>10.2f}  {memo:<26} -> {origem:<10} {(c[1] + " | " + c[2]) if c else "—"}')
        if c is None or origem == 'palpite' and not palpites: pend.append((dt, cent, memo))
        else: itens.append((dt, cent, memo, c, origem))
    abertura_final = None
    soma = sum(cent for _, cent, _ in lin)
    print(f'saldo inicial implícito (final − movimentos): {(saldo - soma)/100:,.2f}')
    if propor or pend:
        if pend: print(f'\n{len(pend)} movimento(s) sem classificação confirmada:'); [print('  ', p) for p in pend]
        return 0 if propor else 2
    if palpites: print('\n*** ATENÇÃO: usando PALPITES. Arquivo apenas para teste local. ***')
    ant = saldo - soma
    for (_, _, _, (tipo, *_), _), (_, cent, _) in zip(itens, lin):
        assert (tipo == 'receita') == (cent > 0)
    vals = ',\n'.join("    (%s::date, %s, %d, %s, %s, %s)" % ("'%s'" % dt, sql(c[0]), abs(cent), sql(c[1]), sql(c[2]), sql(c[3])) for dt, cent, memo, c, _ in itens)
    inicio = min(d for d, _, _ in lin); fim_d = max(d for d, _, _ in lin)
    out = f"""-- Importação ÚNICA do extrato OFX de {inicio[8:]}/{inicio[5:7]} a {fim_d[8:]}/{fim_d[5:7]}/{fim_d[:4]} (conta corrente).
-- Gerado por tools/gerar_importacao_ofx.py. CONTÉM DADOS REAIS: não publicar nem versionar em repositório público.
-- Pré-requisitos: migrações 001 a 007 e IMPORTAR_JUL_SET_2026.sql já executados. Uma única transação: se algo não bater, nada é gravado.
-- Observação: o OFX não identifica o morador; as cotas entram somadas por dia de liquidação.
do $imp$
declare v_cond uuid; v_user uuid; v_n int; v_saldo bigint;
begin
  select id into v_cond from public.condominios where nome = 'Edifício Valença';
  if v_cond is null then raise exception 'Condomínio "Edifício Valença" não encontrado'; end if;
  select user_id into v_user from public.perfis where condominio_id = v_cond and papel = 'sindico' and ativo order by created_at limit 1;
  if v_user is null then raise exception 'Perfil de síndico ativo não encontrado'; end if;
  if not exists (select 1 from public.auditoria where condominio_id = v_cond and acao = 'importar_conciliacao_2026_07_09') then
    raise exception 'Rode antes IMPORTAR_JUL_SET_2026.sql'; end if;
  if exists (select 1 from public.auditoria where condominio_id = v_cond and acao = 'importar_ofx_{inicio[:7].replace("-", "_")}') then
    raise exception 'Esta importação já foi executada; não rode de novo'; end if;
  if exists (select 1 from public.lancamentos where condominio_id = v_cond and data_lancamento >= date '{inicio}') then
    raise exception 'Já existem lançamentos a partir de {inicio[8:]}/{inicio[5:7]}/{inicio[:4]}; confira antes de importar (lançamentos não podem ser apagados)'; end if;
  select saldo_inicial_centavos + coalesce((select sum(case when tipo = 'receita' then valor_centavos else -valor_centavos end) from public.lancamentos where condominio_id = v_cond), 0)
    into v_saldo from public.condominios where id = v_cond;
  if v_saldo <> {ant} then raise exception 'Saldo do livro-caixa antes desta importação = % (o extrato indica {ant})', v_saldo; end if;

  insert into public.lancamentos (condominio_id, tipo, data_lancamento, competencia, valor_centavos, categoria, descricao, fornecedor, criado_por)
  select v_cond, l.tipo::public.tipo_lancamento, l.data_l, date_trunc('month', l.data_l)::date, l.valor, l.categoria, l.descricao, l.fornecedor, v_user
    from (values
{vals}
    ) as l(data_l, tipo, valor, categoria, descricao, fornecedor);
  get diagnostics v_n = row_count;
  if v_n <> {len(itens)} then raise exception 'Esperava {len(itens)} lançamentos, gravou %', v_n; end if;

  select saldo_inicial_centavos + coalesce((select sum(case when tipo = 'receita' then valor_centavos else -valor_centavos end) from public.lancamentos where condominio_id = v_cond), 0)
    into v_saldo from public.condominios where id = v_cond;
  if v_saldo <> {saldo} then raise exception 'Saldo após a importação = % (esperado {saldo}, o saldo do extrato em {dt_saldo[6:]}/{dt_saldo[4:6]})', v_saldo; end if;

  insert into public.auditoria (condominio_id, user_id, acao, entidade, detalhes)
  values (v_cond, v_user, 'importar_ofx_{inicio[:7].replace("-", "_")}', 'lancamentos', jsonb_build_object('lancamentos', v_n, 'saldo_final_centavos', v_saldo, 'extrato_ate', '{fim_d}'));
end $imp$;

-- Conferência visual: saldo final = R$ {saldo/100:,.2f}
select count(*) as lancamentos_outubro, round(coalesce(sum(valor_centavos) filter (where tipo = 'receita'), 0) / 100.0, 2) as entradas, round(coalesce(sum(valor_centavos) filter (where tipo = 'despesa'), 0) / 100.0, 2) as saidas
  from public.lancamentos where data_lancamento >= date '{inicio}';
"""
    open(saida, 'w', encoding='utf-8').write(out)
    print(f'\nSQL gravado em {saida}: {len(itens)} lançamentos | saldo inicial {ant/100:,.2f} | saldo final {saldo/100:,.2f}')
    return 0

if __name__ == '__main__': sys.exit(main(sys.argv))
