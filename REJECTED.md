# Rejected criteria

Four of the eight acceptance criteria are wrong. Each is refused below, with the number that
proves it. The four others (1, 3, 4, 5) are accepted; see the last section.

## Criterion 2: "E7 causes exactly one overdraft fee, on Day 2" — REFUSED

E7 is booked on Day 5 with value date Day 2, so it lowers every closing from Day 2 onward.

| Value date | Closing before E7 | Closing as known after E7 | Negative? |
|---|---|---|---|
| Day 2 | 250.00 | −370.00 | yes, fee |
| Day 3 | 650.00 | 30.00 − 25.00 (Day 2 fee) = 5.00 | no |
| Day 4 | 465.00 | 5.00 − 185.00 = −180.00 | yes, fee |
| Day 5 | 465.00 | −180.00 − 25.00 (Day 4 fee) = −205.00 | yes, fee |

The Day 2 fee feeds forward into Day 3, which is why Day 3 stays positive (5.00) and gets no
fee, but Days 4 and 5 are both negative. **Three** fees (AED 75.00 total), value dates 2, 4, 5.
Test: `charges three fees for E7, not one`.

## Criterion 6: "After E9, all balances and fees return to their pre-E7 values" — REFUSED

E9 reverses E7 by posting an opposing entry; nothing is edited or deleted (the ledger is
append-only). The three fees were assessed on the basis of balances that E7 created, and no rule
says a reversal refunds them. After E9 the Day 4 closing is 390.00, not the pre-E7 465.00. The
75.00 gap is exactly the three fees, and all three fees are still on the books.

Making this criterion true needs a fee-refund policy (a second reversing entry per fee). The
brief does not define one, and inventing it would be a business decision, not an implementation
detail. This is the deliberately failing spec: `rake failing`.

## Criterion 7: "The three BHD instalments in E10 must each be BHD 3.334" — REFUSED

10.000 BHD = 10,000 fils. Three times 3.334 = 10.002, which creates 0.002 BHD out of nothing.
The instalments must sum to the posted total, so they are **3.333, 3.333, 3.334**, with the
indivisible remainder on the last. Test: `split 3.333, 3.333, 3.334`.

## Criterion 8: "If the rounded accruals do not sum to the capitalized total, the remainder is discarded" — REFUSED

The non-negotiable rules say the rounded daily accruals **must sum exactly** to the capitalized
total. Discarding a remainder would mean the posted credit and the accrual schedule disagree,
which is precisely the failure the rule exists to prevent. The capitalized credit is defined as the sum of the rounded accruals, so
the invariant holds by construction (AED: 10+9+25+17+16+16 = 93). Test: `AED accruals sum exactly
to the capitalised credit`.

## Accepted criteria

- **1** correct: 1,200 − 950 − 620 = −370.00 (the Auth-A hold does not touch the ledger).
- **3** correct: Auth-A was approved (250 − 200 ≥ 0) and 185 ≤ the 200 hold.
- **4** correct: Auth-Z is rejected, no funds move.
- **5** correct but vacuous: it is conditional on Auth-B being approved, and Auth-B is
  **declined** (ledger −155.00, available after hold −245.00). The holds-vs-ledger behaviour is
  tested on Auth-A and on a standalone account instead.

## Design alternatives considered and not adopted

These are alternatives visible in the design, not a record of mid-build history.

- **Refund fees on reversal.** Rejected as above: unspecified policy.
- **Round the total interest once** (would give 92 vs the 93 sum of daily roundings; exact is
  91.8). Not adopted: the brief requires the *daily* roundings to sum to the credit.
- **Floats for money.** Not adopted: integer minor units avoid binary rounding error.
- **Mutating or deleting E7 on reversal.** Not adopted: the ledger is append-only.
