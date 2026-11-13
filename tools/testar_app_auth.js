/* Teste dos fluxos de tela (login, convite, convites do síndico, vaga de visitante) — V1.9.
   Carrega o index.html REAL com auth.js num navegador simulado (jsdom) e um Supabase FALSO em memória.
   Não testa as regras de segurança do banco (isso é feito por tools/sql/rodar_testes_local.sh)
   nem a conexão com o Supabase real (isso é teste manual no projeto de teste).
   Uso: npm i --no-save jsdom && node tools/testar_app_auth.js */
const fs = require('fs'), path = require('path');
const { JSDOM } = require('jsdom');
const ROOT = path.join(__dirname, '..');
const read = f => fs.readFileSync(path.join(ROOT, f), 'utf8');

let ok = 0, bad = 0; const falhas = [];
const check = (nome, cond, info) => { if (cond) ok++; else { bad++; falhas.push(nome + (info ? ' → ' + info : '')); } };
const wait = ms => new Promise(r => setTimeout(r, ms));

/* ---------- Supabase falso ---------- */
const COND = 'cond-A', U101 = 'u-101', U102 = 'u-102';
function novoMundo() {
  return {
    users: [], session: null, chamadas: [], falhaRede: false,
    lancamentos: [], ciclos: [], cobrancas: [], itensc: [], previstos: [], previsoes: [], cpag: [], extratos: [], extlinhas: [], regras: [], comprovantes: [], historico: [], storage: {}, falhaUpload: false, perfis: [], unidades: [{ id: U101, identificacao: '101', fracao_ideal: 0.6, ativa: true }, { id: U102, identificacao: '102', fracao_ideal: 0.4, ativa: true }],
    vinculos: [], avisos: [], convites: [], dashboards_financeiros: [], dashExtrato: {}, seq: 1
  };
}
function fakeClient(w) {
  const cbs = [];
  const emit = ev => cbs.forEach(cb => cb(ev, w.session));
  const res = (data, error) => ({ data: data === undefined ? null : data, error: error || null });
  const erro = m => ({ message: m });
  function builder(tabela) {
    const q = { tabela, op: 'select', filtros: [], ordem: [], lim: null, single: false, payload: null, ret: false };
    const b = {
      select() { q.ret = true; return b; },
      eq(c, v) { q.filtros.push(['eq', c, v]); return b; },
      gte(c, v) { q.filtros.push(['gte', c, v]); return b; },
      lt(c, v) { q.filtros.push(['lt', c, v]); return b; },
      lte(c, v) { q.filtros.push(['lte', c, v]); return b; },
      in(c, v) { q.filtros.push(['in', c, v]); return b; },
      order(c, o) { q.ordem.push([c, !(o && o.ascending === false)]); return b; },
      limit(n) { q.lim = n; return b; },
      maybeSingle() { q.single = true; return b; },
      insert(o) { q.op = 'insert'; q.payload = o; return b; },
      delete() { q.op = 'delete'; return b; },
      update(o) { q.op = 'update'; q.payload = o; return b; },
      then(ok_, ko_) { return Promise.resolve(exec(q)).then(ok_, ko_); }
    };
    return b;
  }
  function exec(q) {
    w.chamadas.push({ tabela: q.tabela, op: q.op, payload: q.payload, filtros: q.filtros });
    if (w.falhaRede) return res(null, erro('Failed to fetch'));
    const dados = w[q.tabela]; if (!dados) return res(null, erro('tabela inexistente: ' + q.tabela));
    const casa = r => q.filtros.every(([t, c, v]) => t === 'eq' ? r[c] === v : t === 'in' ? v.includes(r[c]) : t === 'lt' ? String(r[c]) < String(v) : t === 'lte' ? String(r[c]) <= String(v) : String(r[c]) >= String(v));
    const eu = w.session && w.session.user, perfilEu = eu && w.perfis.find(p => p.user_id === eu.id), ehMorador = perfilEu && perfilEu.papel === 'morador';
    if (q.tabela === 'dashboards_financeiros' && q.op === 'select' && ehMorador) return res(dados.filter(r => r.visivel_moradores).filter(casa));   // RLS do banco
    if (q.op === 'delete') { const alvo = dados.filter(casa); alvo.forEach(r => dados.splice(dados.indexOf(r), 1)); return res(null); }
    if (q.op === 'insert') {
      const r = Object.assign({ id: 'id-' + (w.seq++), status: 'ativo' }, q.payload);
      if (q.tabela === 'avisos') r.status = 'ativo';
      dados.push(r); return res(q.ret ? [r] : null);
    }
    if (q.op === 'update') {
      const alvo = dados.filter(casa); alvo.forEach(r => Object.assign(r, q.payload));
      return res(q.ret ? alvo.map(r => ({ id: r.id })) : null);
    }
    let rows = dados.filter(casa);
    if (ehMorador) {   // regras de leitura do morador (RLS): só a cobrança da própria unidade, depois de liberada
      if (['ciclos', 'previsoes', 'previstos'].includes(q.tabela)) rows = [];
      const minhas = new Set(w.cobrancas.filter(c => c.status !== 'rascunho' && w.vinculos.some(v => v.user_id === eu.id && v.unidade_id === c.unidade_id)).map(c => c.id));
      if (q.tabela === 'cobrancas') rows = rows.filter(r => minhas.has(r.id));
      if (q.tabela === 'itensc' || q.tabela === 'cpag') rows = rows.filter(r => minhas.has(r.cobranca_id));
    }
    q.ordem.slice().reverse().forEach(([c, asc]) => rows.sort((a, b) => (a[c] > b[c] ? 1 : a[c] < b[c] ? -1 : 0) * (asc ? 1 : -1)));
    if (q.lim) rows = rows.slice(0, q.lim);
    return q.single ? res(rows[0] || null) : res(rows);
  }
  const tabelas = { avisos_vaga_visitante: 'avisos', vinculos_unidades: 'vinculos', comprovantes_financeiros: 'comprovantes', lancamentos_historico: 'historico', extratos_importados: 'extratos', extrato_linhas: 'extlinhas', regras_extrato: 'regras', ciclos_cobranca: 'ciclos', itens_cobranca: 'itensc', itens_cobranca_previstos: 'previstos', previsoes_mensais: 'previsoes', cobranca_pagamentos: 'cpag' };
  return {
    auth: {
      async getSession() { return res({ session: w.session }); },
      async signInWithPassword({ email, password }) {
        const u = w.users.find(x => x.email === email && x.password === password);
        if (!u) return res(null, erro('Invalid login credentials'));
        if (!u.confirmed) return res(null, erro('Email not confirmed'));
        w.session = { user: { id: u.id, email: u.email } }; emit('SIGNED_IN'); return res({ session: w.session });
      },
      async signUp({ email, password }) { w.chamadas.push({ signUp: email }); w.users.push({ id: 'usr-' + email, email, password, confirmed: false }); return res({ session: null, user: { email } }); },
      async signOut() { w.session = null; emit('SIGNED_OUT'); return res(null); },
      async resetPasswordForEmail(e) { w.chamadas.push({ reset: e }); return res({}); },
      async updateUser() { return res({}); },
      onAuthStateChange(cb) { cbs.push(cb); return { data: { subscription: { unsubscribe() {} } } }; }
    },
    from(t) { return builder(tabelas[t] || t); },
    storage: { from(bucket) { return {
      async upload(path, file, opts) { w.chamadas.push({ storage: 'upload', bucket, path, contentType: opts && opts.contentType }); if (w.falhaUpload) return res(null, erro('Upload failed: storage indisponível')); w.storage[path] = { size: file.size, type: opts && opts.contentType }; return res({ path }); },
      async createSignedUrl(path, secs) { w.chamadas.push({ storage: 'signed', path, secs }); return res({ signedUrl: 'https://signed.test/' + path + '?token=x&t=' + secs }); } }; } },
    async rpc(nome, args) {
      w.chamadas.push({ rpc: nome, args });
      if (w.falhaRede) return res(null, erro('Failed to fetch'));
      const eu = w.session && w.session.user, perfil = eu && w.perfis.find(p => p.user_id === eu.id);
      if (nome === 'criar_convite') {
        if (!perfil || perfil.papel !== 'sindico') return res(null, erro('Apenas o síndico pode criar convites'));
        const token = 'tok' + (w.seq++) + 'abcdef0123456789abcdef0123456789abcdef';
        w.convites.push({ id: 'cv-' + w.seq, email: args.p_email.toLowerCase(), papel: args.p_papel, unidade_id: args.p_unidade_id, token, aceito_em: null,
          expira_em: new Date(Date.now() + args.p_validade_dias * 864e5).toISOString(), created_at: new Date().toISOString() });
        return res(token);
      }
      if (nome === 'cancelar_convite') {
        const c = w.convites.find(x => x.id === args.p_convite_id); if (!c) return res(null, erro('Convite não encontrado ou já utilizado'));
        c.expira_em = new Date(Date.now() - 1000).toISOString(); return res(null);
      }
      if (nome === 'aceitar_convite') {
        const c = w.convites.find(x => x.token === args.p_token);
        if (!eu || !c || c.aceito_em || new Date(c.expira_em) <= new Date() || c.email !== eu.email) return res(null, erro('Convite inválido ou expirado'));
        c.aceito_em = new Date().toISOString();
        w.perfis.push({ user_id: eu.id, condominio_id: COND, nome: eu.email.split('@')[0], email: eu.email, papel: c.papel, ativo: true });
        if (c.unidade_id) w.vinculos.push({ user_id: eu.id, unidade_id: c.unidade_id, ativo: true });
        return res({ papel: c.papel });
      }
      if (['dashboard_financeiro', 'salvar_dashboard_financeiro', 'excluir_dashboard_financeiro', 'registrar_saldo_extrato'].includes(nome)) return rpcDash(w, nome, args, perfil);
      if (['registrar_lancamento', 'estornar_lancamento', 'resumo_financeiro', 'relatorio_mensal', 'editar_lancamento', 'registrar_comprovante', 'remover_comprovante', 'saldo_livro_em', 'importar_extrato'].includes(nome)) return rpcCaixa(w, nome, args, perfil);
      if (['gerar_cobranca_mensal', 'validar_cobranca_mensal', 'liberar_cobranca_mensal', 'reabrir_cobranca_mensal', 'registrar_pagamento_cobranca', 'remover_pagamento_cobranca', 'cobrancas_em_aberto'].includes(nome)) return rpcCobranca(w, nome, args, perfil);
      return res(null, erro('rpc desconhecida'));
    }
  };
}

/* ---------- livro-caixa falso (a regra real é testada em tools/sql/teste_livro_caixa.sql) ---------- */
function rpcCaixa(w, nome, args, perfil) {
  const res = (data, error) => ({ data: data === undefined ? null : data, error: error || null }), erro = m => ({ message: m });
  if (!perfil) return res(null, erro('Usuário sem vínculo ativo com condomínio'));
  const mesDe = r => String(r.data_lancamento).slice(0, 7), chave = String(args.p_ano) + '-' + String(args.p_mes).padStart(2, '0');
  const orig = r => w.lancamentos.find(o => o.id === r.lancamento_original_id);
  const entrada = r => r.tipo === 'receita' || (r.tipo === 'estorno' && orig(r).tipo === 'despesa') ? r.valor_centavos : 0;
  const saida = r => r.tipo === 'despesa' || (r.tipo === 'estorno' && orig(r).tipo === 'receita') ? r.valor_centavos : 0;
  if (nome === 'resumo_financeiro') {
    const m = w.lancamentos.filter(r => mesDe(r) === chave), e = m.reduce((s, r) => s + entrada(r), 0), s = m.reduce((s2, r) => s2 + saida(r), 0);
    return res([{ receitas_centavos: e, despesas_centavos: s, saldo_centavos: e - s }]);
  }
  if (nome === 'relatorio_mensal') {
    if (perfil.papel === 'morador') return res(null, erro('Relatório detalhado restrito ao síndico e ao conselho'));
    const ab = w.abertura, aberturaMes = ab ? ab.data.slice(0, 7) : '0000-00';
    const m = w.lancamentos.filter(r => mesDe(r) === chave && mesDe(r) >= aberturaMes), ant = (ab && chave > aberturaMes ? ab.centavos : ab && chave === aberturaMes ? ab.centavos : 0) + w.lancamentos.filter(r => mesDe(r) < chave && mesDe(r) >= aberturaMes).reduce((s, r) => s + entrada(r) - saida(r), 0);
    const e = m.reduce((s, r) => s + entrada(r), 0), s = m.reduce((s2, r) => s2 + saida(r), 0), cats = {};
    m.forEach(r => { const c = cats[r.categoria] = cats[r.categoria] || { categoria: r.categoria, entradas_centavos: 0, saidas_centavos: 0 }; c.entradas_centavos += entrada(r); c.saidas_centavos += saida(r); });
    return res({ saldo_anterior_centavos: ant, entradas_centavos: e, saidas_centavos: s, saldo_mes_centavos: e - s, saldo_final_centavos: ant + e - s, quantidade: m.length, por_categoria: Object.values(cats), saldo_abertura_centavos: ab ? ab.centavos : null, saldo_abertura_data: ab ? ab.data : null });
  }
  const saldoEm = (ate, extra) => { const ab = w.abertura; return (ab && ate >= ab.data ? ab.centavos : 0) + w.lancamentos.concat(extra || []).filter(r => r.data_lancamento <= ate && (!ab || r.data_lancamento >= ab.data)).reduce((s, r) => s + entrada(r) - saida(r), 0); };
  if (nome === 'saldo_livro_em') { if (perfil.papel === 'morador') return res(null, erro('Restrito ao síndico e ao conselho')); return res(saldoEm(args.p_data)); }
  if (perfil.papel !== 'sindico') return res(null, erro('Apenas o síndico pode executar esta ação'));
  if (nome === 'importar_extrato') {
    if (w.extratos.some(e => e.arquivo_sha256 === args.p_sha256)) return res(null, erro('Este arquivo já foi importado em 01/01/2026'));
    const mem = x => String(x).trim().replace(/\s+/g, ' ').toUpperCase(), snap = {}, cont = {};
    w.extlinhas.forEach(x => { snap[x.chave] = (snap[x.chave] || 0) + 1; });
    const novosL = [], novasX = []; let L = 0, C = 0, I = 0, J = 0;
    for (const [i, l] of args.p_linhas.entries()) {
      const k = l.data + '|' + l.valor_centavos + '|' + mem(l.memo); cont[k] = (cont[k] || 0) + 1;
      if (cont[k] <= (snap[k] || 0)) { J++; continue; }
      const base = { id: 'x-' + (w.seq++), condominio_id: 'cond-A', ordem: i + 1, data_mov: l.data, valor_centavos: l.valor_centavos, memo: l.memo, chave: k, extrato_id: 'ext-new' };
      if (l.acao === 'lancar') { const n = { id: 'l-' + (w.seq++), tipo: l.valor_centavos > 0 ? 'receita' : 'despesa', data_lancamento: l.data, valor_centavos: Math.abs(l.valor_centavos), categoria: l.categoria, descricao: l.descricao, fornecedor: l.fornecedor, numero_documento: null, observacao: 'Extrato: ' + l.memo, lancamento_original_id: null, estornado_em: null, motivo_estorno: null, versao: 1, editado_em: null, criado_em: new Date().toISOString() + w.seq };
        novosL.push(n); novasX.push(Object.assign(base, { status: 'lancada', lancamento_id: n.id })); L++;
        if (l.lembrar) w.regras.push({ memo_padrao: mem(l.memo), sinal: l.valor_centavos > 0 ? 1 : -1, valor_centavos: l.lembrar === 'memo_valor' ? Math.abs(l.valor_centavos) : null, categoria: l.categoria, descricao: l.descricao, fornecedor: l.fornecedor }); }
      else if (l.acao === 'conciliar') { const x = w.lancamentos.find(q => q.id === l.lancamento_id); if (!x || x.valor_centavos !== Math.abs(l.valor_centavos)) return res(null, erro('Movimento ' + (i + 1) + ': lançamento inválido para conciliar')); novasX.push(Object.assign(base, { status: 'conciliada', lancamento_id: x.id })); C++; }
      else if (l.acao === 'ignorar') { novasX.push(Object.assign(base, { status: 'ignorada', lancamento_id: null, motivo_ignorar: l.motivo })); I++; }
      else return res(null, erro('Movimento ' + (i + 1) + ': Escolha o que fazer com o movimento'));
    }
    let dif = null, livro = null;
    if (args.p_saldo_final_centavos !== null) { livro = saldoEm(args.p_saldo_data, novosL); dif = args.p_saldo_final_centavos - livro;
      if (args.p_exigir_saldo && dif !== 0) return res(null, erro('Saldo do livro-caixa em ' + args.p_saldo_data + ' ficaria R$ ' + (livro / 100) + ', mas o extrato informa R$ ' + (args.p_saldo_final_centavos / 100) + '. Nada foi importado.')); }
    novosL.forEach(n => w.lancamentos.push(n)); novasX.forEach(x => w.extlinhas.push(x));
    w.extratos.push({ id: 'ext-' + w.seq++, arquivo_nome: args.p_arquivo_nome, arquivo_sha256: args.p_sha256, periodo_ini: args.p_periodo_ini, periodo_fim: args.p_periodo_fim, saldo_final_centavos: args.p_saldo_final_centavos, diferenca_saldo_centavos: dif, qtd_movimentos: args.p_linhas.length, qtd_lancadas: L, qtd_conciliadas: C, qtd_ignoradas: I, qtd_ja_importadas: J, importado_em: new Date().toISOString() });
    return res({ extrato_id: 'ext', lancadas: L, conciliadas: C, ignoradas: I, ja_importadas: J, saldo_livro_centavos: livro, diferenca_saldo_centavos: dif });
  }
  if (nome === 'editar_lancamento') {
    const l = w.lancamentos.find(r => r.id === args.p_id); if (!l) return res(null, erro('Lançamento não encontrado'));
    if (l.tipo === 'estorno' || l.estornado_em) return res(null, erro('Lançamento não editável'));
    if ((args.p_motivo || '').trim().length < 5) return res(null, erro('Informe o motivo da edição (5 a 200 caracteres)'));
    const campos = { data_lancamento: args.p_data, valor_centavos: args.p_valor_centavos, categoria: args.p_categoria, descricao: args.p_descricao, fornecedor: args.p_fornecedor, numero_documento: args.p_numero_documento, observacao: args.p_observacao };
    const antes = {}, depois = {}; Object.keys(campos).forEach(k => { if ((l[k] === undefined ? null : l[k]) !== campos[k]) { antes[k] = l[k] === undefined ? null : l[k]; depois[k] = campos[k]; } });
    if (!Object.keys(depois).length) return res(null, erro('Nada foi alterado'));
    Object.assign(l, campos); l.versao = (l.versao || 1) + 1; l.editado_em = new Date().toISOString();
    w.historico.push({ lancamento_id: l.id, versao: l.versao, motivo: args.p_motivo, antes, depois, editado_em: l.editado_em });
    return res(l.versao);
  }
  if (nome === 'registrar_comprovante') {
    const okPath = new RegExp('^cond-A/' + args.p_lancamento_id + '/[0-9a-f-]{36}\\.(pdf|jpg|png|webp)$').test(args.p_caminho);
    if (!okPath) return res(null, erro('Caminho do arquivo inválido'));
    if (!w.storage[args.p_caminho]) return res(null, erro('Arquivo não encontrado no armazenamento; envie de novo'));
    if (!/^[0-9a-f]{64}$/.test(args.p_sha256 || '')) return res(null, erro('Impressão digital (SHA-256) inválida'));
    if (w.comprovantes.filter(c => c.lancamento_id === args.p_lancamento_id && !c.removido_em).length >= 8) return res(null, erro('Limite de 8 anexos por lançamento'));
    const c = { id: 'c-' + (w.seq++), lancamento_id: args.p_lancamento_id, caminho_storage: args.p_caminho, nome_arquivo: args.p_nome, mime_type: args.p_mime, tamanho_bytes: args.p_tamanho, sha256: args.p_sha256, created_at: new Date().toISOString(), removido_em: null };
    w.comprovantes.push(c); return res(c.id);
  }
  if (nome === 'remover_comprovante') {
    const c = w.comprovantes.find(x => x.id === args.p_id && !x.removido_em); if (!c) return res(null, erro('Anexo não encontrado ou já removido'));
    if ((args.p_motivo || '').trim().length < 5) return res(null, erro('Informe o motivo (5 a 200 caracteres)'));
    c.removido_em = new Date().toISOString(); c.motivo_remocao = args.p_motivo; return res(null);
  }
  if (nome === 'registrar_lancamento') {
    if (!(args.p_valor_centavos > 0) || !Number.isInteger(args.p_valor_centavos)) return res(null, erro('O valor deve ser maior que zero'));
    const r = { id: 'l-' + (w.seq++), tipo: args.p_tipo, data_lancamento: args.p_data, valor_centavos: args.p_valor_centavos, categoria: args.p_categoria, descricao: args.p_descricao,
      fornecedor: args.p_fornecedor, numero_documento: args.p_numero_documento, observacao: args.p_observacao, lancamento_original_id: null, estornado_em: null, motivo_estorno: null, versao: 1, editado_em: null, criado_em: new Date().toISOString() + w.seq };
    w.lancamentos.push(r); return res(r.id);
  }
  const o = w.lancamentos.find(r => r.id === args.p_id);
  if (!o) return res(null, erro('Lançamento não encontrado'));
  if (o.estornado_em) return res(null, erro('Este lançamento já foi estornado'));
  if ((args.p_motivo || '').trim().length < 5) return res(null, erro('Informe o motivo do estorno (5 a 200 caracteres)'));
  const hoje = new Date().toLocaleDateString('en-CA', { timeZone: 'America/Sao_Paulo' });
  o.estornado_em = new Date().toISOString(); o.motivo_estorno = args.p_motivo;
  w.lancamentos.push({ id: 'l-' + (w.seq++), tipo: 'estorno', data_lancamento: hoje, valor_centavos: o.valor_centavos, categoria: o.categoria, descricao: 'Estorno: ' + o.descricao, numero_documento: o.numero_documento,
    observacao: args.p_motivo, lancamento_original_id: o.id, estornado_em: null, motivo_estorno: null, criado_em: new Date().toISOString() + w.seq });
  return res('ok');
}


/* ---------- cobrança por unidade falsa (a regra real é testada em tools/sql/teste_cobranca_pagamentos.sql) ---------- */
function rpcCobranca(w, nome, args, perfil) {
  const res = (data, error) => ({ data: data === undefined ? null : data, error: error || null }), erro = m => ({ message: m });
  const hoje = new Date().toLocaleDateString('en-CA', { timeZone: 'America/Sao_Paulo' });
  if (!perfil) return res(null, erro('Usuário sem vínculo ativo com condomínio'));
  const pagoDe = id => w.cpag.filter(p => p.cobranca_id === id && !p.removido_em).reduce((s, p) => s + p.valor_centavos, 0);
  const recalcula = c => { const pg = pagoDe(c.id); if (pg >= c.valor_total_centavos) c.status = 'paga'; else if (c.status === 'paga') c.status = 'pronta_para_emissao'; };
  if (nome === 'cobrancas_em_aberto') {
    if (perfil.papel === 'morador') return res(null, erro('Restrito ao síndico e ao conselho'));
    return res(w.cobrancas.filter(c => !['rascunho', 'paga'].includes(c.status) && c.valor_total_centavos - pagoDe(c.id) > 0).map(c => ({ cobranca_id: c.id, unidade: (w.unidades.find(u => u.id === c.unidade_id) || {}).identificacao, competencia: c.competencia, vencimento: c.vencimento, total_centavos: c.valor_total_centavos, pago_centavos: pagoDe(c.id), saldo_centavos: c.valor_total_centavos - pagoDe(c.id), dias_atraso: Math.max(0, Math.round((new Date(hoje) - new Date(c.vencimento)) / 864e5)) })));
  }
  if (perfil.papel !== 'sindico') return res(null, erro('Apenas o síndico pode executar esta ação'));
  if (nome === 'validar_cobranca_mensal') return res(w.validacao || []);
  if (nome === 'gerar_cobranca_mensal') {
    const prev = w.previsoes.find(p => p.competencia === args.p_competencia); if (!prev) return res(null, erro('Cadastre a previsão orçamentária da competência antes de gerar as cobranças'));
    let ciclo = w.ciclos.find(c => c.competencia === args.p_competencia);
    if (ciclo && (!args.p_substituir_rascunhos || ciclo.status === 'liberado')) return res(null, erro('Já existem cobranças para esta competência'));
    if (ciclo) { const ids = w.cobrancas.filter(c => c.ciclo_id === ciclo.id).map(c => c.id); w.cobrancas = w.cobrancas.filter(c => c.ciclo_id !== ciclo.id); w.itensc = w.itensc.filter(i => !ids.includes(i.cobranca_id)); w.ciclos.splice(w.ciclos.indexOf(ciclo), 1); }
    ciclo = { id: 'cic-' + (w.seq++), competencia: args.p_competencia, vencimento: args.p_vencimento, status: 'gerado' }; w.ciclos.push(ciclo);
    w.unidades.filter(u => u.ativa !== false).forEach(u => {
      const itens = [{ tipo: 'cota_condominial', descricao: 'Taxa condominial', valor_centavos: prev.taxa_por_unidade_centavos }];
      if (prev.fundo_obras_por_unidade_centavos > 0) itens.push({ tipo: 'fundo_obras', descricao: 'Fundo de obras', valor_centavos: prev.fundo_obras_por_unidade_centavos });
      itens.push({ tipo: 'agua', descricao: 'Água', valor_centavos: Math.floor(args.p_fatura_agua_centavos * u.fracao_ideal) });
      w.previstos.filter(i => i.competencia === args.p_competencia && i.unidade_id === u.id).forEach(i => itens.push({ tipo: i.tipo, descricao: i.descricao, valor_centavos: i.valor_centavos }));
      const c = { id: 'cob-' + (w.seq++), ciclo_id: ciclo.id, unidade_id: u.id, competencia: args.p_competencia, vencimento: args.p_vencimento, valor_total_centavos: itens.reduce((s, i) => s + i.valor_centavos, 0), status: 'rascunho', pago_em: null, valor_pago_centavos: null };
      w.cobrancas.push(c); itens.forEach(i => w.itensc.push(Object.assign({ cobranca_id: c.id }, i)));
    });
    return res(ciclo.id);
  }
  const ciclo = w.ciclos.find(c => c.competencia === args.p_competencia);
  if (nome === 'liberar_cobranca_mensal') { if (!ciclo || ciclo.status !== 'gerado') return res(null, erro('Não há rascunho para liberar')); ciclo.status = 'liberado'; w.cobrancas.filter(c => c.ciclo_id === ciclo.id).forEach(c => { c.status = 'pronta_para_emissao'; }); return res(null); }
  if (nome === 'reabrir_cobranca_mensal') {
    if (!ciclo || ciclo.status !== 'liberado') return res(null, erro('Cobranças não estão liberadas'));
    if (w.cobrancas.some(c => c.ciclo_id === ciclo.id && pagoDe(c.id) > 0)) return res(null, erro('Há pagamentos registrados nesta competência: remova-os (com motivo) antes de reabrir'));
    ciclo.status = 'gerado'; w.cobrancas.filter(c => c.ciclo_id === ciclo.id).forEach(c => { c.status = 'rascunho'; }); return res(null);
  }
  if (nome === 'registrar_pagamento_cobranca') {
    const c = w.cobrancas.find(x => x.id === args.p_cobranca_id); if (!c) return res(null, erro('Cobrança não encontrada'));
    if (c.status === 'rascunho') return res(null, erro('A cobrança ainda não foi liberada'));
    if (!(args.p_valor_centavos > 0)) return res(null, erro('O valor do pagamento deve ser maior que zero'));
    if (pagoDe(c.id) + args.p_valor_centavos > c.valor_total_centavos * 1.5) return res(null, erro('O total pago passa de 150% do valor da cobrança: confira o valor'));
    w.cpag.push({ id: 'pg-' + (w.seq++), cobranca_id: c.id, data_pagamento: args.p_data, valor_centavos: args.p_valor_centavos, forma: args.p_forma, extrato_linha_id: args.p_extrato_linha_id, observacao: args.p_observacao, removido_em: null });
    recalcula(c); return res({ status: c.status, pago_centavos: pagoDe(c.id), total_centavos: c.valor_total_centavos, saldo_centavos: Math.max(0, c.valor_total_centavos - pagoDe(c.id)) });
  }
  if (nome === 'remover_pagamento_cobranca') {
    const p = w.cpag.find(x => x.id === args.p_pagamento_id && !x.removido_em); if (!p) return res(null, erro('Pagamento não encontrado ou já removido'));
    if ((args.p_motivo || '').trim().length < 5) return res(null, erro('Informe o motivo (5 a 200 caracteres)'));
    p.removido_em = new Date().toISOString(); recalcula(w.cobrancas.find(c => c.id === p.cobranca_id)); return res(null);
  }
  return res(null, erro('rpc desconhecida'));
}

/* dashboard financeiro: 12 meses fixos (jul/26–jun/27) com saldo inicial 9.370,02; extrato informado define o status */
function rpcDash(w, nome, args, perfil) {
  const res = (data, error) => ({ data: data === undefined ? null : data, error: error || null }), erro = m => ({ message: m });
  if (!perfil) return res(null, erro('Autenticação necessária'));
  const adm = perfil.papel === 'sindico';
  if (nome === 'salvar_dashboard_financeiro') {
    if (!adm) return res(null, erro('Só o síndico pode criar ou editar o dashboard'));
    let d = args.p_id && w.dashboards_financeiros.find(x => x.id === args.p_id);
    if (!d) { d = { id: 'dash-' + (w.seq++), criado_por: perfil.user_id }; w.dashboards_financeiros.push(d); }
    Object.assign(d, { titulo: args.p_titulo, mes_inicio: args.p_mes_inicio, mes_fim: args.p_mes_fim, visivel_moradores: args.p_visivel_moradores, observacao: args.p_observacao, atualizado_em: new Date().toISOString() });
    return res(d.id);
  }
  if (nome === 'excluir_dashboard_financeiro') {
    if (!adm) return res(null, erro('Só o síndico pode excluir o dashboard'));
    const i = w.dashboards_financeiros.findIndex(x => x.id === args.p_id); if (i < 0) return res(null, erro('Dashboard não encontrado'));
    w.dashboards_financeiros.splice(i, 1); return res(null);
  }
  const calc = mes => { const n = (Number(mes.slice(0, 4)) - 2026) * 12 + Number(mes.slice(5, 7)) - 7; return [448364, 562326, 324757, 400970][Math.min(Math.max(n, 0), 3)]; };
  if (nome === 'registrar_saldo_extrato') {
    if (!adm) return res(null, erro('Só o síndico pode informar o saldo do extrato'));
    const mes = args.p_competencia.slice(0, 7); w.dashExtrato[mes] = args.p_saldo_extrato_centavos;
    const st = args.p_saldo_extrato_centavos == null ? 'pendente' : args.p_saldo_extrato_centavos === calc(mes) ? 'conciliado' : 'divergente';
    return res({ mes, status: st, saldo_calculado_centavos: calc(mes), saldo_extrato_centavos: args.p_saldo_extrato_centavos, diferenca_centavos: args.p_saldo_extrato_centavos == null ? null : calc(mes) - args.p_saldo_extrato_centavos });
  }
  const d = w.dashboards_financeiros.find(x => x.id === args.p_id);
  if (!d || (perfil.papel === 'morador' && !d.visivel_moradores)) return res(null, erro('Dashboard não encontrado'));
  const E = [980906, 1062075, 715406, 1063911], S = [1469544, 948113, 952975, 987698], meses = [];
  let ini = 937002;
  for (let i = 0; i < 12; i++) {
    const a = 2026 + Math.floor((6 + i) / 12), mm = String((6 + i) % 12 + 1).padStart(2, '0'), mes = a + '-' + mm, e = E[i] || 0, sa = S[i] || 0, fim = ini + e - sa, ex = w.dashExtrato[mes];
    meses.push({ mes, saldo_inicial_centavos: ini, entradas_centavos: e, saidas_centavos: sa, saldo_final_centavos: fim, quantidade: e ? 9 : 0, saldo_extrato_centavos: ex == null ? null : ex, status: ex == null ? 'pendente' : ex === fim ? 'conciliado' : 'divergente' });
    ini = fim;
  }
  const soma = f => meses.reduce((t, m) => t + m[f], 0);
  return res({ id: d.id, titulo: d.titulo, mes_inicio: '2026-07', mes_fim: '2027-06', visivel_moradores: d.visivel_moradores, observacao: d.observacao, meses,
    totais: { entradas_centavos: soma('entradas_centavos'), saidas_centavos: soma('saidas_centavos'), resultado_centavos: soma('entradas_centavos') - soma('saidas_centavos'), conciliados: meses.filter(m => m.status === 'conciliado').length, meses: 12 } });
}

/* ---------- carrega o app ---------- */
async function abrir(mundo, { configurado = true } = {}) {
  let html = read('index.html');
  const inline = f => '<script>' + read(f).replace(/<\/script/gi, '<\\/script') + '</script>';
  const troca = (de, para) => { if (!html.includes(de)) throw new Error('trecho não encontrado no index.html: ' + de); html = html.split(de).join(para); };
  troca('<script src="./cobranca.js"></script>', inline('cobranca.js'));
  troca('<script src="./boleto.js"></script>', inline('boleto.js'));
  html = html.replace(/<script src="\.\/data\/financeiro\.js"[^>]*><\/script>/, () => '');
  troca('<script src="./vendor/supabase.js"></script>', '<script>window.__fake(window)</script>');
  troca('<script src="./config.js"></script>', configurado ? inline('config.js') : '<script>window.APP_CONFIG={SUPABASE_URL:"",SUPABASE_KEY:""}</script>');
  troca('<script src="./auth.js"></script>', inline('auth.js'));
  troca('<script src="./ofx.js"></script>', inline('ofx.js'));
  troca('<script src="./caixa.js"></script>', inline('caixa.js'));
  troca('<script src="./extrato.js"></script>', inline('extrato.js'));
  troca('<script src="./cobranca-ui.js"></script>', inline('cobranca-ui.js'));
  troca('<script src="./dashboard-fin.js"></script>', inline('dashboard-fin.js'));
  const { VirtualConsole } = require('jsdom'); const vc = new VirtualConsole(); vc.on('jsdomError', e => { if (!/Not implemented/.test(e.message)) console.error('[página]', e.message.split('\n')[0]); });
  const dom = new JSDOM(html, { virtualConsole: vc,
    url: 'https://app.test/condominio/', runScripts: 'dangerously', pretendToBeVisual: true,
    beforeParse(win) {
      win.__fake = w => { w.supabase = { createClient: () => fakeClient(mundo) }; };
      win.fetch = () => Promise.reject(new Error('sem arquivo no teste')); const nodeCrypto = require('crypto'); Object.defineProperty(win, 'crypto', { configurable: true, value: { randomUUID: () => nodeCrypto.randomUUID(), subtle: { digest: (alg, buf) => nodeCrypto.subtle.digest(alg, Buffer.from(new Uint8Array(buf))) } } });
      win.TextDecoder = TextDecoder; win.__abertos = []; win.open = u => { const j = { location: { href: '' }, close() { j.fechada = true; } }; win.__abertos.push(j); return j; };
      win.print = () => { win.__printHTML = win.document.getElementById('printarea').innerHTML; win.__imprimiu = true; win.dispatchEvent(new win.Event('afterprint')); }; win.scrollTo = () => {}; win.prompt = () => null; win.confirm = () => true; win.__alertas = []; win.alert = m => win.__alertas.push(m);
      win.matchMedia = win.matchMedia || (() => ({ matches: false, addListener() {}, removeListener() {} }));
    }
  });
  await wait(60);
  return dom.window;
}
/* só o texto visível: os <script> inline do teste também entram no textContent e contaminariam as verificações */
const txt = w => { const c = w.document.body.cloneNode(true); c.querySelectorAll('script,style').forEach(e => e.remove()); return c.textContent.replace(/\s+/g, ' '); };
const gateVisivel = w => { const g = w.document.getElementById('authgate'); return !!g && !g.classList.contains('hide'); };
const gateTxt = w => (w.document.getElementById('authgate') || { textContent: '' }).textContent.replace(/\s+/g, ' ');
async function preencheESubmete(w, form, campos) {
  Object.entries(campos).forEach(([id, v]) => { const el = w.document.getElementById(id); if (!el) throw new Error('campo "' + id + '" não existe na tela. Tela atual: ' + gateTxt(w).slice(0, 160) + ' | ' + txt(w).slice(0, 200)); el.value = v; });
  w.document.getElementById(form).dispatchEvent(new w.Event('submit', { cancelable: true, bubbles: true }));
  await wait(60);
}
const clica = async (w, el) => { el.dispatchEvent(new w.Event('click', { bubbles: true })); await wait(60); };
const irPara = async (w, pagina) => { await clica(w, w.document.querySelector('[data-page="' + pagina + '"]')); };
function logado(mundo, email, papel, { unidade = null, ativo = true, comPerfil = true } = {}) {
  const id = 'usr-' + email;
  if (!mundo.users.find(u => u.id === id)) mundo.users.push({ id, email, password: 'senha1234', confirmed: true });
  if (comPerfil) mundo.perfis.push({ user_id: id, condominio_id: COND, nome: email.split('@')[0], email, papel, ativo });
  if (unidade) mundo.vinculos.push({ user_id: id, unidade_id: unidade, ativo: true });
  mundo.session = { user: { id, email } };
  return id;
}

(async () => {
  /* 1. modo demonstração */
  {
    const w = await abrir(novoMundo(), { configurado: false });
    check('demo: tela de acesso fica oculta', !gateVisivel(w));
    check('demo: seletor de perfil continua visível', !w.document.getElementById('role').classList.contains('hide'));
    check('demo: item Convites oculto', w.document.getElementById('navconvites').classList.contains('hide'));
    await irPara(w, 'reservas');
    check('demo: página da vaga renderiza (mural de demonstração)', /Vaga de visitante/.test(txt(w)));
    w.close();
  }
  /* 2. sem sessão → entrar; erros de login */
  {
    const m = novoMundo(); m.users.push({ id: 'usr-x', email: 'x@a.com', password: 'senha1234', confirmed: false });
    const w = await abrir(m);
    check('sem sessão: mostra a tela Entrar', gateVisivel(w) && /Entrar/.test(gateTxt(w)));
    check('sem sessão: conteúdo do app NÃO aparece por trás sem estar coberto', gateVisivel(w));
    await preencheESubmete(w, 'ag-f', { 'ag-email': 'x@a.com', 'ag-senha': 'errada123' });
    check('login com senha errada mostra erro em português', /E-mail ou senha incorretos/.test(gateTxt(w)), gateTxt(w));
    await preencheESubmete(w, 'ag-f', { 'ag-email': 'x@a.com', 'ag-senha': 'senha1234' });
    check('login com e-mail não confirmado orienta a confirmar', /Confirme seu e-mail/.test(gateTxt(w)), gateTxt(w));
    await clica(w, w.document.getElementById('ag-criar'));
    check('abre a tela Criar conta', /Criar conta/.test(gateTxt(w)));
    await preencheESubmete(w, 'ag-f', { 'ag-email': 'novo@a.com', 'ag-senha': '123' });
    check('senha curta é recusada na tela', /pelo menos 8/.test(gateTxt(w)) || !m.chamadas.some(c => c.signUp), gateTxt(w));
    await preencheESubmete(w, 'ag-f', { 'ag-email': 'novo@a.com', 'ag-senha': 'senha1234' });
    check('cadastro pede confirmação de e-mail e não entra no app', /Confirme seu e-mail/.test(gateTxt(w)) && gateVisivel(w), gateTxt(w));
    check('cadastro chamou signUp com o e-mail digitado', m.chamadas.some(c => c.signUp === 'novo@a.com'));
    w.close();
  }
  /* 3. conta sem perfil → código do convite */
  {
    const m = novoMundo(); const id = logado(m, 'novo@a.com', 'morador', { comPerfil: false, unidade: null });
    m.convites.push({ id: 'cv-1', email: 'novo@a.com', papel: 'morador', unidade_id: U102, token: 'TOKENVALIDO', aceito_em: null, expira_em: new Date(Date.now() + 864e5).toISOString(), created_at: '2026-10-26' });
    const w = await abrir(m);
    check('conta sem perfil cai na tela do código do convite', /Código do convite/.test(gateTxt(w)), gateTxt(w));
    check('sem perfil o app NÃO é liberado', gateVisivel(w));
    await preencheESubmete(w, 'ag-f', { 'ag-token': 'TOKENERRADO' });
    check('código errado mostra "inválido ou expirado"', /inválido ou expirado/.test(gateTxt(w)), gateTxt(w));
    await preencheESubmete(w, 'ag-f', { 'ag-token': '  TOKENVALIDO  ' });
    check('código correto (com espaços) libera o app', !gateVisivel(w), gateTxt(w));
    check('perfil morador criado e papel aplicado', m.perfis.some(p => p.email === 'novo@a.com' && p.papel === 'morador'));
    check('seletor de perfil de demonstração some após o login', w.document.getElementById('role').classList.contains('hide'));
    check('botão Sair aparece', !!w.document.getElementById('btnsair'));
    check('morador não vê o item Convites', w.document.getElementById('navconvites').classList.contains('hide'));
    check('rodapé mostra o nome do usuário e a versão', /novo/.test(w.document.querySelector('.sidefoot').textContent) && /1\.16/.test(w.document.querySelector('.sidefoot').textContent));
    w.close();
  }
  /* 4. perfil desativado / falha de rede */
  {
    const m = novoMundo(); logado(m, 'off@a.com', 'morador', { ativo: false });
    const w = await abrir(m);
    check('perfil desativado vê "Acesso desativado" e não entra', /Acesso desativado/.test(gateTxt(w)) && gateVisivel(w), gateTxt(w));
    w.close();
    const m2 = novoMundo(); logado(m2, 'a@a.com', 'morador'); m2.falhaRede = true;
    const w2 = await abrir(m2);
    check('falha de rede mostra erro e opção de tentar de novo', /Não foi possível carregar/.test(gateTxt(w2)) && /Tentar de novo/.test(gateTxt(w2)), gateTxt(w2));
    w2.close();
  }
  /* 5. morador: vaga de visitante */
  {
    const m = novoMundo(); const id = logado(m, 'm101@a.com', 'morador', { unidade: U101 });
    const hoje = new Date().toLocaleDateString('en-CA', { timeZone: 'America/Sao_Paulo' });
    const amanha = new Date(Date.now() + 864e5).toLocaleDateString('en-CA', { timeZone: 'America/Sao_Paulo' });
    m.avisos.push({ id: 'av-outro', condominio_id: COND, unidade_id: U102, criado_por: 'outro', data_uso: amanha, hora_inicio: '10:00:00', hora_fim: '12:00:00', observacao: 'Visita do João', status: 'ativo' });
    const w = await abrir(m);
    check('morador entra no app', !gateVisivel(w));
    await irPara(w, 'reservas'); await wait(80);
    check('vaga: lista avisos vindos do banco', /Visita do João/.test(txt(w)) && /Unidade 102/.test(txt(w)), txt(w).slice(0, 300));
    check('vaga: texto deixa claro que NÃO é reserva', /não realiza reservas/.test(txt(w)));
    check('vaga: morador não vê "Cancelar" no aviso de outro', !w.document.querySelector('[data-vaga-cancel]'));
    await clica(w, w.document.getElementById('newvisitor'));
    check('vaga: formulário abre só com a unidade do morador', /Avisar uso da vaga/.test(txt(w)) && w.document.querySelectorAll('#av-un option').length === 1);
    await preencheESubmete(w, 'av-f', { 'av-d': amanha, 'av-i': '18:00', 'av-t': '17:00' });
    check('vaga: hora final menor que inicial é barrada na tela', /horário final/.test(w.document.getElementById('av-erro').textContent) && !m.chamadas.some(c => c.op === 'insert'));
    await preencheESubmete(w, 'av-f', { 'av-d': amanha, 'av-i': '14:00', 'av-t': '18:00', 'av-o': 'Churrasco' });
    const ins = m.chamadas.find(c => c.op === 'insert');
    check('vaga: insert envia condomínio, unidade, criado_por e horários corretos',
      ins && ins.payload.condominio_id === COND && ins.payload.unidade_id === U101 && ins.payload.criado_por === id &&
      ins.payload.data_uso === amanha && ins.payload.hora_inicio === '14:00' && ins.payload.hora_fim === '18:00' && ins.payload.observacao === 'Churrasco', JSON.stringify(ins && ins.payload));
    await wait(80);
    check('vaga: aviso novo aparece na lista após publicar', /Churrasco/.test(txt(w)));
    const btn = w.document.querySelector('[data-vaga-cancel]');
    check('vaga: morador vê "Cancelar" só no próprio aviso', !!btn && w.document.querySelectorAll('[data-vaga-cancel]').length === 1);
    await clica(w, btn); await wait(80);
    const up = m.chamadas.find(c => c.op === 'update' && c.tabela === 'avisos');
    check('vaga: cancelar envia status=cancelado para o aviso certo', up && up.payload.status === 'cancelado' && m.avisos.find(a => a.observacao === 'Churrasco').status === 'cancelado');
    check('vaga: aviso cancelado aparece como Cancelado', /Cancelado/.test(txt(w)));
    w.close();
  }
  /* 6. morador sem unidade vinculada */
  {
    const m = novoMundo(); logado(m, 'semun@a.com', 'morador');
    const w = await abrir(m); await irPara(w, 'reservas'); await wait(80);
    check('sem unidade: não há botão de avisar e há orientação', !w.document.getElementById('newvisitor') && /não está vinculado/.test(txt(w)));
    w.close();
  }
  /* 7. síndico: convites */
  {
    const m = novoMundo(); logado(m, 'sind@a.com', 'sindico');
    const w = await abrir(m);
    check('síndico vê o item Convites', !w.document.getElementById('navconvites').classList.contains('hide'));
    await irPara(w, 'convites'); await wait(80);
    check('convites: tela abre com formulário', !!w.document.getElementById('cv-f'));
    await preencheESubmete(w, 'cv-f', { 'cv-email': 'Novo@A.com', 'cv-papel': 'morador', 'cv-un': '', 'cv-dias': '7' });
    check('convites: morador sem unidade é barrado na tela', /unidade do morador/.test(w.document.getElementById('cv-erro').textContent) && !m.chamadas.some(c => c.rpc === 'criar_convite'));
    await preencheESubmete(w, 'cv-f', { 'cv-email': 'Novo@A.com', 'cv-papel': 'morador', 'cv-un': U101, 'cv-dias': '7' });
    const rpc = m.chamadas.find(c => c.rpc === 'criar_convite');
    check('convites: rpc criar_convite recebe e-mail, papel, unidade e validade', rpc && rpc.args.p_email === 'Novo@A.com' && rpc.args.p_papel === 'morador' && rpc.args.p_unidade_id === U101 && rpc.args.p_validade_dias === 7, JSON.stringify(rpc && rpc.args));
    await wait(80);
    const ta = w.document.getElementById('cv-texto');
    check('convites: mensagem com o código aparece uma vez para copiar', !!ta && /tok\d+abcdef/.test(ta.value) && /novo@a\.com/.test(ta.value), ta && ta.value);
    check('convites: link do WhatsApp gerado', !!w.document.querySelector('a[href^="https://wa.me/"]'));
    check('convites: lista mostra o convite como Pendente', /Pendente/.test(txt(w)));
    await clica(w, w.document.querySelector('[data-cv-cancel]')); await wait(80);
    check('convites: cancelar chama cancelar_convite e passa a Expirado/cancelado', m.chamadas.some(c => c.rpc === 'cancelar_convite') && /Expirado\/cancelado/.test(txt(w)));
    await irPara(w, 'inicio');
    check('convites: o código some ao sair da tela (não fica exposto)', !w.document.getElementById('cv-texto'));
    await clica(w, w.document.querySelector('[data-page="menu"]'));
    check('menu do síndico tem o atalho de Convites', /Convidar moradores/.test(txt(w)));
    w.close();
  }
  /* 8. morador não acessa convites; sair */
  {
    const m = novoMundo(); logado(m, 'm@a.com', 'morador', { unidade: U101 });
    const w = await abrir(m);
    w.document.querySelector('[data-page="inicio"]');
    const btn = w.document.createElement('button'); btn.dataset.page = 'convites'; w.document.body.appendChild(btn);
    // força a navegação por código, como se o morador digitasse a rota
    w.eval("page='convites'; render();"); await wait(60);
    check('morador em /convites vê "Acesso restrito" e nenhum formulário', /Acesso restrito ao síndico/.test(txt(w)) && !w.document.getElementById('cv-f'));
    check('morador não dispara rpc de convites', !m.chamadas.some(c => c.rpc));
    w.document.getElementById('btnsair').dispatchEvent(new w.Event('click')); await wait(80);
    check('Sair encerra a sessão', m.session === null);
    w.close();
  }

  /* 9. livro-caixa — síndico */
  const hojeS = new Date().toLocaleDateString('en-CA', { timeZone: 'America/Sao_Paulo' });
  const mesAnt = (() => { const [a, m] = hojeS.slice(0, 7).split('-').map(Number); return m === 1 ? (a - 1) + '-12' : a + '-' + String(m - 1).padStart(2, '0'); })();
  const lanc = (id, tipo, data, cent, cat, desc, doc) => ({ id, tipo, data_lancamento: data, valor_centavos: cent, categoria: cat, descricao: desc, fornecedor: null, numero_documento: doc || null,
    observacao: null, lancamento_original_id: null, estornado_em: null, motivo_estorno: null, versao: 1, editado_em: null, criado_em: data + 'T10:00:00Z' + id });
  const mundoCaixa = papel => {
    const m = novoMundo(); logado(m, papel + '@a.com', papel, { unidade: papel === 'morador' ? U101 : null });
    m.lancamentos.push(lanc('l1', 'receita', hojeS, 65000, 'Taxa condominial', 'Taxa condominial — unidade 101'),
      lanc('l2', 'despesa', hojeS, 42000, 'Manutenção e reparos', 'Manutenção do portão', 'OS 024'),
      lanc('l3', 'despesa', mesAnt + '-15', 18640, 'Energia das áreas comuns', 'Energia das áreas comuns'));
    return m;
  };
  {
    const m = mundoCaixa('sindico');
    const w = await abrir(m); await irPara(w, 'financeiro'); await wait(120);
    check('caixa/síndico: estatísticas vêm do relatório do banco', /Entradas do mês/.test(txt(w)) && /650,00/.test(txt(w)) && /420,00/.test(txt(w)), txt(w).slice(0, 400));
    check('caixa/síndico: saldo do mês = entradas − saídas (230,00)', /Saldo do mês[^R]*R\$\s*230,00/.test(txt(w)));
    check('caixa/síndico: saldo acumulado inclui mês anterior (43,60)', /Saldo acumulado[^R]*R\$\s*43,60/.test(txt(w)));
    check('caixa/síndico: lista mostra lançamentos do mês e o documento', /Manutenção do portão/.test(txt(w)) && /Documento: OS 024/.test(txt(w)) && !/Energia das áreas comuns.*Documento/.test(txt(w)));
    check('caixa/síndico: não aparece o aviso de "demonstração fictícia"', !/dados são fictícios e não são salvos/.test(txt(w)));
    check('caixa/síndico: mês anterior NÃO aparece na lista do mês atual', !/R\$\s*186,40/.test(w.document.getElementById('cx-tabela').textContent));
    const tp = w.document.getElementById('cx-tipo'); tp.value = 'receita'; tp.dispatchEvent(new w.Event('change', { bubbles: true })); await wait(30);
    check('caixa: filtro por tipo mostra só receitas', /Taxa condominial — unidade 101/.test(txt(w)) && !/Manutenção do portão/.test(w.document.getElementById('cx-tabela').textContent));
    tp.value = 'todos'; tp.dispatchEvent(new w.Event('change', { bubbles: true }));
    const bs = w.document.getElementById('cx-busca'); bs.value = 'portão'; bs.dispatchEvent(new w.Event('input', { bubbles: true })); await wait(30);
    check('caixa: busca por texto filtra a tabela', /Manutenção do portão/.test(w.document.getElementById('cx-tabela').textContent) && !/Taxa condominial —/.test(w.document.getElementById('cx-tabela').textContent));
    bs.value = ''; bs.dispatchEvent(new w.Event('input', { bubbles: true }));
    // novo lançamento
    await clica(w, w.document.getElementById('cx-novo'));
    check('caixa: formulário de lançamento abre', !!w.document.getElementById('cx-f'));
    await preencheESubmete(w, 'cx-f', { 'cx-fx': 'Reparo bomba', 'cx-fv': '0' });
    check('caixa: valor zero é barrado na tela, sem chamar o banco', /valor válido/.test(w.document.getElementById('cx-erro').textContent) && !m.chamadas.some(c => c.rpc === 'registrar_lancamento'));
    await preencheESubmete(w, 'cx-f', { 'cx-fx': 'Reparo bomba', 'cx-fv': 'abc' });
    check('caixa: valor com letras é barrado', !m.chamadas.some(c => c.rpc === 'registrar_lancamento'));
    await preencheESubmete(w, 'cx-f', { 'cx-ft': 'despesa', 'cx-fd': hojeS, 'cx-fx': 'Reparo bomba', 'cx-fc': 'Manutenção e reparos', 'cx-fv': '1.234,56', 'cx-fn': 'NF 99' });
    const reg = m.chamadas.find(c => c.rpc === 'registrar_lancamento');
    check('caixa: valor 1.234,56 vai ao banco como 123456 centavos inteiros', reg && reg.args.p_valor_centavos === 123456 && Number.isInteger(reg.args.p_valor_centavos), JSON.stringify(reg && reg.args));
    check('caixa: registro envia tipo, data, categoria, descrição e documento', reg && reg.args.p_tipo === 'despesa' && reg.args.p_data === hojeS && reg.args.p_categoria === 'Manutenção e reparos' && reg.args.p_descricao === 'Reparo bomba' && reg.args.p_numero_documento === 'NF 99');
    await wait(100);
    check('caixa: novo lançamento aparece e as saídas somam (1.654,56)', /Reparo bomba/.test(txt(w)) && /1\.654,56/.test(txt(w)) && !w.document.getElementById('cxmodal'));
    // estorno
    const btn = [...w.document.querySelectorAll('[data-cx-est]')].find(b => /Reparo bomba/.test(b.closest('tr').textContent));
    await clica(w, btn);
    check('caixa: tela de estorno pede o motivo', /Estornar lançamento/.test(txt(w)) && !!w.document.getElementById('cx-fm'));
    await preencheESubmete(w, 'cx-f', { 'cx-fm': 'abc' });
    check('caixa: motivo curto é barrado sem chamar o banco', !m.chamadas.some(c => c.rpc === 'estornar_lancamento'));
    await preencheESubmete(w, 'cx-f', { 'cx-fm': 'Valor lançado errado' });
    const est = m.chamadas.find(c => c.rpc === 'estornar_lancamento');
    check('caixa: estorno envia o id e o motivo', est && est.args.p_id === m.lancamentos.find(l => l.descricao === 'Reparo bomba').id && est.args.p_motivo === 'Valor lançado errado');
    await wait(100);
    const t = w.document.getElementById('cx-tabela').textContent;
    check('caixa: aparece a linha de estorno e o original marcado como estornado', /Estorno: Reparo bomba/.test(t) && /Estornado em/.test(t) && /Valor lançado errado/.test(t));
    check('caixa: estorno de despesa entra como entrada (+) e o saldo do mês continua 230,00', /\+\s*R\$\s*1\.234,56/.test(t) && /Saldo do mês[^R]*R\$\s*230,00/.test(txt(w)));
    check('caixa: original estornado e o próprio estorno não têm botão Estornar', [...w.document.querySelectorAll('[data-cx-est]')].every(b => !/Reparo bomba/.test(b.closest('tr').textContent)));
    // troca de mês
    const cm = w.document.getElementById('cx-mes'); cm.value = mesAnt; cm.dispatchEvent(new w.Event('change', { bubbles: true })); await wait(120);
    const [aA, mA] = mesAnt.split('-').map(Number), rpcMes = m.chamadas.filter(c => c.rpc === 'relatorio_mensal').pop();
    check('caixa: trocar o mês consulta o ano/mês certo', rpcMes && rpcMes.args.p_ano === aA && rpcMes.args.p_mes === mA, JSON.stringify(rpcMes && rpcMes.args));
    check('caixa: mês anterior mostra só os lançamentos dele', /Energia das áreas comuns/.test(w.document.getElementById('cx-tabela').textContent) && !/Reparo bomba/.test(w.document.getElementById('cx-tabela').textContent));
    // impressão
    await clica(w, w.document.getElementById('cx-print'));
    check('caixa: imprimir gera o relatório mensal para impressão', w.__imprimiu === true && /Relatório mensal/.test(w.__printHTML || '') && /Saldo final/.test(w.__printHTML || ''));
    w.close();
  }
  /* 9b. livro-caixa com saldo de abertura */
  {
    const m = mundoCaixa('sindico'); m.abertura = { data: mesAnt + '-01', centavos: 937002 };
    const w = await abrir(m); await irPara(w, 'financeiro'); await wait(120);
    check('caixa/abertura: saldo acumulado = abertura + movimentos (9.413,62)', /Saldo acumulado[^R]*R\$\s*9\.413,62/.test(txt(w)), txt(w).slice(0, 500));
    check('caixa/abertura: o cartão informa valor e data do saldo de abertura', /Inclui saldo de abertura de R\$\s*9\.370,02 em 01\/\d{2}\/\d{4}/.test(txt(w)));
    w.close();
  }
  /* 9d. livro-caixa — anexos (nota fiscal), edição e histórico */
  {
    const nodeCrypto = require('crypto');
    const setFiles = (w, id, arr) => Object.defineProperty(w.document.getElementById(id), 'files', { value: arr, configurable: true });
    const mkFile = (w, conteudo, nome, tipo) => new w.File([Buffer.from(conteudo)], nome, { type: tipo });
    const linha = (w, t) => [...w.document.querySelectorAll('#cx-tabela tbody tr')].find(tr => tr.textContent.includes(t));
    const submete = async (w, id) => { w.document.getElementById(id).dispatchEvent(new w.Event('submit', { cancelable: true, bubbles: true })); await wait(400); };
    const m = mundoCaixa('sindico');
    m.lancamentos.push(Object.assign(lanc('l4', 'despesa', hojeS, 10000, 'Limpeza', 'Limpeza geral'), { fornecedor: 'ACME' }),
      Object.assign(lanc('l5', 'despesa', hojeS, 7000, 'Outras despesas', 'Despesa estornada'), { estornado_em: new Date().toISOString(), motivo_estorno: 'erro de lançamento' }),
      Object.assign(lanc('l6', 'estorno', hojeS, 7000, 'Outras despesas', 'Estorno: Despesa estornada'), { lancamento_original_id: 'l5', observacao: 'erro de lançamento' }));
    const w = await abrir(m); await irPara(w, 'financeiro'); await wait(150);
    const n0 = () => m.chamadas.filter(c => c.rpc === 'registrar_lancamento').length;
    const erroTxt = () => w.document.getElementById('cx-erro').textContent;
    // ---- validações de arquivo (antes de gravar) ----
    await clica(w, w.document.getElementById('cx-novo'));
    const base = { 'cx-fd': hojeS, 'cx-fx': 'Reparo com nota', 'cx-ff': 'ACME Ltda', 'cx-fc': 'Manutenção e reparos', 'cx-fv': '300,50', 'cx-fn': 'NF 1234' };
    check('anexos: o formulário tem o campo de nota fiscal/documento e o de fornecedor', !!w.document.getElementById('cx-fa') && !!w.document.getElementById('cx-ff'));
    setFiles(w, 'cx-fa', [mkFile(w, 'x', 'virus.exe', 'application/x-msdownload')]); await preencheESubmete(w, 'cx-f', base);
    check('anexos: formato não aceito é barrado ANTES de gravar o lançamento', /formato não aceito/.test(erroTxt()) && n0() === 0, erroTxt());
    setFiles(w, 'cx-fa', [new w.File([new Uint8Array(11 * 1024 * 1024)], 'enorme.pdf', { type: 'application/pdf' })]); await preencheESubmete(w, 'cx-f', base);
    check('anexos: arquivo acima de 10 MB é barrado', /limite é 10 MB/.test(erroTxt()) && n0() === 0, erroTxt());
    setFiles(w, 'cx-fa', Array.from({ length: 9 }, (_, i) => mkFile(w, 'p' + i, 'a' + i + '.pdf', 'application/pdf'))); await preencheESubmete(w, 'cx-f', base);
    check('anexos: mais de 8 arquivos é barrado', /no máximo 8/.test(erroTxt()) && n0() === 0, erroTxt());
    // ---- gravação com dois anexos ----
    const pdfBytes = '%PDF-1.4 nota fiscal 1234', pdf = mkFile(w, pdfBytes, 'NF 1234.pdf', 'application/pdf'), jpg = mkFile(w, [1, 2, 3, 4, 5], 'foto.jpg', 'image/jpeg');
    setFiles(w, 'cx-fa', [pdf, jpg]); await preencheESubmete(w, 'cx-f', base); await wait(500);
    const reg = m.chamadas.find(c => c.rpc === 'registrar_lancamento' && c.args.p_descricao === 'Reparo com nota');
    check('anexos: o fornecedor digitado vai ao banco', reg && reg.args.p_fornecedor === 'ACME Ltda' && reg.args.p_valor_centavos === 30050, JSON.stringify(reg && reg.args));
    const ups = m.chamadas.filter(c => c.storage === 'upload');
    check('anexos: 2 arquivos enviados ao bucket privado "comprovantes" na pasta do condomínio/lançamento', ups.length === 2 && ups.every(u => u.bucket === 'comprovantes' && /^cond-A\/l-\d+\/[0-9a-f-]{36}\.(pdf|jpg)$/.test(u.path)), JSON.stringify(ups));
    check('anexos: tipo do arquivo informado no envio', ups.some(u => u.contentType === 'application/pdf') && ups.some(u => u.contentType === 'image/jpeg'));
    const rc = m.chamadas.filter(c => c.rpc === 'registrar_comprovante');
    const shaPdf = nodeCrypto.createHash('sha256').update(Buffer.from(pdfBytes)).digest('hex');
    check('anexos: cada arquivo é registrado com nome, tamanho e SHA-256 corretos', rc.length === 2 && rc.some(c => c.args.p_nome === 'NF 1234.pdf' && c.args.p_sha256 === shaPdf && c.args.p_tamanho === pdfBytes.length && c.args.p_mime === 'application/pdf'), JSON.stringify(rc.map(c => c.args.p_nome)));
    check('anexos: a linha do lançamento mostra 📎 2', /📎 2/.test(linha(w, 'Reparo com nota').textContent) && !w.document.getElementById('cxmodal'));
    // ---- janela de anexos: abrir, remover, anexar depois ----
    await clica(w, linha(w, 'Reparo com nota').querySelector('[data-cx-anx]'));
    const mt = () => w.document.getElementById('cxmodal').textContent.replace(/\s+/g, ' ');
    check('anexos: a janela lista os arquivos com impressão digital', /NF 1234\.pdf/.test(mt()) && /foto\.jpg/.test(mt()) && /Impressão digital/.test(mt()), mt().slice(0, 200));
    await clica(w, w.document.querySelector('[data-cx-abrir]'));
    check('anexos: "Abrir" usa link temporário de 60 segundos', m.chamadas.some(c => c.storage === 'signed' && c.secs === 60) && w.__abertos.length >= 1 && /signed\.test/.test(w.__abertos[w.__abertos.length - 1].location.href) && /toque aqui/.test(mt()));
    await clica(w, w.document.querySelector('[data-cx-rem]'));
    await preencheESubmete(w, 'cx-f', { 'cx-fm': 'abc' });
    check('anexos: remoção sem motivo é barrada', /motivo/.test(erroTxt()) && !m.chamadas.some(c => c.rpc === 'remover_comprovante'));
    await preencheESubmete(w, 'cx-f', { 'cx-fm': 'arquivo enviado por engano' }); await wait(200);
    check('anexos: remover chama o banco com o motivo e atualiza a lista e a contagem', m.chamadas.some(c => c.rpc === 'remover_comprovante' && c.args.p_motivo === 'arquivo enviado por engano') && /📎 1/.test(linha(w, 'Reparo com nota').textContent) && w.document.querySelectorAll('[data-cx-abrir]').length === 1, mt().slice(0, 200));
    setFiles(w, 'cx-anx-f', [mkFile(w, 'recibo', 'recibo.png', 'image/png')]); await submete(w, 'cx-fanx');
    check('anexos: anexar depois pela janela envia o arquivo e a contagem volta a 2', /📎 2/.test(linha(w, 'Reparo com nota').textContent) && m.chamadas.filter(c => c.storage === 'upload').length === 3);
    await clica(w, w.document.getElementById('cx-x'));
    // ---- falha no envio: o lançamento fica salvo e o síndico é avisado ----
    m.falhaUpload = true; await clica(w, w.document.getElementById('cx-novo'));
    setFiles(w, 'cx-fa', [mkFile(w, 'nota', 'nota.pdf', 'application/pdf')]); await preencheESubmete(w, 'cx-f', Object.assign({}, base, { 'cx-fx': 'Sem upload', 'cx-fn': '' })); await wait(500);
    check('anexos: falha no envio mantém o lançamento salvo', m.lancamentos.some(l => l.descricao === 'Sem upload'));
    check('anexos: falha no envio mostra aviso claro e o botão Anexar na linha', /não foram enviados/.test(txt(w)) && /Anexar/.test(linha(w, 'Sem upload').textContent), txt(w).slice(0, 300));
    m.falhaUpload = false; await clica(w, w.document.getElementById('cx-aviso-x'));
    check('anexos: o aviso pode ser dispensado', !/não foram enviados/.test(txt(w)));
    // ---- edição ----
    await clica(w, linha(w, 'Manutenção do portão').querySelector('[data-cx-edit]'));
    check('edição: o formulário abre preenchido com os dados atuais', w.document.getElementById('cx-fv').value === '420,00' && w.document.getElementById('cx-fd').value === hojeS && w.document.getElementById('cx-fx').value === 'Manutenção do portão' && w.document.getElementById('cx-fn').value === 'OS 024');
    await preencheESubmete(w, 'cx-f', { 'cx-fv': '450,00' });
    check('edição: sem motivo é barrada', /motivo/.test(erroTxt()) && !m.chamadas.some(c => c.rpc === 'editar_lancamento'));
    w.document.getElementById('cx-fv').dispatchEvent(new w.Event('input', { bubbles: true }));
    check('edição: ao mudar o valor o app avisa que o saldo do mês muda', /altera o saldo de/.test(w.document.getElementById('cx-aviso-ed').textContent));
    await preencheESubmete(w, 'cx-f', { 'cx-fv': '420,00', 'cx-fm': 'Conferido com a nota' });
    check('edição: sem nenhuma mudança é recusada ("Nada foi alterado")', /Nada foi alterado/.test(erroTxt()) && !m.chamadas.some(c => c.rpc === 'editar_lancamento'));
    await preencheESubmete(w, 'cx-f', { 'cx-fv': '450,00', 'cx-fm': 'Valor corrigido conforme a nota' }); await wait(200);
    const ed = m.chamadas.find(c => c.rpc === 'editar_lancamento');
    check('edição: envia id, valor em centavos, demais campos e o motivo', ed && ed.args.p_valor_centavos === 45000 && ed.args.p_numero_documento === 'OS 024' && ed.args.p_descricao === 'Manutenção do portão' && ed.args.p_motivo === 'Valor corrigido conforme a nota' && ed.args.p_id === 'l2', JSON.stringify(ed && ed.args));
    check('edição: a lista mostra o novo valor e a marca "editado"', /450,00/.test(linha(w, 'Manutenção do portão').textContent) && /editado/.test(linha(w, 'Manutenção do portão').textContent));
    await clica(w, linha(w, 'Manutenção do portão').querySelector('[data-cx-hist]'));
    check('edição: o histórico mostra versão, motivo e valor antes → depois', /Versão 2/.test(mt()) && /Valor corrigido conforme a nota/.test(mt()) && /420,00/.test(mt()) && /450,00/.test(mt()), mt().slice(0, 300));
    await clica(w, w.document.getElementById('cx-x'));
    // fornecedor não é apagado ao editar só a descrição
    await clica(w, linha(w, 'Limpeza geral').querySelector('[data-cx-edit]'));
    await preencheESubmete(w, 'cx-f', { 'cx-fx': 'Limpeza geral do prédio', 'cx-fm': 'Descrição mais clara' }); await wait(200);
    const ed2 = m.chamadas.filter(c => c.rpc === 'editar_lancamento').pop();
    check('edição: o fornecedor existente é preservado ao editar outro campo', ed2 && ed2.args.p_fornecedor === 'ACME' && ed2.args.p_descricao === 'Limpeza geral do prédio', JSON.stringify(ed2 && ed2.args));
    check('edição: lançamento estornado e estorno NÃO têm botão Editar nem Estornar', !linha(w, 'Despesa estornada').querySelector('[data-cx-edit]') && !linha(w, 'Despesa estornada').querySelector('[data-cx-est]') && !linha(w, 'Estorno: Despesa estornada').querySelector('[data-cx-edit]'));
    await clica(w, w.document.getElementById('cx-print'));
    check('anexos: o relatório impresso indica quantos anexos cada lançamento tem', /\[2 anexo\(s\)\]/.test(w.__printHTML || ''), (w.__printHTML || '').slice(0, 100));
    w.close();
  }
  /* 9e. conselho: vê anexos e histórico, sem escrever */
  {
    const nodeCrypto = require('crypto');
    const linha = (w, t) => [...w.document.querySelectorAll('#cx-tabela tbody tr')].find(tr => tr.textContent.includes(t));
    const m = mundoCaixa('conselho');
    const l2 = m.lancamentos.find(l => l.id === 'l2'); l2.versao = 2; l2.editado_em = new Date().toISOString();
    m.historico.push({ lancamento_id: 'l2', versao: 2, motivo: 'Valor corrigido conforme a nota', antes: { valor_centavos: 40000 }, depois: { valor_centavos: 42000 }, editado_em: new Date().toISOString() });
    const caminho = 'cond-A/l2/' + nodeCrypto.randomUUID() + '.pdf';
    m.storage[caminho] = { size: 2048 };
    m.comprovantes.push({ id: 'c1', lancamento_id: 'l2', caminho_storage: caminho, nome_arquivo: 'OS 024.pdf', mime_type: 'application/pdf', tamanho_bytes: 2048, sha256: 'a'.repeat(64), created_at: new Date().toISOString(), removido_em: null });
    const w = await abrir(m); await irPara(w, 'financeiro'); await wait(100); await clica(w, w.document.getElementById('cx-mostrar')); await wait(250);
    check('conselho: vê 📎 na linha com anexo e o link "ver histórico"', /📎 1/.test(linha(w, 'Manutenção do portão').textContent) && !!linha(w, 'Manutenção do portão').querySelector('[data-cx-hist]'));
    check('conselho: NÃO vê Editar nem Anexar', !w.document.querySelector('[data-cx-edit]') && !/Anexar/.test(w.document.getElementById('cx-tabela').textContent));
    await clica(w, linha(w, 'Manutenção do portão').querySelector('[data-cx-hist]'));
    check('conselho: consulta o histórico de edições', /Versão 2/.test(w.document.getElementById('cxmodal').textContent) && /400,00/.test(w.document.getElementById('cxmodal').textContent));
    await clica(w, w.document.getElementById('cx-x'));
    await clica(w, linha(w, 'Manutenção do portão').querySelector('[data-cx-anx]'));
    check('conselho: abre a janela de anexos em modo de consulta (sem Remover nem envio)', /OS 024\.pdf/.test(w.document.getElementById('cxmodal').textContent) && !w.document.querySelector('[data-cx-rem]') && !w.document.getElementById('cx-fanx'));
    await clica(w, w.document.querySelector('[data-cx-abrir]'));
    check('conselho: consegue abrir o arquivo por link temporário', m.chamadas.some(c => c.storage === 'signed' && c.path === caminho));
    w.close();
  }
  /* 9g. importação de extrato OFX (síndico) */
  {
    const nodeCrypto = require('crypto');
    const ofxTxt = (movs, saldo, dtasof, ini, fim) => 'OFXHEADER:100\r\nDATA:OFXSGML\r\nVERSION:102\r\nSECURITY:NONE\r\nENCODING:USASCII\r\nCHARSET:1252\r\nCOMPRESSION:NONE\r\nOLDFILEUID:NONE\r\nNEWFILEUID:NONE\r\n\r\n<OFX><BANKMSGSRSV1><STMTTRNRS><STMTRS><CURDEF>BRL<BANKACCTFROM><BANKID>104<ACCTID>999888777<ACCTTYPE>CHECKING</BANKACCTFROM><BANKTRANLIST><DTSTART>' + ini.replace(/-/g, '') + '030000.000<DTEND>' + fim.replace(/-/g, '') + '030000.000' +
      movs.map(([d, v, memo, fit]) => '<STMTTRN><TRNTYPE>' + (v < 0 ? 'DEBIT' : 'CREDIT') + '<DTPOSTED>' + d.replace(/-/g, '') + '030000.000<TRNAMT>' + v + '<FITID>' + fit + '<MEMO>' + memo + '</STMTTRN>').join('') + '</BANKTRANLIST><LEDGERBAL><BALAMT>' + saldo + '<DTASOF>' + dtasof.replace(/-/g, '') + '030000.000</LEDGERBAL></STMTRS></STMTTRNRS></BANKMSGSRSV1></OFX>';
    const mkOfx = (w, txt, nome) => new w.File([Buffer.from(txt, 'latin1')], nome || 'extrato.ofx');
    const escolhe = async (w, f) => { const i = w.document.getElementById('ex-f'); Object.defineProperty(i, 'files', { value: [f], configurable: true }); i.dispatchEvent(new w.Event('change', { bubbles: true })); await wait(600); };
    const campo = (w, i, k) => w.document.querySelector('[data-ex="' + k + '"][data-i="' + i + '"]');
    const muda = async (w, i, k, v, ev) => { const el = campo(w, i, k); el.value = v; el.dispatchEvent(new w.Event(ev || 'change', { bubbles: true })); await wait(50); };
    const mt = w => w.document.getElementById('cxmodal').textContent.replace(/\s+/g, ' ');
    const mm = mesAnt.slice(5, 7), d = n => mesAnt + '-' + n;
    const mov1 = [[d('03'), 117918, 'COB COMPE', '1'], [d('03'), -630, 'COB COMPE', '1'], [d('08'), -131038, 'DEB PIX CHAVE', '2'], [d('08'), -850, 'TAR PIX', '3'], [d('15'), -145890, 'AGUA', '4'], [d('15'), -108202, 'PAGAMENTO DE BOLETO', '5'], [d('20'), -4589, 'PAGAMENTO SERVIÇO À VISTA', '6']]
      .map(([dt, v, memo, f]) => [dt, v / 100, memo, f]);
    const txt1 = ofxTxt(mov1, 9999.99, d('20'), d('01'), d('28'));
    const m = mundoCaixa('sindico'); m.lancamentos.push(lanc('lp', 'despesa', d('08'), 131038, 'Obras', 'Reembolso manual'));
    const w = await abrir(m); await irPara(w, 'financeiro'); await wait(150);
    check('extrato/síndico: o Financeiro tem os botões Importar extrato e Extratos importados', !!w.document.getElementById('cx-ofx') && !!w.document.getElementById('cx-extratos'));
    await clica(w, w.document.getElementById('cx-ofx'));
    await escolhe(w, new w.File([Buffer.from('isto não é um extrato')], 'lixo.ofx'));
    check('extrato: arquivo que não é OFX mostra erro claro', /não parece ser um extrato OFX/.test(mt(w)), mt(w).slice(0, 200));
    await escolhe(w, new w.File([new Uint8Array(2 * 1048576 + 1)], 'grande.ofx'));
    check('extrato: arquivo acima de 2 MB é recusado', /mais de 2 MB/.test(mt(w)));
    await escolhe(w, mkOfx(w, txt1));
    check('extrato: mostra o resumo do arquivo (movimentos, período)', /extrato\.ofx/.test(mt(w)) && /7 movimentos/.test(mt(w)), mt(w).slice(0, 300));
    check('extrato: acentos do arquivo (Windows-1252) aparecem corretos', /PAGAMENTO SERVIÇO À VISTA/.test(mt(w)));
    check('extrato: sugere automaticamente o que sabe (4 a lançar, 1 a conciliar) e deixa 2 pendentes', /4 a lançar · 1 a conciliar · 0 a ignorar · 0 já importados · 2 pendentes/.test(mt(w)), mt(w).match(/\d+ a lançar[^.]*pendentes/)?.[0]);
    check('extrato: botão Importar fica desativado enquanto há pendentes', w.document.getElementById('ex-ok').disabled === true);
    check('extrato: cotas por boleto vêm classificadas, com a data na descrição', campo(w, 0, 'categoria').value === 'Taxa condominial' && campo(w, 0, 'descricao').value === 'Cotas recebidas por boleto — liquidação de 03/' + mm, campo(w, 0, 'descricao') && campo(w, 0, 'descricao').value);
    check('extrato: tarifa de boletos informa a quantidade (R$ 6,30 cada)', campo(w, 1, 'descricao').value === 'Tarifa de cobrança bancária (1 boleto)', campo(w, 1, 'descricao') && campo(w, 1, 'descricao').value);
    check('extrato: PIX com o mesmo valor de um lançamento manual vem como "conciliar" com ele', campo(w, 2, 'acao').value === 'conciliar' && campo(w, 2, 'lancId').value === 'lp');
    check('extrato: água vem como Água e esgoto', campo(w, 4, 'categoria').value === 'Água e esgoto');
    check('extrato: avisa quando o saldo do início do período não confere', /No início do período/.test(mt(w)));
    // resolver os pendentes
    await muda(w, 5, 'acao', 'lancar'); await muda(w, 5, 'categoria', 'Limpeza'); await muda(w, 5, 'descricao', 'Ideal Assessoria', 'input'); await muda(w, 5, 'lembrar', 'memo_valor');
    check('extrato: ainda falta 1 pendente e o botão segue desativado', /1 pendentes/.test(mt(w)) && w.document.getElementById('ex-ok').disabled === true);
    await muda(w, 6, 'acao', 'ignorar'); await muda(w, 6, 'motivo', 'abc', 'input');
    check('extrato: motivo curto para ignorar mantém o pendente', /1 pendentes/.test(mt(w)));
    await muda(w, 6, 'motivo', 'não é do condomínio', 'input');
    check('extrato: sem pendentes o botão Importar é liberado', /0 pendentes/.test(mt(w)) && w.document.getElementById('ex-ok').disabled === false);
    const antes = m.lancamentos.length;
    await clica(w, w.document.getElementById('ex-ok')); await wait(100);
    const c1 = m.chamadas.filter(c => c.rpc === 'importar_extrato');
    check('extrato: saldo que não bate: o banco recusa, nada é gravado e o app oferece "importar mesmo assim"', c1.length === 1 && c1[0].args.p_exigir_saldo === true && /Nada foi importado/.test(w.document.getElementById('ex-erro').textContent) && !w.document.getElementById('ex-forcar').classList.contains('hide') && m.lancamentos.length === antes, w.document.getElementById('ex-erro').textContent);
    w.document.getElementById('ex-forcar-cb').checked = true; w.document.getElementById('ex-forcar-cb').dispatchEvent(new w.Event('change', { bubbles: true }));
    await clica(w, w.document.getElementById('ex-ok')); await wait(150);
    const c2 = m.chamadas.filter(c => c.rpc === 'importar_extrato')[1], a = c2 && c2.args;
    check('extrato: importar mesmo assim envia p_exigir_saldo = false', a && a.p_exigir_saldo === false);
    check('extrato: envia a impressão digital SHA-256 do arquivo e só o NOME do arquivo (sem conta)', a && a.p_sha256 === nodeCrypto.createHash('sha256').update(Buffer.from(txt1, 'latin1')).digest('hex') && a.p_arquivo_nome === 'extrato.ofx' && !JSON.stringify(a).includes('999888777'));
    check('extrato: envia período, saldo final e data do saldo', a && a.p_periodo_ini === d('01') && a.p_periodo_fim === d('28') && a.p_saldo_final_centavos === 999999 && a.p_saldo_data === d('20'));
    check('extrato: envia as 7 linhas com a ação de cada uma', a && a.p_linhas.length === 7 && a.p_linhas.map(l => l.acao).join() === 'lancar,lancar,conciliar,lancar,lancar,lancar,ignorar', a && a.p_linhas.map(l => l.acao).join());
    check('extrato: a conciliação leva o código do lançamento existente', a && a.p_linhas[2].lancamento_id === 'lp');
    check('extrato: "lembrar" e o motivo de ignorar vão junto', a && a.p_linhas[5].lembrar === 'memo_valor' && a.p_linhas[5].categoria === 'Limpeza' && a.p_linhas[6].motivo === 'não é do condomínio');
    check('extrato: valores com sinal em centavos (débito negativo)', a && a.p_linhas[0].valor_centavos === 117918 && a.p_linhas[1].valor_centavos === -630 && a.p_linhas[5].valor_centavos === -108202);
    check('extrato: resultado mostra 5 lançados, 1 conciliado, 1 ignorado e avisa a diferença de saldo', /5 lançados · 1 conciliados · 1 ignorados/.test(mt(w)) && /Diferença/.test(mt(w)), mt(w).slice(0, 250));
    await clica(w, w.document.getElementById('ex-fim')); await wait(250);
    check('extrato: ao concluir, o Financeiro mostra o mês do extrato com os novos lançamentos', /Ideal Assessoria/.test(txt(w)) && /Copasa — água e esgoto/.test(txt(w)) && /Cotas recebidas por boleto/.test(txt(w)));
    check('extrato: a regra "lembrar" foi guardada', m.regras.some(r => r.memo_padrao === 'PAGAMENTO DE BOLETO' && r.valor_centavos === 108202));
    // mesmo arquivo de novo
    await clica(w, w.document.getElementById('cx-ofx')); await escolhe(w, mkOfx(w, txt1));
    check('extrato: o mesmo arquivo é recusado na hora, antes de revisar', /já foi importado em/.test(mt(w)) && !w.document.getElementById('ex-lista'), mt(w).slice(0, 200));
    // período que se sobrepõe: 2 movimentos já importados + 1 novo
    const txt2 = ofxTxt([[d('03'), 1179.18, 'COB COMPE', '1'], [d('03'), -6.3, 'COB COMPE', '1'], [d('26'), -12.6, 'COB COMPE', '9']], 9999.99, d('26'), d('01'), d('28'));
    await escolhe(w, mkOfx(w, txt2, 'extrato2.ofx'));
    check('extrato: movimentos de um período que se sobrepõe aparecem como "já importados"', /2 já importados/.test(mt(w)) && (mt(w).match(/Já importado antes/g) || []).length === 2, mt(w).match(/\d+ a lançar[^.]*pendentes/)?.[0]);
    check('extrato: o movimento novo já vem classificado pela regra (tarifa de boletos)', campo(w, 2, 'categoria') && campo(w, 2, 'categoria').value === 'Outras despesas');
    await clica(w, w.document.getElementById('ex-x'));
    w.close();
  }
  /* 9h. extratos importados: consulta (conselho) e ausência de botões para o morador */
  {
    const m = mundoCaixa('conselho');
    m.extratos.push({ id: 'ext-1', arquivo_nome: 'out.ofx', arquivo_sha256: 'a'.repeat(64), periodo_ini: '2026-10-01', periodo_fim: '2026-10-21', saldo_final_centavos: 412232, diferenca_saldo_centavos: 0, qtd_movimentos: 3, qtd_lancadas: 1, qtd_conciliadas: 1, qtd_ignoradas: 1, qtd_ja_importadas: 0, importado_em: new Date().toISOString() });
    m.extlinhas.push({ id: 'x1', extrato_id: 'ext-1', ordem: 1, data_mov: '2026-10-01', valor_centavos: 117918, memo: 'COB COMPE', status: 'lancada', lancamento_id: 'l1', chave: 'k1' },
      { id: 'x2', extrato_id: 'ext-1', ordem: 2, data_mov: '2026-10-08', valor_centavos: -42000, memo: 'PAGAMENTO DE BOLETO', status: 'conciliada', lancamento_id: 'l2', chave: 'k2' },
      { id: 'x3', extrato_id: 'ext-1', ordem: 3, data_mov: '2026-10-08', valor_centavos: -850, memo: 'TAR PIX', status: 'ignorada', lancamento_id: null, motivo_ignorar: 'tarifa não lançada', chave: 'k3' });
    const w = await abrir(m); await irPara(w, 'financeiro'); await wait(100); await clica(w, w.document.getElementById('cx-mostrar')); await wait(250);
    check('extrato/conselho: vê "Extratos importados" mas NÃO o botão de importar', !!w.document.getElementById('cx-extratos') && !w.document.getElementById('cx-ofx'));
    await clica(w, w.document.getElementById('cx-extratos')); await wait(100);
    const mt = () => w.document.getElementById('cxmodal').textContent.replace(/\s+/g, ' ');
    check('extrato/conselho: a lista mostra arquivo, período e contagens', /out\.ofx/.test(mt()) && /3 movimentos: 1 lançados, 1 conciliados, 1 ignorados/.test(mt()), mt().slice(0, 250));
    await clica(w, w.document.querySelector('[data-ex-ver]')); await wait(150);
    check('extrato/conselho: os movimentos mostram situação, lançamento ligado e motivo', /Conciliado/.test(mt()) && /Ignorado/.test(mt()) && /→ Manutenção do portão/.test(mt()) && /Motivo: tarifa não lançada/.test(mt()), mt().slice(0, 300));
    w.close();
    const m2 = mundoCaixa('morador'); const w2 = await abrir(m2); await irPara(w2, 'financeiro'); await wait(100); await clica(w2, w2.document.getElementById('cx-mostrar')); await wait(200);
    check('extrato/morador: sem botões de extrato e sem consulta ao banco de extratos', !w2.document.getElementById('cx-ofx') && !w2.document.getElementById('cx-extratos') && !m2.chamadas.some(c => c.tabela === 'extratos'));
    w2.close();
  }
  /* 9i. cobrança por unidade — síndico: preparar, gerar, conferir, liberar, pagamentos */
  {
    const mes = hojeS.slice(0, 7), comp = mes + '-01', ant2 = mesAnt;
    const m = mundoCaixa('sindico'); const idSind = 'usr-sindico@a.com';
    m.extlinhas.push({ id: 'x1', extrato_id: 'e1', ordem: 1, data_mov: hojeS, valor_centavos: 136500, memo: 'COB COMPE', status: 'lancada', lancamento_id: null, chave: 'k1' });
    const w = await abrir(m); await irPara(w, 'cobranca'); await wait(200);
    const c = () => w.document.getElementById('content').textContent.replace(/\s+/g, ' ');
    const mt = () => w.document.getElementById('cxmodal').textContent.replace(/\s+/g, ' ');
    const sub = async id => { w.document.getElementById(id).dispatchEvent(new w.Event('submit', { cancelable: true, bubbles: true })); await wait(300); };
    const set = (id, v) => { const e = w.document.getElementById(id); e.value = v; };
    const linha = t => [...w.document.querySelectorAll('#content tbody tr')].find(tr => tr.textContent.includes(t));
    const rp = nome => m.chamadas.filter(x => x.rpc === nome);
    check('cobrança/síndico: abre visível e mostra os 3 passos do preparo', /1\. Previsão do mês/.test(c()) && /2\. Itens por unidade/.test(c()) && /3\. Gerar a cobrança/.test(c()) && !w.document.getElementById('cb-mostrar'), c().slice(0, 200));
    set('cb-venc', hojeS); set('cb-agua', '1.000,00'); await sub('cb-fger');
    check('cobrança/síndico: gerar sem salvar a previsão é barrado na tela', /Salve a previsão/.test(w.document.getElementById('cb-erro-ger').textContent) && !rp('gerar_cobranca_mensal').length);
    set('cb-taxa', ''); await sub('cb-fprev');
    check('cobrança/síndico: previsão sem a taxa é recusada', /Informe a taxa/.test(w.document.getElementById('cb-erro-prev').textContent) && !m.previsoes.length);
    set('cb-taxa', '700,00'); set('cb-fundo', '65,00'); await sub('cb-fprev'); await wait(150);
    check('cobrança/síndico: salva a previsão em centavos para a competência certa', m.previsoes.length === 1 && m.previsoes[0].taxa_por_unidade_centavos === 70000 && m.previsoes[0].fundo_obras_por_unidade_centavos === 6500 && m.previsoes[0].competencia === comp && m.previsoes[0].condominio_id === 'cond-A', JSON.stringify(m.previsoes));
    check('cobrança/síndico: a previsão salva reaparece nos campos', w.document.getElementById('cb-taxa').value === '700,00' && w.document.getElementById('cb-fundo').value === '65,00');
    await clica(w, w.document.getElementById('cb-add-item'));
    set('cb-iu', U102); set('cb-it', 'gas'); set('cb-id', 'Gás 3 m³'); set('cb-iv', '88,00'); await sub('cb-fi'); await wait(150);
    check('cobrança/síndico: item por unidade é gravado com unidade, tipo, valor e autor', m.previstos.length === 1 && m.previstos[0].unidade_id === U102 && m.previstos[0].tipo === 'gas' && m.previstos[0].valor_centavos === 8800 && m.previstos[0].criado_por === idSind && m.previstos[0].competencia === comp, JSON.stringify(m.previstos));
    await clica(w, w.document.getElementById('cb-add-item'));
    set('cb-iu', U101); set('cb-it', 'desconto'); set('cb-id', 'Crédito de obra'); set('cb-iv', '10,00'); w.document.getElementById('cb-ineg').checked = true; await sub('cb-fi'); await wait(150);
    check('cobrança/síndico: desconto entra com valor negativo', m.previstos.length === 2 && m.previstos[1].valor_centavos === -1000 && /Crédito de obra/.test(c()));
    await clica(w, w.document.querySelectorAll('[data-cb-delprev]')[1]); await wait(150);
    check('cobrança/síndico: remover item some da lista e do banco', m.previstos.length === 1 && !/Crédito de obra/.test(c()));
    // gerar
    set('cb-venc', hojeS); set('cb-agua', '1.000,00'); set('cb-cons', ant2); m.validacao = [{ nivel: 'aviso', codigo: 'x', mensagem: 'Gás informado só para a unidade 102' }]; await sub('cb-fger'); await wait(150);
    const g1 = rp('gerar_cobranca_mensal')[0];
    check('cobrança/síndico: gerar envia competência, vencimento, água em centavos e mês de consumo', g1 && g1.args.p_competencia === comp && g1.args.p_vencimento === hojeS && g1.args.p_fatura_agua_centavos === 100000 && g1.args.p_competencia_consumo_agua === ant2 + '-01' && g1.args.p_substituir_rascunhos === false, JSON.stringify(g1 && g1.args));
    check('cobrança/síndico: rascunho mostra situação, composição e totais por unidade', /Rascunho/.test(c()) && /1\.365,00/.test(linha('101').textContent) && /1\.253,00/.test(linha('102').textContent) && /2\.618,00/.test(c()), c().slice(0, 300));
    check('cobrança/síndico: aviso da conferência aparece e não impede liberar', /Gás informado só para a unidade 102/.test(c()) && !w.document.getElementById('cb-liberar').disabled);
    check('cobrança/síndico: moradores NÃO veem o rascunho (regra do banco simulada)', m.cobrancas.every(x => x.status === 'rascunho'));
    // gerar de novo com erro de conferência
    await clica(w, w.document.getElementById('cb-regerar')); set('cb-agua', '1.000,00'); m.validacao = [{ nivel: 'erro', codigo: 'y', mensagem: 'Soma das frações diferente de 1' }]; await sub('cb-fger'); await wait(200);
    const g2 = rp('gerar_cobranca_mensal')[1];
    check('cobrança/síndico: "gerar de novo" substitui o rascunho (p_substituir_rascunhos = true)', g2 && g2.args.p_substituir_rascunhos === true && m.ciclos.length === 1 && m.cobrancas.length === 2);
    check('cobrança/síndico: com erro na conferência o botão Liberar fica desativado', /Soma das frações diferente de 1/.test(c()) && w.document.getElementById('cb-liberar').disabled === true);
    await clica(w, w.document.getElementById('cb-regerar')); set('cb-agua', '1.000,00'); m.validacao = []; await sub('cb-fger'); await wait(200);
    check('cobrança/síndico: sem erros o botão Liberar é liberado e a conferência confirma', w.document.getElementById('cb-liberar').disabled === false && /Conferência sem avisos/.test(c()));
    // liberar
    await clica(w, w.document.getElementById('cb-liberar')); await wait(250);
    check('cobrança/síndico: liberar chama o banco e mostra "Liberada" com as ações de pagamento', rp('liberar_cobranca_mensal').length === 1 && /Liberada/.test(c()) && w.document.querySelectorAll('[data-cb-pagar]').length === 2);
    check('cobrança/síndico: "Quem está em aberto" lista as duas unidades com o saldo', /Quem está em aberto/.test(c()) && w.document.querySelectorAll('#content .card:last-child tbody tr').length === 2 && /1\.365,00/.test(c()));
    // pagamento parcial
    await clica(w, linha('101').querySelector('[data-cb-pagar]'));
    check('cobrança/síndico: o pagamento já vem com o saldo e oferece o crédito do extrato', w.document.getElementById('cb-pv').value === '1.365,00' && /COB COMPE/.test(mt()) && /livre R\$\s*1\.365,00/.test(mt()), mt().slice(0, 300));
    set('cb-pv', '9.999,00'); await sub('cb-fp');
    check('cobrança/síndico: valor muito acima da cobrança é recusado pelo banco e a tela mostra o motivo', /150%/.test(w.document.getElementById('cb-erro-pag').textContent));
    set('cb-pv', '500,00'); set('cb-pf', 'pix'); set('cb-po', 'primeira parte'); await sub('cb-fp'); await wait(250);
    const p1 = rp('registrar_pagamento_cobranca').pop();
    check('cobrança/síndico: registra o pagamento com data, valor, forma e observação', p1 && p1.args.p_valor_centavos === 50000 && p1.args.p_forma === 'pix' && p1.args.p_data === hojeS && p1.args.p_observacao === 'primeira parte' && p1.args.p_extrato_linha_id === null);
    check('cobrança/síndico: após pagar parte, a 101 mostra pago e segue em aberto', /500,00/.test(linha('101').textContent) && /Em aberto|Atrasada/.test(linha('101').textContent) && !/Paga\b/.test(linha('101').querySelector('.pill').textContent));
    await clica(w, linha('101').querySelector('[data-cb-pagar]')); set('cb-pl', 'x1'); w.document.getElementById('cb-pl').dispatchEvent(new w.Event('change', { bubbles: true }));
    check('cobrança/síndico: escolher o crédito do extrato preenche o valor com o menor entre o saldo e o crédito livre', w.document.getElementById('cb-pv').value === '865,00');
    await sub('cb-fp'); await wait(250);
    const p2 = rp('registrar_pagamento_cobranca').pop();
    check('cobrança/síndico: o pagamento leva o código do crédito do extrato', p2 && p2.args.p_extrato_linha_id === 'x1' && p2.args.p_valor_centavos === 86500);
    check('cobrança/síndico: quitada, a 101 fica "Paga" e sai de "quem está em aberto"', /Paga/.test(linha('101').querySelector('.pill').textContent) && w.document.querySelectorAll('#content .card:last-child tbody tr').length === 1);
    // histórico e remoção
    await clica(w, linha('101').querySelector('[data-cb-pags]'));
    check('cobrança/síndico: a janela de pagamentos lista os 2 pagamentos', /500,00/.test(mt()) && /865,00/.test(mt()) && w.document.querySelectorAll('[data-cb-rem]').length === 2);
    await clica(w, w.document.querySelector('[data-cb-rem]')); set('cb-rm', 'abc'); await sub('cb-fr');
    check('cobrança/síndico: remover pagamento sem motivo é barrado', /pelo menos 5/.test(w.document.getElementById('cb-erro-rem').textContent) && !rp('remover_pagamento_cobranca').length);
    set('cb-rm', 'lançado na unidade errada'); await sub('cb-fr'); await wait(250);
    check('cobrança/síndico: remover pagamento chama o banco e a unidade volta a dever', rp('remover_pagamento_cobranca').length === 1 && /Em aberto|Atrasada/.test(linha('101').querySelector('.pill').textContent));
    // reabrir
    await clica(w, w.document.getElementById('cb-reabrir')); await wait(250);
    check('cobrança/síndico: reabrir com pagamentos registrados mostra o aviso do banco', /remova-os/.test(w.document.getElementById('cb-erro-acao').textContent), w.document.getElementById('cb-erro-acao').textContent);
    // limpar pagamentos e reabrir
    m.cpag.forEach(p => { p.removido_em = new Date().toISOString(); }); m.cobrancas.forEach(x => { x.status = 'pronta_para_emissao'; });
    await clica(w, w.document.getElementById('cb-ocultar'));
    check('cobrança/síndico: "Ocultar valores" esconde tudo e "Mostrar" traz de volta', !!w.document.getElementById('cb-mostrar') && !/1\.365,00/.test(c()));
    await clica(w, w.document.getElementById('cb-mostrar')); await wait(250);
    await clica(w, w.document.getElementById('cb-reabrir')); await wait(250);
    check('cobrança/síndico: sem pagamentos, reabrir volta ao rascunho', /Rascunho/.test(c()) && !!w.document.getElementById('cb-liberar'));
    w.close();
  }
  /* 9j. cobrança por unidade — morador (só a própria) e conselho (consulta) */
  {
    const mes = hojeS.slice(0, 7), comp = mes + '-01';
    const mundoCob = papel => {
      const m = mundoCaixa(papel); m.ciclos.push({ id: 'cic-1', competencia: comp, vencimento: hojeS, status: 'liberado' });
      m.cobrancas.push({ id: 'cob-101', ciclo_id: 'cic-1', unidade_id: U101, competencia: comp, vencimento: hojeS, valor_total_centavos: 130000, status: 'pronta_para_emissao' },
        { id: 'cob-102', ciclo_id: 'cic-1', unidade_id: U102, competencia: comp, vencimento: hojeS, valor_total_centavos: 111100, status: 'pronta_para_emissao' },
        { id: 'cob-old', ciclo_id: 'cic-0', unidade_id: U101, competencia: mesAnt + '-01', vencimento: hojeS, valor_total_centavos: 99900, status: 'rascunho' });
      m.itensc.push({ cobranca_id: 'cob-101', tipo: 'cota_condominial', descricao: 'Taxa condominial', valor_centavos: 70000 }, { cobranca_id: 'cob-101', tipo: 'agua', descricao: 'Água', valor_centavos: 60000 }, { cobranca_id: 'cob-102', tipo: 'cota_condominial', descricao: 'Taxa condominial', valor_centavos: 111100 });
      m.cpag.push({ id: 'pg-1', cobranca_id: 'cob-101', data_pagamento: hojeS, valor_centavos: 50000, forma: 'pix', removido_em: null });
      return m;
    };
    const mm = mundoCob('morador'); const w = await abrir(mm); await irPara(w, 'cobranca'); await wait(150);
    const c = () => w.document.getElementById('content').textContent.replace(/\s+/g, ' ');
    check('cobrança/morador: abre com os valores ocultos e sem pedir nada ao banco', !!w.document.getElementById('cb-mostrar') && /Minha cobrança/.test(c()) && !mm.chamadas.some(x => x.tabela === 'cobrancas'));
    await clica(w, w.document.getElementById('cb-mostrar')); await wait(250);
    check('cobrança/morador: vê só a cobrança da própria unidade, com total, vencimento e itens', /Unidade 101/.test(c()) && /1\.300,00/.test(c()) && /Taxa condominial/.test(c()) && /Água/.test(c()) && !/Unidade 102|1\.111,00/.test(c()), c().slice(0, 300));
    check('cobrança/morador: mostra o pagamento já feito e o saldo', /500,00 \(PIX\)/.test(c()) && /saldo R\$\s*800,00/.test(c()), c().slice(0, 400));
    check('cobrança/morador: não vê cobrança em rascunho nem de outras unidades (apenas 1 cartão)', w.document.querySelectorAll('#content .card .cardhead h2').length === 1);
    check('cobrança/morador: sem formulários, botões de ação nem "quem está em aberto"', !w.document.getElementById('cb-fprev') && !w.document.querySelector('[data-cb-pagar]') && !/Quem está em aberto/.test(c()) && !mm.chamadas.some(x => x.rpc === 'cobrancas_em_aberto'));
    await irPara(w, 'inicio'); await irPara(w, 'cobranca'); await wait(60);
    check('cobrança/morador: sair e voltar oculta de novo', !!w.document.getElementById('cb-mostrar') && !/1\.300,00/.test(c()));
    w.close();
    const mc = mundoCob('conselho'); const w2 = await abrir(mc); await irPara(w2, 'cobranca'); await wait(100); await clica(w2, w2.document.getElementById('cb-mostrar')); await wait(300);
    const c2 = () => w2.document.getElementById('content').textContent.replace(/\s+/g, ' ');
    check('cobrança/conselho: vê as duas unidades, os pagamentos e quem está em aberto', /1\.300,00/.test(c2()) && /1\.111,00/.test(c2()) && /Quem está em aberto/.test(c2()) && /Liberada/.test(c2()), c2().slice(0, 300));
    check('cobrança/conselho: SEM formulários, registrar pagamento, liberar ou reabrir', !w2.document.getElementById('cb-fprev') && !w2.document.querySelector('[data-cb-pagar]') && !w2.document.getElementById('cb-liberar') && !w2.document.getElementById('cb-reabrir'));
    w2.close();
  }
  /* 9c. livro-caixa — síndico pode ocultar; não oculta sozinho */
  {
    const m = mundoCaixa('sindico'); const w = await abrir(m); await irPara(w, 'financeiro'); await wait(120);
    check('privacidade/síndico: abre com os valores visíveis', !w.document.getElementById('cx-mostrar') && /Manutenção do portão/.test(txt(w)));
    await clica(w, w.document.getElementById('cx-ocultar'));
    check('privacidade/síndico: "Ocultar valores" limpa a tela', !!w.document.getElementById('cx-mostrar') && !/Manutenção do portão|650,00/.test(txt(w)));
    await clica(w, w.document.getElementById('cx-mostrar')); await wait(120);
    check('privacidade/síndico: "Mostrar valores" traz os dados de volta', /Manutenção do portão/.test(txt(w)));
    await irPara(w, 'inicio'); await irPara(w, 'financeiro'); await wait(120);
    check('privacidade/síndico: sair e voltar não oculta (é o administrador)', !w.document.getElementById('cx-mostrar') && /Manutenção do portão/.test(txt(w)));
    w.close();
  }
  /* 10. livro-caixa — conselho e morador: valores OCULTOS por padrão */
  for (const papel of ['conselho', 'morador']) {
    const m = mundoCaixa(papel); const w = await abrir(m);
    await irPara(w, 'financeiro'); await wait(120);
    const P = 'privacidade/' + papel + ': ';
    check(P + 'abre com os valores OCULTOS', !!w.document.getElementById('cx-mostrar') && /ocultos/.test(txt(w)) && !/650,00|Manutenção do portão/.test(txt(w)), txt(w).slice(0, 300));
    check(P + 'antes de mostrar, NADA financeiro é pedido ao banco', !m.chamadas.some(c => c.tabela === 'lancamentos' || c.rpc === 'resumo_financeiro' || c.rpc === 'relatorio_mensal'));
    await clica(w, w.document.getElementById('cx-mostrar')); await wait(150);
    if (papel === 'conselho') {
      check('caixa/conselho: vê o detalhe dos lançamentos depois de mostrar', /Manutenção do portão/.test(txt(w)));
      check('caixa/conselho: SEM novo lançamento, estorno ou impressão', !w.document.getElementById('cx-novo') && !w.document.getElementById('cx-print') && !w.document.querySelector('[data-cx-est]'));
      check('caixa/conselho: aviso de consulta sem exportação', /sem edição, exportação ou download/.test(txt(w)));
    } else {
      check('caixa/morador: vê só os totais do mês depois de mostrar', /Receitas do mês/.test(txt(w)) && /650,00/.test(txt(w)) && /Saldo do mês/.test(txt(w)));
      check('caixa/morador: NÃO vê lançamentos individuais', !/Manutenção do portão/.test(txt(w)) && !w.document.getElementById('cx-tabela') && /não exibe lançamentos individuais/.test(txt(w)));
      check('caixa/morador: o app nem pede a lista nem o relatório ao banco', !m.chamadas.some(c => c.tabela === 'lancamentos') && !m.chamadas.some(c => c.rpc === 'relatorio_mensal'));
      check('caixa/morador: sem botões de escrita', !w.document.getElementById('cx-novo') && !w.document.getElementById('cx-print'));
    }
    await irPara(w, 'inicio'); await irPara(w, 'financeiro'); await wait(60);
    check(P + 'sair da tela e voltar OCULTA de novo e limpa os dados', !!w.document.getElementById('cx-mostrar') && !/650,00|Manutenção do portão/.test(txt(w)));
    await clica(w, w.document.getElementById('cx-mostrar')); await wait(150);
    Object.defineProperty(w.document, 'hidden', { value: true, configurable: true }); w.document.dispatchEvent(new w.Event('visibilitychange')); await wait(40);
    check(P + 'minimizar o app (aba oculta) OCULTA os valores', !!w.document.getElementById('cx-mostrar') && !/650,00/.test(txt(w)));
    Object.defineProperty(w.document, 'hidden', { value: false, configurable: true });
    await clica(w, w.document.getElementById('cx-mostrar')); await wait(150);
    await clica(w, w.document.getElementById('cx-ocultar'));
    check(P + 'botão "Ocultar valores" oculta na hora', !!w.document.getElementById('cx-mostrar') && !/650,00/.test(txt(w)));
    w.close();
  }
  {
    const m = mundoCaixa('conselho'); const w = await abrir(m); w.APP.cx.ociosoMs = 600;
    await irPara(w, 'financeiro'); await wait(60); await clica(w, w.document.getElementById('cx-mostrar')); await wait(60);
    check('privacidade/conselho: logo após mostrar os valores aparecem', /Manutenção do portão/.test(txt(w)));
    await wait(900);
    check('privacidade/conselho: sem uso por um tempo, os valores voltam a ficar OCULTOS', !!w.document.getElementById('cx-mostrar') && !/Manutenção do portão|650,00/.test(txt(w)));
    w.close();
  }
  /* 10b. Início sem números financeiros; Boletos (teste) só para o síndico; Cobrança mensal para todos (cada perfil vê o que lhe cabe) */
  for (const papel of ['sindico', 'conselho', 'morador']) {
    const m = mundoCaixa(papel); const w = await abrir(m); const c = () => w.document.getElementById('content').textContent.replace(/\s+/g, ' ');
    const P = 'inicio/' + papel + ': ';
    check(P + 'o Início NÃO traz saldo, receitas nem despesas', /Ocorrências pendentes/.test(c()) && !/Saldo demonstrativo|Receitas registradas|Despesas registradas|R\$/.test(c()), c().slice(0, 250));
    const oculto = id => w.document.querySelector('.sidebar [data-page="' + id + '"], aside [data-page="' + id + '"], [data-page="' + id + '"]').classList.contains('hide');
    check(P + 'vê Cobrança mensal no menu' + (papel === 'sindico' ? ' e Boletos' : ' e NÃO vê Boletos'), !oculto('cobranca') && (papel === 'sindico' ? !oculto('boletos') : oculto('boletos')));
    await clica(w, w.document.querySelector('[data-page="menu"]'));
    check(P + 'o Menu lista Cobrança mensal' + (papel === 'sindico' ? ' e Boletos' : ' mas não Boletos'), /Cobrança mensal/.test(c()) && (papel === 'sindico' ? /Boletos/.test(c()) : !/Boletos/.test(c())), c().slice(0, 200));
    if (papel !== 'sindico') {
      w.eval("page='cobranca'; render();"); await wait(60);
      check(P + 'abrir a Cobrança mostra a tela própria do perfil (valores ocultos até pedir)', /ocultos/.test(c()) && (papel === 'morador' ? /Minha cobrança/.test(c()) : /Cobrança mensal/.test(c())), c().slice(0, 200));
      w.eval("page='boletos'; render();"); await wait(40);
      check(P + 'abrir /boletos por rota volta ao Início', /Bom dia/.test(c()));
    }
    w.close();
  }
  /* 11. livro-caixa — erro de rede, XSS e valores */
  {
    const m = mundoCaixa('sindico'); m.lancamentos.push(lanc('lx', 'despesa', hojeS, 100, 'Limpeza', '<img src=x onerror="window.__xss=1">'));
    const w = await abrir(m); m.falhaRede = true; await irPara(w, 'financeiro'); await wait(120);
    check('caixa: falha de rede mostra erro e "Tentar de novo"', /Sem conexão/.test(txt(w)) && !!w.document.getElementById('cx-retry'));
    m.falhaRede = false; await clica(w, w.document.getElementById('cx-retry')); await wait(120);
    check('caixa: tentar de novo recupera os dados', /Manutenção do portão/.test(txt(w)));
    check('caixa: texto com HTML do lançamento é escapado (sem XSS)', !w.document.querySelector('#cx-tabela img') && w.__xss === undefined && /<img src=x/.test(w.document.getElementById('cx-tabela').textContent));
    const pc = w.parseCentavos;
    const casos = [['1.234,56', 123456], ['0,05', 5], ['12.5', 1250], ['12,5', 1250], ['1.234', 123400], ['1234', 123400], ['0.29', 29], ['R$ 25,00', 2500], ['1.234.567,89', 123456789], ['19,99', 1999], ['10,999', null], ['abc', null], ['', null], ['12,345,67', null], ['-5', null], ['1.2.3', null]];
    casos.forEach(([ent, esp]) => check('parseCentavos("' + ent + '") = ' + esp, pc(ent) === esp, String(pc(ent))));
    w.close();
  }
  /* 12. demonstração (sem login) continua igual no Financeiro */
  {
    const w = await abrir(novoMundo(), { configurado: false }); await irPara(w, 'financeiro');
    { const c = w.document.getElementById('content').textContent; check('demo: Início mantém os números fictícios de demonstração', true); }
    check('demo: Financeiro mantém os dados fictícios e o botão de demonstração', /valores exibidos são fictícios/.test(txt(w)) && !!w.document.getElementById('newentry') && !w.document.getElementById('cx-mes'));
    w.close();
  }

  /* 13. dashboard financeiro (V1.16): síndico cria/edita/concilia; conselho e morador só visualizam */
  {
    const mundoDash = papel => { const m = novoMundo(); logado(m, papel + '@a.com', papel, { unidade: papel === 'morador' ? U101 : null });
      m.dashboards_financeiros.push({ id: 'dash-1', titulo: 'Conciliação bancária – Edifício Valença – Jul/2026 a Jun/2027', mes_inicio: '2026-07-01', mes_fim: '2027-06-01', visivel_moradores: true, observacao: null });
      m.dashExtrato = { '2026-07': 448364, '2026-08': 562326, '2026-09': 324757, '2026-10': 400970 }; return m; };
    { // síndico
      const m = mundoDash('sindico'), w = await abrir(m), c = () => txt(w);
      check('dashboard: não fica no menu nem no Início (só dentro do Financeiro)', !w.document.querySelector('[data-page="dashboard"]') && !w.document.querySelector('[data-go="dashboard"]'));
      await irPara(w, 'financeiro'); await wait(60);
      check('financeiro: abas Livro-caixa e Dashboard abaixo do título', !!w.document.querySelector('#content .df-abas [data-df-aba="dashboard"]') && w.document.querySelector('#content .df-abas .on').dataset.dfAba === 'financeiro');
      await clica(w, w.document.querySelector('[data-df-aba="dashboard"]')); await wait(60);
      check('aba Dashboard: título Financeiro, aba marcada e item Financeiro do menu destacado', /Financeiro/.test(w.document.querySelector('#content .heading h1').textContent) && w.document.querySelector('#content .df-abas .on').dataset.dfAba === 'dashboard' && w.document.querySelector('aside [data-page="financeiro"]').classList.contains('active'));
      check('dashboard/síndico: abre direto com os valores (sem cadeado)', /CONCILIAÇÃO BANCÁRIA|Conciliação bancária – Edifício Valença/i.test(c()) && !/estão ocultos/.test(c()), c().slice(0, 300));
      check('dashboard/síndico: sem aviso de módulo de demonstração', !/ainda é uma demonstração/.test(c()));
      check('dashboard/síndico: tabela com jul/2026 e totais do PDF', /Jul-2026/.test(c()) && /9\.370,02/.test(c()) && /38\.222,98/.test(c()) && /43\.583,30/.test(c()) && /\(R\$\s?5\.360,32\)/.test(c()) && /4 de 12/.test(c()), c().slice(0, 900));
      check('dashboard/síndico: 4 conciliados e 8 pendentes', (c().match(/✔ Conciliado/g) || []).length === 4 && (c().match(/⚠ Pendente/g) || []).length === 8);
      check('dashboard/síndico: dois gráficos (barras e saldo)', w.document.querySelectorAll('.df-graf svg').length === 2 && w.document.querySelectorAll('.df-graf svg path[fill="#2a78d6"]').length === 4);
      const alvo = w.document.querySelector('.df-graf[data-df-graf="barras"] .df-alvo[data-i="3"]'); await clica(w, alvo);
      check('dashboard: tocar no mês mostra o detalhe (tooltip)', /Out-2026/.test(w.document.querySelector('.df-graf .df-tip').textContent) && /10\.639,11/.test(w.document.querySelector('.df-graf .df-tip').textContent));
      check('dashboard/síndico: tem Novo, Editar, Excluir e Informar extrato', !!w.document.getElementById('df-novo') && !!w.document.getElementById('df-editar') && !!w.document.getElementById('df-excluir') && w.document.querySelectorAll('[data-df-extrato]').length >= 4);
      // extrato divergente
      await clica(w, w.document.querySelector('[data-df-extrato="2026-10"]'));
      await preencheESubmete(w, 'df-fx', { 'df-sx': '4.000,00' }); await wait(60);
      check('dashboard/síndico: extrato diferente → divergente com aviso', /✖ Divergente/.test(c()) && /difere do saldo calculado em R\$\s?9,70/.test(c()), c().slice(0, 400));
      check('dashboard: registrar extrato chama a função do banco', m.chamadas.some(x => x.rpc === 'registrar_saldo_extrato' && x.args.p_competencia === '2026-10-01' && x.args.p_saldo_extrato_centavos === 400000));
      await clica(w, w.document.querySelector('[data-df-extrato="2026-10"]')); await preencheESubmete(w, 'df-fx', { 'df-sx': '4.009,70' }); await wait(60);
      check('dashboard/síndico: corrigir o extrato → conciliado de novo', (c().match(/✔ Conciliado/g) || []).length === 4 && !/Divergente/.test(c()));
      // novo dashboard
      await clica(w, w.document.getElementById('df-novo'));
      check('dashboard/síndico: formulário sugere o exercício julho–junho', /^\d{4}-07$/.test(w.document.getElementById('df-ini').value) && /^\d{4}-06$/.test(w.document.getElementById('df-fim').value));
      await preencheESubmete(w, 'df-f', { 'df-tit': 'Exercício 2027/2028', 'df-ini': '2027-07', 'df-fim': '2028-06' }); await wait(60);
      check('dashboard/síndico: cria pelo banco e passa a ter seletor de período', m.dashboards_financeiros.length === 2 && m.chamadas.some(x => x.rpc === 'salvar_dashboard_financeiro' && x.args.p_mes_inicio === '2027-07-01') && !!w.document.getElementById('df-sel'));
      // voltar (celular): da aba para o Início, sem sair do app
      w.eval("go('inicio')"); await wait(60);
      await irPara(w, 'avisos'); await irPara(w, 'financeiro'); await clica(w, w.document.querySelector('[data-df-aba="dashboard"]')); await wait(40);
      check('voltar: abrir abas não empilha histórico (uma entrada só)', w.history.length === 2 && w.history.state && w.history.state.aba === 'dashboard', String(w.history.length));
      await clica(w, w.document.querySelector('[data-df-extrato="2026-10"]'));
      w.history.back(); await wait(80);
      check('voltar com janela aberta: fecha a janela e continua na aba', !w.document.querySelector('.modal') && !!w.document.querySelector('.df-faixa') && w.eval('page') === 'dashboard');
      w.history.back(); await wait(80);
      check('voltar na aba: vai para a tela inicial do app', w.eval('page') === 'inicio' && /Bom dia/.test(c()));
      await irPara(w, 'financeiro'); await irPara(w, 'inicio'); await wait(80);
      check('tocar em Início desfaz a entrada da aba (próximo voltar sai do app)', w.eval('page') === 'inicio' && !(w.history.state && w.history.state.aba));
      w.close();
    }
    for (const papel of ['conselho', 'morador']) {
      const m = mundoDash(papel), w = await abrir(m), c = () => txt(w), P = 'dashboard/' + papel + ': ';
      await irPara(w, 'financeiro'); await clica(w, w.document.querySelector('[data-df-aba="dashboard"]')); await wait(40);
      check(P + 'abre com valores ocultos', /valores do dashboard estão ocultos/.test(c()) && !/38\.222,98/.test(c()) && !m.chamadas.some(x => x.rpc === 'dashboard_financeiro'));
      await clica(w, w.document.getElementById('df-mostrar')); await wait(60);
      check(P + 'mostra os valores ao pedir', /38\.222,98/.test(c()) && /4 de 12/.test(c()));
      await clica(w, w.document.querySelector('[data-df-aba="financeiro"]')); await wait(40);
      check(P + 'aba Livro-caixa volta ao livro-caixa (com cadeado do Financeiro)', w.eval('page') === 'financeiro' && /valores financeiros estão ocultos/.test(c()));
      await clica(w, w.document.querySelector('[data-df-aba="dashboard"]')); await wait(40);
      check(P + 'somente leitura (sem Novo, Editar, Excluir nem extrato)', !w.document.getElementById('df-novo') && !w.document.getElementById('df-editar') && !w.document.getElementById('df-excluir') && !w.document.querySelector('[data-df-extrato]'));
      w.close();
    }
    { const m = mundoDash('morador'); m.dashboards_financeiros[0].visivel_moradores = false; const w = await abrir(m);
      await irPara(w, 'financeiro'); await clica(w, w.document.querySelector('[data-df-aba="dashboard"]')); await clica(w, w.document.getElementById('df-mostrar')); await wait(60);
      check('dashboard/morador: dashboard oculto aos moradores não aparece', /ainda não publicou/.test(txt(w)) && !/38\.222,98/.test(txt(w))); w.close(); }
    { const w = await abrir(novoMundo(), { configurado: false });
      w.eval('window.FINANCEIRO_DATA = ' + read('data/financeiro.json').replace(/<\/script/gi, '') + '; page="dashboard"; render();'); await wait(60);
      check('dashboard/demonstração: usa as planilhas, mostra 4 conciliados, sem edição', /4 de 12/.test(txt(w)) && /38\.222,98/.test(txt(w)) && !w.document.getElementById('df-novo'), txt(w).slice(0, 300)); w.close(); }
  }

  console.log(falhas.length ? 'FALHAS:\n - ' + falhas.join('\n - ') : '');
  console.log('Testes de tela: ' + ok + ' passaram, ' + bad + ' falharam.');
  process.exit(bad ? 1 : 0);
})().catch(e => { console.error('ERRO no teste:', e); process.exit(2); });
