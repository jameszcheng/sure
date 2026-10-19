require "test_helper"

# Payroll deposits that providers report as generic investment "Contribution"
# activities must import as income (kind: standard), not investment_contribution
# — IncomeStatement hard-classifies investment_contribution as an expense, so a
# paycheck landing directly in a brokerage would otherwise never count as income.
class Account::ProviderImportAdapterPayrollTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:investment)
    @family = @account.family
    @adapter = Account::ProviderImportAdapter.new(@account)
  end

  test "payroll contribution imports as standard income" do
    entry = @adapter.import_transaction(
      external_id: "payroll-dd-1",
      amount: -1205.08,
      currency: "USD",
      date: Date.today,
      name: "DIRECT DEPOSIT ACME CORP SPAYROLL (Cash Management)",
      source: "snaptrade",
      investment_activity_label: "Contribution",
      allow_heuristic_matching: false
    )

    transaction = entry.transaction
    assert_equal "standard", transaction.kind
    assert_equal @family.income_category, transaction.category
  end

  test "salary contribution imports as standard income" do
    entry = @adapter.import_transaction(
      external_id: "salary-dd-1",
      amount: -5000,
      currency: "USD",
      date: Date.today,
      name: "SALARY DEPOSIT",
      source: "snaptrade",
      investment_activity_label: "Contribution",
      allow_heuristic_matching: false
    )

    assert_equal "standard", entry.transaction.kind
  end

  test "non-payroll contribution keeps investment_contribution kind" do
    entry = @adapter.import_transaction(
      external_id: "p2p-dd-1",
      amount: -14000,
      currency: "USD",
      date: Date.today,
      name: "DIRECT DEPOSIT BANK OF AMERP2P JAMES CHE",
      source: "snaptrade",
      investment_activity_label: "Contribution",
      allow_heuristic_matching: false
    )

    transaction = entry.transaction
    assert_equal "investment_contribution", transaction.kind
    assert_equal @family.investment_contributions_category, transaction.category
  end
end
