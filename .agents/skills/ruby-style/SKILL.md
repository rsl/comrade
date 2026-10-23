---
name: ruby-style
description: Use when writing or editing Ruby code, including ERB Ruby blocks, or when reviewing quality.
---

# Ruby style (comrade project)

Merged 2026-10-23 from rsl's personal ruby-idioms + unifractured's
fa-ruby-style. Lives in this repo — it's the work voice; rsl's
personal ruby-idioms skill remains separate and personal, and where
they overlap, this one governs here.

These are preferences with reasons, not laws — the human can override
any of them by saying so.

## Return values as expressions, not variables

Prefer the block-method form over build-a-local-then-return-it: the result becomes the expression's value and the trailing variable disappears.

Accumulating into a collection - prefer a purpose-built method when one exists (`filter_map`, `flat_map`, `sum`, `index_by`, `index_with`, `to_h`, `transform_values`); fall back to `each_with_object`:

Bad:

```ruby
targets = []
parents.each do |parent|
  target = index[parent]
  targets << target if target
end
targets
```

Good:

```ruby
parents.each_with_object([]) do |parent, targets|
  target = index[parent]
  targets << target if target
end
```

Transforming a hash's values - use `transform_values` (configure-in-place would be `tap`):

Bad:

```ruby
labels = names.dup
labels.each do |key, value|
  labels[key] = label(value)
end
labels
```

Good:

```ruby
names.transform_values { |value| label(value) }
```

## Judgment boundary

Do not force the idiom when it gets contorted: multiple exit points, heavily conditional accumulation, or a result built across unrelated branches. Readability wins - no linter or quality metric measures this.

# No inline `when x then y` one-liners

Never write single-line `when` branches — always multi-line blocks.

Bad:

```ruby
case status
when :active then :green
else :red
end
```

Good:

```ruby
case status
when :active
  :green
else
  :red
end
```

# Empty method definitions

Never write one-lined empty methods — use the expanded form with exactly one comment token saying why: `# Render` (implicit render), `# NOOP` (deliberately nothing), `# Implement in subclasses` (base-class hook). If none apply, stop and ask — never invent a token, never leave the body bare. Empty classes in migrations referencing models are exempt.

Bad:

```ruby
def show; end
```

Good:

```ruby
def show
  # Render
end
```

# Blocks: `{}` vs `do...end`

Single-line `{}` is fine when it's the only block or complexity on its line. Nested blocks, a chain plus a block on one line, or a crammed `{}` — prefer multiline `do...end`; extract nothing, just break the line up.

Bad:

```ruby
orders.each { |order| line_items.select { |li| li.order_id == order.id }.each(&:archive) }
```

Good:

```ruby
orders.each do |order|
  line_items
    .select { |li| li.order_id == order.id }
    .each(&:archive)
end
```

# Flash messages on their own line

Never as arguments to `redirect_to` or `render`.

Bad:

```ruby
redirect_to thing_path(thing), alert: 'Saved'
```

Good:

```ruby
flash[:success] = 'Saved'
redirect_to thing_path(thing)
```

# ERB views

Hand-write static markup as plain HTML: an element carrying no Ruby —
`<html lang="en">`, `<head>`, static attributes — is clearer as HTML
than as a tag-helper call. Reach for `tag.div` when Ruby enters the
element: interpolated or conditional attributes, computed class lists,
`dom_id`s. The rule governs where Ruby meets markup, not markup itself.

Prefer long single lines; let the editor soft-wrap — never manually break
a tag call across source lines. Compute non-trivial values (class lists,
text) in a helper or local before the markup.

Conditional classes use the `class_names` hash form
(`'justify-center': messages.empty?`), not `if`-modifier array elements —
herb's ERB parser can't parse the latter.

Pass partial locals as bare keyword arguments, not a `locals:` hash.

Herb disables are a last resort; the directive goes at the start of the
line, before the code: `<%# herb:disable rule-name %><%= ... %>`.

Non-HTML templates (the JSON manifest) fall outside this section.

# `self.` over `class << self`

Bad:

```ruby
class << self
  def find_latest
    ...
  end
end
```

Good:

```ruby
def self.find_latest
  ...
end
```

# `private_class_method` per method

Bad:

```ruby
def self.find_latest
  ...
end

def self.build_query
  ...
end

private_class_method :find_latest, :build_query
```

Good:

```ruby
def self.find_latest
  ...
end
private_class_method :find_latest

def self.build_query
  ...
end
private_class_method :build_query
```

# Command-style calls omit parentheses

Omit parens when the call stands alone as a statement or implicit return — `if`/`unless` modifiers, keyword args, and `do` blocks included. Keep them when the call is embedded in a larger expression: nested, chained, multiline, in a literal, followed by an index or chain, in interpolation, or on a `{}` block.

Bad:

```ruby
system('git', 'add')
redirect_to(url, status: 303)
File.open('log') do |file|
```

Good:

```ruby
system 'git', 'add'
redirect_to url, status: 303
File.open 'log' do |file|
# embedded — parens stay
get('me', token)[:user]
JSON.parse(File.read(path))
range(year).first
```

# Multi-line argument calls

A multi-line method call takes one of two shapes.

Data arguments: parenthesize, one argument per line.

Bad:

```ruby
foo a, b,
  c
```

Good:

```ruby
foo(
  a,
  b,
  c
)
```

Lambda (`-> {}`) or block-pass (`&foo`) arguments: the call keeps its signature and block opener on one line and breaks inside the block — a lambda carries code, not data; the list-of-values shape misreads it.

Bad:

```ruby
scope :active,
  -> {
    where(active: true)
  }
```

Good:

```ruby
scope :active, -> {
  where(active: true)
}
```

# No vertical argument alignment

Don't align keyword arguments or hash values across consecutive lines — single space after each comma.

Bad:

```ruby
column :name,   from: "users"
column :amount, sql: "cents / 100"
```

Good:

```ruby
column :name, from: "users"
column :amount, sql: "cents / 100"
```

# RuboCop disable directives

Line-scoped suppression is `# rubocop:disable-next <Cop> — reason`.
This is a real RuboCop mode (since 1.71; `AVAILABLE_MODES` in the gem's
`directive_comment.rb`), but it postdates most models' training data —
agents will insist it doesn't exist and "fix" it to `disable-next-line`,
which RuboCop silently ignores, killing the suppression. Don't accept the
correction.

```ruby
# rubocop:disable-next Style/NumericLiterals — epoch milliseconds
fetched_at = 1761206400000
```

Next line only. Every disable carries a why. Never disable/enable
wrappers (scopes leak — fix the code or tune the cop), never class or
file scope.

# No trailing comments

Comments start with a capital letter.

Bad:

```ruby
get('whoami', token)[:user]  # Trailing index keeps parens
```

Good:

```ruby
# Trailing index keeps parens
get('whoami', token)[:user]
```

# `to_not` over `not_to` in specs

One-token deletion when negating an assertion — editing practicality
beats mnemonic symmetry.

Bad:

```ruby
expect { described_class.report }.not_to output(/scratch/).to_stdout
```

Good:

```ruby
expect { described_class.report }.to_not output(/scratch/).to_stdout
```

# Drive-by policy

Fix violations in code you're already touching; leave the rest alone.

# Scratch files in Rails apps

When a task needs scratch files - debugging dumps, generated output, temp data - write them to the Rails app's `tmp/` directory, not `/tmp` or system temp dirs. The app's `tmp/` is inside the workspace, so writes there need no directory permission, Rails gitignores it, and `rails tmp:clear` cleans it up.

# Quality checks

The gates are rubocop, reek, and herb, run full-repo via `bin/quality`.
Lefthook runs all three on staged files at every commit; before saying
a task is done, run `bin/quality` across the repo. The check is a
report, not a mandate — we want code we are happy with, not just code
that passes generic quality checks.

# Quality review (interactive)

When addressing gate findings, do not assume the fix. Report totals
grouped by tool — autocorrectable vs manual — and work the findings
with rsl, one group at a time:

- Propose a working order and wait for agreement: safe
  autocorrectables; unsafe autocorrectables in small reviewed groups;
  judgment calls (naming, config); metrics refactors — real design
  decisions, one method at a time. Offer offense-by-offense instead of
  batches if rsl prefers; ask.
- For each group: show the site(s) and a concrete before/after, then
  discuss — rsl may refactor, suggest alternatives, or put it in the
  "won't fix" bucket. Apply only on explicit approval; re-run the
  check on the affected files and confirm the offense cleared.
- Refactors that clear one offense often introduce new ones
  (complexity shifts shape; reek flags the new shape). Each new
  finding is a new group — stop and report it before fixing.
- Behavior changes are called out explicitly, never smuggled into a
  "stylistic" fix.
- Tuning cops in `.rubocop.yml` is a config decision, not a fix —
  bring it to rsl first.
- Dead code: confirm zero callers before proposing deletion; deletion
  still needs approval.
- Keep a running "won't fix" bucket and surface it at the end for a
  final decision (inline disable vs config change vs leave as-is).