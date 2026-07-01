# Worker Verify Recipes

Named acceptance recipes so worker prompts don't repeat multi-line test scripts.

Orchestrator writes: `ACCEPTANCE: recipe <name>`
Worker looks up the expansion here and runs it verbatim.

## recipe: syntax-check

Verify a bash script is syntactically valid.

```
bash -n <script-path> && echo OK
```

## recipe: exec-bit

Verify a file is executable.

```
[ -x <path> ] && echo OK
```

## recipe: smoke-pass

Verify smoke test still passes after change.

```
cd /Users/gx/qoder-swarm && bash tests/smoke-test.sh 2>&1 | tail -3 | grep -q "failed: 0" && echo OK
```

## recipe: yaml-valid

Verify agent frontmatter is parseable YAML.

```
python3 -c "import yaml, sys; yaml.safe_load(open(sys.argv[1]).read().split('---')[1])" <path>
```

## recipe: race-safe

Verify concurrent invocations of a state-mutating script don't corrupt state.
Usage: `recipe race-safe <script> <acquire-cmd> <verify-cmd> <expected>`

```
for i in $(seq 1 5); do ( <acquire-cmd> & ); done; wait
[ "$(<verify-cmd>)" = "<expected>" ] && echo OK
```

## recipe: grep-count-min

Verify a grep count meets minimum.
Usage: `recipe grep-count-min <pattern> <file> <min>`

```
[ "$(grep -c '<pattern>' <file>)" -ge <min> ] && echo OK
```

## recipe: jsonl-schema

Verify a JSONL file has required fields per line.
Usage: `recipe jsonl-schema <file> <field1> <field2> ...`

```
jq -e 'select(.<field1> and .<field2>)' <file> > /dev/null && echo OK
```

## recipe: file-exists

Sanity — file was actually created.

```
[ -f <path> ] && echo OK
```

## recipe: frontmatter-model

Verify agent frontmatter has expected model.

```
[ "$(grep -m1 '^model:' <path> | awk '{print $2}')" = "<expected-model>" ] && echo OK
```

## How to add a new recipe

If a new dispatch would use the same verify pattern more than twice, add it here. Otherwise inline it.
