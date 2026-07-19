# Leather 算法远征实施与运维说明

## 已实现范围

算法远征作为独立模块加入 Leather，原任务导图保持不变。当前实现包括：

- Codeforces、AtCoder、洛谷公开账号绑定与所有权验证。
- 资料验证码和备用编译错误提交验证。
- Edge Function 增量同步、数据库队列、游标、幂等提交和指数退避。
- 七张地图、41 个算法区域、58 个规范算法节点和版本化掌握度模型。
- 热力图、能力轮廓、强弱项、每日推荐、远征日志、探险榜和成就。
- 独立设置页、四项训练隐私设置与私密热力图管理员访问审计。
- 管理后台同步队列、数据源错误和私密访问审计面板。

## Supabase 组件

按文件名顺序应用：

1. `202607150004_training_world_schema.sql`
2. `202607150005_training_world_logic.sql`
3. `202607150006_training_world_scheduler.sql`
4. `202607150007_training_catalog_schedule.sql`
5. `202607150008_training_privacy_hardening.sql`
6. `202607150009_training_worker_token.sql`

部署以下 Edge Functions：

- `training-bind`
- `training-sync-request`
- `training-sync-worker`
- `training-catalog-sync`

`training-sync-worker` 必须开启网关 JWT 校验；其余函数在函数体内执行用户 JWT 或 Worker 密钥校验。Supabase 自动提供的 `SUPABASE_URL`、`SUPABASE_ANON_KEY` 和 `SUPABASE_SERVICE_ROLE_KEY` 仅存在于 Edge Runtime。

## 定时任务

首次部署后，以数据库所有者身份调用一次：

```sql
select public.configure_training_worker_schedule(
  'https://YOUR_PROJECT_REF.supabase.co',
  'YOUR_LEGACY_ANON_JWT'
);
```

该函数把项目地址、网关 JWT 和随机 Worker Token 写入 Supabase Vault；数据库只保存 Worker Token 的 bcrypt 哈希，任何值都不写入仓库，并创建：

- `leather-training-worker`：每五分钟触发队列 Worker。
- `leather-training-cron-cleanup`：每周清理 30 天前的 Cron 运行记录。

Worker 会安全领取目录任务：AtCoder 每日刷新，Codeforces 每周刷新。洛谷目录随用户公开提交增量更新。

## 数据与隐私

- 不保存题目源码、平台密码、登录 Cookie 或私有凭据。
- 原始提交事件和同步运行日志对 anon/authenticated 显式拒绝。
- 公开 RPC 只返回裁剪后的账号、热力图、地图和近期记录 DTO。
- 私密热力图仅本人、管理员和站长可读；工作人员读取会写入 `private.training_access_audit`。
- 解除绑定会级联清除该账号的提交事件，并立即重新计算聚合数据。
- 平台故障只将对应绑定标记为 `degraded`，不会清空历史统计。

## 评分解释

板块分数由广度 45%、挑战度 25%、子技能覆盖 20%、跨日稳定性 10% 组成。只有可信度不低于 0.7 的标签参与评分。同一题的重复 AC 和已确认镜像题只贡献一次证据。掌握度不随时间倒退，最近训练状态由独立“手感温度”表达。

## 运维检查

管理后台“算法远征运行状态”显示队列、平台状态、24 小时错误和私密访问记录。常用数据库检查：

```sql
select platform,status,last_success_at,last_error,next_sync_at
from public.training_catalog_state order by platform;

select status,count(*) from public.training_sync_jobs group by status;

select platform,status,count(*) from public.external_accounts group by platform,status;
```

洛谷出现 `parser_changed`、403 或循环跳转时，应保留历史数据并停用 `luogu_sync_enabled` 功能开关，修复契约样例后再恢复。

## 验证

```bash
npm test
npm run test:remote
```

本地测试覆盖 DOM/RLS 静态约束、地图与评分不变量、固定抓取域名、队列与隐私接口；远程测试还会创建临时用户验证私密热力图、工作人员审计和原始提交隔离，并在结束后自动清理。
