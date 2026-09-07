require "test_helper"

class SnaptradeItemTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @family = families(:dylan_family)
  end

  def personal_key_item
    @personal_key_item ||= @family.snaptrade_items.create!(
      name: "Personal", client_id: "test-client-id", consumer_key: "test-consumer-key"
    )
  end

  test "validates presence of name" do
    item = SnaptradeItem.new(family: @family)
    assert_not item.valid?
    assert_includes item.errors[:name], "can't be blank"
  end

  test "allows oauth-only items without api credentials" do
    item = SnaptradeItem.new(family: @family, name: "Test")
    assert item.valid?
  end

  test "snaptrade_provider returns nil when oauth token not present" do
    item = SnaptradeItem.new(family: @family, name: "Test")
    assert_nil item.snaptrade_provider
  end

  test "snaptrade_provider returns provider instance when oauth token present" do
    item = SnaptradeItem.new(
      family: @family,
      name: "Test",
      oauth_access_token: "test-access-token"
    )
    provider = item.snaptrade_provider
    assert_instance_of Provider::Snaptrade, provider
  end

  test "credentials_configured? mirrors oauth_configured?" do
    item = SnaptradeItem.new(family: @family, name: "Test")
    assert_equal item.oauth_configured?, item.credentials_configured?
    assert_not item.credentials_configured?

    item.oauth_access_token = "test-access-token"
    assert_equal item.oauth_configured?, item.credentials_configured?
    assert item.credentials_configured?
  end

  test "personal_key_configured? needs both halves of the key pair" do
    assert personal_key_item.personal_key_configured?
    assert_not SnaptradeItem.new(family: @family, name: "Test", client_id: "cid").personal_key_configured?
    assert_not SnaptradeItem.new(family: @family, name: "Test").personal_key_configured?
  end

  test "credentials_configured? accepts a personal key pair without oauth tokens" do
    assert personal_key_item.credentials_configured?
    assert personal_key_item.fully_configured?
    assert_instance_of Provider::Snaptrade, personal_key_item.snaptrade_provider
  end

  test "syncable scope includes personal-key items" do
    assert_includes SnaptradeItem.syncable, personal_key_item
  end

  test "an unlinked account awaiting activities does not keep the item syncing" do
    item = snaptrade_items(:configured_item)
    account = snaptrade_accounts(:fidelity_401k)
    account.update!(activities_fetch_pending: true)

    assert_nil account.current_account
    assert_not item.syncing?
  end

  test "sync_later_with_follow_up queues a follow-up after an active sync" do
    item = snaptrade_items(:configured_item)
    active_sync = item.syncs.create!
    active_sync.start!

    assert_enqueued_with job: SnaptradeFollowUpSyncJob do
      item.sync_later_with_follow_up
    end
  end
end
