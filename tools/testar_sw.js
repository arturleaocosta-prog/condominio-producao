/* Teste da lógica do service worker (sw.js) com um navegador falso: rede primeiro, offline, isolamento e instalação sem cache HTTP. Uso: node tools/testar_sw.js */
const fs = require('fs'), vm = require('vm'), path = require('path');
let ok = 0, bad = 0; const falhas = [];
const check = (n, c, i) => { if (c) ok++; else { bad++; falhas.push(n + (i ? ' → ' + i : '')); } };
const flush = () => new Promise(r => setTimeout(r, 10));
function carrega({ rede = true, versaoRede = 'NOVO', cacheInicial = {} } = {}) {
  const handlers = {}, caches = new Map(); const chamadas = [];
  const abre = nome => { if (!caches.has(nome)) caches.set(nome, new Map()); const m = caches.get(nome);
    return { addAll: async reqs => { chamadas.push({ addAll: reqs.map(r => ({ url: r.url, cache: r.cache })) }); reqs.forEach(r => m.set(r.url, { corpo: 'INSTALADO:' + r.url })); },
             put: async (req, res) => { m.set(req.url || req, res); }, match: async req => m.get(req.url || req) }; };
  Object.entries(cacheInicial).forEach(([nome, mapa]) => { const c = abre(nome); Object.entries(mapa).forEach(([u, corpo]) => c.put(u, { corpo })); });
  const fakeCaches = { open: async n => abre(n), keys: async () => [...caches.keys()], delete: async n => caches.delete(n),
    match: async req => { const chave = typeof req === 'string' ? new URL(req, 'https://app.test/Sistema/').href : req.url; for (const m of caches.values()) { const h = m.get(chave); if (h) return h; } } };
  const sandbox = {
    self: { addEventListener: (t, f) => { handlers[t] = f; }, skipWaiting: () => { chamadas.push('skipWaiting'); }, clients: { claim: () => { chamadas.push('claim'); } }, location: { origin: 'https://app.test' } },
    caches: fakeCaches, URL, Promise, setTimeout,
    Request: class { constructor(url, init) { this.url = new URL(url, 'https://app.test/Sistema/').href; this.cache = init && init.cache; } },
    fetch: async (req, init) => { chamadas.push({ fetch: req.url, cache: init && init.cache }); if (!rede) throw new Error('offline'); return { ok: true, clone() { return this; }, corpo: versaoRede + ':' + req.url }; }
  };
  vm.createContext(sandbox); vm.runInContext(fs.readFileSync(path.join(__dirname, '..', 'sw.js'), 'utf8'), sandbox);
  const dispara = async (tipo, ev) => { await handlers[tipo](ev); await flush(); };
  const get = (url, extra = {}) => { let resp; const ev = Object.assign({ request: { url, method: 'GET', mode: 'navigate' }, respondWith: p => { resp = p; }, waitUntil: p => { resp = p; } }, extra); handlers.fetch(ev); return { ev, resp: () => resp }; };
  return { handlers, caches, chamadas, dispara, get, sandbox };
}
(async () => {
  { const s = carrega(); const e = { waitUntil: p => { s.p = p; } }; s.handlers.install(e); await s.p; await flush();
    const add = s.chamadas.find(c => c.addAll);
    check('instalação: todos os arquivos do app são pré-carregados', add && add.addAll.length >= 10);
    check('instalação ignora o cache HTTP (cache: reload) em TODOS os arquivos', add && add.addAll.every(a => a.cache === 'reload'));
    check('instalação ativa a nova versão sem esperar (skipWaiting)', s.chamadas.includes('skipWaiting')); }
  { const s = carrega({ cacheInicial: { 'condominio-shell-v1-8-1': { 'x': 'velho' }, 'condominio-shell-v1-12-1': { 'y': 'atual' } } });
    const e = { waitUntil: p => { s.p = p; } }; s.handlers.activate(e); await s.p; await flush();
    check('ativação apaga os caches de versões antigas e mantém o atual', !s.caches.has('condominio-shell-v1-8-1') && s.caches.has('condominio-shell-v1-12-1'));
    check('ativação assume as abas abertas (claim)', s.chamadas.includes('claim')); }
  { // rede primeiro: com cache VELHO e rede disponível, entrega a versão NOVA e atualiza o cache
    const s = carrega({ cacheInicial: { 'condominio-shell-v1-12-1': { 'https://app.test/Sistema/index.html': 'VELHO:index' } } });
    const g = s.get('https://app.test/Sistema/index.html'); const r = await g.resp(); await flush();
    check('rede disponível: entrega a versão NOVA mesmo com versão velha no cache', r.corpo.startsWith('NOVO:'), r.corpo);
    check('a busca na rede revalida (cache: no-cache)', s.chamadas.some(c => c.fetch && c.cache === 'no-cache'));
    check('o cache é atualizado com a versão nova', s.caches.get('condominio-shell-v1-12-1').get('https://app.test/Sistema/index.html').corpo.startsWith('NOVO:')); }
  { // offline
    const s = carrega({ rede: false, cacheInicial: { 'condominio-shell-v1-12-1': { 'https://app.test/Sistema/auth.js': 'CACHE:auth', 'https://app.test/Sistema/index.html': 'CACHE:index' } } });
    const a = await s.get('https://app.test/Sistema/auth.js').resp(); check('sem rede: serve o arquivo do cache', a.corpo === 'CACHE:auth');
    const n = await s.get('https://app.test/Sistema/qualquer-rota').resp(); check('sem rede e rota desconhecida: cai no index.html', n.corpo === 'CACHE:index'); }
  { // o que NUNCA passa pelo service worker
    const s = carrega();
    const casos = [['https://kvqi.supabase.co/rest/v1/lancamentos', {}, 'Supabase (outro domínio)'], ['https://app.test/Sistema/data/financeiro.js', {}, 'dados financeiros (/data/)'],
                   ['https://app.test/Sistema/index.html', { request: { url: 'https://app.test/Sistema/index.html', method: 'POST' } }, 'gravações (POST)']];
    for (const [u, extra, nome] of casos) { const g = s.get(u, extra); check(nome + ': o service worker não intercepta', g.resp() === undefined); } }
  console.log(falhas.length ? 'FALHAS:\n - ' + falhas.join('\n - ') : '');
  console.log('Testes do service worker: ' + ok + ' passaram, ' + bad + ' falharam.'); process.exit(bad ? 1 : 0);
})().catch(e => { console.error('ERRO:', e); process.exit(2); });
