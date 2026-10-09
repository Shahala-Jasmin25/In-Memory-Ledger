# frozen_string_literal: true

require "spec_helper"

# THIS SPEC IS EXPECTED TO FAIL. Run it with `rake failing`.
#
# It encodes criterion 6 from the brief: "After E9, all balances and fees return to their
# pre-E7 values."
RSpec.describe "criterion 6: reversal restores the pre-E7 state" do
  it "returns every balance and fee to its pre-E7 value after E9" do
    before = Replay.play(through: 4)
    after  = Replay.play(through: 6, capitalize: false)

    fees_after = after.entries.count { |e| e.kind == :fee }

    expect(fees_after).to eq(0), "fees should be back to pre-E7 (none), got #{fees_after}"
    expect(after.balance("ACC-001", 6)).to eq(before.balance("ACC-001", 4)),
                                           "ledger balance should be back to pre-E7 (465.00), got #{Ledger::Money.fmt(after.balance('ACC-001', 6), 2)}"
  end
end
