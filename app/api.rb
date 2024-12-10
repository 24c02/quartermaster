require 'grape'
require 'aasm'
require_relative './models'
require_relative './yap'
require_relative './validate'
require_relative './fulfillment'
require_relative './hcb_api'
require_relative './agh'

Norairrecord.user_agent = "quartermaster (ping nora!)"

module Quartermaster
  class API < Grape::API
    include Quartermaster
    format :json

    helpers do
      def order
        @order ||= ShopOrder.find(params[:id])
        error!('wrong env, ignoring', 200) unless !!@order["dev"] == (ENV["ENV"] == "DEV")
        @order
      rescue Norairrecord::Error => e
        p e
        error!({ error: "order #{params[:id]} not found :-/" }, 404)
      end
      def authcronticate!
        error!("nope!", 401) unless headers["authorization"] == ENV["CRON_SECRET"]
      end
      def airthenticate!
        error!("nope!", 401) unless headers["authorization"] == ENV["AIRTABLE_SECRET"]
      end
    end
    namespace :d do
      namespace :crons do
        before { authcronticate! }
        get :agh_nightlies do
          AGH.process_nightlies
        end
      end
      resource :order do
        before { airthenticate! }
        params do
          requires :id, type: String
        end
        route_param :id do
          get do
            order['status']
          end
          post '/validate' do
            error!({ error: "can't validate an order that isn't fresh!" }, 418) unless order.may_validate?
            Quartermaster.validate! order
          end
          post '/fulfill' do
            error!({ error: "can't fulfill an order that isn't in flight!" }, 418) unless order.may_mark_fulfilled?
            Quartermaster.fulfill! order
          end
        end
      end
      rescue_from AASM::InvalidTransition do |e|
        error!({ error: "can't #{e.event_name} an order that's #{e.originating_state}!" }, 400)
      end
    end
  end
end
