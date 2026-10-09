# frozen_string_literal: true

require "spec_helper"

# Expected values below are hand-derived from the brief, NOT copied from program output.
# Re-derive them on paper before the defense.
RSpec.describe Ledger do
  let(:a) { "ACC-001" }
  let(:b) { "ACC-002" }

  def fees(book, acct = "ACC-001") = book.entries.select { |e| e.kind == :fee && e.account == acct }

  def standalone_book(id: "X", currency: "AED", scale: 2, opening: "1000.00")
    Ledger::Book.new([Ledger::Account.new(id: id, currency: currency, scale: scale, opening: opening)])
  end

  def event(**kw) = Ledger::Event.new(**kw)

  describe "day closings" do
    it "are as known at the end of each day" do
      expect(Replay.play(through: 1).balance(a, 1)).to eq(25_000) # 1200 - 950
      expect(Replay.play(through: 2).balance(a, 2)).to eq(25_000) # a hold does not touch the ledger
      expect(Replay.play(through: 3).balance(a, 3)).to eq(65_000) # +400
      expect(Replay.play(through: 4).balance(a, 4)).to eq(46_500) # -185 (Auth-A settlement)
    end

    it "puts Day 2 at -370.00 at end of Day 5 before any fee (criterion 1)" do
      book = Replay.play(through: 5, close_last: false)
      expect(book.balance(a, 2)).to eq(-37_000)
      expect(fees(book)).to be_empty
    end
  end

  describe "authorizations" do
    it "approves Auth-A and the hold reduces available, not ledger" do
      book = Replay.play(through: 2)
      expect(book.auth_records.find { |r| r.auth_id == "Auth-A" }.status).to eq(:approved)
      expect(book.balance(a, 2)).to eq(25_000)
      expect(book.holds(a)).to eq(20_000)
      expect(book.available(a, 2)).to eq(5_000)
    end

    it "declines Auth-B because backdated E7 makes available negative" do
      book = Replay.play(through: 5)
      auth_b = book.auth_records.find { |r| r.auth_id == "Auth-B" }
      expect(auth_b.status).to eq(:declined)
      expect(auth_b.note).to match(/available after hold -245\.00/)
      expect(book.holds(a)).to eq(0)
    end

    it "keeps the ledger unchanged and lands exactly on zero as approved" do
      book = standalone_book
      book.apply(event(id: "T1", day: 1, type: :authorization, account: "X", amount: "300.00", value_date: 1, auth_id: "A1"))
      expect(book.balance("X", 1)).to eq(100_000)
      expect(book.available("X", 1)).to eq(70_000)
      book.apply(event(id: "T2", day: 1, type: :authorization, account: "X", amount: "700.00", value_date: 1, auth_id: "A2"))
      expect(book.auth_records.last.status).to eq(:approved)
      book.apply(event(id: "T3", day: 1, type: :authorization, account: "X", amount: "0.01", value_date: 1, auth_id: "A3"))
      expect(book.auth_records.last.status).to eq(:declined)
    end
  end

  describe "settlements" do
    it "accepts Auth-A on Day 4 and releases the hold (criterion 3)" do
      book = Replay.play(through: 4)
      expect(book.auth_records.map(&:status)).to include(:settled)
      expect(book.holds(a)).to eq(0)
      expect(book.entries.count { |e| e.kind == :settlement && e.amount == -18_500 }).to eq(1)
    end

    it "rejects an unknown auth and no funds leave (criterion 4)" do
      book = Replay.play(through: 4)
      expect(book.entries.select { |e| e.event_id == "E6" }).to be_empty
      expect(book.auth_records.map(&:status)).to include(:settlement_rejected)
      expect(book.errors.find { |e| e.event_id == "E6" }.message).to match(/no funds moved/)
      expect(book.balance(a, 4)).to eq(46_500) # only Auth-A's 185.00 left the account
    end

    it "rejects over-hold and duplicate settlements" do
      book = standalone_book
      ev = ->(id, type, amt, auth) { event(id: id, day: 1, type: type, account: "X", amount: amt, value_date: 1, auth_id: auth) }
      book.apply(ev.("T1", :authorization, "100.00", "A1"))
      book.apply(ev.("T2", :settlement, "100.01", "A1")) # over the hold
      book.apply(ev.("T3", :settlement, "100.00", "A1")) # ok
      book.apply(ev.("T4", :settlement, "100.00", "A1")) # duplicate
      expect(book.errors.map(&:event_id)).to eq(%w[T2 T4])
      expect(book.balance("X", 1)).to eq(90_000)
    end
  end

  describe "overdraft fees" do
    it "charges three fees for E7, not one (criterion 2 is wrong)" do
      book = Replay.play(through: 5)
      expect(fees(book).map(&:value_date)).to eq([2, 4, 5])
      expect(fees(book)).to all(have_attributes(amount: -2_500, booked_day: 5))
      expect(book.balance(a, 5)).to eq(-23_000) # -155.00 restated, minus 3 x 25.00
    end

    it "does not charge on Day 3 because the Day 2 fee feeds forward" do
      book = Replay.play(through: 5)
      expect(book.balance(a, 3)).to eq(500) # 30.00 - 25.00
      expect(fees(book).select { |f| f.value_date == 3 }).to be_empty
    end

    it "is idempotent" do
      book = Replay.play(through: 5)
      2.times { book.close_day(5) }
      expect(fees(book).size).to eq(3)
    end

    it "reports, rather than silently skips, a currency with no fee defined" do
      book = standalone_book(id: "Y", currency: "BHD", scale: 3, opening: "0.000")
      book.apply(event(id: "T1", day: 1, type: :debit, account: "Y", amount: "1.000", value_date: 1))
      book.close_day(1)
      expect(book.entries.select { |e| e.kind == :fee }).to be_empty
      expect(book.errors.last.message).to match(/no overdraft fee defined/)
    end
  end

  describe "reversals" do
    it "are append-only and leave fees in place (criterion 6 is wrong)" do
      book = Replay.play(through: 6, capitalize: false)
      expect(book.balance(a, 6)).to eq(39_000)
      expect(fees(book).size).to eq(3)
      expect(book.entries.count { |e| e.event_id == "E7" }).to eq(1)  
      rev = book.entries.find { |e| e.kind == :reversal }
      expect([rev.amount, rev.value_date, rev.ref]).to eq([62_000, 2, "E7"])
    end

    it "rejects a double reversal" do
      book = Replay.play(through: 6)
      book.apply(event(id: "E9b", day: 6, type: :reversal, account: a, amount: "620.00", value_date: 2, ref: "E7"))
      expect(book.errors.last.message).to match(/already reversed/)
    end
  end

  describe "BHD instalments" do
    it "split 3.333, 3.333, 3.334 (criterion 7 is wrong)" do
      book = Replay.play(through: 5)
      parts = book.entries.select { |e| e.account == b && e.kind == :credit }
      expect(parts.map(&:amount)).to eq([3_333, 3_333, 3_334])
      expect(parts.sum(&:amount)).to eq(10_000)
      expect(Ledger::Money.fmt(parts.last.amount, 3)).to eq("3.334")
    end
  end

  describe "interest" do
    it "AED accruals sum exactly to the capitalised credit (criterion 8 is wrong)" do
      book = Replay.play
      rows = book.accruals.select { |r| r.account == a }
      expect(rows.map(&:closing)).to eq([25_000, 22_500, 62_500, 41_500, 39_000, 39_000])
      expect(rows.map(&:amount)).to eq([10, 9, 25, 17, 16, 16])
      cap = book.entries.find { |e| e.kind == :interest && e.account == a }
      expect(cap.amount).to eq(93)
      expect(cap.amount).to eq(rows.sum(&:amount))
      expect(book.balance(a, 6)).to eq(39_093)
    end

    it "BHD accrues only on the last two days and ends at 10.008" do
      book = Replay.play
      rows = book.accruals.select { |r| r.account == b }
      expect(rows.map(&:amount)).to eq([0, 0, 0, 0, 4, 4])
      expect(book.balance(b, 6)).to eq(10_008)
    end
  end

  describe "precision" do
    it "is enforced per currency" do
      book = Ledger::Book.new(Replay::ACCOUNTS)
      book.apply(event(id: "T1", day: 1, type: :credit, account: a, amount: "1.005", value_date: 1))
      expect(book.errors.last.message).to match(/more than 2 decimal places/)
      expect(book.entries).to be_empty
    end
  end

  describe "append-only guarantees" do
    it "freezes the views and the records" do
      book = Replay.play
      expect { book.entries << :x }.to raise_error(FrozenError)
      expect { book.entries.first.amount = 0 }.to raise_error(FrozenError)
      expect { book.events.first.amount = "0.00" }.to raise_error(FrozenError)
      expect(book.entries.map(&:seq)).to eq((1..book.entries.size).to_a)
    end
  end
end
