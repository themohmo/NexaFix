---
name: "momo-car-hunter"
description: "Momo Car Hunter. Scans Momo's saved UAE car-broker Instagram accounts in Chrome, 99smsarq first, over the last 4 months for cars matching his brief and returns a linked shortlist spreadsheet."
---

# Momo Car Hunter

Finds cars for Momo on his saved Instagram broker accounts. It reads every post from the last 4 months through his logged-in Chrome, filters against his brief, checks the unclear ones by eye, and hands back one spreadsheet with a link to every match.

Proven on hse.ae and tested live on 99smsarq and alain.adv.1.

## Rules

- Search only the accounts listed under "Accounts", in that order: 99smsarq first, then the rest. Add other sources only if Momo names them.
- Look back 4 months at most. The cut-off is today minus 4 months (run on 25 September 2026, the cut-off is 25 May 2026). Never crawl, list or report older posts. Go shorter only if Momo asks.
- Read-only on Instagram. Never like, follow, comment, message, save or post anything.
- Work in tabs you open yourself. Do not navigate or change Momo's own tabs. Close your tabs at the end.
- Writing: UK spelling, no em or en dashes, no emojis, short plain sentences.
- Never guess. If a post does not give a price, contact, year, engine or mileage, leave that field empty.
- Keep Momo posted. Send a one to three line update with SendUserMessage when the crawl starts (include a time estimate), after each account or group of small accounts, and at least every 10 minutes. He does not like long silences.

## Step 1. Pin down the brief

Needed before starting:

1. Make and model, and which close relatives to exclude (for example full-size Range Rover only: no Sport, Defender, Velar, Evoque).
2. Engine or variant codes allowed (for example P360, P400, P530).
3. Minimum model year.
4. Maximum mileage. Treat it as strictly under unless he says "up to".
5. Optional: price cap, spec (GCC only or imports fine), colour, trim.
6. Search window: fixed at the last 4 months. Do not ask about it unless he wants something shorter.

If make/model, year or mileage is missing, ask once with AskUserQuestion (all gaps in one question set). Otherwise state your assumptions in one line and start. Include sold posts but mark them. For a brand-specific brief, offer once to skip accounts that clearly cannot hold the car (for example the Tesla accounts for a Range Rover hunt); default is all accounts.

## Step 2. Accounts (crawl in this order)

```
99smsarq, alain.adv.1, 123_smsar, hse.ae, motorzuae, defenders.ae, smsar99saood, defender.shj,
70kumh, 1.car.sale, smsarunion, motodar, smsar_range, smsar1rak, 99, simsarmotors, rover4all,
rangerover4all, range.uae, benz.hse, wanted_car, semsar_4you, broker_4all, amg.hse, syarah.uae,
rangerovers.ae, smsarg63, smsar_4all, dr.smsar, defender.gcc, nsn4all, al3incar, 7okuma, 7okumh,
auto.bens, smsarlaqta, teslacars_ae, tesla.smsar, tesla.carz
```

The saved link for "99" looks incomplete (instagram.com/99/). Keep it in the queue; if it fails or is not a car account, report it and move on. 70kumh, 7okuma and 7okumh are three different accounts.

## Step 3. Browser setup (once per session)

Tools: the Claude in Chrome tools (tabs_context_mcp, tabs_create_mcp, navigate, javascript_tool, get_page_text, computer, browser_batch).

1. Call tabs_context_mcp with createIfEmpty true, then tabs_create_mcp to open your own **profile tab**. Navigate it to https://www.instagram.com/99smsarq/. If Instagram shows a login screen, stop and ask Momo to log in.
2. In the profile tab run **JS A** to hook Instagram's own profile-posts request. Then scroll down with the computer tool (scroll, 10 ticks, twice) and run `String(!!window.__mchTpl)`. Repeat the scrolling until it returns true.
3. Open a second tab of your own, the **worker tab**, at https://www.instagram.com/robots.txt. It is on the same origin but is a plain page, so it is safe to write into. Run **JS B** in the worker tab, then **JS C** in the profile tab, then check `String(!!window.__mchTpl)` in the worker tab.

One captured template crawls every account: the crawler swaps the username (tested on hse.ae and defenders.ae from a 99smsarq template). Recapture it (steps 1 to 3) if the tab is lost or requests start failing after a few hours.

## Step 4. Crawl (worker tab)

1. Run **JS D** in the worker tab with the account list and the cut-off date: today minus 4 months, in ISO format (for example '2026-05-25'). JS D also enforces the 4-month limit itself, so it never goes further back even if a wrong date is passed. It crawls the accounts one after another in the background, about 5 to 6 posts a second, pausing 1.8 to 3 seconds between pages, and stops an account once a whole page is older than the cut-off. Four months of 99smsarq is roughly 1,800 posts, about 6 minutes.
2. Poll with **JS E** every 60 to 90 seconds (browser_batch: several 10 second waits, then JS E). Use the first account's speed to give Momo a time estimate.
3. JS E flags `OWNER-MISMATCH` if returned posts belong to someone else, and `failed` after repeated errors. For either, recapture the template on that account's page and rerun just that account. If several accounts fail in a row, Instagram is throttling: stop (`window.__mchStop = true`), wait 10 to 15 minutes, then re-queue the failed ones.

## Step 5. Get the data out

Dump as accounts finish, so a lost tab never costs more than one batch.

1. Run **JS F** in the worker tab with the finished handles. It writes the posts into the page as JSON lines and pads short dumps, so the next call always saves to a file instead of flooding the chat.
2. Call get_page_text on the worker tab with `max_chars: 8000000`. The result says "Output too large ... saved to: <path>".
3. Run **extract.py** on that path to save `posts_batchNN.jsonl` in the scratchpad.

## Step 6. Filter

1. Save **hunt.py** and **report.py** (below) into the scratchpad.
2. Edit `BRIEF` at the top of hunt.py for this request. `posted_after` defaults to today minus 4 months; only change it to a later date if Momo asked for a shorter window. The default brief is the Range Rover one. Use the vocabulary reference below for Arabic spellings. Set `engines_ok` to an empty set if the brief has no engine rule, and `v8_means` / `six_means` to None when a bare cylinder count is ambiguous for that model.
3. Coded hashtags: some accounts (hse.ae and its sister pages) end each caption with a code such as `#3B6276VOGW`, where the three letters are the model family (VOG full-size Range Rover, SPT Sport, DFN Defender, VLR Velar, EVQ/EVC Evoque, OCT Defender Octa, RIM rims, PRT/SPR parts, WNT/WAT wanted ads). Count families per account first; if an account uses them, set `tags_in` / `tags_out` to match.
4. Run `python3 hunt.py posts_*.jsonl`. It prints counts per account and writes `classified.json` and `review.txt` (one line per MATCH or CHECK with a caption excerpt).

What hunt.py does: normalises Arabic (digits, letter variants, bidi marks, diacritics), strips hashtags and boilerplate footers before model matching (hashtag blocks name every model), skips wanted ads, reads year from موديل / model, reads mileage only when anchored on a mileage word, ignores warranty and service figures, turns "35 الف" into 35,000 and a bare "الممشى 112" into 112,000, converts miles, infers engine from codes, cylinders or horsepower, and marks posts whose details are only in the photo.

## Step 7. Review by hand (never skip)

1. Read every MATCH line in review.txt against its excerpt. The parser had no false positives on hse.ae, but a new account can break a rule.
2. Resolve every CHECK line you can from the caption: numbers written before the mileage word ("26K الممشى"), "0 كم" or "زيرو" (new), a 2023 SV (P530), sister posts of the same car. What cannot be resolved stays in To check with a short reason.
3. Skim the mileage exclusions for the target model and year (rows in classified.json whose `why` ends in "km") and make sure the figure is real mileage, not a service or warranty number.
4. Photo-only posts: build a contact sheet in the worker tab with **JS G** (about 15 to 20 post codes per sheet, taken from the CHECK rows marked "details only in image"; start with those whose image text names the model), take a screenshot at scale 0.6, and note which tiles show the target model. Open only those posts in the profile tab (navigate, screenshot at scale 0.5, zoom on text) and read the details. If more than about 150 photo-only posts remain, report the number and ask Momo whether to check them.
5. Save the final MATCH and CHECK rows (with any `note` you add) to `reviewed.json`.

## Step 8. Deliver

1. Run `python3 report.py reviewed.json "<brief in one line>" /mnt/user-data/outputs/car_hunt_<model>_<yyyy-mm-dd>.xlsx`. Sheets: Matches, To check, Summary. Reposts of the same car (same contact, year and engine, across accounts) share a "Repost group". Sold posts are greyed out.
2. Recalculate with the xlsx skill's `scripts/recalc.py`, confirm zero errors, then SendUserFile.
3. Reply in a few short lines: matches and likely unique cars, split by engine and year, how many are sold, what is in To check, and any judgement calls (for example "V8 only" read as P530). No long explanations.
4. Close your profile and worker tabs.

## Gotchas (learned the hard way)

- Never inject elements into the Instagram app page. React crashes, the page reloads and all in-page data is lost. Write into the robots.txt worker tab only.
- javascript_tool returns about 1,000 characters at most, and output containing URLs or query strings is blocked ("Cookie/query string data"). Return short status strings only.
- /api/v1/... endpoints redirect to the homepage. Use the captured GraphQL template.
- read_page cuts text at about 100 characters. Use get_page_text with max_chars.
- Tabs can drop out of the tab group mid-session. Dump data early; if a tab is lost, open new ones and recapture the template.
- "35 الف" is exactly 35,000, so it fails a strict "under 35,000".
- "39 كم" or "37 كيلو" on a used car probably means thousands. Put it in To check.
- "رنجات" / "رنقات" means rims, not Range. The model regex guards against this; keep that guard when writing new regexes.
- "SV rims" or "رنقات SV" does not make a car an SV.
- Posts that start with مطلوب مطلوب, or carry a WNT/WAT or WANTED tag, are buyers, not listings.
- 99smsarq posts about 15 cars a day. Its captions end with a long AutoHub footer after a row of underscores; hunt.py cuts it off. About 15% of its posts have details only in the photo.

## Reference: Arabic listing vocabulary

| Meaning | Words |
|---|---|
| Mileage | ممشى، الممشى، ممشاه، ماشي، ماشيه، متشي، مشي، العداد، الكيلومتر، قاطع، المسافة المقطوعة |
| Thousand | الف، ألف، آلاف، k |
| Model year | موديل، مديل، الموديل، model، year، سنة الصنع |
| Cylinders | سلندر. ثمانية سلندر = V8. ستة سلندر = 6-cylinder. حصان = horsepower |
| Price | السعر، المطلوب، مطلوب، درهم. A bare number under 5,000 next to a price word is thousands (مطلوب 460 = AED 460,000) |
| Warranty or service context (not mileage) | ضمان، لين، لغاية، حتى، كونتراكت، سيرفس، تشييك، صيانة |
| Spec | خليجي = GCC. الطاير = Al Tayer (agency). وارد = import. كلين تايتل = clean title (US import) |
| Status | تم البيع / SOLD = sold. زيرو / صفر كم / غير مستخدم = new |
| Range Rover family | رنج، رينج، رانج (Range). فوج، فوغ، ڤوج (Vogue). اوتوبيوغرافي (Autobiography). سبورت (Sport). ديفندر، دفندر (Defender). فيلار (Velar). ايفوك (Evoque). ديسكفري (Discovery) |
| Other common models | لاندكروزر (Land Cruiser). باترول (Patrol). جي كلاس (G-Class). تسلا (Tesla). لكزس (Lexus) |

## Reference: Range Rover engine facts

- 2022+ Range Rover (L460): P360 and P400 are the 3.0 six-cylinder mild hybrids; P440e, P510e and P550e are plug-in hybrids; P530 is the 4.4 V8.
- The 2023 SV came with the P530 V8. From 2024 the SV uses the P615 V8 (KBB, Edmunds).
- So on a 2023+ full-size Range Rover, "V8" alone means P530 (unless it is a 2024+ SV) and "V6" or "6 cylinder" alone means P360 or P400 (unless it says hybrid or plug-in).
- "P525" on a 2023+ Range Rover is a seller typo (P525 is the old supercharged V8). Put it in To check as likely P530.
- For any other make or model, confirm engine and year facts with a quick web search before relying on them.

## Code

### JS A. Capture the template (profile tab)

```js
(function(){
  if (window.__mchHooked) return 'already hooked';
  window.__mchHooked = true; window.__mchTpl = null;
  const P = XMLHttpRequest.prototype, o = P.open, s = P.send, h = P.setRequestHeader;
  P.open = function(m, u){ this.__u = u; this.__h = {}; return o.apply(this, arguments); };
  P.setRequestHeader = function(k, v){ try { this.__h[k] = v; } catch(e){} return h.apply(this, arguments); };
  P.send = function(b){
    try {
      if (!window.__mchTpl && String(this.__u).includes('graphql') && typeof b === 'string' && b.includes('ProfilePostsTabContentQuery'))
        window.__mchTpl = {url: String(this.__u), headers: this.__h, body: b};
    } catch(e){}
    return s.apply(this, arguments);
  };
  return 'hooked';
})()
```

### JS B. Listen for the template (worker tab)

```js
window.__mchTpl = null; window.__mchBC = new BroadcastChannel('__mch'); window.__mchBC.onmessage = e => { window.__mchTpl = e.data; }; 'listening'
```

### JS C. Send the template (profile tab)

```js
var __bc = new BroadcastChannel('__mch'); __bc.postMessage(window.__mchTpl); setTimeout(() => __bc.close(), 1000); 'sent'
```

### JS D. Crawl a queue of accounts (worker tab)

Replace the handles and the cut-off (today minus 4 months) in the last line.

```js
(function(HANDLES, CUTOFF){
  const tpl = window.__mchTpl; if (!tpl) return 'no template';
  if (window.__mchRun && window.__mchRun.status === 'running') return 'already running';
  if (!document.getElementById('dump')) document.body.innerHTML = '<div id="st"></div><pre id="dump" style="white-space:pre-wrap"></pre>';
  const cap = Date.now() / 1000 - 122 * 86400;   // hard limit: 4 months back
  const stopBefore = Math.max(CUTOFF ? Date.parse(CUTOFF) / 1000 : 0, cap);
  const run = window.__mchRun = {status: 'running', queue: HANDLES.slice(), done: [], acc: {}, current: null};
  window.__mchData = window.__mchData || {}; window.__mchStop = false;
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  function req(handle, after, count) {
    const p = new URLSearchParams(tpl.body);
    const v = JSON.parse(p.get('variables'));
    v.username = handle; v.after = after; v.first = count; if (v.data) v.data.count = count;
    p.set('variables', JSON.stringify(v));
    return new Promise(resolve => {
      const x = new XMLHttpRequest();
      x.open('POST', tpl.url, true);
      for (const [k, val] of Object.entries(tpl.headers || {})) { try { x.setRequestHeader(k, val); } catch (e) {} }
      x.withCredentials = true;
      x.onload = () => resolve(x.responseText);
      x.onerror = () => resolve('');
      x.send(p.toString());
    });
  }
  (async () => {
    while (run.queue.length && !window.__mchStop) {
      const h = run.queue.shift(); run.current = h;
      const st = run.acc[h] = {status: 'running', pages: 0, n: 0, err: 0, owner: '', oldest: ''};
      const items = window.__mchData[h] = []; const seen = {};
      let cursor = null, more = true, count = 33, tries = 0;
      while (more && !window.__mchStop) {
        let j = null; try { j = JSON.parse(await req(h, cursor, count)); } catch (e) {}
        const conn = j && j.data && j.data.xdt_api__v1__feed__user_timeline_graphql_connection;
        if (!conn) {
          st.err++;
          if (count !== 12) { count = 12; continue; }
          if (++tries > 3) { st.status = 'failed'; break; }
          await sleep(10000 * tries); continue;
        }
        tries = 0; let allOld = conn.edges.length > 0;
        for (const e of conn.edges) {
          const n = e.node; if (seen[n.code]) continue; seen[n.code] = 1;
          if (!st.owner && n.user) st.owner = n.user.username;
          if (n.taken_at >= stopBefore) allOld = false;
          let acc = n.accessibility_caption || '';
          if (n.carousel_media) acc += ' || ' + n.carousel_media.map(c => c.accessibility_caption || '').join(' || ');
          const iv = n.image_versions2 || (n.carousel_media && n.carousel_media[0] && n.carousel_media[0].image_versions2);
          const cands = ((iv && iv.candidates) || []).slice().sort((a, b) => a.width - b.width);
          const pick = cands.find(c => c.width >= 300) || cands[cands.length - 1];
          items.push({a: h, c: n.code, t: n.taken_at, mt: n.media_type, cc: n.carousel_media_count || 0,
                      cap: (n.caption && n.caption.text) || '', acc: acc, th: pick ? pick.url : ''});
        }
        st.pages++; st.n = items.length;
        if (items.length) st.oldest = new Date(items[items.length - 1].t * 1000).toISOString().slice(0, 10);
        cursor = conn.page_info.end_cursor; more = !!conn.page_info.has_next_page;
        document.getElementById('st').textContent = h + ': ' + st.n + ' posts, back to ' + st.oldest;
        if (allOld) break;
        await sleep(1800 + Math.random() * 1200);
      }
      if (st.status === 'running') st.status = 'done';
      run.done.push(h);
      await sleep(4000);
    }
    run.status = window.__mchStop ? 'stopped' : 'done'; run.current = null;
    document.title = 'crawl ' + run.status;
  })();
  return 'started ' + HANDLES.length + ' accounts';
})(['99smsarq', 'alain.adv.1'], '2026-05-25')
```

### JS E. Status (worker tab)

```js
(function(){ const r = window.__mchRun; if (!r) return 'not started';
  const rows = Object.entries(r.acc).slice(-10).map(([h, s]) => h + ':' + s.status + ':' + s.n + ':' + s.oldest + ':err' + s.err + (s.owner && s.owner !== h ? ':OWNER-MISMATCH' : ''));
  return r.status + ' | now ' + r.current + ' | done ' + r.done.length + ' | left ' + r.queue.length + ' || ' + rows.join(' ; '); })()
```

### JS F. Dump finished accounts (worker tab)

```js
(function(HANDLES){
  const clean = x => String(x || '').replace(/https?:\/\/\S+/g, 'URL').replace(/[=&]/g, ' ');
  const says = a => { const m = String(a || '').match(/text that says[^|]*/g); return m ? Array.from(new Set(m)).join(' | ') : ''; };
  const lines = [];
  for (const h of HANDLES) for (const it of ((window.__mchData || {})[h] || []))
    lines.push(JSON.stringify({a: it.a, c: it.c, t: it.t, mt: it.mt, cc: it.cc, cap: clean(it.cap), acc: clean(says(it.acc)).slice(0, 1500)}));
  let txt = 'DUMP-START\n' + lines.join('\n') + '\nDUMP-END';
  if (txt.length < 200000) txt += '\n' + 'PAD '.repeat(55000);
  document.getElementById('dump').textContent = txt;
  return lines.length + ' posts dumped';
})(['99smsarq', 'alain.adv.1'])
```

### JS G. Contact sheet of photo-only posts (worker tab)

```js
(function(CODES){
  const all = {}; for (const h in (window.__mchData || {})) for (const it of window.__mchData[h]) all[it.c] = it;
  const cells = CODES.map(c => all[c]).filter(Boolean).map(it =>
    '<div style="display:inline-block;width:230px;margin:4px;vertical-align:top;font:12px monospace;color:#000">' +
    '<img src="' + it.th + '" style="width:230px;height:230px;object-fit:cover;display:block"><div>' + it.c + '</div></div>');
  let sheet = document.getElementById('sheet');
  if (!sheet) { sheet = document.createElement('div'); sheet.id = 'sheet'; document.body.prepend(sheet); }
  sheet.style.cssText = 'background:#fff;padding:6px';
  sheet.innerHTML = cells.join('');
  window.scrollTo(0, 0);
  return cells.length + ' tiles';
})(['CODE1', 'CODE2'])
```

### extract.py

Usage: `python3 extract.py <saved get_page_text file> posts_batch01.jsonl`

```python
import json, sys
t = json.load(open(sys.argv[1], encoding='utf-8'))[0]['text']
body = t[t.index('DUMP-START'):t.index('DUMP-END')].split('\n', 1)[1]
open(sys.argv[2], 'w', encoding='utf-8').write(body)
print(sum(1 for l in body.split('\n') if l.startswith('{')), 'posts saved to', sys.argv[2])
```

### hunt.py

```python
# hunt.py - parse and filter crawled Instagram car posts against a brief
import json, re, sys, datetime, collections

# ---------------- 1. BRIEF (edit per request) ----------------
BRIEF = {
    'label': 'Range Rover full-size, P360/P400/P530, 2023+, under 35,000 km',
    'model_in': r'range\s*rover|rang\s*rover|rangerover|(?<!\w)(?:ال)?(?:رنج|رينج|رانج)(?!\w)|(?<!\w)(?:فوج|فوغ|فوچ|ڤوج|قوج)(?!\w)|vogue|vouge|autobiography|اوتوبيو|اتوبيو|\blwb\b',
    'model_out': r'sport|سبورت|defender|ديفندر|دفندر|ديفيندر|ديڤندر|velar|فيلار|evoque|ايفوك|discovery|ديسكفري|\bsvr\b',
    'tags_in': {'VOG'},            # coded hashtag families that mean the target model (see step 6); empty set if none
    'tags_out': {'SPT', 'DFN', 'VLR', 'EVQ', 'EVC', 'OCT', 'RIM', 'PRT', 'SPR', 'WNT', 'WAT'},
    'engines_ok': {'P360', 'P400', 'P530'},
    'v8_means': 'P530',            # what a bare "V8" means for this model and year range (None if ambiguous)
    'six_means': 'P360/P400',      # what a bare "6 cylinder" means (None if ambiguous)
    'year_min': 2023,
    'km_max': 35000,               # strict: km must be BELOW this
    'price_max': None,             # AED, or None
    'posted_after': (datetime.date.today() - datetime.timedelta(days=122)).isoformat(),  # 4-month limit; only ever move it later
    'trims': [('Autobiography', r'autobiography|اوتوبيو|اتوبيو|اوتو\s*بايو'), ('First Edition', r'first edition|فيرست'),
              ('SV', r'\bsv\b|اس في'), ('HSE', r'hse'), ('SE', r'\bse\b'), ('LWB', r'\blwb\b|\blong\b|لونج')],
}

# ---------------- 2. Normalisation ----------------
AR_DIGITS = str.maketrans('٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹', '01234567890123456789')
_INVISIBLE = [(0x200B, 0x200F), (0x202A, 0x202E), (0x2066, 0x2069), (0x0640, 0x0640), (0xFEFF, 0xFEFF), (0x064B, 0x065F), (0x0670, 0x0670)]
MARKS = re.compile('[' + ''.join(chr(a) + '-' + chr(b) for a, b in _INVISIBLE) + ']')   # bidi marks, tatweel, harakat
def norm(s):
    s = MARKS.sub('', (s or '').translate(AR_DIGITS))
    for a, b in (('،', ','), ('٬', ','), ('٫', '.'), ('أ', 'ا'), ('إ', 'ا'), ('آ', 'ا'), ('ى', 'ي'), ('ة', 'ه'), ('\t', ' ')):
        s = s.replace(a, b)
    return s
def body(cap):                     # caption without hashtags (hashtag blocks name every model) or the boilerplate footer
    return re.sub(r'#\S+', ' ', norm(re.split(r'_{5,}', cap or '')[0]))

# ---------------- 3. Field parsers ----------------
TAG = re.compile(r'#?\b\d{0,3}[A-Z]{1,2}\d{3,6}([A-Z]{3})([A-Z])\b')   # e.g. #3B6276VOGW -> VOG
def tag_family(cap):
    m = TAG.findall(cap or '')
    return m[-1][0] if m else None

YEAR_KW = re.compile(r'(موديل|مديل|الموديل|المديل|الطراز|model|year|سنه\s*:|سنة\s*:|سنه الصنع|سنه الصنع|الصنع)\s*[:\-]?\s*\(?\s*(20[12]\d|1[5-9]|2\d)(?!\d)', re.I)
YEAR = re.compile(r'(?<![\d/.])(20[12]\d)(?![\d/])')
WARR_BEFORE = re.compile(r'(لين|لغايه|حتي|الي|until|till|ضمان|warranty|service|سيرفس|سيرفيس|كونتراكت|كنتراكت|contract|تنتهي|ينتهي|نهايه|شهر|month|valid|ساري|/)\s*[:\-]?\s*(\d{1,2}\s*[/\-.]\s*)?$', re.I)
def model_year(c):
    m = YEAR_KW.search(c)
    if m:
        y = int(m.group(2))
        return y + 2000 if y < 100 else y
    for m in YEAR.finditer(c):
        if not WARR_BEFORE.search(c[max(0, m.start() - 25):m.start()]):
            return int(m.group(1))
    return None

NUM = r'(\d{1,3}(?:[,\.]\d{3})+|\d+(?:\.\d+)?)'
MILE_KW = (r'(ممشاه|ممشي|الممشي|الممشئ|ممشئ|مماشي|ماشي|ماشيه|ما\s?شي|ما\s?شيه|متشي|مشي|العداد|عداد|عداده|قاطع|قاطعه|المسافه المقطوعه|قطعت مسافه|المسافه'
           r'|الكيلومتر|الكيلو\s*متر|الكيلو|mileage|milage|millage|odometer|odo|kilometers|km\s*[:\-]|kms\s*[:\-]|km\s+(?=\d))')
FILL = r'(?:\s|[:\-\(\)\.,=|•\*~\[\]]|السياره|الموتر|حاليا|الحين|فقط|تقريبا|الحالي|الفعلي|اصلي|كيلومتر|كيلو|km|كم|بس|only|approx)*'
MILE = re.compile(MILE_KW + FILL + NUM + r'\s*(k|K|الف|الاف|آلاف|kkm)?\s*(كيلو|كم|km|كلم|kms|ميل|mile|miles|mi)?', re.I)
NUM_KM = re.compile(NUM + r'\s*(k|K|الف|الاف)?\s*(كيلو|كم|km|كلم|kms|ميل|mile|miles|mi)\b', re.I)
SVC_BEFORE = re.compile(r'(صيانه|maintenance|لين|لغايه|حتي|الي|او|or|until|till|ضمان|warranty|service|سيرفس|سيرفيس|سيرفز|كونتراكت|كنتراكت|contract|تشييك|تجييك|تشيك|تشيكات|تجييكات|check|اخر|last|علي|at|ب)\s*[:\-]?\s*$', re.I)
def _num(s):
    s = s.replace(' ', '')
    return float(s.replace(',', '').replace('.', '')) if re.fullmatch(r'\d{1,3}(?:[,\.]\d{3})+', s) else float(s.replace(',', ''))
def _km(val, thou, unit):
    v = val
    if thou and v < 1000: v *= 1000
    elif not thou and v < 400 and not unit: v *= 1000          # "الممشى 112" = 112,000
    if unit and re.match(r'ميل|mile|mi', unit, re.I): v *= 1.609344
    return v
def mileage(c):
    """Returns (km or None, matched text, flag). flag: '' | 'zero' | 'suspect'"""
    hits = []
    for m in MILE.finditer(c):
        if re.match(r'km', m.group(1), re.I) and re.search(r'\d[\d,\.]*\s*$', c[max(0, m.start() - 12):m.start()]):
            continue                                            # 'km' closing a previous number
        svc = bool(SVC_BEFORE.search(c[max(0, m.start() - 22):m.start()]))
        hits.append((svc, _km(_num(m.group(2)), m.group(3), m.group(4)), m.group(0), m.group(3)))
    hits.sort(key=lambda h: h[0])                               # prefer non-service context
    if not hits:
        for m in NUM_KM.finditer(c):
            if SVC_BEFORE.search(c[max(0, m.start() - 30):m.start()]): continue
            hits.append((False, _km(_num(m.group(1)), m.group(2), m.group(3)), m.group(0), m.group(2)))
    zero = bool(re.search(r'زيرو|zero|صفر\s*(كم|كيلو)|\b0\s*(km|كم|كيلو)|brand\s*new|غير مستخدم|اصفار', c, re.I))
    if hits:
        _, v, txt, thou = hits[0]
        flag = 'suspect' if (0 < v < 200 and not thou) else ''       # "39 كم" may mean 39,000
        return v, txt, flag
    return (0, 'zero', 'zero') if zero else (None, '', '')

def engine(c):
    codes = {('P' + m.group(1) + (m.group(2) or '').lower()) for m in re.finditer(r'\bp\s*-?\s*(\d{3})\s*(e(?![a-z]))?(?!\d)', c, re.I)}
    codes |= {('P' + m.group(1)) for m in re.finditer(r'(?<!\d)(360|400|530|615)\s*p\b', c, re.I)}
    codes |= {('P' + m.group(1)) for m in re.finditer(r'\b(?:hse|se)\s*-?\s*(360|400|530)(?!\d)', c, re.I)}
    codes |= {'D' + m.group(1) for m in re.finditer(r'\bd\s*-?\s*(250|300|350)\b', c, re.I)}
    hp = {m.group(1) for m in re.finditer(r'\b(\d{3})\s*(حصان|hp|bhp|ps|horse)', c, re.I)}
    v8 = bool(re.search(r'(?<![a-z])v\s*8(?!\d)|8\s*سلندر|8\s*سيلندر|8\s*سلند|ثمان\w*\s*سلندر|8\s*cyl|سلندر\s*[:\-]?\s*(8|v8)\b', c, re.I))
    six = bool(re.search(r'(?<![a-z])v\s*6(?!\d)|\bi\s*6\b|6\s*سلندر|ست\w*\s*سلندر|6\s*cyl|6cylender|سلندر\s*[:\-]?\s*(6|v6)\b|\b6v\b', c, re.I))
    phev = bool(re.search(r'plug|phev|هايبرد|هايبريد|hybrid', c, re.I)) and not re.search(r'mild|mhev', c, re.I)
    sv = bool(re.search(r'(رنج|رينج|range\s*rover|vogue|فوج)\s*(روفر\s*)?(اس في\s*)?sv\b|\bsv\s*(20\d\d|موديل|model)|اس في sv', c, re.I))
    return codes, hp, v8, six, phev, sv

def price(c):
    for m in re.finditer(r'(?:السعر المطلوب|السعر|سعر|المطلوب|مطلوب في \w+|مطلوب|asking price|price|aed|dhs)\s*[:\-=]?\s*(?:درهم|aed)?\s*[:\-]?\s*(\d[\d,\.]*)\s*(الف|k|K)?', c, re.I):
        try: v = _num(m.group(1).rstrip('.,'))
        except Exception: continue
        if v < 5000: v *= 1000
        if 20000 <= v <= 5000000: return int(v)
    return None

def phone(c):
    t = re.sub(r'(?<=\d)[\s/\-](?=\d)', '', c)
    m = re.search(r'(?:\+?00971|\+971|971)\s*0?(5\d{8})', t) or re.search(r'(?<!\d)0(5\d{8})(?!\d)', t)
    if not m: return ''
    d = '0' + m.group(1)
    return f'{d[:3]} {d[3:6]} {d[6:]}'

def spec(c):
    t = c.lower()
    for label, rx in (('Korea import', r'كوريا|korea'), ('Canada import', r'كندا|canad'), ('Japan import', r'اليابان|japan'),
                      ('Germany import', r'المانيا|الماني(?! اكسبرس)|germany'), ('US import', r'امريكا|امريكي|american|\busa?\b|clean title|كلين تايتل'),
                      ('Europe import', r'اوروبي|europe'), ('GCC', r'خليجي|gcc|الطاير|الطائر|al\s*tayer|altayer|بريمير|premier|الفطيم|futtaim|وكاله|agency')):
        if re.search(rx, t): return label
    return 'Import' if 'وارد' in t else ''

SOLD = re.compile(r'sold|تم البيع|مباع', re.I)
WANTED = re.compile(r'^\W*(مطلوب\s*){1,3}(?!\s*[:\-]?\s*\d)|\bwanted\b|#\w*WANT', re.I)

# ---------------- 4. Classify ----------------
def classify(p, B=BRIEF):
    raw = p.get('cap', '') or ''
    c = norm(raw); b = body(raw); bl = b.lower()
    r = {'account': p.get('a', ''), 'code': p['c'], 'link': f"https://www.instagram.com/p/{p['c']}/",
         'date': datetime.datetime.utcfromtimestamp(p['t']).strftime('%Y-%m-%d'),
         'sold': 'Sold' if SOLD.search(c) else '', 'phone': phone(c), 'price': price(b)}
    if B.get('posted_after') and r['date'] < B['posted_after']:
        r['verdict'], r['why'] = 'X', 'posted before cut-off'; return r
    fam = tag_family(raw)
    if WANTED.search(b.strip()[:40]) or fam in ('WNT', 'WAT'):
        r['verdict'], r['why'] = 'X', 'wanted ad'; return r
    in_txt, out_txt = bool(re.search(B['model_in'], bl, re.I)), bool(re.search(B['model_out'], bl, re.I))
    if fam in B['tags_in']: model = 'yes' if not out_txt else 'check'
    elif fam in B['tags_out']: model = 'check' if (in_txt and not out_txt) else 'no'
    else: model = 'yes' if (in_txt and not out_txt) else ('image' if len(b.strip()) < 25 else 'no')
    if model == 'image':                                        # use Instagram's image text (OCR) to pre-screen
        ocr = norm(p.get('acc', '')).lower()
        if ocr and re.search(B['model_out'], ocr, re.I) and not re.search(B['model_in'], ocr, re.I):
            r['verdict'], r['why'] = 'X', 'other model (image text)'; return r
        r['ocr_hit'] = bool(ocr and re.search(B['model_in'], ocr, re.I))
    if model == 'no': r['verdict'], r['why'] = 'X', 'other model'; return r
    y = model_year(c); r['year'] = y
    km, kmtxt, kflag = mileage(c); r['km'] = None if km is None else int(round(km)); r['km_text'] = kmtxt
    codes, hp, v8, six, phev, sv = engine(c)
    ok = codes & B['engines_ok']
    if not B['engines_ok']: eng = 'any'                          # brief has no engine rule
    elif ok: eng = '/'.join(sorted(ok))
    elif codes - B['engines_ok']: eng = 'NO:' + '/'.join(sorted(codes))
    elif phev: eng = 'NO:plug-in hybrid'
    elif v8 and not six: eng = (B['v8_means'] + ' (V8)') if B['v8_means'] else 'V8?'
    elif six and not v8: eng = (B['six_means'] + ' (6-cyl)') if B['six_means'] else '6cyl?'
    else: eng = ''
    if sv and y and y >= 2024 and 'V8' in eng: eng = 'NO:2024+ SV (P615)'
    r['engine'] = eng
    r['trim'] = ' '.join(lbl for lbl, rx in B.get('trims', []) if re.search(rx, bl, re.I))
    r['spec'] = spec(b)
    reasons = []
    if model == 'image':
        r['verdict'], r['why'] = 'CHECK', 'details only in image' + (' (image text names the model)' if r.get('ocr_hit') else ''); return r
    if y is not None and y < B['year_min']: r['verdict'], r['why'] = 'X', f'year {y}'; return r
    if eng.startswith('NO:'): r['verdict'], r['why'] = 'X', eng[3:]; return r
    if r['km'] is not None and kflag != 'suspect' and r['km'] >= B['km_max']: r['verdict'], r['why'] = 'X', f"{r['km']:,} km"; return r
    if B['price_max'] and r['price'] and r['price'] > B['price_max']: r['verdict'], r['why'] = 'X', 'over budget'; return r
    if model == 'check': reasons.append('model tag and text disagree')
    if y is None: reasons.append('year not stated')
    if not eng or eng.endswith('?'): reasons.append('engine not stated')
    if r['km'] is None: reasons.append('mileage not stated')
    if kflag == 'suspect': reasons.append(f'caption says "{kmtxt.strip()}", may mean thousands')
    r['verdict'], r['why'] = ('CHECK', '; '.join(reasons)) if reasons else ('MATCH', '')
    return r

if __name__ == '__main__':
    # usage: python3 hunt.py posts_*.jsonl   -> classified.json + review.txt
    posts, seen = [], set()
    for f in sys.argv[1:]:
        for l in open(f, encoding='utf-8'):
            if l.strip().startswith('{'):
                p = json.loads(l)
                if p['c'] not in seen: seen.add(p['c']); posts.append(p)
    caps = {p['c']: p.get('cap', '') for p in posts}
    rows = [classify(p) for p in posts]
    json.dump(rows, open('classified.json', 'w', encoding='utf-8'), ensure_ascii=False)
    with open('review.txt', 'w', encoding='utf-8') as out:
        for r in rows:
            if r['verdict'] in ('MATCH', 'CHECK'):
                snip = re.sub(r'\s+', ' ', body(caps[r['code']]))[:150]
                out.write(f"{r['verdict']} {r['account']} {r['code']} {r['date']} Y{r.get('year')} {r.get('engine')} {r.get('km')}km {r['sold']} | {r['why']} | {snip}\n")
    print('posts', len(posts), collections.Counter(r['verdict'] for r in rows))
    by_acc = collections.defaultdict(collections.Counter)
    for r in rows: by_acc[r['account']][r['verdict']] += 1
    for a, c in by_acc.items(): print(a, dict(c))
```

### report.py

```python
# report.py - write the shortlist workbook from reviewed rows
# usage: python3 report.py reviewed.json "<brief label>" /mnt/user-data/outputs/car_hunt_<name>.xlsx
import json, sys, datetime, collections
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.utils import get_column_letter

rows, label, out = json.load(open(sys.argv[1], encoding='utf-8')), sys.argv[2], sys.argv[3]
matches = sorted([r for r in rows if r['verdict'] == 'MATCH'], key=lambda r: (r['date']), reverse=True)
checks = sorted([r for r in rows if r['verdict'] == 'CHECK'], key=lambda r: (r['date']), reverse=True)

def fam(e):
    e = e or ''
    return 'V8' if ('530' in e or 'V8' in e) else ('6' if any(k in e for k in ('360', '400', '6-cyl')) else e)
groups = collections.defaultdict(list)
for r in matches:
    groups[(r['phone'], r.get('year'), fam(r.get('engine'))) if r.get('phone') else ('solo', r['code'])].append(r)
n = 0
for key, rs in sorted(groups.items(), key=lambda kv: max(x['date'] for x in kv[1]), reverse=True):
    n += 1
    for r in rs:
        r['group'] = f'Car {n:03d}' if len(rs) > 1 else ''

F = 'Arial'
HEADS = ['#', 'Account', 'Posted', 'Post link', 'Year', 'Engine', 'Trim', 'Mileage (km)', 'Spec', 'Price (AED)', 'Contact', 'Status', 'Repost group']
def sheet(ws, rs, last):
    ws.append(HEADS + [last])
    for c in ws[1]:
        c.font = Font(name=F, bold=True, color='FFFFFF', size=10); c.fill = PatternFill('solid', start_color='1F3A2E')
        c.alignment = Alignment(vertical='center', wrap_text=True)
    for i, r in enumerate(rs, 1):
        ws.append([i, r.get('account', ''), datetime.date.fromisoformat(r['date']), r['link'], r.get('year'), r.get('engine', ''),
                   r.get('trim', ''), r.get('km'), r.get('spec', ''), r.get('price'), r.get('phone', ''), r.get('sold', ''),
                   r.get('group', ''), r.get('note') or r.get('why', '')])
        row = ws.max_row
        for c in ws[row]:
            c.font = Font(name=F, size=10, color='8C8C8C' if r.get('sold') else '000000')
            c.border = Border(bottom=Side(style='thin', color='D9D9D9'))
            c.alignment = Alignment(vertical='top', wrap_text=(c.column == 14))
        lk = ws.cell(row=row, column=4); lk.hyperlink = r['link']; lk.font = Font(name=F, size=10, color='0563C1', underline='single')
        ws.cell(row=row, column=3).number_format = 'dd mmm yyyy'
        ws.cell(row=row, column=8).number_format = '#,##0'; ws.cell(row=row, column=10).number_format = '#,##0'
    for i, w in enumerate([5, 14, 12, 44, 7, 18, 20, 13, 15, 12, 14, 8, 12, 48], 1):
        ws.column_dimensions[get_column_letter(i)].width = w
    ws.freeze_panes = 'E2'; ws.auto_filter.ref = f'A1:N{ws.max_row}'

wb = Workbook()
ws1 = wb.active; ws1.title = 'Matches'; sheet(ws1, matches, 'Note')
ws2 = wb.create_sheet('To check'); sheet(ws2, checks, 'What to check')
ws3 = wb.create_sheet('Summary')
m1, c1 = len(matches) + 1, len(checks) + 1
for k, v in [('Brief', label), ('Scanned', datetime.date.today().strftime('%d %b %Y')), ('', ''),
             ('Matching posts', f'=COUNTA(Matches!D2:D{max(m1, 2)})'),
             ('Marked sold', f'=COUNTIF(Matches!L2:L{max(m1, 2)},"Sold")'),
             ('Repost groups', f'=SUMPRODUCT((Matches!M2:M{max(m1, 2)}<>"")/COUNTIF(Matches!M2:M{max(m1, 2)},Matches!M2:M{max(m1, 2)}&""))'),
             ('Posts to check', f"=COUNTA('To check'!D2:D{max(c1, 2)})")]:
    ws3.append([k, v])
for row in ws3.iter_rows():
    for c in row:
        c.font = Font(name=F, size=10, bold=(c.column == 1)); c.alignment = Alignment(vertical='top', wrap_text=True, horizontal='left')
ws3.column_dimensions['A'].width = 24; ws3.column_dimensions['B'].width = 90
wb.save(out)
print('saved', out, len(matches), 'matches', len(checks), 'to check')
```