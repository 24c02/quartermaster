require 'faraday'
require 'faraday/mashify'
require 'json'

class HCBError < StandardError; end

class RaiseHCBErrorMiddleware < Faraday::Middleware
  def on_complete(env)
    raise HCBError, "HCB returned #{env.response.body}" unless env.response.success?
  end
end

Faraday::Response.register_middleware hcb_error: RaiseHCBErrorMiddleware

class HCBAPI
  class << self
    def create_card_grant(email:, amount_cents:, allowed_merchants: nil, category_lock: nil)
      conn.post("organizations/#{@hcb_org_slug}/card_grants", email:, amount_cents:, category_lock:, merchant_lock: allowed_merchants).body
    end

    def topup_card_grant(hashid:, amount_cents:)
      conn.post("card_grants/#{hashid}/topup", amount_cents:).body
    end

    def rename_transaction(hashid:, new_memo:)
      resp = conn.put("organizations/#{@hcb_org_slug}/transactions/#{hashid}", memo: new_memo).body
    end

    def show_card_grant(hashid:)
      conn.get("card_grants/#{hashid}?expand=balance_cents,disbursements").body
    end

    def conn
      hcb_api_token = ENV['HCB_API_TOKEN']
      @hcb_base_url = ENV['HCB_BASE_URL']
      @hcb_org_slug = ENV['HCB_ORG_SLUG']

      raise 'missing HCB_BASE_URL >:-O' unless @hcb_base_url
      raise 'missing HCB_API_TOKEN >:-/' unless hcb_api_token
      raise 'missing HCB_ORG_SLUG >:-P' unless @hcb_org_slug

      @conn ||= Faraday.new url: "#{@hcb_base_url}/api/v4/".freeze do |faraday|
        faraday.request :json
        faraday.response :mashify
        faraday.response :json
        faraday.response :hcb_error
        faraday.headers["Authorization"] = "Bearer #{hcb_api_token}".freeze
      end
    end
  end
end


