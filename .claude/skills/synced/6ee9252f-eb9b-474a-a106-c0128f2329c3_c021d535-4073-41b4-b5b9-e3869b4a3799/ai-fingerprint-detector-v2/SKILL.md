---
name: "ai-fingerprint-detector-v2"
description: "Audit text for AI rhetorical fingerprints, score how AI-sounding it is, and rewrite to reduce the signature without changing substance. Keeps hard rules against em-dashes, American spelling and invented facts. Use whenever the user asks to check if text sounds AI-generated, detect AI tells, audit emails, reports or essays for AI patterns, score writing for AI-likeness, de-AI a passage, humanise without a humaniser, or compare a draft against a known AI rhetorical pattern list. Also trigger when the user pastes a passage and asks “does this sound AI”, “how do I make this sound less AI”, or “what is wrong with this writing”, or wants abrupt, choppy sentences or stock transitions smoothed, or asks how AI detectors, detector labels, watermarks or university AI policies work. Apply this skill even when the user does not use the word “AI” but is clearly asking about robotic, generic, or LLM-flavoured prose."
---

# AI Fingerprint Detector (v2)

This skill audits text for the rhetorical, lexical and structural patterns that betray LLM output, scores it, and produces a clean rewrite that preserves substance.

It is designed for managers, editors, and team leads who want their staff to use AI productively but not have it be obvious to recipients.

This is v2 with the October 2026 evidence update. The file has three parts:

- **Part A, operating instructions.** Follow it on every run.
- **Part B, writing reference.** Use it when rewriting.
- **Part C, research reference.** Use it to explain a rating, to answer questions about detectors, and for thesis work on AI detection. Part C never changes how Part A works.

# Part A. Operating instructions

## Hard rule 1: never use em-dashes

The em-dash character (the long dash, U+2014) is a widely cited typographic AI tell, and AI-drafted prose leans on it as a connector. **This skill must never produce that character in any audit, rewrite, example, answer or rationale.** The same ban covers the en-dash (U+2013). Replace a dash that joins or interrupts a sentence with one of:

- a comma, when separating a clause from a subordinate aside
- a colon, when introducing a list, an explanation or an example
- a semicolon, when joining two independent clauses
- a pair of round brackets, for an aside
- a full stop and a new sentence, when the original was hiding a run-on

Plain hyphens stay where they belong: in compound words such as “cross-border” and “post-quantum”, and in number ranges such as “40-45%”, which may also be written “40 to 45%”.

Three special cases:

- **Audit quotes.** When a fragment quoted in the audit contains a dash, write [long dash] or [en dash] in its place. The quote is otherwise word for word.
- **Quoted matter in a rewrite.** Inside a direct quotation, a title or a citation, put a spaced plain hyphen where a dash interrupted the sentence, and a plain hyphen where an en-dash marked a number range. Change nothing else there, and report the change under “Altered in quoted matter”.
- **Scoring.** Only a long dash in the author’s own prose scores under category 0. A dash inside a quotation, a title, a citation or code scores nothing. An en-dash scores nothing anywhere.

This is a house rule. The research behind it is thin: the em-dash appears on practitioner lists, and the 2026 review found no corpus study that measures it. The rule stays strict because readers know the tell.

## Hard rule 2: always use British spelling

**Everything this skill writes uses British spelling**: the audit, the rationale, the rewrite, any answer and every example. That means -ise and -isation endings (organise, organisation), -our (behaviour, colour), -re (centre), doubled consonants (labelled, modelling), and forms such as analyse, defence and judgement.

In a rewrite, change every American spelling in the author’s own prose to its British form, and list the changes in the notes on the rewrite. In an audit with no rewrite, list the American spellings found under “House style”. American spelling is not a tell and scores nothing.

Leave these exactly as written: direct quotations; titles of published works; proper names of every kind (people, places, organisations, institutions, laws, ships, products); code; and the fragments quoted from the source text in an audit.

Mind the words whose British form depends on the sense: practise (verb) and practice (noun); license (verb) and licence (noun); programme (a plan or a broadcast) and program (software); metre (the unit) and meter (the device); cheque (at a bank) and check (to verify).

## Hard rule 3: never invent

A rewrite uses only what the source text holds. **Never add a fact, a figure, a date, a name, a source, a cause, a condition, a hedge or an opinion that the source does not state or plainly entail.**

When a fix needs something that only the author can supply, do not write it. Keep the sentence as close to the source as the other rules allow, put a marker in square brackets at the spot, such as [AUTHOR: which study?], and list the item under “For the author to supply”. In a short message that is meant to be sent as it stands, such as an email, put no marker in the text: keep the sentence as the source has it and list the gap under “For the author to supply”.

Before returning a rewrite, check it against the source. Every name, number, date, source, cause, contrast, sequence and purpose in the rewrite must be in the source. Remove any that is not. “Plainly entail” means that the source’s own words leave no other reading.

Never chase a score. If the hits that remain are gaps that only the author can fill, stop and list them. The rewrite may then keep a high score, and the notes say why.

Every Before and After pair in Part B keeps the same facts. Copy the move only.

## How to use this skill

When given a passage to audit, do all four steps unless the user specifies otherwise:

1. Score the passage on the 22 fingerprint categories below
2. Quote the offending fragments verbatim so the user can see them in context
3. Give an overall AI-likeness rating (Low, Medium, High, Very High)
4. Produce a clean rewrite that preserves substance, obeys the three hard rules, and leaves no abrupt joins between sentences

Other modes:

- **Rewrite only.** Skip the audit. Still give the notes on the rewrite, without scores.
- **Audit only.** Skip the rewrite.
- **Smoothing only.** When the user only wants abrupt or choppy sentences smoothed, skip the audit and apply rewrite principles 8, 15 and 16 with joining techniques 1 to 12 and the “Sentence variety” devices in Part B. Merge the choppy runs, but keep one short sentence that carries a finding. Change joins and sentence shape only, apart from what the hard rules require. Still give the notes on the rewrite, without scores.
- **A question.** When the user asks about detectors, detector labels, watermarks, policy or the research, answer from Part C and from the Limits section below, in plain prose that opens with the answer. Give the source and the date of each fact beside it, and say “undated” where a source has no date. Answer what was asked, and offer the related section of Part C in one line. If Part C holds only part of the answer, give that part and say what is missing. If Part C does not hold the answer, say so; do not fill the gap from memory. For a category, “validated” means its evidence grade, not a match to a vendor label.

“Unless the user specifies otherwise” covers the steps. It never lifts a hard rule.

## Definitions

- **Running prose.** Sentences in paragraphs. Block quotations, reference lists and code score nothing. Headings, subject lines, list items, tables, captions, salutations and signatures are scored only for categories 0, 6 and 21.
- **Paragraph.** A block of running prose. The paragraph-level checks are the category 3 add-on, the paragraph hits in categories 7 and 14, and category 15. They apply only to a paragraph of three or more sentences, unless the check sets its own minimum. Categories 1, 2 and 9 and the overrides apply to a paragraph of any length.
- **Hit.** The shortest run of words that triggers a category. Where one run triggers two categories, or one hit lies inside another, score once: under the higher weight, or under the lower category number on a tie. Mention the other category in the explanation. Two exceptions: each em-dash is always its own category 0 hit, and a paragraph-level hit is scored once per paragraph, on top of the hits inside it.
- **Word count.** Count the words of the running prose, quotations included. A hyphenated compound is one word. A free-standing dash is not a word.
- **Sentence.** Text that ends at a full stop, a question mark or an exclamation mark. A fragment such as “Why her?” counts as a sentence.
- **Block.** For any check that says “within a block”: a text of 300 words or fewer is one block. In a longer text, close each block at the first paragraph end at or after 300 words.
- **Conclusion.** The final paragraph of a text of four or more paragraphs, or a section headed as a conclusion or a summary.
- **Inflected forms.** A listed word covers its inflections: “underscore” covers “underscores” and “underscoring”.
- **Linking adverbial.** A single word or fixed phrase that states a logical relation between sentences: however, therefore, in addition, as a result. A fronted clause or phrase of time, place or cause, such as “Because of the hiring,”, is not one.
- **Markers.** When scoring a rewrite, leave [AUTHOR: ...] markers out of the word count and out of category 6.

## The 22 fingerprint categories

Each category has a weight and an evidence grade. The weight says how far one hit moves the score. The evidence grade says how well research supports the category:

- **Strong**: measured in corpus studies that compare LLM text with human text
- **Moderate**: reported by expert readers, or measured for some models only
- **Weak**: found on practitioner lists or vendor lists only
- **Untested**: carried over from earlier versions of this skill; the 2026 review found no study for or against

A category marked “house rule” keeps its full weight whatever its evidence grade. Where a category closely matches a label that the detector GPTZero shows to its users, the entry says so. Section C1 of Part C maps every label to the categories that cover it.

### High weight (3 points per hit)

**0. Em-dashes.** Each long dash in the author’s own prose is one hit. Hard rule 1 covers quotations and audit quotes. *House rule. Evidence: weak.*

**1. The reversal ending.** A sentence that closes on an antithesis: “X stops being Y, X becomes Z”, “no longer A but B”, “what was once A is now B”, “ceases to be A and becomes B”, “it is not X, it is Y”, “not just X but Y”. Count the short forms “not X but Y”, “X, not Y” and “not only X but also Y” only when they close a paragraph or section. Check the final sentence of every paragraph and section, every time. An antithesis that corrects a misreading which the text has already named is not a hit. GPTZero lists the same pattern as “Not just X, but Y”. *House rule. Evidence: weak to moderate (practitioner lists and one vendor list).*

**2. Cosmic-conclusion openers.** Sentences beginning with “In a world where”, “At a time when”, “In an era of”, “In an age where”, and close variants such as “In today’s world”. Often paired with category 1, as a set-up for the reversal. *Evidence: untested.*

**3. Abstract-noun-on-abstract-noun agency.** A clause whose subject is one high-level abstraction acting on another, with no person, organisation or thing doing anything. Example: “the geographical pivot interacts with the technological convergence to produce risk exposures”. Human writers usually ground at least one side in a concrete actor (a company, a regulator, a person, a team). A noun for a group of people, such as “leadership” or “management”, counts as an abstraction unless the text has said who they are. Count one hit per sentence of this kind, including a sentence where the clause follows a frame such as “It is important to note that”. Add one paragraph-level hit where more than half the sentences of a paragraph have a nominalisation as their subject. A nominalisation is a noun made from a verb or an adjective, most often ending in -tion, -ment, -ance, -ence or -ity. A noun that names a body or a role, such as “organisation” or “government”, is not one. Numbers, data and records that show something, as in “the figures back this up”, are not abstractions for this check. A sentence that relates the field’s own standard terms, such as “deterrence depends on credibility”, is not a hit. *Evidence: strong. Instruction-tuned models use nominalisations at 1.5 to 2 times the human rate (Reinhart et al., 2025).*

**4. Four-part anaphora.** Lists of four or more items that all begin with the same word or phrase. Example: “the same cloud, the same models, the same settlement rails, and broadly the same approach to encryption”. Four-part repetition with identical openers is rare in natural writing. *Evidence: untested.*

**5. Participle tails.** A sentence that ends with a comma or a dash and then an -ing clause that comments on significance and adds no fact: “, highlighting the need for reform”, “, underscoring the importance of trust”, “, reflecting a broader shift”. A tail that carries a fact is not a hit: “The board met in March, voting 7 to 2 to delay the launch.” GPTZero’s “Empty Commentary” covers the same move. *Evidence: strong. GPT models use present participial clauses at about five times the human rate (Reinhart et al., 2025).*

**6. Chatbot residue.** Text left over from the exchange with a chatbot: “As an AI language model”, “Certainly! Here is”, “I hope this helps”, “Let me know if you would like”, a refusal, a knowledge cut-off disclaimer, a placeholder such as “[insert source]”, or a web link that ends in a chatbot tracking tag. One hit each. GPTZero calls this “Chatbot Language”. *Evidence: practitioner lists and one vendor list. Unlike the other categories, an instance here is hard to explain in any other way.*

### Medium weight (1 point per hit)

**7. Stock connective chains.** Sentence-opening adverbials used as glue: Moreover, Furthermore, Additionally, Notably, Importantly, Consequently, Overall, Ultimately, Firstly, Secondly, Lastly. A single one is never a category 7 hit. Count one hit per paragraph, and only one, when any of these is true:

- two or more of the listed openers begin sentences in the paragraph
- the paragraph has four or more sentences, and more than one in three opens with a linking adverbial of any kind, plain ones included
- three or more sentences in the paragraph open with “this” or “these” plus a noun

Count one more hit per block where one listed opener, or one other linking adverbial, sits in the same position three times.

*Evidence: moderate. “Overall” is a measured ChatGPT preference (Sun et al., 2025), and “these” shows measured LLM excess in biomedical papers (Holzwarth et al., 2026). The others rest on learner-corpus studies and practitioner lists (Granger & Tyson, 1996; Lei, 2012). Connective chains also mark second-language writing, so a hit here says nothing about AI on its own. The signal is repetition and fixed position; a single connective says little.*

**8. Discourse scaffolding.** Phrases that narrate the structure of the essay rather than do the work: “We can see that”, “To further elaborate”, “It is important to note that”, “It is worth noting that”, “At the same time”, “This essay will”, “Here is a quick summary of”, “Going forward,” as an opener, and a reminder of something the reader plainly knows. One hit per use. Count “not only ... but also” from its second use in a block. “However” was on this list in earlier versions and is removed: it is the most common linker in published academic prose (Liu, 2008). GPTZero’s “Task-Oriented” and “Unnecessary Caveats” cover nearby ground. *Evidence: weak, except “this essay will”, which is a measured ChatGPT bundle (Jiang & Hyland, 2025a).*

**9. Summary and uplift closers.** A paragraph-final sentence that restates the paragraph, draws a moral, or ends on a vague hopeful note, including one that opens with “Overall,”, “Ultimately,”, “In summary,” or “In conclusion,”. Do not count sentences in the conclusion, where a summary belongs. A closing sentence that adds a new claim, finding or judgement is not a hit. *Evidence: moderate. Expert readers name vague, optimistic conclusions as a cue (Russell et al., 2025).*

**10. Cleft-construction transitions.** “What X has not yet done, and what Y...”, “What is striking is...”, “What matters here is...”. These are stock scaffolding for setting up a thesis statement. An it-cleft that answers a rival claim which the text has named is not a hit: “It was the fuel shortage that halted the advance.” *Evidence: untested.*

**11. Doublet redundancy.** Pairing two near-synonyms where one would do: “overlook or miss”, “opportunities and successes”, “key factors and drivers”, “issues and concerns”. A fixed legal or technical pair such as “terms and conditions” is not a hit. Neither is a pair whose two words mean different things. *Evidence: untested for synonym pairs. GPT-4o joins phrases with “and” at about 1.9 times the human rate (Reinhart et al., 2025).*

**12. Adverb-plus-adjective evaluative compounds.** “Uncomfortably correlated”, “broadly the same”, “remarkably consistent”, “significantly impacted”. These signal a stance without committing to evidence. A statistical term such as “significantly different” with its test is not a hit. *Evidence: untested.*

**13. Lexical fingerprints.** Density matters more than the presence of any single word. Never score a listed word in its technical or literal sense: “robust standard errors”, “word embedding”, “convergence” in mathematics, a carbon “footprint”. Four lists:

- **List A, measured excess in LLM text** (Kobak et al., 2025; Juzek & Ward, 2025; Russell et al., 2025): delve, underscore, intricate, crucial, pivotal, vibrant, tapestry. One hit per use. Add one high-weight hit (3 points) when three or more different List A words fall within a block; a List A word counts towards this rule even when it lies inside a longer hit. *Evidence: strong for scientific abstracts, moderate elsewhere.*
- **List B, measured for ChatGPT** (Sun et al., 2025): “such as”, “certainly”, “overall”. One hit for each of these used three or more times within a block. *Evidence: moderate.*
- **List C, house list**: footprint, doubling down, at industrial scale, structural pillar, nexus, corridor economy, convergence, magnifier, amplifying, embedding, robust, leverage (as a verb), navigate (used metaphorically), landscape (used metaphorically), in the realm of, testament to, multifaceted. One hit per use. *Evidence: untested.*
- **List D, promotional and dressed-up phrasing** (GPTZero, 2026a): “serves as” where “is” would do, “marks a pivotal moment”, “enduring legacy”, “nestled in the heart of”. One hit per use. GPTZero’s names for these are “Dressed-up Verbs”, “Overblown Importance” and “Sales-pitch Tone”. *Evidence: weak (vendor list).*

Word lists age. Marker words shift between model generations and fade once they become known. Human-feedback training (RLHF) is one likely source of the overused words, and readers reacted against “delve” once it was a known marker (Juzek & Ward, 2025). Models differ too: GPT-4o avoids joining clauses with “and”, while Llama models overdo it (Reinhart et al., 2025), and one expert reader spotted Claude text less well because he knew the vocabulary of ChatGPT (Russell et al., 2025). Treat these lists as dated October 2026. Give structure more weight than vocabulary.

**14. Generic content and vague attribution.** Two kinds of hit:

- **Phrase hit.** An appeal to unnamed authority: “studies show”, “experts agree”, “research suggests”, “many scholars”, “others argue”, with no study, expert or researcher named. One hit per phrase. GPTZero calls this “Phantom Experts”.
- **Paragraph hit.** In an essay, a report or an argument, a paragraph of three or more sentences that names no person, organisation, place, case, date, figure or source. Count it only where the paragraph has no phrase hit already. Skip short transactional messages.

*Evidence: moderate (Markey et al., 2024; Russell et al., 2025). Scientists named more researchers and used more numbers than ChatGPT, which preferred “others” (Desaire et al., 2023).*

**15. Faceless prose (robotic formality).** In an essay, a report or an argument, a paragraph of four or more sentences with fewer than two stance or engagement markers. Stance markers are a hedge tied to a claim (may, suggests, appears, probably), a booster (clearly, in fact), an attitude word tied to a claim (surprisingly, regrettably), and first person (I, we, our). Engagement markers are a real question, a direct address to the reader, an aside in brackets, and an approximation such as “roughly” or “about”. The stock phrases of categories 8 and 13 do not count as stance. Skip short transactional messages, and skip genres that bar first person and judgement, such as a methods section. This is the nearest measurable match for GPTZero’s “Robotic Formality”, a label that the vendor names and does not define. *Evidence: strong for essays. GPT-4 essays carried 12.26 stance markers per 1,000 words against 37.55 in student essays, with self-mention 97% lower (Jiang & Hyland, 2026). ChatGPT essays carried 41.1 metadiscourse markers per 1,000 words against 79.1 (Jiang & Hyland, 2025c), and fewer questions and asides (Jiang & Hyland, 2025b).*

**16. Monotonous syntax.** A GPTZero label, defined by the vendor as “Predictable, limited syntax variety results in repetitive and monotonous sentence structures.” Apply it to a block of ten or more sentences. Count one hit for each check that fires, to a limit of three hits per block:

- **No short sentences.** Fewer than one sentence in ten has 15 words or fewer
- **Same-length run.** Four consecutive sentences whose longest and shortest differ by three words or fewer
- **Same opening.** Four consecutive sentences that open with the same word
- **Repeated frame.** The same sentence skeleton (the same opening word type and the same clause order) three times in the block, or twice running, as in “By doing X, Y can Z”
- **Run-on.** A sentence of more than 40 words in which three or more clauses hang on commas. GPTZero’s labels here are “Run-On Sentences” and “Complex Sentences”
- **Stacked list.** A sentence with five or more comma-separated items of the same length and grammatical shape
- **Narrow range.** A block that uses fewer than two of the ten devices listed under “Sentence variety” in Part B. This is the check for prose that “lacks creative grammar”
- **Same-build paragraphs.** Three consecutive paragraphs of the same length and the same build: an opener, three points and a closer. Users report the GPTZero label “Formulaic Organization” for this

*Evidence: moderate. In news text, 32 to 33% of human sentences had 15 tokens or fewer, against 1 to 4% for 2025 instruction-tuned models (Gude et al., 2026). A repeated six-tag grammatical template appeared in 95% of model summaries of film reviews, against 38% of human ones (Shaib et al., 2024). Expert readers cited sentence structure in 35.9% of their explanations (Russell et al., 2025). The cut-offs above are judgement, and no study measures sentence openers.*

**17. Ungrounded speculation (speculative focus).** A forward-looking or consequence claim with no source, no stated condition, no evidence and no owner. The usual shape is a modal verb or the word “potential” joined to a vague outcome: “can lead to”, “could potentially transform”, “may reshape”, “the potential for”, “the future of”. One hit per sentence. A hedge on a specific, evidenced claim is never a hit. “Speculative Focus” is reported as a GPTZero label, but no vendor definition could be found, so this check rests on the research. *Evidence: moderate for the formulas. “Can lead to” was the second most frequent three-word bundle in GPT-4 essays, and “the potential for” and “the future of” were in the top eight (Jiang & Hyland, 2025a). “Potential” showed strong excess in 2024 PubMed abstracts (Kobak et al., 2025). LLM summaries overgeneralised research findings in 26 to 73% of cases (Peters & Chin-Yee, 2025). The link from these findings to the label is inference.*

### Low weight (0.5 points per hit)

**18. Mechanical precision.** A GPTZero label that the vendor names and does not define. The vendor’s page mentions needless technical jargon as a trait of AI text but does not tie it to this label, so the checks below are inferred. Count one hit for each of these:

- a technical or Latinate term where the passage’s own register would use a plain word, unless the term is the field’s standard name for the thing
- the same hedge or qualifier word on three or more claims in one paragraph (one hit per paragraph)

Sentences of even length and balanced lists also read as mechanical; categories 16 and 19 score those. *Evidence: weak (vendor label; components inferred).*

**19. Reflex triads.** A list of exactly three parallel items in two or more consecutive sentences, or more than one such list in a paragraph. A single list of three is not a hit. GPTZero calls this “Everything in Threes”. *Evidence: weak to moderate (practitioner lists and one vendor list; expert readers cite it under sentence structure).*

**20. Self-echoing.** The same decorative phrase used twice within a block: a figure of speech, an evaluative compound or a flourish of two or more words. A repeated technical term, name or key noun is never a hit; holding key terms fixed is how scholars tie a paragraph together. *Evidence: untested.*

**21. Formatting artefacts.** In text meant as an email, a letter or an essay: bullet points that each open with a bold label; headings in title case; stray Markdown marks such as asterisks or hash signs; emoji in formal text; straight and curly quotation marks mixed in one document. One hit per kind, per document. GPTZero says it does not score formatting. *Evidence: weak (practitioner lists).*

## What not to flag

Do not score these. In a rewrite, do not remove them as tells:

- **Hedges, boosters and attitude markers tied to a specific claim.** ChatGPT essays use far fewer of all three than student essays (Jiang & Hyland, 2025c, 2026). Hedge stacking was a category in earlier versions and is retired. The stock phrases in categories 8 and 13, the compounds in category 12 and the repeated hedge in category 18 are scored as such, whatever their type. Where two hedges sit on one claim, as in “may potentially”, the rewrite may keep one.
- **A plain connective used once.** “However”, “thus”, “therefore” and “also” are among the most common linkers in published academic prose (Liu, 2008; Lei, 2012). Joining clauses with “and” is fine too. Density and fixed position are scored under category 7, whatever the word.
- **Having connectives at all.** Text with fewer links does not read as more human. Human writers use more metadiscourse than ChatGPT does, and the gap is widest in stance and engagement (Jiang & Hyland, 2025c).
- **Subordinate clauses.** LLMs do not use fewer of them. Base models used more than journalists did (Muñoz-Ortiz et al., 2024).
- **Passive voice.** GPT-4o uses agentless passives at about half the human rate (Reinhart et al., 2025).
- **Clean grammar and a neutral tone.** Non-expert readers wrongly take a neutral tone for AI (Russell et al., 2025). Tone is scored only through category 15. Never add errors, typos or slang to a rewrite.
- **Contractions, or the lack of them.** Their rate varies about 25-fold across 2026 models (Rudnicka & Juzek, 2026).
- **Repeated key terms.** See category 20.
- **Direct quotations.** They are another writer’s words, and tells inside them score nothing.
- **American spelling.** Fix it under hard rule 2. It earns no points.

## Scoring rubric

Count the hits per category. Apply weights:

- High weight categories (0 to 6): each hit is worth 3 points
- Medium weight categories (7 to 17): each hit is worth 1 point
- Low weight categories (18 to 21): each hit is worth 0.5 points

For category 0, each em-dash counts as one hit, capped at 3 hits (9 points) per block, so a long article with many em-dashes does not swamp the score.

Scale the total to the length of the text:

- 300 words or fewer: the score is the raw total
- more than 300 words: score = raw total ÷ (word count ÷ 300), which gives points per 300 words

Rate on the unrounded score and show it to one decimal place:

- Under 2.5: Low. Few or no tells.
- 2.5 to under 5.5: Medium. Some tells. Acceptable for most internal use.
- 5.5 to under 9.5: High. Attentive recipients are likely to read it as AI-flavoured.
- 9.5 and above: Very High. The tells dominate, and most attentive readers will take it for AI drafting.

Two overrides apply regardless of the score. When one applies, say so on the rating line:

- The reversal ending (category 1) plus the cosmic-conclusion opener (category 2) in the same paragraph is an automatic Very High.
- Three or more em-dashes in the author’s own prose, counted before the cap, in a text of 300 words or fewer is an automatic Very High. In a longer text, the same applies at an average of three or more per 300 words.

Under 100 words there is too little text to rate with confidence. Report the hits and the rating, and add “low confidence” on the rating line.

### Worked scoring example

Passage, 45 words: “In an era of rapid change, leadership plays a crucial role in adoption, highlighting the need for training. Moreover, studies show that staff resist new tools. Furthermore, it is important to note that culture matters. Ultimately, AI is no longer a tool but a partner.”

| Hit | Category | Points |
|---|---|---|
| “In an era of” | 2 | 3 |
| “leadership plays a crucial role in adoption” (holds the List A word “crucial”) | 3 | 3 |
| “, highlighting the need for training” | 5 | 3 |
| “AI is no longer a tool but a partner” (also a closer; scored once, under the higher weight) | 1 | 3 |
| Moreover, Furthermore and Ultimately open sentences in one paragraph | 7 | 1 |
| “it is important to note that” | 8 | 1 |
| “studies show” | 14 | 1 |
| Four sentences with no stance or engagement marker | 15 | 1 |

Raw total: 16.0 over 45 words. The text has 300 words or fewer, so the score is 16.0. Rating line: Very High (low confidence) (override: categories 1 and 2 in one paragraph).

## Output format for the audit

Use this structure:

```
## Audit

Overall rating: [Low / Medium / High / Very High] [add “(low confidence)” under 100 words; add “(override: ...)” when one applies]
Score: X.X per 300 words (raw Y.Y points over N words)
Tally: [category number: points; ...; list only the categories with points]

### Hits found

**Category N: [Name]** (weight: high/medium/low; evidence: [the grade given in the category]; points: P)

> [verbatim quote from the text]

[brief explanation of why this is a tell]

[repeat for each hit, in category order; hits in one category may share one heading]

### Verdict

[1 to 3 sentences explaining the most damaging patterns and what fixing them would do]

### Hot spots

[only for a text over 600 words: the two paragraphs with the most points]

### House style

[audit-only mode, and only when needed: American spellings found, each with its British form; dashes found inside quotations, titles or citations]

### For the author to supply

[only when needed: the named sources, cases, figures, conditions or judgements that the text lacks and that a rewrite cannot add without inventing them]
```

For a passage of 300 words or fewer, write the score line as “Score: X.X (N words)”. For a paragraph-level or block-level hit, quote the first few words of the paragraph or block. If no category fires, write “None” under Hits found, give the score as 0.0 and rate the text Low.

## Rewrite principles

Hard rule 3 governs every step below. A fix that needs new content becomes an [AUTHOR: ...] marker.

1. Remove every em-dash and en-dash, as hard rule 1 sets out. The rewrite must contain zero long-dash characters.
2. Cut the reversal ending. Keep the claim and state it flat. Use a concrete consequence only if the source gives one.
3. Cut the cosmic-conclusion opener. Start the sentence with its actual subject.
4. Give an abstract subject a concrete actor only if the source names that actor in the same paragraph or the one before. “The convergence produces risk” becomes “Both banks now face the same failure modes” where the source has already named the banks and the failure modes. If the source names no actor, turn the nominalisation into a verb where that needs no new actor, and mark the gap.
5. Cut participle tails. End the sentence on the claim. If the tail held a real point, give it a sentence of its own with a subject and a finite verb. If it held nothing, delete it.
6. Break four-part anaphora and reflex triads only where items repeat or pad. Keep every item that carries its own content, and vary the openers instead.
7. Strip discourse scaffolding. “We can see that HSBC has consolidated” becomes “HSBC has consolidated”. Keep the connectives that carry logic.
8. Thin the stock connective chains until no more than one sentence in three opens with a linking adverbial. Then rebuild the joins with the techniques in Part B. Join two sentences only with a relation that the source states or that its own words entail. Where the author merely listed points, use word order, a repeated term or a pronoun, or leave two sentences. Plain “and” asserts no relation, so it is allowed; keep any date, place or condition with the clause it came from.
9. Fix the closers. Delete a closing sentence only if it adds no claim: a pure restatement or a bare claim of importance. If it carries the author’s only conclusion, keep the claim and state it plainly. Once an empty closer is cut, let the paragraph end where it then ends. Do not move sentences.
10. Collapse a doublet to one word where the two words mean the same. Cut an adverb-plus-adjective evaluative compound unless it is doing real work.
11. Replace lexical fingerprints with plainer alternatives. “Footprint” becomes “presence” or is deleted. “Doubling down” becomes “focusing more on”. “At industrial scale” is deleted, or becomes the number if the source gives one. Where a word only claims importance (“crucial”, “pivotal”), give the reason if the source states it, or cut the claim.
12. Mark unsupported attribution. Where the text says “studies show” and names no study, keep the claim, add [AUTHOR: which study?], and list it.
13. Ground speculation. For each ungrounded forward-looking claim, try in order: attribute it to a source that the text gives; state a condition that the text gives; anchor it to evidence in the text. If the text offers none of these, add [AUTHOR: source, condition or evidence?]. Cut the sentence only if it adds no claim. In a short message meant to be sent as it stands, keep one plain hedge and list the gap in the notes (hard rule 3).
14. Keep stance. Leave hedges, boosters, judgements and first person as they are. Add a hedge only where the source states the limit, and report it in the notes. Do not strip hedges to sound confident.
15. Restore short sentences. In a paragraph of four or more sentences, at least one sentence should have 15 words or fewer. Let a short sentence carry a finding or a limit. Never pad or split a sentence only to change its length, and never alternate long and short on a schedule.
16. Widen the range of sentence forms with the devices under “Sentence variety” in Part B, each used for a reason. Split a run-on of more than 40 words at its main joint.
17. Swap needless jargon for the plain word, unless the term is the field’s standard name.
18. Remove chatbot residue and formatting artefacts. Take the bold off bullet labels and keep the words. If the residue is a closing offer of help or detail, keep the offer in plain words (“Ask me if you want more detail.”) and cut only the stock phrasing. Use one style of quotation mark throughout: the style of the source, or of the destination if the user names one.
19. Never add errors, typos or slang to make text seem human.
20. Convert every American spelling to British, as hard rule 2 sets out.
21. Match the author. Where the source or the user gives a sample of the author’s own writing, match its sentence length, person and formality. One house voice across many writers becomes a fingerprint of its own.
22. Check the result. Run the invention check in hard rule 3. In full mode, score the rewrite again. Reread each pair of neighbouring sentences and fix any abrupt join. If any sentence still sounds like a TED talk caption, state its claim in plain words, and cut it only if it adds no claim.

## Output format for the rewrite

Give the rewrite in every mode that asks for one, in this structure:

```
## Rewrite

[the rewritten text, with the paragraph breaks of the source and any [AUTHOR: ...] markers]

### Notes on the rewrite

Score before: X.X. Score after: X.X. [full mode only]
Cut or merged: [each sentence cut, or joined to another, with the reason]
Altered in quoted matter: [each dash replaced inside a quotation, a title or a citation, with a reminder to restore the original character wherever exact quotation is required]
Spelling changed: [each American spelling changed to British]
Hedges added: [each hedge added, with the limit that the source states]
Other changes: [phrases cut, sentences split, dashes replaced in the author’s own prose]
Techniques used: [numbers of the joining techniques and sentence-variety devices used in Part B]
For the author to supply: [every [AUTHOR: ...] marker; in full mode, also each category 14 or 15 gap that fired]
```

Leave out a line of the notes when it has nothing to report. In rewrite-only and smoothing-only modes, leave out the scores.

## What to preserve

The rewrite removes the signature and keeps the substance. It must not make the text sound simpler than its author. Keep:

- All factual claims and numbers
- The argument structure and the order of ideas
- Specialist vocabulary that is genuinely needed (sukuk, IMEC, post-quantum, tokenisation)
- The author’s stated stance, including hedges that match real limits in the evidence
- Citations and direct quotations, word for word and in their original spelling, apart from the dash rule in hard rule 1
- The author’s own conclusions, even where their wording has to change

## Limits

- The rating estimates how the text reads to an attentive person. It does not predict what Turnitin, GPTZero, Pangram or any other classifier will return, because those tools score statistics across the whole text. No rewrite guarantees that a text will not be flagged.
- A rating describes the text and settles nothing about who wrote it. No single tell proves anything, and people produce every pattern on this list. Never use a rating as proof that someone used AI. If the user says a text is their own unaided work, take that as given.
- In one 2023 study, seven detectors wrongly flagged 61% of essays by non-native English writers on average (Liang et al., 2023). Vendors report much lower rates in their own tests (section C4). Category 7 in particular marks second-language writing as much as AI.
- A rewrite made with this skill is itself AI-edited text. Many detectors flag lightly AI-polished human writing as AI (Saha & Feizi, 2025). For work that a detector will check, the safer use is the audit: read the hits, then make the edits by hand.
- Anthropic states that text from the Claude models on its list carries a watermark (Anthropic, 2026a, 2026b). A rewrite that Claude produces with this skill is covered if the model is on that list. Google marks Gemini text (Dathathri et al., 2024). This skill cannot see, weaken or remove a watermark, and it does not try to. Section C3 gives the detail.
- In one independent test, the strongest commercial classifier and experienced readers kept catching edited text (Russell et al., 2025).
- The labels that a detector shows beside a sentence describe style. They are not a read-out of the detector’s decision (section C1), and fixing a labelled sentence may leave the score unchanged.
- The word lists and the dated facts are from October 2026. If today’s date is later, say that they may be out of date.
- This skill edits style. Any duty to disclose AI use to a university, publisher or client still applies.

# Part B. Writing reference

Part B holds the methods for the rewrite. Hard rule 3 applies throughout: every Before and After pair below keeps the same facts, and a move that needs new content becomes an [AUTHOR: ...] marker.

## The ten-pass edit

For a text of more than three paragraphs, work in this order. The rewrite principles give the fix for each item. This list gives the order.

1. **Reverse outline.** Note one line per paragraph for yourself. If the order of ideas is the problem, say so in the verdict or the notes. Do not reorder the argument unless the user asks.
2. **Connective audit.** Thin the linking adverbials until no more than one sentence in three opens with one.
3. **Position check.** Move some uses of “however” and “therefore” inside the sentence.
4. **Ban-list sweep.** Find Additionally, Overall, Ultimately, Notably, Importantly, crucial, pivotal, delve, underscore, tapestry, “it is important to note”, and Moreover and Furthermore in series. Apply rewrite principles 7, 8 and 11 to each.
5. **Given-new pass.** Each sentence opening links back to something already said.
6. **“This” pass.** A noun follows every “this”, and no paragraph has more than two such links.
7. **Density pass.** Turn some nominalisations back into verbs with actors that the source names.
8. **Tail pass.** Cut “, highlighting”, “, underscoring” and “, reflecting” endings.
9. **Specificity and stance pass.** Each paragraph of an argument should carry one named case or figure and one judgement. These come from the author. Mark a gap only where category 14 or 15 fired, and never fill it.
10. **Rhythm pass.** Check sentence lengths paragraph by paragraph and break up runs of similar length.

## Joining sentences

Published scholars link most sentences through word order, repeated terms and grammar, and they lean on a narrow core of plain connectives (Liu, 2008; Lei, 2012). Use the techniques below before reaching for a linking adverb. Join two sentences only with a relation that the source states or that its own words entail. Each technique gives the method, a before and after, the common mistake and a check.

### Between two sentences

**1. Given-new order.** Open each sentence with something the reader already has, and end it on the new point. Each opening then echoes the end of the sentence before.

- Before: “Firms set up AI steering committees. Clear accountability for errors was the reason that managers gave for them.”
- After: “Firms set up AI steering committees. The reason managers gave for them was clear accountability for errors.”
- Mistake: opening with a long new phrase that the reader cannot place.
- Check: the first five words of each sentence connect to something already said.

**2. Topic and stress positions.** The opening of a sentence tells the reader whose story it is, and the end carries the emphasis (Gopen & Swan, 1990; Williams & Bizup, 2017). Put the point to stress at the end, then start the next sentence with it.

- Before: “Middle managers shape adoption in most firms. They decide which tools staff try.”
- After: “In most firms, adoption is shaped by middle managers. Those managers decide which tools staff try.”
- Mistake: ending on a weak tag such as “in many cases”.
- Check: the last three words of each sentence are the words that matter.

**3. Key-term repetition.** Pick two or three key terms and keep them fixed. Change the word only when the meaning changes (Halliday & Hasan, 1976; Hoey, 1991). Merge two terms only where the source shows that they name one thing.

- Before: “Deterrence failed in 1914. The dissuasion posture of the powers was weak. Their coercive stance lacked credibility.”
- After: “Deterrence failed in 1914. The deterrence that the powers practised was weak, and it lacked credibility.”
- Mistake: elegant variation, which makes the reader think three different things are meant.
- Check: mark the key term in each sentence. If its name changes, ask whether the concept did.

**4. Reference words.** Point back with one clear pronoun or demonstrative: it, they, this, that, these (Halliday & Hasan, 1976). The reader has to look back to decode the word, so the two sentences read as one unit.

- Before: “The board rejected the two proposals. The board gave no reasons.”
- After: “The board rejected the two proposals. It gave no reasons.”
- Mistake: a pronoun that could point to two different nouns.
- Check: trace each pronoun back to its noun. If it could point to two nouns, repeat the noun.

**5. “This” plus a summary noun.** Name what the previous sentence did (a trend, a claim, a delay, a change), then open the next sentence with “this” plus that noun (Francis, 1994; Swales & Feak, 2012).

- Before: “Ministries delayed procurement for two years. This meant that rivals gained ground.”
- After: “Ministries delayed procurement for two years. This delay let rivals gain ground.”
- Mistake: a bare “this”. Overuse is the newer risk, since “these” shows measured LLM excess (Holzwarth et al., 2026).
- Check: a noun follows every “this”, and no paragraph has more than two such links.

**6. Subordination.** Join two short related sentences with although, because, whereas, since or given that, or with a relative clause. Put the main idea in the main clause. The grammar states the relation, so no adverb is needed.

- Before: “The policy was popular. However, it was not enforced.”
- After: “Although the policy was popular, it was not enforced.”
- Mistake: three subordinate clauses in one sentence, or a subordinator that asserts a relation the author never stated.
- Check: each sentence has one main claim that is easy to find.

**7. Colon, semicolon and parallel structure.** Use a colon when the second part explains the first. Use a semicolon for two equal, related clauses. Keep the items of a list or a comparison in one grammatical form.

- Before: “The doctrine had one flaw. It assumed rational opponents.”
- After: “The doctrine had one flaw: it assumed rational opponents.”
- Mistake: a semicolon between unrelated clauses, or a colon reveal in every paragraph.
- Check: replace the colon with “namely”. If the sentence still reads well, the colon fits.

**8. Nominalisation as a hinge, used sparingly.** Turn the verb of the previous sentence into the subject of the next one, once, then go back to verbs.

- Before: “Staff resisted the new appraisal tool. Because of this, managers went back to paper forms.”
- After: “Staff resisted the new appraisal tool. That resistance sent managers back to paper forms.”
- Mistake: doing it in every sentence. Nominalisation density is a strong tell (category 3).
- Check: no more than one nominalised subject in any two sentences.

**9. Coherence relations.** Name the relation between each pair of sentences in one word: cause, contrast, elaboration, resemblance or sequence (Kehler, 2002; Mann & Thompson, 1988; Pinker, 2014). Where the source states the relation, let the grammar or a moved phrase carry it. Where no word fits, the pair may be out of order: say so in the verdict or the notes, and do not invent a link. Add an explicit connective only where the relation would surprise the reader. A time or place phrase that the source already holds can carry the relation once it moves to the front, as long as it still governs only the clause it governed in the source.

- Before: “The firm cut training budgets in 2023. Turnover among new hires doubled within a year.”
- After: “The firm cut training budgets in 2023. Within a year, turnover among new hires had doubled.”
- Mistake: “Furthermore” on a pair that is really a contrast.
- Check: name the relation for each pair.

### Across a paragraph

**10. Thematic progression.** Look at the opening of each sentence and choose one pattern (Daneš, 1974). Linear: the end of one sentence becomes the opening of the next. Use it for a chain of argument. Constant: every sentence opens on the same theme. Use it to follow one actor. Derived: each sentence opens on a part of one larger theme. Use it to compare parts.

- Before: “The merger doubled the number of reporting lines. Managers had more meetings because of the extra lines. Decisions slowed as a result of those meetings.”
- After (linear): “The merger doubled the number of reporting lines. Those lines brought managers more meetings, and the meetings slowed decisions.”
- Mistake: random openings, so that each sentence starts a new story.
- Check: list the sentence openings one under another. A pattern should show.

**11. Clause relations.** Use a pattern that readers expect: situation, problem, response, evaluation; or general then particular; or claim then counterclaim (Hoey, 1983). Give each slot one or two sentences, and keep the evaluation that the author gives.

- Before: “Many firms use AI to screen applicants. Some of the models reject qualified candidates from under-represented groups. Yearly bias audits are one response. But an audit catches only what it measures.”
- After: “Many firms use AI to screen applicants, and some of the models reject qualified candidates from under-represented groups. One response is a yearly bias audit, but an audit catches only what it measures.”
- Mistake: stopping at the response with no evaluation.
- Check: label each sentence with its slot.

**12. Paragraph architecture.** State the claim of the paragraph in its topic sentence. Open the paragraph by echoing a key term from the end of the previous one. Inside the paragraph, the usual order is claim, evidence, meaning. Note a different order in the verdict, and do not move sentences. For an introduction, the three CARS moves are: establish a territory, establish a niche, occupy the niche (Swales, 1990). A paragraph can also move between concrete evidence and higher abstraction, as in the Uneven U (Hayot, 2014).

- Previous paragraph ends: “The training data do not explain the gap between sites.”
- Before: “Another important factor is leadership.”
- After: “Leadership is another factor in that gap.”
- Mistake: “Another factor is” openings, which list where they should argue.
- Check: read only the first sentence of every paragraph. Together they should read like an abstract.

### Across the argument

**13. Metadiscourse with a purpose.** Metadiscourse is language about the text and about the writer’s stance: transitions, frame markers, code glosses, evidentials, hedges, boosters, attitude markers, self-mention and engagement markers (Hyland, 2005a). Human writers use far more of the stance and engagement kinds than ChatGPT does (Jiang & Hyland, 2025c). A calibrated hedge marks a claim as plausible reasoning short of certain knowledge, and its strength matches the evidence (Hyland, 2005b). In a rewrite, hedge only where the source states the limit, and never add a judgement that the author did not make.

- Before: “Our results show that remote work increases productivity. Our data come from one firm, and selection cannot be ruled out.”
- After: “Our results suggest that remote work raised productivity in this firm, though we cannot rule out selection.”
- Mistake: boosters everywhere (“clearly”, “undoubtedly”).
- Check: every hedge matches a limit that the text states.

**14. Source integration.** Make citations carry the argument (Graff & Birkenstein, 2021). Group the sources by position. Cite integrally the view that the text engages, with the name inside the sentence, as in “Freedman argues”. Keep the other citations non-integral, in brackets. Use a reporting verb only as strong as the text supports: argues, shows, assumes, overlooks. The author’s reply, a concession followed by a rebuttal, has to come from the author. The names in the example are invented for illustration.

- Before: “Studies show that remote work raises output (Lee, 2021; Okafor, 2022). Others disagree (Brandt, 2023).”
- After: “Lee (2021) and Okafor (2022) find that remote work raises output; Brandt (2023) disputes this. [AUTHOR: your own position, and the reason for it.]”
- Mistake: “studies show” with no study named.
- Check: every claim about the literature names who made it.

**15. Rhythm, specificity and voice.** Vary sentence length. After a sentence of more than 30 words, a sentence of 15 words or fewer lands the point. One named case, date or figure per paragraph anchors an abstract claim, and one stated view per paragraph gives the text a voice (Sword, 2012; Becker, 2007). The case, the figure and the view come from the author.

- Before: “AI adoption in organisations presents numerous challenges and opportunities that require careful consideration by leaders.”
- After: “AI adoption in organisations presents numerous challenges and opportunities that require careful consideration by leaders [AUTHOR: which challenge, in which case, with what figure?].”
- Mistake: uniform sentences of medium length, or a particular made up to fill the gap.
- Check: count the words per sentence in one paragraph. There should be a spread.

## Sentence variety

These ten devices are what “creative grammar” means in scholarly prose: variation in sentence form that serves a purpose (Kolln & Gray, 2017). Two limits apply to all of them: reach the verb quickly (Williams & Bizup, 2017), and end on the new point (Gopen & Swan, 1990). Category 16 counts how many of the ten a block uses.

**1. Short linking opener.** A brief adverbial before the subject ties the sentence to the one before.

- Before: “Turnover doubled within two quarters of the reform.”
- After: “Within two quarters of the reform, turnover doubled.”
- Mistake: an opener of more than 12 words, or a stock transition.
- Check: the opener points back to something already said.

**2. Clause order for end weight.** Arrange the clauses so that the new point comes last.

- Before: “Adoption stalled, although the pilot met every target.”
- After: “Although the pilot met every target, adoption stalled.”
- Mistake: flipping every sentence.
- Check: the ending feeds the next sentence.

**3. Short sentence after a long one.** Use a sentence of 15 words or fewer for a finding or a limit (Sword, 2012; Tufte, 2006).

- Before: “The restructuring removed two management layers and merged four regional units, and line managers were not told.”
- After: “The restructuring removed two management layers and merged four regional units. Line managers were not told.”
- Mistake: an empty slogan.
- Check: the short sentence makes a claim that could be false.

**4. Cumulative sentence.** Put the main clause first, then add free modifiers that carry evidence (Christensen, 1963).

- Before: “The brigade dropped its timetable. The timetable was already broken by the lost bridge.”
- After: “The brigade dropped its timetable, already broken by the lost bridge.”
- Mistake: a trailing -ing comment, which is category 5.
- Check: each modifier adds a fact.

**5. Appositive.** A noun phrase that renames its neighbour defines a term in passing (Kolln & Gray, 2017; Tufte, 2006).

- Before: “Project Atlas was the firm’s first shortlisting tool. It was withdrawn after six weeks.”
- After: “Project Atlas, the firm’s first shortlisting tool, was withdrawn after six weeks.”
- Mistake: an appositive that only praises.
- Check: the phrase would serve as a glossary entry.

**6. Relative clause variety.** Use who, which, or a preposition plus which to fold a fact into its noun.

- Before: “The regiment held the ridge for two days. During those two days its supplies were cut.”
- After: “The regiment held the ridge for two days, during which its supplies were cut.”
- Mistake: stacked relative clauses.
- Check: one clause per noun, with a clear antecedent.

**7. Colon or semicolon.** A colon announces an explanation. A semicolon joins two full clauses. Joining technique 7 gives the example.

- Mistake: a colon straight after a verb.
- Check: a full clause stands before the mark.

**8. A real question.** Ask a question that the paragraph then answers (Sword, 2012). ChatGPT essays use fewer questions than student essays (Jiang & Hyland, 2025b).

- Before: “It is necessary to consider why the reform failed in the north. Shift patterns offer one answer.”
- After: “Why did the reform fail in the north? Shift patterns offer one answer.”
- Mistake: a question as a hook in every section.
- Check: evidence follows at once.

**9. Bracketed aside.** Put a short caveat in round brackets. Human writers use more of these than ChatGPT does (Jiang & Hyland, 2025b).

- Before: “The response rate was 38 per cent. This is low for a staff survey.”
- After: “The response rate was 38 per cent (low for a staff survey).”
- Mistake: hiding the main point in brackets.
- Check: the sentence stands without the brackets.

**10. Cleft or fronting.** Use “It was X that”, or move an element to the front, to answer a rival claim that the text has named (Kolln & Gray, 2017).

- Before: “Staff blamed the weather. The fuel shortage halted the advance.”
- After: “Staff blamed the weather. It was the fuel shortage that halted the advance.”
- Mistake: inversion with nothing to contrast. A “What matters here is” frame is category 10.
- Check: the rival claim can be named.

### What not to do

- Do not add deliberate errors. Expert readers take slips as human (Russell et al., 2025), but errors cost credibility, and no study shows a benefit.
- Do not force fragments into academic text, invert without a contrast, or reach for purple prose.
- Do not vary on a schedule. Alternating long and short sentences, or rotating openers, is a new template (Shaib et al., 2024).
- Do not open with stock transitions or with long clauses that delay the verb.
- Do not open with participial phrases or close with -ing comments. LLMs overuse both (Reinhart et al., 2025).
- Do not stack clauses or chain them with commas. GPTZero labels run-on and complex sentences as AI features.
- Do not use triads or “not only ... but also” for balance.
- Do not tune a text to a detector score. Detectors err, and most of all on non-native writers (Liang et al., 2023).

## Nine fixes for formality, mechanical precision and speculation

Fixes 1 and 2 answer robotic formality. Fixes 3 to 6 answer mechanical precision. Fixes 7 to 9 answer speculation. Most of them need something from the author, so in a rewrite the After is often a marker.

| Fix | Move | Before | After in a rewrite |
|---|---|---|---|
| 1. Restore the agent | Turn abstract nouns into verbs and name who acted | “The implementation of the appraisal system resulted in a reduction of managerial discretion.” | “[AUTHOR: who?] implemented the appraisal system, and as a result managers had less discretion.” |
| 2. Own the claim | Use “I” or “we” for the author’s own judgement, where the genre allows | “It can be argued that leader support is relevant to AI adoption.” | “It can be argued that leader support is relevant to AI adoption [AUTHOR: is this your own claim? If so, write it in the first person].” |
| 3. Unbalance the list | Keep the items that matter and rank them | “Sea power gives a state reach, flexibility and endurance.” | “Sea power gives a state reach, flexibility and endurance. [AUTHOR: which of the three matters most here?]” |
| 4. Let logic carry the link | Delete the stock connector and state the relation | “It is important to note that the training budget was cut. In addition, turnover increased.” | “The training budget was cut, and turnover increased. [AUTHOR: did one cause the other, or only follow it?]” |
| 5. Vary length by job | Short sentences for claims, longer ones for evidence | “The policy ran in three regions. It was reviewed after six months. Two showed gains.” | “The policy ran in three regions and was reviewed after six months. Two showed gains.” |
| 6. Name the particular | Replace a generic actor with the case, the figure or the source | “Many organisations have seen significant productivity gains from AI tools.” | “Many organisations have seen significant productivity gains from AI tools [AUTHOR: which organisations, how large a gain, what source?].” |
| 7. Attribute it | Give the forecast to a named source | “AI could potentially transform recruitment.” | “AI could transform recruitment [AUTHOR: who predicts this, and where?].” |
| 8. State the condition | Say when the outcome follows | “Drone swarms could change the character of land warfare.” | “Drone swarms could change the character of land warfare [AUTHOR: under what condition?].” |
| 9. Anchor it or cut it | Tie a forward-looking sentence to something observed, or delete it | “Going forward, these developments could reshape the future of strategic planning.” | “These developments could reshape the future of strategic planning [AUTHOR: what has already been observed?].” Cut the sentence only if it adds no claim, and log the cut |

Common mistakes: guessing an unnamed agent; “I think” on settled facts; trimming a real three-part finding; deleting a “however” that carries a real contrast; inventing the figure; “experts say”; stacked hedges such as “may potentially”; swapping one generality for another.

## Connectives by function

Use a connective only after the techniques above. The risk ratings are a synthesis from the research review; no study measured them directly. Low means common in published prose with no measured AI excess. High means measured or widely reported AI excess, or a strong novice signal.

- **Low:** use freely, with variety
- **Medium:** at most once in 300 words
- **High:** cut, or allow once in a whole document

### Addition

| Connective | Risk | Basis | Position | Punctuation | Example or advice |
|---|---|---|---|---|---|
| also | Low | Top item in published articles (Lei, 2012) | Mid-sentence, before the verb | None | “Line managers also shaped uptake.” |
| and, joining clauses | Low | Core coordinator; GPT-4o under-uses it (Reinhart et al., 2025) | Between clauses; sometimes sentence-initial | Comma before a long new clause | “The pilot ended, and the team went back to spreadsheets.” |
| in addition | Medium | Common; learner overuse (Lei, 2012) | Initial, sparingly | Comma after | “In addition, the survey covered contractors.” |
| moreover, furthermore | Medium; high if repeated | Used less than “also”; learner overuse; practitioner lists | Initial | Comma after | Prefer “also” or a given-new link |
| additionally | High | Less common; practitioner lists | Avoid | n/a | Use “also” |

### Contrast

| Connective | Risk | Basis | Position | Punctuation | Example or advice |
|---|---|---|---|---|---|
| however | Low to medium | Most frequent academic linker (Liu, 2008); the risk lies in repetition | Medial, after the subject | Commas around it | “The pilot, however, excluded night shifts.” |
| but | Low | Core | Mid or initial | No comma after an initial “But” | “But the data end in 2019.” |
| yet | Low | Common | Initial or mid | Comma before it when mid | “The ceasefire held, yet both armies kept their reserves forward.” |
| by contrast, in contrast | Low | Frequent (Liu, 2008) | Initial or medial | Comma | “Firm B, by contrast, trained managers first.” |
| instead, rather | Low | Frequent (Liu, 2008) | Initial or medial | Comma when initial | “Rather, the threat was implicit.” |
| on the other hand | Medium | Common in learner writing; a novice signal | Only after “on the one hand” | Comma | Use “by contrast” |

### Concession

| Connective | Risk | Basis | Position | Punctuation | Example or advice |
|---|---|---|---|---|---|
| although, though | Low | Frequent (Liu, 2008) | Fronted or final clause | Comma after a fronted clause | “Although more staff signed up, few used the tool each week.” |
| while, whereas | Low | Common | Mid or initial | Comma | “Whereas HR led in Firm A, IT led in Firm B.” |
| still | Low | Common | Initial | Comma optional | “Still, the model ignores alliances.” |
| admittedly | Low to medium | Moderate use | Initial | Comma | “Admittedly, the sample is small.” |
| that said | Medium | Moderate use; practitioner lists | Initial | Comma | Use once at most |

### Cause and result

| Connective | Risk | Basis | Position | Punctuation | Example or advice |
|---|---|---|---|---|---|
| thus | Low | Top academic linker (Liu, 2008; Lei, 2012) | Medial, before the verb | Often no commas | “The delay was thus costly for both firms.” |
| therefore | Low | Top academic linker (Liu, 2008) | Medial or initial | Commas in long clauses | “The claim therefore needs a test.” |
| so | Low to medium | Frequent in speech; informal in academic prose | Joining clauses | Comma before it | “Costs rose, so firms paused hiring.” |
| because, since, given that | Low | Core subordinators | Mid-sentence | No comma before “because” | “Firms waited because rules were unclear.” |
| hence | Low | Common | Initial, before a noun phrase | None | “Hence the turn to pilots.” |
| consequently | Medium | Common; on practitioner lists when initial and repeated | Initial, rarely | Comma | Prefer “thus” |

### Example and restatement

| Connective | Risk | Basis | Position | Punctuation | Example or advice |
|---|---|---|---|---|---|
| for example, for instance | Low | Apposition is the second most common linking function (Liu, 2008) | Initial or medial | Commas | “Some ministries, for instance, banned the tool.” |
| such as | Medium | Very common; ChatGPT-preferred (Sun et al., 2025) | Before a list | No comma when restrictive | Vary with “including” or a named case |
| that is (or i.e.) | Low | Common | Medial | Commas | “The second strike, that is, the retaliatory force...” |
| in other words | Medium | Common; novice overuse | Initial | Comma | Use only when the restatement is simpler |
| in turn | Low | Common | Medial | Commas optional | “The bank trained its managers, who in turn trained their teams.” |

### Sequence and summary

| Connective | Risk | Basis | Position | Punctuation | Example or advice |
|---|---|---|---|---|---|
| first, second | Low to medium | Common; “firstly” and “secondly” flagged in learner studies | Initial | Comma | Prefer “first” to “firstly” |
| then, next | Low | Common | Initial or medial | Comma optional | “The board then reversed course.” |
| finally, lastly | Medium | Common; a novice signal in lists | Initial | Comma | Use once |
| overall | High | Common; ChatGPT-preferred (Sun et al., 2025) | Avoid at the start of a paragraph | n/a | End on the finding |
| in conclusion, in summary | High | Common in student essays; compulsive summaries on practitioner lists | Only in a true conclusion | Comma | Use a heading |
| ultimately | High | Moderate use; practitioner lists | Avoid as a closer | n/a | Cut |
| notably, importantly | High | Moderate use; inflated significance (Russell et al., 2025) | Avoid at the start of a sentence | n/a | Give the reason, if the source has one |

### Stock phrases to cut

“plays a crucial role”, “it is important to note”, “it is worth noting”, and “not only ... but also” as a cadence.

### Position and density

- Move “however”, “therefore” and “thus” inside the sentence some of the time.
- Put “also” before the verb.
- Use no comma after a sentence-opening “But” or “Yet”.
- Let no more than one sentence in three open with a linking adverbial.
- Never run Moreover, Furthermore and Additionally in series.

No connective is safe by itself. Readers and detectors respond to density, repetition and fixed position across the whole text. Disciplines also differ in how often they use linking adverbials (Peacock, 2010), so match the field.

## Worked example: one paragraph rebuilt in stages

**Original, abrupt.** “Deterrence depends on credibility. Credibility is hard to build in cyberspace. Moreover, cyber operations are hard to attribute. Furthermore, a state that cannot name its attacker cannot credibly threaten punishment. As a result, leaders often absorb attacks. Additionally, allies can supply attribution evidence that a state lacks. However, shared attribution is slow, so punishment comes late. Overall, cyber deterrence plays a crucial role in modern strategy.”

**Stage 1: stock openers cut, and the empty closer cut.** “Deterrence depends on credibility. Credibility is hard to build in cyberspace. Cyber operations are hard to attribute. A state that cannot name its attacker cannot credibly threaten punishment. As a result, leaders often absorb attacks. Allies can supply attribution evidence that a state lacks. However, shared attribution is slow, so punishment comes late.”

**Stage 2: given-new order, with two pairs joined by “and”.** “Deterrence depends on credibility, and in cyberspace credibility is hard to build. Cyber operations are hard to attribute, and a state that cannot name its attacker cannot credibly threaten punishment.”

**Stage 3: a short sentence that keeps the stated result.** “Leaders therefore often absorb attacks.”

**Stage 4: subordination for the stated contrast.** “Although allies can supply attribution evidence that a state lacks, shared attribution is slow, so punishment comes late.”

**Final.** “Deterrence depends on credibility, and in cyberspace credibility is hard to build. Cyber operations are hard to attribute, and a state that cannot name its attacker cannot credibly threaten punishment. Leaders therefore often absorb attacks. Although allies can supply attribution evidence that a state lacks, shared attribution is slow, so punishment comes late.”

**Notes on the rewrite.** Cut: “Overall, cyber deterrence plays a crucial role in modern strategy”, a bare claim of importance that adds no claim. For the author to supply: a named case, date or figure, since the paragraph still has none (category 14).

Techniques used: given-new order (1), a stated relation moved inside the sentence (9), subordination (6) and a short sentence after a long one (variety device 3). Every fact and every stated relation in the final version is in the original, and the two uses of “and” assert nothing new. The sentences run to 12, 18, 5 and 18 words.

# Part C. Research reference

Part C is reference material: for explaining a rating, for questions about detectors, and for thesis work on AI detection. Facts are dated October 2026 unless a line gives another date. When passing one on, give its date and its source. If a full reference is not listed at the end of this file, say so; never complete one from memory. A full reference lists every author, the year, the title and the venue or link. An entry that has “et al.” in place of some authors, or has neither a venue nor a link, is partial: give it as listed and say so. Say “undated” where a source has no date. Vendor statements are marked as such and count as claims.

## C1. Detector labels and where this skill covers them

### GPTZero sentence labels

GPTZero shows short labels with explanations beside high-impact sentences, in a feature called “Natural Language Explanations” within Advanced Scan. It launched on 10 June 2025 and was described as beta (GPTZero, 2025). GPTZero publishes only some of its labels. It reports that a classifier trained only on these features reached “around 90%” accuracy (GPTZero, 2025), which makes the labels a description of style that sits beside the detector. They are not a read-out of its decision. GPTZero (2023) is reported to have said that removing a highlighted sentence may not lower the score, because the model weighs the whole document; this was not re-checked.

| Label | Side | Vendor definition | Status | Covered by |
|---|---|---|---|---|
| Monotonous Syntax | AI | “Predictable, limited syntax variety results in repetitive and monotonous sentence structures.” | Published | Category 16 |
| Run-On Sentences | AI | “The sentence structure is long and run-on with multiple clauses connected by commas.” | Published | Category 16, run-on check |
| Task-Oriented | AI | “The writing structure is linear and task-oriented, focusing on addressing the user’s request directly.” | Published | Categories 6 and 8 |
| Robotic Formality | AI | None published | Named, undefined | Category 15, with 3 and 16 |
| Mechanical Precision | AI | None published. The page mentions needless technical jargon as a trait of AI text but does not tie it to a label | Named, undefined | Category 18, with 16 and 19 |
| Complex Sentences | AI | None published | Named, undefined | Category 16, run-on check |
| Sophisticated Clarity | AI | None published | Named, undefined | No specific check |
| Rigid Guidance | AI | Not found on the vendor’s page | Unverified | No specific check |
| Formulaic Organization | AI | Not found on the vendor’s page; reported by a user in 2026 | Unverified | Category 16, same-build paragraphs |
| Predictable Syntax | AI | Not found as a label. “Predictable” opens the definition of Monotonous Syntax | Unverified | Category 16 |
| Lacks Creative Grammar | AI | Not found as a label. A writer quoted on GPTZero’s blog says GPTZero is “saying that it’s too robotic and lacks creative grammar” (GPTZero, 2026b) | Unverified | Category 16, narrow range; “Sentence variety” |
| Speculative Focus | AI | Not found on the vendor’s page | Unverified | Category 17 |

Sources for the table: GPTZero (2025) for the published and named labels, GPTZero (2026b) for the blog quotation, and a user’s report of a scan in May 2026 for Formulaic Organization.

Human-side labels that GPTZero names on its page: Personal Tone (opinions and reflections in informal language), Direct Quotes, Community Impact, Contemporary Relevance, Informative Analysis and Journalistic Style. Reports of other human-side labels (varied sentence structure, subjective stance, qualitative focus) could not be confirmed. Category 15 and the devices in Part B point the same way.

### GPTZero AI Patterns

On 19 August 2026 GPTZero published ten “AI Patterns” (the page was modified on 28 September 2026), a taxonomy that it says is derived from Wikipedia’s signs of AI writing (GPTZero, 2026a). The vendor says a pattern “is not proof of AI authorship”, that patterns can appear in documents classified as human-written, and that it leaves formatting out.

| Pattern | Vendor description | Covered by |
|---|---|---|
| Overblown Importance | Sentences that “make ordinary events sound much more important than they are” | Category 13, Lists A and D; category 9 |
| Name Dropping | Text that “piles up press coverage references” to seem credible | Not scored; note it in the verdict |
| Empty Commentary | “superficial analysis” with no suitable evidence | Categories 5 and 14 |
| Sales-pitch Tone | “an advertising-like writing style” | Category 13, List D |
| Phantom Experts | A claim assigned “to unnamed authorities” | Category 14 |
| Dressed-up Verbs | “elaborate-sounding constructions” in place of “is” or “are”, such as “serves as” | Category 13, List D |
| Not just X, but Y | Rejecting a statement, then following it with a larger one | Category 1 |
| Everything in Threes | Ideas presented as “three parallel items” | Category 19 |
| Unnecessary Caveats | Disclaimers or reminders that readers already understand | Category 8 |
| Chatbot Language | “explicit AI-assistance or refusal messages” | Category 6 |

### How other detectors explain a flag

| Detector | Named reasons | What it shows |
|---|---|---|
| Turnitin | No | One highlight for likely AI text. A separate AI-paraphrased highlight was removed from 4 August 2026 (University of Palermo Library, 2026) |
| Pangram | Partly | Segments labelled AI-generated, AI-assisted or Human, and an “AI Phrases” scan (Pangram, 2025, 2026) |
| Originality.ai | No | A colour heatmap by sentence |
| Copyleaks | Yes | “AI Logic”: AI Phrases, shown with a frequency ratio, and AI Source Match, a match to published AI content (Copyleaks, n.d.) |
| QuillBot | Yes, mostly unpublished | Explainer cards for “10 specific patterns, including overly formal tone, technical jargon, predictable structure, and generic language” (QuillBot, n.d.) |
| Winston AI | No | A prediction map and score bands; the vendor says sentence scores “should not be interpreted on their own” |
| Grammarly, ZeroGPT, Sapling | No | A percentage with highlighted or scored sentences |
| Scribbr | No | Four categories, from AI-generated to human-written, with two AI-refined kinds between them |

Source for the table: vendor pages read in October 2026, apart from the entries that carry their own citation.

### How far to trust the explanations

- GPTZero’s own paper (a vendor paper) says its highlighted sentences are “at least correlated with detector predictions, even if they are not necessarily causal” (Adam et al., 2026).
- A reporter found a text that Copyleaks judged to be AI while both of its explanation tools returned nothing (Reed, 2025).
- In a study of explanation methods for detectors, the method that users rated most useful was the worst at helping them predict the detector (Schoenegger et al., 2024).
- Detectors often lean on stylistic cues that are specific to their training data (Pudasaini et al., 2026).
- No independent test of the named reasons shown by GPTZero, QuillBot or Copyleaks was found.

## C2. How detectors work

- **Perplexity.** How surprised a language model is by a text. LLM output tends to score low. So does simple, predictable human writing, which is one likely reason that detectors flagged non-native writers more often in a 2023 study (Liang et al., 2023).
- **Burstiness.** Variation in sentence length and in surprise from one sentence to the next. Human writers vary more. It is a weak signal on its own. GPTZero says it dropped the measure in autumn 2023, and Turnitin says its model is not programmed to check it (GPTZero, n.d.; Turnitin, 2026c).
- **Probability curvature.** DetectGPT changes a passage slightly and checks whether the original sits at a local peak of model probability, as machine text tends to (Mitchell et al., 2023). Fast-DetectGPT gets a similar signal far more cheaply (Bao et al., 2024).
- **Cross-perplexity.** Binoculars compares how surprising a text is to one model with how surprising that model’s predictions are to a second model (Hans et al., 2024).
- **Older tools.** GLTR shows how often each word was among a model’s top predictions (Gehrmann et al., 2019). It is a teaching tool now.
- **Zero-shot detectors as a group.** They need no training on labelled examples. They do well on raw model output and much worse on edited text (Russell et al., 2025).
- **Trained classifiers.** Turnitin, Pangram, GPTZero, Originality.ai and Copyleaks learn from labelled human and AI text and apply a threshold. Moving the threshold trades wrong flags against misses. In one independent study, Pangram, GPTZero and Originality.ai all beat an open-source detector (Jabarian & Imas, 2025).
- **False positive rate (FPR) and false negative rate.** FPR is the share of human texts wrongly flagged; the false negative rate is the share of AI texts missed. In education FPR matters most, because a wrong flag is an accusation.
- **Judging a detector.** Ask how much AI text it catches at a fixed low FPR, such as 1%. A high AUROC, the summary score across all thresholds, can hide poor results at that level.
- **Level of detail.** Some tools give one score for a document. Others mark sentences or spans. Mixed human and AI text makes span marking more useful and less reliable.
- **Minimum length.** Short texts carry little signal for any method. SynthID-Text reaches only about 30% true positives at 1% FPR on 50-token texts (“On Google’s SynthID-Text”, 2026).
- **Retrieval.** A provider can store what its model writes and check a suspect text against that store by meaning (Krishna et al., 2023).
- **Style fingerprints.** The word, grammar and rhetoric patterns behind the 22 categories. Excess style words suggest that at least 13.5% of 2024 PubMed abstracts were processed with an LLM (Kobak et al., 2025), and one follow-up puts the share of 2025 open-access biomedical papers with such vocabulary at 89% (Holzwarth et al., 2026). Style alone let a classifier tell ChatGPT, Claude, Grok, Gemini and DeepSeek apart with 97.1% accuracy (Sun et al., 2025).
- **Expert readers.** People who use LLMs heavily for their own writing spot AI text far better than others. In one study, five such readers misjudged 1 article in 300 by majority vote, while non-experts scored near chance and were overconfident. The experts cited vocabulary, sentence structure (35.9% of explanations) and grammar (24.8%) (Russell et al., 2025).

## C3. Watermarks and provenance

- **How a text watermark works.** In the original scheme, at each step the model splits the vocabulary into a “green” list and a “red” list with a secret key, and nudges its choice towards green words. A detector that holds the key counts green words and runs a statistical test (Kirchenbauer et al., 2023). SynthID-Text works differently, as the next entry shows.
- **Google.** SynthID-Text uses “Tournament sampling”. A live test on nearly 20 million Gemini responses found no loss of quality, and Google has used it in Gemini since 2024 (Dathathri et al., 2024). Researchers have shown that the presence of such a watermark can be detected through black-box queries to a model (Gloaguen et al., 2025).
- **Anthropic.** Anthropic states that text from the Claude models on its list carries a watermark that is a version of SynthID-Text, and that “Nothing is added to the text and there are no hidden characters” (Anthropic, 2026b). Its help page lists Claude Fable 5.1, Fable 5, Mythos 5.1, Opus 5.5, Opus 5, Opus 4.8, Sonnet 5.5, Sonnet 5 and Haiku 5.5, across the Claude Platform (API), Claude, Claude Code, Claude Cowork and Claude Tag (Anthropic, 2026a; page read on 8 October 2026). The mark travels with copied text and “may persist through some editing”. A detection API is in private preview for eligible organisations, which include educational organisations, regulators, media and independent researchers.
- **What a Claude mark shows.** Anthropic says a detected mark is a signal that Claude was involved and “is not fully conclusive”. It cannot tell Claude writing a text from Claude heavily editing one, it holds no information about the user, and a missing mark does not show that a text is free of AI (Anthropic, 2026a, 2026b).
- **OpenAI.** OpenAI built a text watermark in 2024 and chose not to release it (Nemecek et al., 2026).
- **Verification.** Outsiders cannot yet verify the deployed watermarks of either Google or Anthropic, which one paper calls the main governance failure (Nemecek et al., 2026).
- **Weak points.** A watermark works only for text from a provider that uses one. Paraphrase, translation and summarising degrade text watermarks (“Watermarking Without Standards”, 2025). Anthropic says its mark may be lost through heavy editing, paraphrasing, translation or mixing with other writing, and in very short passages (Anthropic, 2026a).
- **EU AI Act, Article 50.** Providers of generative systems must mark outputs in a machine-readable, detectable way (Article 50(2)). Deployers must label deepfakes and AI-generated text published to inform the public on matters of public interest (Article 50(4)). The duties applied from 2 August 2026, and content made available before that date need not be marked (European Commission, 2026a, which is the Commission’s FAQ on the Code of Practice; the text of the Act was not read).
- **Code of Practice.** The Commission published a voluntary Code of Practice on marking and labelling on 10 June 2026 (European Commission, 2026b). It accepts that no single technique meets the duty, so it expects layered methods (Paul, Weiss, 2026), and it sets a threshold of 200 tokens for very short text (Bird & Bird, 2026).
- **For a student (the skill’s inference from Article 50(2) and (4)).** Article 50 puts its duties on providers and deployers. It does not oblige a university to detect anything, and a student essay is not public-interest publishing.

## C4. Vendors in detail

**Turnitin.**

- Claims an FPR below 1% for documents with more than 20% AI writing, and shows no score for results from 1% to 19% (Turnitin, 2026a). Vendor claim.
- Added AI-paraphrase detection, then detection of “AI bypasser” tools on 27 August 2025. Both work for English only (Turnitin, 2026a, 2026b).
- A February 2026 update aimed to raise recall. A May 2026 Spanish update targeted GPT-5 class and Gemini 2.5 output (Turnitin, 2026a, 2026b).
- From 4 August 2026 the report shows a single highlight, and the separate AI-paraphrased category is gone (University of Palermo Library, 2026, a university library notice).
- Turnitin Clarity adds a view of the writing process (Turnitin, 2026b).
- A figure of 0.014 for nearly 2,000 samples by English-language learners, against 0.013 for native writers, is reported as a vendor self-report. Unverified: it was not traced to a Turnitin page, and its unit may differ from the document-level claim above. Check before citing.
- States that its score is not proof of misconduct (Turnitin, 2026a).

**Pangram.**

- Its technical report claims 0% false positives on the TOEFL set used by Liang et al. and very low rates on two larger learner corpora (Emi & Spero, 2024). Vendor self-report.
- Independent tests: it was the only detector to meet an FPR cap of 0.5% without losing detection (Jabarian & Imas, 2025), and it matched expert readers, holding at 90% or more on humanised text (Russell et al., 2025).
- One critic found that its verdicts changed across nested versions of the same text (deBoer, 2026).

**GPTZero.**

- Beat the open-source detector in one independent study, as did Pangram and Originality.ai (Jabarian & Imas, 2025).
- Caught 46.7% of humanised o1-pro articles (Russell et al., 2025).
- In a 2026 study of four tools, it was the only one that misclassified a fully human text (“Who wrote this?”, 2026).
- Says that its AI Vocabulary feature does not directly affect the score (GPTZero, 2024).

**Others.**

- An older comparison of 16 detectors found only Copyleaks, Turnitin and Originality.ai accurate on both human and AI documents (Walters, 2023).
- In the 2026 study of four tools, most underestimated the AI content from the newest model (“Who wrote this?”, 2026).
- Tests on a vendor’s own blog are marketing. Do not cite them as findings.

## C5. Reliability and fairness

| Evidence | Finding |
|---|---|
| RAID benchmark (Dugan et al., 2024) | Over 6 million texts, 11 models, 8 domains and 11 attacks. Most detectors were easily fooled by attacks and by unseen settings |
| RAID shared task (Dugan et al., 2025) | With all domains and models seen in training, 9 teams made 23 submissions, several passed 99% accuracy at 5% FPR (a looser limit than the 1% used elsewhere in this file), and the two winners, Leidos and Pangram, kept 97.7% TPR under attack. Known conditions are solvable; unknown ones are the problem |
| Liang et al. (2023) | Seven detectors flagged 61.22% of 91 TOEFL essays as AI on average, and all seven flagged 19.78% of them |
| Jabarian and Imas (2025) | Commercial tools beat open-source ones; Pangram alone met an FPR cap of 0.5% |
| Russell et al. (2025) | Expert readers and Pangram were near-perfect; Binoculars and Fast-DetectGPT were weak on humanised text |
| “Who wrote this?” (2026) | Human text was mostly cleared; AI text from the newest model was often underestimated |
| Vanderbilt University (2023) | At a 1% FPR, its 75,000 yearly submissions could mean about 750 wrongly labelled papers |

Most people cannot spot AI text. People who use LLMs heavily for their own writing can, with high accuracy, on a small expert sample (Russell et al., 2025).

## C6. Robustness: which edits beat which detectors

These are research findings on robustness, for the thesis paper and for honest answers about what a rewrite can and cannot do. Part A does not use them as methods. The rewrite stays a style edit, with no look-alike characters, no hidden text and no humaniser tools.

| Edit or attack | Finding | Source |
|---|---|---|
| Paraphrasing | Sharply cuts detection for most detectors. Retrieval over stored outputs recovers much of it | Krishna et al., 2023 |
| Humaniser tools | On humanised o1-pro articles, Binoculars caught 6.7%, Fast-DetectGPT 23.3% and GPTZero 46.7% (all multiples of 1/30, so the set was probably about 30 articles; check the paper). Pangram held at 90% or more, and expert readers misjudged 1 article in 300 | Russell et al., 2025 |
| Character tricks | Homoglyph and similar attacks degraded most detectors on RAID | Dugan et al., 2024 |
| Known conditions | When domains and models were seen in training, the best systems kept 97.7% TPR under attack | Dugan et al., 2025 |
| Light AI polishing of human text | Often flagged as AI | Saha & Feizi, 2025 |
| Richer word choice | Enriching the vocabulary of TOEFL essays cut false flags from 61.22% to 11.77% | Liang et al., 2023 |
| Editing an AI draft by hand | Post-edited LLM drafts stayed closer to LLM style than to the writer’s own | Baumler et al., 2026 (preprint) |
| Removing a flagged sentence | May not lower the score, because the detector weighs the whole document | GPTZero, 2023 (vendor; not re-checked) |
| Watermarks | Paraphrase and summarising degrade SynthID-Text. Anthropic says its mark may persist through some editing and may be lost through heavy editing, paraphrasing, translation or mixing with other writing | “Watermarking Without Standards”, 2025; Anthropic, 2026a |
| Newer models | Experts still caught the reasoning model o1-pro. Turnitin says its 2026 updates cover GPT-5 class and Gemini 2.5 class models | Russell et al., 2025; Turnitin, 2026b |
| Theory | As model text approaches human text, the best possible detector approaches chance | Sadasivan et al., 2023 |

Countermeasures that the literature proposes: retrieval defences (Krishna et al., 2023), watermarks (Kirchenbauer et al., 2023; Dathathri et al., 2024), classifiers trained on humaniser output (Turnitin, 2026a), and process-based assessment.

## C7. University and publisher policy

**Institutional responses to detection.**

- Vanderbilt University disabled Turnitin’s AI detector on 16 August 2023 (Vanderbilt University, 2023).
- Australian Catholic University piloted switching it off in 2025 (CAQA, 2025).
- Curtin University disabled it from 1 January 2026 while keeping similarity checking (EdTech Innovation Hub, 2025; announced in 2025, so check that it took effect), and pointed students to Turnitin’s Authorship function and to Grammarly (Biztech Community, 2025).
- UAE University goes the other way. Its 2025 policy says faculty “are required to use AI-generated text detection tools” (UAE University, 2025).

**Rules on using and disclosing AI.**

- UAE University: students may use generative AI tools for academic and research purposes, but “using AI-generated content without acknowledgment is considered plagiarism”, and a declaration is expected when adapting such material (UAE University, 2025).
- Zayed University: “Unauthorized use of AI Tools is considered cheating and/or plagiarism”, though professors may allow limited use with citation (Zayed University Library, 2026, a library guide and not the policy text).
- APA 7: the guidance on citing generative AI was updated in September 2025 and now cites the specific chat, where it once cited only the tool (McAdoo et al., 2025).
- COPE: “AI tools cannot be listed as an author of a paper” (COPE Council, 2023).

Policies differ by institution and change often. Check the rules of the author’s own university and course.

## C8. Thesis support

### Open debates

1. **Is reliable detection possible?** Sadasivan et al. (2023) say no in the limit. Jabarian and Imas (2025) and Russell et al. (2025) show that the best tools work well on the models they tested, although one 2026 study found text from the newest model often underestimated (“Who wrote this?”, 2026).
2. **Accuracy against fairness.** At a 1% FPR a large university could wrongly flag hundreds of papers a year (Vanderbilt University, 2023), and the TOEFL result shows that error can fall on one group (Liang et al., 2023).
3. **Detection, provenance or redesign?** The EU route is provenance by providers (European Commission, 2026a). Some universities choose to redesign assessment (EdTech Innovation Hub, 2025). UAE University mandates detection (UAE University, 2025).
4. **Explanation or decoration?** Detectors now show named reasons, but the reasons sit beside the classifier and no independent test of them was found (Adam et al., 2026; Schoenegger et al., 2024).

### Literature map

| Theme | Source | One-line finding |
|---|---|---|
| Prevalence | Kobak et al. (2025), Science Advances | At least 13.5% of 2024 PubMed abstracts processed with LLMs |
| Prevalence | Holzwarth et al. (2026), arXiv | 89% of 2025 open-access biomedical full texts show excess LLM vocabulary |
| Lexical cause | Juzek and Ward (2025), COLING | 21 focal words; human-feedback training likely contributes |
| Style | Reinhart et al. (2025), PNAS | Instruction-tuned LLMs are noun-heavy and dense |
| Style | Markey et al. (2024), Written Communication | Generated text is dense and dialogically closed |
| Syntax | Gude et al. (2026), ACL | 2025 instruction-tuned models write almost no short sentences and are less diverse than 2023 base models |
| Syntax | Shaib et al. (2024), EMNLP | Repeated grammatical templates are far more common in model text |
| Rhetoric | Jiang and Hyland (2025a, 2025b, 2025c, 2026) | ChatGPT uses stock bundles and far less stance, engagement and interactional metadiscourse |
| Speculation | Peters and Chin-Yee (2025), Royal Society Open Science | LLM summaries overgeneralise research findings in 26 to 73% of cases |
| Attribution | Sun et al. (2025), ICML | 97.1% accuracy in telling five chatbots apart |
| Benchmarks | Dugan et al. (2024, 2025) | Detectors are fragile under attack and strong when conditions are seen |
| Tool audits | Jabarian and Imas (2025); Walters (2023); “Who wrote this?” (2026) | Commercial tools beat the open-source detector tested; the newest models are often underestimated |
| Humans | Russell et al. (2025), ACL | Frequent LLM users detect AI text near-perfectly |
| Fairness | Liang et al. (2023), Patterns | 61% false positives on non-native essays |
| Polished text | Saha and Feizi (2025), arXiv | Lightly AI-polished human text is often flagged |
| Watermarks | Kirchenbauer et al. (2023); Dathathri et al. (2024); Gloaguen et al. (2025); Nemecek et al. (2026) | Watermarks work at scale, can be detected and weakened, and cannot yet be verified from outside |
| Explanations | Schoenegger et al. (2024); Pudasaini et al. (2026) | Explanations of detector verdicts are weak guides to detector behaviour |
| Policy | European Commission (2026a, 2026b) | Article 50 marking and labelling duties from 2 August 2026 |
| Learner connectives | Granger and Tyson (1996); Lei (2012); Liu (2008) | Learners overuse additive links; scholars rely on a narrow core |

### Research gaps as of October 2026

- Independent tests of detectors on Gulf-region and Arabic-L1 English writing.
- False positive rates for AI-polished human writing.
- Non-vendor tests of detection on the newest reasoning models.
- Outside verification of provider watermarks (Nemecek et al., 2026).
- How organisations, and not only universities, adopt and govern detectors.
- Whether disclosure policies change student behaviour.
- Independent tests of the named reasons that detectors show beside sentences.
- Whether editing for sentence variety changes detector scores: no study found.
- Sentence openers, idiom and speculative endings in LLM text: no direct measurement found.

### Candidate research questions

| Question | Method | Feasibility |
|---|---|---|
| How do UAE university staff interpret AI-detector scores in misconduct decisions? | Semi-structured interviews; thematic analysis | High |
| Do students see mandated detection as fair, and does that affect institutional trust? | Survey using organisational justice scales | High |
| How often do detectors flag human-written essays by Arabic-L1 graduate students? | Consented pre-2022 or supervised essays run through two or three tools; report FPR | Medium |
| How do Gulf HR managers treat AI-written job applications? | Vignette experiment with recruiters | Medium |
| What drives adoption of AI-detection tools in organisations? | Technology adoption survey or case studies | Medium |
| Does AI polishing of L2 writing change detector scores? | Controlled experiment: human text, then light AI editing | Medium |

### Suggested paper structure

Introduction; background on how detection works; literature review (accuracy, robustness, fairness, policy); UAE and Gulf policy context; method; findings; discussion of detection against provenance against redesign, with the implications for HR and organisational governance; limits; conclusion.

## C9. Advice for the author

Pass this on when the same tells keep coming back, or when the author asks how to write so that the tells do not appear.

- **Build it in while drafting.** Use the exact terms of the field. Name who did what. End paragraphs on evidence or on a real question. Take a position and say how sure you are.
- **One and one.** Aim for one named case or figure and one clear judgement in every paragraph of an argument.
- **Write the first draft yourself.** An AI draft that is edited by hand stays close to AI style (Baumler et al., 2026).
- **Know your own habits.** Run the audit on something you wrote before 2023. Hits that show up there are your own style, and the cut-offs can be read against them.
- **Keep a paper trail.** Draft with version history on. Keep notes, outlines and annotated sources. Where the institution offers a writing-process tool such as Turnitin Clarity, use it for major work.
- **If falsely flagged.** Ask for the report and the threshold. Supply version history and notes. Offer an oral discussion. Point to the tool maker’s own position that a score is not proof (Turnitin, 2026a) and to the evidence on false positives (Liang et al., 2023).
- **Disclose.** Follow the rules of the university, the publisher and the style guide (section C7).
- **Drill 1.** Reverse-outline a published article from a leading journal in the field, and note how each paragraph opens.
- **Drill 2.** Copy one paragraph, underline each theme, box each rheme, and draw an arrow wherever a rheme becomes the next theme.
- **Drill 3.** Delete every connective from a paragraph, then restore only those that the meaning needs.

## What changed in the October 2026 update

- Categories renumbered: there are now 22. New ones are participle tails (5), chatbot residue (6), stock connective chains (7), summary and uplift closers (9), generic content and vague attribution (14), faceless prose (15), monotonous syntax (16), ungrounded speculation (17), mechanical precision (18), reflex triads (19) and formatting artefacts (21)
- Five style labels now have checks: robotic formality (15), monotonous or predictable syntax and creative grammar (16), speculative focus (17), mechanical precision (18). Section C1 shows which of these labels GPTZero’s own page confirms
- Hedge stacking retired as a tell. The rewrite keeps hedges
- “However” no longer counts as scaffolding
- Hard rule 2 added: British spelling. Hard rule 3 added: never invent, with [AUTHOR: ...] markers
- Scoring: a hit is defined, scores are scaled per 300 words, a tally and a worked example are given, and the rewrite is scored again
- Every rewrite now carries notes: cuts, changes inside quoted matter, spelling changes and gaps for the author
- Part B added: the ten-pass edit, 15 joining techniques, ten sentence-variety devices, nine fixes, full connective tables and a staged example
- Part C added: detector labels, how detectors work, watermarks, vendor detail, reliability, robustness findings, policy, thesis support and advice for the author

## References

In APA order, the three 2025 papers by Jiang and Hyland are lettered by title. The October 2026 research report used 2025a for the engagement paper and 2025b for the metadiscourse paper.

**LLM text, detection and watermarks**

- Adam, A., et al. (2026). GPTZero: Robust detection of LLM-generated texts. arXiv:2602.13042. Vendor paper.
- Bao, G., Zhao, Y., Teng, Z., Yang, L., & Zhang, Y. (2024). Fast-DetectGPT: Efficient zero-shot detection of machine-generated text via conditional probability curvature. ICLR 2024.
- Baumler, C., et al. (2026). Can you make it sound like you? Post-editing LLM-generated text for personal style. arXiv:2604.24444.
- Dathathri, S., et al. (2024). Scalable watermarking for identifying large language model outputs. Nature, 634, 818-823.
- Desaire, H., Chua, A. E., Isom, M., Jarosova, R., & Hua, D. (2023). Distinguishing academic science writing from humans or ChatGPT with over 99% accuracy using off-the-shelf machine learning tools. Cell Reports Physical Science, 4(6), 101426.
- Dugan, L., et al. (2024). RAID: A shared benchmark for robust evaluation of machine-generated text detectors. ACL 2024.
- Dugan, L., et al. (2025). GenAI content detection task 3: Cross-domain machine-generated text detection challenge. COLING 2025 workshop.
- Emi, B., & Spero, M. (2024). Technical report on the Pangram AI-generated text classifier. arXiv:2402.14873. Vendor report.
- Gehrmann, S., Strobelt, H., & Rush, A. (2019). GLTR: Statistical detection and visualization of generated text. ACL 2019.
- Gloaguen, T., Jovanović, N., Staab, R., & Vechev, M. (2025). Black-box detection of language model watermarks. arXiv:2405.20777.
- Gude, Santos-Rios, Bond, Flickinger, Gómez-Rodríguez, & Zamaraeva (2026). More aligned, less diverse? Analyzing the grammar and lexicon of two generations of LLMs. ACL 2026.
- Hans, A., et al. (2024). Spotting LLMs with Binoculars: Zero-shot detection of machine-generated text. ICML 2024.
- Holzwarth et al. (2026). Most biomedical publications show signs of LLM-assisted writing. arXiv:2608.10715.
- Jabarian, B., & Imas, A. (2025). Artificial writing and automated detection.
- Jiang, F. K., & Hyland, K. (2025a). Does ChatGPT argue like students? Bundles in argumentative essays. Applied Linguistics, 46(3), 375-391.
- Jiang, F. K., & Hyland, K. (2025b). Does ChatGPT write like a student? Engagement markers in argumentative essays. Written Communication, 42(3), 463-492.
- Jiang, F. K., & Hyland, K. (2025c). Rhetorical distinctions: Comparing metadiscourse in essays by ChatGPT and students. English for Specific Purposes, 79, 17-29.
- Jiang, F. K., & Hyland, K. (2026). Taking a stance: AI generated versus student written argumentative essays. Applied Linguistics Review. https://doi.org/10.1515/applirev-2025-0188
- Juzek, T. S., & Ward, Z. B. (2025). Why does ChatGPT “delve” so much? Exploring the sources of lexical overrepresentation in large language models. COLING 2025.
- Kirchenbauer, J., et al. (2023). A watermark for large language models. ICML 2023.
- Kobak, D., González-Márquez, R., Horvát, E.-Á., & Lause, J. (2025). Delving into LLM-assisted writing in biomedical publications through excess vocabulary. Science Advances, 11(27), eadt3813.
- Krishna, K., Song, Y., Karpinska, M., Wieting, J., & Iyyer, M. (2023). Paraphrasing evades detectors of AI-generated text, but retrieval is an effective defense. NeurIPS 2023.
- Liang, W., Yuksekgonul, M., Mao, Y., Wu, E., & Zou, J. (2023). GPT detectors are biased against non-native English writers. Patterns, 4(7), 100779.
- Markey, B., Brown, D. W., Laudenbach, M., & Kohler, A. (2024). Dense and disconnected: Analyzing the sedimented style of ChatGPT-generated text at scale. Written Communication, 41(4), 571-600.
- Mitchell, E., et al. (2023). DetectGPT: Zero-shot machine-generated text detection using probability curvature. ICML 2023.
- Muñoz-Ortiz, A., Gómez-Rodríguez, C., & Vilares, D. (2024). Contrasting linguistic patterns in human and LLM-generated news text. Artificial Intelligence Review, 57, 265.
- Nemecek, A., Chaudhary, V., & Ayday, E. (2026). Watermarks without verification: AI text watermarking after the EU AI Act. arXiv:2609.09604.
- On Google’s SynthID-Text LLM watermarking system: Theoretical analysis and empirical validation. (2026). arXiv:2603.03410.
- Peters, U., & Chin-Yee, B. (2025). Generalization bias in large language model summarization of scientific research. Royal Society Open Science, 12(4), 241776.
- Pudasaini et al. (2026). Why AI-generated text detection fails: Evidence from explainable AI beyond benchmark accuracy. arXiv:2603.23146.
- Reinhart, A., Markey, B., Laudenbach, M., Pantusen, K., Yurko, R., Weinberg, G., & Brown, D. W. (2025). Do LLMs write like humans? Variation in grammatical and rhetorical styles. PNAS, 122(8), e2422455122.
- Rudnicka, K., & Juzek, T. S. (2026). Beyond “AI language”: The case for the idiolectal nature of LLM output. arXiv:2608.06589.
- Russell, J., Karpinska, M., & Iyyer, M. (2025). People who frequently use ChatGPT for writing tasks are accurate and robust detectors of AI-generated text. ACL 2025.
- Sadasivan, V. S., Kumar, A., Balasubramanian, S., Wang, W., & Feizi, S. (2023). Can AI-generated text be reliably detected? arXiv:2303.11156.
- Saha, S., & Feizi, S. (2025). Almost AI, almost human: The challenge of detecting AI-polished writing. arXiv:2502.15666.
- Schoenegger, L., Xia, Y., & Roth, B. (2024). An evaluation of explanation methods for black-box detectors of machine-generated text. arXiv:2408.14252.
- Shaib, C., Elazar, Y., Li, J. J., & Wallace, B. C. (2024). Detection and measurement of syntactic templates in generated text. EMNLP 2024.
- Sun, M., Yin, Y., Xu, Z., Kolter, J. Z., & Liu, Z. (2025). Idiosyncrasies in large language models. ICML 2025.
- Walters, W. H. (2023). The effectiveness of software designed to detect AI-generated writing: A comparison of 16 AI text detectors. Open Information Science, 7(1).
- Watermarking without standards is not AI governance. (2025). arXiv:2505.23814.
- Who wrote this? Evaluating the reliability of AI detection tools in higher education. (2026). International Journal for Educational Integrity. https://link.springer.com/article/10.1007/s40979-026-00226-w

**Vendor, policy and press sources**

- Anthropic. (2026a). How Claude marks AI-generated content. Claude Help Center. https://support.claude.com/en/articles/16266773-how-claude-marks-ai-generated-content
- Anthropic. (2026b, 14 August). How Claude’s text watermark works. https://www.anthropic.com/news/claude-text-watermark
- Bird & Bird. (2026). Taking the EU AI Act to practice: The final transparency code of practice.
- Biztech Community. (2025). Curtin University to disable Turnitin’s AI writing detection feature in 2026.
- CAQA. (2025).
- COPE Council. (2023). Authorship and AI tools. https://publicationethics.org/guidance/cope-position/authorship-and-ai-tools
- Copyleaks. (n.d.). AI Logic. https://copyleaks.com/ai-content-detector/ai-logic
- deBoer, F. (2026, 19 July). I wouldn’t say Pangram is broken, but I would say that it’s brittle.
- EdTech Innovation Hub. (2025). Curtin University to disable Turnitin AI detection tool in 2026.
- European Commission. (2026a). Signing the Code of Practice on transparency of AI-generated content. https://digital-strategy.ec.europa.eu/en/faqs/signing-code-practice-transparency-ai-generated-content
- European Commission. (2026b, 10 June). Commission publishes Code of Practice on marking and labelling AI-generated content. https://digital-strategy.ec.europa.eu/en/news/commission-publishes-code-practice-marking-and-labelling-ai-generated-content
- GPTZero. (2023, 26 November). Understanding AI detection results with deep analysis.
- GPTZero. (2024, 6 December). How to understand your AI scan results.
- GPTZero. (2025, 10 June). Introducing natural language explanations in Advanced Scan. https://gptzero.me/news/introducing-natural-language-explanations-in-advanced-scan/
- GPTZero. (2026a, 19 August). 10 AI patterns, and a new way to understand AI-like writing. https://gptzero.me/news/ai-patterns/
- GPTZero. (2026b, 24 April). Why does my writing get flagged as AI (when it’s not)? https://gptzero.me/news/why-writing-flagged-ai/
- GPTZero. (n.d.). How do I interpret burstiness or perplexity? https://support.gptzero.me/hc/en-us/articles/15130070230551-How-do-I-interpret-burstiness-or-perplexity
- McAdoo, T., et al. (2025). Citing generative AI in APA Style. https://apastyle.apa.org/blog/cite-generative-ai-references
- Pangram. (2025, 14 February). Pangram AI Phrases. https://www.pangram.com/blog/pangram-ai-phrases
- Pangram. (2026). What are AI segments? https://www.pangram.com/knowledge-hub/what-are-ai-segments
- Paul, Weiss. (2026). EU finalises transparency rules for AI-generated content.
- QuillBot. (n.d.). The technology behind our AI detector. https://quillbot.com/technology-behind-ai-detector
- Reed, J. (2025, 12 June). This AI writing detector shows its work. For me, it’s a step in the right direction. CNET. https://tech.yahoo.com/ai/articles/ai-writing-detector-shows-step-130006775.html
- Turnitin. (2026a). AI writing detection model. https://guides.turnitin.com/hc/en-us/articles/28294949544717-AI-writing-detection-model
- Turnitin. (2026b). Turnitin product updates. https://guides.turnitin.com/hc/en-us/articles/29645383597965-Turnitin-product-updates
- Turnitin. (2026c). AI writing detection capabilities FAQs. https://guides.turnitin.com/hc/en-us/articles/28477544839821-Turnitin-s-AI-writing-detection-capabilities-FAQs
- UAE University. (2025). Generative AI policy. https://www.uaeu.ac.ae/en/about/pdfs/policies-2025/generative-ai-policy.pdf
- University of Palermo Library. (2026, 31 August). iThenticate: semplificazione AI report dal 4 agosto 2026. https://www.unipa.it/biblioteche/iThenticate---Semplificazione-AI-report-dal-4-agosto-2026/
- Vanderbilt University. (2023). Guidance on AI detection and why we’re disabling Turnitin’s AI detector.
- Wikipedia. (n.d.). Signs of AI writing. https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing
- Zayed University Library. (2026). AI and academic integrity at ZU. https://zu.libguides.com/ai/academic-integrity

**Connectives in corpora**

- Granger, S., & Tyson, S. (1996). Connector usage in the English essay writing of native and non-native EFL speakers of English. World Englishes, 15(1), 17-27.
- Lei, L. (2012). Linking adverbials in academic writing on applied linguistics by Chinese doctoral students. Journal of English for Academic Purposes, 11(3), 267-275.
- Liu, D. (2008). Linking adverbials: An across-register corpus study and its implications. International Journal of Corpus Linguistics, 13(4), 491-518.
- Peacock, M. (2010). Linking adverbials in research articles across eight disciplines. Ibérica, 20, 9-34.

**Cohesion, style and sentence craft**

- Becker, H. S. (2007). Writing for social scientists (2nd ed.). University of Chicago Press.
- Christensen, F. (1963). A generative rhetoric of the sentence. College Composition and Communication, 14(3), 155-161.
- Daneš, F. (1974). Functional sentence perspective and the organization of the text. In F. Daneš (Ed.), Papers on functional sentence perspective. Academia.
- Francis, G. (1994). Labelling discourse: An aspect of nominal-group lexical cohesion. In M. Coulthard (Ed.), Advances in written text analysis. Routledge.
- Gopen, G. D., & Swan, J. A. (1990). The science of scientific writing. American Scientist, 78(6), 550-558.
- Graff, G., & Birkenstein, C. (2021). They say / I say (5th ed.). W. W. Norton.
- Halliday, M. A. K., & Hasan, R. (1976). Cohesion in English. Longman.
- Hayot, E. (2014). The elements of academic style. Columbia University Press.
- Hoey, M. (1983). On the surface of discourse. Allen & Unwin.
- Hoey, M. (1991). Patterns of lexis in text. Oxford University Press.
- Hyland, K. (2005a). Metadiscourse: Exploring interaction in writing. Continuum.
- Hyland, K. (2005b). Stance and engagement: A model of interaction in academic discourse. Discourse Studies, 7(2), 173-192.
- Kehler, A. (2002). Coherence, reference, and the theory of grammar. CSLI Publications.
- Kolln, M., & Gray, L. (2017). Rhetorical grammar: Grammatical choices, rhetorical effects (8th ed.). Pearson.
- Mann, W. C., & Thompson, S. A. (1988). Rhetorical structure theory: Toward a functional theory of text organization. Text, 8(3), 243-281.
- Pinker, S. (2014). The sense of style. Viking.
- Swales, J. M. (1990). Genre analysis. Cambridge University Press.
- Swales, J. M., & Feak, C. B. (2012). Academic writing for graduate students (3rd ed.). University of Michigan Press.
- Sword, H. (2012). Stylish academic writing. Harvard University Press.
- Tufte, V. (2006). Artful sentences: Syntax as style. Graphics Press.
- Williams, J. M., & Bizup, J. (2017). Style: Lessons in clarity and grace (12th ed.). Pearson.