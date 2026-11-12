// Supabase Edge Function — scaffold seguro da integração CAIXA.
// NÃO registra boletos ainda: a operação real depende do manual e das credenciais
// específicas do convênio, além da homologação. Não remover o bloqueio sem testes.
import { createClient } from 'npm:@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': Deno.env.get('APP_ORIGIN') ?? '',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, idempotency-key',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Content-Type': 'application/json; charset=utf-8',
};

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders });
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json(405, { error: 'method_not_allowed' });

  const authHeader = req.headers.get('Authorization');
  if (!authHeader?.startsWith('Bearer ')) return json(401, { error: 'authentication_required' });

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !anonKey || !serviceKey) {
    return json(503, { error: 'server_not_configured', message: 'Configuração interna incompleta.' });
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData.user) return json(401, { error: 'invalid_session' });

  const adminClient = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: profile, error: profileError } = await adminClient
    .from('perfis')
    .select('user_id, condominio_id, papel, ativo')
    .eq('user_id', userData.user.id)
    .maybeSingle();
  if (profileError || !profile?.ativo) return json(403, { error: 'active_condominium_profile_required' });

  let body: { action?: string; cobranca_id?: string };
  try { body = await req.json(); } catch { return json(400, { error: 'invalid_json' }); }
  const action = body.action;
  if (!['status', 'emitir', 'consultar', 'cancelar'].includes(action ?? '')) {
    return json(400, { error: 'invalid_action' });
  }
  if (profile.papel !== 'sindico') return json(403, { error: 'syndic_role_required' });

  const { data: config, error: configError } = await adminClient
    .from('configuracao_cobranca_caixa')
    .select('habilitada, ambiente, modalidade, codigo_beneficiario, carteira, padrao_remessa, versao_manual, homologada_em')
    .eq('condominio_id', profile.condominio_id)
    .maybeSingle();
  if (configError) return json(500, { error: 'configuration_lookup_failed' });

  if (action === 'status') {
    const missing: string[] = [];
    if (!config?.habilitada) missing.push('habilitar integração após validação documental');
    if (!config?.codigo_beneficiario) missing.push('confirmar código do beneficiário/convênio');
    if (!config?.carteira) missing.push('confirmar carteira/modalidade');
    if (!config?.padrao_remessa) missing.push('confirmar canal técnico (WebService XML ou CNAB)');
    if (!config?.versao_manual) missing.push('registrar versão do manual fornecido pela CAIXA');
    if (!config?.homologada_em) missing.push('concluir homologação');
    return json(200, {
      provider: 'CAIXA',
      configured: Boolean(config),
      enabled: Boolean(config?.habilitada),
      environment: config?.ambiente ?? 'homologacao',
      homologated: Boolean(config?.homologada_em),
      ready_for_issuance: false,
      missing_steps: missing,
      note: 'A emissão está bloqueada nesta versão até implementar e testar o adaptador com o manual/credenciais específicos do convênio.',
    });
  }

  // Fail closed: não simular emissão, consulta, baixa ou pagamento como se fossem reais.
  // O próximo incremento implementará a chamada SOAP/XML ou CNAB conforme a CAIXA confirmar.
  return json(501, {
    error: 'bank_adapter_not_implemented',
    action,
    message: 'Operação bancária ainda não executada. Nenhum boleto foi emitido, consultado ou cancelado.',
  });
});
