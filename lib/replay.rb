# frozen_string_literal: true

require_relative "ledger"

# The brief's event stream, the day loop, and the printed report.
module Replay
  LAST_DAY = 6

  ACCOUNTS = [
    Ledger::Account.new(id: "ACC-001", currency: "AED", scale: 2, opening: "0.00"),
    Ledger::Account.new(id: "ACC-002", currency: "BHD", scale: 3, opening: "0.000")
  ].freeze

  def self.ev(**kw) = Ledger::Event.new(**kw)

  # Listed order is preserved within a booked day. NOTE: E9 (Day 6) is listed before E10 (Day 5),
  # but we replay by booked day, so E10 runs first. See AMBIGUITIES.md.
  EVENTS = [
    ev(id: "E1",  day: 1, type: :credit,        account: "ACC-001", amount: "1,200.00", value_date: 1),
    ev(id: "E2",  day: 1, type: :debit,         account: "ACC-001", amount: "950.00",   value_date: 1),
    ev(id: "E3",  day: 2, type: :authorization, account: "ACC-001", amount: "200.00",   value_date: 2, auth_id: "Auth-A"),
    ev(id: "E4",  day: 3, type: :credit,        account: "ACC-001", amount: "400.00",   value_date: 3),
    ev(id: "E5",  day: 4, type: :settlement,    account: "ACC-001", amount: "185.00",   value_date: 4, auth_id: "Auth-A"),
    ev(id: "E6",  day: 4, type: :settlement,    account: "ACC-001", amount: "180.00",   value_date: 4, auth_id: "Auth-Z"),
    ev(id: "E7",  day: 5, type: :debit,         account: "ACC-001", amount: "620.00",   value_date: 2),
    ev(id: "E8",  day: 5, type: :authorization, account: "ACC-001", amount: "90.00",    value_date: 5, auth_id: "Auth-B"),
    ev(id: "E9",  day: 6, type: :reversal,      account: "ACC-001", amount: "620.00",   value_date: 2, ref: "E7"),
    ev(id: "E10", day: 5, type: :credit,        account: "ACC-002", amount: "10.000",   value_date: 5, instalments: 3)
  ].freeze

  def self.play(through: LAST_DAY, close_last: true, capitalize: true, out: nil)
    book = Ledger::Book.new(ACCOUNTS)
    (1..through).each do |day|
      EVENTS.select { |e| e.day == day }.each { |e| book.apply(e) }
      next if day == through && !close_last

      book.close_day(day)
      pre = book.accounts.keys.to_h { |id| [id, book.balance(id, day)] }
      capitalised = day == LAST_DAY && capitalize ? book.capitalize_interest(day) : {}
      Report.day(out, book, day, pre, capitalised) if out
    end
    Report.summary(out, book) if out && through == LAST_DAY
    book
  end

  module Report
    module_function

    def m(book, id, minor) = Ledger::Money.fmt(minor, book.accounts.fetch(id).scale)

    def day(out, book, day, pre, capitalised)
      out.puts "=== Day #{day} ==="
      out.puts "events:"
      book.events.select { |e| e.day == day }.each do |e|
        extra = [e.auth_id, (e.ref && "reverses #{e.ref}"), (e.instalments && "#{e.instalments} instalments")].compact.join(", ")
        out.puts "  #{e.id} #{e.type.to_s.upcase} #{e.account} #{e.amount} (value Day #{e.value_date})#{extra.empty? ? '' : " [#{extra}]"}"
      end
      book.accounts.each_value do |a|
        closing = pre.fetch(a.id)
        holds = book.holds(a.id)
        out.puts "#{a.id} #{a.currency}: closing ledger #{m(book, a.id, closing)} | holds #{m(book, a.id, holds)} | available #{m(book, a.id, closing - holds)}"
        fees = book.entries.select { |e| e.kind == :fee && e.account == a.id && e.booked_day == day }
        if fees.empty?
          out.puts "  fees: none"
        else
          fees.each { |f| out.puts "  fee: #{m(book, a.id, f.amount)} booked Day #{day}, value Day #{f.value_date}" }
        end
        total = capitalised[a.id]
        if total
          out.puts "  interest capitalised: +#{m(book, a.id, total)} -> closing after capitalisation #{m(book, a.id, book.balance(a.id, day))}"
        end
      end
      out.puts "authorizations:"
      auths = book.auth_records.select { |r| r.day == day }
      out.puts "  none" if auths.empty?
      auths.each { |r| out.puts "  #{r.event_id} #{r.auth_id} #{r.status.to_s.upcase} (#{r.note})" }
      out.puts "errors:"
      errs = book.errors.select { |r| r.day == day }
      out.puts "  none" if errs.empty?
      errs.each { |r| out.puts "  #{r.event_id}: #{r.message}" }
      out.puts
    end

    def summary(out, book)
      out.puts "=== Restated closings and interest (final knowledge) ==="
      book.accounts.each_value do |a|
        rows = book.accruals.select { |r| r.account == a.id }
        out.puts a.id
        rows.each { |r| out.puts "  Day #{r.day}: closing #{m(book, a.id, r.closing)} accrual #{m(book, a.id, r.amount)}" }
        sum_rounded = rows.sum(&:amount)
        exact = Rational(rows.sum { |r| [r.closing, 0].max }) * Ledger::Book::DAILY_RATE
        out.puts format("  sum of rounded accruals: %s (= capitalised credit)", m(book, a.id, sum_rounded))
        out.puts format("  exact unrounded interest: %.6f, drift %+.6f", exact.to_f / (10**a.scale), (sum_rounded - exact).to_f / (10**a.scale))
        out.puts "  final ledger balance: #{m(book, a.id, book.balance(a.id, LAST_DAY))}"
      end
    end
  end
end
