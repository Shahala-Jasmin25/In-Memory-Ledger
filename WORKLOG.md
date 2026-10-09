# Worklog

## 2026-10-07

11:00 => Read through the assessment brief, then used Claude to explain each requirement in detail breaking down the analysis step by step.
11:20 => Refreshed my knwoledge in ledger basics and compared them with how we handled it in my past works.Used that to decide how this design should store and recalculate balances.
11:45 => Rated the difficulty. Main risk identified: the backdated E7 debit changes the balance of days that are already closed.
12:30 => Wrote down the rules from the brief and broke them into small pieces of logic to implement in Ruby, so I could build and test each one separately.
2:30 => Ruby LSP would not start, so no has issues with navigation. Cause: no Gemfile in the folder, and the LSP's own bundle download was timing out in the editor. Fixed the issue first as it is painful to work without it. (Not related to the assessment but highly required)
2:45 => Started implementing the solution using Claude, following the logic I had planned earlier. Before starting the implementation, I went through a few rounds of interaction with Claude to validate the logic against the requirements and identify any necessary updates.
3:30 => Updating the code-generated scaffold and running the implementation, making adjustments to the changes I wasn’t happy with. For instance, swapped the suite to Rspec rom minitest, and wrote some guidelines on the level of test coverage I intended.
17:00 => Went through the parts of `Money.parse` I didn't fully understand: `Rational`, `Struct`, `keyword_init`, `divmod`. Considered the `money` gem and decided against it
17:40 => E9 (Day 6) is listed before E10 (Day 5). Chose to replay by booked day, listed order within a day, and recorded it as AMBIGUITIES item.


## 2026-10-08
8:28 => Analysed what happens if a late credit makes an already-fined day positive. Current rule: one fee per account and value date, ever. Kept it and noted it.
9:00 =>  Looked at whether to keep rejecting amounts with too many decimals. Compared a `money` gem. Raised that the brief says amounts are "rounded to their own precision". Decided to reject as it is adopted by standard payment gateways
10:30 => Working on test cases and polishing the implementation.
12:00 => Drafting the required .md files requested, based on the analysis
1:00 => working on the architecture and trade-offs document


## 2026-10-09
10:00 => Pushed the initil commit with working logic
10:10 => Working on polishing the test suite.
