import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = path => readFileSync(new URL(`../${path}`, import.meta.url), "utf8");
const schema = read("supabase/migrations/202607150004_training_world_schema.sql");
const logic = read("supabase/migrations/202607150005_training_world_logic.sql");
const scheduler = read("supabase/migrations/202607150006_training_world_scheduler.sql") + read("supabase/migrations/202607150007_training_catalog_schedule.sql");
const binding = read("supabase/functions/training-bind/index.ts");
const adapters = read("supabase/functions/_shared/training.ts");
const worker = read("supabase/functions/training-sync-worker/index.ts");
const frontend = read("training-world.js");

assert.equal((schema.match(/^\('(?:plains|bronze|silver|gold|platinum|master|legend)'/gm) || []).length, 7, "seven map definitions required");
for (const map of ["plains","bronze","silver","gold","platinum","master","legend"]) assert(schema.includes(`'${map}'`), `missing map ${map}`);
for (const weight of [".45*breadth",".25*challenge",".20*coverage",".10*stability"]) assert(logic.includes(weight), `mastery weight missing: ${weight}`);
assert.match(logic, /coalesce\(a\.canonical_problem_id,p\.problem_id\)/, "known aliases must deduplicate evidence");
assert.match(logic, /confidence>=0\.7/, "low-confidence tags must not affect mastery");
assert.match(logic, /coalesce\(s\.mastery_percent,0\)<100/, "all core regions must reach 100 before unlock");
assert.match(schema, /unique\(platform,external_user_id\)/); assert.match(schema, /unique\(platform,external_submission_id\)/);
assert.match(logic, /insert into private\.training_access_audit/); assert.match(logic, /not coalesce\(v_public,true\) and v_staff/);
assert.match(binding, /profileContainsChallenge/); assert.match(binding, /windowAttempts >= 3/); assert(!/password|cookie/i.test(binding.replace(/平台密码|Cookie/g, "")), "binding code must not accept platform credentials");
for (const host of ["codeforces.com","kenkoooo.com","luogu.com.cn","atcoder.jp"]) assert(adapters.includes(host), `fixed adapter host missing: ${host}`);
assert(!/new URL\([^)]*body|fetch\([^)]*body\./.test(adapters + binding), "user input must not control fetch origins");
assert.match(worker, /claim_training_sync_job/); assert.match(worker, /verify_training_worker_token/); assert.match(worker, /EdgeRuntime/); assert.match(scheduler, /\*\/5 \* \* \* \*/); assert.match(scheduler, /training_worker_token/);
assert.match(frontend, /fetchTrainingHeatmap/); assert.match(frontend, /assessmentText/); assert.match(frontend, /data-bind-platform/);

console.log("Algorithm Expedition checks passed: maps, scoring, privacy, adapters, queue and UI contracts.");
