/* Staged-reveal report: run each query through the proxy, reveal its panel
 * with the chart AND the measured badge from the same run. Reveal order is
 * the performance story: rollup-backed panels first, journey queries last.
 * ?track=naive runs the Tinybird-verbatim suite instead (same panels, slower
 * reveals — that contrast is the demo). */

const TRACK = new URLSearchParams(location.search).get("track") === "naive" ? "naive" : "optimized";
document.getElementById("trackinfo").textContent =
  `track: ${TRACK}${TRACK === "naive" ? " (Tinybird-verbatim baseline — raw-table scans)" : " (rollups + rewrites + projection)"}`;

const css = (name) => getComputedStyle(document.documentElement).getPropertyValue(name).trim();
const SERIES = () => [css("--series-1"), css("--series-2"), css("--series-3"), css("--series-4"), css("--series-5")];
const CHANNELS = ["direct", "email", "organic", "paid_search", "social"]; // fixed hue order, never cycled
const channelColor = (ch) => SERIES()[CHANNELS.indexOf(ch)] ?? css("--text-muted");
const TEXT2 = () => css("--text-secondary");
const GRID = () => css("--border");

Chart.defaults.font.family = getComputedStyle(document.body).fontFamily;
Chart.defaults.color = TEXT2();
Chart.defaults.borderColor = GRID();
Chart.defaults.plugins.legend.labels.boxWidth = 10;
Chart.defaults.plugins.legend.labels.boxHeight = 10;
Chart.defaults.animation = false;

const PANELS = [
  { name: "q1", title: "Campaign performance", sub: "Daily revenue per channel, last 30 days", render: renderQ1 },
  { name: "q4", title: "Conversion funnel", sub: "Visitors → leads → trials → purchases, last 30 days", render: renderQ4 },
  { name: "q8", title: "Email list health", sub: "Unsub / bounce rate per week vs alert thresholds", render: renderQ8 },
  { name: "q2", title: "Paid-search keywords", sub: "Top keywords by revenue per session, last 14 days", render: renderQ2 },
  { name: "q6", title: "Landing page / SEO", sub: "Landing→lead % by traffic source, latest week", render: renderQ6 },
  { name: "q7", title: "Email hourly", sub: "Sends, opens, clicks by hour, last 7 days", render: renderQ7 },
  { name: "q3", title: "Multi-touch attribution", sub: "Three models disagree — that gap is the point", render: renderQ3 },
  { name: "q5", title: "Cohort retention", sub: "Weekly cohorts × weeks since acquisition (all channels)", render: renderQ5 },
];

const grid = document.getElementById("grid");
for (const p of PANELS) {
  const el = document.createElement("section");
  el.className = "panel"; el.id = `panel-${p.name}`;
  el.innerHTML = `<span class="badge" hidden></span><h2>${p.title}</h2>
    <p class="sub">${p.sub}</p>
    <div class="skeleton"><span class="spin"></span>running ${p.name} (${TRACK})…</div>
    <div class="body" hidden></div>`;
  grid.appendChild(el);
}

const fmt = new Intl.NumberFormat("en-US");
const fmtS = (s) => s >= 10 ? `${s.toFixed(1)}s` : `${s.toFixed(2)}s`;

(async () => {
  for (const p of PANELS) {                       // sequential on purpose: the reveal IS the story
    const el = document.getElementById(`panel-${p.name}`);
    const body = el.querySelector(".body");
    try {
      const resp = await fetch(`/api/query?name=${p.name}&track=${TRACK}`);
      const rec = await resp.json();
      if (!resp.ok || rec.error) throw new Error(rec.error || resp.statusText);
      el.querySelector(".skeleton").remove();
      body.hidden = false;
      p.render(body, rec.data);
      const b = el.querySelector(".badge");
      b.innerHTML = `<b>${fmtS(rec.wall_s)}</b> · ${fmt.format(rec.read_rows ?? 0)} rows read`;
      b.hidden = false;
      el.classList.add("revealed");
    } catch (e) {
      el.querySelector(".skeleton").outerHTML = `<div class="err">${p.name} failed: ${e.message}</div>`;
      el.classList.add("revealed");
    }
  }
})();

function plot(el) { const d = document.createElement("div"); d.className = "plot";
  const c = document.createElement("canvas"); d.appendChild(c); el.appendChild(d); return c; }

/* Q1: line — daily revenue per channel (identity → categorical hues, 2px lines) */
function renderQ1(el, rows) {
  const days = [...new Set(rows.map(r => r.day.slice(0, 10)))].sort();
  const byCh = {};
  for (const r of rows) {
    const d = r.day.slice(0, 10);
    (byCh[r.channel] ??= {})[d] = (byCh[r.channel][d] ?? 0) + (+r.revenue || 0);
  }
  new Chart(plot(el), { type: "line", data: {
    labels: days,
    datasets: CHANNELS.filter(c => byCh[c]).map(c => ({
      label: c, data: days.map(d => byCh[c][d] ?? 0),
      borderColor: channelColor(c), backgroundColor: channelColor(c),
      borderWidth: 2, pointRadius: 0, pointHitRadius: 8, tension: .25,
    })) },
    options: { maintainAspectRatio: false, interaction: { mode: "index", intersect: false },
      scales: { x: { ticks: { maxTicksLimit: 6 }, grid: { display: false } },
                y: { title: { display: true, text: "revenue (USD/day)" } } } } });
}

/* Q4: horizontal bars — funnel totals across campaigns (magnitude, single hue) */
function renderQ4(el, rows) {
  const sum = (k) => rows.reduce((a, r) => a + (+r[k] || 0), 0);
  const stages = [["visitors", sum("visitors")], ["leads", sum("leads")],
                  ["trial starts", sum("trial_starts")], ["purchasers", sum("purchasers")]];
  new Chart(plot(el), { type: "bar", data: {
    labels: stages.map(s => s[0]),
    datasets: [{ data: stages.map(s => s[1]), backgroundColor: css("--series-1"),
                 borderRadius: 4, barThickness: 22 }] },
    options: { indexAxis: "y", maintainAspectRatio: false,
      plugins: { legend: { display: false } },
      scales: { x: { type: "logarithmic", title: { display: true, text: "distinct users (log)" } },
                y: { grid: { display: false } } } } });
}

/* Q8: table — rates vs thresholds; status color + label, never color alone */
function renderQ8(el, rows) {
  const recent = rows.slice(0, 8);
  el.innerHTML = `<table><tr><th>week</th><th>source</th><th class="num">sends</th>
    <th class="num">unsub %</th><th class="num">bounce %</th><th>state</th></tr>` +
    recent.map(r => {
      const bad = +r.unsub_rate_pct > 0.5 || +r.bounce_rate_pct > 2;
      return `<tr><td>${r.week}</td><td>${r.source ?? "—"}</td>
        <td class="num">${fmt.format(r.sends)}</td>
        <td class="num">${r.unsub_rate_pct}</td><td class="num">${r.bounce_rate_pct}</td>
        <td class="${bad ? "alert" : "ok"}">${bad ? "⚠ ALERT" : "✓ ok"}</td></tr>`;
    }).join("") + `</table>
    <p class="sub" style="margin-top:8px">thresholds: unsub &gt; 0.5%, bounce &gt; 2% of sends</p>`;
}

/* Q2: horizontal bars — top 10 by revenue/session (magnitude, single hue) */
function renderQ2(el, rows) {
  const top = rows.slice(0, 10);
  new Chart(plot(el), { type: "bar", data: {
    labels: top.map(r => `${r.keyword} · ${r.ad_group}`),
    datasets: [{ data: top.map(r => +r.revenue_per_session), backgroundColor: css("--series-1"),
                 borderRadius: 4, barThickness: 12 }] },
    options: { indexAxis: "y", maintainAspectRatio: false,
      plugins: { legend: { display: false } },
      scales: { x: { title: { display: true, text: "revenue per session (USD)" } },
                y: { ticks: { font: { size: 10 } }, grid: { display: false } } } } });
}

/* Q6: grouped bars — landing→lead % per source on the busiest pages */
function renderQ6(el, rows) {
  const week = rows.length ? rows[0].week : null;                 // latest week only
  const wk = rows.filter(r => r.week === week);
  const pages = [...new Set(wk.map(r => r.landing_page))]
    .map(p => [p, wk.filter(r => r.landing_page === p).reduce((a, r) => a + +r.sessions, 0)])
    .sort((a, b) => b[1] - a[1]).slice(0, 6).map(x => x[0]).sort();
  const srcs = ["organic", "paid_search", "social"];
  new Chart(plot(el), { type: "bar", data: {
    labels: pages,
    datasets: srcs.map(s => ({
      label: s, backgroundColor: channelColor(s), borderRadius: 4, barThickness: 8,
      data: pages.map(p => +(wk.find(r => r.landing_page === p && r.channel === s)?.landing_to_lead_pct ?? 0)),
    })) },
    options: { indexAxis: "y", maintainAspectRatio: false,
      scales: { x: { title: { display: true, text: `landing→lead % (week of ${week ?? "—"})` } },
                y: { ticks: { font: { size: 10 } }, grid: { display: false } } } } });
}

/* Q7: line — sends/opens/clicks by hour (burst-then-decay shape) */
function renderQ7(el, rows) {
  const byHour = {};
  for (const r of rows) {
    const h = r.hour;
    const o = (byHour[h] ??= { sends: 0, opens: 0, clicks: 0 });
    o.sends += +r.sends; o.opens += +r.opens; o.clicks += +r.clicks;
  }
  const hours = Object.keys(byHour).sort();
  const mk = (k, i) => ({ label: k, data: hours.map(h => byHour[h][k]),
    borderColor: SERIES()[i], backgroundColor: SERIES()[i],
    borderWidth: 2, pointRadius: 0, pointHitRadius: 8 });
  new Chart(plot(el), { type: "line", data: {
    labels: hours.map(h => h.slice(5, 13)),
    datasets: [mk("sends", 0), mk("opens", 1), mk("clicks", 2)] },
    options: { maintainAspectRatio: false, interaction: { mode: "index", intersect: false },
      scales: { x: { ticks: { maxTicksLimit: 7 }, grid: { display: false } },
                y: { title: { display: true, text: "events/hour" } } } } });
}

/* Q3: grouped bars per channel — the three models side by side */
function renderQ3(el, rows) {
  const agg = {};
  for (const r of rows) {
    const a = (agg[r.channel] ??= { linear: 0, first: 0, last: 0 });
    a.linear += +r.linear_attributed_revenue || 0;
    a.first  += +r.first_touch_revenue || 0;
    a.last   += +r.last_touch_revenue || 0;
  }
  const chs = CHANNELS.filter(c => agg[c]);
  const model = (k, label, i) => ({ label, data: chs.map(c => agg[c][k]),
    backgroundColor: SERIES()[i], borderRadius: 4, barThickness: 10 });
  new Chart(plot(el), { type: "bar", data: {
    labels: chs,
    datasets: [model("linear", "linear", 0), model("first", "first-touch", 1), model("last", "last-touch", 2)] },
    options: { indexAxis: "y", maintainAspectRatio: false,
      scales: { x: { title: { display: true, text: "attributed revenue (USD, 30d)" } },
                y: { grid: { display: false } } } } });
}

/* Q5: heatmap grid — retention % per cohort week (sequential: one hue, light→dark) */
function renderQ5(el, rows) {
  const agg = {};                                   // sum across channels per (cohort, weekN)
  for (const r of rows) {
    const k = r.acquisition_week;
    const o = (agg[k] ??= {});
    const cell = (o[r.weeks_since_acquisition] ??= { ret: 0, size: 0 });
    cell.ret += +r.retained_users; cell.size += +r.cohort_size;
  }
  const cohorts = Object.keys(agg).sort().slice(-10);
  const maxW = 8;
  const wrap = document.createElement("div");
  wrap.className = "heat";
  wrap.style.gridTemplateColumns = `72px repeat(${maxW + 1}, 1fr)`;
  wrap.innerHTML = `<div class="rowlab"></div>` +
    [...Array(maxW + 1)].map((_, i) => `<div class="rowlab" style="text-align:center">w${i}</div>`).join("");
  for (const c of cohorts) {
    wrap.innerHTML += `<div class="rowlab">${c}</div>` + [...Array(maxW + 1)].map((_, w) => {
      const cell = agg[c][w];
      if (!cell || !cell.size) return `<div class="cell"></div>`;
      const pct = cell.ret / cell.size * 100;
      const a = Math.min(1, .08 + pct / 60);        // one hue, opacity = magnitude
      return `<div class="cell" style="background:color-mix(in oklab, ${css("--series-1")} ${Math.round(a * 100)}%, transparent)">${pct.toFixed(0)}</div>`;
    }).join("");
  }
  el.appendChild(wrap);
}
