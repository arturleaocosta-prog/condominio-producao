#!/usr/bin/env python3
"""Gera o SQL de importação dos lançamentos da planilha de Conciliação Bancária (conta corrente).
Uso: python3 tools/gerar_importacao_conciliacao.py "Conciliação_Bancaria_Valença.xlsx" docs/IMPORTAR_JUL_SET_2026.sql
Lê as abas Jul-2026, Ago-2026 e Set-2026. Não faz chamada de rede. O SQL gerado contém dados reais: NÃO publicar."""
import sys, re, datetime, openpyxl
from decimal import Decimal as D

ABAS = ['Jul-2026', 'Ago-2026', 'Set-2026']
UNIDADES = {'SEBASTIAO MORAIS SIQUEIRA': '01', 'LARA CRISTINA RODRIGUES COELHO': '02', 'IRENY MARIA VIEIRA': '101',
            'THIAGO DINIZ GONZAGA DE LIMA': '102', 'JANAINA VIAL': '201', 'ERICA SHISLENE REZENDE PINTO': '202',
            'ARTUR LEAO COSTA': '301', 'CELSO CERQUEIRA REIS': '302'}
CNPJ = re.compile(r'\s*\d{2}\.\d{3}\.\d{3}/\d{4}-\d{2}')

def num(x):
    if isinstance(x, (int, float)): return D(str(x))
    if isinstance(x, str) and re.search(r'\d', x): return D(re.sub(r'[^\d.-]', '', x.replace(',', '')))
    return None
def centavos(x): return int((D(str(x)) * 100).to_integral_value()) if isinstance(x, (int, float)) and x else 0
def data(x):
    if isinstance(x, datetime.datetime): return x.date()
    if isinstance(x, (int, float)) and x > 40000: return datetime.date(1899, 12, 30) + datetime.timedelta(days=int(x))
def limpa(s): return re.sub(r'\s+', ' ', str(s or '')).strip()
def sql(s):
    return 'null' if s is None or s == '' else "'" + s.replace("'", "''") + "'"

def classifica(desc, cat, obs, entrada):
    d, o = desc.upper(), (obs or '').upper()
    if cat == 'Cota condominial': return 'receita', 'Taxa condominial'
    if cat == 'Juros/Multa recebido': return 'receita', 'Outras receitas'
    if cat == 'Água COPASA': return 'despesa', 'Água e esgoto'
    if cat == 'Energia elétrica': return 'despesa', 'Energia das áreas comuns'
    if cat == 'Limpeza': return 'despesa', ('Taxas e impostos' if 'DARF' in d else 'Limpeza')
    if cat == 'Seguro': return 'despesa', 'Seguro'
    if cat in ('Administração', 'Contabilidade'): return 'despesa', 'Honorários'
    if cat == 'Fundo de reserva' or 'TRANSFERÊNCIA APLICAÇÃO' in d or 'TRANSFERENCIA APLICACAO' in d: return 'despesa', 'Fundo de reserva'
    if 'CAICARA GAS' in d: return 'despesa', 'Gás'
    if cat == 'Manutenção':
        if '2M CONSTRUTORA' in d or 'OBRA' in o: return 'despesa', 'Obras'
        return 'despesa', 'Manutenção e reparos'
    if cat == 'Outros - saída': return 'despesa', 'Outras despesas'
    raise ValueError('categoria sem regra: %r (%s)' % (cat, desc))

def descreve(desc, cat, obs, tipo):
    base = CNPJ.sub('', limpa(desc))
    nome = base.upper()
    if cat in ('Cota condominial', 'Juros/Multa recebido'):
        un = next((u for k, u in UNIDADES.items() if k in nome), None)
        rot = 'Cota condominial' if cat == 'Cota condominial' else 'Juros/multa recebido'
        return (rot + ' — Apto ' + un) if un else rot, None, None
    if re.match(r'(PAULO|BRUNO|LILIAN)\b', nome) and obs:          # reembolsos a moradores: usa a observação do síndico
        return limpa(obs)[:120], None, None
    fornecedor = None
    if re.search(r'LTDA|S A\b|S/A|SEGUROS|CONSTRUTORA|ASSESSORIA|COPASA|GAS\b', nome) or CNPJ.search(limpa(desc)):
        fornecedor = base[:120]
    return base[:120], fornecedor, (limpa(obs)[:300] if obs else None)

def main(xlsx, saida):
    wb = openpyxl.load_workbook(xlsx, data_only=True)
    linhas, esperado, mapa = [], {}, {}
    for aba in ABAS:
        ws = wb[aba]; cred = deb = 0; ini = None
        for row in ws.iter_rows(values_only=True):
            c = list(row) + [None] * 12
            if isinstance(c[1], str) and 'SALDO INICIAL' in c[1].upper():
                ini = next((num(x) for x in c[2:] if num(x) is not None), None)
            d_ = data(c[1])
            if d_ and (c[5] or c[6]):
                entrada = bool(c[6]); v = centavos(c[6] if entrada else c[5])
                tipo, cat_app = classifica(limpa(c[2]), c[3], c[8], entrada)
                if (tipo == 'receita') != entrada: raise ValueError('tipo incoerente: %r' % (row,))
                desc, forn, obs = descreve(c[2], c[3], c[8], tipo)
                linhas.append((d_, tipo, v, cat_app, desc, forn, obs))
                mapa.setdefault((c[3], cat_app), [0, 0]); mapa[(c[3], cat_app)][0] += 1; mapa[(c[3], cat_app)][1] += v
                cred += v if entrada else 0; deb += 0 if entrada else v
        esperado[aba] = (cred, deb)
        if aba == ABAS[0]: abertura = int((ini * 100).to_integral_value())
    final_esp = abertura + sum(c - d for c, d in esperado.values())
    vals = ',\n'.join('    (%s::date, %s, %d, %s, %s, %s, %s)' % ("'%s'" % d_.isoformat(), sql(t), v, sql(cat), sql(desc), sql(forn), sql(obs))
                      for d_, t, v, cat, desc, forn, obs in linhas)
    meses = ',\n'.join("    ('%s-%02d-01'::date, %d, %d)" % (2026, 7 + i, esperado[a][0], esperado[a][1]) for i, a in enumerate(ABAS))
    out = f"""-- Importação ÚNICA dos lançamentos de jul–set/2026 (conta corrente), a partir da planilha de Conciliação Bancária.
-- Gerado por tools/gerar_importacao_conciliacao.py. CONTÉM DADOS REAIS: não publicar nem versionar em repositório público.
-- Rodar no SQL Editor do Supabase (como administrador do projeto), depois das migrações 001 a 007.
-- Tudo acontece em uma única transação: se qualquer conferência falhar, nada é gravado.
do $imp$
declare
  v_cond uuid; v_user uuid; v_n int; v_abertura constant bigint := {abertura};
  v_ini date; v_e bigint; v_s bigint; v_exp record;
begin
  select id into v_cond from public.condominios where nome = 'Edifício Valença';
  if v_cond is null then raise exception 'Condomínio "Edifício Valença" não encontrado'; end if;
  select user_id into v_user from public.perfis where condominio_id = v_cond and papel = 'sindico' and ativo order by created_at limit 1;
  if v_user is null then raise exception 'Perfil de síndico ativo não encontrado'; end if;
  if exists (select 1 from public.auditoria where condominio_id = v_cond and acao = 'importar_conciliacao_2026_07_09') then
    raise exception 'Esta importação já foi executada; não rode de novo';
  end if;
  if exists (select 1 from public.lancamentos where condominio_id = v_cond and data_lancamento < '2026-10-01') then
    raise exception 'Já existem lançamentos antes de 01/10/2026; confira antes de importar';
  end if;

  update public.condominios set saldo_inicial_centavos = v_abertura, saldo_inicial_data = date '2026-07-01' where id = v_cond;

  insert into public.lancamentos (condominio_id, tipo, data_lancamento, competencia, valor_centavos, categoria, descricao, fornecedor, observacao, criado_por)
  select v_cond, l.tipo::public.tipo_lancamento, l.data_l, date_trunc('month', l.data_l)::date, l.valor, l.categoria, l.descricao, l.fornecedor, l.observacao, v_user
    from (values
{vals}
    ) as l(data_l, tipo, valor, categoria, descricao, fornecedor, observacao);
  get diagnostics v_n = row_count;
  if v_n <> {len(linhas)} then raise exception 'Esperava {len(linhas)} lançamentos, gravou %', v_n; end if;

  -- conferência mês a mês contra os totais da planilha
  for v_exp in select * from (values
{meses}
  ) as t(mes, entradas, saidas) loop
    select e, s into v_e, v_s from (
      select coalesce(sum(valor_centavos) filter (where tipo = 'receita'), 0)::bigint as e,
             coalesce(sum(valor_centavos) filter (where tipo = 'despesa'), 0)::bigint as s
        from public.lancamentos where condominio_id = v_cond and data_lancamento >= v_exp.mes and data_lancamento < (v_exp.mes + interval '1 month')::date) x;
    if v_e <> v_exp.entradas or v_s <> v_exp.saidas then
      raise exception 'Conferência falhou em %: entradas % (esperado %), saídas % (esperado %)', v_exp.mes, v_e, v_exp.entradas, v_s, v_exp.saidas;
    end if;
  end loop;
  select v_abertura + coalesce(sum(case when tipo = 'receita' then valor_centavos else -valor_centavos end), 0) into v_e
    from public.lancamentos where condominio_id = v_cond;
  if v_e <> {final_esp} then raise exception 'Saldo final em 30/09/2026 = % (esperado {final_esp})', v_e; end if;

  insert into public.auditoria (condominio_id, user_id, acao, entidade, detalhes)
  values (v_cond, v_user, 'importar_conciliacao_2026_07_09', 'lancamentos', jsonb_build_object('lancamentos', v_n, 'saldo_abertura_centavos', v_abertura, 'saldo_final_set_centavos', v_e));
end $imp$;

-- Conferência visual (deve mostrar 3 meses e o saldo final de 30/09/2026 = R$ {final_esp/100:,.2f}):
select to_char(date_trunc('month', data_lancamento), 'MM/YYYY') as mes, count(*) as lancamentos,
       round(coalesce(sum(valor_centavos) filter (where tipo = 'receita'), 0) / 100.0, 2) as entradas,
       round(coalesce(sum(valor_centavos) filter (where tipo = 'despesa'), 0) / 100.0, 2) as saidas
  from public.lancamentos group by 1 order by 1;
"""
    open(saida, 'w', encoding='utf-8').write(out)
    print('lançamentos:', len(linhas), '| abertura:', abertura, '| final esperado 30/09:', final_esp)
    for a in ABAS: print(' ', a, 'entradas', esperado[a][0], 'saídas', esperado[a][1])
    print('\nMAPEAMENTO (categoria da planilha → categoria do app: qtde, total R$)')
    for (orig, dest), (n, tot) in sorted(mapa.items(), key=lambda kv: (str(kv[0][0]), kv[0][1])):
        print('  %-22s → %-26s %3d  %10.2f' % (orig, dest, n, tot / 100))
    return linhas

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
