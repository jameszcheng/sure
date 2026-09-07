require "test_helper"

class Provider::SnaptradeAdapterTest < ActiveSupport::TestCase
  test "supports Investment and Crypto accounts" do
    assert_includes Provider::SnaptradeAdapter.supported_account_types, "Investment"
    assert_includes Provider::SnaptradeAdapter.supported_account_types, "Crypto"
  end

  test "build_provider returns nil when family is nil" do
    assert_nil Provider::SnaptradeAdapter.build_provider(family: nil)
  end

  test "build_provider does not require instance-level oauth app configuration" do
    # Personal-key deployments set no SNAPTRADE_OAUTH_* env at all; the item's
    # own credentials are sufficient. The global gate is gone on purpose.
    Provider::Snaptrade.stubs(:oauth_configured?).returns(false)
    family = families(:dylan_family)
    item = snaptrade_items(:configured_item)

    provider = Provider::SnaptradeAdapter.build_provider(family: family)

    assert_instance_of Provider::Snaptrade, provider
    assert_equal item, provider.snaptrade_item
  end

  test "build_provider returns nil when family has no configured snaptrade item" do
    assert_nil Provider::SnaptradeAdapter.build_provider(family: families(:empty))
  end

  test "build_provider returns a Provider::Snaptrade wrapping the authorized item" do
    family = families(:dylan_family)
    item = snaptrade_items(:configured_item)

    provider = Provider::SnaptradeAdapter.build_provider(family: family)

    assert_instance_of Provider::Snaptrade, provider
    assert_equal item, provider.snaptrade_item
  end

  test "build_provider serves a personal-key item with no oauth anywhere" do
    Provider::Snaptrade.stubs(:oauth_configured?).returns(false)
    snaptrade_items(:configured_item).update!(oauth_access_token: nil, oauth_refresh_token: nil)
    personal = families(:dylan_family).snaptrade_items.create!(
      name: "Personal", client_id: "test-client-id", consumer_key: "test-consumer-key"
    )

    provider = Provider::SnaptradeAdapter.build_provider(family: families(:dylan_family))

    assert_instance_of Provider::Snaptrade, provider
    assert_equal personal, provider.snaptrade_item
    assert provider.personal_key_mode?
  end
end
