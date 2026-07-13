"use strict";

const $ = (s, p = document) => p.querySelector(s);
const $$ = (s, p = document) => [...p.querySelectorAll(s)];
const enc = new TextEncoder();
const dec = new TextDecoder();
const esc = (v = "") => String(v).replace(/[&<>'"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;" }[c]));
const uid = () => `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
const nowText = t => new Intl.DateTimeFormat("zh-CN", { month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit" }).format(t || Date.now());

function toast(message, type = "") {
  const item = document.createElement("div");
  item.className = `toast ${type}`;
  item.textContent = message;
  $("#toastStack").append(item);
  setTimeout(() => item.remove(), 2800);
}

let modalResolve = null;
function openModal({ title, html, confirm = "确定", onOpen }) {
  $("#modalTitle").textContent = title;
  $("#modalBody").innerHTML = html;
  $("#modalConfirm").textContent = confirm;
  $("#modalBackdrop").classList.remove("hidden");
  setTimeout(() => $("#modalBody input, #modalBody textarea")?.focus(), 30);
  if (onOpen) onOpen($("#modalBody"));
  return new Promise(resolve => { modalResolve = resolve; });
}
function closeModal(ok = false) {
  $("#modalBackdrop").classList.add("hidden");
  if (modalResolve) modalResolve(ok ? $("#modalBody") : null);
  modalResolve = null;
}
$("#modalClose").onclick = () => closeModal(false);
$("#modalCancel").onclick = () => closeModal(false);
$("#modalConfirm").onclick = () => closeModal(true);
$("#modalBackdrop").addEventListener("click", e => { if (e.target === e.currentTarget) closeModal(false); });

// Navigation
const titles = { home: "首页", vault: "模板库", stress: "代码对拍", roadmap: "任务导图" };
function route() {
  const name = location.hash.slice(1) || "home";
  const page = titles[name] ? name : "home";
  $$(".page").forEach(el => el.classList.toggle("active", el.id === `page-${page}`));
  $$(".main-nav a").forEach(el => el.classList.toggle("active", el.dataset.page === page));
  $("#pageTitle").textContent = titles[page];
  $("#sidebar").classList.remove("open");
  window.scrollTo({ top: 0, behavior: "instant" });
}
window.addEventListener("hashchange", route);
$("#menuBtn").onclick = () => $("#sidebar").classList.toggle("open");
document.addEventListener("click", e => {
  if (innerWidth <= 850 && !$("#sidebar").contains(e.target) && e.target !== $("#menuBtn")) $("#sidebar").classList.remove("open");
});
route();

// Encrypted code vault
const vault = { mode: "open", id: "", keyword: "", password: "", key: null, salt: null, data: null, sid: "", pid: "", versionId: "" };
const colors = ["#2f6b53", "#bd623f", "#42677b", "#88704d", "#785f7d", "#4f807a"];
const b64 = bytes => btoa(String.fromCharCode(...new Uint8Array(bytes)));
const unb64 = str => Uint8Array.from(atob(str), c => c.charCodeAt(0));

async function hashKeyword(keyword) {
  const hash = await crypto.subtle.digest("SHA-256", enc.encode(keyword.trim()));
  return `leather-vault-${b64(hash).replace(/[+/=]/g, "").slice(0, 24)}`;
}
async function deriveKey(password, salt) {
  const base = await crypto.subtle.importKey("raw", enc.encode(password), "PBKDF2", false, ["deriveKey"]);
  return crypto.subtle.deriveKey({ name: "PBKDF2", salt, iterations: 180000, hash: "SHA-256" }, base, { name: "AES-GCM", length: 256 }, false, ["encrypt", "decrypt"]);
}
async function encryptData(data, key, salt) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const raw = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, key, enc.encode(JSON.stringify(data)));
  return { v: 1, alg: "AES-256-GCM", salt: b64(salt), iv: b64(iv), data: b64(raw), updated: Date.now() };
}
async function decryptData(box, key) {
  const raw = await crypto.subtle.decrypt({ name: "AES-GCM", iv: unb64(box.iv) }, key, unb64(box.data));
  return JSON.parse(dec.decode(raw));
}
function starterVault(keyword) {
  const code = `#include <bits/stdc++.h>\nusing namespace std;\n#define int long long\n#define rep(i,a,n) for(int i=(a);i<=(n);i++)\n#define dop(i,a,n) for(int i=(n);i>=(a);i--)\n\nconst int N=1e5+10;\nint n,m,a[N];\n\nsigned main(){\n    ios::sync_with_stdio(false);\n    cin.tie(nullptr);\n    \n    return 0;\n}`;
  const t = Date.now(), pid = uid();
  return { name: keyword, created: t, sections: [{ id: uid(), name: "常用模板", color: colors[0], pages: [{ id: pid, title: "C++14 基础模板", lang: "C++", tags: ["基础", "C++14"], code, updated: t, snapshots: [{ id: uid(), time: t, title: "C++14 基础模板", lang: "C++", tags: ["基础", "C++14"], code }] }] }] };
}
async function saveVault(message = "已加密保存") {
  if (!vault.data || !vault.key) return;
  const box = await encryptData(vault.data, vault.key, vault.salt);
  localStorage.setItem(vault.id, JSON.stringify(box));
  $("#saveState").innerHTML = "<i></i>已加密保存";
  if (message) toast(message);
}
function currentSection() { return vault.data?.sections.find(s => s.id === vault.sid); }
function currentPage() { return currentSection()?.pages.find(p => p.id === vault.pid); }

$$('.gate-tabs button').forEach(btn => btn.onclick = () => {
  vault.mode = btn.dataset.mode;
  $$('.gate-tabs button').forEach(b => b.classList.toggle("active", b === btn));
  $("#confirmField").classList.toggle("hidden", vault.mode !== "create");
  $("#vaultConfirm").required = vault.mode === "create";
  $("#vaultSubmit").innerHTML = vault.mode === "create" ? "创建并进入 <span>→</span>" : "解锁代码库 <span>→</span>";
  $("#vaultError").textContent = "";
});
$("#togglePassword").onclick = () => {
  const input = $("#vaultPassword");
  input.type = input.type === "password" ? "text" : "password";
};
$("#vaultForm").addEventListener("submit", async e => {
  e.preventDefault();
  const keyword = $("#vaultKeyword").value.trim();
  const password = $("#vaultPassword").value;
  const err = $("#vaultError");
  err.textContent = "";
  if (!crypto?.subtle) { err.textContent = "当前环境不支持 Web Crypto，请使用 HTTPS 或 localhost 打开。"; return; }
  if (password.length < 6) { err.textContent = "密码至少需要 6 位。"; return; }
  if (vault.mode === "create" && password !== $("#vaultConfirm").value) { err.textContent = "两次输入的密码不一致。"; return; }
  const submit = $("#vaultSubmit");
  submit.disabled = true;
  submit.textContent = "正在派生密钥…";
  try {
    const id = await hashKeyword(keyword);
    const stored = localStorage.getItem(id);
    if (vault.mode === "create" && stored) throw new Error("这个关键字已存在，请改用“打开代码库”或更换关键字。");
    if (vault.mode === "open" && !stored) throw new Error("本浏览器中没有找到这个关键字对应的代码库。");
    let salt, key, data;
    if (vault.mode === "create") {
      salt = crypto.getRandomValues(new Uint8Array(16));
      key = await deriveKey(password, salt);
      data = starterVault(keyword);
    } else {
      const box = JSON.parse(stored);
      salt = unb64(box.salt);
      key = await deriveKey(password, salt);
      data = await decryptData(box, key);
    }
    Object.assign(vault, { id, keyword, password, salt, key, data, sid: data.sections[0]?.id || "", pid: data.sections[0]?.pages[0]?.id || "", versionId: "" });
    if (vault.mode === "create") await saveVault("");
    openVaultWorkspace();
    toast(vault.mode === "create" ? "代码库已创建" : "代码库已解锁");
  } catch (error) {
    err.textContent = error.name === "OperationError" ? "密码错误，或本地密文已经损坏。" : error.message;
  } finally {
    submit.disabled = false;
    submit.innerHTML = vault.mode === "create" ? "创建并进入 <span>→</span>" : "解锁代码库 <span>→</span>";
  }
});
function openVaultWorkspace() {
  $("#vaultGate").classList.add("hidden");
  $("#vaultWorkspace").classList.remove("hidden");
  renderVault();
}
function renderVault() {
  $("#vaultName").textContent = vault.data.name || vault.keyword;
  const pc = vault.data.sections.reduce((n, s) => n + s.pages.length, 0);
  $("#vaultStats").textContent = `${vault.data.sections.length} 个分区 · ${pc} 个模板`;
  renderSections();
  renderPages();
  loadEditor();
}
function renderSections() {
  const box = $("#sectionList");
  if (!vault.data.sections.length) { box.innerHTML = '<div class="empty-list">还没有分区</div>'; return; }
  box.innerHTML = vault.data.sections.map(s => `<div class="section-item ${s.id === vault.sid ? "active" : ""}" data-id="${s.id}"><i style="background:${s.color}"></i><b>${esc(s.name)}</b><span>${s.pages.length}</span><button title="分区设置">•••</button></div>`).join("");
  $$(".section-item", box).forEach(el => {
    el.onclick = e => {
      if (e.target.tagName === "BUTTON") { editSection(el.dataset.id); return; }
      if (!confirmDiscard()) return;
      vault.sid = el.dataset.id;
      vault.pid = currentSection()?.pages[0]?.id || "";
      vault.versionId = "";
      renderVault();
    };
  });
}
function renderPages() {
  const sec = currentSection(), box = $("#pageList");
  $("#activeSectionName").textContent = sec?.name || "未选择分区";
  $("#activeSectionDot").style.background = sec?.color || "#aaa";
  if (!sec) { box.innerHTML = '<div class="empty-list">请先创建分区</div>'; return; }
  const q = $("#templateSearch").value.trim().toLowerCase(), lang = $("#languageFilter").value;
  const pages = sec.pages.filter(p => (!q || `${p.title} ${p.tags.join(" ")}`.toLowerCase().includes(q)) && (!lang || p.lang === lang));
  box.innerHTML = pages.length ? pages.map(p => `<div class="page-item ${p.id === vault.pid ? "active" : ""}" data-id="${p.id}"><b>${esc(p.title || "未命名模板")}</b><span>${esc(p.lang)} · ${nowText(p.updated)}</span><div class="tag-row">${p.tags.slice(0, 3).map(t => `<span class="tag">${esc(t)}</span>`).join("")}</div></div>`).join("") : '<div class="empty-list">没有匹配的模板</div>';
  $$(".page-item", box).forEach(el => el.onclick = () => {
    if (!confirmDiscard()) return;
    vault.pid = el.dataset.id;
    vault.versionId = "";
    renderPages(); loadEditor();
  });
}
function isEditorDirty() {
  const p = currentPage();
  if (!p || $("#editorBody").classList.contains("hidden")) return false;
  const tags = $("#pageTags").value.split(/[,，]/).map(v => v.trim()).filter(Boolean);
  return p.title !== $("#pageNameInput").value.trim() || p.lang !== $("#pageLanguage").value || p.code !== $("#codeEditor").value || JSON.stringify(p.tags) !== JSON.stringify(tags);
}
function confirmDiscard() { return !isEditorDirty() || confirm("当前修改还没有保存版本，确定放弃吗？"); }
function loadEditor() {
  const p = currentPage();
  $("#emptyEditor").classList.toggle("hidden", !!p);
  $("#editorBody").classList.toggle("hidden", !p);
  if (!p) return;
  $("#pageNameInput").value = p.title;
  $("#pageLanguage").value = p.lang;
  $("#pageTags").value = p.tags.join(", ");
  $("#codeEditor").value = p.code;
  updateLineNumbers();
  renderVersions();
}
function updateLineNumbers() {
  const n = Math.max(1, $("#codeEditor").value.split("\n").length);
  $("#lineNumbers").textContent = Array.from({ length: n }, (_, i) => i + 1).join("\n");
}
$("#codeEditor").addEventListener("input", updateLineNumbers);
$("#codeEditor").addEventListener("scroll", e => { $("#lineNumbers").scrollTop = e.target.scrollTop; });
$("#codeEditor").addEventListener("keydown", e => {
  if (e.key === "Tab") {
    e.preventDefault();
    const a = e.target.selectionStart, b = e.target.selectionEnd;
    e.target.setRangeText("    ", a, b, "end"); updateLineNumbers();
  }
});
$("#templateSearch").oninput = renderPages;
$("#languageFilter").onchange = renderPages;
$("#savePageBtn").onclick = async () => {
  const p = currentPage(); if (!p) return;
  const title = $("#pageNameInput").value.trim() || "未命名模板";
  const tags = [...new Set($("#pageTags").value.split(/[,，]/).map(v => v.trim()).filter(Boolean))].slice(0, 12);
  const snap = { id: uid(), time: Date.now(), title, lang: $("#pageLanguage").value, tags, code: $("#codeEditor").value };
  const last = p.snapshots[p.snapshots.length - 1];
  if (last && last.title === snap.title && last.lang === snap.lang && last.code === snap.code && JSON.stringify(last.tags) === JSON.stringify(snap.tags)) { toast("内容没有变化，无需创建快照"); return; }
  Object.assign(p, { title: snap.title, lang: snap.lang, tags: snap.tags, code: snap.code, updated: snap.time });
  p.snapshots.push(snap);
  if (p.snapshots.length > 60) p.snapshots.splice(0, p.snapshots.length - 60);
  vault.versionId = snap.id;
  await saveVault("新版本已加密保存");
  renderPages(); renderVersions();
};
document.addEventListener("keydown", e => {
  if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "s" && location.hash === "#vault" && vault.data && currentPage()) { e.preventDefault(); $("#savePageBtn").click(); }
});

async function addSection() {
  const body = await openModal({ title: "添加分区", html: '<label>分区名称<input id="newSectionName" maxlength="30" placeholder="例如：图论"></label><label>标识颜色<select id="newSectionColor">' + colors.map((c, i) => `<option value="${c}">颜色 ${i + 1}</option>`).join("") + '</select></label>', confirm: "添加" });
  if (!body) return;
  const name = $("#newSectionName", body).value.trim(); if (!name) { toast("分区名称不能为空", "error"); return; }
  const sec = { id: uid(), name, color: $("#newSectionColor", body).value, pages: [] };
  vault.data.sections.push(sec); vault.sid = sec.id; vault.pid = "";
  await saveVault("分区已添加"); renderVault();
}
$("#addSectionBtn").onclick = addSection;
async function editSection(id) {
  const s = vault.data.sections.find(v => v.id === id); if (!s) return;
  const body = await openModal({ title: "分区设置", html: `<label>分区名称<input id="editSectionName" maxlength="30" value="${esc(s.name)}"></label><label>标识颜色<select id="editSectionColor">${colors.map((c, i) => `<option value="${c}" ${c === s.color ? "selected" : ""}>颜色 ${i + 1}</option>`).join("")}</select></label><label><input id="deleteSectionCheck" type="checkbox" style="display:inline;width:auto;margin-right:6px">删除这个分区及其中所有模板</label>`, confirm: "保存" });
  if (!body) return;
  if ($("#deleteSectionCheck", body).checked) {
    if (!confirm(`确定永久删除“${s.name}”及其中 ${s.pages.length} 个模板吗？`)) return;
    vault.data.sections = vault.data.sections.filter(v => v.id !== id);
    vault.sid = vault.data.sections[0]?.id || ""; vault.pid = currentSection()?.pages[0]?.id || "";
  } else { s.name = $("#editSectionName", body).value.trim() || s.name; s.color = $("#editSectionColor", body).value; }
  await saveVault("分区已更新"); renderVault();
}
$("#addPageBtn").onclick = async () => {
  const sec = currentSection(); if (!sec) { toast("请先创建分区", "error"); return; }
  const body = await openModal({ title: "新建代码模板", html: '<label>模板名称<input id="newPageName" maxlength="80" placeholder="例如：Dinic 最大流"></label><label>语言<select id="newPageLang"><option>C++</option><option>Python</option><option>Java</option><option>JavaScript</option><option>Other</option></select></label>', confirm: "创建" });
  if (!body) return;
  const title = $("#newPageName", body).value.trim() || "未命名模板", lang = $("#newPageLang", body).value, t = Date.now();
  const p = { id: uid(), title, lang, tags: [], code: "", updated: t, snapshots: [] };
  sec.pages.push(p); vault.pid = p.id;
  await saveVault("模板已创建"); renderVault();
};
$("#deletePageBtn").onclick = async () => {
  const p = currentPage(), sec = currentSection(); if (!p || !confirm(`确定永久删除“${p.title}”吗？`)) return;
  sec.pages = sec.pages.filter(v => v.id !== p.id); vault.pid = sec.pages[0]?.id || "";
  await saveVault("模板已删除"); renderVault();
};
$("#lockVaultBtn").onclick = () => {
  if (!confirmDiscard()) return;
  Object.assign(vault, { id: "", keyword: "", password: "", key: null, salt: null, data: null, sid: "", pid: "" });
  $("#vaultPassword").value = ""; $("#vaultConfirm").value = "";
  $("#vaultWorkspace").classList.add("hidden"); $("#vaultGate").classList.remove("hidden");
  $("#saveState").innerHTML = "<i></i>本地存储"; toast("代码库已锁定");
};
$("#exportVaultBtn").onclick = () => {
  const payload = localStorage.getItem(vault.id); if (!payload) return;
  download(`leather-${vault.keyword.replace(/[^\w\u4e00-\u9fa5-]/g, "-")}-backup.json`, JSON.stringify({ type: "leather-vault", version: 1, keyword: vault.keyword, payload: JSON.parse(payload) }, null, 2), "application/json");
  toast("密文备份已导出");
};
$("#importVaultBtn").onclick = () => $("#vaultFileInput").click();
$("#vaultFileInput").onchange = async e => {
  const file = e.target.files[0]; e.target.value = ""; if (!file) return;
  try {
    const backup = JSON.parse(await file.text());
    if (backup.type !== "leather-vault" || !backup.payload?.salt) throw new Error("不是有效的 Leather 密文备份。");
    const salt = unb64(backup.payload.salt), key = await deriveKey(vault.password, salt), data = await decryptData(backup.payload, key);
    if (!confirm(`将备份“${data.name || backup.keyword}”导入并覆盖当前代码库吗？`)) return;
    vault.data = data;
    vault.sid = data.sections[0]?.id || ""; vault.pid = data.sections[0]?.pages[0]?.id || "";
    await saveVault("备份已导入并重新加密"); renderVault();
  } catch (error) { toast(error.name === "OperationError" ? "备份密码与当前密码不一致" : error.message, "error"); }
};

function renderVersions() {
  const p = currentPage(); if (!p) return;
  const list = [...p.snapshots].reverse();
  $("#versionCount").textContent = `${list.length} 个快照`;
  $("#versionList").innerHTML = list.length ? list.map((v, i) => `<button class="version-chip ${v.id === vault.versionId || (!vault.versionId && i === 0) ? "active" : ""}" data-id="${v.id}">v${p.snapshots.length - i} · ${nowText(v.time)}</button>`).join("") : '<span class="empty-list">首次保存后会生成快照</span>';
  $$(".version-chip", $("#versionList")).forEach(btn => btn.onclick = () => { vault.versionId = btn.dataset.id; renderVersions(); renderDiff(); });
  if (!$("#diffPanel").classList.contains("hidden")) renderDiff();
}
$("#toggleDiffBtn").onclick = () => {
  const panel = $("#diffPanel"); panel.classList.toggle("hidden");
  $("#toggleDiffBtn").textContent = panel.classList.contains("hidden") ? "展开差异" : "收起差异";
  if (!panel.classList.contains("hidden")) renderDiff();
};
function renderDiff() {
  const p = currentPage(), panel = $("#diffPanel"); if (!p || !p.snapshots.length) { panel.innerHTML = '<div class="empty-list">暂无可比较版本</div>'; return; }
  let at = p.snapshots.findIndex(v => v.id === vault.versionId); if (at < 0) at = p.snapshots.length - 1;
  const cur = p.snapshots[at], prev = p.snapshots[at - 1];
  const lines = lineDiff(prev?.code || "", cur.code || "");
  panel.innerHTML = `<div style="padding:8px;border-bottom:1px solid #ddd;font-family:var(--sans)"><b>v${at + 1}</b> 对比 ${at ? `v${at}` : "空文件"} · ${nowText(cur.time)} <button class="text-btn" id="restoreVersionBtn">恢复此版本</button></div>` + lines.map((v, i) => `<div class="diff-line ${v.type}"><span>${v.type === "add" ? "+" : v.type === "del" ? "−" : " "}${i + 1}</span><span>${esc(v.text) || " "}</span></div>`).join("");
  $("#restoreVersionBtn").onclick = () => {
    $("#pageNameInput").value = cur.title; $("#pageLanguage").value = cur.lang; $("#pageTags").value = cur.tags.join(", "); $("#codeEditor").value = cur.code; updateLineNumbers(); toast("版本已载入编辑器，保存后才会生成新快照");
  };
}
function lineDiff(oldText, newText) {
  const a = oldText.split("\n"), b = newText.split("\n"), n = a.length, m = b.length;
  if (n * m > 250000) return b.map((text, i) => ({ type: a[i] === text ? "same" : "add", text }));
  const dp = Array.from({ length: n + 1 }, () => new Uint16Array(m + 1));
  for (let i = n - 1; i >= 0; i--) for (let j = m - 1; j >= 0; j--) dp[i][j] = a[i] === b[j] ? dp[i + 1][j + 1] + 1 : Math.max(dp[i + 1][j], dp[i][j + 1]);
  const out = []; let i = 0, j = 0;
  while (i < n && j < m) {
    if (a[i] === b[j]) { out.push({ type: "same", text: a[i++] }); j++; }
    else if (dp[i + 1][j] >= dp[i][j + 1]) out.push({ type: "del", text: a[i++] });
    else out.push({ type: "add", text: b[j++] });
  }
  while (i < n) out.push({ type: "del", text: a[i++] });
  while (j < m) out.push({ type: "add", text: b[j++] });
  return out;
}

function download(name, content, type = "text/plain") {
  const a = document.createElement("a"); a.href = URL.createObjectURL(new Blob([content], { type })); a.download = name; a.click(); setTimeout(() => URL.revokeObjectURL(a.href), 1000);
}

// Stress testing
const stressDefaults = {
  js: {
    solution: `function solve(input) {\n  const a = input.trim().split(/\\s+/).map(Number);\n  const n = a[0];\n  let best = -Infinity, sum = 0;\n  for (let i = 1; i <= n; i++) {\n    sum = Math.max(a[i], sum + a[i]);\n    best = Math.max(best, sum);\n  }\n  return String(best);\n}`,
    brute: `function solve(input) {\n  const a = input.trim().split(/\\s+/).map(Number);\n  const n = a[0];\n  let best = -Infinity;\n  for (let l = 1; l <= n; l++) {\n    let sum = 0;\n    for (let r = l; r <= n; r++) {\n      sum += a[r];\n      best = Math.max(best, sum);\n    }\n  }\n  return String(best);\n}`,
    generator: `function generate(seed) {\n  const n = rnd(1, 25);\n  const a = Array.from({ length: n }, () => rnd(-50, 50));\n  return n + "\\n" + a.join(" ") + "\\n";\n}`
  },
  cpp: {
    solution: `#include <bits/stdc++.h>\nusing namespace std;\n#define int long long\nsigned main(){\n    ios::sync_with_stdio(false); cin.tie(nullptr);\n    int n,x,s=0,ans=LLONG_MIN; cin>>n;\n    while(n--){ cin>>x; s=max(x,s+x); ans=max(ans,s); }\n    cout<<ans;\n    return 0;\n}`,
    brute: `#include <bits/stdc++.h>\nusing namespace std;\n#define int long long\nsigned main(){\n    ios::sync_with_stdio(false); cin.tie(nullptr);\n    int n,a[110],ans=LLONG_MIN; cin>>n;\n    for(int i=1;i<=n;i++) cin>>a[i];\n    for(int l=1;l<=n;l++){\n        int s=0;\n        for(int r=l;r<=n;r++) s+=a[r],ans=max(ans,s);\n    }\n    cout<<ans;\n    return 0;\n}`,
    generator: `#include <bits/stdc++.h>\nusing namespace std;\nint main(int argc,char** argv){\n    unsigned seed=argc>1?stoul(argv[1]):2026;\n    mt19937 rng(seed);\n    int n=rng()%25+1;\n    cout<<n<<"\\n";\n    for(int i=1;i<=n;i++) cout<<(int)(rng()%101)-50<<" ";\n    cout<<"\\n";\n    return 0;\n}`
  }
};
let stressLang = "js", stressWorker = null, stressTimer = null;
function getStressStore() { try { return JSON.parse(localStorage.getItem("leather-stress-v1")) || {}; } catch { return {}; } }
function saveStress() {
  const all = getStressStore(); all[stressLang] = { solution: $("#solutionCode").value, brute: $("#bruteCode").value, generator: $("#generatorCode").value };
  localStorage.setItem("leather-stress-v1", JSON.stringify(all));
}
function loadStress(lang) {
  stressLang = lang; const item = getStressStore()[lang] || stressDefaults[lang];
  $("#solutionCode").value = item.solution; $("#bruteCode").value = item.brute; $("#generatorCode").value = item.generator;
  const js = lang === "js";
  $("#runStressBtn").innerHTML = js ? "▶ 开始对拍" : "↓ 下载本地脚本";
  $("#runtimeNote").innerHTML = js ? '<span>i</span><p><b>在线模式约定：</b>正解和暴力分别定义 <code>solve(input)</code> 并返回字符串；生成器定义 <code>generate(seed)</code>。代码在独立 Worker 中运行，无法访问页面与本地模板。</p>' : '<span>i</span><p><b>C++14 本地模式：</b>三段代码都是完整程序；生成器从第一个命令行参数读取种子。网页会生成 PowerShell 脚本，在你的电脑上调用 <code>g++</code> 编译并逐组比较。</p>';
}
[$("#solutionCode"), $("#bruteCode"), $("#generatorCode")].forEach(el => el.addEventListener("input", () => { clearTimeout(el._t); el._t = setTimeout(saveStress, 250); }));
$("#stressLanguage").onchange = e => { saveStress(); loadStress(e.target.value); };
$$('.reset-code').forEach(btn => btn.onclick = () => {
  const key = btn.dataset.target === "solutionCode" ? "solution" : "brute";
  if (confirm("恢复示例会覆盖当前代码，确定继续吗？")) { $("#" + btn.dataset.target).value = stressDefaults[stressLang][key]; saveStress(); }
});
const genTemplates = {
  js: {
    array: `function generate(seed) {\n  const n = rnd(1, 100);\n  const a = Array.from({ length: n }, () => rnd(-1000, 1000));\n  return n + "\\n" + a.join(" ") + "\\n";\n}`,
    number: `function generate(seed) {\n  const a = rnd(1, 1000000000);\n  const b = rnd(1, 1000000000);\n  return a + " " + b + "\\n";\n}`,
    graph: `function generate(seed) {\n  const n = rnd(2, 30);\n  const maxM = Math.min(n * (n - 1) / 2, n + 40);\n  const m = rnd(n - 1, maxM);\n  const edges = [], used = new Set();\n  for (let v = 2; v <= n; v++) {\n    const u = rnd(1, v - 1);\n    edges.push([u, v]); used.add(u + "," + v);\n  }\n  while (edges.length < m) {\n    let u = rnd(1, n), v = rnd(1, n);\n    if (u > v) [u, v] = [v, u];\n    const key = u + "," + v;\n    if (u !== v && !used.has(key)) { used.add(key); edges.push([u, v]); }\n  }\n  return n + " " + m + "\\n" + edges.map(e => e.join(" ")).join("\\n") + "\\n";\n}`
  },
  cpp: {
    array: `#include <bits/stdc++.h>\nusing namespace std;\nint main(int argc,char** argv){\n    unsigned seed=argc>1?stoul(argv[1]):2026; mt19937 rng(seed);\n    int n=rng()%100+1; cout<<n<<"\\n";\n    for(int i=1;i<=n;i++) cout<<(int)(rng()%2001)-1000<<" ";\n    cout<<"\\n"; return 0;\n}`,
    number: `#include <bits/stdc++.h>\nusing namespace std;\nint main(int argc,char** argv){\n    unsigned seed=argc>1?stoul(argv[1]):2026; mt19937 rng(seed);\n    cout<<rng()%1000000000+1<<" "<<rng()%1000000000+1<<"\\n";\n    return 0;\n}`,
    graph: `#include <bits/stdc++.h>\nusing namespace std;\nint main(int argc,char** argv){\n    unsigned seed=argc>1?stoul(argv[1]):2026; mt19937 rng(seed);\n    int n=rng()%29+2,m=n-1+rng()%min(41,(n-1)*(n-2)/2+1);\n    set<pair<int,int>> e;\n    for(int v=2;v<=n;v++) e.insert({rng()%(v-1)+1,v});\n    while((int)e.size()<m){ int u=rng()%n+1,v=rng()%n+1; if(u>v) swap(u,v); if(u!=v)e.insert({u,v}); }\n    cout<<n<<" "<<m<<"\\n"; for(auto x:e) cout<<x.first<<" "<<x.second<<"\\n";\n    return 0;\n}`
  }
};
$("#generatorMenuBtn").onclick = e => { e.stopPropagation(); $("#generatorDropdown").classList.toggle("hidden"); };
document.addEventListener("click", () => $("#generatorDropdown").classList.add("hidden"));
$$('#generatorDropdown button').forEach(btn => btn.onclick = e => {
  e.stopPropagation();
  if (!$("#generatorCode").value.trim() || confirm("插入模板会覆盖当前生成器，确定继续吗？")) { $("#generatorCode").value = genTemplates[stressLang][btn.dataset.template]; saveStress(); }
  $("#generatorDropdown").classList.add("hidden");
});
function stressStatus(kind, title, summary, progress) {
  $("#resultTitle").textContent = title; $("#resultSummary").textContent = summary;
  $("#stressProgress").style.width = `${progress}%`;
  const dot = $(".console-head i"); dot.className = kind;
}
$("#runStressBtn").onclick = () => stressLang === "js" ? runOnlineStress() : downloadCppStress();
$("#stopStressBtn").onclick = () => stopStress("已手动停止");
function stopStress(reason = "运行已停止") {
  if (stressWorker) stressWorker.terminate(); stressWorker = null; clearTimeout(stressTimer);
  $("#runStressBtn").classList.remove("hidden"); $("#stopStressBtn").classList.add("hidden");
  stressStatus("fail", reason, "可以调整代码后重新运行", 0);
}
function runOnlineStress() {
  const count = Math.max(1, Math.min(5000, Number($("#caseCount").value) || 100));
  const seed = Number($("#seedInput").value) || 1;
  saveStress();
  if (stressWorker) stressWorker.terminate();
  const src = buildWorker($("#solutionCode").value, $("#bruteCode").value, $("#generatorCode").value, count, seed);
  const url = URL.createObjectURL(new Blob([src], { type: "text/javascript" }));
  stressWorker = new Worker(url); URL.revokeObjectURL(url);
  $("#runStressBtn").classList.add("hidden"); $("#stopStressBtn").classList.remove("hidden");
  $("#resultBody").innerHTML = '<div class="console-empty">正在生成数据并比较输出…</div>';
  stressStatus("running", "正在对拍", `0 / ${count} 组`, 0);
  const started = performance.now();
  stressWorker.onmessage = e => {
    const d = e.data;
    if (d.type === "progress") stressStatus("running", "正在对拍", `${d.done} / ${count} 组`, d.done / count * 100);
    if (d.type === "done") finishStress("success", "全部通过", `${count} 组输出完全一致 · ${(performance.now() - started).toFixed(0)} ms`, 100, `<div style="color:#8fc8a2">✓ 未发现差异。随机种子 ${seed}，共完成 ${count} 组。</div>`);
    if (d.type === "mismatch") finishStress("fail", `第 ${d.caseNo} 组发现差异`, `种子 ${d.caseSeed} · 已停止`, (d.caseNo - 1) / count * 100, `<div class="result-grid"><div class="result-block input"><b>输入数据</b><pre>${esc(d.input)}</pre></div><div class="result-block"><b>正解输出</b><pre>${esc(d.actual)}</pre></div><div class="result-block"><b>暴力输出</b><pre>${esc(d.expected)}</pre></div></div>`);
    if (d.type === "error") finishStress("fail", `${d.stage}运行错误`, d.message, 0, `<div style="color:#ef9c94">${esc(d.stack || d.message)}</div>`);
  };
  stressWorker.onerror = e => finishStress("fail", "Worker 运行错误", e.message, 0, `<div style="color:#ef9c94">${esc(e.message)}</div>`);
  stressTimer = setTimeout(() => stopStress("运行超时（20 秒）"), 20000);
}
function finishStress(kind, title, summary, progress, html) {
  if (stressWorker) stressWorker.terminate(); stressWorker = null; clearTimeout(stressTimer);
  $("#runStressBtn").classList.remove("hidden"); $("#stopStressBtn").classList.add("hidden");
  stressStatus(kind, title, summary, progress); $("#resultBody").innerHTML = html;
}
function buildWorker(solution, brute, generator, count, seed) {
  return `const sc=${JSON.stringify(solution)},bc=${JSON.stringify(brute)},gc=${JSON.stringify(generator)},cnt=${count},base=${seed};
let state=1;
function setSeed(v){state=(Number(v)>>>0)||1}
function rnd(l,r){state^=state<<13;state^=state>>>17;state^=state<<5;const u=state>>>0;return l+(u%(r-l+1))}
function factory(code,name){try{return new Function('rnd',code+'\\n;if(typeof solve!=="undefined") return solve;if(typeof generate!=="undefined") return generate;')(rnd)}catch(e){postMessage({type:'error',stage:name,message:e.message,stack:e.stack});throw e}}
(async()=>{let sol,br,gen;try{sol=factory(sc,'正解');br=factory(bc,'暴力');gen=factory(gc,'生成器')}catch(e){return}
for(let i=0;i<cnt;i++){const sd=base+i;try{setSeed(sd);const input=String(await gen(sd));const actual=String(await sol(input)).trimEnd();const expected=String(await br(input)).trimEnd();if(actual!==expected){postMessage({type:'mismatch',caseNo:i+1,caseSeed:sd,input,actual,expected});return}}catch(e){postMessage({type:'error',stage:'第 '+(i+1)+' 组',message:e.message,stack:e.stack});return}if((i+1)%Math.max(1,Math.floor(cnt/100))===0)postMessage({type:'progress',done:i+1})}postMessage({type:'done'})})();`;
}
function psQuoteBase64(text) {
  const bytes = new TextEncoder().encode(text); let bin = ""; bytes.forEach(v => bin += String.fromCharCode(v)); return btoa(bin);
}
function downloadCppStress() {
  saveStress();
  const cnt = Math.max(1, Math.min(5000, Number($("#caseCount").value) || 100)), seed = Number($("#seedInput").value) || 1;
  const a = psQuoteBase64($("#solutionCode").value), b = psQuoteBase64($("#bruteCode").value), g = psQuoteBase64($("#generatorCode").value);
  const ps = `$ErrorActionPreference = "Stop"\n$dir = Join-Path $env:TEMP ("leather-stress-" + [guid]::NewGuid())\nNew-Item -ItemType Directory -Path $dir | Out-Null\ntry {\n  if (-not (Get-Command g++ -ErrorAction SilentlyContinue)) { throw "未找到 g++，请安装 MinGW-w64 并加入 PATH。" }\n  [IO.File]::WriteAllBytes((Join-Path $dir "sol.cpp"), [Convert]::FromBase64String("${a}"))\n  [IO.File]::WriteAllBytes((Join-Path $dir "brute.cpp"), [Convert]::FromBase64String("${b}"))\n  [IO.File]::WriteAllBytes((Join-Path $dir "gen.cpp"), [Convert]::FromBase64String("${g}"))\n  Push-Location $dir\n  g++ sol.cpp -std=c++14 -O2 -o sol.exe; if ($LASTEXITCODE) { throw "正解编译失败" }\n  g++ brute.cpp -std=c++14 -O2 -o brute.exe; if ($LASTEXITCODE) { throw "暴力编译失败" }\n  g++ gen.cpp -std=c++14 -O2 -o gen.exe; if ($LASTEXITCODE) { throw "生成器编译失败" }\n  for ($i=1; $i -le ${cnt}; $i++) {\n    $s = ${seed} + $i - 1\n    cmd /c "gen.exe $s > input.txt"\n    cmd /c "sol.exe < input.txt > sol.txt"\n    cmd /c "brute.exe < input.txt > brute.txt"\n    $x = (Get-Content sol.txt -Raw).TrimEnd(); $y = (Get-Content brute.txt -Raw).TrimEnd()\n    if ($x -ne $y) {\n      Write-Host "第 $i 组发现差异，种子 $s" -ForegroundColor Red\n      Write-Host "----- 输入 -----"; Get-Content input.txt\n      Write-Host "----- 正解 -----"; Get-Content sol.txt\n      Write-Host "----- 暴力 -----"; Get-Content brute.txt\n      Read-Host "按 Enter 退出"; exit 1\n    }\n    if ($i % 10 -eq 0 -or $i -eq ${cnt}) { Write-Host "通过 $i / ${cnt}" -ForegroundColor Green }\n  }\n  Write-Host "全部通过：${cnt} 组输出完全一致。" -ForegroundColor Green\n  Read-Host "按 Enter 退出"\n} finally { Pop-Location -ErrorAction SilentlyContinue; Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }\n`;
  download("leather-stress.ps1", "\ufeff" + ps, "text/plain;charset=utf-8");
  stressStatus("success", "脚本已生成", `共 ${cnt} 组 · 种子 ${seed}`, 100);
  $("#resultBody").innerHTML = '<div class="cpp-download"><p>脚本已下载。请在装有 g++ 的 Windows 电脑上右键使用 PowerShell 运行；如果系统阻止脚本，可在终端执行 <b>powershell -ExecutionPolicy Bypass -File .\\leather-stress.ps1</b>。</p></div>';
}
$("#copyResultBtn").onclick = async () => {
  const text = $("#resultBody").innerText;
  try { await navigator.clipboard.writeText(text); }
  catch {
    const area = document.createElement("textarea"); area.value = text; area.style.position = "fixed"; area.style.opacity = "0"; document.body.append(area); area.select(); document.execCommand("copy"); area.remove();
  }
  toast("结果已复制");
};
loadStress("js");

// Layered training roadmap
const roadmap = { levels: [], dragged: null };
const sampleRoadmap = () => [{ id: uid(), name: "本周必做", note: "最高优先级", color: "#bd623f", tasks: [{ id: uid(), title: "补完网络流专题", desc: "复习 Dinic，并完成 3 道建图题", due: "周三", done: false }, { id: uid(), title: "校内模拟赛", desc: "赛后当天完成复盘", due: "周六", done: false }] }, { id: uid(), name: "持续推进", note: "重要但不紧急", color: "#2f6b53", tasks: [{ id: uid(), title: "整理字符串模板", desc: "KMP、Z 函数、AC 自动机", due: "本周", done: false }, { id: uid(), title: "错题二刷", desc: "重新独立完成最近 5 道错题", due: "周日", done: true }] }, { id: uid(), name: "空闲拓展", note: "有余力再做", color: "#42677b", tasks: [{ id: uid(), title: "阅读 IOI 论文", desc: "记录可迁移的思路", due: "长期", done: false }] }];
function loadRoadmap() { try { roadmap.levels = JSON.parse(localStorage.getItem("leather-roadmap-v1")) || sampleRoadmap(); } catch { roadmap.levels = sampleRoadmap(); } renderRoadmap(); }
function saveRoadmap(message = "") { localStorage.setItem("leather-roadmap-v1", JSON.stringify(roadmap.levels)); if (message) toast(message); }
function renderRoadmap() {
  const board = $("#roadmapBoard");
  board.innerHTML = roadmap.levels.length ? roadmap.levels.map((lv, i) => `<section class="roadmap-level" data-level="${lv.id}" style="--level-color:${lv.color}"><div class="level-label"><span class="level-no">LEVEL ${String(i + 1).padStart(2, "0")}</span><input value="${esc(lv.name)}" maxlength="30" aria-label="层级名称"><small>${esc(lv.note || (i === 0 ? "最高优先级" : "较低优先级"))}</small><div class="level-actions"><button data-action="up" title="上移">↑ 上移</button><button data-action="down" title="下移">↓ 下移</button><button data-action="delete" title="删除层级">删除</button></div></div><div class="task-lane" data-level="${lv.id}">${lv.tasks.map(t => `<article class="task-card ${t.done ? "done" : ""}" draggable="true" data-task="${t.id}"><div class="task-top"><button class="task-check" title="切换完成状态">${t.done ? "✓" : ""}</button><button class="task-menu" title="编辑任务">•••</button></div><h3>${esc(t.title)}</h3><p>${esc(t.desc || "暂无备注")}</p><footer><span>${esc(t.due || "未设时间")}</span><span>${t.done ? "已完成" : `优先级 ${i + 1}`}</span></footer></article>`).join("")}<button class="add-task-card" data-level="${lv.id}">＋ 添加任务</button></div></section>`).join("") : '<div class="empty-state" style="min-height:350px"><div>◎</div><h3>还没有任务层级</h3><p>添加第一层，开始规划训练。</p></div>';
  bindRoadmap(); updateRoadmapProgress();
}
function updateRoadmapProgress() {
  const tasks = roadmap.levels.flatMap(v => v.tasks), done = tasks.filter(v => v.done).length, p = tasks.length ? Math.round(done / tasks.length * 100) : 0;
  $("#progressRing").style.setProperty("--p", p); $("#progressRing b").textContent = `${p}%`;
}
function bindRoadmap() {
  $$(".roadmap-level").forEach(levelEl => {
    const lv = roadmap.levels.find(v => v.id === levelEl.dataset.level);
    $(".level-label input", levelEl).onchange = e => { lv.name = e.target.value.trim() || lv.name; saveRoadmap(); renderRoadmap(); };
    $$(".level-actions button", levelEl).forEach(btn => btn.onclick = () => levelAction(lv.id, btn.dataset.action));
  });
  $$(".add-task-card").forEach(btn => btn.onclick = () => addTask(btn.dataset.level));
  $$(".task-card").forEach(card => {
    const found = findTask(card.dataset.task); if (!found) return;
    $(".task-check", card).onclick = e => { e.stopPropagation(); found.task.done = !found.task.done; saveRoadmap(); renderRoadmap(); };
    $(".task-menu", card).onclick = e => { e.stopPropagation(); editTask(found.level.id, found.task.id); };
    card.ondragstart = e => { roadmap.dragged = { levelId: found.level.id, taskId: found.task.id }; card.classList.add("dragging"); e.dataTransfer.effectAllowed = "move"; };
    card.ondragend = () => { roadmap.dragged = null; card.classList.remove("dragging"); $$(".task-lane").forEach(v => v.classList.remove("drag-over")); };
    card.ondragover = e => { e.preventDefault(); e.stopPropagation(); };
    card.ondrop = e => { e.preventDefault(); e.stopPropagation(); moveTask(roadmap.dragged, found.level.id, found.task.id); };
  });
  $$(".task-lane").forEach(lane => {
    lane.ondragover = e => { e.preventDefault(); lane.classList.add("drag-over"); };
    lane.ondragleave = e => { if (!lane.contains(e.relatedTarget)) lane.classList.remove("drag-over"); };
    lane.ondrop = e => { e.preventDefault(); if (e.target.closest(".task-card")) return; moveTask(roadmap.dragged, lane.dataset.level, null); };
  });
}
function findTask(id) { for (const level of roadmap.levels) { const task = level.tasks.find(t => t.id === id); if (task) return { level, task }; } return null; }
function moveTask(from, targetLevelId, beforeId) {
  if (!from) return; const source = roadmap.levels.find(v => v.id === from.levelId), target = roadmap.levels.find(v => v.id === targetLevelId); if (!source || !target) return;
  if (from.levelId === targetLevelId && from.taskId === beforeId) return;
  const at = source.tasks.findIndex(v => v.id === from.taskId); if (at < 0) return; const [task] = source.tasks.splice(at, 1);
  let pos = beforeId ? target.tasks.findIndex(v => v.id === beforeId) : target.tasks.length; if (pos < 0) pos = target.tasks.length;
  target.tasks.splice(pos, 0, task); saveRoadmap("任务顺序已更新"); renderRoadmap();
}
async function addTask(levelId) {
  const body = await openModal({ title: "添加训练任务", html: '<label>任务名称<input id="taskTitle" maxlength="60" placeholder="例如：完成最短路专题"></label><label>任务说明<textarea id="taskDesc" maxlength="160" placeholder="目标、题目范围或注意事项"></textarea></label><label>时间提示<input id="taskDue" maxlength="20" placeholder="例如：周五前"></label>', confirm: "添加" });
  if (!body) return; const title = $("#taskTitle", body).value.trim(); if (!title) { toast("任务名称不能为空", "error"); return; }
  roadmap.levels.find(v => v.id === levelId)?.tasks.push({ id: uid(), title, desc: $("#taskDesc", body).value.trim(), due: $("#taskDue", body).value.trim(), done: false });
  saveRoadmap("任务已添加"); renderRoadmap();
}
async function editTask(levelId, taskId) {
  const found = findTask(taskId); if (!found) return; const t = found.task;
  const body = await openModal({ title: "编辑任务", html: `<label>任务名称<input id="taskTitle" maxlength="60" value="${esc(t.title)}"></label><label>任务说明<textarea id="taskDesc" maxlength="160">${esc(t.desc || "")}</textarea></label><label>时间提示<input id="taskDue" maxlength="20" value="${esc(t.due || "")}"></label><label><input id="deleteTaskCheck" type="checkbox" style="display:inline;width:auto;margin-right:6px">删除这个任务</label>`, confirm: "保存" });
  if (!body) return;
  if ($("#deleteTaskCheck", body).checked) found.level.tasks = found.level.tasks.filter(v => v.id !== taskId);
  else { t.title = $("#taskTitle", body).value.trim() || t.title; t.desc = $("#taskDesc", body).value.trim(); t.due = $("#taskDue", body).value.trim(); }
  saveRoadmap("任务已更新"); renderRoadmap();
}
async function levelAction(id, action) {
  const at = roadmap.levels.findIndex(v => v.id === id); if (at < 0) return;
  if (action === "delete") { const lv = roadmap.levels[at]; if (!confirm(`确定删除“${lv.name}”及其中 ${lv.tasks.length} 个任务吗？`)) return; roadmap.levels.splice(at, 1); }
  if (action === "up" && at > 0) [roadmap.levels[at - 1], roadmap.levels[at]] = [roadmap.levels[at], roadmap.levels[at - 1]];
  if (action === "down" && at < roadmap.levels.length - 1) [roadmap.levels[at + 1], roadmap.levels[at]] = [roadmap.levels[at], roadmap.levels[at + 1]];
  saveRoadmap("层级已更新"); renderRoadmap();
}
$("#addLevelBtn").onclick = async () => {
  const body = await openModal({ title: "添加优先级层", html: '<label>层级名称<input id="levelName" maxlength="30" placeholder="例如：下月计划"></label><label>层级说明<input id="levelNote" maxlength="40" placeholder="例如：提前准备"></label><label>标识颜色<select id="levelColor">' + colors.map((c, i) => `<option value="${c}">颜色 ${i + 1}</option>`).join("") + '</select></label>', confirm: "添加" });
  if (!body) return; const name = $("#levelName", body).value.trim(); if (!name) { toast("层级名称不能为空", "error"); return; }
  roadmap.levels.push({ id: uid(), name, note: $("#levelNote", body).value.trim(), color: $("#levelColor", body).value, tasks: [] }); saveRoadmap("层级已添加"); renderRoadmap();
};
$("#resetRoadmapBtn").onclick = () => { if (confirm("载入示例会覆盖当前任务导图，确定继续吗？")) { roadmap.levels = sampleRoadmap(); saveRoadmap("示例导图已载入"); renderRoadmap(); } };
loadRoadmap();

window.addEventListener("beforeunload", e => { if (isEditorDirty()) { e.preventDefault(); e.returnValue = ""; } });
