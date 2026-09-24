# Example: a small B2B SaaS with an AI assistant: شو بيغطيه الرادار أصلًا

**2026-09-24** · رادار JBelly · مطابَق مع 2729 عنصر بالكتالوج (803 سكيل، 468 خادم MCP)

كل متطلب تحت جاي من قسم البناء بالمعمارية، مش من الرادار. الرادار بيجاوب سؤال
واحد بس عنه: في إشي موجود بيغطي هاد، وبيسوى إشي ولا لأ.

ولا إشي هون توصية. المطابقة بتعني إنه في إشي موجود وكم واحد بيستعمله — مش إنه
منيح. اقرأ المصدر قبل ما تنصّبه.

## مغطّى

### auth - Email and Google sign-in, team invitations, role checks on every endpoint

**المختار:** Supabase Auth

7 مرشّح بالكتالوج. أقواهم:

- **[supabase-postgres-best-practices](https://github.com/supabase/agent-skills)** - Supabase
  <br>414,075 installs · موجود بالرادار من 2026-09-23 - supabase
  <br>`npx skills add supabase/agent-skills`
- **[supabase](https://github.com/supabase/agent-skills)** - Supabase
  <br>289,444 installs · موجود بالرادار من 2026-09-23 - supabase
  <br>`npx skills add supabase/agent-skills`
- **[convex-setup-auth](https://github.com/get-convex/agent-skills)** - Convex
  <br>94,104 installs · موجود بالرادار من 2026-09-23 - auth
  <br>`npx skills add get-convex/agent-skills`

_متعلّم `open`. طلع مغطّى، فما انفتحت البدائل._

### payments - Subscriptions, metered usage billing, invoices

**المختار:** Stripe

12 مرشّح بالكتالوج. أقواهم:

- **[stripe-best-practices](https://github.com/stripe/ai)** - Stripe
  <br>88,170 installs · موجود بالرادار من 2026-09-23 - stripe, payments
  <br>`npx skills add stripe/ai`
- **[upgrade-stripe](https://github.com/stripe/ai)** - Stripe
  <br>67,710 installs · موجود بالرادار من 2026-09-23 - stripe, payments
  <br>`npx skills add stripe/ai`
- **[stripe-projects](https://github.com/stripe/ai)** - Stripe
  <br>65,065 installs · موجود بالرادار من 2026-09-23 - stripe, payments
  <br>`npx skills add stripe/ai`

_متعلّم `firm`، فهاد بينذكر وما بينفتح من جديد._

### assistant - An in-product assistant that reads the customer's own data and acts on it

**المختار:** MCP server over our own API

178 مرشّح بالكتالوج. أقواهم:

- **[@typia/mcp](https://www.npmjs.com/package/@typia/mcp)** - ناشر غير محدّد
  <br>14,815 weekly downloads · موجود بالرادار من 2026-09-23 - model context protocol, tool
- **[activeing123/mcptoon](https://github.com/activeing123/mcptoon)** - activeing123
  <br>203 stars · موجود بالرادار من 2026-09-17 - agent, tool
- **[INo-xious/stockbit-mcp](https://github.com/INo-xious/stockbit-mcp)** - INo-xious
  <br>43 stars · موجود بالرادار من 2026-09-23 - model context protocol, agent

_انشالوا لأنهم عامّين على هالمجموعة (كل وحدة طابقت أكتر من ربعها): mcp, agents. الكلمة اللي بتطابق كل إشي ما بترتّب ولا إشي._

_متعلّم `firm`، فهاد بينذكر وما بينفتح من جديد._

### observability - Trace every assistant call: latency, tokens, cost per customer

**المختار:** OpenTelemetry + a hosted backend

15 مرشّح بالكتالوج. أقواهم:

- **[@hasna/logs](https://www.npmjs.com/package/@hasna/logs)** - ناشر غير محدّد
  <br>1,342 weekly downloads · شوفناه أول مرة 2026-09-23 - monitoring, logs
- **[google-agents-cli-observability](https://github.com/google/agents-cli)** - Google
  <br>328,249 installs · موجود بالرادار من 2026-09-23 - observability
  <br>`npx skills add google/agents-cli`
- **[azure-observability](https://github.com/microsoft/azure-skills)** - Microsoft
  <br>98,331 installs · موجود بالرادار من 2026-09-23 - observability
  <br>`npx skills add microsoft/azure-skills`

_متعلّم `open`. طلع مغطّى، فما انفتحت البدائل._

### search - Semantic search across the customer's uploaded documents

**المختار:** pgvector on the existing Postgres

3 مرشّح بالكتالوج. أقواهم:

- **[yuezhiai/jonex](https://github.com/yuezhiai/jonex)** - yuezhiai
  <br>1,167 stars · موجود بالرادار من 2026-09-23 - rag
- **[axoviq-ai/synthadoc](https://github.com/axoviq-ai/synthadoc)** - axoviq-ai
  <br>1,332 stars · موجود بالرادار من 2026-09-23 - rag
- **[001TMF/harness-forge](https://github.com/001TMF/harness-forge)** - 001TMF
  <br>80 stars · موجود بالرادار من 2026-09-23 - retrieval

_متعلّم `open`. طلع مغطّى، فما انفتحت البدائل._

### pdf-extraction - Pull tables out of supplier PDFs and normalise them

**المختار:** undecided

8 مرشّح بالكتالوج. أقواهم:

- **[pdf](https://github.com/anthropics/skills)** - Anthropic
  <br>200,352 installs · موجود بالرادار من 2026-09-23 - pdf
  <br>`npx skills add anthropics/skills`
- **[nexu-io/open-design](https://github.com/nexu-io/open-design)** - nexu-io
  <br>97,822 stars · موجود بالرادار من 2026-09-17 - pdf
- **[virgiliojr94/book-to-skill](https://github.com/virgiliojr94/book-to-skill)** - virgiliojr94
  <br>32,142 stars · موجود بالرادار من 2026-09-17 - pdf

_متعلّم `open`. طلع مغطّى، فما انفتحت البدائل._

## مش شغل الرادار

### invoicing-ledger - Double-entry bookkeeping for the finance team's export

_متعلّم `manual`: بينبني بالإيد، فما في سكيل ولا خادم MCP إله علاقة._


---

## كيف تقرأ هالتقرير

**مغطّى** يعني في مرشّح واحد على الأقل طابق بالعنوان أو بوسم التقنية، **و** إله
ناشر معروف أو استخدام فوق الوسيط لنوعه بهالكتالوج. الوسيط بينحسب وقت التشغيل من
الكتالوج نفسه، فبيتحرك معه، ومش رقم مجمّد جوّا سكربت.

**ضعيف** يعني في مرشّحين طابقوا بس ولا واحد عدّى هالحد. خده على إنه *يمكن*، وروح
اقرأ المصدر.

**ما في تغطية** هي النتيجة الوحيدة اللي بيصير تحرّك قرار — وبس لمتطلب متعلّم
`open`. المتطلب المتعلّم `firm` انقرّر قبل ما ننسأل الرادار؛ وفتحه كل ما يطلع إشي
جديد هو بالضبط كيف المشروع ما بيخلص أبدًا.

المطابقة صارت مع **السجل**، اللي بيحمل كل إشي شافه الرادار من يوم ما بلّش، مش مع
التغذية الحالية اللي بتحمل مزامنة وحدة وكل مصدر فيها مقصوص. لو سألنا التغذية، كان
"ما في تغطية" كتير مرات بيعني "مش ضمن أول N اليوم" — وبتنقرا نفس الإشي وهي غلط.

المطابقة حسابية بالكامل: كلمات مفتاحية مقابل العناوين ووسوم التقنية والملخّصات
والناشرين. بلا نموذج، بلا شبكة. نفس الخطة ونفس الكتالوج بيعطوا نفس التقرير.
أي كلمة مفتاحية بتطابق أكتر من ربع المجموعة اللي بتدوّر فيها بتنشال وبينذكر اسمها،
لأنها ما بتقدر تفرز إشي عن إشي.


*رادار JBelly · CC BY 4.0*
