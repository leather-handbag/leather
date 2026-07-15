-- Leather Algorithm Expedition: schema, taxonomy, privacy and queue foundation.
-- External credentials and source code are deliberately never stored.

create table if not exists public.mastery_model_versions (
  version integer primary key,
  name text not null,
  config jsonb not null default '{}'::jsonb,
  active boolean not null default false,
  created_at timestamptz not null default now()
);
create unique index if not exists mastery_model_one_active_idx on public.mastery_model_versions(active) where active;

insert into public.mastery_model_versions(version,name,config,active) values
(1,'Leather Atlas v1','{"weights":{"breadth":0.45,"challenge":0.25,"coverage":0.20,"stability":0.10},"tag_threshold":0.7}'::jsonb,true)
on conflict(version) do update set name=excluded.name,config=excluded.config,active=excluded.active;

create table if not exists public.training_maps (
  code text primary key,
  name text not null,
  subtitle text not null default '',
  icon text not null default '◇',
  position integer not null unique check(position between 1 and 20),
  cf_min integer,
  cf_max integer,
  atcoder_min integer,
  atcoder_max integer,
  luogu_min integer,
  luogu_max integer,
  color text not null check(color ~ '^#[0-9a-fA-F]{6}$'),
  description text not null default '',
  created_at timestamptz not null default now()
);

insert into public.training_maps(code,name,subtitle,icon,position,cf_min,cf_max,atcoder_min,atcoder_max,luogu_min,luogu_max,color,description) values
('plains','启程平原','把基础练成可靠的本能','⌁',1,0,1099,-9999,399,0,1,'#76996f','模拟、枚举与基础思维构成第一张地图。'),
('bronze','青铜海湾','学会选择正确的航线','◒',2,1100,1399,400,799,2,2,'#a8734f','二分、搜索与基础动态规划开始交汇。'),
('silver','白银山脉','让常用模型成为装备','△',3,1400,1699,800,1199,3,3,'#718596','图、树、背包与字符串是攀登工具。'),
('gold','黄金荒漠','在复杂状态中寻找方向','✦',4,1700,1999,1200,1599,4,4,'#b38a43','高级数据结构与状态设计进入主线。'),
('platinum','铂金天穹','跨越模型之间的边界','⬡',5,2000,2399,1600,1999,5,5,'#548f91','综合算法、优化与严谨建模成为常态。'),
('master','大师星域','在陌生问题里建立秩序','✧',6,2400,2799,2000,2399,6,6,'#735d91','复杂结构、数学工具与随机化共同工作。'),
('legend','传奇深渊','抵达算法版图的未知边缘','♜',7,2800,null,2400,null,7,null,'#8d4c46','跨领域综合与极限优化组成最终主线。')
on conflict(code) do update set name=excluded.name,subtitle=excluded.subtitle,icon=excluded.icon,position=excluded.position,
cf_min=excluded.cf_min,cf_max=excluded.cf_max,atcoder_min=excluded.atcoder_min,atcoder_max=excluded.atcoder_max,
luogu_min=excluded.luogu_min,luogu_max=excluded.luogu_max,color=excluded.color,description=excluded.description;

create table if not exists public.canonical_skills (
  code text primary key,
  parent_code text references public.canonical_skills(code) on delete restrict,
  name text not null,
  icon text not null default '·',
  description text not null default '',
  position integer not null default 0,
  is_leaf boolean not null default true
);
create index if not exists canonical_skills_parent_idx on public.canonical_skills(parent_code,position);

insert into public.canonical_skills(code,parent_code,name,icon,position,is_leaf) values
('fundamentals',null,'基础与实现','⌁',10,false),('simulation','fundamentals','模拟','◎',11,true),('enumeration','fundamentals','枚举','⋯',12,true),('sorting','fundamentals','排序','⇅',13,true),('prefix','fundamentals','前缀和与差分','∑',14,true),('binary_search','fundamentals','二分','◐',15,true),('two_pointers','fundamentals','双指针与滑窗','↔',16,true),('complexity','fundamentals','复杂度与优化','⌛',17,true),
('greedy_root',null,'贪心与构造','✦',20,false),('greedy','greedy_root','贪心','✦',21,true),('constructive','greedy_root','构造','⌘',22,true),
('search_root',null,'搜索','⌕',30,false),('dfs_bfs','search_root','BFS 与 DFS','⌕',31,true),('backtracking','search_root','回溯与剪枝','⌇',32,true),('meet_middle','search_root','折半搜索','⋈',33,true),('randomized','search_root','随机化','⚄',34,true),
('ds',null,'数据结构','▦',40,false),('stack_queue','ds','栈与队列','▤',41,true),('dsu','ds','并查集','⛓',42,true),('heap','ds','堆与优先队列','▲',43,true),('fenwick_segment','ds','树状数组与线段树','⌗',44,true),('sparse_table','ds','ST 表与倍增','≋',45,true),('advanced_ds','ds','高级数据结构','⬡',46,true),('persistent_dynamic','ds','可持久化与动态树','♢',47,true),
('graph',null,'图论','◇',50,false),('graph_traversal','graph','图遍历与拓扑','↝',51,true),('shortest_path','graph','最短路','⌁',52,true),('mst_scc','graph','MST 与连通分量','△',53,true),('tree','graph','树与 LCA','♧',54,true),('flow_matching','graph','网络流与匹配','⇄',55,true),('advanced_graph','graph','复杂图论','✣',56,true),
('dp',null,'动态规划','▥',60,false),('basic_dp','dp','基础 DP','▥',61,true),('knapsack','dp','背包','▣',62,true),('tree_dp','dp','树形 DP','♧',63,true),('state_digit_dp','dp','状压与数位 DP','▧',64,true),('dp_optimization','dp','DP 优化','⟐',65,true),('advanced_dp','dp','综合动态规划','⬢',66,true),
('strings',null,'字符串','≋',70,false),('string_hash','strings','哈希与 Trie','♯',71,true),('kmp_z','strings','KMP 与 Z 函数','Z',72,true),('suffix','strings','后缀结构与自动机','§',73,true),('advanced_string','strings','困难字符串','¶',74,true),
('math',null,'数学','∑',80,false),('basic_math','math','基础数学','＋',81,true),('number_theory','math','数论','ℕ',82,true),('combinatorics','math','组合计数','C',83,true),('probability','math','概率与期望','P',84,true),('linear_algebra','math','线性代数','▨',85,true),('polynomial','math','多项式与变换','ƒ',86,true),('advanced_math','math','困难数学','∞',87,true),
('geometry',null,'计算几何','△',90,false),('basic_geometry','geometry','基础几何','△',91,true),('advanced_geometry','geometry','高级几何','⬠',92,true),
('synthesis',null,'综合能力','♜',100,false),('cross_domain','synthesis','跨领域综合','♜',101,true),('proof_construction','synthesis','证明与构造','∵',102,true),('extreme_optimization','synthesis','极限优化','⚡',103,true)
on conflict(code) do update set parent_code=excluded.parent_code,name=excluded.name,icon=excluded.icon,position=excluded.position,is_leaf=excluded.is_leaf;

create table if not exists public.map_regions (
  code text primary key,
  map_code text not null references public.training_maps(code) on delete cascade,
  name text not null,
  icon text not null default '◇',
  description text not null default '',
  position integer not null default 0,
  is_core boolean not null default true,
  breadth_target numeric(6,2) not null check(breadth_target>0),
  upper_target numeric(6,2) not null check(upper_target>0),
  required_days integer not null default 4 check(required_days>0),
  required_weeks integer not null default 2 check(required_weeks>0),
  unique(map_code,position)
);

create table if not exists public.map_region_skills (
  region_code text not null references public.map_regions(code) on delete cascade,
  skill_code text not null references public.canonical_skills(code) on delete restrict,
  required boolean not null default true,
  primary key(region_code,skill_code)
);

insert into public.map_regions(code,map_code,name,icon,position,is_core,breadth_target,upper_target,description) values
('plains_implementation','plains','工匠营地','◎',10,true,6,2,'模拟、枚举与排序'),('plains_prefix','plains','河谷驿站','∑',20,true,6,2,'前缀和、差分与基础优化'),('plains_greedy','plains','风车田野','✦',30,true,6,2,'基础贪心与构造'),('plains_math','plains','算术石阵','＋',40,true,6,2,'基础数学与计数'),('plains_relic','plains','旧日遗迹','?',90,false,6,2,'额外的基础探索'),
('bronze_binary','bronze','潮汐灯塔','◐',10,true,7,2,'二分与双指针'),('bronze_search','bronze','迷雾群岛','⌕',20,true,7,2,'BFS、DFS 与回溯'),('bronze_structure','bronze','港口仓库','▤',30,true,7,2,'栈、队列与基础结构'),('bronze_dp','bronze','航海棋盘','▥',40,true,7,2,'基础动态规划'),('bronze_math','bronze','星盘码头','ℕ',50,true,7,2,'基础数论'),('bronze_relic','bronze','沉船遗迹','?',90,false,7,2,'额外的青铜探索'),
('silver_structure','silver','机关矿道','⛓',10,true,8,3,'并查集、堆与倍增'),('silver_graph','silver','雪线栈道','⌁',20,true,8,3,'最短路与树遍历'),('silver_dp','silver','冰晶背包','▣',30,true,8,3,'背包与常用 DP'),('silver_string','silver','回声洞穴','♯',40,true,8,3,'字符串哈希与 Trie'),('silver_relic','silver','峰顶遗迹','?',90,false,8,3,'额外的白银探索'),
('gold_structure','gold','流沙工坊','⌗',10,true,9,3,'树状数组与线段树'),('gold_graph','gold','古城路网','△',20,true,9,3,'MST、SCC 与 LCA'),('gold_dp','gold','幻象棋局','▧',30,true,9,3,'树形、状压与数位 DP'),('gold_string','gold','铭文神殿','Z',40,true,9,3,'KMP、Z 与哈希'),('gold_math','gold','日轮祭坛','C',50,true,9,3,'组合计数'),('gold_relic','gold','沙海遗迹','?',90,false,9,3,'额外的黄金探索'),
('platinum_structure','platinum','浮空铸造厂','⬡',10,true,10,3,'高级数据结构'),('platinum_graph','platinum','云端枢纽','⇄',20,true,10,3,'网络流与匹配'),('platinum_dp','platinum','天穹矩阵','⟐',30,true,10,3,'动态规划优化'),('platinum_string','platinum','星语回廊','§',40,true,10,3,'后缀结构与自动机'),('platinum_math','platinum','数论星盘','ℕ',50,true,10,3,'进阶数论与几何'),('platinum_relic','platinum','浮岛遗迹','?',90,false,10,3,'额外的铂金探索'),
('master_structure','master','时空船坞','♢',10,true,11,4,'动态树与可持久化'),('master_graph','master','引力航道','✣',20,true,11,4,'复杂图论'),('master_math','master','多项式星云','ƒ',30,true,11,4,'多项式与线性代数'),('master_probability','master','概率脉冲','P',40,true,11,4,'概率、期望与随机化'),('master_geometry','master','几何星环','⬠',50,true,11,4,'高级计算几何'),('master_relic','master','失落卫星','?',90,false,11,4,'额外的大师探索'),
('legend_cross','legend','万象裂谷','♜',10,true,12,4,'跨领域综合'),('legend_proof','legend','真理王座','∵',20,true,12,4,'证明与构造'),('legend_opt','legend','雷霆熔炉','⚡',30,true,12,4,'极限优化'),('legend_structure','legend','深渊机械城','⬢',40,true,12,4,'困难数据结构与图论'),('legend_math','legend','无穷观测站','∞',50,true,12,4,'困难数学与几何'),('legend_string','legend','静默档案馆','¶',60,true,12,4,'困难字符串与综合 DP'),('legend_relic','legend','边界之外','?',90,false,12,4,'最终遗迹')
on conflict(code) do update set map_code=excluded.map_code,name=excluded.name,icon=excluded.icon,position=excluded.position,is_core=excluded.is_core,breadth_target=excluded.breadth_target,upper_target=excluded.upper_target,description=excluded.description;

insert into public.map_region_skills(region_code,skill_code) values
('plains_implementation','simulation'),('plains_implementation','enumeration'),('plains_implementation','sorting'),('plains_prefix','prefix'),('plains_prefix','complexity'),('plains_greedy','greedy'),('plains_greedy','constructive'),('plains_math','basic_math'),('plains_relic','basic_geometry'),
('bronze_binary','binary_search'),('bronze_binary','two_pointers'),('bronze_search','dfs_bfs'),('bronze_search','backtracking'),('bronze_structure','stack_queue'),('bronze_dp','basic_dp'),('bronze_math','number_theory'),('bronze_relic','meet_middle'),
('silver_structure','dsu'),('silver_structure','heap'),('silver_structure','sparse_table'),('silver_graph','shortest_path'),('silver_graph','tree'),('silver_dp','knapsack'),('silver_dp','basic_dp'),('silver_string','string_hash'),('silver_relic','graph_traversal'),
('gold_structure','fenwick_segment'),('gold_graph','mst_scc'),('gold_graph','tree'),('gold_dp','tree_dp'),('gold_dp','state_digit_dp'),('gold_string','kmp_z'),('gold_string','string_hash'),('gold_math','combinatorics'),('gold_relic','basic_geometry'),
('platinum_structure','advanced_ds'),('platinum_graph','flow_matching'),('platinum_dp','dp_optimization'),('platinum_string','suffix'),('platinum_math','number_theory'),('platinum_math','basic_geometry'),('platinum_relic','linear_algebra'),
('master_structure','persistent_dynamic'),('master_graph','advanced_graph'),('master_math','polynomial'),('master_math','linear_algebra'),('master_probability','probability'),('master_probability','randomized'),('master_geometry','advanced_geometry'),('master_relic','advanced_dp'),
('legend_cross','cross_domain'),('legend_cross','advanced_dp'),('legend_proof','proof_construction'),('legend_proof','constructive'),('legend_opt','extreme_optimization'),('legend_structure','persistent_dynamic'),('legend_structure','advanced_graph'),('legend_math','advanced_math'),('legend_math','advanced_geometry'),('legend_string','advanced_string'),('legend_string','advanced_dp'),('legend_relic','cross_domain')
on conflict do nothing;

create table if not exists public.external_accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  platform text not null check(platform in ('codeforces','atcoder','luogu')),
  handle text not null,
  normalized_handle text not null,
  external_user_id text not null,
  avatar_url text not null default '',
  profile_url text not null default '',
  verification_method text not null default 'profile_code' check(verification_method in ('profile_code','submission_challenge')),
  verified_at timestamptz not null default now(),
  status text not null default 'active' check(status in ('active','degraded','reverify_required','disabled')),
  sync_cursor jsonb not null default '{}'::jsonb,
  last_sync_at timestamptz,
  last_success_at timestamptz,
  data_through timestamptz,
  next_sync_at timestamptz not null default now(),
  last_error_code text not null default '',
  last_error_message text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(user_id,platform),
  unique(platform,external_user_id)
);
create index if not exists external_accounts_due_idx on public.external_accounts(next_sync_at) where status in ('active','degraded');

create table if not exists public.binding_challenges (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  platform text not null check(platform in ('codeforces','atcoder','luogu')),
  requested_handle text not null,
  normalized_handle text not null,
  external_user_id text not null,
  canonical_handle text not null,
  avatar_url text not null default '',
  profile_url text not null default '',
  method text not null check(method in ('profile_code','submission_challenge')),
  code_hash text not null default '',
  payload jsonb not null default '{}'::jsonb,
  attempts integer not null default 0 check(attempts between 0 and 20),
  attempt_window_started_at timestamptz,
  window_attempts integer not null default 0 check(window_attempts between 0 and 10),
  last_attempt_at timestamptz,
  status text not null default 'pending' check(status in ('pending','verified','expired','cancelled')),
  expires_at timestamptz not null,
  verified_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists binding_challenges_user_idx on public.binding_challenges(user_id,created_at desc);

create table if not exists public.training_sync_jobs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  external_account_id uuid references public.external_accounts(id) on delete cascade,
  platform text check(platform in ('codeforces','atcoder','luogu')),
  kind text not null default 'incremental' check(kind in ('initial','incremental','cleanup','catalog','recompute')),
  status text not null default 'queued' check(status in ('queued','running','succeeded','partial','failed','cancelled')),
  requested_by text not null default 'automatic' check(requested_by in ('binding','manual','automatic','admin','system')),
  priority integer not null default 0,
  cursor jsonb not null default '{}'::jsonb,
  attempts integer not null default 0,
  max_attempts integer not null default 5,
  run_after timestamptz not null default now(),
  locked_at timestamptz,
  locked_by text,
  error_code text not null default '',
  error_message text not null default '',
  processed_count integer not null default 0,
  created_at timestamptz not null default now(),
  started_at timestamptz,
  finished_at timestamptz
);
create index if not exists training_sync_jobs_claim_idx on public.training_sync_jobs(status,run_after,priority desc,created_at);
create unique index if not exists training_sync_one_open_idx on public.training_sync_jobs(external_account_id,kind) where status in ('queued','running') and external_account_id is not null;

create table if not exists public.training_sync_runs (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references public.training_sync_jobs(id) on delete cascade,
  platform text,
  outcome text not null check(outcome in ('succeeded','partial','failed')),
  fetched_count integer not null default 0,
  inserted_count integer not null default 0,
  duration_ms integer not null default 0,
  error_code text not null default '',
  error_message text not null default '',
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists training_sync_runs_job_idx on public.training_sync_runs(job_id,created_at desc);

create table if not exists private.platform_rate_leases (
  platform text primary key check(platform in ('codeforces','atcoder','luogu')),
  available_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
insert into private.platform_rate_leases(platform) values('codeforces'),('atcoder'),('luogu') on conflict do nothing;

create table if not exists public.problem_catalog (
  id uuid primary key default gen_random_uuid(),
  platform text not null check(platform in ('codeforces','atcoder','luogu')),
  external_problem_id text not null,
  contest_id text not null default '',
  problem_index text not null default '',
  title text not null,
  url text not null,
  raw_difficulty numeric,
  normalized_difficulty integer,
  map_code text references public.training_maps(code) on delete set null,
  is_available boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(platform,external_problem_id)
);
create index if not exists problem_catalog_recommend_idx on public.problem_catalog(map_code,normalized_difficulty) where is_available;

create table if not exists public.platform_tag_mappings (
  platform text not null check(platform in ('codeforces','atcoder','luogu')),
  raw_tag text not null,
  skill_code text not null references public.canonical_skills(code) on delete restrict,
  confidence numeric(4,3) not null check(confidence between 0 and 1),
  source text not null default 'official',
  primary key(platform,raw_tag,skill_code)
);

insert into public.platform_tag_mappings(platform,raw_tag,skill_code,confidence) values
('codeforces','implementation','simulation',1),('codeforces','brute force','enumeration',1),('codeforces','sortings','sorting',1),('codeforces','prefix sums','prefix',1),('codeforces','binary search','binary_search',1),('codeforces','two pointers','two_pointers',1),('codeforces','greedy','greedy',1),('codeforces','constructive algorithms','constructive',1),('codeforces','dfs and similar','dfs_bfs',1),('codeforces','meet-in-the-middle','meet_middle',1),('codeforces','data structures','advanced_ds',0.8),('codeforces','dsu','dsu',1),('codeforces','trees','tree',1),('codeforces','shortest paths','shortest_path',1),('codeforces','graphs','graph_traversal',0.8),('codeforces','flows','flow_matching',1),('codeforces','dp','basic_dp',0.8),('codeforces','bitmasks','state_digit_dp',0.8),('codeforces','string suffix structures','suffix',1),('codeforces','strings','string_hash',0.8),('codeforces','hashing','string_hash',1),('codeforces','number theory','number_theory',1),('codeforces','combinatorics','combinatorics',1),('codeforces','probabilities','probability',1),('codeforces','geometry','basic_geometry',0.9),('codeforces','fft','polynomial',1),('codeforces','matrices','linear_algebra',1),('codeforces','randomized','randomized',1),
('luogu','模拟','simulation',1),('luogu','枚举','enumeration',1),('luogu','排序','sorting',1),('luogu','前缀和','prefix',1),('luogu','二分答案','binary_search',1),('luogu','贪心','greedy',1),('luogu','搜索','dfs_bfs',0.8),('luogu','广度优先搜索','dfs_bfs',1),('luogu','深度优先搜索','dfs_bfs',1),('luogu','并查集','dsu',1),('luogu','堆','heap',1),('luogu','线段树','fenwick_segment',1),('luogu','树状数组','fenwick_segment',1),('luogu','最短路','shortest_path',1),('luogu','最小生成树','mst_scc',1),('luogu','强连通分量','mst_scc',1),('luogu','网络流','flow_matching',1),('luogu','动态规划','basic_dp',0.8),('luogu','背包','knapsack',1),('luogu','树形 DP','tree_dp',1),('luogu','状态压缩','state_digit_dp',1),('luogu','数位 DP','state_digit_dp',1),('luogu','KMP','kmp_z',1),('luogu','字符串哈希','string_hash',1),('luogu','后缀数组','suffix',1),('luogu','数论','number_theory',1),('luogu','组合数学','combinatorics',1),('luogu','概率论','probability',1),('luogu','计算几何','basic_geometry',0.9),('luogu','多项式','polynomial',1)
on conflict(platform,raw_tag,skill_code) do update set confidence=excluded.confidence,source=excluded.source;

create table if not exists public.problem_skill_tags (
  problem_id uuid not null references public.problem_catalog(id) on delete cascade,
  skill_code text not null references public.canonical_skills(code) on delete restrict,
  confidence numeric(4,3) not null check(confidence between 0 and 1),
  source text not null check(source in ('official','owner','trusted','community','inferred')),
  raw_tag text not null default '',
  reviewed_at timestamptz,
  primary key(problem_id,skill_code)
);
create index if not exists problem_skill_tags_skill_idx on public.problem_skill_tags(skill_code,confidence desc);

create table if not exists public.problem_aliases (
  problem_id uuid primary key references public.problem_catalog(id) on delete cascade,
  canonical_problem_id uuid not null references public.problem_catalog(id) on delete cascade,
  source text not null default 'owner',
  confirmed_at timestamptz not null default now(),
  check(problem_id<>canonical_problem_id)
);

create table if not exists public.submission_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  external_account_id uuid not null references public.external_accounts(id) on delete cascade,
  problem_id uuid not null references public.problem_catalog(id) on delete cascade,
  platform text not null check(platform in ('codeforces','atcoder','luogu')),
  external_submission_id text not null,
  verdict text not null,
  is_accepted boolean not null default false,
  language text not null default '',
  submitted_at timestamptz not null,
  time_ms integer,
  memory_kb integer,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique(platform,external_submission_id)
);
create index if not exists submission_events_user_time_idx on public.submission_events(user_id,submitted_at desc);
create index if not exists submission_events_user_problem_idx on public.submission_events(user_id,problem_id,submitted_at);

create table if not exists public.user_problem_progress (
  user_id uuid not null references public.profiles(id) on delete cascade,
  problem_id uuid not null references public.problem_catalog(id) on delete cascade,
  platform text not null check(platform in ('codeforces','atcoder','luogu')),
  first_attempt_at timestamptz not null,
  first_accepted_at timestamptz,
  last_activity_at timestamptz not null,
  attempt_count integer not null default 0,
  failed_before_ac integer not null default 0,
  is_solved boolean not null default false,
  primary key(user_id,problem_id)
);
create index if not exists user_problem_progress_solved_idx on public.user_problem_progress(user_id,first_accepted_at) where is_solved;

create table if not exists public.training_daily_stats (
  user_id uuid not null references public.profiles(id) on delete cascade,
  activity_date date not null,
  platform text not null check(platform in ('codeforces','atcoder','luogu')),
  submission_count integer not null default 0,
  accepted_submissions integer not null default 0,
  solved_count integer not null default 0,
  primary key(user_id,activity_date,platform)
);
create index if not exists training_daily_stats_user_date_idx on public.training_daily_stats(user_id,activity_date desc);

create table if not exists public.skill_mastery (
  user_id uuid not null references public.profiles(id) on delete cascade,
  map_code text not null references public.training_maps(code) on delete cascade,
  region_code text not null references public.map_regions(code) on delete cascade,
  model_version integer not null references public.mastery_model_versions(version) on delete restrict,
  breadth_score numeric(5,2) not null default 0,
  challenge_score numeric(5,2) not null default 0,
  coverage_score numeric(5,2) not null default 0,
  stability_score numeric(5,2) not null default 0,
  mastery_percent integer not null default 0 check(mastery_percent between 0 and 100),
  confidence text not null default 'low' check(confidence in ('low','medium','high')),
  assessment text not null default 'unexplored' check(assessment in ('strength','weakness','unexplored','steady','rusty')),
  evidence numeric(8,3) not null default 0,
  upper_evidence numeric(8,3) not null default 0,
  solved_count integer not null default 0,
  attempted_count integer not null default 0,
  covered_skills integer not null default 0,
  required_skills integer not null default 0,
  active_days integer not null default 0,
  active_weeks integer not null default 0,
  last_trained_at timestamptz,
  explanation text not null default '',
  updated_at timestamptz not null default now(),
  primary key(user_id,map_code,region_code,model_version)
);
create index if not exists skill_mastery_user_idx on public.skill_mastery(user_id,model_version,map_code);

create table if not exists public.map_unlocks (
  user_id uuid not null references public.profiles(id) on delete cascade,
  map_code text not null references public.training_maps(code) on delete cascade,
  model_version integer not null references public.mastery_model_versions(version) on delete restrict,
  unlocked_at timestamptz not null default now(),
  detail jsonb not null default '{}'::jsonb,
  primary key(user_id,map_code)
);

create table if not exists public.training_privacy (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  accounts_public boolean not null default true,
  heatmap_public boolean not null default true,
  map_public boolean not null default true,
  recent_public boolean not null default true,
  updated_at timestamptz not null default now()
);

create table if not exists private.training_access_audit (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid not null references public.profiles(id) on delete cascade,
  target_user_id uuid not null references public.profiles(id) on delete cascade,
  resource text not null check(resource in ('private_heatmap')),
  context jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists training_access_audit_target_idx on private.training_access_audit(target_user_id,created_at desc);

create table if not exists public.training_recommendations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  recommendation_date date not null default private.china_today(),
  slot text not null check(slot in ('weakness','progress','explore')),
  problem_id uuid not null references public.problem_catalog(id) on delete cascade,
  region_code text references public.map_regions(code) on delete set null,
  reason text not null,
  score numeric(8,4) not null default 0,
  skipped_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  unique(user_id,recommendation_date,slot)
);

create table if not exists public.expedition_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  type text not null check(type in ('binding','sync','region_mastered','map_unlocked','streak','guardian')),
  title text not null,
  message text not null,
  detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists expedition_logs_user_idx on public.expedition_logs(user_id,created_at desc);

create table if not exists public.training_feature_flags (
  key text primary key,
  enabled boolean not null default false,
  config jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
insert into public.training_feature_flags(key,enabled,config) values
('training_world_enabled',true,'{"rollout":"all"}'::jsonb),('luogu_sync_enabled',true,'{}'::jsonb)
on conflict(key) do nothing;

-- New users receive privacy defaults and the first map. Existing users are backfilled below.
create or replace function private.initialize_training_user()
returns trigger language plpgsql security definer set search_path=public,private,pg_catalog
as $$
declare v_model integer;
begin
  select version into v_model from public.mastery_model_versions where active limit 1;
  insert into public.training_privacy(user_id) values(new.id) on conflict do nothing;
  insert into public.map_unlocks(user_id,map_code,model_version,detail) values(new.id,'plains',coalesce(v_model,1),'{"reason":"starting_map"}'::jsonb) on conflict do nothing;
  return new;
end $$;
drop trigger if exists zz_initialize_training_user on public.profiles;
create trigger zz_initialize_training_user after insert on public.profiles for each row execute function private.initialize_training_user();
insert into public.training_privacy(user_id) select id from public.profiles on conflict do nothing;
insert into public.map_unlocks(user_id,map_code,model_version,detail)
select p.id,'plains',coalesce((select version from public.mastery_model_versions where active limit 1),1),'{"reason":"starting_map"}'::jsonb from public.profiles p on conflict do nothing;

-- RLS: raw ingestion tables are service-only. Public definitions remain readable.
alter table public.mastery_model_versions enable row level security;
alter table public.training_maps enable row level security;
alter table public.canonical_skills enable row level security;
alter table public.map_regions enable row level security;
alter table public.map_region_skills enable row level security;
alter table public.external_accounts enable row level security;
alter table public.binding_challenges enable row level security;
alter table public.training_sync_jobs enable row level security;
alter table public.training_sync_runs enable row level security;
alter table public.problem_catalog enable row level security;
alter table public.platform_tag_mappings enable row level security;
alter table public.problem_skill_tags enable row level security;
alter table public.problem_aliases enable row level security;
alter table public.submission_events enable row level security;
alter table public.user_problem_progress enable row level security;
alter table public.training_daily_stats enable row level security;
alter table public.skill_mastery enable row level security;
alter table public.map_unlocks enable row level security;
alter table public.training_privacy enable row level security;
alter table public.training_recommendations enable row level security;
alter table public.expedition_logs enable row level security;
alter table public.training_feature_flags enable row level security;

drop policy if exists mastery_models_read on public.mastery_model_versions;
create policy mastery_models_read on public.mastery_model_versions for select to anon,authenticated using(true);
drop policy if exists training_maps_read on public.training_maps;
create policy training_maps_read on public.training_maps for select to anon,authenticated using(true);
drop policy if exists canonical_skills_read on public.canonical_skills;
create policy canonical_skills_read on public.canonical_skills for select to anon,authenticated using(true);
drop policy if exists map_regions_read on public.map_regions;
create policy map_regions_read on public.map_regions for select to anon,authenticated using(true);
drop policy if exists map_region_skills_read on public.map_region_skills;
create policy map_region_skills_read on public.map_region_skills for select to anon,authenticated using(true);
drop policy if exists problem_catalog_read on public.problem_catalog;
create policy problem_catalog_read on public.problem_catalog for select to anon,authenticated using(is_available);
drop policy if exists platform_tag_mappings_read on public.platform_tag_mappings;
create policy platform_tag_mappings_read on public.platform_tag_mappings for select to anon,authenticated using(true);
drop policy if exists problem_skill_tags_read on public.problem_skill_tags;
create policy problem_skill_tags_read on public.problem_skill_tags for select to anon,authenticated using(confidence>=0.7);
drop policy if exists problem_aliases_read on public.problem_aliases;
create policy problem_aliases_read on public.problem_aliases for select to anon,authenticated using(true);
drop policy if exists training_flags_read on public.training_feature_flags;
create policy training_flags_read on public.training_feature_flags for select to anon,authenticated using(true);

drop policy if exists external_accounts_own_read on public.external_accounts;
create policy external_accounts_own_read on public.external_accounts for select to authenticated using(user_id=auth.uid());
drop policy if exists binding_challenges_own_read on public.binding_challenges;
create policy binding_challenges_own_read on public.binding_challenges for select to authenticated using(user_id=auth.uid());
drop policy if exists training_sync_jobs_own_read on public.training_sync_jobs;
create policy training_sync_jobs_own_read on public.training_sync_jobs for select to authenticated using(user_id=auth.uid());
drop policy if exists user_problem_progress_own_read on public.user_problem_progress;
create policy user_problem_progress_own_read on public.user_problem_progress for select to authenticated using(user_id=auth.uid());
drop policy if exists training_daily_stats_own_read on public.training_daily_stats;
create policy training_daily_stats_own_read on public.training_daily_stats for select to authenticated using(user_id=auth.uid());
drop policy if exists skill_mastery_own_read on public.skill_mastery;
create policy skill_mastery_own_read on public.skill_mastery for select to authenticated using(user_id=auth.uid());
drop policy if exists map_unlocks_own_read on public.map_unlocks;
create policy map_unlocks_own_read on public.map_unlocks for select to authenticated using(user_id=auth.uid());
drop policy if exists training_privacy_own_read on public.training_privacy;
create policy training_privacy_own_read on public.training_privacy for select to authenticated using(user_id=auth.uid());
drop policy if exists training_recommendations_own_read on public.training_recommendations;
create policy training_recommendations_own_read on public.training_recommendations for select to authenticated using(user_id=auth.uid());
drop policy if exists expedition_logs_own_read on public.expedition_logs;
create policy expedition_logs_own_read on public.expedition_logs for select to authenticated using(user_id=auth.uid());

revoke all on public.external_accounts,public.binding_challenges,public.training_sync_jobs,public.training_sync_runs,public.submission_events,public.user_problem_progress,public.training_daily_stats,public.skill_mastery,public.map_unlocks,public.training_privacy,public.training_recommendations,public.expedition_logs from public,anon,authenticated;
grant select on public.external_accounts,public.binding_challenges,public.training_sync_jobs,public.user_problem_progress,public.training_daily_stats,public.skill_mastery,public.map_unlocks,public.training_privacy,public.training_recommendations,public.expedition_logs to authenticated;
grant select on public.mastery_model_versions,public.training_maps,public.canonical_skills,public.map_regions,public.map_region_skills,public.problem_catalog,public.platform_tag_mappings,public.problem_skill_tags,public.problem_aliases,public.training_feature_flags to anon,authenticated;
revoke all on private.platform_rate_leases,private.training_access_audit from public,anon,authenticated;
revoke execute on function private.initialize_training_user() from public,anon,authenticated;

-- Training achievements reuse the existing safe award/notification pipeline.
insert into public.achievement_definitions(code,name,description,icon,sort_order) values
('training_first_bind','踏上远征','完成第一个竞赛平台绑定','⌁',120),
('training_three_platforms','三站旅者','同时绑定 Codeforces、AtCoder 与洛谷','◈',130),
('training_balanced','均衡发展','在一张地图中所有核心板块达到 80%','✣',140),
('training_map_master','地图制霸','完整点亮一张算法地图','♜',150)
on conflict(code) do update set name=excluded.name,description=excluded.description,icon=excluded.icon,sort_order=excluded.sort_order;
