#!/usr/bin/env python3
"""Importa as planilhas financeiras do Edifício Valença para o protótipo.

Uso:
  python tools/importar_planilhas.py Previsao_Orcamentaria.xlsx Conciliacao_Bancaria.xlsx [--manter-nomes]

Gera data/financeiro.json e data/financeiro.js (lidos por index.html). Por padrão, nomes de pessoas físicas
são substituídos pela unidade (ex.: "Cota condominial — Apto 302") ou mascarados.
Não publique o arquivo gerado em hospedagem aberta: ele contém valores reais.
Os valores vêm do cache das fórmulas; abra e salve as planilhas no Excel antes de importar.
"""
import json, re, sys, unicodedata, datetime as dt
from pathlib import Path
import openpyxl

MESES = ["Jul-2026","Ago-2026","Set-2026","Out-2026","Nov-2026","Dez-2026",
         "Jan-2027","Fev-2027","Mar-2027","Abr-2027","Mai-2027","Jun-2027"]
NUM = {"Jan":1,"Fev":2,"Mar":3,"Abr":4,"Mai":5,"Jun":6,"Jul":7,"Ago":8,"Set":9,"Out":10,"Nov":11,"Dez":12}
UNIDADES = ["01","02","101","102","201","202","301","302"]
PRIMEIRO_NOME = {"sebastiao":"01","lara":"02","ireny":"101","irany":"101","thiago":"102",
                 "janaina":"201","erica":"202","artur":"301","celso":"302"}

def norm(s):
    s = unicodedata.normalize("NFD", str(s or "")).encode("ascii", "ignore").decode()
    return re.sub(r"\s+", " ", s).strip().lower()

def iso(v):
    return v.date().isoformat() if isinstance(v, dt.datetime) else (v if isinstance(v, str) else None)

def mes_id(rotulo):
    m, a = rotulo.split("-"); return f"{a}-{NUM[m]:02d}"

def num(v):
    return round(float(v), 2) if isinstance(v, (int, float)) else 0.0

def unidade_de(txt):
    m = re.search(r"apto\s*(\d+)", norm(txt)); return m.group(1) if m else None

def achar(ws, texto, inicio=1, col=2):
    t = norm(texto)
    for r in range(inicio, ws.max_row + 1):
        if t in norm(ws.cell(r, col).value): return r
    return None

def cabecalhos(ws, r):
    return {norm(ws.cell(r, c).value): c for c in range(1, ws.max_column + 1) if ws.cell(r, c).value}

# ---------------------------------------------------------------- previsão
def ler_previsao(ws, wv):
    v = lambda r, c: wv.cell(r, c).value
    out = {}
    r0 = achar(ws, "DESPESAS GERAIS"); rt = achar(ws, "TOTAL DESPESAS GERAIS")
    out["despesas"] = [{"descricao": str(v(r, 2)).strip(), "competencia": iso(v(r, 3)) if isinstance(v(r,3), dt.datetime) else v(r, 3),
                        "vencimento": iso(v(r, 4)), "valor": num(v(r, 5))}
                       for r in range(r0 + 2, rt) if v(r, 2) and isinstance(v(r, 5), (int, float))]
    out["total_despesas"] = num(v(rt, 5))
    out["taxa_por_unidade"] = num(v(rt + 1, 5))
    out["fundo_obras_por_unidade"] = num(v(achar(ws, "Fundo de Obras"), 5))
    ra = achar(ws, "Valor total fatura COPASA")
    rh = achar(ws, "Apartamento", ra)
    agua = {"fatura": num(v(ra, 4)), "competencia": iso(v(ra, 6)) or v(ra, 6), "vencimento": iso(v(ra, 8)), "itens": []}
    r = rh + 1
    while norm(v(r, 2)).startswith("apto"):
        agua["itens"].append({"unidade": unidade_de(v(r, 2)), "fracao_ideal": float(v(r, 4)), "valor": num(v(r, 8))}); r += 1
    out["agua"] = agua
    rg = achar(ws, "Preço por m", ra)
    gas = {"preco_m3": round(float(v(rg, 4)), 4), "itens": []}
    r = rg + 2
    while norm(v(r, 2)).startswith("apto"):
        gas["itens"].append({"unidade": unidade_de(v(r, 2)), "leitura_anterior": v(r, 3), "leitura_atual": v(r, 4),
                             "consumo_m3": round(float(v(r, 5) or 0), 3), "valor": num(v(r, 8))}); r += 1
    gas["total"] = round(sum(i["valor"] for i in gas["itens"]), 2)
    out["gas"] = gas
    rp = achar(ws, "Fornecedor", rg); rpt = achar(ws, "TOTAL", rp + 1)
    par = {"fornecedores": [{"fornecedor": str(v(r, 2)).strip(), "categoria": v(r, 3), "valor_total": num(v(r, 4)),
                             "parcelas": v(r, 5), "valor_parcela": num(v(r, 6))}
                            for r in range(rp + 1, rpt) if v(r, 2)], "por_unidade": []}
    r = achar(ws, "Apartamento / Morador", rpt) + 1
    while norm(v(r, 2)).startswith("apto"):
        par["por_unidade"].append({"unidade": unidade_de(v(r, 2)), "valor": num(v(r, 8)), "observacao": v(r, 4)}); r += 1
    out["parceladas"] = par
    rc = achar(ws, "PREVISÃO DE COBRANÇA POR UNIDADE"); hd = cabecalhos(ws, rc + 1)
    col = lambda nome: next(c for k, c in hd.items() if k.startswith(nome))
    cob = []; r = rc + 2
    while norm(v(r, 2)).startswith("apto"):
        item = {"unidade": unidade_de(v(r, 2)), "taxa": num(v(r, col("taxa"))), "fundo_obras": num(v(r, col("fundo"))),
                "agua": num(v(r, col("agua"))), "gas": num(v(r, col("gas"))), "parceladas": num(v(r, col("parcel"))),
                "compensacao": num(v(r, col("compens"))) if any(k.startswith("compens") for k in hd) else 0.0,
                "total": num(v(r, col("total")))}
        cob.append(item); r += 1
    out["cobranca_planilha"] = cob
    # Recalcula usando a fração da tabela de água (única fonte coerente com o cadastro).
    agua_u = {i["unidade"]: i["valor"] for i in agua["itens"]}
    gas_u = {i["unidade"]: i["valor"] for i in gas["itens"]}
    par_u = {i["unidade"]: i["parceladas"] for i in cob}  # respeita parcelas já pagas por fora (ex.: PIX)
    comp_u = {i["unidade"]: i["compensacao"] for i in cob}
    cobr = []
    for u in UNIDADES:
        it = {"unidade": u, "taxa": out["taxa_por_unidade"], "fundo_obras": out["fundo_obras_por_unidade"],
              "agua": agua_u.get(u, 0.0), "gas": gas_u.get(u, 0.0), "parceladas": par_u.get(u, 0.0), "compensacao": comp_u.get(u, 0.0)}
        it["total"] = round(sum(it[k] for k in ("taxa","fundo_obras","agua","gas","parceladas","compensacao")), 2)
        cobr.append(it)
    out["cobranca"] = cobr
    out["total_previsto"] = round(sum(i["total"] for i in cobr), 2)
    return out

# ------------------------------------------------------------- conciliação
def ler_conciliacao(ws, wv, mascarar):
    v = lambda r, c: wv.cell(r, c).value
    rh = achar(ws, "Data"); rt = achar(ws, "TOTAIS DO MÊS")
    saldo_ini = num(v(achar(ws, "SALDO INICIAL"), 6))
    movs = []
    for r in range(rh + 1, rt):
        d = v(r, 2)
        if not isinstance(d, dt.datetime): continue
        desc, cat = str(v(r, 3) or "").strip(), str(v(r, 4) or "").strip()
        un = None
        if mascarar and cat in ("Cota condominial", "Juros/Multa recebido"):
            un = PRIMEIRO_NOME.get(norm(desc).split(" ")[0])
            if un: desc = f"{cat} — Apto {un}" if cat == "Cota condominial" else f"Juros/multa — Apto {un}"
        elif mascarar and not re.search(r"ltda|s a\b|copasa|tarifa|cobranca|darf|transfer|juros", norm(desc)):
            desc = "Reembolso a pessoa física" if "reembolso" in norm(v(r, 9)) else "Pessoa física (nome omitido)"
        movs.append({"data": d.date().isoformat(), "descricao": desc, "categoria": cat, "tipo": str(v(r, 5)).strip(),
                     "debito": num(v(r, 6)), "credito": num(v(r, 7)), "unidade": un, "observacao": (v(r, 9) or "").strip() if mascarar is False or True else ""})
    deb, cred = round(sum(m["debito"] for m in movs), 2), round(sum(m["credito"] for m in movs), 2)
    calc = round(saldo_ini + cred - deb, 2)
    rx = achar(ws, "Saldo final s/ extrato")
    extrato = v(rx, 6) if rx else None
    extrato = round(float(extrato), 2) if isinstance(extrato, (int, float)) and extrato else None
    status = "sem_dados" if not movs else ("conciliado" if extrato is not None and abs(calc - extrato) < 0.01 else "pendente")
    return {"saldo_inicial": saldo_ini, "movimentos": movs, "total_debitos": deb, "total_creditos": cred,
            "saldo_calculado": calc, "saldo_extrato": extrato, "status": status}

def ler_aplicacao(wv):
    ws = wv["Aplicação"]; out = []
    for i, c in enumerate(range(3, 15)):
        g = lambda r: ws.cell(r, c).value
        out.append({"mes": mes_id(MESES[i]), "saldo_inicial": num(g(5)), "rendimentos": num(g(6)), "depositos": num(g(7)),
                    "resgates": num(g(8)), "saldo_calculado": num(g(9)),
                    "saldo_extrato": num(g(10)) if g(10) else None})
    return out

def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 2: sys.exit(__doc__)
    mascarar = "--manter-nomes" not in sys.argv
    pv, pf = (openpyxl.load_workbook(args[0], data_only=True), openpyxl.load_workbook(args[0]))
    cv = openpyxl.load_workbook(args[1], data_only=True)
    alertas, meses = [], []
    for rot in MESES:
        m = {"id": mes_id(rot), "rotulo": rot, "previsao": ler_previsao(pf[rot], pv[rot]),
             "conciliacao": ler_conciliacao(cv[rot], cv[rot], mascarar)}
        meses.append(m)
    apl = ler_aplicacao(cv)
    # fração vigente = a da aba mais recente que tem os dados (Out-2026)
    atual = {i["unidade"]: i["fracao_ideal"] for i in meses[3]["previsao"]["agua"]["itens"]}
    anterior = {i["unidade"]: i["fracao_ideal"] for i in meses[0]["previsao"]["agua"]["itens"]}
    if abs(sum(atual.values()) - 1) > 1e-7: alertas.append("A soma das frações atualizadas não é 1,0000000.")
    # --- verificações cruzadas
    meses_fr = [m["rotulo"] for m in meses if {i["unidade"]: i["fracao_ideal"] for i in m["previsao"]["agua"]["itens"]} != atual]
    if meses_fr:
        alertas.append("Rateio da água com frações diferentes das atualizadas em: " + ", ".join(meses_fr) + ".")
    for m in meses:
        dif = [(c["unidade"], p["total"], c["total"]) for c, p in zip(m["previsao"]["cobranca"], m["previsao"]["cobranca_planilha"]) if abs(c["total"] - p["total"]) > 0.02]
        if dif:
            alertas.append(f"{m['rotulo']}: tabela de cobrança da planilha usa fração antiga em {len(dif)} unidade(s); maior diferença R$ {max(abs(a-b) for _, a, b in dif):.2f}.")
    dash = pv["Dashboard"]; soma_dash = round(sum(num(dash.cell(r, 8).value) for r in range(6, 18)), 2)
    soma_real = round(sum(m["previsao"]["total_previsto"] - sum(i["compensacao"] for i in m["previsao"]["cobranca"]) for m in meses), 2)
    if abs(soma_dash - soma_real) > 0.01:
        alertas.append(f"Dashboard da previsão soma R$ {soma_dash:,.2f}; somando as abas mensais o total é R$ {soma_real:,.2f}.")
    for m, a in zip(meses, apl):
        dep = round(sum(x["debito"] for x in m["conciliacao"]["movimentos"] if "aplica" in norm(x["descricao"])), 2)
        if m["conciliacao"]["movimentos"] and abs(dep - a["depositos"]) > 0.01:
            alertas.append(f"{m['rotulo']}: transferências para aplicação no extrato (R$ {dep:.2f}) ≠ depósitos na aba Aplicação (R$ {a['depositos']:.2f}).")
    saida = {"gerado_em": dt.datetime.now().isoformat(timespec="seconds"), "nomes_mascarados": mascarar,
             "unidades": [{"id": u, "fracao_ideal": atual[u], "fracao_anterior": anterior[u]} for u in UNIDADES],
             "meses": meses, "aplicacao": apl, "alertas": alertas}
    for m in meses: m["previsao"].pop("cobranca_planilha")
    p = Path(__file__).resolve().parent.parent / "data"; p.mkdir(exist_ok=True)
    (p / "financeiro.json").write_text(json.dumps(saida, ensure_ascii=False, indent=1), encoding="utf-8")
    # Cópia em .js: o navegador bloqueia fetch() de arquivos locais (file://), mas aceita <script src>.
    (p / "financeiro.js").write_text("window.FINANCEIRO_DATA = " + json.dumps(saida, ensure_ascii=False) + ";\n", encoding="utf-8")
    print(f"OK: {len(meses)} meses → {p/'financeiro.json'} e {p/'financeiro.js'}")
    for a in alertas: print("ALERTA:", a)

if __name__ == "__main__":
    main()
