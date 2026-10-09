# Numbers

Only the values I chose myself. Anything the brief fixes (the AED 25.00 fee, the 0.04% rate,
2 and 3 decimal places, the Day 1 to Day 6 window, approval at "at or above zero") is not
listed, because there was nothing to decide.

| Constant | Value | Where |
|---|---|---|
| Rounding mode | half-up | `Money.round_half_up` |
| Instalment remainder | goes on the last instalment | `post_cash` |
| BHD overdraft fee | none | `Book::OVERDRAFT_FEE` |
| "Negative" for the fee test | strictly below zero | `close_day` |
| Hold lifetime | never expires | `holds` |
| Too many decimals | rejected, not rounded | `Money.parse` |

## Why these values, and not the alternative

**Half-up rounding (not floor, not banker's).** The brief says only "rounded". Half-up is what
someone doing the sums on paper expects (0.005 becomes 0.01), so it is the easiest to defend by
hand. Floor would give a 90-fil total instead of 93 and always favour the bank. Banker's rounding
differs from half-up only on exact halves, and none of this replay's accruals land on one, so
the outputs would be identical here. Half-up is used for interest only.

**Remainder on the last instalment (not the first).** "Three equal instalments" of BHD 10.000 is
impossible, since 10.000 / 3 does not divide. Putting the leftover on the first gives
3.334, 3.333, 3.333. Putting it on the last gives 3.333, 3.333, 3.334. Either keeps the total at
exactly 10.000. I picked the last because it is the common convention. The one thing I ruled out
is 3.334 for all three, which totals 10.002 and creates 2 fils from nothing.

**No BHD overdraft fee (not a copy of the AED one).** The brief defines a fee for AED only.
Reusing 25.00 for BHD would be a different amount of real money, since a dinar is worth about
ten dirhams, and I had nothing to base a BHD figure on. So no fee is charged, and an error line
says so once per account and day, so the gap is visible and not silent.

**Strictly negative (not "zero or below").** A balance of exactly 0.00 is not overdrawn, so it is
not charged. If the bank meant `<= 0`, one comparison in `close_day` changes.

**Holds never expire (not a timed expiry).** The brief gives no expiry, and any number I invented
(24 hours, 7 days) would be a guess that changes results. An approved hold lasts until it is
settled. The cost of this is listed in DESIGN.md section 3.

**Reject extra decimals (not round them).** AED 1.005 has no valid two-place value, and picking
1.00 or 1.01 would silently change the customer's money. Rejecting it records an error and moves
nothing.
