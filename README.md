# In-memory account ledger

An in-memory, append-only account ledger core in plain Ruby. No web layer, no persistence,
no UI, no database. It replays a fixed event stream over six days and prints, per day: closing
ledger balance, holds and available balance, fee assessments, authorization states, and errors.

## Requirements

- Ruby 3.2.2 (see `.ruby-version`)
- The `rspec` gem (`gem install rspec`). Nothing else.

## Layout

```
lib/ledger.rb              core: Money, Book (events, fees, holds, interest)
lib/replay.rb              the event stream, the day loop, and the printed report
replay                     executable: prints the full six-day report
spec/ledger_spec.rb        the suite (hand-derived expectations)
spec/failing/design_spec.rb  one spec that FAILS on purpose (see below)
NUMBERS.md                 every constant, and what changes if it changes
AMBIGUITIES.md            every gap in the brief and how it was resolved
REJECTED.md                acceptance criteria refused, with reasons
```

## Running it

```sh
./replay          # print the six-day report
rake test         # run the suite (default task); expected: 19 examples, 0 failures
rake failing      # run the deliberately failing spec; expected: 1 example, 1 failure
```

`rake failing` exits non-zero. That is the point: it encodes acceptance criterion 6
("after E9 everything returns to pre-E7 values"), which the design cannot satisfy. The
annotations at the top of `spec/failing/design_spec.rb` say what the failure reveals.
Plain `rspec` runs both directories, so it will report that one failure too.

## Reading the report

Each `=== Day N ===` block has:

- **events**: events *booked* that day, with their value date in brackets, e.g.
  `E7 DEBIT ACC-001 620.00 (value Day 2)` means booked Day 5, counted on Day 2.
- **closing ledger / holds / available** per account. *Closing ledger* counts every entry with
  `value_date <= day` as known **at the end of that day**. *Available* = ledger minus active holds.
- **fees**: one line per fee. `booked Day 5, value Day 2` is a fee assessed on Day 5 for Day 2.
  This is how a backdated event shows up.
- **interest capitalised** (Day 6 only): the single lump credit and the closing balance after it.
- **authorizations**: `APPROVED`, `DECLINED`, `SETTLED`, or `SETTLEMENT_REJECTED`, with a note
  showing the arithmetic.
- **errors**: rejected events. A rejected event moves no money.

The final block, **Restated closings and interest**, recomputes every day's closing using
*final* knowledge (E7 and its reversal E9 both known). Interest accrues on these restated
balances, which is why Day 5 prints `-230.00` in its own block but `390.00` in the summary.

Money is stored as integer minor units (fils); `Ledger::Money.fmt` only formats for display.
