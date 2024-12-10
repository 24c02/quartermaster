require 'faraday'
require 'faraday/mashify'
require 'json'

class ParcelPyxisError < StandardError; end

class RaiseParcelPyxisErrorMiddleware < Faraday::Middleware
  def on_complete(env)
    raise ParcelPyxisError, "parcel-pyxis returned #{env.response.body}" unless env.response.success?
  end
end

Faraday::Response.register_middleware pp_error: RaiseParcelPyxisErrorMiddleware

class ParcelPyxisAPI
  class << self
    def create_shipreq(body)
      conn.post("warehouse/msr", body).body
    end

    def conn
      parcel_pyxis_token = ENV['PARCEL_PYXIS_TOKEN']

      raise 'missing PARCEL_PYXIS_TOKEN >:-/' unless parcel_pyxis_token

      @conn ||= Faraday.new url: ENV["PARCEL_PYXIS_BASE_URL"].freeze do |faraday|
        faraday.request :json
        faraday.response :pp_error
        faraday.response :json
        faraday.headers["Authorization"] = parcel_pyxis_token
      end
    end
  end
end
