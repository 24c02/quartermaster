require_relative 'parcel_pyxis'
module Quartermaster
  module AGH
    ALWAYS_INCLUDED_ITEMS = [
      {
        sku: "Sti/HS/Main/1st",
        quantity: 5
      },
      {
        sku: "Pri/HS/4x6/1st",
        quantity: 1
      }
    ]
    BONUS_INCLUDED_ITEMS = [
      # {
      #   sku: "Gra/Can/Jap/Ran",
      #   quantity: 1
      # }
    ]

    class << self
      def process_nightlies
        orders = ShopOrder.all :filter => "AND(OR({shop_item:fulfillment_type}='agh', {shop_item:fulfillment_type}='agh_random_stickers'), {status}='pending_nightly')"
        orders.group_by { |order| order["recipient"][0] }.each do |recipient, recipient_orders|
          puts "processing #{recipient_orders.length} for #{recipient_orders.first["recipient:full_name"]&.first}"
          recipient_orders.group_by { |order| order["addr_seq"] }.each do |addr_seq, addr_orders|
            begin
              first_order = addr_orders.first
              next if first_order['person:freeze']
              address = {
                first_name: first_order["addr_first_name"],
                last_name: first_order["addr_last_name"],
                line_1: first_order["addr_line1"],
                line_2: first_order["addr_line2"],
                city: first_order["addr_city"],
                state_province: first_order["addr_state_province"],
                zip: first_order["addr_postal_code"],
                country: first_order["addr_country"],
                phone: first_order["addr_phone"]
              }

              puts "\tat address #{address[:line_1]}:"
              item_names = []
              order_ids = []
              add_candy = false
              contents = [*ALWAYS_INCLUDED_ITEMS]
              contents += [["Sti/HS/Bun/Ar1"], ["Sti/HS/Bun/TB1"], %w[Sti/HS/Bun/TB1 Sti/HS/Bun/Ar1]].sample.map {|sku| { sku:, quantity: rand(1..2) }} if rand < 0.26
              begin
                person = Person.find(recipient)
                if person['add_to_next_agh_run']
                  contents += JSON.parse(person['add_to_next_agh_run'])
                  person['add_to_next_agh_run'] = nil
                  person.save
                end
              rescue NorairrecordError, JSON::ParserError => e
                puts "#{e.message} when loading next agh for #{recipient}"
              end
              addr_orders.each do |order|
                o = EnrichedOrder.new(order)
                add_candy = true unless o.item["no_candy"]
                contents += generate_contents(o) || []
                item_names << o.item["name"]
                order_ids << "Shop order #{o.order.id}"
              end
              contents += BONUS_INCLUDED_ITEMS if add_candy
              contents.each do |content|
                puts "\t\t#{content[:quantity]}x #{content[:sku]}"
              end
              puts first_order["recipient:email"]
              zenv_order = ParcelPyxisAPI.create_shipreq(
                user_facing_title: "High Seas – #{item_names.join(', ')}",
                email: first_order["recipient:email"][0],
                address:,
                request_type: "High Seas",
                ref: "QM: #{order_ids.join(', ')}",
                contents:,
                send_for_real: true
              )
              puts "\t\t#{zenv_order}"
              addr_orders.each {|order| order.mark_fulfilled!(ref: zenv_order["id"], slack_ref: "<#{zenv_order["url"]}|MSR #{zenv_order["id"]}>")}
            rescue StandardError => e
              addr_orders.each {|order| order.mark_errored!(e)}
            end
          end
        end
        return
      end

      def generate_contents(o)
        item_skus = JSON.parse(o.item["agh_skus"])
        case o.item["fulfillment_type"]
        when "agh"
          item_skus.map { |sku| { sku:, quantity: o.order["quantity"] } }

        when "agh_random_stickers"
          item_skus.shuffle.cycle.take(o.item["agh_random_sticker_count"] * o.order["quantity"]).map { |sku| { sku:, quantity: 1 } }
        end
      end
    end
  end
end