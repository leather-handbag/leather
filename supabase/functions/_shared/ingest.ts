import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import type { NormalizedProblem, NormalizedSubmission, Platform, SyncPage } from "./training.ts";

function dbError(error: { message?: string } | null) {
  if (error) throw new Error(error.message || "database operation failed");
}

export async function upsertProblems(admin: SupabaseClient, problems: NormalizedProblem[]) {
  if (!problems.length) return new Map<string, string>();
  const platform = problems[0].platform;
  const ids = [...new Set(problems.map(problem => problem.externalProblemId))];
  const existing = new Map<string, Record<string, unknown>>();
  for (let i = 0; i < ids.length; i += 200) {
    const { data, error } = await admin.from("problem_catalog").select("*").eq("platform", platform).in("external_problem_id", ids.slice(i, i + 200));
    dbError(error);for (const row of data || []) existing.set(row.external_problem_id, row);
  }
  const payload = problems.map(problem => {
    const old = existing.get(problem.externalProblemId) || {};
    const hasDifficulty = problem.normalizedDifficulty != null;
    return {
      platform: problem.platform,
      external_problem_id: problem.externalProblemId,
      contest_id: problem.contestId || old.contest_id || "",
      problem_index: problem.index || old.problem_index || "",
      title: problem.title === problem.externalProblemId && old.title ? old.title : problem.title,
      url: problem.url || old.url,
      raw_difficulty: hasDifficulty ? problem.rawDifficulty : old.raw_difficulty ?? null,
      normalized_difficulty: hasDifficulty ? problem.normalizedDifficulty : old.normalized_difficulty ?? null,
      map_code: hasDifficulty ? problem.mapCode : old.map_code ?? null,
      is_available: true,
      metadata: { ...((old.metadata as Record<string, unknown>) || {}), ...(problem.metadata || {}) },
      updated_at: new Date().toISOString(),
    };
  });
  const rows: Array<Record<string, unknown>> = [];
  for (let i = 0; i < payload.length; i += 200) {
    const { data, error } = await admin.from("problem_catalog").upsert(payload.slice(i, i + 200), { onConflict: "platform,external_problem_id" }).select("id,external_problem_id");
    dbError(error);rows.push(...(data || []));
  }
  const result = new Map(rows.map(row => [String(row.external_problem_id), String(row.id)]));

  const rawTags = [...new Set(problems.flatMap(problem => problem.rawTags))];
  const mappings: Array<Record<string, unknown>> = [];
  for (let i = 0; i < rawTags.length; i += 200) {
    const { data, error } = await admin.from("platform_tag_mappings").select("raw_tag,skill_code,confidence,source").eq("platform", platform).in("raw_tag", rawTags.slice(i, i + 200));
    dbError(error);mappings.push(...(data || []));
  }
  const byTag = new Map<string, Array<Record<string, unknown>>>();
  for (const mapping of mappings) {
    const tag = String(mapping.raw_tag);const list = byTag.get(tag) || [];list.push(mapping);byTag.set(tag, list);
  }
  const tagRowMap = new Map<string, Record<string, unknown>>();
  for (const problem of problems) {
    const problemId = result.get(problem.externalProblemId);if (!problemId) continue;
    for (const rawTag of problem.rawTags) for (const mapping of byTag.get(rawTag) || []) {
      const key = `${problemId}:${mapping.skill_code}`;const old = tagRowMap.get(key);
      if (!old || Number(mapping.confidence) > Number(old.confidence)) tagRowMap.set(key, { problem_id: problemId, skill_code: mapping.skill_code, confidence: mapping.confidence, source: mapping.source === "official" ? "official" : "trusted", raw_tag: rawTag });
    }
  }
  const tagRows = [...tagRowMap.values()];
  for (let i = 0; i < tagRows.length; i += 300) {
    const { error } = await admin.from("problem_skill_tags").upsert(tagRows.slice(i, i + 300), { onConflict: "problem_id,skill_code" });dbError(error);
  }
  return result;
}

export async function ingestSyncPage(admin: SupabaseClient, account: { id: string; user_id: string; platform: Platform }, page: SyncPage) {
  const problemIds = await upsertProblems(admin, page.problems);
  const submissions = page.submissions.filter(item => item.externalSubmissionId && problemIds.has(item.problemExternalId)).map((item: NormalizedSubmission) => ({
    user_id: account.user_id,
    external_account_id: account.id,
    problem_id: problemIds.get(item.problemExternalId),
    platform: account.platform,
    external_submission_id: item.externalSubmissionId,
    verdict: item.verdict,
    is_accepted: item.accepted,
    language: item.language,
    submitted_at: item.submittedAt,
    time_ms: item.timeMs,
    memory_kb: item.memoryKb,
    metadata: item.metadata || {},
  }));
  let changed = 0;
  for (let i = 0; i < submissions.length; i += 300) {
    const { data, error } = await admin.from("submission_events").upsert(submissions.slice(i, i + 300), { onConflict: "platform,external_submission_id", ignoreDuplicates: true }).select("id");
    dbError(error);changed += data?.length || 0;
  }
  return { fetched: page.submissions.length, changed };
}
