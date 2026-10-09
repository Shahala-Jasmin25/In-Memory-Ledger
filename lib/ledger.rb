# frozen_string_literal: true

# In-memory, append-only account ledger core.
# All money is held as Integer minor units (AED = 2 dp, BHD = 3 dp). No floats anywhere.
module Ledger
  module Money
    module_function

    # Turns text like "1,200.00" into whole minor units: 120000.
    # Refuses more decimal places than the currency allows (e.g. "1.005" for AED).
    def parse(str, scale)
      text = str.to_s.delete(",")
      minor = Rational(text) * (10**scale)

      if minor.denominator != 1
        raise ArgumentError, "#{str} has more than #{scale} decimal places"
      end

      minor.to_i
    end

    # For display. Turns minor units back into text: 120000 with scale 2 -> "1200.00".
    def fmt(minor, scale)
      sign = minor.negative? ? "-" : ""
      parts = minor.abs.divmod(10**scale) # [whole units, leftover minor units]
      whole = parts[0]
      fraction = parts[1]
      "#{sign}#{whole}.#{fraction.to_s.rjust(scale, '0')}"
    end

    def round_half_up(rational)
      (rational + Rational(1, 2)).floor
    end
  end

  Account     = Struct.new(:id, :currency, :scale, :opening, keyword_init: true)
  Event       = Struct.new(:id, :day, :type, :account, :amount, :value_date, :auth_id, :ref, :instalments, keyword_init: true)
  Entry       = Struct.new(:seq, :event_id, :account, :kind, :amount, :value_date, :booked_day, :ref, keyword_init: true)
  AuthRecord  = Struct.new(:seq, :event_id, :day, :account, :auth_id, :status, :amount, :note, keyword_init: true)
  ErrorRecord = Struct.new(:day, :event_id, :message, keyword_init: true)
  Accrual    = Struct.new(:account, :day, :closing, :amount, keyword_init: true)

  class Book
    OVERDRAFT_FEE = { "AED" => 2_500 }.freeze
    DAILY_RATE    = Rational(4, 10_000)

    attr_reader :accounts

    def initialize(accounts)
      @accounts = {}
      accounts.each do |account|
        @accounts[account.id] = account
      end

      @events       = []
      @entries      = []
      @auth_records = []
      @errors       = []
      @accruals     = []

      accounts.each do |account|
        opening_amount = Money.parse(account.opening, account.scale)
        post(account.id, :opening, opening_amount, 0, 0, "OPENING-#{account.id}") unless opening_amount.zero?
      end
    end

    def events
      @events.dup.freeze
    end

    def entries
      @entries.dup.freeze
    end

    def auth_records
      @auth_records.dup.freeze
    end

    def errors
      @errors.dup.freeze
    end

    def accruals
      @accruals.dup.freeze
    end

    def balance(account, as_of)
      @entries.sum { |e| e.account == account && e.value_date <= as_of ? e.amount : 0 }
    end

    def holds(account)
      open = {} # auth_id -> held amount
      @auth_records.each do |record|
        next unless record.account == account

        if record.status == :approved
          open[record.auth_id] = record.amount
        elsif record.status == :settled
          open.delete(record.auth_id)
        end
      end
      open.values.sum
    end

    def available(account, as_of)
      balance(account, as_of) - holds(account)
    end

    # Applies one event. A bad event never crashes the run: its error is recorded instead
    # and no money moves.
    def apply(event)
      @events << event.freeze

      begin
        account = @accounts[event.account]
        raise ArgumentError, "unknown account #{event.account}" if account.nil?

        case event.type
        when :credit, :debit
          post_cash(event, account)
        when :authorization
          authorize(event, account)
        when :settlement
          settle(event, account)
        when :reversal
          reverse(event, account)
        else
          raise ArgumentError, "unknown event type #{event.type}"
        end
      rescue ArgumentError => e
        @errors << ErrorRecord.new(day: event.day, event_id: event.id, message: e.message).freeze
      end
    end

    def close_day(day)
      @accounts.each_value do |account|
        (1..day).each do |value_date|
          next if fee_assessed?(account.id, value_date)
          next unless balance(account.id, value_date).negative?

          fee = OVERDRAFT_FEE[account.currency]
          if fee.nil?
            note_once(day, "FEE-#{account.id}-D#{value_date}", "no overdraft fee defined for #{account.currency}")
          else
            post(account.id, :fee, -fee, value_date, day, "FEE-#{account.id}-D#{value_date}")
          end
        end
      end
    end

    def capitalize_interest(through_day)
      raise "interest already capitalised" if @entries.any? { |e| e.kind == :interest }

      totals = {}
      @accounts.each_value do |account|
        rows = []
        (1..through_day).each do |day|
          closing = balance(account.id, day)
          amount = 0
          amount = Money.round_half_up(Rational(closing) * DAILY_RATE) if closing.positive?
          rows << Accrual.new(account: account.id, day: day, closing: closing, amount: amount).freeze
        end

        total = rows.sum(&:amount)
        @accruals.concat(rows)
        post(account.id, :interest, total, through_day, through_day, "INT-#{account.id}") if total.positive?
        totals[account.id] = total
      end
      totals
    end

    private

    def post(account, kind, amount, value_date, booked_day, event_id, ref = nil)
      entry = Entry.new(seq: @entries.size + 1, event_id: event_id, account: account, kind: kind,
                        amount: amount, value_date: value_date, booked_day: booked_day, ref: ref)
      @entries << entry.freeze
    end

    def record_auth(event, account, status, amount, note)
      record = AuthRecord.new(seq: @auth_records.size + 1, event_id: event.id, day: event.day,
                              account: account.id, auth_id: event.auth_id, status: status,
                              amount: amount, note: note)
      @auth_records << record.freeze
    end

    def fee_assessed?(account, value_date)
      @entries.any? { |e| e.kind == :fee && e.account == account && e.value_date == value_date }
    end

    # Records an error message only the first time it is seen.
    def note_once(day, event_id, message)
      return if @errors.any? { |e| e.event_id == event_id }

      @errors << ErrorRecord.new(day: day, event_id: event_id, message: message).freeze
    end

    def post_cash(event, account)
      total = Money.parse(event.amount, account.scale)
      raise ArgumentError, "#{event.id}: amount must be positive" unless total.positive?

      count = event.instalments || 1
      base = total / count

      parts = Array.new(count, base)
      parts[-1] += total - (base * count)

      sign = event.type == :debit ? -1 : 1
      parts.each_with_index do |part, index|
        label = count > 1 ? "#{index + 1}/#{count}" : nil
        post(account.id, event.type, sign * part, event.value_date, event.day, event.id, label)
      end
    end

    def authorize(event, account)
      already_used = @auth_records.any? do |r|
        r.auth_id == event.auth_id && (r.status == :approved || r.status == :declined)
      end
      raise ArgumentError, "#{event.id}: authorization #{event.auth_id} already exists" if already_used

      hold   = Money.parse(event.amount, account.scale)
      ledger = balance(account.id, event.value_date)
      after  = ledger - holds(account.id) - hold

      status = after >= 0 ? :approved : :declined
      note = "ledger #{Money.fmt(ledger, account.scale)}, available after hold #{Money.fmt(after, account.scale)}"
      record_auth(event, account, status, hold, note)
    end

    def settle(event, account)
      amount = Money.parse(event.amount, account.scale)

      auth = @auth_records.find do |r|
        r.auth_id == event.auth_id && r.account == account.id && r.status == :approved
      end
      already_settled = @auth_records.any? { |r| r.auth_id == event.auth_id && r.status == :settled }

      if auth.nil?
        reject_settlement(event, account, amount, "no approved authorization #{event.auth_id}")
      elsif already_settled
        reject_settlement(event, account, amount, "#{event.auth_id} already settled")
      elsif amount > auth.amount
        reject_settlement(event, account, amount, "settlement exceeds hold #{Money.fmt(auth.amount, account.scale)}")
      end

      post(account.id, :settlement, -amount, event.value_date, event.day, event.id, event.auth_id)
      note = "settled #{Money.fmt(amount, account.scale)}, hold #{Money.fmt(auth.amount, account.scale)} released"
      record_auth(event, account, :settled, amount, note)
    end

    def reject_settlement(event, account, amount, reason)
      record_auth(event, account, :settlement_rejected, amount, reason)
      raise ArgumentError, "#{event.id}: settlement rejected, #{reason}; no funds moved"
    end

    def reverse(event, account)
      reversible_kinds = [:credit, :debit]
      originals = @entries.select { |e| e.event_id == event.ref && reversible_kinds.include?(e.kind) }

      raise ArgumentError, "#{event.id}: no reversible event #{event.ref}" if originals.empty?

      unless originals.all? { |e| e.account == account.id }
        raise ArgumentError, "#{event.id}: #{event.ref} belongs to another account"
      end

      if @entries.any? { |e| e.kind == :reversal && e.ref == event.ref }
        raise ArgumentError, "#{event.id}: #{event.ref} already reversed"
      end

      unless originals.all? { |e| e.value_date == event.value_date }
        raise ArgumentError, "#{event.id}: value_date differs from #{event.ref}"
      end

      originals.each do |original|
        post(account.id, :reversal, -original.amount, original.value_date, event.day, event.id, event.ref)
      end
    end
  end
end
