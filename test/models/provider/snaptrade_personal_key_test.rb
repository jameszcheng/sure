require "test_helper"
require "ostruct"

# Personal API keys authenticate every data call with the key pair itself
# (HMAC-signed, same scheme as SnapTrade's official SDK): no registerUser,
# no userId/userSecret, no Bearer tokens.
class Provider::SnaptradePersonalKeyTest < ActiveSupport::TestCase
  PERSONAL_CLIENT_ID = "test-client-id"
  PERSONAL_CONSUMER_KEY = "test-consumer-key"
  FROZEN_TIMESTAMP = 1_720_000_000

  setup do
    @family = families(:dylan_family)
  end

  def personal_item(attrs = {})
    SnaptradeItem.new(
      {
        family: @family,
        name: "Personal",
        client_id: PERSONAL_CLIENT_ID,
        consumer_key: PERSONAL_CONSUMER_KEY
      }.merge(attrs)
    )
  end

  def faraday_response(status:, body:)
    OpenStruct.new(status: status, body: body, success?: (200..299).cover?(status))
  end

  def stub_time!
    Time.stubs(:now).returns(Time.at(FROZEN_TIMESTAMP))
  end

  # Independently recomputes the expected Signature for the canonical request
  # document. The implementation must produce byte-identical output or
  # SnapTrade rejects the call, so this pins the wire format (param order,
  # key sorting, hashing, encoding).
  def expected_signature(path:, params:, body: nil)
    query = Faraday::Utils.build_query(params)
    content = body.nil? ? nil : body.sort.to_h
    sig_content = JSON.generate({ "content" => content, "path" => path, "query" => query })
    Base64.strict_encode64(OpenSSL::HMAC.digest(OpenSSL::Digest::SHA256.new, PERSONAL_CONSUMER_KEY, sig_content)).strip
  end

  test "personal_key_mode? is true only with a key pair and no live oauth token" do
    assert Provider::Snaptrade.new(personal_item).personal_key_mode?

    oauth_live = personal_item(oauth_access_token: "at", oauth_token_expires_at: 1.hour.from_now)
    assert_not Provider::Snaptrade.new(oauth_live).personal_key_mode?,
      "a live OAuth token must keep using Bearer"

    oauth_expired = personal_item(oauth_access_token: "at", oauth_token_expires_at: 1.hour.ago)
    assert Provider::Snaptrade.new(oauth_expired).personal_key_mode?,
      "an expired token must fall back to the key pair instead of staying bricked"

    bare = SnaptradeItem.new(family: @family, name: "Bare")
    assert_not Provider::Snaptrade.new(bare).personal_key_mode?
  end

  test "personal mode GET sends signed query params and no bearer token" do
    stub_time!
    provider = Provider::Snaptrade.new(personal_item)
    request = OpenStruct.new(headers: {}, params: {})
    connection = mock("faraday")
    connection.expects(:get).with("https://api.snaptrade.com/api/v1/accounts").yields(request)
      .returns(faraday_response(status: 200, body: [ { "id" => "a1" } ].to_json))
    provider.stubs(:api_connection).returns(connection)

    assert_equal [ { "id" => "a1" } ], provider.list_accounts

    assert_nil request.headers["Authorization"], "personal keys must not send a Bearer token"
    assert_equal %w[clientId timestamp], request.params.keys,
      "clientId must precede timestamp exactly as SnapTrade's SDK orders them"
    assert_equal PERSONAL_CLIENT_ID, request.params["clientId"]
    assert_equal FROZEN_TIMESTAMP, request.params["timestamp"]
    assert_equal "application/json", request.headers["Accept"]
    assert_equal(
      expected_signature(
        path: "/api/v1/accounts",
        params: { "clientId" => PERSONAL_CLIENT_ID, "timestamp" => FROZEN_TIMESTAMP }
      ),
      request.headers["Signature"]
    )
  end

  test "personal mode POST signs the sorted body and is not retried" do
    stub_time!
    provider = Provider::Snaptrade.new(personal_item)
    request = OpenStruct.new(headers: {}, params: {})
    connection = mock("faraday")
    connection.expects(:post).with("https://api.snaptrade.com/api/v1/snapTrade/login").yields(request)
      .returns(faraday_response(status: 200, body: { "redirectURI" => "https://app.snaptrade.com/portal" }.to_json))
    provider.stubs(:api_connection).returns(connection)

    assert_equal(
      "https://app.snaptrade.com/portal",
      provider.get_connection_url(redirect_url: "https://sure.test/cb", broker: "Fidelity")
    )

    body = JSON.parse(request.body)
    assert_equal "https://sure.test/cb", body["customRedirect"]
    assert_equal "read", body["connectionType"]
    assert_equal "Fidelity", body["broker"]
    assert_equal(
      expected_signature(
        path: "/api/v1/snapTrade/login",
        params: { "clientId" => PERSONAL_CLIENT_ID, "timestamp" => FROZEN_TIMESTAMP },
        body: body
      ),
      request.headers["Signature"]
    )
  end

  test "personal mode 401 marks the item for update and raises without refreshing tokens" do
    item = @family.snaptrade_items.create!(
      name: "Personal", client_id: PERSONAL_CLIENT_ID, consumer_key: PERSONAL_CONSUMER_KEY
    )
    provider = Provider::Snaptrade.new(item)
    request = OpenStruct.new(headers: {}, params: {})
    connection = mock("faraday")
    connection.expects(:get).returns(faraday_response(status: 401, body: "unauthorized"))
    provider.stubs(:api_connection).returns(connection)
    Provider::Snaptrade.expects(:refresh_tokens).never

    error = assert_raises(Provider::Snaptrade::AuthenticationError) { provider.list_accounts }
    assert_match "401", error.message
    assert item.reload.requires_update?,
      "rejected personal keys must surface as requires_update, not silently keep the old snapshot"
  end

  test "incomplete key pair with no oauth token raises instead of sending unsigned calls" do
    provider = Provider::Snaptrade.new(personal_item(consumer_key: nil))
    assert_not provider.personal_key_mode?

    error = assert_raises(Provider::Snaptrade::AuthenticationError) { provider.list_accounts }
    assert_match "no access token", error.message
  end
end
