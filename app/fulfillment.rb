require_relative './fulfill_hcb'

module Quartermaster
  def self.fulfill!(source_order)
    begin
      source_order.transaction do
        order = EnrichedOrder.new(source_order)
        ref = case order.item['fulfillment_type']
              when "hcb_grant"; fulfill_hcb_grant(order)
              when "hq_mail", "third_party_physical", "third_party_virtual", "minuteman", "special", "agh", "agh_random_stickers"
                source_order.queue
              when "dummy"
                dummy_fulfill(source_order)
              else
                raise ArgumentError, "don't know how to fulfill a #{source_order['fulfillment_type']}!!"
              end
      end
    rescue StandardError => e
      source_order.mark_errored! e
    end
  end

  def dummy_fulfill(o)
    o.mark_fulfilled!(ref: ':3', quiet: true)
  end
  class EnrichedOrder
    attr_reader :recipient
    attr_reader :item
    attr_reader :order

    def initialize(order)
      @order = order
      @item = order.item
      @recipient = order.recipient
    end
    def self.from_id(id)
      new(ShopOrder.find id)
    end
  end
end