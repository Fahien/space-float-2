---
name: technical-writing
description: Technical writing, documentation drafting, editing, and review. Use when creating or improving README files, developer guides, tutorials, API docs, design docs, release notes, error messages, sample-code explanations, accessibility-focused docs, or prompts for documentation work. Do not use for marketing copy unless the task is to make technical content clearer, more accurate, more usable, or more accessible.
---

# Technical Writing

Use this skill to create, revise, or review technical documentation. Optimize for reader success: the reader should quickly understand what matters, why it matters, and what to do next.

## Operating principles

- Prefer clarity over cleverness, style, or completeness.
- Write for the stated audience, not for the author or implementation team.
- Make the document teach a task, concept, decision, or recovery path.
- Preserve technical accuracy. Do not invent behavior, requirements, APIs, limits, or outputs.
- Verify claims against the repository, source files, tests, issue context, or authoritative docs when available.
- Use simple, culturally neutral English. Avoid idioms, slang, and pop-culture references unless they are necessary for the audience.
- Use a consistent style guide when one exists. Otherwise, follow the rules in this skill.

## First, identify the writing job

Before drafting or editing, infer or ask for the following when they are missing and materially affect the result:

- **Document type**: README, tutorial, how-to, concept guide, API reference, design doc, error message, release note, migration guide, troubleshooting guide, or code comment.
- **Target audience**: role, experience level, domain knowledge, and proximity to the system.
- **Reader goal**: what readers need to know or do after reading.
- **Current knowledge**: what readers probably already know.
- **Scope**: what the document covers.
- **Non-scope**: what a reasonable reader might expect but the document does not cover.
- **Prerequisites**: concepts, tools, permissions, files, setup, versions, or prior reading.

For substantial docs, start with a brief plan or outline before writing the full text.

## Document structure

### Introductions

Start long or important documents with an introduction that answers:

- What does this document cover?
- Who is this document for?
- What should readers know before reading?
- What does this document not cover?
- What will readers be able to do or understand after reading?

Put key points early. Assume some readers will read only the first paragraph or summary.

### Organization

- Organize around reader goals, not implementation order, unless implementation order is the reader's task order.
- Use task-based headings when readers are trying to do something.
- Add brief context under each heading before nesting more headings.
- Do not skip heading levels.
- Use progressive disclosure: introduce terminology and detail near the step or concept that needs it.
- Start with simple examples; add complexity gradually.
- For large topics, use shorter linked documents when the audience is new, and longer reference-style pages when the audience needs scanning and depth.
- Add navigation aids where helpful: overview, prerequisites, table of contents, next steps, related links, and troubleshooting.

### Scope control

During review, compare every section with the scope statement. Delete, move, or re-scope content that does not help the target reader accomplish the stated goal.

## Sentences

- Prefer active voice: identify who or what performs the action.
- Use imperative verbs for instructions: “Open the file,” “Run the command,” “Set the variable.”
- Choose strong, specific verbs instead of weak verbs such as “is,” “are,” “occur,” or “happen.”
- Avoid starting sentences with “There is” or “There are.” Replace them with a real subject and verb.
- Keep each sentence focused on one idea.
- Break long sentences into shorter sentences or lists.
- Remove filler phrases.
- Prefer objective data over vague adjectives and adverbs.
- Use “that” for essential clauses and “which” for nonessential clauses in US English. Put a comma before “which,” not before “that.”
- Avoid double negatives and exceptions to exceptions. State the positive rule directly when possible.

Examples:

```text
Weak: A compiler error happens when a variable declaration doesn't have a data type.
Better: The compiler returns an error when a variable declaration omits the data type.
```

```text
Weak: There is a parameter named timeout that controls retry behavior.
Better: The timeout parameter controls retry behavior.
```

## Words and terminology

- Define unfamiliar terms on first use or link to a reliable definition.
- Use one term for one concept. Do not vary terms for elegance.
- Introduce acronyms only when the acronym is significantly shorter and appears many times.
- On first use, write the term, then the acronym in parentheses. Use the acronym consistently after that.
- Avoid ambiguous pronouns. Replace “it,” “they,” “this,” and “that” with nouns when the referent is unclear.
- Keep pronouns close to the nouns they refer to. If another noun appears between the noun and pronoun, repeat the noun.
- Prefer simple words over rare or literary words.

## Paragraphs

- Start most paragraphs with a sentence that states the central point.
- Keep each paragraph focused on one topic.
- Move or delete sentences that belong to another topic.
- Prefer paragraphs of three to five sentences.
- Avoid walls of text. Split long paragraphs or convert dense material to lists.
- Avoid long runs of one-sentence paragraphs; combine related points or use a list.
- Ensure important paragraphs answer: what, why, and how.

## Lists and tables

Use lists aggressively when they make information easier to scan.

- Use bulleted lists for unordered items.
- Use numbered lists for ordered steps or rankings.
- Avoid embedded lists inside long sentences.
- Introduce each list with a sentence that explains what the list contains. End the introductory sentence with a colon.
- Keep list items parallel in grammar, category, capitalization, and punctuation.
- Start numbered steps with imperative verbs when possible.
- Capitalize the first word of each list item.
- Use sentence-ending punctuation for list items that are complete sentences.

Use tables for comparing structured facts.

- Introduce each table with a sentence that explains what the table contains.
- Use clear column headers.
- Keep cells concise. If a cell needs more than two sentences, consider prose or a list instead.
- Keep data types parallel within each column.
- Consider whether the table will work on small screens.

## Sample code and code explanations

Good sample code is documentation. Treat it like production-quality teaching material.

- Ensure sample code builds, runs, and performs the task it claims to perform.
- Test sample code when possible.
- Prefer correctness over brevity.
- Keep samples short and focused on the teaching goal.
- Omit unrelated setup or framework noise unless it is required to run the example.
- Use descriptive names for variables, functions, classes, flags, and parameters.
- Avoid clever tricks, deep nesting, and obscure language features unless they are the topic.
- Prefer explicit parameter names when they help newcomers understand the API.
- Explain how to run the sample: dependencies, setup, command, environment variables, permissions, and expected output.
- Mention relevant side effects, costs, cleanup, security implications, and limitations.
- Include both examples and anti-examples when a common mistake is important.
- Sequence sample sets from simple to moderate to complex.

Comments in sample code:

- Keep comments short.
- Explain non-obvious parts.
- For experienced audiences, explain why the code does something, not what obvious code does.
- Put explanations that should travel with copied code inside comments.
- Put longer conceptual explanations outside the code block before the sample.

## Error messages

A good error message answers two questions:

1. What went wrong?
2. How can the user fix it?

When writing or reviewing error messages:

- Do not fail silently.
- Report the specific cause when known.
- Identify invalid user input, including the actual value when safe and useful.
- State the expected requirement, limit, format, permission, or constraint.
- Provide the next action or a link to the next action.
- Include examples when the fix is easier to show than explain.
- Use terminology the target audience understands.
- Use consistent product terminology and consistent messages for the same problem.
- Keep the message concise, but not cryptic.
- Avoid blame, jokes, shaming, or panic.
- Avoid double negatives.
- Use progressive disclosure or truncation for very long invalid inputs.
- For systems with error codes, include and document useful internal or external codes.
- Raise errors as early as useful so debugging remains close to the cause.

Template:

```text
[Specific problem]. [Relevant invalid value or constraint]. [How to fix or where to learn more].
```

Examples:

```text
Weak: Invalid postal code.
Better: The postal code for the US must contain 5 or 9 digits. The specified postal code, 4872953, contains 7 digits.
```

```text
Weak: Permission denied.
Better: Permission denied. Only members of <group name> can access this resource. Ask an administrator to add you to <group name>.
```

## Accessibility

Accessible documentation is better documentation.

### Headings and links

- Use semantic headings: `#`, `##`, `###`, or equivalent HTML heading elements.
- Use one level-1 heading for the page title or main content heading.
- Do not skip heading levels.
- Use informative link text. Avoid “click here,” “learn more,” and “this document.”
- Make link text meaningful when read out of context.

### Alt text and image descriptions

- Provide alt text for informative images.
- Describe the image in the context of the surrounding text.
- Keep alt text short: usually one phrase or one or two sentences.
- Do not start alt text with “Image of” or “Photo of.”
- Use empty alt text (`alt=""`) for decorative or redundant images.
- For complex diagrams, charts, or maps, provide short alt text plus a longer explanation in the body text or a linked description.
- Include demographic details only when they are necessary to understand the image.
- Use consistent alt text for repeated images.
- Avoid all-caps text.

### Visual accessibility

- Do not rely on color, shape, position, font styling, or direction alone to communicate meaning.
- Pair visual cues with text labels or descriptions.
- Check color contrast with a contrast checker; do not rely on visual judgment.
- Use at least WCAG contrast ratios when designing visuals: 4.5:1 for small text and 3:1 for large text.
- Ensure diagram text is readable and has sufficient contrast.
- Prefer SVG for scalable diagrams when the publishing system supports it.

### Inclusive language

- Avoid euphemisms, patronizing terms, and language that implies judgment.
- Avoid calling people without disabilities “normal.” Prefer terms such as “nondisabled,” “sighted,” “hearing,” or “person without disabilities,” as context requires.
- Prefer person-first language unless a community commonly prefers identity-first language.
- Research community preferences when writing about a specific community.

### Accessibility testing

When practical, test documentation by:

- Zooming the page.
- Navigating with only the keyboard.
- Reading link text out of context.
- Using a screen reader or text-to-speech tool.
- Checking whether diagrams still make sense without color.

## Illustrations and diagrams

- Write the caption before creating or revising the illustration.
- Make the caption concise and focused on the takeaway.
- Ensure the illustration teaches the caption's point.
- Limit a diagram to roughly one paragraph's worth of information.
- Split complex systems into a big-picture diagram plus smaller subsystem diagrams.
- Use callouts, labels, arrows, or highlighting to focus attention.
- Avoid decorative graphics that do not teach.
- Revise diagrams like prose: simplify, split, label, improve contrast, and clarify the takeaway.

## Editing workflow

When revising existing documentation, follow this order:

1. **Audience and goal**: Confirm who the reader is and what they need to do or learn.
2. **Scope**: Remove content outside the document's purpose.
3. **Organization**: Fix outline, headings, and flow before line editing.
4. **Completeness**: Add missing prerequisites, setup, constraints, examples, outputs, and next steps.
5. **Accuracy**: Verify claims, commands, code, links, and outputs.
6. **Clarity**: Apply sentence, paragraph, list, and terminology rules.
7. **Accessibility**: Check headings, links, alt text, visual cues, contrast, and inclusive language.
8. **Final pass**: Read aloud or mentally simulate the reader performing the task.

For peer review comments, be specific and actionable. Identify the issue, explain why it matters to the reader, and suggest a concrete edit.

## Using LLMs for technical writing

When asked to create prompts or use an LLM-assisted workflow for documentation:

- Specify the role the LLM should take.
- Specify the target audience.
- Specify the document type.
- Define the reader goal.
- Provide source context: code, notes, transcript, existing docs, issue, design, or API reference.
- Add constraints to reduce hallucination, such as “Use only the provided source text.”
- Ask for structure and length explicitly.
- Iterate on prompts, but edit a strong draft directly instead of endlessly prompting.
- Always verify LLM-generated technical claims and examples.

Prompt template:

```text
You are an expert technical writer. Write a <document type> for <target audience>.
After reading it, readers should be able to <goal>.
Use only the following source material: <sources>.
Organize the document as follows: <structure>.
Use active voice, simple terminology, and concise paragraphs.
Include prerequisites, steps, examples, expected output, and troubleshooting when relevant.
```

## Output expectations

When producing documentation:

- Provide the final text in the format the user requested.
- If the user asked for a review, organize findings by severity or by document section.
- If facts are uncertain, mark them clearly as assumptions or TODOs.
- If code or commands are unverified, state that they need testing.
- Keep explanations lean; give the user usable text, not a lecture about writing.
