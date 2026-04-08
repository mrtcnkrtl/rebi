-- Data-driven active rules for ingredient-level planning (no product recommendations).
-- The backend reads these rules and generates `active_plan`.

create extension if not exists pgcrypto;

create table if not exists public.active_rules (
  id uuid primary key default gen_random_uuid(),
  active_key text not null,         -- e.g. "salicylic_acid"
  family text,                      -- e.g. "bha"
  role text,                        -- e.g. "comedones_sebum"
  priority int not null default 100, -- lower = earlier / more important
  enabled boolean not null default true,
  rule jsonb not null,              -- rule payload (conditions, ranges, copy)
  created_at timestamptz not null default now(),
  unique (active_key)
);

create index if not exists active_rules_enabled_priority_idx
  on public.active_rules (enabled, priority, active_key);

-- Optional: allow read for all clients; writes should be server-side only.
alter table public.active_rules enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='active_rules' and policyname='active_rules_public_read'
  ) then
    create policy active_rules_public_read on public.active_rules
      for select using (true);
  end if;
end $$;

-- Seed rules (minimal schema; backend can evolve without migration).
-- Keys the backend uses in `ctx`:
--   concern, skin_type, risk_level, severity_level, strength_stage, age_group, is_pregnant,
--   tol_bha, tol_aha, tol_retinol, tol_benzoyl, tol_azelaic, tol_vitamin_c, tol_pigment, tol_niacinamide

insert into public.active_rules (active_key, family, role, priority, enabled, rule)
values
(
  'sunscreen',
  null,
  'protection',
  1,
  true,
  jsonb_build_object(
    'recommended', true,
    'when', 'morning',
    'concentration', null,
    'constraints', jsonb_build_object('avoid_in_pregnancy', false, 'avoid_if_sensitive', false),
    'copy', jsonb_build_object(
      'why_tr', 'UV; leke, bariyer ve yaşlanmada en büyük dış tetikleyici.',
      'why_en', 'UV is the biggest external driver for pigmentation, barrier stress, and photoaging.',
      'notes_tr', 'Geniş spektrum SPF: her sabah. Ürün değil, prensip.',
      'notes_en', 'Broad-spectrum SPF every morning. Principle, not a product suggestion.'
    )
  )
),
(
  'ceramides_cholesterol_fatty_acids',
  null,
  'barrier_repair',
  20,
  true,
  jsonb_build_object(
    'recommended_if_any', jsonb_build_array(
      jsonb_build_object('concern_in', jsonb_build_array('dryness','sensitivity','general')),
      jsonb_build_object('skin_type_in', jsonb_build_array('dry','sensitive'))
    ),
    'when', 'evening',
    'concentration', jsonb_build_object('note', 'Etiket % şart değil; hedef: bariyer lipitleri 3:1:1 mantığı'),
    'constraints', jsonb_build_object('avoid_in_pregnancy', false, 'avoid_if_sensitive', false),
    'copy', jsonb_build_object(
      'why_tr', 'Kuruluk/hassasiyette bariyeri stabilize eder; aktif toleransını iyileştirir.',
      'why_en', 'Stabilizes the barrier in dryness/sensitivity and improves overall active tolerance over time.',
      'notes_tr', 'Seramid NP/AP/EOP + kolesterol + yağ asitleri hedefi. Gece bariyer katmanı.',
      'notes_en', 'Aim for ceramides + cholesterol + fatty acids (3:1:1 logic). Use as the evening barrier layer.'
    )
  )
),
(
  'panthenol',
  null,
  'soothing_barrier',
  25,
  true,
  jsonb_build_object(
    'recommended_if_any', jsonb_build_array(
      jsonb_build_object('concern_in', jsonb_build_array('dryness','sensitivity')),
      jsonb_build_object('risk_level_in', jsonb_build_array('high','crisis'))
    ),
    'when', 'evening',
    'concentration', jsonb_build_object('default_range', '%2-5'),
    'constraints', jsonb_build_object('avoid_in_pregnancy', false, 'avoid_if_sensitive', false),
    'copy', jsonb_build_object(
      'why_tr', 'Yanma/batma veya yüksek riskte yatıştırma + bariyer desteği.',
      'why_en', 'Soothing + barrier support when irritation signals are present or risk is high.',
      'notes_tr', 'Panthenol %2-5 aralığı genelde iyi tolere edilir.',
      'notes_en', 'Panthenol 2–5% is usually well tolerated.'
    )
  )
),
(
  'niacinamide',
  'niacinamide',
  'sebum_balance_barrier',
  30,
  true,
  jsonb_build_object(
    'recommended_if_any', jsonb_build_array(
      jsonb_build_object('concern_in', jsonb_build_array('acne','oiliness','pores','pigmentation')),
      jsonb_build_object('skin_type_in', jsonb_build_array('oily','combination'))
    ),
    'when', 'morning_or_evening',
    'concentration', jsonb_build_object(
      'from_ctx_pct', 'niacinamide_start_pct',
      'min', 2,
      'max', 10,
      'spread', 3
    ),
    'constraints', jsonb_build_object('avoid_in_pregnancy', false, 'avoid_if_sensitive', false),
    'copy', jsonb_build_object(
      'why_tr', 'Sebum dengesi + bariyer desteği (özellikle yağlı/karma, gözenek ve leke ekseninde).',
      'why_en', 'Supports sebum balance and barrier function—useful in oily/combination skin, pores, and pigmentation routines.',
      'notes_tr', 'Tahriş sinyalinde aralığın alt ucunda kal.',
      'notes_en', 'If irritation appears, stay in the lower end of the range.'
    )
  )
),
(
  'salicylic_acid',
  'bha',
  'comedones_sebum',
  40,
  true,
  jsonb_build_object(
    'recommended_if', jsonb_build_object('concern_in', jsonb_build_array('acne','oiliness','pores')),
    'when', 'evening',
    'concentration', jsonb_build_object(
      'default_range', '%0.5-2',
      'overrides', jsonb_build_array(
        jsonb_build_object('if', jsonb_build_object('risk_level_in', jsonb_build_array('high','crisis')), 'range', '%0.5-1'),
        jsonb_build_object('if', jsonb_build_object('tol_bha_in', jsonb_build_array('never','mild')), 'range', '%0.5-1')
      )
    ),
    'frequency', jsonb_build_object(
      'per_week', '2-4',
      'overrides', jsonb_build_array(
        jsonb_build_object('if', jsonb_build_object('risk_level_in', jsonb_build_array('high','crisis')), 'per_week', '1-2'),
        jsonb_build_object('if', jsonb_build_object('tol_bha_in', jsonb_build_array('never','mild')), 'per_week', '1-2')
      )
    ),
    'constraints', jsonb_build_object('avoid_in_pregnancy', false, 'avoid_if_sensitive', true),
    'copy', jsonb_build_object(
      'why_tr', 'Siyah nokta/komedon tıkacını çözmede en direkt aktiflerden.',
      'why_en', 'One of the most direct actives for blackheads/clogged pores and sebum buildup.',
      'notes_tr', 'Aynı seansta çoklu güçlü asit/retinoid biriktirme.',
      'notes_en', 'Avoid stacking multiple strong acids/retinoids in the same session.'
    )
  )
),
(
  'benzoyl_peroxide',
  'benzoyl',
  'antibacterial_inflammatory_acne',
  50,
  true,
  jsonb_build_object(
    'recommended_if', jsonb_build_object('concern_in', jsonb_build_array('acne'), 'severity_in', jsonb_build_array('orta','şiddetli')),
    'when', 'evening',
    'concentration', jsonb_build_object(
      'default_range', '%2.5-5',
      'overrides', jsonb_build_array(
        jsonb_build_object('if', jsonb_build_object('risk_level_in', jsonb_build_array('high','crisis')), 'range', '%2.5'),
        jsonb_build_object('if', jsonb_build_object('tol_benzoyl_in', jsonb_build_array('never','mild')), 'range', '%2.5')
      )
    ),
    'frequency', jsonb_build_object('per_week', '1-3'),
    'constraints', jsonb_build_object('avoid_in_pregnancy', false, 'avoid_if_sensitive', true),
    'copy', jsonb_build_object(
      'why_tr', 'İnflamatuvar aknede hızlı etkili; tolerans ve riskte düşük yüzde.',
      'why_en', 'Fast, effective for inflammatory acne; keep % conservative under risk/tolerance limits.',
      'notes_tr', 'Kısa temas (5-10 dk) toleransı artırabilir.',
      'notes_en', 'Short-contact (5–10 min) can improve tolerability for some skin types.'
    )
  )
),
(
  'zinc_pca',
  'zinc_pca',
  'sebum_balance_support',
  55,
  true,
  jsonb_build_object(
    'recommended_if_any', jsonb_build_array(
      jsonb_build_object('concern_in', jsonb_build_array('acne','oiliness','pores')),
      jsonb_build_object('skin_type_in', jsonb_build_array('oily','combination'))
    ),
    'when', 'morning_or_evening',
    'concentration', jsonb_build_object(
      'default_range', '%0.1-1',
      'overrides', jsonb_build_array(
        jsonb_build_object('if', jsonb_build_object('tol_zinc_pca_in', jsonb_build_array('never','mild')), 'range', '%0.1-0.5'),
        jsonb_build_object('if', jsonb_build_object('risk_level_in', jsonb_build_array('high','crisis')), 'range', '%0.1-0.5')
      )
    ),
    'frequency', jsonb_build_object('per_week', '3-7'),
    'constraints', jsonb_build_object('avoid_in_pregnancy', false, 'avoid_if_sensitive', false),
    'copy', jsonb_build_object(
      'why_tr', 'Sebum dengesine yardımcı; akne/gözenek ekseninde destekleyici.',
      'why_en', 'Supportive for sebum balance; helpful in acne/pores routines.',
      'notes_tr', 'Tek başına “tedavi” değil; BHA/azelaik gibi ana aktiflerin yanında destek olarak düşün.',
      'notes_en', 'Not a stand-alone “treatment”; think of it as support alongside core actives like BHA/azelaic.'
    )
  )
),
(
  'sulfur',
  'sulfur',
  'acne_oil_support',
  58,
  true,
  jsonb_build_object(
    'recommended_if', jsonb_build_object('concern_in', jsonb_build_array('acne','oiliness','pores')),
    'when', 'evening',
    'concentration', jsonb_build_object(
      'default_range', '%2-10',
      'overrides', jsonb_build_array(
        jsonb_build_object('if', jsonb_build_object('tol_sulfur_in', jsonb_build_array('never','mild')), 'range', '%2-5'),
        jsonb_build_object('if', jsonb_build_object('risk_level_in', jsonb_build_array('high','crisis')), 'range', '%2-5')
      )
    ),
    'frequency', jsonb_build_object(
      'per_week', '1-3',
      'overrides', jsonb_build_array(
        jsonb_build_object('if', jsonb_build_object('risk_level_in', jsonb_build_array('high','crisis')), 'per_week', '1'),
        jsonb_build_object('if', jsonb_build_object('tol_sulfur_in', jsonb_build_array('never','mild')), 'per_week', '1')
      )
    ),
    'constraints', jsonb_build_object('avoid_in_pregnancy', false, 'avoid_if_sensitive', true),
    'copy', jsonb_build_object(
      'why_tr', 'Yağlılık/komedon eğiliminde destekleyici; bazı ciltlerde iyi tolere edilir.',
      'why_en', 'Supportive for oiliness/comedonal tendency and can be well tolerated in some skin types.',
      'notes_tr', 'Kurutma yaparsa sıklığı düşür ve bariyer desteğini artır.',
      'notes_en', 'If drying occurs, reduce frequency and increase barrier support.'
    )
  )
),
(
  'azelaic_acid',
  'azelaic',
  'acne_pigment_redness',
  60,
  true,
  jsonb_build_object(
    'recommended_if', jsonb_build_object('concern_in', jsonb_build_array('acne','pigmentation','sensitivity')),
    'when', 'evening',
    'concentration', jsonb_build_object(
      'default_range', '%10-15',
      'overrides', jsonb_build_array(
        jsonb_build_object('if', jsonb_build_object('severity_in', jsonb_build_array('şiddetli'), 'risk_level_in', jsonb_build_array('normal','moderate'), 'tol_azelaic_in', jsonb_build_array('good')), 'range', '%10-20')
      )
    ),
    'frequency', jsonb_build_object('per_week', '2-4'),
    'constraints', jsonb_build_object('avoid_in_pregnancy', false, 'avoid_if_sensitive', false),
    'copy', jsonb_build_object(
      'why_tr', 'Akne + leke + kızarıklık ekseninde dengeli; çoğu ciltte toleransı iyi.',
      'why_en', 'Balanced across acne + pigmentation + redness, and generally well tolerated.',
      'notes_tr', 'Çoğu ciltte iyi tolere olur; yavaş artır.',
      'notes_en', 'Often well tolerated; ramp up gradually.'
    )
  )
),
(
  'adapalene',
  'adapalene',
  'comedonal_acne_turnover',
  65,
  true,
  jsonb_build_object(
    'recommended_if', jsonb_build_object('concern_in', jsonb_build_array('acne','pores')),
    'when', 'evening',
    'concentration', jsonb_build_object(
      'default_range', '%0.1',
      'overrides', jsonb_build_array(
        jsonb_build_object('if', jsonb_build_object('risk_level_in', jsonb_build_array('high','crisis')), 'range', '%0.1'),
        jsonb_build_object('if', jsonb_build_object('tol_adapalene_in', jsonb_build_array('never','mild')), 'range', '%0.1')
      )
    ),
    'frequency', jsonb_build_object(
      'per_week', '1-3',
      'overrides', jsonb_build_array(
        jsonb_build_object('if', jsonb_build_object('risk_level_in', jsonb_build_array('high','crisis')), 'per_week', '1'),
        jsonb_build_object('if', jsonb_build_object('tol_adapalene_in', jsonb_build_array('never','mild')), 'per_week', '1')
      )
    ),
    'constraints', jsonb_build_object(
      'avoid_in_pregnancy', true,
      'avoid_if_sensitive', true,
      'avoid_same_session_with', jsonb_build_array('glycolic_or_lactic_acid', 'salicylic_acid')
    ),
    'copy', jsonb_build_object(
      'why_tr', 'Komedon/siyah nokta ve aknede hücre döngüsünü düzenleyen retinoid sınıfı.',
      'why_en', 'A retinoid-class active that normalizes cell turnover in comedonal acne/blackheads.',
      'notes_tr', 'Aynı gece AHA/BHA ile bindirme. Hamilelikte kaçın.',
      'notes_en', 'Do not stack with AHA/BHA the same night. Avoid in pregnancy.'
    )
  )
),
(
  'glycolic_or_lactic_acid',
  'aha',
  'texture_turnover_pigment_support',
  70,
  true,
  jsonb_build_object(
    'recommended_if', jsonb_build_object('concern_in', jsonb_build_array('pigmentation','aging'), 'skin_type_not_in', jsonb_build_array('sensitive')),
    'when', 'evening',
    'concentration', jsonb_build_object(
      'default_range', '%5-10',
      'overrides', jsonb_build_array(
        jsonb_build_object('if', jsonb_build_object('risk_level_in', jsonb_build_array('high','crisis')), 'range', '%5'),
        jsonb_build_object('if', jsonb_build_object('tol_aha_in', jsonb_build_array('never','mild')), 'range', '%5')
      )
    ),
    'frequency', jsonb_build_object(
      'per_week', '1-3',
      'overrides', jsonb_build_array(
        jsonb_build_object('if', jsonb_build_object('risk_level_in', jsonb_build_array('high','crisis')), 'per_week', '1'),
        jsonb_build_object('if', jsonb_build_object('tol_aha_in', jsonb_build_array('never','mild')), 'per_week', '1')
      )
    ),
    'constraints', jsonb_build_object('avoid_in_pregnancy', false, 'avoid_if_sensitive', true),
    'copy', jsonb_build_object(
      'why_tr', 'Doku/ton desteği için yüzey yenileme; yüksek riskte düşük yüzde.',
      'why_en', 'Texture/tone support via surface renewal; lower % under higher risk.',
      'notes_tr', 'Aynı gece retinol ile bindirme.',
      'notes_en', 'Do not stack with retinol the same night.'
    )
  )
),
(
  'tranexamic_acid',
  'pigment',
  'pigment_modulation',
  80,
  true,
  jsonb_build_object(
    'recommended_if', jsonb_build_object('concern_in', jsonb_build_array('pigmentation')),
    'when', 'evening',
    'concentration', jsonb_build_object('default_range', '%2-5'),
    'frequency', jsonb_build_object('per_week', '3-7'),
    'constraints', jsonb_build_object('avoid_in_pregnancy', false, 'avoid_if_sensitive', false),
    'copy', jsonb_build_object(
      'why_tr', 'Leke yolaklarında destek; güçlü asit/retinoid kadar irrite etmeyebilir.',
      'why_en', 'Supports pigmentation pathways and can be less irritating than strong acids/retinoids.',
      'notes_tr', 'Niasinamid ile aynı adımda veya ayrı katmanda olabilir.',
      'notes_en', 'Can be used with niacinamide in the same step or layered separately.'
    )
  )
),
(
  'alpha_arbutin',
  'pigment',
  'tyrosinase_support',
  85,
  true,
  jsonb_build_object(
    'recommended_if', jsonb_build_object('concern_in', jsonb_build_array('pigmentation')),
    'when', 'evening',
    'concentration', jsonb_build_object('default_range', '%2-3'),
    'frequency', jsonb_build_object('per_week', '3-7'),
    'constraints', jsonb_build_object('avoid_in_pregnancy', false, 'avoid_if_sensitive', false),
    'copy', jsonb_build_object(
      'why_tr', 'Ton eşitsizliği/lekede destekleyici; toleransa göre sıklık ayarlanır.',
      'why_en', 'Supportive for uneven tone/pigmentation; frequency can be adjusted by tolerability.',
      'notes_tr', 'C vitamini genelde sabah; arbutin akşam ayrımı netlik sağlar.',
      'notes_en', 'Vitamin C is usually morning; keeping arbutin at night keeps the routine clearer.'
    )
  )
),
(
  'urea',
  'urea',
  'hydration_keratolytic_barrier',
  86,
  true,
  jsonb_build_object(
    'recommended_if_any', jsonb_build_array(
      jsonb_build_object('concern_in', jsonb_build_array('dryness','general')),
      jsonb_build_object('skin_type_in', jsonb_build_array('dry'))
    ),
    'when', 'evening',
    'concentration', jsonb_build_object(
      'default_range', '%2-10',
      'overrides', jsonb_build_array(
        jsonb_build_object('if', jsonb_build_object('risk_level_in', jsonb_build_array('high','crisis')), 'range', '%2-5'),
        jsonb_build_object('if', jsonb_build_object('tol_urea_in', jsonb_build_array('never','mild')), 'range', '%2-5')
      )
    ),
    'frequency', jsonb_build_object('per_week', '3-7'),
    'constraints', jsonb_build_object('avoid_in_pregnancy', false, 'avoid_if_sensitive', false),
    'copy', jsonb_build_object(
      'why_tr', 'Nem tutma + bariyer desteği; bazı konsantrasyonlarda nazik keratolitik etki.',
      'why_en', 'Humectant hydration + barrier support, with gentle keratolytic effect at higher concentrations.',
      'notes_tr', 'Yüksek riskte daha düşük aralık. Batma olursa aralığın alt ucunda kal.',
      'notes_en', 'Use the lower end under higher risk. If stinging appears, stay in the lower range.'
    )
  )
),
(
  'retinol',
  'retinol',
  'collagen_texture_pigment',
  88,
  true,
  jsonb_build_object(
    'recommended_if', jsonb_build_object('concern_in', jsonb_build_array('pigmentation','aging')),
    'when', 'evening',
    'concentration', jsonb_build_object(
      'default_range', '%0.3-0.5',
      'overrides', jsonb_build_array(
        jsonb_build_object('if', jsonb_build_object('strength_stage_in', jsonb_build_array('starter')), 'range', '%0.1-0.3'),
        jsonb_build_object('if', jsonb_build_object('tol_retinol_in', jsonb_build_array('never','mild')), 'range', '%0.1-0.3'),
        jsonb_build_object('if', jsonb_build_object('risk_level_in', jsonb_build_array('high','crisis')), 'range', '%0.1-0.3'),
        jsonb_build_object('if', jsonb_build_object('strength_stage_in', jsonb_build_array('strong')), 'range', '%0.5-1')
      )
    ),
    'frequency', jsonb_build_object(
      'per_week', '1-3',
      'overrides', jsonb_build_array(
        jsonb_build_object('if', jsonb_build_object('strength_stage_in', jsonb_build_array('starter')), 'per_week', '1'),
        jsonb_build_object('if', jsonb_build_object('tol_retinol_in', jsonb_build_array('never','mild')), 'per_week', '1'),
        jsonb_build_object('if', jsonb_build_object('risk_level_in', jsonb_build_array('high','crisis')), 'per_week', '1'),
        jsonb_build_object('if', jsonb_build_object('strength_stage_in', jsonb_build_array('strong')), 'per_week', '2-3')
      )
    ),
    'constraints', jsonb_build_object(
      'avoid_in_pregnancy', true,
      'avoid_if_sensitive', true,
      'avoid_same_session_with', jsonb_build_array('glycolic_or_lactic_acid', 'salicylic_acid')
    ),
    'copy', jsonb_build_object(
      'why_tr', 'Kırışıklık/tekstür ve bazı leke tiplerinde güçlü gece aktifi; risk/toleransta düşük %.',
      'why_en', 'A strong night active for texture/collagen support and some pigmentation patterns; keep % lower under risk/tolerance limits.',
      'notes_tr', 'Aynı gece AHA/BHA gibi güçlü asitlerle bindirme.',
      'notes_en', 'Do not stack with strong acids (AHA/BHA) the same night.'
    )
  )
),
(
  'vitamin_c_derivatives',
  'vitamin_c_derivatives',
  'antioxidant_pigment_support',
  89,
  true,
  jsonb_build_object(
    'recommended_if', jsonb_build_object('concern_in', jsonb_build_array('pigmentation','aging')),
    'when', 'morning',
    'concentration', jsonb_build_object(
      'default_range', '%5-10',
      'overrides', jsonb_build_array(
        jsonb_build_object('if', jsonb_build_object('skin_type_in', jsonb_build_array('sensitive')), 'range', '%3-10'),
        jsonb_build_object('if', jsonb_build_object('risk_level_in', jsonb_build_array('high','crisis')), 'range', '%3-10'),
        jsonb_build_object('if', jsonb_build_object('tol_vitamin_c_derivatives_in', jsonb_build_array('never','mild')), 'range', '%3-10')
      )
    ),
    'constraints', jsonb_build_object('avoid_in_pregnancy', false, 'avoid_if_sensitive', false),
    'copy', jsonb_build_object(
      'why_tr', 'L-AA (saf C) tolere edilemiyorsa daha nazik C türevleriyle antioksidan + ton desteği.',
      'why_en', 'If pure L-AA is not tolerated, gentler vitamin C derivatives can provide antioxidant and tone support.',
      'notes_tr', 'SAP/MAP gibi türevler genelde daha naziktir; hedef aralığı kademeli artır.',
      'notes_en', 'Derivatives like SAP/MAP are often gentler; ramp within the range.'
    )
  )
),
(
  'vitamin_c_l_ascorbic_acid',
  'vitamin_c',
  'antioxidant_pigment_support',
  90,
  true,
  jsonb_build_object(
    'recommended_if', jsonb_build_object('concern_in', jsonb_build_array('pigmentation','aging')),
    'when', 'morning',
    'concentration', jsonb_build_object(
      'default_range', '%8-15',
      'overrides', jsonb_build_array(
        jsonb_build_object('if', jsonb_build_object('risk_level_in', jsonb_build_array('high','crisis')), 'range', '%5-10'),
        jsonb_build_object('if', jsonb_build_object('skin_type_in', jsonb_build_array('sensitive')), 'range', '%5-10'),
        jsonb_build_object('if', jsonb_build_object('tol_vitamin_c_in', jsonb_build_array('never','mild')), 'range', '%5-10')
      )
    ),
    'constraints', jsonb_build_object('avoid_in_pregnancy', false, 'avoid_if_sensitive', true),
    'copy', jsonb_build_object(
      'why_tr', 'Antioksidan koruma + leke/ton desteği; hassasiyette düşük yüzde.',
      'why_en', 'Antioxidant protection + pigmentation/tone support; lower % in sensitivity phases.',
      'notes_tr', 'Hassasiyet olursa alt aralığa in.',
      'notes_en', 'If sensitivity appears, stay at the lower end.'
    )
  )
)
on conflict (active_key) do update
  set family = excluded.family,
      role = excluded.role,
      priority = excluded.priority,
      enabled = excluded.enabled,
      rule = excluded.rule;

