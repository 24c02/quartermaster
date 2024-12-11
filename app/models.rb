require 'norairrecord'
require 'aircts_as_state_machine'

Norairrecord.api_key = ENV["AIRTABLE_PAT"]

module Quartermaster
  class ShopItem < Norairrecord::Table
    self.base_key = "appTeNFYcUiYfGcR6"
    self.table_name = 'tblGChU9vC3QvswAV' # 'shop_items'

    has_many :orders, class: "ShopOrder", column: "orders"
  end

  class ShopOrder < AirctsAsStateMachine
    include AASM

    self.base_key = "appTeNFYcUiYfGcR6"
    self.table_name = 'tbl7Dj23N5tjLanM4' # 'shop_orders'

    belongs_to :recipient, class: "Quartermaster::Person", column: "recipient"
    has_one :item, class: "Quartermaster::ShopItem", column: "shop_item"
    has_one :cdg, class: "Quartermaster::ShopCardGrant", column: "card_grant_rec"

    aasm column: 'status' do
      state :draft
      state :fresh
      state :in_flight
      state :fulfilled
      state :REJECTED
      state :pending_nightly
      state :error_fulfilling
      state :PENDING_MANUAL_REVIEW
      state :AWAITING_YSWS_VERIFICATION
      state :refunded

      event :validate do
        transitions from: :fresh, to: :in_flight
      end

      event :mark_in_flight do
        transitions from: :fresh, to: :in_flight
        before do
          Yap.post_to_noise "#{pretty_name} is good, now in flight!"
        end
      end

      event :send_for_review do
        transitions from: :fresh, to: :PENDING_MANUAL_REVIEW
        before do
          Yap.post_to_ops "#{%w[hey hai haii what\ up what's\ up yo ahoy! avast!].sample} <!subteam^S07PYE7FXPT>, #{pretty_name} is waiting for you! set it to in_flight if it's good to go :3"
        end
      end

      event :mark_fulfilled do
        transitions from: [:pending_nightly, :in_flight], to: :fulfilled
        before do |params|
          raise ArgumentError("needs a ref!") unless params[:ref]
          self['external_ref'] = params[:ref]
          params[:slack_ref] ||= params[:ref]
          Yap.post_to_ops params[:custom_message] || "#{pretty_name} was automatically fulfilled! (ref: #{params[:slack_ref]})" unless params[:quiet]
        end
      end

      event :queue do
        transitions from: :in_flight, to: :pending_nightly
        before do
          Yap.post_to_noise "queueing #{pretty_name} for periodical #{self['shop_item:fulfillment_type'][0]} run..."
        end
      end

      event :reject do
        transitions to: :REJECTED
        before do |reason|
          self['rejection_reason'] = reason
          Yap.post_to_ops "#{pretty_name} was rejected!\n (reason: #{reason})"
        end
      end

      event :mark_errored do
        transitions to: :error_fulfilling
        before do |error|
          self['error'] = error.message
          Yap.post_to_ops "<@U06QK6AG3RD>: error fulfilling #{slack_url}!\n error was #{error.message} in #{error.backtrace[..2]}"
        end
      end

      event :pend_verification do
        transitions from: :fresh, to: :AWAITING_YSWS_VERIFICATION
        before do
          Yap.post_to_noise "#{pretty_name} awaits YSWS verification..."
        end
      end
    end


    def initialize(*one, **two)
      super
      if self['status']
        self.aasm.current_state = self['status'].to_sym
      end
    end

    def pretty_name
      "#{self['recipient:full_name'][0]}'s #{slack_url} for #{self['shop_item:name'][0]}"
    end
  end
  class Person < Norairrecord::Table
    self.base_key = "appTeNFYcUiYfGcR6"
    self.table_name = 'tblfTzYVqvDJlIYUB' # 'people'

    has_one :address, class: 'Quartermaster::ShopAddress', column: 'address'

    def invalidate_otp!
      self['shop_otp'] = self['shop_otp_expires_at'] = nil
      self.save
    end

    def nice_full_name
      "#{self["first_name"]} #{self["last_name"]}"
    end
  end

  class ShopAddress < Norairrecord::Table
    self.base_key = "appTeNFYcUiYfGcR6"
    self.table_name = 'tblYxntrYxcTewLJW' # 'shop_addresses'
  end

  class ShopCardGrant < Norairrecord::Table
    self.base_key = "appTeNFYcUiYfGcR6"
    self.table_name = "tblitljiz4cxhF5tr"

    def self.lookup_or_create(person, shop_item)
      records(filter: "{identifier}='cdg_#{person.id}_#{shop_item['identifier']}'", max_records: 1).first || self.new(
        "recipient" => [person.id],
        "shop_item" => [shop_item.id]
      )
    end
  end
end

module Norairrecord
  # ∑:3
  class Table
    # url to view model on airtable
    def airtable_url
      "https://airtable.com/#{self.class.base_key}/#{self.class.table_name}/#{self.id}"
    end
    # clickable slack link to model
    def slack_url
      "<#{self.airtable_url}|#{self.friendly_name} #{self.id}>"
    end
    def to_s
      # for compatibility with karkalicious ids
      "<#{self.friendly_name} id='#{self.id}'>"
    end
    def friendly_name
      self.class.name&.split('::')&.last
    end
  end
end