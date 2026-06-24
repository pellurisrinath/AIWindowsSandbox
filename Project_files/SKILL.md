---
name: stop-slop
description: Remove AI writing patterns from prose. Use when drafting, editing, or reviewing .md files (and other prose) destined for this GitHub repository to eliminate predictable AI tells.
metadata:
  trigger: Writing or editing any .md file, changelog entries, implementation plans, README sections, or commit messages
  author: Adapted from hardikpandya/stop-slop (MIT)
  source: https://github.com/hardikpandya/stop-slop
---

# Stop Slop — .md Writing Standard

Apply these rules to every .md file written for this project.

## Core Rules

1. Cut filler phrases. Remove throat-clearing openers, emphasis crutches, and adverbs.
2. Break formulaic structures. No binary contrasts, negative listings, dramatic fragmentation, rhetorical setups, false agency.
3. Use active voice. Name the actor. No passive constructions. No inanimate objects performing human actions.
4. Be specific. Name the thing. No vague declaratives. No lazy extremes ("every," "always," "never") doing vague work.
5. Put the reader in the room. "You" beats "People." Specifics beat abstractions.
6. Vary rhythm. Mix sentence lengths. Two items beat three. End paragraphs differently. No em dashes.
7. Trust readers. State facts directly. Skip softening, justification, hand-holding.
8. Cut quotables. If it sounds like a pull-quote, rewrite it.

## Banned Phrases

Throat-clearing openers:
- "Here's the thing:" / "Here's what [X]" / "Here's why [X]" / "It turns out" / "The real [X] is" / "Let me be clear" / "The truth is,"

Emphasis crutches:
- "Full stop." / "Let that sink in." / "This matters because" / "Make no mistake"

Business jargon:
- navigate challenges, unpack analysis, lean into, deep dive, circle back, game-changer, double down, moving forward, take a step back, on the same page

Adverbs (kill all -ly words and softeners):
- really, just, literally, genuinely, honestly, simply, actually, deeply, truly, fundamentally, inherently, inevitably, interestingly, importantly, crucially

Vague declaratives:
- "The reasons are structural" / "The implications are significant" / "The stakes are high" / "The consequences are real"

## Banned Structures

Binary contrasts:
- "Not because X. Because Y." / "[X] isn't the problem. [Y] is." / "The question isn't X. It's Y."
- Replace with: "The problem is Y." / "Y matters here."

Negative listings:
- "Not a X... Not a Y... A Z."
- Replace with: State Z directly.

Dramatic fragmentation:
- "[Noun]. That's it. That's the [thing]."
- Replace with: Complete sentences.

False agency:
- "the decision emerges" / "the culture shifts" / "the data tells us"
- Replace with: Name the person who did it.

Wh- sentence starters:
- Avoid sentences starting with What, When, Where, Which, Who, Why, How
- Replace with: Lead with the subject or verb.

## Project-Specific Conventions

This is a technical project. Some flexibility applies:

- Code blocks, file paths, and technical terms are exempt from the rhythm rules
- Tables are useful for reference data (allowed)
- Em dashes in code comments are fine
- Headers should be short and direct
- Bullet points should start with the verb (imperative mood)
- The .md file should move the reader to the next action, not announce its own structure

## Quick Self-Check

Before saving any .md file, scan for:

- [ ] Adverbs (-ly words) — kill them
- [ ] Passive voice — find the actor, make them the subject
- [ ] Inanimate thing doing a human verb — name the person
- [ ] Sentence starts with Wh- — restructure
- [ ] "Here's what/this/that" — cut to the point
- [ ] "Not X, it's Y" contrasts — state Y directly
- [ ] Three matching-length sentences in a row — break one
- [ ] Em-dashes — remove
- [ ] Vague declaratives — name the specific thing
- [ ] Meta-joiners ("The rest of this document...") — delete
- [ ] Throat-clearing openers — cut

## Scoring (Optional)

Rate 1-10 on each:

- Directness: statements or announcements?
- Rhythm: varied or metronomic?
- Trust: respects reader intelligence?
- Authenticity: sounds human?
- Density: anything cuttable?

Below 35/50: revise.

## License

MIT. Source: https://github.com/hardikpandya/stop-slop
