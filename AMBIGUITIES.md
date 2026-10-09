# Ambiguities

Every gap or conflict I found in the brief, and how I resolved it. Where the resolution
changes an output, the effect is stated.

## Ordering and dates

1. **Listed order vs booked day.** The stream is "replayed in this order", but E9 (Day 6) is
   listed before E10 (Day 5). *Resolution:* replay by booked day, keeping listed order within a day,
   so E10 runs on Day 5 and E9 on Day 6. Replaying literally would apply a Day 6 event before a
   Day 5 one. The day-by-day report and "closing balance per day" only make sense in booked-day order.

   *What the choice changes (measured, not assumed).* I replayed the stream three ways:

   | Replay | Overdraft fees (value dates) | ACC-001 Day 6 balance before interest |
   |---|---|---|
   | Booked-day order (this design) | 2, 4, 5 | 390.00 |
   | Literal listed order, Day 5 closed before E9 runs | 2, 4, 5 | 390.00 |
   | Literal listed order, **no close until after E9** | none | 465.00 |

   Applying E9 before E10 does not matter on its own: they touch different accounts, and as long
   as Day 5 is closed before E9 arrives, the result is identical (row 2). The result only changes if
   the day close is deferred until after E9, because then E7 is already reversed when fees are
   tested, no day is negative, and E7 causes no fees at all. That would remove the scenario the
   brief is built around (and make criterion 6 trivially true), so I treat E9 as arriving on
   Day 6, after the Day 5 close. If the intended reading is the third row, criteria 2 and 6 flip.
2. **Which closing is "the" closing?** A day's closing changes when a backdated event arrives later.
   *Resolution:* two views. The per-day block prints the closing **as known at end of that day**;
   the summary prints the **restated** closing with final knowledge. Fees use the closing as known
   when assessed (that is how E7 triggers fees on Day 5); interest uses the restated closing.
3. **Criterion 1 timing.** "Day 2 closing, evaluated at end of Day 5 and before any fee": I read
   this as "after E7 is applied, before Day 5's close runs", giving −370.00. Tested with
   `close_last: false`.
4. **When is a backdated fee assessed, and with what dates?** Fees for value dates 2 and 4 are
   discovered on Day 5. *Resolution:* booked on Day 5 (`booked_day`), `value_date` = the day
   assessed, as the brief says ("value_date equal to the day assessed").

## Fees

5. **"Once per day per account" with backdating.** *Resolution:* one fee per (account, value
   date), ever. Re-running `close_day` is idempotent. A day assessed negative is never
   re-assessed, even if a later reversal makes it positive.
6. **Does a fee affect later days' tests?** The brief does not say. *Resolution:* yes, a fee is a
   real entry, so it lowers every later closing. Days are assessed in ascending order, so the Day 2
   fee is in the Day 3 balance. Effect: Day 3 closes at 5.00 and gets no fee (see NUMBERS.md for how
   fragile that is).
7. **Zero balance.** "Negative" means strictly below zero; exactly 0.00 gets no fee.
8. **BHD fee.** The brief defines an AED fee only. *Resolution:* no fee for BHD, and an error
   (reported once per account per day) so it is not silent: `no overdraft fee defined for BHD`.
9. **Reversal and fees.** The brief says nothing about refunding the fees E7 caused.
   *Resolution:* not refunded (see REJECTED.md, criterion 6).

## Authorizations and settlements

10. **What does "available" use?** Ledger as of the authorization's own value date, minus **all**
    currently active holds (regardless of their dates). Holds have no expiry.
11. **Exactly zero.** Available landing on exactly 0.00 after the hold is **approved**
    ("at or above zero").
12. **Auth-B.** Applied on Day 5 after E7 (listed earlier), so ledger as of Day 5 is −155.00 and
    available after the hold is −245.00: **declined**. Had it been applied before E7 it would
    have been approved, so event order within the day matters. The brief's "Auth-B is never settled"
    is moot because it was never approved.
13. **Settlement for less than the hold.** E5 settles 185.00 against a 200.00 hold.
    *Resolution:* the whole hold is released (not 15.00 left behind), and 185.00 is debited.
14. **Settlement greater than the hold.** Rejected, no funds move.
15. **Duplicate settlement or duplicate authorization ID.** Rejected, with an error.
16. **Auth-Z (E6).** No preceding authorization. *Resolution:* recorded as `SETTLEMENT_REJECTED`
    and an error; **no entry is posted**. The error text carries "no funds moved".
17. **Settlement value date vs hold.** Settlement posts at its own value date (Day 4), not the
    authorization's. The hold (not a ledger entry) simply disappears from `holds`.

## Reversal

18. **What does E9's amount do?** E9 repeats "620.00", but I reverse the *original entries* of
    E7, so the figure is informational and is not cross-checked. *Resolution:* reversal takes
    amounts from E7's entries; value date must match E7's (Day 2) or it is rejected.
19. **Reversal of anything other than a credit/debit.** Only `credit` / `debit` entries are
    reversible; reversing a fee, settlement or interest entry is rejected as "no reversible event".
20. **Double reversal and cross-account reversal.** Both rejected.

## Interest

21. **Which balance accrues?** Restated (final-knowledge) closing for each of Days 1 to 6,
    including the fees and E7/E9, positive balances only. Day 2's restated closing is 225.00
    (250 − 25), not the −370.00 seen at Day 5.
22. **Rounding.** Per-day half-up on the rational product, then summed; the capitalized credit *is*
    that sum, so "rounded accruals sum exactly to the total" holds by construction. The sum (93) differs from
    rounding the exact total (91.8 → 92); I chose the one the brief's rule requires.
23. **Day 6 and capitalization date.** Day 6 itself accrues. The credit is booked and valued on
    Day 6 and is not itself in any day's accrual base (no interest on interest in-window).
24. **Zero total.** If a total rounds to 0, no interest entry is posted (BHD would otherwise
    post a zero entry).
25. **Capitalizing twice** raises an error.

## Money and instalments

26. **"Three equal instalments" of 10.000.** Not divisible. *Resolution:* 3.333, 3.333, 3.334
    with the remainder on the last (see NUMBERS.md). All three share E10's booked and value date.
27. **Precision.** More decimals than the account's currency allows (e.g. AED 1.005) is
    *rejected* rather than rounded, so no money is silently altered. Input commas are accepted ("1,200.00").
28. **Opening balances** are 0, so no opening entries are posted.
29. **Rejected events are still recorded** in `events` (append-only: nothing is dropped), and appear in
    the day's error list; they post no entries.
